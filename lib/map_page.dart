import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'map_controller.dart';
import 'search_components.dart';
import 'search_controller.dart';
import 'search_models.dart';
import 'search_url_codec.dart';

const _kMinRadiusMeters = 500.0;
const _kBg = Color(0xFF0B0B0B);
const _kPanelBg = Color(0xFF141414);
const _kBorder = Color(0xFF242424);
const _kAccent = Color(0xFF3D7EFF);

enum _BaseMapStyle { street, satellite, hybrid }

extension on _BaseMapStyle {
  _BaseMapStyle get next {
    switch (this) {
      case _BaseMapStyle.street:
        return _BaseMapStyle.satellite;
      case _BaseMapStyle.satellite:
        return _BaseMapStyle.hybrid;
      case _BaseMapStyle.hybrid:
        return _BaseMapStyle.street;
    }
  }

  IconData get icon {
    switch (this) {
      case _BaseMapStyle.street:
        return Icons.map_outlined;
      case _BaseMapStyle.satellite:
        return Icons.satellite_alt;
      case _BaseMapStyle.hybrid:
        return Icons.layers;
    }
  }

  String get label {
    switch (this) {
      case _BaseMapStyle.street:
        return 'Street';
      case _BaseMapStyle.satellite:
        return 'Satellite';
      case _BaseMapStyle.hybrid:
        return 'Hybrid';
    }
  }
}

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});
  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  final MapController _mapController = MapController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController(text: '2000');

  _BaseMapStyle _baseMapStyle = _BaseMapStyle.street;
  double _currentZoom = 2;
  double _currentRotation = 0;

  // Two-tap bounding-box drawing — see _handleMapTap. Replaces the old
  // "search whatever's on screen" behavior: the person picks the exact
  // area instead of it defaulting to the current viewport.
  bool _drawingBbox = false;
  ll.LatLng? _bboxFirstPoint;

  bool _handledInitialParams = false;

  static const double _minZoom = 2;
  static const double _maxZoom = 19;

  double get _radius {
    final r = double.tryParse(_radiusCtrl.text.trim()) ?? _kMinRadiusMeters;
    return r < _kMinRadiusMeters ? _kMinRadiusMeters : r;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledInitialParams) return;
    _handledInitialParams = true;

    // Deep-link entry point for AssetViewer's "View Photos Clicked Nearby"
    // — /map?lat=..&lng=..&radiusKm=.. — triggers a pure geosearch (browse
    // mode) radius search around that point on first load.
    final params = GoRouterState.of(context).uri.queryParameters;
    final lat = double.tryParse(params['lat'] ?? '');
    final lng = double.tryParse(params['lng'] ?? '');
    if (lat == null || lng == null) return;

    final radiusKm = double.tryParse(params['radiusKm'] ?? '') ?? 10;
    final radiusM = radiusKm * 1000;

    _latCtrl.text = lat.toStringAsFixed(6);
    _lngCtrl.text = lng.toStringAsFixed(6);
    _radiusCtrl.text = radiusM.toStringAsFixed(0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(ll.LatLng(lat, lng), 12);
      ref.read(mapSearchControllerProvider.notifier).browseRadius(lat, lng, radiusM);
    });
  }

  void _searchAt(double lat, double lng) {
    final r = _radius;
    _radiusCtrl.text = r.toStringAsFixed(0);
    _latCtrl.text = lat.toStringAsFixed(6);
    _lngCtrl.text = lng.toStringAsFixed(6);
    ref.read(mapSearchControllerProvider.notifier).searchRadius(lat, lng, r);
  }

  void _handleTap(ll.LatLng point) => _searchAt(point.latitude, point.longitude);

  void _submitCoords() {
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat == null || lng == null) return;
    _searchAt(lat, lng);
    _mapController.move(ll.LatLng(lat, lng), _mapController.camera.zoom);
  }

  void _toggleBboxDrawing() {
    setState(() {
      _drawingBbox = !_drawingBbox;
      _bboxFirstPoint = null;
    });
  }

  /// Routes a map tap to whichever interaction is currently active: laying
  /// down a bounding-box corner, or (in explore mode) a normal radius tap.
  /// Imported mode ignores taps entirely — there's no fetch to trigger
  /// while viewing your own already-fetched results.
  void _handleMapTap(MapViewState mapState, ll.LatLng point) {
    if (_drawingBbox) {
      if (_bboxFirstPoint == null) {
        setState(() => _bboxFirstPoint = point);
        return;
      }
      final p1 = _bboxFirstPoint!;
      final north = math.max(p1.latitude, point.latitude);
      final south = math.min(p1.latitude, point.latitude);
      final west = math.min(p1.longitude, point.longitude);
      final east = math.max(p1.longitude, point.longitude);
      setState(() {
        _drawingBbox = false;
        _bboxFirstPoint = null;
      });
      ref
          .read(mapSearchControllerProvider.notifier)
          .searchBoundingBox([north, west, south, east]);
      return;
    }

    if (mapState.mode == GeoMode.imported) return;
    _handleTap(point);
  }

  void _fitToItems(List<SearchItem> items) {
    final coords = items
        .where((i) => i.hasCoordinates)
        .map((i) => ll.LatLng(i.resolvedLatitude!, i.resolvedLongitude!))
        .toList();
    if (coords.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (coords.length == 1) {
        _mapController.move(coords.first, 12);
        return;
      }
      final bounds = LatLngBounds.fromPoints(coords);
      _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)));
    });
  }

  /// "Search → map" tab: switches display to the main search page's live
  /// results. Nothing is copied — build() derives the plotted set fresh
  /// from searchControllerProvider every time, so this is just a mode
  /// flip plus a one-time camera fit to whatever's plottable right now.
  void _handleSelectImport() {
    setState(() {
      _drawingBbox = false;
      _bboxFirstPoint = null;
    });
    ref.read(mapSearchControllerProvider.notifier).setMode(GeoMode.imported);
    _fitToItems(ref.read(searchControllerProvider).activeSession.items);
  }

  void _handleSelectExplore() {
    final current = ref.read(mapSearchControllerProvider);
    if (current.mode == GeoMode.imported) {
      ref.read(mapSearchControllerProvider.notifier).setMode(GeoMode.browse);
    }
  }

  void _openItem(SearchItem item) {
    context.push(Uri(
      path: '/view',
      queryParameters: {'id': item.title, 'from': 'map'},
    ).toString());
  }

  void _openInMainSearch(MapViewState state) {
    SearchState target;
    if (state.mode == GeoMode.filtered) {
      if (!state.session.hasSearched) return;
      target = state.filterState;
    } else if (state.mode == GeoMode.browse && state.boundingBox != null) {
      final box = state.boundingBox!;
      final center = ll.LatLng((box[0] + box[2]) / 2, (box[1] + box[3]) / 2);
      final corner = ll.LatLng(box[0], box[1]);
      final radiusM = const ll.Distance().as(ll.LengthUnit.Meter, center, corner);
      target = SearchState(
        nearCoord: NearCoordFilter(
            lat: center.latitude, lng: center.longitude, radiusKm: radiusM / 1000),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No bounding-box keyword in CirrusSearch — opening as a circular radius covering the box instead.'),
      ));
    } else {
      return;
    }
    final params = SearchUrlCodec.toQueryParams(target);
    context.go(Uri(path: '/', queryParameters: params.isEmpty ? null : params).toString());
  }

  void _showClusterSheet(BuildContext context, _MarkerCluster cluster) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => SafeArea(
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
                        _openItem(item);
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
      ),
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
                left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('FILTERS FOR NEXT RADIUS SEARCH',
                    style: TextStyle(
                        color: Color(0xFF7A7A7A),
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextField(
                  controller: queryCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: _fieldDecoration(hint: 'Optional text query…'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<LicensePreset>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  value: license,
                  decoration: _fieldDecoration(),
                  items: LicensePreset.values
                      .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(licensePresetLabel(p), style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => license = v ?? license),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<QualityFilter>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  value: quality,
                  decoration: _fieldDecoration(),
                  items: QualityFilter.values
                      .map((q) => DropdownMenuItem(
                          value: q,
                          child: Text(qualityFilterLabel(q), style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (v) => setSheetState(() => quality = v ?? quality),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    onPressed: () {
                      notifier.updateFilters((s) => s.copyWith(
                          queryText: queryCtrl.text.trim(), licensePreset: license, qualityFilter: quality));
                      Navigator.of(context).pop();
                    },
                    child: const Text('Apply',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapSearchControllerProvider);
    final mainSearchSession = ref.watch(searchControllerProvider).activeSession;
    final mainSearchItems = mainSearchSession.items;
    final isImportMode = state.mode == GeoMode.imported;

    // Live-derived, not a stored snapshot — recomputes on every rebuild
    // this widget gets from watching searchControllerProvider, so a
    // loadMore fired from the main search page (or from this page's own
    // results pane below) shows up immediately without re-toggling modes.
    final importedPlottable =
        mainSearchItems.where((i) => i.hasCoordinates).toList();
    final session = isImportMode
        ? SearchSession(
            items: importedPlottable,
            hasSearched: true,
            loading: mainSearchSession.loading,
            loadingMore: mainSearchSession.loadingMore,
            hasMore: mainSearchSession.hasMore,
          )
        : state.session;
    final plottable = session.items.where((i) => i.hasCoordinates).toList();
    final clusters = _clusterItems(plottable, _currentZoom);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text('GEOSPATIAL BROWSE',
            style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Filters', onPressed: () => _showFilterSheet(context)),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Explicit two-mode toggle — "search → map" (plot what you
          // already found) vs "map → search" (tap/draw to find something
          // new). See GeoMode's doc for the full rationale.
          Container(
            color: _kPanelBg,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: 'SEARCH → MAP',
                    sublabel: 'Plot your current results',
                    selected: isImportMode,
                    onTap: _handleSelectImport,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    label: 'MAP → SEARCH',
                    sublabel: 'Tap or draw to find photos',
                    selected: !isImportMode,
                    onTap: _handleSelectExplore,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;

              final mapArea = Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: const ll.LatLng(20, 0),
                      initialZoom: 2,
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                      interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                      onTap: (_, point) => _handleMapTap(state, point),
                      onPositionChanged: (camera, hasGesture) {
                        if (camera.zoom != _currentZoom || camera.rotation != _currentRotation) {
                          setState(() {
                            _currentZoom = camera.zoom;
                            _currentRotation = camera.rotation;
                          });
                        }
                      },
                    ),
                    children: [
                      if (_baseMapStyle == _BaseMapStyle.street)
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.commonslens.app',
                          maxZoom: 19,
                        )
                      else ...[
                        TileLayer(
                          urlTemplate:
                              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                          userAgentPackageName: 'com.commonslens.app',
                          maxZoom: 19,
                        ),
                        // Hybrid = satellite imagery + this transparent
                        // roads/labels overlay on top. Satellite alone
                        // (the branch above without this layer) stays
                        // available as its own mode for a clean image.
                        if (_baseMapStyle == _BaseMapStyle.hybrid)
                          TileLayer(
                            urlTemplate:
                                'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
                            userAgentPackageName: 'com.commonslens.app',
                            maxZoom: 19,
                          ),
                      ],
                      if (state.boundingBox != null)
                        PolygonLayer(polygons: [
                          Polygon(
                            points: [
                              ll.LatLng(state.boundingBox![0], state.boundingBox![1]),
                              ll.LatLng(state.boundingBox![0], state.boundingBox![3]),
                              ll.LatLng(state.boundingBox![2], state.boundingBox![3]),
                              ll.LatLng(state.boundingBox![2], state.boundingBox![1]),
                            ],
                            color: _kAccent.withOpacity(0.15),
                            borderColor: _kAccent,
                            borderStrokeWidth: 2,
                          ),
                        ]),
                      if (state.hasPoint)
                        CircleLayer(circles: [
                          CircleMarker(
                            point: ll.LatLng(state.centerLat!, state.centerLng!),
                            radius: state.radiusMeters,
                            useRadiusInMeter: true,
                            color: _kAccent.withOpacity(0.12),
                            borderColor: _kAccent,
                            borderStrokeWidth: 2,
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
                      if (_bboxFirstPoint != null)
                        MarkerLayer(markers: [
                          Marker(
                            point: _bboxFirstPoint!,
                            width: 16,
                            height: 16,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _kAccent,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ]),
                      MarkerLayer(
                        markers: clusters
                            .map((c) => Marker(
                                  key: ValueKey('cluster-${c.key}-${c.items.length}'),
                                  point: c.center,
                                  width: c.items.length > 1 ? 44 : 34,
                                  height: c.items.length > 1 ? 44 : 34,
                                  child: _ClusterMarker(
                                    key: ValueKey('cluster-w-${c.key}-${c.items.length}'),
                                    cluster: c,
                                    onTap: () => c.items.length == 1
                                        ? _openItem(c.items.first)
                                        : _showClusterSheet(context, c),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),

                  if (!isImportMode)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: _CoordPanel(
                          latCtrl: _latCtrl,
                          lngCtrl: _lngCtrl,
                          radiusCtrl: _radiusCtrl,
                          onSubmit: _submitCoords,
                        ),
                      ),
                    ),

                  if (_drawingBbox)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _kPanelBg.withOpacity(0.96),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _kAccent),
                          ),
                          child: Text(
                            _bboxFirstPoint == null
                                ? 'Tap the first corner of your search area'
                                : 'Tap the opposite corner to finish',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    )
                  else if (isImportMode)
                    Positioned(
                      top: 12,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _kPanelBg.withOpacity(0.96),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _kBorder),
                            ),
                            child: const Text(
                              'Showing your current search results with location data. Switch to "Map → Search" to explore new areas.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFFAAAAAA), fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                    ),

                  Positioned(
                    top: 12,
                    right: 12,
                    child: Column(
                      children: [
                        _OverlayIconButton(
                          icon: _baseMapStyle.icon,
                          tooltip: '${_baseMapStyle.label} map — tap for ${_baseMapStyle.next.label}',
                          onTap: () => setState(() => _baseMapStyle = _baseMapStyle.next),
                        ),
                        if (!isImportMode) ...[
                          const SizedBox(height: 8),
                          _OverlayIconButton(
                            icon: _drawingBbox ? Icons.close : Icons.crop_free,
                            tooltip:
                                _drawingBbox ? 'Cancel drawing' : 'Draw bounding box (tap 2 points)',
                            active: _drawingBbox,
                            onTap: _toggleBboxDrawing,
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (session.loading)
                    const Positioned(
                      bottom: 12,
                      left: 12,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent),
                      ),
                    ),

                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: _MapNavigationControls(
                      mapController: _mapController,
                      currentRotation: _currentRotation,
                      minZoom: _minZoom,
                      maxZoom: _maxZoom,
                    ),
                  ),
                ],
              );

              final results = _ResultsPane(
                session: session,
                onLoadMore: () => isImportMode
                    ? ref.read(searchControllerProvider.notifier).loadMore()
                    : ref.read(mapSearchControllerProvider.notifier).loadMore(),
                onOpenInMainSearch: isImportMode ? null : () => _openInMainSearch(state),
                onOpenItem: _openItem,
                searchState: state.mode == GeoMode.filtered ? state.filterState : const SearchState(),
                emptyMessage: isImportMode
                    ? 'None of your current search results have location data.'
                    : 'No media found here.',
                noteText: isImportMode
                    ? '${importedPlottable.length} of ${mainSearchItems.length} results have location data.'
                    : null,
              );

              if (isDesktop) {
                return Row(children: [
                  Expanded(flex: 3, child: mapArea),
                  Container(
                    width: 420,
                    decoration: const BoxDecoration(
                        color: Color(0xFF0D0D0D), border: Border(left: BorderSide(color: Color(0xFF1E1E1E)))),
                    child: results,
                  ),
                ]);
              }
              return Column(children: [
                Expanded(flex: 3, child: mapArea),
                Container(
                  height: 320,
                  decoration: const BoxDecoration(
                      color: Color(0xFF0D0D0D), border: Border(top: BorderSide(color: Color(0xFF1E1E1E)))),
                  child: results,
                ),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration({String? hint}) => InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 12.5),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
    );

// -----------------------------------------------------------------------------
// Clustering — unchanged: grid-bucket by zoom-scaled cell size, keyed so
// MarkerLayer can diff and skip re-fetching unchanged thumbnails on zoom.
// -----------------------------------------------------------------------------

class _MarkerCluster {
  final String key;
  final ll.LatLng center;
  final List<SearchItem> items;
  const _MarkerCluster({required this.key, required this.center, required this.items});
}

List<_MarkerCluster> _clusterItems(List<SearchItem> items, double zoom) {
  if (items.isEmpty) return const [];
  final cellSize = 40 / math.pow(2, zoom).clamp(0.0005, 40);
  final buckets = <String, List<SearchItem>>{};
  for (final item in items) {
    final lat = item.resolvedLatitude;
    final lng = item.resolvedLongitude;
    if (lat == null || lng == null) continue;
    final key = '${(lat / cellSize).round()}:${(lng / cellSize).round()}';
    buckets.putIfAbsent(key, () => []).add(item);
  }
  return buckets.entries.map((entry) {
    final group = entry.value;
    final lat = group.map((i) => i.resolvedLatitude!).reduce((a, b) => a + b) / group.length;
    final lng = group.map((i) => i.resolvedLongitude!).reduce((a, b) => a + b) / group.length;
    return _MarkerCluster(key: entry.key, center: ll.LatLng(lat, lng), items: group);
  }).toList();
}

// -----------------------------------------------------------------------------
// Small presentational widgets
// -----------------------------------------------------------------------------

class _ModeButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool selected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? _kAccent : _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF9A9A9A),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(sublabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? const Color(0xFFCBD9FF) : const Color(0xFF666666),
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _CoordPanel extends StatelessWidget {
  final TextEditingController latCtrl;
  final TextEditingController lngCtrl;
  final TextEditingController radiusCtrl;
  final VoidCallback onSubmit;

  const _CoordPanel({
    required this.latCtrl,
    required this.lngCtrl,
    required this.radiusCtrl,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kPanelBg.withOpacity(0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: latCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: _fieldDecoration(hint: 'Lat'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: lngCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: _fieldDecoration(hint: 'Lon'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: radiusCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _fieldDecoration(hint: 'Radius (m), min 500'),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: onSubmit,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _kAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                child: const Icon(Icons.search, size: 18, color: Colors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ClusterMarker extends StatelessWidget {
  final _MarkerCluster cluster;
  final VoidCallback onTap;
  const _ClusterMarker({super.key, required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = cluster.items.length;
    final isCluster = count > 1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCluster ? _kAccent : const Color(0xFF1A1A1A),
          border: Border.all(color: isCluster ? Colors.white : _kAccent, width: 2),
        ),
        alignment: Alignment.center,
        child: isCluster
            ? Text('$count',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
            : ClipOval(
                child: Image.network(
                  cluster.items.first.thumb,
                  fit: BoxFit.cover,
                  width: 34,
                  height: 34,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 16, color: Colors.white54),
                ),
              ),
      ),
    );
  }
}

class _CenterDot extends StatelessWidget {
  const _CenterDot();
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: _kAccent, border: Border.all(color: Colors.white, width: 2)),
      );
}

class _OverlayIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
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
            color: active ? _kAccent.withOpacity(0.25) : _kPanelBg.withOpacity(0.96),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? _kAccent : _kBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// Zoom in/out + rotate + reset-to-north compass. Kept as-is per request.
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
    mapController.move(camera.center, (camera.zoom + delta).clamp(minZoom, maxZoom));
  }

  void _rotateBy(double degrees) => mapController.rotate(mapController.camera.rotation + degrees);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: _kPanelBg.withOpacity(0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NavButton(icon: Icons.add, tooltip: 'Zoom in', onTap: () => _zoomBy(1)),
          const _NavDivider(),
          _NavButton(icon: Icons.remove, tooltip: 'Zoom out', onTap: () => _zoomBy(-1)),
          const _NavDivider(),
          _NavButton(icon: Icons.rotate_left, tooltip: 'Rotate left', onTap: () => _rotateBy(-15)),
          const _NavDivider(),
          _NavButton(icon: Icons.rotate_right, tooltip: 'Rotate right', onTap: () => _rotateBy(15)),
          const _NavDivider(),
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
                    child: const Icon(Icons.explore, size: 19, color: _kAccent),
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
  const _NavButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 18, color: Colors.white70)),
        ),
      );
}

class _NavDivider extends StatelessWidget {
  const _NavDivider();
  @override
  Widget build(BuildContext context) => Container(height: 1, color: _kBorder);
}

/// Split-screen results pane: a normal MediaCard grid on the right of the
/// map, sourced live from whichever geo state is active (radius, bbox, or
/// imported).
class _ResultsPane extends StatelessWidget {
  final SearchSession session;
  final VoidCallback onLoadMore;
  final VoidCallback? onOpenInMainSearch;
  final void Function(SearchItem) onOpenItem;
  final SearchState searchState;
  final String emptyMessage;
  final String? noteText;

  const _ResultsPane({
    required this.session,
    required this.onLoadMore,
    required this.onOpenInMainSearch,
    required this.onOpenItem,
    required this.searchState,
    required this.emptyMessage,
    this.noteText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    session.error ??
                        '${session.items.length} RESULT${session.items.length == 1 ? '' : 'S'}',
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700),
                  ),
                ),
                if (onOpenInMainSearch != null && session.items.isNotEmpty)
                  TextButton.icon(
                    onPressed: onOpenInMainSearch,
                    style: TextButton.styleFrom(
                        foregroundColor: _kAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('Open in main search',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
              if (noteText != null) ...[
                const SizedBox(height: 4),
                Text(noteText!,
                    style: const TextStyle(color: Color(0xFF555555), fontSize: 10.5)),
              ],
            ],
          ),
        ),
        Expanded(
          child: session.items.isEmpty
              ? Center(
                  child: Text(
                    session.loading
                        ? 'Searching…'
                        : session.hasSearched
                            ? emptyMessage
                            : 'Tap the map, or enter coordinates, to search a radius.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF404040), fontSize: 13),
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) onLoadMore();
                    return false;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.85),
                    itemCount: session.items.length + (session.loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == session.items.length) {
                        return const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: _kAccent)),
                        );
                      }
                      final item = session.items[i];
                      return RepaintBoundary(
                        key: ValueKey(item.url),
                        child: MediaCard(
                          item: item,
                          searchResultsNotifier: ValueNotifier(session.items),
                          onLoadMore: onLoadMore,
                          index: i,
                          searchState: searchState,
                          extraParams: const {'from': 'map'},
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
