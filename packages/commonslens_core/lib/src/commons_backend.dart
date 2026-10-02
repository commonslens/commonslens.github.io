import 'search_models.dart';
import 'search_service.dart';

/// Plain-data result of one backend fetch. Exactly "the media and its
/// metadata" — no loading flags (the call has already finished by the time
/// you hold this), no scroll offsets, nothing that only makes sense inside
/// a widget tree. JSON-serializable end to end (SearchItem is flat fields,
/// continueToken is a plain Map).
class MediaSearchResult {
  final List<SearchItem> items;
  final bool hasMore;
  final String? error;

  /// Opaque, JSON-serializable. Hand it back as [CommonsBackend.search]'s
  /// `continueToken` argument to get the next page. Null when there is no
  /// next page.
  final Map<String, dynamic>? continueToken;

  /// The literal CirrusSearch query string this result came from — useful
  /// for logging, debugging, or showing a human/agent what its filters
  /// actually resolved to.
  final String queryUsed;

  /// Wikimedia's own estimate of total matches, when available — see
  /// [SearchResponse.totalHits] for why this is sometimes null even on a
  /// successful search (multi-branch fan-out queries: "+"-terms, or
  /// union-mode category/depicts/statement filters).
  final int? totalHits;

  /// CirrusSearch's "did you mean" spelling suggestion, if any. Same
  /// fan-out caveat as [totalHits].
  final String? suggestion;

  const MediaSearchResult({
    required this.items,
    required this.hasMore,
    required this.continueToken,
    required this.queryUsed,
    this.error,
    this.totalHits,
    this.suggestion,
  });

  bool get ok => error == null;

  /// This is literally what a JSON server handler returns as the response
  /// body for a search request.
  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'hasMore': hasMore,
        'error': error,
        'continueToken': continueToken,
        'queryUsed': queryUsed,
        'totalHits': totalHits,
        'suggestion': suggestion,
      };

  /// Parses this shape back — useful if you're building a Dart *client*
  /// against a JSON server that serves [toJson]'s shape, not just the
  /// server side.
  static MediaSearchResult fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final continueTokenRaw = json['continueToken'];
    return MediaSearchResult(
      items: itemsRaw is List
          ? itemsRaw
              .whereType<Map>()
              .map((m) => SearchItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      hasMore: json['hasMore'] as bool? ?? false,
      continueToken: continueTokenRaw is Map
          ? Map<String, dynamic>.from(continueTokenRaw)
          : null,
      queryUsed: json['queryUsed'] as String? ?? '',
      error: json['error'] as String?,
      totalHits: (json['totalHits'] as num?)?.toInt(),
      suggestion: json['suggestion'] as String?,
    );
  }
}

/// The complete fetch + filter + paginate backend. Every method is
/// stateless: pass the filters (and, for page 2+, the continuation token
/// from the previous call) and get plain data back. No session object to
/// keep alive, nothing mutable, safe to call concurrently from as many
/// callers as you want.
///
/// This is the shape a JSON server handler wants: request in, [SearchState]
/// out of the request body, one call, JSON-serializable [MediaSearchResult]
/// out. It's equally the shape an agent's "search" tool wants, or a UI's
/// data layer.
///
/// Internally this still gets the benefit of [SearchService]'s parallel
/// fan-out (multi-term "+" queries, union-mode categories/depicts/
/// statements, and per-format requests all run concurrently via
/// `Future.wait`, not serially) — that optimization lives in SearchService
/// and this class doesn't need to know about it.
///
/// If you're inside a long-running process (a Flutter app, an agent loop)
/// and would rather not carry the continuation token around yourself,
/// see [CommonsSearchSession] in commons_engine.dart, which wraps this and
/// keeps the token for you.
class CommonsBackend {
  CommonsBackend({SearchService? service})
      : _service = service ?? SearchService();

  final SearchService _service;

