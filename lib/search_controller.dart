import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_models.dart';
import 'search_view_state.dart';
import 'search_url_codec.dart';
import 'commons_engine.dart';

final searchControllerProvider =
    NotifierProvider<SearchController, SearchViewState>(SearchController.new);

/// Riverpod-facing wrapper around [CommonsSearchSession] — every actual
/// fetch/filter/paginate decision lives in commonslens_core now; this class
/// only adapts that plain-Dart engine onto Riverpod's state notification
/// model so the existing widgets (search_page.dart,
/// advanced_filters_drawer.dart, asset_viewer.dart) keep working unchanged.
///
/// No caching here — every [search] call always hits the backend, matching
/// [CommonsSearchSession]'s own "always refresh" contract. Switching tabs
/// or filters back to a previously-used combination re-fetches rather than
/// restoring a stale cached result.
class SearchController extends Notifier<SearchViewState> {
  late final CommonsSearchSession _engine;

  @override
  SearchViewState build() {
    _engine = CommonsSearchSession();
    return SearchViewState(
      filterState: _engine.filterState,
      activeSession: _engine.activeSession,
      lastBuiltQuery: _engine.lastBuiltQuery,
    );
  }

  void _syncFromEngine() {
    state = state.copyWith(
      filterState: _engine.filterState,
      activeSession: _engine.activeSession,
      lastBuiltQuery: _engine.lastBuiltQuery,
    );
  }

  /// Restores filters from a shared/deep-link URL and runs the search.
  /// Safe to call unconditionally — if the resulting filters produce no
  /// usable query, [CommonsSearchSession.search] itself is a no-op (no
  /// network call, session resets to the unsearched default), so there's
  /// no need to pre-check emptiness here the way the old controller did.
  void hydrateFromUrl(Map<String, String> params) {
    if (params.isEmpty) return;
    final nextFilter =
        SearchUrlCodec.fromQueryParams(params, const SearchState());
    search(nextFilter.queryText, overrideState: nextFilter);
  }

  /// Runs a search. [overrideState], when given, replaces every filter at
  /// once (used when applying the filters drawer, removing a chip, or
  /// hydrating from a URL); otherwise only [query] changes and every other
  /// current filter is kept as-is — same contract every call site already
  /// relies on.
  Future<void> search(String query, {SearchState? overrideState}) async {
    final base = overrideState ?? state.filterState;
    final nextFilter = base.copyWith(queryText: query.trim());

    // CommonsSearchSession.search's synchronous prefix (everything up to
    // its first `await`) has already run by the time this line finishes,
    // so _engine's filterState/lastBuiltQuery/activeSession already reflect
    // the "loading" state — sync it immediately so the UI shows loading
    // (and updated chips) without waiting on the network round-trip.
    final future = _engine.search(nextFilter);
    _syncFromEngine();
    await future;
    _syncFromEngine();
  }

  Future<void> loadMore() async {
    final future = _engine.loadMore();
    _syncFromEngine();
    await future;
    _syncFromEngine();
  }

  /// Applies a functional update to the current filters (e.g. toggling a
  /// tab or format) and searches if anything actually changed.
  void applyFilterUpdate(SearchState Function(SearchState current) updater) {
    final nextFilter = updater(state.filterState);
    if (nextFilter == state.filterState) return;
    search(nextFilter.queryText, overrideState: nextFilter);
  }

  void saveScrollOffset(double offset) {
    state = state.copyWith(
      activeSession: state.activeSession.copyWith(scrollOffset: offset),
    );
  }
}

/// Paginated session for a single uploader's portfolio, keyed by username.
/// Thin Riverpod wrapper over [AuthorPortfolioSession] — same rationale as
/// [SearchController]: the actual fetch/paginate logic lives in
/// commonslens_core, this just adapts it onto Riverpod's family-provider
/// model so author_portfolio_page.dart and asset_viewer.dart keep working
/// unchanged.
final authorPortfolioProvider =
    NotifierProvider.family<AuthorPortfolioController, SearchSession, String>(
        AuthorPortfolioController.new);

class AuthorPortfolioController extends FamilyNotifier<SearchSession, String> {
  late final AuthorPortfolioSession _engine;

  @override
  SearchSession build(String username) {
    _engine = AuthorPortfolioSession(username);
    _loadInitial();
    return const SearchSession(hasSearched: true, loading: true);
  }

  Future<void> _loadInitial() async {
    state = await _engine.load();
  }

  Future<void> loadMore(String username) async {
    state = await _engine.loadMore();
  }
}
