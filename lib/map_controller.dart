import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'commons_engine.dart';
import 'search_models.dart';

/// The map page's three geospatial modes:
///
/// - [browse]: pure `list=geosearch` — no relevance ranking, none of
///   [SearchState]'s other filters, distance-sorted (radius) or API-order
///   (bounding box). Also what backs a plain "what's physically near this
///   point" query with no filter intent (see [MapSearchController.browseRadius]).
/// - [filtered]: a normal [CommonsSearchSession] search with `nearCoord`
///   set on [SearchState] — every other filter (category, depicts,
///   license, quality, date, format...) still applies, ANDed with a
///   radius clause via CirrusSearch's `nearcoord:` keyword.
/// - [imported]: not a fetch at all — items already sitting in the main
///   search page's session, plotted here by whatever coordinates they
///   happen to carry (see [SearchItem.hasCoordinates]). This is the
///   "search → map" direction: take what you already found and see where
///   it is, as opposed to [browse]/[filtered] which are "map → search":
///   tap/draw somewhere and find new things there.
enum GeoMode { browse, filtered, imported }

class MapViewState {
  final GeoMode mode;
  final SearchSession session;

  /// Filters for [GeoMode.filtered] — everything a [SearchState] normally
  /// carries (categories, depicts, license, quality...) plus whatever
  /// `nearCoord` the last radius search set. Untouched in [GeoMode.browse]
  /// and [GeoMode.imported].
  final SearchState filterState;

  final double? centerLat;
  final double? centerLng;
  final double radiusMeters;
  final List<double>? boundingBox;

  /// The items currently plotted for [GeoMode.imported] — a snapshot of
  /// the main search page's results at the moment they were imported,
  /// filtered down to whichever ones actually carry coordinates. Persists
  /// across mode switches so flipping to browse/filtered and back doesn't
  /// lose it.
  final List<SearchItem> importedItems;

  const MapViewState({
    this.mode = GeoMode.browse,
    this.session = const SearchSession(),
    this.filterState = const SearchState(),
    this.centerLat,
    this.centerLng,
    this.radiusMeters = 2000,
    this.boundingBox,
    this.importedItems = const [],
  });

  bool get hasPoint => centerLat != null && centerLng != null;

  MapViewState copyWith({
    GeoMode? mode,
    SearchSession? session,
    SearchState? filterState,
    double? centerLat,
    double? centerLng,
    double? radiusMeters,
    List<double>? boundingBox,
    List<SearchItem>? importedItems,
    bool clearPoint = false,
    bool clearBoundingBox = false,
  }) {
    return MapViewState(
      mode: mode ?? this.mode,
      session: session ?? this.session,
      filterState: filterState ?? this.filterState,
      centerLat: clearPoint ? null : (centerLat ?? this.centerLat),
      centerLng: clearPoint ? null : (centerLng ?? this.centerLng),
      radiusMeters: radiusMeters ?? this.radiusMeters,
      boundingBox: clearBoundingBox ? null : (boundingBox ?? this.boundingBox),
      importedItems: importedItems ?? this.importedItems,
    );
  }
}

final mapSearchControllerProvider =
    NotifierProvider<MapSearchController, MapViewState>(MapSearchController.new);

/// Riverpod-facing wrapper around two live engines — [GeoBrowseSession] for
/// [GeoMode.browse] and [CommonsSearchSession] for [GeoMode.filtered] — plus
/// [GeoMode.imported], which has no engine at all: it's just whatever items
/// [importFromItems] was last handed, re-displayed with no network call.
class MapSearchController extends Notifier<MapViewState> {
  late final GeoBrowseSession _browseEngine;
  late final CommonsSearchSession _filteredEngine;

  @override
  MapViewState build() {
    _browseEngine = GeoBrowseSession();
    _filteredEngine = CommonsSearchSession();
    return const MapViewState();
  }

  SearchSession _importedSession(List<SearchItem> items) =>
      SearchSession(items: items, hasSearched: true);

  SearchSession _activeSessionFor(GeoMode mode) {
    switch (mode) {
      case GeoMode.browse:
        return _browseEngine.session;
      case GeoMode.filtered:
        return _filteredEngine.activeSession;
      case GeoMode.imported:
        return _importedSession(state.importedItems);
    }
  }

