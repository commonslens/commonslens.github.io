import 'dart:math' as math;

import 'commons_backend.dart';
import 'search_models.dart';

/// A single, independent, stateful search "thread" for long-running
/// processes (a Flutter app, an agent loop) that would rather not carry a
/// continuation token around themselves. Thin wrapper over [CommonsBackend]
/// — all the actual fetch/filter/paginate work happens there; this class
/// only adds: remembering the current filters, remembering the
/// continuation token, and guarding against out-of-order responses when a
/// newer search starts before an older one resolves.
///
/// Every call to [search] always hits the backend — there is no caching
/// here. If you want to avoid a redundant re-fetch (e.g. restoring what a
/// user was just looking at when they switch back to a filter combo), that
/// caching decision belongs to the caller, not this class.
///
/// Create as many of these as you want — one per UI panel, one per agent
/// task, one per concurrent caller — they never share state with each
/// other.
///
/// If you're stateless (e.g. a JSON server handling independent HTTP
/// requests), skip this and call [CommonsBackend] directly instead — it
/// takes the continuation token as a plain argument and returns it as
/// plain data, no session object required.
///
/// Usage:
/// ```dart
/// final session = CommonsSearchSession();
/// final result = await session.search(SearchState(
///   queryText: 'eiffel tower',
///   licensePreset: LicensePreset.cc0,
/// ));
/// print(result.items.map((i) => i.title));
///
/// final more = await session.loadMore();
/// ```
class CommonsSearchSession {
  CommonsSearchSession({CommonsBackend? backend})
      : _backend = backend ?? CommonsBackend();

  final CommonsBackend _backend;
  int _generation = 0;

  SearchState _filterState = const SearchState();
  QueryBuildResult _lastBuiltQuery =
      const QueryBuildResult(srsearch: '', chips: [], debugPreview: '');
  SearchSession _activeSession = const SearchSession();

  /// The filters/query that produced [activeSession].
  SearchState get filterState => _filterState;

  /// Current results + pagination state for [filterState].
  SearchSession get activeSession => _activeSession;

  /// The CirrusSearch query string + UI-facing chips built from
  /// [filterState] — handy for debugging or for showing a human what a
  /// natural-language request actually resolved to.
  QueryBuildResult get lastBuiltQuery => _lastBuiltQuery;

  /// The stateless backend underneath, if you need direct access (e.g. to
  /// call [CommonsBackend.autocomplete] or [CommonsBackend.fetchItem]).
  CommonsBackend get backend => _backend;

  SearchSession _fromResult(MediaSearchResult result) {
    return SearchSession(
      items: result.items,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      hasSearched: true,
      loading: false,
      loadingMore: false,
      error: result.error,
      totalHits: result.totalHits,
      suggestion: result.suggestion,
    );
  }

  /// Runs a brand-new search, replacing [filterState] wholesale. Pass
  /// `filterState.copyWith(...)` to change just one thing and keep the
  /// rest. Always hits the backend — no stale results, ever. Returns once
  /// the first page has loaded (or failed) — check `.error` for failure,
  /// `.items` for results, `.hasMore` for whether [loadMore] will do
  /// anything.
  ///
  /// If [state] has no usable query or filters at all, this is a no-op:
  /// [filterState]/[lastBuiltQuery] still update to reflect it, but no
  /// network call is made and [activeSession] resets to the unsearched
  /// default — it never flips into an error state for doing nothing.
  Future<SearchSession> search(SearchState state) async {
    final generation = ++_generation;

    final built = _backend.buildQuery(state);
    _filterState = state;
    _lastBuiltQuery = built;

    if (built.srsearch.trim().isEmpty) {
      _activeSession = const SearchSession();
      return _activeSession;
    }

    _activeSession =
        const SearchSession().copyWith(hasSearched: true, loading: true);

    final result = await _backend.search(state);
    if (generation != _generation) return _activeSession; // superseded

    final session = _fromResult(result);
    _activeSession = session;
    return session;
  }

