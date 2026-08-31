import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'commons_engine.dart';
import 'search_models.dart';

/// The map page's two geospatial modes — see [GeoBrowseSession] and
/// [CommonsBackend.geosearch] for the full rationale on why these are
/// genuinely different search mechanisms, not just a UI toggle:
///
/// - [browse]: pure `list=geosearch` — no relevance ranking, none of
///   [SearchState]'s other filters, distance-sorted (radius) or API-order
///   (bounding box). Fast, and the only mode that supports a true
///   rectangular bounding box (Cirrus has no bbox keyword).
/// - [filtered]: a normal [CommonsSearchSession] search with `nearCoord`
///   set on [SearchState] — every other filter (category, depicts,
///   license, quality, date, format...) still applies, ANDed with a
///   radius clause via CirrusSearch's `nearcoord:` keyword. Radius only;
///   no bounding-box equivalent exists in Cirrus.
enum GeoMode { browse, filtered }

class MapViewState {
  final GeoMode mode;
  final SearchSession session;

  /// Filters for [GeoMode.filtered] — everything a [SearchState] normally
  /// carries (categories, depicts, license, quality...) plus whatever
  /// `nearCoord` the last radius search set. Untouched in [GeoMode.browse].
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
    NotifierProvider<MapSearchController, MapViewState>(MapSearchController.new);

/// Riverpod-facing wrapper around two engines at once — [GeoBrowseSession]
/// for [GeoMode.browse] and [CommonsSearchSession] for [GeoMode.filtered] —
/// switched by [setMode]. Each engine keeps running independently; switching
/// modes just changes which one's [SearchSession] the UI is shown, so
/// flipping back to a mode you already searched in doesn't lose that
/// engine's results or continuation token.
class MapSearchController extends Notifier<MapViewState> {
  late final GeoBrowseSession _browseEngine;
  late final CommonsSearchSession _filteredEngine;

  @override
  MapViewState build() {
    _browseEngine = GeoBrowseSession();
    _filteredEngine = CommonsSearchSession();
    return const MapViewState();
  }

  SearchSession _activeSessionFor(GeoMode mode) =>
      mode == GeoMode.browse ? _browseEngine.session : _filteredEngine.activeSession;

  void _syncSession() {
    state = state.copyWith(session: _activeSessionFor(state.mode));
  }

  /// Switches which engine's results are shown. Does not re-run anything —
  /// each engine already holds its own last-run results independently.
  void setMode(GeoMode mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode, session: _activeSessionFor(mode));
  }

  /// Radius search around [lat]/[lng]. Runs against whichever engine
  /// [state.mode] currently points at — [GeoMode.browse] hits
  /// [GeoBrowseSession.searchRadius] directly; [GeoMode.filtered] sets
  /// `nearCoord` on the current [MapViewState.filterState] and re-runs the
  /// full [CommonsSearchSession] with every other active filter still
  /// applied.
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

  /// Bounding-box search over [box] = [northLat, westLng, southLat,
  /// eastLng]. Browse-mode only — CirrusSearch (and therefore
  /// [GeoMode.filtered]) has no bounding-box keyword, only a radius one
  /// (`nearcoord:`/`neartitle:`) — see [CommonsBackend.geosearch]. Calling
  /// this always switches to [GeoMode.browse] rather than silently no-op'ing
  /// in filtered mode.
  Future<void> searchBoundingBox(List<double> box) async {
    state = state.copyWith(mode: GeoMode.browse, boundingBox: box, clearPoint: true);
    final future = _browseEngine.searchBoundingBox(box);
    _syncSession();
    await future;
    _syncSession();
  }

  Future<void> loadMore() async {
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

  /// Applies a functional update to the filtered-mode [SearchState] (e.g.
  /// toggling a category or license from a filter sheet) and, if a point is
  /// already set, immediately re-runs the radius search with the new
  /// filters. If no point is set yet, this just stages the filters for
  /// whenever the person does tap the map.
  void updateFilters(SearchState Function(SearchState current) updater) {
    final next = updater(state.filterState);
    state = state.copyWith(filterState: next);
    if (state.mode == GeoMode.filtered && state.hasPoint) {
      searchRadius(state.centerLat!, state.centerLng!, state.radiusMeters);
    }
  }
}
