import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'download_security.dart';
import 'wikimedia_request_gate.dart';
import 'wikimedia_transport.dart';

class DownloadPayload {
  final Uint8List bytes;
  final String contentType;
  final String extension;
  final String detectedType;
  final DownloadRiskLevel riskLevel;
  final List<String> verificationChecks;
  final String sha1;
  final String expectedMime;
  final String expectedSha1;
  final int? expectedLength;
  final String verifiedUrl;

  const DownloadPayload({
    required this.bytes,
    required this.contentType,
    required this.extension,
    this.detectedType = '',
    this.riskLevel = DownloadRiskLevel.passive,
    this.verificationChecks = const [],
    this.sha1 = '',
    this.expectedMime = '',
    this.expectedSha1 = '',
    this.expectedLength,
    this.verifiedUrl = '',
  });
}

/// Current Wikimedia imageinfo values used to bind a download to the file
/// metadata fetched immediately before the byte request.
class CurrentMediaMetadata {
  final String url;
  final String mime;
  final String sha1;
  final int? length;

  const CurrentMediaMetadata({
    required this.url,
    required this.mime,
    required this.sha1,
    required this.length,
  });
}

/// Headless media-download backend.
///
/// It owns thumbnail URL resolution, media fetching, response validation,
/// bounded streaming, and cancellation. Browser/native presentation layers
/// only decide how to save the returned bytes.
class WikimediaDownloadClient {
  WikimediaDownloadClient({WikimediaTransport? transport})
      : _transport = transport ?? GatedWikimediaTransport(),
        _ownsTransport = transport == null;

  static const int maxConcurrent = WikimediaRequestGate.maxConcurrent;

  final WikimediaTransport _transport;
  final bool _ownsTransport;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<String?> fetchScaledUrl(
    String title,
    int maxWidth, {
    bool Function()? cancelled,
  }) async {
    if (_closed || title.trim().isEmpty || maxWidth <= 0) return null;
    try {
      final normalizedTitle = title.startsWith('File:') ? title : 'File:$title';
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': normalizedTitle,
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '$maxWidth',
      });
      final response = await _transport.get(
        uri,
        timeout: const Duration(seconds: 15),
        cancelled: () => _closed || (cancelled?.call() ?? false),
      );
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final query = decoded['query'];
      if (query is! Map) return null;
      final pages = query['pages'];
      if (pages is! Map) return null;

