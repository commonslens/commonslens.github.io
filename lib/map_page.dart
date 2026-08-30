import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'map_controller.dart';
import 'search_components.dart';
import 'search_models.dart';
import 'search_page.dart' show selectionModeProvider, selectedItemsProvider;
import 'search_url_codec.dart';

/// How a map tap is currently interpreted:
/// - [point]: sets/moves the radius-search center. A tap immediately fires
///   a search at the current radius; the slider then re-searches on release.
/// - [box]: two taps define opposite corners of a rectangle — the first
///   tap places a pending corner marker, the second completes the
///   rectangle and fires a bounding-box search (browse mode only, see
///   [MapSearchController.searchBoundingBox]).
enum _TapMode { point, box }

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final MapController _mapController = MapController();

  _TapMode _tapMode = _TapMode.point;
  ll.LatLng? _pendingBoxCorner;

  // Buffered locally so dragging the slider redraws the preview circle on
  // every frame without firing a network request per pixel — the actual
  // searchRadius() call only fires in onChangeEnd.
  double _draggingRadiusMeters = 2000;
  double _currentZoom = 2;
  double _currentRotation = 0;

  static const double _minZoom = 2;
  static const double _maxZoom = 19;

  @override
  void initState() {
    super.initState();
    final state = ref.read(mapSearchControllerProvider);
    _draggingRadiusMeters = state.radiusMeters;
  }

  void _handleTap(ll.LatLng point) {
    if (_tapMode == _TapMode.box) {
      final pending = _pendingBoxCorner;
      if (pending == null) {
        setState(() => _pendingBoxCorner = point);
        return;
      }
      final north = math.max(pending.latitude, point.latitude);
      final south = math.min(pending.latitude, point.latitude);
      final west = math.min(pending.longitude, point.longitude);
      final east = math.max(pending.longitude, point.longitude);
      setState(() {
        _pendingBoxCorner = null;
        _tapMode = _TapMode.point; // back to point mode once the box lands
      });
      ref.read(mapSearchControllerProvider.notifier).searchBoundingBox(
            [north, west, south, east],
          );
      return;
    }

    ref
        .read(mapSearchControllerProvider.notifier)
        .searchRadius(point.latitude, point.longitude, _draggingRadiusMeters);
  }

  /// `camera.visibleBounds` always returns an axis-aligned box (north,
  /// west, south, east) regardless of the map's current rotation — that
  /// part is never a problem for Wikimedia's `ggsbbox`, which only ever
  /// accepts a horizontal rectangle. But when the map IS rotated, that
  /// axis-aligned box is the enclosing rectangle around the actual
  /// (diamond-shaped, on screen) rotated viewport — bigger than what's
  /// visually on screen. Snapping to north-up first, right before reading
  /// visibleBounds, means "search this area" always searches exactly the
  /// rectangle the person can see, not a superset of it. `rotate()` is
  /// synchronous (not animated), so visibleBounds is already correct on
  /// the very next line.
  void _searchThisArea() {
    if (_currentRotation != 0) {
      _mapController.rotate(0);
    }
    final bounds = _mapController.camera.visibleBounds;
    ref.read(mapSearchControllerProvider.notifier).searchBoundingBox([
      bounds.north,
      bounds.west,
      bounds.south,
      bounds.east,
    ]);
  }

  void _openItem(SearchItem item, MapViewState state) {
    if (state.mode == GeoMode.filtered) {
      // Filtered-mode results came from a real nearCoord + filters
      // CirrusSearch query — reuse the exact same URL-hydration path the
      // main search page already uses, so the asset viewer opens with the
      // full swipeable gallery of these same map results, not just a
      // single standalone file.
      final params = <String, String>{
        'id': item.title,
        ...SearchUrlCodec.toQueryParams(state.filterState),
      };
      context.push(Uri(path: '/view', queryParameters: params).toString());
    } else {
      // Browse mode is a pure geosearch, not a CirrusSearch query — there's
      // no SearchState that reproduces this exact result set, so this
      // opens as a standalone single-file view rather than a swipeable
      // gallery over the map's own results.
      context.push(Uri(path: '/view', queryParameters: {'id': item.title}).toString());
    }
  }

  /// Hands the current map results off to the main search page, where
  /// every other filter (category, depicts, license, quality, date,
  /// format...) becomes available.
  ///
  /// - Filtered mode: trivial — [MapViewState.filterState] already IS a
  ///   real [SearchState] with `nearCoord` set, so this is exactly the
  ///   query the main page's [CommonsSearchSession] would run itself.
  /// - Browse mode, radius: approximated as the same `nearCoord` filter,
  ///   since `nearcoord:` is a genuine CirrusSearch keyword — this won't
  ///   reproduce the exact same result set (CirrusSearch relevance
  ///   ranking applies, browse mode's pure distance sort doesn't carry
  ///   over), but it's the same real geographic area with full filtering
  ///   now available on top.
  /// - Browse mode, bounding box: CirrusSearch has no bounding-box
  ///   keyword at all (see [CommonsBackend.geosearch]) — there is no exact
  ///   equivalent to hand off. This approximates the box as a circle
  ///   around its center, sized to cover every corner, and says so.
  void _openInMainSearch(MapViewState state) {
    SearchState target;

    if (state.mode == GeoMode.filtered) {
      if (!state.session.hasSearched) return;
      target = state.filterState;
    } else if (state.hasPoint) {
      target = SearchState(
        nearCoord: NearCoordFilter(
          lat: state.centerLat!,
          lng: state.centerLng!,
          radiusKm: state.radiusMeters / 1000,
        ),
      );
    } else if (state.boundingBox != null) {
      final box = state.boundingBox!; // [northLat, westLng, southLat, eastLng]
      final center = ll.LatLng((box[0] + box[2]) / 2, (box[1] + box[3]) / 2);
      final corner = ll.LatLng(box[0], box[1]);
      final coveringRadiusMeters =
          const ll.Distance().as(ll.LengthUnit.Meter, center, corner);
      target = SearchState(
        nearCoord: NearCoordFilter(
          lat: center.latitude,
          lng: center.longitude,
          radiusKm: coveringRadiusMeters / 1000,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'CirrusSearch has no bounding-box keyword, so this opens as a '
          'circular radius covering the box instead of the box itself.',
        ),
      ));
    } else {
      return;
    }

    final params = SearchUrlCodec.toQueryParams(target);
    context.go(Uri(path: '/', queryParameters: params.isEmpty ? null : params).toString());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapSearchControllerProvider);
    final session = state.session;
    final plottable = session.items.where((i) => i.hasCoordinates).toList();
    final clusters = _clusterItems(plottable, _currentZoom);

    // _ResultsSheet is a DraggableScrollableSheet with initialChildSize:
    // 0.32 (see its class below) — that's 200-300px on a typical phone,
    // well past the old hardcoded `bottom: 128`. Since the sheet is added
    // to the Stack after (i.e. on top of) the radius slider, it was
    // visually covering the slider — and swallowing its drag gestures —
    // any time results were showing. Anchoring to the sheet's actual
    // collapsed height keeps the slider sitting just above it instead.
    const resultsSheetInitialFraction = 0.32;
    final resultsSheetHeight =
        MediaQuery.of(context).size.height * resultsSheetInitialFraction;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'GEOSPATIAL BROWSE',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (state.mode == GeoMode.filtered)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Filters',
              onPressed: () => _showFilterSheet(context),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const ll.LatLng(20, 0),
              initialZoom: 2,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              // Explicit rather than relying on the default, so it's clear
              // pan/pinch-zoom/two-finger-rotate are all deliberately on —
              // the on-screen controls below are an addition for
              // mouse-only/desktop use, not a replacement for these.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onTap: (_, point) => _handleTap(point),
              onPositionChanged: (camera, hasGesture) {
                if (camera.zoom != _currentZoom ||
                    camera.rotation != _currentRotation) {
                  setState(() {
                    _currentZoom = camera.zoom;
                    _currentRotation = camera.rotation;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.commonslens.app',
                maxZoom: 19,
              ),
              if (state.boundingBox != null)
                PolygonLayer(polygons: [
                  Polygon(
                    points: [
                      ll.LatLng(state.boundingBox![0], state.boundingBox![1]),
                      ll.LatLng(state.boundingBox![0], state.boundingBox![3]),
                      ll.LatLng(state.boundingBox![2], state.boundingBox![3]),
                      ll.LatLng(state.boundingBox![2], state.boundingBox![1]),
                    ],
                    color: const Color(0xFF3D7EFF).withOpacity(0.15),
                    borderColor: const Color(0xFF3D7EFF),
                    borderStrokeWidth: 2,
                  ),
                ]),
              if (state.hasPoint)
                CircleLayer(circles: [
                  CircleMarker(
                    point: ll.LatLng(state.centerLat!, state.centerLng!),
                    radius: _tapMode == _TapMode.point
                        ? _draggingRadiusMeters
                        : state.radiusMeters,
                    useRadiusInMeter: true,
                    color: const Color(0xFF3D7EFF).withOpacity(0.12),
                    borderColor: const Color(0xFF3D7EFF),
                    borderStrokeWidth: 2,
                  ),
                ]),
              if (_pendingBoxCorner != null)
                MarkerLayer(markers: [
                  Marker(
                    point: _pendingBoxCorner!,
                    width: 16,
                    height: 16,
                    child: const _CornerDot(),
                  ),
                ]),
              if (state.hasPoint)
                MarkerLayer(markers: [
                  Marker(
                    point: ll.LatLng(state.centerLat!, state.centerLng!),
                    width: 14,
                    height: 14,
                    child: const _CenterDot(),
                  ),
                ]),
              MarkerLayer(
                markers: clusters
                    .map((c) => Marker(
                          point: c.center,
                          width: c.items.length > 1 ? 44 : 34,
                          height: c.items.length > 1 ? 44 : 34,
                          child: _ClusterMarker(
                            cluster: c,
                            onTap: () => c.items.length == 1
                                ? _openItem(c.items.first, state)
                                : _showClusterSheet(context, c, state),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),

          // Top overlay — mode toggle + draw-box toggle + search-this-area.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                Expanded(
                  child: _PillToggle(
                    left: 'Browse',
                    right: 'Filtered',
                    selectedLeft: state.mode == GeoMode.browse,
                    onSelectLeft: () => ref
                        .read(mapSearchControllerProvider.notifier)
                        .setMode(GeoMode.browse),
                    onSelectRight: () => ref
                        .read(mapSearchControllerProvider.notifier)
                        .setMode(GeoMode.filtered),
                  ),
                ),
                const SizedBox(width: 8),
                _OverlayIconButton(
                  icon: Icons.radio_button_checked,
                  active: _tapMode == _TapMode.point,
                  tooltip: 'Search a radius around a point',
                  onTap: () => setState(() {
                    _tapMode = _TapMode.point;
                    _pendingBoxCorner = null;
                  }),
                ),
                const SizedBox(width: 8),
                _OverlayIconButton(
                  icon: Icons.crop_square,
                  active: _tapMode == _TapMode.box,
                  tooltip: 'Draw bounding box (2 taps)',
                  onTap: () => setState(() {
                    _tapMode = _TapMode.box;
                    _pendingBoxCorner = null;
                  }),
                ),
                const SizedBox(width: 8),
                _OverlayIconButton(
                  icon: Icons.my_location,
                  tooltip: 'Search this area',
                  onTap: _searchThisArea,
                ),
              ],
            ),
          ),

          if (_tapMode == _TapMode.box)
            Positioned(
              top: 64,
              left: 12,
              right: 12,
              child: _HintBanner(
                text: _pendingBoxCorner == null
                    ? 'Tap the map to place the first corner of the box.'
                    : 'Tap again to place the opposite corner.',
              ),
            ),

          if (_tapMode == _TapMode.point && !state.hasPoint)
            const Positioned(
              top: 64,
              left: 12,
              right: 12,
              child: _HintBanner(
                text: 'Tap anywhere on the map to search a radius around that point.',
              ),
            ),

          if (session.loading)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF3D7EFF)),
              ),
            ),

          // Zoom / rotate cluster — pan itself needs no button (drag/flick
          // are already on via interactionOptions above); this covers the
          // two things a mouse-only/desktop user has no gesture for.
          // Fixed offset rather than anchored to the hint banner (which is
          // conditional and variable-height) — 130 clears both the top
          // pill-toggle row and a two-line hint comfortably.
          Positioned(
            top: 130,
            right: 12,
            child: _MapNavigationControls(
              mapController: _mapController,
              currentRotation: _currentRotation,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
            ),
          ),

          // Bottom overlay — radius slider (point mode + a point set only).
          if (_tapMode == _TapMode.point && state.hasPoint)
            Positioned(
              left: 12,
              right: 12,
              bottom: session.hasSearched ? resultsSheetHeight + 16 : 24,
              child: _RadiusControl(
                meters: _draggingRadiusMeters,
                onChanged: (v) => setState(() => _draggingRadiusMeters = v),
                onChangeEnd: (v) {
                  setState(() => _draggingRadiusMeters = v);
                  ref.read(mapSearchControllerProvider.notifier).searchRadius(
                      state.centerLat!, state.centerLng!, v);
                },
              ),
            ),

          if (session.hasSearched)
            Positioned.fill(
              child: _ResultsSheet(
                session: session,
                plottableCount: plottable.length,
                onLoadMore: () =>
                    ref.read(mapSearchControllerProvider.notifier).loadMore(),
                onOpenInMainSearch: () => _openInMainSearch(state),
                searchState: state.mode == GeoMode.filtered
                    ? state.filterState
                    : const SearchState(),
              ),
            ),
        ],
      ),
    );
  }

  void _showClusterSheet(BuildContext context, _MarkerCluster cluster, MapViewState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text('${cluster.items.length} FILES AT THIS SPOT',
                      style: const TextStyle(
                          color: Color(0xFF7A7A7A),
                          fontSize: 11,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 160,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.85),
                    itemCount: cluster.items.length,
                    itemBuilder: (context, i) {
                      final item = cluster.items[i];
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(context).pop();
                          _openItem(item, state);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(item.thumb, fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFilterSheet(BuildContext context) {
    final notifier = ref.read(mapSearchControllerProvider.notifier);
    final current = ref.read(mapSearchControllerProvider).filterState;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        LicensePreset license = current.licensePreset;
        QualityFilter quality = current.qualityFilter;
        final queryCtrl = TextEditingController(text: current.queryText);

        return StatefulBuilder(builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FILTERED SEARCH',
                    style: TextStyle(
                        color: Color(0xFF7A7A7A),
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Combined with a radius around wherever you tap next — every '
                  'other filter here rides along, same as the main search.',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 11.5, height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: queryCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    hintText: 'Optional text query…',
                    hintStyle: const TextStyle(color: Colors.white30),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<LicensePreset>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  value: license,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  items: LicensePreset.values
                      .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(licensePresetLabel(p),
                              style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => license = v ?? license),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<QualityFilter>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  value: quality,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  items: QualityFilter.values
                      .map((q) => DropdownMenuItem(
                          value: q,
                          child: Text(qualityFilterLabel(q),
                              style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => quality = v ?? quality),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D7EFF),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      notifier.updateFilters((s) => s.copyWith(
                            queryText: queryCtrl.text.trim(),
                            licensePreset: license,
                            qualityFilter: quality,
                          ));
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Lightweight, self-contained marker clustering — grid-bucket items by
// rounding lat/lng into cells whose size shrinks as zoom increases (roughly
// constant on-screen size regardless of zoom level), rather than pulling in
// a separate clustering package whose marker-widget API might not line up
// with whatever flutter_map version this project pins. Recomputed on every
// build; cheap enough for the result-set sizes a single geosearch/CirrusSearch
// page returns (at most a few hundred items).
// -----------------------------------------------------------------------------

class _MarkerCluster {
  final ll.LatLng center;
  final List<SearchItem> items;
  const _MarkerCluster({required this.center, required this.items});
}

List<_MarkerCluster> _clusterItems(List<SearchItem> items, double zoom) {
  if (items.isEmpty) return const [];

  // Degrees-per-cell halves with every zoom level, tuned so clusters read
  // as roughly a fixed pixel radius on screen at any zoom rather than
  // covering a fixed geographic area.
  final cellSize = 40 / math.pow(2, zoom).clamp(0.0005, 40);

  final buckets = <String, List<SearchItem>>{};
  for (final item in items) {
    final lat = item.resolvedLatitude;
    final lng = item.resolvedLongitude;
    if (lat == null || lng == null) continue;
    final key = '${(lat / cellSize).round()}:${(lng / cellSize).round()}';
    buckets.putIfAbsent(key, () => []).add(item);
  }

  return buckets.values.map((group) {
    final lat = group.map((i) => i.resolvedLatitude!).reduce((a, b) => a + b) /
        group.length;
    final lng = group.map((i) => i.resolvedLongitude!).reduce((a, b) => a + b) /
        group.length;
    return _MarkerCluster(center: ll.LatLng(lat, lng), items: group);
  }).toList();
}

// -----------------------------------------------------------------------------
// Small presentational widgets
// -----------------------------------------------------------------------------

class _ClusterMarker extends StatelessWidget {
  final _MarkerCluster cluster;
  final VoidCallback onTap;
  const _ClusterMarker({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = cluster.items.length;
    final isCluster = count > 1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCluster
              ? const Color(0xFF3D7EFF)
              : const Color(0xFF1A1A1A),
          border: Border.all(
              color: isCluster ? Colors.white : const Color(0xFF3D7EFF),
              width: 2),
        ),
        alignment: Alignment.center,
        child: isCluster
            ? Text('$count',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
            : ClipOval(
                child: Image.network(
                  cluster.items.first.thumb,
                  fit: BoxFit.cover,
                  width: 34,
                  height: 34,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.image, size: 16, color: Colors.white54),
                ),
              ),
      ),
    );
  }
}

class _CenterDot extends StatelessWidget {
  const _CenterDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3D7EFF),
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}

class _CornerDot extends StatelessWidget {
  const _CornerDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFF3D7EFF), width: 2),
      ),
    );
  }
}

