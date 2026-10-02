import 'dart:async';

import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/commons_engine.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

SearchItem _item(String title) => SearchItem(
      title: title,
      url: 'https://upload.wikimedia.org/$title',
      thumb: 'https://upload.wikimedia.org/thumb/$title',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:$title',
      snippet: title,
      mime: 'image/jpeg',
      isSvg: false,
    );

MediaSearchResult _page(
  List<SearchItem> items, {
  Map<String, dynamic>? cursor,
  String? error,
}) =>
    MediaSearchResult(
      items: items,
      hasMore: cursor != null,
      continueToken: cursor,
      queryUsed: 'test',
      error: error,
    );

class _ScriptedBackend extends CommonsBackend {
  final List<MediaSearchResult> searchPages;
  final List<MediaSearchResult> authorPages;
  int searchCalls = 0;
  int authorCalls = 0;

  _ScriptedBackend({
    this.searchPages = const [],
    this.authorPages = const [],
  });

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
  }) async {
    return searchPages[searchCalls++];
  }

  @override
  Future<MediaSearchResult> authorUploads(
    String username, {
    Map<String, dynamic>? continueToken,
  }) async {
    return authorPages[authorCalls++];
  }

  @override
  List<SearchItem> applyClientSort(
    List<SearchItem> items,
    SortMode sortMode,
  ) {
    if (sortMode != SortMode.titleMatch) return items;
    return [...items]..sort((a, b) => a.title.compareTo(b.title));
  }
}

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
  group('CommonsSearchSession', () {
    test('empty query resets without calling the backend', () async {
      final backend = _ScriptedBackend();
      final session = CommonsSearchSession(backend: backend);

      final result = await session.search(const SearchState());

      expect(result.hasSearched, isFalse);
      expect(result.items, isEmpty);
      expect(backend.searchCalls, 0);
    });

    test('loads, deduplicates, and re-sorts appended pages', () async {
      final alpha = _item('Alpha.jpg');
      final bravo = _item('Bravo.jpg');
      final charlie = _item('Charlie.jpg');
      final backend = _ScriptedBackend(searchPages: [
        _page([bravo, alpha], cursor: {'next': '2'}),
        _page([charlie, bravo]),
      ]);
      final session = CommonsSearchSession(backend: backend);

      await session.search(const SearchState(
        queryText: 'letters',
        sortMode: SortMode.titleMatch,
      ));
      final result = await session.loadMore();

      expect(result.items.map((item) => item.title), [
        'Alpha.jpg',
        'Bravo.jpg',
        'Charlie.jpg',
      ]);
      expect(result.hasMore, isFalse);
      expect(result.loadingMore, isFalse);
      expect(backend.searchCalls, 2);
    });

    test('ignores an older response after a newer search wins', () async {
      final backend = _DeferredBackend();
      final session = CommonsSearchSession(backend: backend);

      final older = session.search(const SearchState(queryText: 'older'));
      final newer = session.search(const SearchState(queryText: 'newer'));

      backend.requests['newer']!.complete(_page([_item('Newer.jpg')]));
      await newer;
      backend.requests['older']!.complete(_page([_item('Older.jpg')]));
      await older;

      expect(session.filterState.queryText, 'newer');
      expect(session.activeSession.items.single.title, 'Newer.jpg');
    });

    test('keeps existing items when loading the next page fails', () async {
      final alpha = _item('Alpha.jpg');
      final backend = _ScriptedBackend(searchPages: [
        _page([alpha], cursor: {'next': '2'}),
        _page(const [], error: 'temporary failure'),
      ]);
      final session = CommonsSearchSession(backend: backend);

      await session.search(const SearchState(queryText: 'alpha'));
      final result = await session.loadMore();

      expect(result.items, [same(alpha)]);
      expect(result.loadingMore, isFalse);
      expect(result.hasMore, isTrue);
    });
  });

  test('AuthorPortfolioSession deduplicates paginated uploads', () async {
    final alpha = _item('Alpha.jpg');
    final bravo = _item('Bravo.jpg');
    final backend = _ScriptedBackend(authorPages: [
      _page([alpha], cursor: {'aicontinue': '2'}),
      _page([alpha, bravo]),
    ]);
    final session = AuthorPortfolioSession('Example', backend: backend);

    await session.load();
    final result = await session.loadMore();

    expect(result.items.map((item) => item.title), ['Alpha.jpg', 'Bravo.jpg']);
    expect(result.hasMore, isFalse);
    expect(backend.authorCalls, 2);
  });
}
