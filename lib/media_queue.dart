// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'bookmark_service.dart';
import 'pipeline_controller.dart';

/// A description of the list a file was opened from. It is small enough to
/// travel in a URL; the media themselves stay in the providers that own them.
class MediaQueueSource {
  final String kind;
  final Map<String, String> parameters;
  final String returnUrl;

  const MediaQueueSource(this.kind, this.parameters, this.returnUrl);

  factory MediaQueueSource.search(SearchState state, {bool map = false}) {
    final params = SearchUrlCodec.toQueryParams(state);
    if (map) params['view'] = 'map';
    return MediaQueueSource(
      'search',
      params,
      Uri(path: '/', queryParameters: params.isEmpty ? null : params)
          .toString(),
    );
  }

  factory MediaQueueSource.author(String name) => MediaQueueSource(
        'author',
        {'author': name},
        Uri(path: '/author', queryParameters: {'name': name}).toString(),
      );

  factory MediaQueueSource.bookmarks(String query) => MediaQueueSource(
        'bookmarks',
        {'from': 'bookmarks', if (query.isNotEmpty) 'bq': query},
        Uri(
          path: '/bookmarks',
          queryParameters: query.isEmpty ? null : {'bq': query},
        ).toString(),
      );

  factory MediaQueueSource.pipeline(String nodeId,
          {String returnUrl = '/pipeline'}) =>
      MediaQueueSource(
        'pipeline',
        {'from': 'pipeline', 'pipelineNode': nodeId},
        returnUrl,
      );

  factory MediaQueueSource.related(String title, String returnUrl) =>
      MediaQueueSource('related', {'related': title}, returnUrl);

  factory MediaQueueSource.session(String returnUrl) =>
      MediaQueueSource('session', const {}, returnUrl);

  factory MediaQueueSource.fromUrl(Map<String, String> params) {
    final kind = params['source'] ??
        (params['author']?.isNotEmpty == true
            ? 'author'
            : params['from'] == 'pipeline'
                ? 'pipeline'
                : params['from'] == 'bookmarks'
                    ? 'bookmarks'
                    : SearchUrlCodec.hasSearchContext(params)
                        ? 'search'
                        : 'direct');
    if (kind == 'author') {
      return MediaQueueSource.author(params['author'] ?? '');
    }
    if (kind == 'bookmarks') {
      return MediaQueueSource.bookmarks(params['bq'] ?? '');
    }
    if (kind == 'pipeline') {
      return MediaQueueSource.pipeline(
        params['pipelineNode'] ?? '',
        returnUrl: params['return'] ?? '/pipeline',
      );
    }
    if (kind == 'related') {
      return MediaQueueSource.related(
        params['related'] ?? '',
        params['return'] ?? '/',
      );
    }
    if (kind == 'session') {
      return MediaQueueSource.session(params['return'] ?? '/');
    }
    if (kind == 'search') {
      final searchParams = Map<String, String>.from(params)
        ..remove('id')
        ..remove('source')
        ..remove('queue')
        ..remove('return')
        ..remove('from')
        ..remove('bq')
        ..remove('related')
        ..remove('pipelineNode')
        ..remove('author');
      final state = SearchUrlCodec.fromQueryParams(
        searchParams,
        const SearchState(),
      );
      return MediaQueueSource.search(
        state,
        map: searchParams['view'] == 'map' || params['from'] == 'map',
      );
    }
    return const MediaQueueSource('direct', {}, '/');
  }

  Map<String, String> get urlParameters => {
        ...parameters,
        if (kind != 'direct') 'source': kind,
        if (kind == 'related' ||
            kind == 'session' ||
            (kind == 'pipeline' && returnUrl != '/pipeline'))
          'return': returnUrl,
      };

  String get key => Uri(queryParameters: urlParameters).query;

  String urlFor(String title, {String? queueId}) => Uri(
        path: '/view',
        queryParameters: {
          'id': title,
          ...urlParameters,
          if (queueId != null) 'queue': queueId,
        },
      ).toString();
}

class MediaQueueSnapshot {
  final MediaQueueSource source;
  final List<SearchItem> items;
  final bool hasMore;

  const MediaQueueSnapshot(this.source, this.items, this.hasMore);
}

/// Holds the current list without serializing it into every navigation. A
/// sessionStorage copy lets a reload in the same tab reopen a runtime list.
class MediaQueueStore {
  final Map<String, MediaQueueSnapshot> _queues = {};
  int _sequence = 0;
  String? _activeId;

