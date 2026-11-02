import 'package:commonslens_core/commonslens_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _DownloadFixtureTransport implements WikimediaMediaTransport {
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

  @override
  Future<http.StreamedResponse> getStream(
    Uri uri, {
    Duration timeout = const Duration(seconds: 20),
    bool Function()? cancelled,
  }) async {
    requests.add(uri);
    final response = handler(uri);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      contentLength:
          int.tryParse(response.headers['content-length'] ?? '') ?? -1,
      headers: response.headers,
      request: http.Request('GET', uri),
    );
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
                  {"thumburl": "https://upload.wikimedia.org/wikipedia/commons/thumb/scaled.jpg"}
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
      'https://upload.wikimedia.org/wikipedia/commons/thumb/scaled.jpg',
    );
    expect(transport.requests, hasLength(1));
  });

  test('returns validated media bytes without browser dependencies', () async {
    final bytes = <int>[0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9];
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

    final payload = await client.fetchMedia(
        'https://upload.wikimedia.org/wikipedia/commons/example.jpg');

    expect(payload, isNotNull);
    expect(payload!.bytes, bytes);
    expect(payload.contentType, 'image/jpeg');
    expect(payload.extension, 'jpg');
  });

  test('revalidates current Wikimedia metadata before an original download',
      () async {
    final bytes = <int>[0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9];
    final transport = _DownloadFixtureTransport((uri) {
      if (uri.queryParameters['formatversion'] == '2') {
        return http.Response('''
          {
            "query": {
              "pages": [{
                "title": "File:Example.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/wikipedia/commons/example.jpg",
                  "mime": "image/jpeg",
                  "size": ${bytes.length},
                  "sha1": ""
                }]
              }]
            }
          }
        ''', 200);
      }
      return http.Response.bytes(
        bytes,
        200,
        headers: {
          'content-type': 'image/jpeg',
          'content-length': '${bytes.length}',
        },
      );
    });
    final client = WikimediaDownloadClient(transport: transport);

    final payload = await client.fetchMedia(
      'https://upload.wikimedia.org/wikipedia/commons/stale.jpg',
      revalidateTitle: 'Example.jpg',
    );

    expect(payload, isNotNull);
    expect(
      payload!.verifiedUrl,
      'https://upload.wikimedia.org/wikipedia/commons/example.jpg',
    );
    expect(payload.expectedMime, 'image/jpeg');
    expect(payload.expectedLength, bytes.length);
    expect(
      payload.verificationChecks,
      contains(
        'fresh Wikimedia imageinfo metadata was fetched immediately before download',
      ),
    );
    expect(transport.requests, hasLength(2));
  });

  test('stops reading a streamed response at the hard byte limit', () async {
    final transport = _DownloadFixtureTransport(
      (_) => http.Response.bytes(
        <int>[0xff, 0xd8, 0xff, 0x00, 0xff, 0xd9],
        200,
        headers: {'content-type': 'image/jpeg'},
      ),
    );
    final client = WikimediaDownloadClient(transport: transport);

    final payload = await client.fetchMedia(
      'https://upload.wikimedia.org/wikipedia/commons/large.jpg',
      maxBytes: 4,
    );
    expect(payload, isNull);
    expect(transport.requests, hasLength(1));
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
      await client.fetchMedia(
          'https://upload.wikimedia.org/wikipedia/commons/error.jpg'),
      isNull,
    );
    client.close();
    expect(
      await client.fetchMedia(
          'https://upload.wikimedia.org/wikipedia/commons/after-close.jpg'),
      isNull,
    );
    expect(transport.requests, hasLength(1));
  });
}