  /// The CirrusSearch query string + UI-facing chips [filters] resolves
  /// to — exposed so callers (including [CommonsSearchSession]) never need
  /// their own [SearchService] instance just to inspect or hash a query.
  QueryBuildResult buildQuery(SearchState filters) =>
      _service.buildQuery(filters);

  /// A stable signature for [filters] — identical filters always produce
  /// the same signature, safe to use as a cache/session key.
  String buildQuerySignature(SearchState filters) =>
      _service.buildQuerySignature(filters);

  /// Fetch + filter + paginate, in one call. [filters] describes the full
  /// query — free text, tab, formats, category/depicts/wikidata-statement
  /// include/exclude sets (with union/intersection mode), license,
  /// quality, dates, geo, exclusions — see [SearchState]. [continueToken]
  /// is the previous call's [MediaSearchResult.continueToken] for the
  /// *same* [filters]; omit it for page one.
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) async {
    final built = _service.buildQuery(filters);

    if (built.srsearch.trim().isEmpty) {
      return MediaSearchResult(
        items: const [],
        hasMore: false,
        continueToken: null,
        queryUsed: built.srsearch,
        error: 'No query or filters supplied.',
      );
    }

    final result =
        await _service.fetchPage(filters, continueParams: continueToken);

    if (result == null) {
      return MediaSearchResult(
        items: const [],
        hasMore: false,
        continueToken: continueToken,
        queryUsed: built.srsearch,
        error: 'Fetch failed — check connectivity or retry.',
      );
    }

    final items = filters.sortMode == SortMode.relevance
        ? result.items
        : _service.applyClientSort(result.items, filters.sortMode);

    return MediaSearchResult(
      items: items,
      hasMore: result.continueParams != null,
      continueToken: result.continueParams,
      queryUsed: built.srsearch,
      totalHits: result.totalHits,
      suggestion: result.suggestion,
    );
  }

  /// One uploader's full upload history, paginated the same way as
  /// [search] — stateless, pass the previous [continueToken] back in for
  /// the next page.
  Future<MediaSearchResult> authorUploads(
    String username, {
    Map<String, dynamic>? continueToken,
  }) async {
    final result = await _service.fetchAuthorImages(
      username,
      continueParams: continueToken,
    );

    if (result == null) {
      return MediaSearchResult(
        items: const [],
        hasMore: false,
        continueToken: continueToken,
        queryUsed: 'allimages:$username',
        error: "Could not load this uploader's portfolio.",
      );
    }

    return MediaSearchResult(
      items: result.items,
      hasMore: result.continueParams != null,
      continueToken: result.continueParams,
      queryUsed: 'allimages:$username',
    );
  }

  /// A single file by title/filename — full metadata, no search involved.
  Future<SearchItem?> fetchItem(String fileIdOrTitle) =>
      _service.fetchSingleItem(fileIdOrTitle);

  /// Every stored revision of a file, newest first — its upload/edit
  /// history, not just the current version [fetchItem] returns. Not
  /// paginated the way [search]/[authorUploads] are: this is a single
  /// bounded list (`limit`, default 20), not an opaque-continuation feed.
  Future<List<FileRevision>> fileHistory(String fileIdOrTitle,
          {int limit = 20}) =>
      _service.fetchFileHistory(fileIdOrTitle, limit: limit);

  /// A file's full Structured Data on Commons entity — multilingual
  /// captions plus every structured statement (creator, institution,
  /// coordinates of depicted place, and anything else editors have added)
  /// — as opposed to *filtering* on one of those via [SearchState]'s
  /// `statementsInclude`/`statementsExclude`. Null if the file has no SDC
  /// entity, or on any fetch failure.
  Future<StructuredDataResult?> structuredData(String fileIdOrTitle) =>
      _service.fetchStructuredData(fileIdOrTitle);

  /// Pure geographic browse — either a radius around ([lat], [lng]) or a
  /// literal rectangle via [boundingBox] ([northLat, westLng, southLat,
  /// eastLng]), ordered by distance where that's meaningful (radius mode),
  /// with none of [SearchState]'s other filters applied. Unlike [search]
  /// with a `nearCoord` filter set (which ANDs `nearcoord:` into a normal
  /// CirrusSearch relevance query), this bypasses CirrusSearch entirely
  /// via MediaWiki's own geosearch index — useful for a literal map/bbox
  /// browsing UI rather than "text/filter search, additionally constrained
  /// by location". Exactly one of (lat & lng) or [boundingBox] must be
  /// supplied.
  ///
  /// [limit] defaults to 500 — the documented anonymous-user ceiling for
  /// this module (mw:Extension:GeoData#list=geosearch) — rather than the
  /// smaller page size [search]/[authorUploads] use. This is deliberate,
  /// not an oversight: verified against GeoData's own source
  /// (QueryGeoSearchElastic.php, the backend Commons actually runs —
  /// `$wgGeoDataBackend = 'elastic'`), this module never emits a
  /// `continue` token at all. It just returns up to `limit` results,
  /// full stop — there is no page 2 to ask for. Given that, asking for
  /// anything less than the max in the first request only throws results
  /// away for no benefit; [continueToken] is still accepted for forward
  /// compatibility, but in practice [MediaSearchResult.hasMore] will
  /// always come back false from this method against Commons today.
  Future<MediaSearchResult> geosearch({
    double? lat,
    double? lng,
    double radiusMeters = 1000,
    List<double>? boundingBox,
    int limit = 500,
    Map<String, dynamic>? continueToken,
  }) async {
    final result = await _service.geosearch(
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
      boundingBox: boundingBox,
      limit: limit,
      continueParams: continueToken,
    );

    final queryUsed = boundingBox != null
        ? 'geosearch:bbox(${boundingBox.join(",")})'
        : 'geosearch:$lat,$lng,${radiusMeters}m';

    if (result == null) {
      return MediaSearchResult(
        items: const [],
        hasMore: false,
        continueToken: continueToken,
        queryUsed: queryUsed,
        error: 'Could not load nearby media — check connectivity, or that '
            'either lat/lng or a bounding box was supplied.',
      );
    }

    return MediaSearchResult(
      items: result.items,
      hasMore: result.continueParams != null,
      continueToken: result.continueParams,
      queryUsed: queryUsed,
    );
  }

  /// Every Wikimedia page (any language, any project) that currently
  /// embeds this file — a real-world usage signal (files actually used
  /// somewhere vs. unused personal uploads) distinct from anything
  /// CirrusSearch itself indexes.
  Future<List<GlobalUsageEntry>> globalUsage(String fileIdOrTitle,
          {int limit = 500}) =>
      _service.fetchGlobalUsage(fileIdOrTitle, limit: limit);

  Future<BrowseResult<CategoryItem>> browseCategories({
    String? prefix,
    String? cursor,
    int limit = 500,
  }) =>
      _service.browseCategories(
        prefix: prefix,
        cursor: cursor,
        limit: limit,
      );

  Future<BrowseResult<String>> browseTemplates({
    String? prefix,
    String? cursor,
    int limit = 500,
  }) =>
      _service.browseTemplates(
        prefix: prefix,
        cursor: cursor,
        limit: limit,
      );

  /// Re-sorts already-fetched items for [SortMode.titleMatch] (a no-op for
  /// every other mode, which the backend already orders correctly).
  /// Needed after client-side merging paginated results — e.g. appending a
  /// [loadMore]-style next page — since concatenating two already-sorted
  /// pages does not keep the combined list sorted.
  List<SearchItem> applyClientSort(List<SearchItem> items, SortMode sortMode) =>
      _service.applyClientSort(items, sortMode);

  /// The autocomplete surface, kept deliberately separate from
  /// search/pagination — see [CommonsAutocomplete].
  CommonsAutocomplete get autocomplete =>
      CommonsAutocomplete(service: _service);
}