class _PillToggle extends StatelessWidget {
  final String left;
  final String right;
  final bool selectedLeft;
  final VoidCallback onSelectLeft;
  final VoidCallback onSelectRight;

  const _PillToggle({
    required this.left,
    required this.right,
    required this.selectedLeft,
    required this.onSelectLeft,
    required this.onSelectRight,
  });

  @override
  Widget build(BuildContext context) {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF3D7EFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFAAAAAA),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        children: [
          segment(left, selectedLeft, onSelectLeft),
          segment(right, !selectedLeft, onSelectRight),
        ],
      ),
    );
  }
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _OverlayIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF3D7EFF) : const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? const Color(0xFF3D7EFF) : const Color(0xFF242424)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _HintBanner extends StatelessWidget {
  final String text;
  const _HintBanner({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withOpacity(0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3D7EFF)),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 12.5)),
    );
  }
}

/// Zoom in/out + rotate left/right + a compass that doubles as a
/// reset-to-north button — all built on [MapController]'s own inbuilt
/// `move`/`rotate` methods (no extra flutter_map plugin needed). State
/// isn't tracked here: every call goes through [MapController], and
/// [_MapPageState]'s own `onPositionChanged` (already wired up for
/// clustering) picks up the resulting camera change and rebuilds this
/// widget with the new rotation for the compass needle.
class _MapNavigationControls extends StatelessWidget {
  final MapController mapController;
  final double currentRotation;
  final double minZoom;
  final double maxZoom;

