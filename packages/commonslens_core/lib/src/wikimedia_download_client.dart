import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'download_security.dart';
import 'wikimedia_request_gate.dart';
import 'wikimedia_transport.dart';

class DownloadPayload {
  final Uint8List bytes;
  final String contentType;
  final String extension;

  const DownloadPayload({
    required this.bytes,
    required this.contentType,
    required this.extension,
  });
}

/// Headless media-download backend.
///
/// It owns thumbnail URL resolution, media fetching, response validation,
/// retries, and cancellation. Browser/native presentation layers only decide
/// how to save the returned bytes.
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

  Future<DownloadPayload?> fetchMedia(
    String url, {
    bool Function()? cancelled,
    int maxAttempts = 4,
    Duration timeout = const Duration(seconds: 45),
    String? expectedMime,
    String? expectedSha1,
    int? expectedLength,
    int maxBytes = DownloadSecurityPolicy.maxFileBytes,
  }) async {
    if (_closed) return null;
    try {
      final requestedUri = DownloadSecurityPolicy.requireTrustedMediaUri(url);
      final requestedExtension =
          DownloadSecurityPolicy.requireSafeDownloadExtension(requestedUri);
      if (expectedLength != null && expectedLength > maxBytes) {
        throw DownloadSecurityException(
          'file_too_large',
          'Download blocked: the file exceeds the '
              '${maxBytes ~/ (1024 * 1024)} MiB safety limit.',
        );
      }
      final response = await _transport.get(
        requestedUri,
        timeout: timeout,
        maxAttempts: maxAttempts,
        deduplicate: false,
        cancelled: () => _closed || (cancelled?.call() ?? false),
        acceptResponse: (response) => _isUsableMediaResponse(
          response,
          maxBytes: maxBytes,
        ),
      );
      if (!_isUsableMediaResponse(response, maxBytes: maxBytes)) return null;

      final finalUri = response.request?.url ?? requestedUri;
      DownloadSecurityPolicy.requireTrustedMediaUri(finalUri.toString());
      final finalExtension =
          DownloadSecurityPolicy.requireSafeDownloadExtension(finalUri);
      if (finalExtension != requestedExtension) {
        throw const DownloadSecurityException(
          'redirect_type_change',
          'Download blocked: a redirect changed the expected file type.',
        );
      }

      final verified = DownloadSecurityPolicy.verifyMedia(
        bytes: response.bodyBytes,
        declaredContentType: response.headers['content-type'] ?? '',
        expectedExtension: finalExtension,
        expectedMime: expectedMime,
        expectedSha1: expectedSha1,
        expectedLength: expectedLength,
        maxBytes: maxBytes,
      );
      return DownloadPayload(
        bytes: response.bodyBytes,
        contentType: verified.contentType,
        extension: verified.extension,
      );
    } on DownloadSecurityException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  bool _isUsableMediaResponse(
    http.Response response, {
    required int maxBytes,
  }) {
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return false;

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    if (contentType.contains('text/html') ||
        contentType.contains('application/json')) {
      return false;
    }

    final contentEncoding =
        (response.headers['content-encoding'] ?? '').toLowerCase();
    if (contentEncoding.isNotEmpty && contentEncoding != 'identity') {
      return false;
    }
    final declaredLength =
        int.tryParse(response.headers['content-length'] ?? '');
    if (declaredLength != null &&
        (declaredLength > maxBytes ||
            declaredLength != response.bodyBytes.length)) {
      return false;
    }
    if (response.bodyBytes.length > maxBytes) return false;
    return true;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsTransport && _transport is GatedWikimediaTransport) {
      _transport.close();
    }
  }
}
