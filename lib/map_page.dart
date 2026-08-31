import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'map_controller.dart';
import 'search_components.dart';
import 'search_models.dart';
import 'search_url_codec.dart';

const _kMinRadiusMeters = 500.0;
const _kBg = Color(0xFF0B0B0B);
const _kPanelBg = Color(0xFF141414);
const _kBorder = Color(0xFF242424);
const _kAccent = Color(0xFF3D7EFF);

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

  bool _satellite = false;
  double _currentZoom = 2;
  double _currentRotation = 0;

  static const double _minZoom = 2;
  static const double _maxZoom = 19;

  double get _radius {
    final r = double.tryParse(_radiusCtrl.text.trim()) ?? _kMinRadiusMeters;
    return r < _kMinRadiusMeters ? _kMinRadiusMeters : r;
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

  /// Whole-viewport bbox search — the one bbox mechanism kept, since
  /// CirrusSearch has no bbox keyword and this is the only real one
  /// (see CommonsBackend.geosearch). Snaps to north-up first so a rotated
  /// view searches exactly what's on screen, not its enclosing rectangle.
  void _searchThisArea() {
    if (_currentRotation != 0) _mapController.rotate(0);
    final b = _mapController.camera.visibleBounds;
    ref
        .read(mapSearchControllerProvider.notifier)
        .searchBoundingBox([b.north, b.west, b.south, b.east]);
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
    } else if (state.boundingBox != null) {
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
    final session = state.session;
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
      body: LayoutBuilder(builder: (context, constraints) {
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
                onTap: (_, point) => _handleTap(point),
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
                TileLayer(
                  urlTemplate: _satellite
                      ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                      : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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

            // Coordinate / radius entry panel.
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

            // Satellite toggle + search-this-area.
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _OverlayIconButton(
                    icon: _satellite ? Icons.map : Icons.satellite_alt,
                    tooltip: _satellite ? 'Street map' : 'Satellite',
                    onTap: () => setState(() => _satellite = !_satellite),
                  ),
                  const SizedBox(height: 8),
                  _OverlayIconButton(
                    icon: Icons.crop_free,
                    tooltip: 'Search this area (bounding box)',
                    onTap: _searchThisArea,
                  ),
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
          onLoadMore: () => ref.read(mapSearchControllerProvider.notifier).loadMore(),
          onOpenInMainSearch: () => _openInMainSearch(state),
          onOpenItem: _openItem,
          searchState: state.mode == GeoMode.filtered ? state.filterState : const SearchState(),
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
  const _OverlayIconButton({required this.icon, required this.tooltip, required this.onTap});

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
            color: _kPanelBg.withOpacity(0.96),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _kBorder),
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
/// map, sourced live from whichever geo session (radius or bbox) is active.
class _ResultsPane extends StatelessWidget {
  final SearchSession session;
  final VoidCallback onLoadMore;
  final VoidCallback onOpenInMainSearch;
  final void Function(SearchItem) onOpenItem;
  final SearchState searchState;

  const _ResultsPane({
    required this.session,
    required this.onLoadMore,
    required this.onOpenInMainSearch,
    required this.onOpenItem,
    required this.searchState,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Row(children: [
            Expanded(
              child: Text(
                session.error ??
                    '${session.items.length} RESULT${session.items.length == 1 ? '' : 'S'}',
                style: const TextStyle(
                    color: Color(0xFF7A7A7A), fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w700),
              ),
            ),
            if (session.items.isNotEmpty)
              TextButton.icon(
                onPressed: onOpenInMainSearch,
                style: TextButton.styleFrom(
                    foregroundColor: _kAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: const Icon(Icons.open_in_new, size: 14),
                label:
                    const Text('Open in main search', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        Expanded(
          child: session.items.isEmpty
              ? Center(
                  child: Text(
                    session.loading
                        ? 'Searching…'
                        : session.hasSearched
                            ? 'No media found here.'
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
