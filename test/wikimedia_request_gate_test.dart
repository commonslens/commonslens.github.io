import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:commonslens/wikimedia_request_gate.dart';

void main() {
  test('adds Wikimedia safeguards and retries a throttled request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.queryParameters['maxlag'], '5');
      expect(
        request.headers['Api-User-Agent'],
        WikimediaRequestGate.apiUserAgent,
      );

      if (calls == 1) {
        return http.Response(
          'throttled',
          429,
          headers: {'retry-after': '0'},
        );
      }
      return http.Response('{"query":{}}', 200);
    });

    final response = await WikimediaRequestGate.get(
      client,
      Uri.https('www.wikidata.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
      }),
      maxAttempts: 2,
    );

    expect(response.statusCode, 200);
    expect(calls, 2);
    client.close();
  });

  test('retries a rejected or incomplete response body', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.followRedirects, isFalse);
      return calls == 1
          ? http.Response.bytes(const [], 200)
          : http.Response.bytes(const [1, 2, 3], 200);
    });

    final response = await WikimediaRequestGate.get(
      client,
      Uri.parse('https://upload.wikimedia.org/example.jpg'),
      maxAttempts: 2,
      deduplicate: false,
      acceptResponse: (candidate) => candidate.bodyBytes.isNotEmpty,
    );

    expect(response.bodyBytes, const [1, 2, 3]);
    expect(calls, 2);
    client.close();
  });
}