  bool _sameItems(List<SearchItem> left, List<SearchItem> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].title != right[index].title ||
          left[index].url != right[index].url) {
        return false;
      }
    }
    return true;
  }

  String capture(MediaQueueSource source, List<SearchItem> items,
      {bool hasMore = false}) {
    final activeId = _activeId;
    final active = activeId == null ? null : _queues[activeId];
    if (activeId != null && active != null && active.source.key == source.key) {
      if (active.hasMore != hasMore || !_sameItems(active.items, items)) {
        update(activeId, source, items, hasMore: hasMore);
      }
      return activeId;
    }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _activeId = id;
    update(id, source, items, hasMore: hasMore);
    while (_queues.length > 40) {
      final oldest = _queues.keys.first;
      _queues.remove(oldest);
      try {
        html.window.sessionStorage.remove('commonslens.queue.$oldest');
      } catch (_) {}
    }
    return id;
  }

  void update(String id, MediaQueueSource source, List<SearchItem> items,
      {bool hasMore = false}) {
    final snapshot = MediaQueueSnapshot(
      source,
      List<SearchItem>.unmodifiable(items),
      hasMore,
    );
    _queues[id] = snapshot;
    try {
      html.window.sessionStorage['commonslens.queue.$id'] = jsonEncode({
        'source': source.kind,
        'params': source.parameters,
        'return': source.returnUrl,
        'hasMore': hasMore,
        'items': items.map((item) => item.toJson()).toList(),
      });
    } catch (_) {
      // Quota and privacy restrictions only affect reload recovery.
    }
  }

  MediaQueueSnapshot? get(String? id, MediaQueueSource source) {
    if (id == null) return null;
    final cached = _queues[id];
    if (cached != null) {
      return cached.source.key == source.key ? cached : null;
    }
    try {
      final raw = html.window.sessionStorage['commonslens.queue.$id'];
      if (raw == null) return null;
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      final items = (value['items'] as List?)
              ?.whereType<Map>()
              .map((entry) =>
                  SearchItem.fromJson(Map<String, dynamic>.from(entry)))
              .toList() ??
          <SearchItem>[];
      final restored = MediaQueueSnapshot(
        MediaQueueSource(
          value['source'] as String? ?? 'direct',
          Map<String, String>.from(value['params'] as Map? ?? {}),
          value['return'] as String? ?? '/',
        ),
        List<SearchItem>.unmodifiable(items),
        value['hasMore'] == true,
      );
      if (restored.source.key != source.key) return null;
      return _queues[id] = restored;
    } catch (_) {
      return null;
    }
  }
}

final mediaQueueStoreProvider = Provider<MediaQueueStore>((ref) {
  return MediaQueueStore();
});

class MediaQueueData {
  final List<SearchItem> items;
  final bool loading;
  final bool hasMore;
  final bool fromSnapshot;

  const MediaQueueData(
    this.items, {
    this.loading = false,
    this.hasMore = false,
    this.fromSnapshot = false,
  });
}

/// The viewer only consumes this one interface. Source-specific provider
/// reads, hydration, and pagination are kept here with the source model.
abstract final class MediaQueueResolver {
  static bool _sameSearch(SearchState state, MediaQueueSource source) {
    final current = SearchUrlCodec.toQueryParams(state);
    final requested = Map<String, String>.from(source.parameters)
      ..remove('view');
    return Uri(queryParameters: current).query ==
        Uri(queryParameters: requested).query;
  }

  static bool searchIsLive(WidgetRef ref, MediaQueueSource source) {
    final state = ref.read(searchControllerProvider);
    return state.externalQueueNodeId == null &&
        _sameSearch(state.filterState, source) &&
        state.activeSession.hasSearched;
  }

  static MediaQueueData watch(
    WidgetRef ref,
    MediaQueueSource source,
    MediaQueueSnapshot? snapshot,
    String targetTitle,
  ) {
    MediaQueueData? live;
    switch (source.kind) {
      case 'search':
        final state = ref.watch(searchControllerProvider);
        if (state.externalQueueNodeId == null &&
            _sameSearch(state.filterState, source) &&
            state.activeSession.hasSearched) {
          final session = state.activeSession;
          live = MediaQueueData(session.items,
              loading: session.loading || session.loadingMore,
              hasMore: session.hasMore);
        }
        break;
      case 'author':
        final session = ref
            .watch(authorPortfolioProvider(source.parameters['author'] ?? ''));
        live = MediaQueueData(session.items,
            loading: session.loading || session.loadingMore,
            hasMore: session.hasMore);
        break;
      case 'bookmarks':
        final state = ref.watch(bookmarkItemsProvider);
        final query = source.parameters['bq'] ?? '';
        live = MediaQueueData(
          state.items
              .where((item) => bookmarkMatchesSearch(item, query))
              .toList(),
          loading: state.loading,
        );
        break;
      case 'pipeline':
        ref.watch(pipelineControllerProvider);
        final items = ref
            .read(pipelineControllerProvider.notifier)
            .materializedItemsFor(source.parameters['pipelineNode'] ?? '');
        if (items != null) live = MediaQueueData(items);
        break;
      case 'related':
        final result =
            ref.watch(morelikeProvider(source.parameters['related'] ?? ''));
        live = result.when(
          data: (items) => MediaQueueData(items),
          loading: () => const MediaQueueData([], loading: true),
          error: (_, __) => const MediaQueueData([]),
        );
        break;
    }
    if (snapshot != null && snapshot.items.isNotEmpty) {
      final target = normalizeMediaTitle(targetTitle);
      final liveHasTarget = live?.items.any(
            (item) => normalizeMediaTitle(item.title) == target,
          ) ??
          false;
      if (source.kind != 'bookmarks' || live == null || live.loading) {
        if (!liveHasTarget &&
            snapshot.items
                .any((item) => normalizeMediaTitle(item.title) == target)) {
          return MediaQueueData(snapshot.items,
              hasMore: snapshot.hasMore, fromSnapshot: true);
        }
      }
    }
    return live ?? MediaQueueData([], loading: source.kind == 'search');
  }

  static Future<void> hydrateSearch(WidgetRef ref, MediaQueueSource source) {
    final params = Map<String, String>.from(source.parameters)..remove('view');
    return ref.read(searchControllerProvider.notifier).hydrateFromUrl(params);
  }

  static Future<void> loadMore(WidgetRef ref, MediaQueueSource source) {
    if (source.kind == 'author') {
      final name = source.parameters['author'] ?? '';
      return ref.read(authorPortfolioProvider(name).notifier).loadMore(name);
    }
    if (source.kind == 'search') {
      return ref.read(searchControllerProvider.notifier).loadMore();
    }
    return Future.value();
  }
}

String normalizeMediaTitle(String title) => title
    .replaceFirst(RegExp(r'^File:', caseSensitive: false), '')
    .replaceAll('_', ' ')
    .trim()
    .toLowerCase();
