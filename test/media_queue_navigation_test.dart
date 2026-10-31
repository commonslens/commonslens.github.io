@TestOn('browser')
library;

import 'package:commonslens/asset_viewer.dart';
import 'package:commonslens/bookmark_service.dart';
import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/media_queue.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

SearchItem _item(int number) => SearchItem(
      title: 'File:Result $number.bin',
      url: 'https://example.test/$number.bin',
      thumb: '',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:Result_$number.bin',
      snippet: '',
      mime: 'application/octet-stream',
      isSvg: false,
    );

class _StaticBookmarks extends BookmarkItemsController {
  _StaticBookmarks(super.ref, List<SearchItem> items) {
    state = BookmarkItemsState(items: items);
  }
}

class _PagedBackend extends CommonsBackend {
  int searchCalls = 0;
  int authorCalls = 0;
  int fetchItemCalls = 0;

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
  }) async {
    searchCalls++;
    final isNextPage = continueToken != null;
    return MediaSearchResult(
      items: isNextPage ? [_item(3), _item(4)] : [_item(1), _item(2)],
      hasMore: !isNextPage,
      continueToken: isNextPage ? null : {'page': 2},
      queryUsed: filters.queryText,
    );
  }

  @override
  Future<MediaSearchResult> authorUploads(
    String username, {
    Map<String, dynamic>? continueToken,
  }) async {
    authorCalls++;
    final isNextPage = continueToken != null;
    return MediaSearchResult(
      items: isNextPage ? [_item(3), _item(4)] : [_item(1), _item(2)],
      hasMore: !isNextPage,
      continueToken: isNextPage ? null : {'page': 2},
      queryUsed: 'allimages:$username',
    );
  }

  @override
  Future<SearchItem?> fetchItem(String fileIdOrTitle) async {
    fetchItemCalls++;
    return null;
  }
}

void main() {
  test('queue URLs retain the source and selected file', () {
    final source = MediaQueueSource.bookmarks('Result 2');
    final uri =
        Uri.parse(source.urlFor('File:Result 2.bin', queueId: 'queue-1'));
    final restored = MediaQueueSource.fromUrl(uri.queryParameters);

    expect(restored.kind, 'bookmarks');
    expect(restored.parameters['bq'], 'Result 2');
    expect(restored.returnUrl, '/bookmarks?bq=Result+2');
    expect(uri.queryParameters['id'], 'File:Result 2.bin');
    expect(uri.queryParameters['queue'], 'queue-1');

    final mapSource = MediaQueueSource.search(
      const SearchState(queryText: 'mountains'),
      map: true,
    );
    final mapLink = Uri.parse(mapSource.urlFor('File:Peak.jpg'));
    expect(
        MediaQueueSource.fromUrl(mapLink.queryParameters).key, mapSource.key);
    expect(mapSource.returnUrl, '/?q=mountains&view=map');

    final author = MediaQueueSource.author('Ada Lovelace');
    expect(
        MediaQueueSource.fromUrl(
          Uri.parse(author.urlFor('File:Portrait.jpg')).queryParameters,
        ).key,
        author.key);
  });

  test('same-tab snapshot keeps the order of a runtime queue', () {
    final source = MediaQueueSource.pipeline('node-1');
    final store = MediaQueueStore();
    final items = [_item(1), _item(2), _item(3)];
    final queueId = store.capture(source, items);

    expect(store.capture(source, items), queueId);
    expect(store.capture(source, [...items, _item(4)]), queueId);

    expect(store.get(queueId, source)!.items.map((item) => item.title),
        [...items, _item(4)].map((item) => item.title));
    expect(MediaQueueStore().get(queueId, source)!.items.map((item) => item.title),
        [...items, _item(4)].map((item) => item.title));
    expect(store.get(queueId, MediaQueueSource.pipeline('node-2')), isNull);
  });

  testWidgets('bookmark URL opens its requested position and updates on next',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final items = [_item(1), _item(2), _item(3)];
    final source = MediaQueueSource.bookmarks('');
    final router = GoRouter(
      initialLocation: source.urlFor(items[2].title),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookmarkItemsProvider.overrideWith(
          (ref) => _StaticBookmarks(ref, items),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 OF 3'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['id'],
        items[2].title);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    await tester.pumpAndSettle();

    expect(find.text('2 OF 3'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['id'],
        items[1].title);
  });

  testWidgets('bookmark URL retains the filtered list', (tester) async {
    final items = [_item(1), _item(2), _item(3)];
    final source = MediaQueueSource.bookmarks('Result 2');
    final router = GoRouter(
      initialLocation: source.urlFor(items[1].title),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookmarkItemsProvider.overrideWith(
          (ref) => _StaticBookmarks(ref, items),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 OF 1'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['bq'],
        'Result 2');
  });

  testWidgets('pipeline URL uses a stored queue after runtime output is gone',
      (tester) async {
    final items = [_item(1), _item(2), _item(3)];
    final source = MediaQueueSource.pipeline('node-1');
    final queueStore = MediaQueueStore();
    final queueId = queueStore.capture(source, items);
    final router = GoRouter(
      initialLocation: source.urlFor(items[2].title, queueId: queueId),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [mediaQueueStoreProvider.overrideWithValue(queueStore)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 OF 3'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['id'],
        items[2].title);
  });

  testWidgets('pipeline URL without a queue falls back to its requested file',
      (tester) async {
    final backend = _PagedBackend();
    final source = MediaQueueSource.pipeline('missing-node');
    final router = GoRouter(
      initialLocation: source.urlFor(_item(3).title),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Media not found.'), findsOneWidget);
    expect(backend.fetchItemCalls, 1);
  });

  testWidgets('search URL finds a target beyond the first results page',
      (tester) async {
    final backend = _PagedBackend();
    final source = MediaQueueSource.search(
      const SearchState(queryText: 'birds'),
    );
    final router = GoRouter(
      initialLocation: source.urlFor(_item(3).title),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 OF 4'), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.queryParameters['id'],
        _item(3).title);
    expect(backend.searchCalls, 2);
    expect(backend.fetchItemCalls, 0);
  });

  testWidgets('saved search queue opens a later item without refetching',
      (tester) async {
    final backend = _PagedBackend();
    final source = MediaQueueSource.search(
      const SearchState(queryText: 'birds'),
    );
    final store = MediaQueueStore();
    final items = List.generate(6, (index) => _item(index + 1));
    final queueId = store.capture(source, items, hasMore: true);
    final router = GoRouter(
      initialLocation: source.urlFor(items[2].title, queueId: queueId),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        commonsBackendProvider.overrideWithValue(backend),
        mediaQueueStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 OF 6'), findsOneWidget);
    expect(backend.searchCalls, 0);
  });

  testWidgets('author URL finds a target beyond the first uploads page',
      (tester) async {
    final backend = _PagedBackend();
    final source = MediaQueueSource.author('Ada');
    final router = GoRouter(
      initialLocation: source.urlFor(_item(3).title),
      routes: [
        GoRoute(
          path: '/view',
          builder: (context, state) => AssetViewer(
            fileId: state.uri.queryParameters['id'] ?? '',
            returnUrl: '/',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [commonsBackendProvider.overrideWithValue(backend)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.text('3 OF 4'), findsOneWidget);
    expect(backend.authorCalls, 2);
    expect(backend.fetchItemCalls, 0);
  });
}
