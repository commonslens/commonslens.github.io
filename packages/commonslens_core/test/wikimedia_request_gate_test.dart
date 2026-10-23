import 'dart:async';

import 'package:commonslens_core/commonslens_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.onSend);

  final Future<http.Response> Function() onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await onSend();
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  test('cancelling a retry wait throws the transport ClientException', () async {
    final requestStarted = Completer<void>();
    var requests = 0;
    final client = _ScriptedClient(() async {
      requests++;
      if (!requestStarted.isCompleted) requestStarted.complete();
      return http.Response('temporary failure', 503);
    });
    var cancelled = false;
    final transport = GatedWikimediaTransport(client: client);

    final future = transport.get(
      Uri.parse('https://commons.wikimedia.org/w/api.php?action=query'),
      maxAttempts: 3,
      deduplicate: false,
      cancelled: () => cancelled,
    );

    await requestStarted.future;
    // Allow the 503 response to flow into the retry wait before cancelling.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    cancelled = true;

    await expectLater(future, throwsA(isA<http.ClientException>()));
    expect(requests, 1);
    client.close();
  });
}
