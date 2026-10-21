import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// One global clearance layer for every app-managed request this browser tab
/// sends to Wikimedia. It prevents independent features (search, previews, metadata,
/// and bulk downloads) from creating overlapping request bursts.
///
/// Wikimedia currently recommends no more than three concurrent requests.
/// Commons Lens deliberately stays below that at two, spaces request starts,
/// identifies Action API traffic, respects Retry-After, and applies a global
/// cooldown so newly queued work cannot ignore a throttle response received
/// by another feature.
class WikimediaRequestGate {
  WikimediaRequestGate._();

  static const int maxConcurrent = 2;
  static const Duration minimumStartSpacing = Duration(milliseconds: 400);
  static const String apiUserAgent =
      'CommonsLens/1.0 (https://github.com/commonslens/commonslens.github.io; Flutter Web)';

  static final Queue<Completer<void>> _queue = Queue<Completer<void>>();
  static final Map<String, Future<http.Response>> _inFlightApiGets = {};
  static final Random _random = Random();

  static int _active = 0;
  static DateTime _nextStart = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static Timer? _pumpTimer;

  static bool _isActionApi(Uri uri) {
    final host = uri.host.toLowerCase();
    final isWikimediaHost = host == 'wikimedia.org' ||
        host.endsWith('.wikimedia.org') ||
        host == 'wikidata.org' ||
        host.endsWith('.wikidata.org') ||
        host == 'wikipedia.org' ||
        host.endsWith('.wikipedia.org');
    return isWikimediaHost && uri.path.endsWith('/w/api.php');
  }

  static Uri _preparedUri(Uri uri) {
    if (!_isActionApi(uri) || uri.queryParameters.containsKey('maxlag')) {
      return uri;
    }
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'maxlag': '5',
    });
  }

  static Map<String, String>? _preparedHeaders(
    Uri uri,
    Map<String, String>? headers,
  ) {
    if (!_isActionApi(uri)) return headers;
    return {
      ...?headers,
      'Api-User-Agent': apiUserAgent,
    };
  }

  static Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  }) {
    final preparedUri = _preparedUri(uri);
    final isApi = _isActionApi(preparedUri);
    final key = preparedUri.toString();

    if (deduplicate && isApi) {
      final existing = _inFlightApiGets[key];
      if (existing != null) return existing;
    }

    final future = _getWithClearance(
      client,
      preparedUri,
      headers: _preparedHeaders(preparedUri, headers),
      timeout: timeout,
      maxAttempts: maxAttempts,
      cancelled: cancelled,
      acceptResponse: acceptResponse,
    );

    if (deduplicate && isApi) {
      _inFlightApiGets[key] = future;
      future.then<void>(
        (_) {
          if (identical(_inFlightApiGets[key], future)) {
            _inFlightApiGets.remove(key);
          }
        },
        onError: (Object _, StackTrace __) {
          if (identical(_inFlightApiGets[key], future)) {
            _inFlightApiGets.remove(key);
          }
        },
      );
    }
    return future;
  }

  static Future<http.Response> _getWithClearance(
    http.Client client,
    Uri uri, {
    required Map<String, String>? headers,
    required Duration timeout,
    required int maxAttempts,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  }) async {
    Object? lastError;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (cancelled?.call() == true) {
        throw http.ClientException('Request cancelled', uri);
      }

      await _acquire();
      if (cancelled?.call() == true) {
        _release();
        throw http.ClientException('Request cancelled', uri);
      }

      http.Response? response;
      try {
        response = await client.get(uri, headers: headers).timeout(timeout);
      } catch (error) {
        lastError = error;
      } finally {
        _release();
      }

      if (response != null) {
        final throttled = _isThrottleResponse(
          response,
          isActionApi: _isActionApi(uri),
        );
        final rejectedBody = response.statusCode == 200 &&
            acceptResponse != null &&
            !acceptResponse(response);
        final transient = throttled ||
            rejectedBody ||
            response.statusCode >= 500 ||
            response.statusCode == 408;
        if (!transient || attempt == maxAttempts) return response;

        final delay = _retryDelay(response, attempt, throttled: throttled);
        if (throttled) _extendGlobalCooldown(delay);
        await _wait(delay, cancelled);
        continue;
      }

      if (attempt < maxAttempts) {
        await _wait(_networkBackoff(attempt), cancelled);
      }
    }

    if (lastError != null) throw lastError;
    throw http.ClientException('Wikimedia request failed', uri);
  }

  static bool _isThrottleResponse(
    http.Response response, {
    required bool isActionApi,
  }) {
    if (response.statusCode == 429 || response.statusCode == 503) return true;
    if (!isActionApi || response.statusCode != 200) return false;
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('json') && !response.body.startsWith('{')) {
      return false;
    }
    try {
      final data = jsonDecode(response.body);
      return data is Map &&
          data['error'] is Map &&
          const {'maxlag', 'ratelimited'}
              .contains((data['error'] as Map)['code']?.toString());
    } catch (_) {
      return false;
    }
  }

  static Duration _retryDelay(
    http.Response response,
    int attempt, {
    required bool throttled,
  }) {
    final retryAfter = int.tryParse(
      (response.headers['retry-after'] ?? '').trim(),
    );
    if (retryAfter != null && retryAfter >= 0) {
      return Duration(seconds: retryAfter) + _jitter();
    }
    if (throttled) {
      // Wikimedia asks clients to wait at least five seconds when a 429/503
      // response does not expose Retry-After.
      return Duration(seconds: max(5, 1 << (attempt - 1))) + _jitter();
    }
    return Duration(seconds: 1 << (attempt - 1)) + _jitter();
  }

  static Duration _networkBackoff(int attempt) =>
      Duration(seconds: 1 << (attempt - 1)) + _jitter();

  static Duration _jitter() => Duration(milliseconds: _random.nextInt(301));

  static Future<void> _wait(
    Duration duration,
    bool Function()? cancelled,
  ) async {
    var remaining = duration;
    const slice = Duration(milliseconds: 250);
    while (remaining > Duration.zero) {
      if (cancelled?.call() == true) {
        throw const _GateCancelled();
      }
      final wait = remaining < slice ? remaining : slice;
      await Future.delayed(wait);
      remaining -= wait;
    }
  }

  static void _extendGlobalCooldown(Duration duration) {
    final until = DateTime.now().add(duration);
    if (until.isAfter(_blockedUntil)) _blockedUntil = until;
    _pump();
  }

  static Future<void> _acquire() {
    final completer = Completer<void>();
    _queue.add(completer);
    _pump();
    return completer.future;
  }

  static void _release() {
    if (_active > 0) _active--;
    _pump();
  }

  static void _pump() {
    _pumpTimer?.cancel();
    _pumpTimer = null;
    if (_queue.isEmpty || _active >= maxConcurrent) return;

    final now = DateTime.now();
    final allowedAt =
        _nextStart.isAfter(_blockedUntil) ? _nextStart : _blockedUntil;
    if (allowedAt.isAfter(now)) {
      _pumpTimer = Timer(allowedAt.difference(now), _pump);
      return;
    }

    final next = _queue.removeFirst();
    _active++;
    _nextStart = now.add(minimumStartSpacing);
    next.complete();

    if (_queue.isNotEmpty && _active < maxConcurrent) {
      _pumpTimer = Timer(minimumStartSpacing, _pump);
    }
  }
}

class _GateCancelled implements Exception {
  const _GateCancelled();
}