  const _MapNavigationControls({
    required this.mapController,
    required this.currentRotation,
    required this.minZoom,
    required this.maxZoom,
  });

  void _zoomBy(double delta) {
    final camera = mapController.camera;
    final nextZoom = (camera.zoom + delta).clamp(minZoom, maxZoom);
    mapController.move(camera.center, nextZoom);
  }

  void _rotateBy(double degrees) {
    mapController.rotate(mapController.camera.rotation + degrees);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withOpacity(0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavButton(
              icon: Icons.add, tooltip: 'Zoom in', onTap: () => _zoomBy(1)),
          const _NavDivider(),
          _NavButton(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onTap: () => _zoomBy(-1)),
          const _NavDivider(),
          _NavButton(
              icon: Icons.rotate_left,
              tooltip: 'Rotate left',
              onTap: () => _rotateBy(-15)),
          const _NavDivider(),
          _NavButton(
              icon: Icons.rotate_right,
              tooltip: 'Rotate right',
              onTap: () => _rotateBy(15)),
          const _NavDivider(),
          // Needle counter-rotates against the map's own bearing so it
          // keeps pointing at true geographic north regardless of how the
          // map itself is rotated — standard compass convention. Tapping
          // it snaps the map back to north-up (bearing 0).
          Tooltip(
            message: 'Reset to north',
            child: InkWell(
              onTap: () => mapController.rotate(0),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Transform.rotate(
                    angle: -currentRotation * (math.pi / 180),
                    child: const Icon(Icons.explore,
                        size: 19, color: Color(0xFF3D7EFF)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 18, color: Colors.white70),
        ),
      ),
    );
  }
}

class _NavDivider extends StatelessWidget {
  const _NavDivider();
  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: const Color(0xFF242424));
}

