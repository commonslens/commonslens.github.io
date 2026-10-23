import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_models.dart';
import 'search_view_state.dart';
import 'search_url_codec.dart';
import 'commons_engine.dart';
import 'commons_backend.dart';
import 'backend_providers.dart';

/// Every Wikimedia page (any language, any project) currently embedding a
/// given file — see [CommonsBackend.globalUsage]. Keyed by file title,
/// deliberately a plain [FutureProvider.family] rather than something
/// eagerly populated alongside the rest of a [SearchItem]: this needs no
/// auth and is cheap, but it's still one extra request per file, and most
/// files in a results grid are never opened. Riverpod only calls the
/// fetch function the first time something actually watches a given
/// title — i.e. only once the asset viewer's Global Usage section is
/// expanded for that file — and caches the result for the life of the
/// provider container after that.
final globalUsageProvider =
    FutureProvider.family<List<GlobalUsageEntry>, String>((ref, fileTitle) {
  return ref.watch(commonsBackendProvider).globalUsage(fileTitle);
});

/// A file's full Structured Data on Commons entity — captions plus every
/// claim (creator, institution, depicts, coordinates of depicted place,
/// etc.) — see [CommonsBackend.structuredData]. Same lazy,
/// fetch-only-when-watched contract as [globalUsageProvider]: SearchItem
/// itself never carries depicts or other SDC statements (those live in a
/// separate Wikibase entity, not the extmetadata block SearchItem is
/// built from), so this is what actually backs the asset viewer's
/// Structured Data section.
final structuredDataProvider =
    FutureProvider.family<StructuredDataResult?, String>((ref, fileTitle) {
  return ref.watch(commonsBackendProvider).structuredData(fileTitle);
});

/// Files CirrusSearch considers similar to [fileTitle], via its own
/// `morelike:` keyword (see SearchService.buildQuery / SearchState.
/// morelikeTitles) — the same mechanism the advanced filters drawer
/// already exposes as a search input, here run as a one-off single-file
/// query instead. Same lazy, fetch-only-when-watched contract as
/// [globalUsageProvider]/[structuredDataProvider]. CirrusSearch's
/// similarity engine occasionally echoes the source file back in its own
/// results — filtered out here so "related to this file" never lists the
/// file itself.
final morelikeProvider =
    FutureProvider.family<List<SearchItem>, String>((ref, fileTitle) async {
  final result = await ref.watch(commonsBackendProvider).search(
        SearchState(morelikeTitles: {fileTitle}),
      );
  final normalized = fileTitle.replaceFirst('File:', '').trim().toLowerCase();
  return result.items
      .where((i) =>
          i.title.replaceFirst('File:', '').trim().toLowerCase() != normalized)
      .toList();
});

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
  bool _showingExternalResults = false;

  @override
  SearchViewState build() {
    _engine = CommonsSearchSession(backend: ref.watch(commonsBackendProvider));
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

  /// Makes the search surface exactly match a shared/deep-link URL.
  ///
  /// This deliberately also hydrates an empty parameter map. Browser Back
  /// from `/?q=...` to `/` must clear the old filters and results; treating
  /// an empty URL as "nothing to do" leaves stale content underneath a URL
  /// that no longer describes it. [CommonsSearchSession.search] resets an
  /// empty [SearchState] synchronously without making a network request and
  /// increments its generation, so an older in-flight response cannot put
  /// the stale search back afterward.
  Future<void> hydrateFromUrl(Map<String, String> params) {
    final nextFilter =
        SearchUrlCodec.fromQueryParams(params, const SearchState());
    return search(nextFilter.queryText, overrideState: nextFilter);
  }

  /// Runs a search. [overrideState], when given, replaces every filter at
  /// once (used when applying the filters drawer, removing a chip, or
  /// hydrating from a URL); otherwise only [query] changes and every other
  /// current filter is kept as-is — same contract every call site already
  /// relies on.
  Future<void> search(String query, {SearchState? overrideState}) async {
    _showingExternalResults = false;
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
    if (_showingExternalResults) return;
    // Scroll notifications can arrive many times per frame near the bottom
    // of a web grid. Avoid publishing two otherwise-identical provider
    // states for every one of those notifications while a page is already
    // loading (or after pagination has finished). The engine has the same
    // safety guard, but checking here matters because _syncFromEngine below
    // creates a new SearchViewState and would still rebuild the whole search
    // surface even when the engine correctly did no work.
    final session = state.activeSession;
    if (session.loading || session.loadingMore || !session.hasMore) return;

    final future = _engine.loadMore();
    _syncFromEngine();
    await future;
    _syncFromEngine();
  }

  /// Applies a functional update to the current filters (e.g. toggling a
  /// tab or format) and searches if anything actually changed.
  ///
  /// The drawer's category/depicts/template/statement pickers,
  /// license/quality dropdowns, and the search page's tab/format toggles all
  /// call this rather than mutating state directly.
  void applyFilterUpdate(SearchState Function(SearchState current) updater) {
    final current = state.filterState;
    final nextFilter = updater(current);
    if (nextFilter == current) return;
    search(nextFilter.queryText, overrideState: nextFilter);
  }

  void saveScrollOffset(double offset) {
    state = state.copyWith(
      activeSession: state.activeSession.copyWith(scrollOffset: offset),
    );
  }

  /// Displays an externally-produced result set (currently: a Pipeline
  /// sink's materialized output — see pipeline_controller.dart's
  /// sendToSearch) in the main search grid, without running a
  /// CirrusSearch query for it. There's no "next page" for a set that may
  /// already be a merge/dedupe/sort of several independent branches, so
  /// this is presented as a complete, non-paginated result (`hasMore:
  /// false`).
  ///
  /// `_engine.search(const SearchState())` first resets the underlying
  /// [CommonsSearchSession] to its default — per its own documented
  /// contract, an empty query is a synchronous, network-free no-op (see
  /// commons_engine.dart), so this costs nothing and just ensures a
  /// subsequent [loadMore] call (which reads `_engine`'s own internal
  /// session, not this method's injected one) sees `hasMore: false`
  /// rather than whatever a previous real search happened to leave behind.
  /// `_syncFromEngine()` then clears the visible filter chips/query bar to
  /// match that reset, since pipeline results don't correspond to a
  /// single filterState the UI could otherwise misleadingly keep showing.
  void loadExternalResults(List<SearchItem> items) {
    _showingExternalResults = true;
    _engine.search(const SearchState());
    _syncFromEngine();
    state = state.copyWith(
      activeSession:
          SearchSession(items: items, hasSearched: true, hasMore: false),
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
  SearchSession build(String arg) {
    _engine = AuthorPortfolioSession(
      arg,
      backend: ref.watch(commonsBackendProvider),
    );
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