  /// Convenience for the common case: keep every current filter as-is and
  /// only change the free-text query.
  Future<SearchSession> searchText(String query) =>
      search(_filterState.copyWith(queryText: query.trim()));

  /// Fetches the next page for the current [filterState] and appends it to
  /// [activeSession], deduping by URL. No-op if already loading or if
  /// there's no further page.
  Future<SearchSession> loadMore() async {
    final current = _activeSession;
    if (current.loadingMore || !current.hasMore) return current;

    final generation = _generation;
    _activeSession = current.copyWith(loadingMore: true);

    final result = await _backend.search(
      _filterState,
      continueToken: current.continueParams,
    );
    if (generation != _generation) return _activeSession;

    if (result.error != null) {
      final failed = current.copyWith(loadingMore: false);
      _activeSession = failed;
      return failed;
    }

    final existingUrls = current.items.map((e) => e.url).toSet();
    final merged = [
      ...current.items,
      ...result.items.where((i) => !existingUrls.contains(i.url)),
    ];

    // Appending an already-sorted new page onto an already-sorted list
    // does not keep the combined list sorted for titleMatch (each page is
    // fetched in Cirrus's relevance order, then client-sorted alphabetically
    // per page — page 2 isn't guaranteed to alphabetically follow page 1).
    // No-op for every other sort mode, which stays correctly ordered by
    // construction (server-side gsrsort, or already merged correctly by
    // SearchService's fan-out).
    final sortedMerged = _filterState.sortMode == SortMode.relevance
        ? merged
        : _backend.applyClientSort(merged, _filterState.sortMode);

    final done = current.copyWith(
      items: sortedMerged,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      loadingMore: false,
      totalHits: result.totalHits,
      suggestion: result.suggestion,
    );
    _activeSession = done;
    return done;
  }
}

/// Paginated session for a single uploader's portfolio. Thin stateful
/// wrapper over [CommonsBackend.authorUploads] — same rationale as
/// [CommonsSearchSession]: remembers the continuation token so you don't
/// have to.
class AuthorPortfolioSession {
  AuthorPortfolioSession(this.username, {CommonsBackend? backend})
      : _backend = backend ?? CommonsBackend();

  final String username;
  final CommonsBackend _backend;
  int _generation = 0;
  SearchSession _session = const SearchSession();

  SearchSession get session => _session;

  /// Loads the first page. Safe to call more than once — a later call
  /// supersedes an earlier in-flight one.
  Future<SearchSession> load() async {
    final generation = ++_generation;
    _session = _session.copyWith(hasSearched: true, loading: true);

    final result = await _backend.authorUploads(username);
    if (generation != _generation) return _session;

    _session = SearchSession(
      items: result.items,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      hasSearched: true,
      loading: false,
      error: result.error,
    );
    return _session;
  }

  Future<SearchSession> loadMore() async {
    if (_session.loadingMore || !_session.hasMore) return _session;

    final generation = _generation;
    _session = _session.copyWith(loadingMore: true);

    final result = await _backend.authorUploads(
      username,
      continueToken: _session.continueParams,
    );
    if (generation != _generation) return _session;

    if (result.error != null) {
      _session = _session.copyWith(loadingMore: false);
      return _session;
    }

    final existingUrls = _session.items.map((e) => e.url).toSet();
    final merged = [
      ..._session.items,
      ...result.items.where((i) => !existingUrls.contains(i.url)),
    ];

    _session = _session.copyWith(
      items: merged,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      loadingMore: false,
    );
    return _session;
  }
}

