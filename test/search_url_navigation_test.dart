import 'dart:async';

import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/search_controller.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MediaSearchResult _result(String title) => MediaSearchResult(
      items: [
        SearchItem(
          title: title,
          url: 'https://upload.wikimedia.org/$title',
          thumb: 'https://upload.wikimedia.org/thumb/$title',
          commonsUrl: 'https://commons.wikimedia.org/wiki/File:$title',
          snippet: title,
          mime: 'image/jpeg',
          isSvg: false,
        ),
      ],
      hasMore: false,
      continueToken: null,
      queryUsed: title,
    );

class _DeferredBackend extends CommonsBackend {
  final Map<String, Completer<MediaSearchResult>> requests = {};

  @override
  QueryBuildResult buildQuery(SearchState filters) => QueryBuildResult(
        srsearch: filters.queryText.trim(),
        chips: const [],
        debugPreview: filters.queryText.trim(),
      );

  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) {
    return (requests[filters.queryText] = Completer<MediaSearchResult>())
        .future;
  }
}

void main() {
  test('bare search URL clears filters, results, and an in-flight search',
      () async {
    final backend = _DeferredBackend();
    final container = ProviderContainer(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
    );
    addTearDown(container.dispose);

    final controller = container.read(searchControllerProvider.notifier);

    final staleSearch = controller.hydrateFromUrl({'q': 'Eiffel Tower'});
    expect(container.read(searchControllerProvider).filterState.queryText,
        'Eiffel Tower');
    expect(
        container.read(searchControllerProvider).activeSession.loading, isTrue);

    await controller.hydrateFromUrl(const {});

    final reset = container.read(searchControllerProvider);
    expect(reset.filterState, const SearchState());
    expect(reset.activeSession.hasSearched, isFalse);
    expect(reset.activeSession.items, isEmpty);
    expect(reset.lastBuiltQuery?.srsearch, isEmpty);

    backend.requests['Eiffel Tower']!
        .complete(_result('Stale Eiffel result.jpg'));
    await staleSearch;

    final afterStaleResponse = container.read(searchControllerProvider);
    expect(afterStaleResponse.filterState, const SearchState());
    expect(afterStaleResponse.activeSession.hasSearched, isFalse);
    expect(afterStaleResponse.activeSession.items, isEmpty);
  });
}