      for (final page in pages.values) {
        if (page is! Map) continue;
        final imageInfo = page['imageinfo'];
        if (imageInfo is! List || imageInfo.isEmpty) continue;
        final first = imageInfo.first;
        if (first is! Map) continue;
        final thumbnail = first['thumburl'];
        if (thumbnail is String && thumbnail.isNotEmpty) {
          final uri = DownloadSecurityPolicy.requireTrustedMediaUri(thumbnail);
          DownloadSecurityPolicy.requireSafeDownloadExtension(uri);
          return uri.toString();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches fresh, provider-supplied metadata for a file title. This is used
  /// immediately before original-file downloads so a long-lived queue does
  /// not rely only on stale metadata captured when the item was selected.
  Future<CurrentMediaMetadata?> fetchCurrentMediaMetadata(
    String title, {
    bool Function()? cancelled,
  }) async {
    if (_closed || title.trim().isEmpty) return null;
    try {
      final normalizedTitle = title.startsWith('File:') ? title : 'File:$title';
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'formatversion': '2',
        'origin': '*',
        'maxage': '0',
        'smaxage': '0',
        'titles': normalizedTitle,
        'prop': 'imageinfo',
        'iiprop': 'url|size|sha1|mime',
      });
      final response = await _transport.get(
        uri,
        timeout: const Duration(seconds: 15),
        cancelled: () => _closed || (cancelled?.call() ?? false),
      );
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final pages =
          decoded['query'] is Map ? (decoded['query'] as Map)['pages'] : null;
      if (pages is! List || pages.isEmpty || pages.first is! Map) return null;
      final page = pages.first as Map;
      final imageInfo = page['imageinfo'];
      if (imageInfo is! List || imageInfo.isEmpty || imageInfo.first is! Map) {
        return null;
      }
      final info = imageInfo.first as Map;
      final rawUrl = info['url'];
      if (rawUrl is! String || rawUrl.isEmpty) return null;
      final trustedUrl = DownloadSecurityPolicy.requireTrustedMediaUri(rawUrl);
      final rawSize = info['size'];
      final size = rawSize is num
          ? rawSize.toInt()
          : int.tryParse(rawSize?.toString() ?? '');
      return CurrentMediaMetadata(
        url: trustedUrl.toString(),
        mime: info['mime']?.toString() ?? '',
        sha1: info['sha1']?.toString() ?? '',
        length: size,
      );
    } on DownloadSecurityException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<DownloadPayload?> fetchMedia(
    String url, {
    bool Function()? cancelled,
    Duration timeout = const Duration(seconds: 45),
    String? expectedMime,
    String? expectedSha1,
    int? expectedLength,
    int maxBytes = DownloadSecurityPolicy.maxFileBytes,
    bool allowComplex = false,
    String? revalidateTitle,
  }) async {
    if (_closed) return null;
    try {
      var requestedUrl = url;
      var effectiveMime = expectedMime;
      var effectiveSha1 = expectedSha1;
      var effectiveLength = expectedLength;
      var fetchedFreshMetadata = false;

      if (revalidateTitle != null && revalidateTitle.trim().isNotEmpty) {
        final current = await fetchCurrentMediaMetadata(
          revalidateTitle,
          cancelled: cancelled,
        );
        if (current == null) {
          throw const DownloadSecurityException(
            'metadata_unavailable',
            'Download blocked: current Wikimedia file metadata could not be revalidated.',
          );
        }
        requestedUrl = current.url;
        effectiveMime = current.mime;
        effectiveSha1 = current.sha1;
        effectiveLength = current.length;
        fetchedFreshMetadata = true;
      }

      final requestedUri = DownloadSecurityPolicy.requireTrustedMediaUri(
        requestedUrl,
      );
      final requestedExtension = allowComplex
          ? DownloadSecurityPolicy.requireArchiveDownloadExtension(requestedUri)
          : DownloadSecurityPolicy.requireSafeDownloadExtension(requestedUri);
      if (effectiveLength != null && effectiveLength > maxBytes) {
        throw DownloadSecurityException(
          'file_too_large',
          'Download blocked: the file exceeds the '
              '${maxBytes ~/ (1024 * 1024)} MiB safety limit.',
        );
      }
      final mediaTransport = _transport;
      if (mediaTransport is! WikimediaMediaTransport) {
        throw const DownloadSecurityException(
          'streaming_transport_required',
          'Download blocked: the media transport does not support bounded streaming.',
        );
      }
      final response = await mediaTransport.getStream(
        requestedUri,
        timeout: timeout,
        cancelled: () => _closed || (cancelled?.call() ?? false),
      );

      final finalUri = response.request?.url ?? requestedUri;
      late final String finalExtension;
      try {
        DownloadSecurityPolicy.requireTrustedMediaUri(finalUri.toString());
        finalExtension = allowComplex
            ? DownloadSecurityPolicy.requireArchiveDownloadExtension(finalUri)
            : DownloadSecurityPolicy.requireSafeDownloadExtension(finalUri);
      } on Object {
        await _cancelStream(response.stream);
        rethrow;
      }
      if (finalExtension != requestedExtension) {
        await _cancelStream(response.stream);
        throw const DownloadSecurityException(
          'redirect_type_change',
          'Download blocked: a redirect changed the expected file type.',
        );
      }

      if (response.statusCode != 200) {
        await _cancelStream(response.stream);
        return null;
      }

      final contentType =
          (response.headers['content-type'] ?? '').toLowerCase();
      final contentEncoding =
          (response.headers['content-encoding'] ?? '').toLowerCase();
      if (contentType.contains('text/html') ||
          contentType.contains('application/json') ||
          (contentEncoding.isNotEmpty && contentEncoding != 'identity')) {
        await _cancelStream(response.stream);
        return null;
      }

      final headerLength = int.tryParse(
        response.headers['content-length'] ?? '',
      );
      final streamLength = response.contentLength;
      final declaredLength = headerLength ??
          (streamLength != null && streamLength >= 0 ? streamLength : null);
      if (declaredLength != null && declaredLength > maxBytes) {
        await _cancelStream(response.stream);
        throw DownloadSecurityException(
          'file_too_large',
          'Download blocked: the file exceeds the '
              '${maxBytes ~/ (1024 * 1024)} MiB safety limit.',
        );
      }

      final bytes = await _readBoundedBody(
        response.stream,
        maxBytes: maxBytes,
        timeout: timeout,
        cancelled: () => _closed || (cancelled?.call() ?? false),
      );
      if (declaredLength != null && declaredLength != bytes.length) {
        throw const DownloadSecurityException(
          'length_mismatch',
          'Download blocked: the received byte count does not match the HTTP response.',
        );
      }

      final verified = await DownloadSecurityPolicy.verifyMediaCooperatively(
        bytes: bytes,
        declaredContentType: contentType,
        expectedExtension: finalExtension,
        expectedMime: effectiveMime,
        expectedSha1: effectiveSha1,
        expectedLength: effectiveLength,
        maxBytes: maxBytes,
        allowComplex: allowComplex,
        cancelled: () => _closed || (cancelled?.call() ?? false),
      );
      final verificationChecks = [
        ...verified.checks,
        if (fetchedFreshMetadata)
          'fresh Wikimedia imageinfo metadata was fetched immediately before download',
      ];
      return DownloadPayload(
        bytes: bytes,
        contentType: verified.contentType,
        extension: verified.extension,
        detectedType: verified.detectedType,
        riskLevel: verified.riskLevel,
        verificationChecks: verificationChecks,
        sha1: verified.sha1,
        expectedMime: effectiveMime ?? '',
        expectedSha1: effectiveSha1 ?? '',
        expectedLength: effectiveLength,
        verifiedUrl: requestedUri.toString(),
      );
    } on DownloadSecurityException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _readBoundedBody(
    Stream<List<int>> stream, {
    required int maxBytes,
    required Duration timeout,
    required bool Function() cancelled,
  }) async {
    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in stream.timeout(timeout)) {
      if (cancelled()) {
        throw const DownloadSecurityException(
          'cancelled',
          'Download cancelled before verification completed.',
        );
      }
      total += chunk.length;
      if (total > maxBytes) {
        throw DownloadSecurityException(
          'file_too_large',
          'Download blocked: the file exceeds the '
              '${maxBytes ~/ (1024 * 1024)} MiB safety limit.',
        );
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _cancelStream(Stream<List<int>> stream) async {
    final subscription = stream.listen((_) {});
    await subscription.cancel();
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsTransport && _transport is GatedWikimediaTransport) {
      _transport.close();
    }
  }
}