  void _syncSession() {
    state = state.copyWith(session: _activeSessionFor(state.mode));
  }

  /// Switches which engine's (or, for [GeoMode.imported], which snapshot's)
  /// results are shown. Does not re-run anything.
  void setMode(GeoMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, session: _activeSessionFor(mode));
  }

  /// "Search → map": plots [items] — normally the main search page's
  /// current results — by whatever coordinates they carry. Not a fetch;
  /// this is purely a client-side reinterpretation of data that already
  /// exists. Items without [SearchItem.hasCoordinates] are dropped from
  /// the plotted set (they simply can't go on a map), but nothing here
  /// touches the source those items came from.
  void importFromItems(List<SearchItem> items) {
    final withCoords = items.where((i) => i.hasCoordinates).toList();
    state = state.copyWith(
      mode: GeoMode.imported,
      importedItems: withCoords,
      session: _importedSession(withCoords),
      clearPoint: true,
      clearBoundingBox: true,
    );
  }

  /// Radius search around [lat]/[lng] against whichever engine
  /// [state.mode] currently points at — see [GeoMode] doc. Always leaves
  /// [GeoMode.imported] for [GeoMode.filtered] if the person was viewing
  /// imported results and then taps/enters coordinates.
  Future<void> searchRadius(double lat, double lng, double radiusMeters) async {
    state = state.copyWith(
      mode: GeoMode.filtered,
      centerLat: lat,
      centerLng: lng,
      radiusMeters: radiusMeters,
      clearBoundingBox: true,
    );

    final nextFilter = state.filterState.copyWith(
      nearCoord: NearCoordFilter(lat: lat, lng: lng, radiusKm: radiusMeters / 1000),
      clearNearTitle: true,
    );
    state = state.copyWith(filterState: nextFilter);
    final future = _filteredEngine.search(nextFilter);
    _syncSession();
    await future;
    _syncSession();
  }

  /// Pure geosearch radius search — bypasses CirrusSearch entirely (see
  /// [GeoBrowseSession.searchRadius]/[CommonsBackend.geosearch]), unlike
  /// [searchRadius] above, which ANDs `nearcoord:` onto every other active
  /// filter. No filter intent, just "what's physically near this point" —
  /// used by the asset viewer's "View Photos Clicked Nearby" action.
  Future<void> browseRadius(double lat, double lng, double radiusMeters) async {
    state = state.copyWith(
      mode: GeoMode.browse,
      centerLat: lat,
      centerLng: lng,
      radiusMeters: radiusMeters,
      clearBoundingBox: true,
    );
    final future = _browseEngine.searchRadius(lat, lng, radiusMeters);
    _syncSession();
    await future;
    _syncSession();
  }

  /// Bounding-box search over [box] = [northLat, westLng, southLat,
  /// eastLng]. Browse-mode only — see [CommonsBackend.geosearch]. Always
  /// switches to [GeoMode.browse].
  Future<void> searchBoundingBox(List<double> box) async {
    state = state.copyWith(mode: GeoMode.browse, boundingBox: box, clearPoint: true);
    final future = _browseEngine.searchBoundingBox(box);
    _syncSession();
    await future;
    _syncSession();
  }

  Future<void> loadMore() async {
    // Imported results are a static snapshot — there's nothing to page.
    if (state.mode == GeoMode.imported) return;

    if (state.mode == GeoMode.browse) {
      final future = _browseEngine.loadMore();
      _syncSession();
      await future;
      _syncSession();
    } else {
      final future = _filteredEngine.loadMore();
      _syncSession();
      await future;
      _syncSession();
    }
  }

  /// Applies a functional update to the filtered-mode [SearchState] and,
  /// if a point is already set, immediately re-runs the radius search with
  /// the new filters.
  void updateFilters(SearchState Function(SearchState current) updater) {
    final next = updater(state.filterState);
    state = state.copyWith(filterState: next);
    if (state.mode == GeoMode.filtered && state.hasPoint) {
      searchRadius(state.centerLat!, state.centerLng!, state.radiusMeters);
    }
  }
}