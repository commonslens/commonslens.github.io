import 'package:http/http.dart' as http;

import 'wikimedia_request_gate.dart';

/// Injectable read-only HTTP boundary used by the Commons backend.
///
/// Production uses [GatedWikimediaTransport]. Tests and embedders can provide
/// an implementation backed by fixtures without changing search logic.
abstract interface class WikimediaTransport {
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  });
}

/// Streaming transport required by the media-download boundary.
///
/// Search and metadata operations can use a buffered [WikimediaTransport]
/// response. Media downloads must use this interface so the caller can stop
/// reading as soon as the hard byte limit is reached.
abstract interface class WikimediaMediaTransport implements WikimediaTransport {
  Future<http.StreamedResponse> getStream(
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
    bool Function()? cancelled,
  });
}

/// Production transport that applies the global Wikimedia concurrency,
/// identification, maxlag, deduplication, and retry policy.
class GatedWikimediaTransport implements WikimediaMediaTransport {
  GatedWikimediaTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  }) {
    return WikimediaRequestGate.get(
      _client,
      uri,
      headers: headers,
      timeout: timeout,
      maxAttempts: maxAttempts,
      deduplicate: deduplicate,
      cancelled: cancelled,
      acceptResponse: acceptResponse,
    );
  }

  @override
  Future<http.StreamedResponse> getStream(
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
    bool Function()? cancelled,
  }) {
    return WikimediaRequestGate.getStream(
      _client,
      uri,
      timeout: timeout,
      cancelled: cancelled,
    );
  }

  /// Closes only clients created by this transport. Injected clients remain
  /// owned by their caller.
  void close() {
    if (_ownsClient) _client.close();
  }
}