/// Stateful wrapper over [CommonsBackend.geosearch] — same contract as
/// [CommonsSearchSession] (remembers the continuation token, guards
/// against out-of-order responses via a generation counter, dedupes
/// [loadMore] pages by URL) but for pure geographic browse (radius or
/// bounding box) rather than a CirrusSearch text/filter query.
///
/// This is a genuinely different mode from setting `nearCoord`/`nearTitle`
/// on a [SearchState] and running it through [CommonsSearchSession]: no
/// relevance ranking, none of [SearchState]'s other filters, distance-sorted
/// (radius mode) or API-order (bounding-box mode) results only — see
/// [CommonsBackend.geosearch] for the full rationale. Use this for "what's
/// physically in this area, full stop"; use `nearCoord` on a normal
/// [CommonsSearchSession] when you want location combined with category/
/// depicts/license/etc. filters.
///
/// **[loadMore] is here for the interface's sake, not because it usually
/// does anything.** Verified against GeoData's own source: the Elastic
/// backend Commons runs (`QueryGeoSearchElastic.php`) never emits a
/// `continue` token — it returns up to [CommonsBackend.geosearch]'s
/// `limit` (default 500, the documented anonymous ceiling) in one shot and
/// stops. [loadMore] still exists and still checks `hasMore` correctly, so
/// it does the right, safe thing (a no-op) against that reality, and would
/// pick up pagination automatically if a future GeoData version ever added
/// it — but don't build UI that expects it to reliably fetch a second page
/// today.
///
/// One session holds exactly one active area (either a radius search or a
/// bounding-box search, never both at once) — calling either search method
/// replaces whatever the other one had going.
class GeoBrowseSession {
  GeoBrowseSession({CommonsBackend? backend})
      : _backend = backend ?? CommonsBackend();

  final CommonsBackend _backend;
  int _generation = 0;

  double? _lat;
  double? _lng;
  double _radiusMeters = 1000;
  List<double>? _boundingBox;

  SearchSession _session = const SearchSession();

  SearchSession get session => _session;
  double? get lat => _lat;
  double? get lng => _lng;
  double get radiusMeters => _radiusMeters;
  List<double>? get boundingBox => _boundingBox;
  bool get isBoxMode => _boundingBox != null;

  SearchSession _fromResult(MediaSearchResult result) {
    return SearchSession(
      items: result.items,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      hasSearched: true,
      loading: false,
      loadingMore: false,
      error: result.error,
    );
  }

  /// Everything within [radiusMeters] of ([lat], [lng]), nearest first.
  /// [radiusMeters] is clamped to GeoData's own documented ceiling
  /// (10–10,000m) inside [CommonsBackend.geosearch]/[SearchService.geosearch]
  /// — passing something outside that range doesn't error, it just gets
  /// silently clamped there, same as the backend already does.
  Future<SearchSession> searchRadius(double lat, double lng, double radiusMeters) async {
    final generation = ++_generation;
    _lat = lat;
    _lng = lng;
    _radiusMeters = radiusMeters;
    _boundingBox = null;

    _session = const SearchSession().copyWith(hasSearched: true, loading: true);
    final result = await _backend.geosearch(lat: lat, lng: lng, radiusMeters: radiusMeters);
    if (generation != _generation) return _session;
    _session = _fromResult(result);
    return _session;
  }