class _RadiusControl extends StatelessWidget {
  final double meters;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _RadiusControl({
    required this.meters,
    required this.onChanged,
    required this.onChangeEnd,
  });

  String _label(double m) {
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
    return '${m.round()} m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414).withOpacity(0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        children: [
          const Icon(Icons.radio_button_unchecked,
              size: 16, color: Color(0xFF3D7EFF)),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF3D7EFF),
                inactiveTrackColor: const Color(0xFF2A2A2A),
                thumbColor: const Color(0xFF3D7EFF),
                overlayColor: const Color(0xFF3D7EFF).withOpacity(0.2),
                trackHeight: 2,
              ),
              child: Slider(
                // GeoData's own documented radius ceiling — see
                // SearchService.geosearch — matched here so the slider can
                // never request something the backend would silently clamp.
                min: 10,
                max: 10000,
                value: meters.clamp(10, 10000),
                onChanged: onChanged,
                onChangeEnd: onChangeEnd,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(_label(meters),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// Draggable-feeling (fixed-height, scrollable) results strip at the
/// bottom of the map — reuses [MediaCard] so map results look and behave
/// exactly like the main search grid (selection mode, hover states,
/// lazy-loaded thumbnails) rather than a second bespoke card widget.
/// Draggable results panel at the bottom of the map — reuses [MediaCard]
/// with the exact same grid sizing [SearchPage]/[AuthorPortfolioPage] use
/// (`maxCrossAxisExtent: 280`, `childAspectRatio: 0.85`) rather than a
/// custom-sized filmstrip cell, so cards render identically everywhere in
/// the app instead of being squeezed into a size MediaCard wasn't built
/// for. Draggable (not a fixed height) so a screenful of results has room
/// without permanently eating map space.
class _ResultsSheet extends StatelessWidget {
  final SearchSession session;
  final int plottableCount;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenInMainSearch;
  final SearchState searchState;

  const _ResultsSheet({
    required this.session,
    required this.plottableCount,
    required this.onLoadMore,
    required this.onOpenInMainSearch,
    required this.searchState,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.32,
      minChildSize: 0.14,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0D0D0D),
            border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.error != null
                            ? session.error!
                            : '${session.items.length} RESULT${session.items.length == 1 ? '' : 'S'}'
                                ' · $plottableCount mapped',
                        style: const TextStyle(
                            color: Color(0xFF7A7A7A),
                            fontSize: 10.5,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (session.items.isNotEmpty)
                      TextButton.icon(
                        onPressed: onOpenInMainSearch,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF3D7EFF),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('Open in main search',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: session.items.isEmpty
                    ? Center(
                        child: Text(
                          session.loading ? 'Searching…' : 'No media found here.',
                          style: const TextStyle(color: Color(0xFF404040), fontSize: 13),
                        ),
                      )
                    : NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 400) {
                            onLoadMore();
                          }
                          return false;
                        },
                        child: GridView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          // Same grid delegate as SearchPage._buildResults /
                          // AuthorPortfolioPage._buildBody — matching card
                          // size everywhere, not a map-specific shrink.
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 280,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.85),
                          itemCount: session.items.length + (session.loadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i == session.items.length) {
                              return const Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                                ),
                              );
                            }
                            final item = session.items[i];
                            // MediaCard builds its own `/view` navigation from
                            // `searchState` — passing the map's current
                            // filterState (filtered mode) or an empty
                            // SearchState (browse mode) reproduces exactly
                            // the two navigation cases documented on
                            // _MapPageState._openItem, with no extra
                            // tap-handling needed here.
                            return RepaintBoundary(
                              key: ValueKey(item.url),
                              child: MediaCard(
                                item: item,
                                searchResultsNotifier: ValueNotifier(session.items),
                                onLoadMore: onLoadMore,
                                index: i,
                                searchState: searchState,
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}