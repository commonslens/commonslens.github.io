import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'commons_engine.dart';
import 'search_models.dart';
import 'backend_providers.dart';

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
/// - [imported]: not a fetch at all — a live view of whatever items are
///   currently sitting in the main search page's session, plotted here by
///   whatever coordinates they happen to carry (see
///   [SearchItem.hasCoordinates]). This is the "search → map" direction:
///   take what you already found and see where it is, as opposed to
///   [browse]/[filtered] which are "map → search": tap/draw somewhere and
///   find new things there.
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

  const MapViewState({
    this.mode = GeoMode.browse,
    this.session = const SearchSession(),
    this.filterState = const SearchState(),
    this.centerLat,
    this.centerLng,
    this.radiusMeters = 2000,
    this.boundingBox,
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
    );
  }
}

final mapSearchControllerProvider =
    NotifierProvider<MapSearchController, MapViewState>(
        MapSearchController.new);

/// Riverpod-facing wrapper around two live engines — [GeoBrowseSession] for
/// [GeoMode.browse] and [CommonsSearchSession] for [GeoMode.filtered] — plus
/// [GeoMode.imported], which has no engine and no stored session at all:
/// MapPage derives its plotted items live from searchControllerProvider on
/// every build while that mode is active (see _MapPageState.build), so
/// there is nothing here to fetch, cache, or keep in sync.
class MapSearchController extends Notifier<MapViewState> {
  late final GeoBrowseSession _browseEngine;
  late final CommonsSearchSession _filteredEngine;

  @override
  MapViewState build() {
    final backend = ref.watch(commonsBackendProvider);
    _browseEngine = GeoBrowseSession(backend: backend);
    _filteredEngine = CommonsSearchSession(backend: backend);
    return const MapViewState();
  }

  SearchSession _activeSessionFor(GeoMode mode) {
    switch (mode) {
      case GeoMode.browse:
        return _browseEngine.session;
      case GeoMode.filtered:
        return _filteredEngine.activeSession;
      case GeoMode.imported:
        // Placeholder only — see class doc. MapPage never reads
        // state.session while in this mode; it reads
        // searchControllerProvider directly instead.
        return const SearchSession();
    }
  }

  void _syncSession() {
    state = state.copyWith(session: _activeSessionFor(state.mode));
  }

  /// Switches to "search → map" display mode. Not a fetch and not a
  /// snapshot — MapPage reads the main search session live every build
  /// while this mode is active, so there is nothing here to keep in sync.
  void setMode(GeoMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, session: _activeSessionFor(mode));
  }

  /// Radius search around [lat]/[lng] against whichever engine
  /// [state.mode] currently points at — see [GeoMode] doc.
  Future<void> searchRadius(double lat, double lng, double radiusMeters) async {
    state = state.copyWith(
      mode: GeoMode.filtered,
      centerLat: lat,
      centerLng: lng,
      radiusMeters: radiusMeters,
      clearBoundingBox: true,
    );

    final nextFilter = state.filterState.copyWith(
      nearCoord:
          NearCoordFilter(lat: lat, lng: lng, radiusKm: radiusMeters / 1000),
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
    state = state.copyWith(
        mode: GeoMode.browse, boundingBox: box, clearPoint: true);
    final future = _browseEngine.searchBoundingBox(box);
    _syncSession();
    await future;
    _syncSession();
  }

  /// Next page for whichever engine is active. No-op in [GeoMode.imported]
  /// — pagination there is driven by paging the *main* search session
  /// instead (see MapPage's onLoadMore wiring), since imported mode has no
  /// fetch of its own to page.
  Future<void> loadMore() async {
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
