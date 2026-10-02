@TestOn('browser')
library;

import 'dart:async';

import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/search_controller.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeferredPagingBackend extends CommonsBackend {
  final nextPage = Completer<MediaSearchResult>();
  int searchCalls = 0;

  @override
  QueryBuildResult buildQuery(SearchState filters) => QueryBuildResult(
        srsearch: filters.queryText,
        chips: const [],
        debugPreview: filters.queryText,
      );

  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) {
    searchCalls++;
    if (continueToken != null) return nextPage.future;
    return Future.value(const MediaSearchResult(
      items: [],
      hasMore: true,
      continueToken: {'continue': 'next'},
      queryUsed: 'test',
    ));
  }
}

void main() {
  test('duplicate load-more calls do not republish state', () async {
    final backend = _DeferredPagingBackend();
    final container = ProviderContainer(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final controller = container.read(searchControllerProvider.notifier);
    await controller.search('test');

    var notifications = 0;
    final subscription = container.listen(
      searchControllerProvider,
      (_, __) => notifications++,
    );
    addTearDown(subscription.close);

    final firstLoad = controller.loadMore();
    expect(backend.searchCalls, 2);
    expect(notifications, 1);

    await controller.loadMore();
    expect(backend.searchCalls, 2);
    expect(notifications, 1);

    backend.nextPage.complete(const MediaSearchResult(
      items: [],
      hasMore: false,
      continueToken: null,
      queryUsed: 'test',
    ));
    await firstLoad;
    expect(notifications, 2);
  });
}