  /// Everything inside the rectangle [box] = [northLat, westLng, southLat,
  /// eastLng] — see [CommonsBackend.geosearch] for why this, not
  /// nearcoord:/neartitle:, is the real bounding-box mechanism.
  ///
  /// **Tiled, not one request.** In practice, a single `ggsbbox` request
  /// against Commons stops returning matches once the box gets large
  /// (a whole city, for instance) — GeoData's own source (BoundingBox.php,
  /// QueryGeoSearchElastic.php) has no visible area check, so this is
  /// either an undocumented server-side limit or a timeout/result-scan cap
  /// that doesn't surface as an API error, just an empty result. Rather
  /// than chase the exact undocumented number, [box] is split into an
  /// n×n grid of smaller sub-boxes (n scales with the box's diagonal —
  /// a couple of nearby taps still costs one request, a city-sized box
  /// costs several, capped at 4×4), each queried independently via
  /// [Future.wait] and merged, deduped by URL — the same fan-out shape
  /// [SearchService] already uses for "+"-queries and union-mode filters,
  /// just applied to geography instead of query branches.
  Future<SearchSession> searchBoundingBox(List<double> box) async {
    final generation = ++_generation;
    _boundingBox = box;
    _lat = null;
    _lng = null;

    _session = const SearchSession().copyWith(hasSearched: true, loading: true);

    final gridSize = _gridSizeForBox(box);
    final tiles = _tileBoundingBox(box, gridSize);

    final results = await Future.wait(
      tiles.map((tile) => _backend.geosearch(boundingBox: tile)),
    );
    if (generation != _generation) return _session;

    final anySuccess = results.any((r) => r.error == null);
    if (!anySuccess) {
      _session = SearchSession(
        hasSearched: true,
        error: results.isNotEmpty ? results.first.error : 'Could not load nearby media.',
      );
      return _session;
    }

    final seenUrls = <String>{};
    final merged = <SearchItem>[];
    for (final result in results) {
      for (final item in result.items) {
        if (seenUrls.add(item.url)) merged.add(item);
      }
    }

    // hasMore stays false regardless of whether any individual tile came
    // back exactly at its own limit — see the class doc: this endpoint has
    // no continuation to hand a loadMore, tiled or not, so there's nothing
    // for hasMore=true to promise the caller.
    _session = SearchSession(
      items: merged,
      hasMore: false,
      hasSearched: true,
      loading: false,
    );
    return _session;
  }

  /// Rough great-circle distance in km — good enough to pick a tile grid
  /// size, not meant for anything precision-sensitive.
  static double _approxKmSpan(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    double toRad(double deg) => deg * math.pi / 180;
    final dLat = toRad(lat2 - lat1);
    final dLon = toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  /// Tuned against nothing more scientific than "a whole city needs to
  /// work" — the exact server-side threshold this works around is
  /// undocumented (see [searchBoundingBox]), so these breakpoints are a
  /// deliberately conservative approximation, not a measured constant.
  static int _gridSizeForBox(List<double> box) {
    final diagonalKm = _approxKmSpan(box[0], box[1], box[2], box[3]);
    if (diagonalKm <= 3) return 1;
    if (diagonalKm <= 12) return 2;
    if (diagonalKm <= 30) return 3;
    return 4;
  }

  static List<List<double>> _tileBoundingBox(List<double> box, int gridSize) {
    if (gridSize <= 1) return [box];
    final north = box[0], west = box[1], south = box[2], east = box[3];
    final latStep = (north - south) / gridSize;
    final lngStep = (east - west) / gridSize;
    final tiles = <List<double>>[];
    for (var row = 0; row < gridSize; row++) {
      for (var col = 0; col < gridSize; col++) {
        tiles.add([
          north - row * latStep,
          west + col * lngStep,
          north - (row + 1) * latStep,
          west + (col + 1) * lngStep,
        ]);
      }
    }
    return tiles;
  }

  /// Next page for whichever area is currently active (radius or box). No-op
  /// if already loading or there's no further page.
  Future<SearchSession> loadMore() async {
    final current = _session;
    if (current.loadingMore || !current.hasMore) return current;
    if (_lat == null && _boundingBox == null) return current;

    final generation = _generation;
    _session = current.copyWith(loadingMore: true);

    final result = await _backend.geosearch(
      lat: _lat,
      lng: _lng,
      radiusMeters: _radiusMeters,
      boundingBox: _boundingBox,
      continueToken: current.continueParams,
    );
    if (generation != _generation) return _session;

    if (result.error != null) {
      final failed = current.copyWith(loadingMore: false);
      _session = failed;
      return failed;
    }

    final existingUrls = current.items.map((e) => e.url).toSet();
    final merged = [
      ...current.items,
      ...result.items.where((i) => !existingUrls.contains(i.url)),
    ];

    final done = current.copyWith(
      items: merged,
      continueParams: result.continueToken,
      hasMore: result.hasMore,
      loadingMore: false,
    );
    _session = done;
    return done;
  }
}
