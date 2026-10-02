import 'dart:convert';

import 'package:commonslens_core/commonslens_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _DownloadFixtureTransport implements WikimediaTransport {
  _DownloadFixtureTransport(this.handler);

  final http.Response Function(Uri uri) handler;
  final List<Uri> requests = [];

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  }) async {
    requests.add(uri);
    return handler(uri);
  }
}

void main() {
  test('resolves scaled media URLs through the Commons API', () async {
    final transport = _DownloadFixtureTransport((uri) {
      expect(uri.host, 'commons.wikimedia.org');
      expect(uri.queryParameters['titles'], 'File:Example.jpg');
      expect(uri.queryParameters['iiurlwidth'], '640');
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "imageinfo": [
                  {"thumburl": "https://upload.wikimedia.org/scaled.jpg"}
                ]
              }
            }
          }
        }
      ''', 200);
    });
    final client = WikimediaDownloadClient(transport: transport);

    expect(
      await client.fetchScaledUrl('Example.jpg', 640),
      'https://upload.wikimedia.org/scaled.jpg',
    );
    expect(transport.requests, hasLength(1));
  });

  test('returns validated media bytes without browser dependencies', () async {
    final bytes = utf8.encode('binary-ish data');
    final transport = _DownloadFixtureTransport(
      (_) => http.Response.bytes(
        bytes,
        200,
        headers: {
          'content-type': 'image/jpeg',
          'content-length': '${bytes.length}',
        },
      ),
    );
    final client = WikimediaDownloadClient(transport: transport);

    final payload =
        await client.fetchMedia('https://upload.wikimedia.org/example.jpg');

    expect(payload, isNotNull);
    expect(payload!.bytes, bytes);
    expect(payload.contentType, 'image/jpeg');
  });

  test('rejects error documents and prevents work after close', () async {
    final transport = _DownloadFixtureTransport(
      (_) => http.Response(
        '<html>not media</html>',
        200,
        headers: {'content-type': 'text/html'},
      ),
    );
    final client = WikimediaDownloadClient(transport: transport);

    expect(
      await client.fetchMedia('https://upload.wikimedia.org/error'),
      isNull,
    );
    client.close();
    expect(
      await client.fetchMedia('https://upload.wikimedia.org/after-close'),
      isNull,
    );
    expect(transport.requests, hasLength(1));
  });
}
