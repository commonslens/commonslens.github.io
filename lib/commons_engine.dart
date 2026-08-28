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