class _CacheEntry<T> {
  final T value;
  final DateTime expiresAt;
  _CacheEntry(this.value, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Autocomplete/typeahead — separate from [CommonsBackend]'s search and
/// pagination concerns on purpose, since a UI or agent wiring up typeahead
/// shouldn't need to think about query-building or continuation tokens at
/// all. Covers four things:
///
/// - [queries] — free-text suggestions (direct File: title matches, the
///   same dropdown Commons' own search box shows)
/// - [categories] — category name suggestions for category filters
/// - [templates] — template name suggestions for template filters
/// - [wikidataProperties] + [wikidataEntities] — the two-step lookup
///   behind a `haswbstatement:` filter: first resolve a property (P-code,
///   e.g. "location of creation" -> P1071), then resolve a value for it
///   (Q-code). [wikidataEntities] is also what backs the standalone
///   Depicts/P180 picker — same underlying Wikidata item search either way.
///
/// Every method is cached in-memory for [cacheTtl] (default 5 minutes).
/// Autocomplete traffic is bursty and highly repetitive — typing, then
/// backspacing back over the same prefixes — so this cuts real network
/// calls substantially with no staleness risk worth worrying about at this
/// TTL. Debouncing keystrokes is still the caller's job (a UI shouldn't
/// fire one request per keystroke); this cache is what happens *after*
/// that, for the requests that do go out.
class CommonsAutocomplete {
  CommonsAutocomplete({
    SearchService? service,
    this.cacheTtl = const Duration(minutes: 5),
  }) : _service = service ?? SearchService();

  final SearchService _service;
  final Duration cacheTtl;
  final Map<String, _CacheEntry<Object>> _cache = {};
  final Map<String, Future<Object>> _inFlight = {};

  Future<T> _cached<T extends Object>(
      String key, Future<T> Function() fetch) async {
    final hit = _cache[key];
    if (hit != null && !hit.isExpired) return hit.value as T;

    final pending = _inFlight[key];
    if (pending != null) return await pending as T;

    final request = fetch();
    _inFlight[key] = request;
    try {
      final value = await request;
      _cache[key] = _CacheEntry<T>(value, DateTime.now().add(cacheTtl));
      return value;
    } finally {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    }
  }

  /// Free-text query suggestions.
  Future<List<String>> queries(String text) {
    final query = text.trim();
    if (query.isEmpty) return Future.value(const []);
    return _cached(
      'q:$query',
      () => _service.searchTitleSuggestions(query),
    );
  }

  /// Category name suggestions.
  Future<List<String>> categories(String text) {
    final query = text.trim();
    if (query.isEmpty) return Future.value(const []);
    return _cached('c:$query', () => _service.searchCategories(query));
  }

  Future<List<String>> templates(String text) {
    final query = text.trim();
    if (query.isEmpty) return Future.value(const []);
    return _cached('t:$query', () => _service.searchTemplates(query));
  }

  /// Wikidata *properties* (P-codes) — first step of a haswbstatement:
  /// filter. P180 (depicts) and P275 (license) are excluded since those
  /// already have dedicated filters elsewhere in [SearchState].
  Future<List<DepictsEntity>> wikidataProperties(
    String text, {
    int limit = 8,
  }) {
    final query = text.trim();
    if (query.isEmpty) return Future.value(const []);
    return _cached(
      'p:$limit:$query',
      () => _service.searchWikidataProperties(query, limit: limit),
    );
  }

  /// Wikidata *items* (Q-codes) — the value step of a haswbstatement:
  /// filter once a property is chosen, and also what backs the standalone
  /// Depicts/P180 picker.
  Future<List<DepictsEntity>> wikidataEntities(
    String text, {
    int limit = 8,
  }) {
    final query = text.trim();
    if (query.isEmpty) return Future.value(const []);
    return _cached(
      'e:$limit:$query',
      () => _service.searchDepictsEntities(query, limit: limit),
    );
  }

  void clearCache() {
    _cache.clear();
  }
}
