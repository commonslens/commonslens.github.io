import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import 'search_models.dart';
import 'search_components.dart';
import 'search_url_codec.dart';

const _mapBackground = Color(0xFF0B0B0B);
const _mapPanel = Color(0xFF141414);
const _mapBorder = Color(0xFF2A2A2A);
const _mapAccent = Color(0xFF3D7EFF);
const _minimumRadiusKm = 0.5;

/// The map presentation for the main search surface.
///
/// This widget never owns or fetches a second result session. It plots the
/// normal search session and reports map interactions back to SearchPage,
/// which applies them to the same SearchState used by the grid and filters.
class SearchMapView extends StatefulWidget {
  final SearchSession session;
  final SearchState filterState;
  final void Function(double lat, double lng, double radiusKm) onSearchLocation;
  final VoidCallback onClearLocation;
  final VoidCallback onLoadMore;
  final VoidCallback onShowResults;

  const SearchMapView({
    super.key,
    required this.session,
    required this.filterState,
    required this.onSearchLocation,
    required this.onClearLocation,
    required this.onLoadMore,
    required this.onShowResults,
  });

  @override
  State<SearchMapView> createState() => _SearchMapViewState();
}

class _SearchMapViewState extends State<SearchMapView> {
  static const double _minimumZoom = 2;
  static const double _maximumZoom = 19;

  final MapController _mapController = MapController();
  late final TextEditingController _radiusController;
  late final FocusNode _radiusFocusNode;

  _SearchMapStyle _style = _SearchMapStyle.street;
  double _zoom = 2;
  double _rotation = 0;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _radiusController = TextEditingController(
      text: _formatRadius(widget.filterState.nearCoord?.radiusKm ?? 10),
    );
    _radiusFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant SearchMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLocation = oldWidget.filterState.nearCoord;
    final newLocation = widget.filterState.nearCoord;

    if (!_radiusFocusNode.hasFocus &&
        newLocation != null &&
        _radiusController.text != _formatRadius(newLocation.radiusKm)) {
      _radiusController.text = _formatRadius(newLocation.radiusKm);
    }

    if (oldLocation != newLocation && newLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToLocation(newLocation);
      });
    } else if (newLocation == null &&
        oldWidget.session.items.isEmpty &&
        widget.session.items.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitToItems(_plottableItems);
      });
    }
  }

  @override
  void dispose() {
    _radiusController.dispose();
    _radiusFocusNode.dispose();
    super.dispose();
  }

  List<SearchItem> get _plottableItems =>
      widget.session.items.where((item) => item.hasCoordinates).toList();

  String _formatRadius(double radiusKm) {
    if (radiusKm == radiusKm.roundToDouble()) {
      return radiusKm.toStringAsFixed(0);
    }
    return radiusKm.toStringAsFixed(1);
  }

  double get _radiusKm {
    final parsed = double.tryParse(_radiusController.text.trim()) ?? 10;
    return math.max(_minimumRadiusKm, parsed);
  }

  double _zoomForRadius(double radiusKm) {
    if (radiusKm <= 1) return 14;
    if (radiusKm <= 5) return 12;
    if (radiusKm <= 20) return 10;
    if (radiusKm <= 100) return 8;
    if (radiusKm <= 500) return 6;
    return 4;
  }

  void _onMapReady() {
    _mapReady = true;
    final location = widget.filterState.nearCoord;
    if (location != null) {
      _moveToLocation(location);
    } else {
      _fitToItems(_plottableItems);
    }
  }

  void _moveToLocation(NearCoordFilter location) {
    if (!_mapReady) return;
    _mapController.move(
      ll.LatLng(location.lat, location.lng),
      _zoomForRadius(location.radiusKm),
    );
  }

  void _fitToItems(List<SearchItem> items) {
    if (!_mapReady || items.isEmpty) return;
    final points = items
        .map((item) =>
            ll.LatLng(item.resolvedLatitude!, item.resolvedLongitude!))
        .toList();
    if (points.length == 1) {
      _mapController.move(points.first, 12);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(64),
      ),
    );
  }

  void _searchAt(ll.LatLng point) {
    final radius = _radiusKm;
    _radiusController.text = _formatRadius(radius);
    _radiusFocusNode.unfocus();
    widget.onSearchLocation(point.latitude, point.longitude, radius);
  }

  void _applyRadiusToCurrentLocation() {
    final location = widget.filterState.nearCoord;
    if (location == null) return;
    _searchAt(ll.LatLng(location.lat, location.lng));
  }

  void _openItem(SearchItem item) {
    final params = <String, String>{
      'id': item.title,
      ...SearchUrlCodec.toQueryParams(widget.filterState),
      'view': 'map',
    };
    context.push(Uri(path: '/view', queryParameters: params).toString());
  }

  void _showCluster(_MapCluster cluster) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.65, 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${cluster.items.length} FILES AT THIS LOCATION',
                        style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 11,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: cluster.items.length,
                  itemBuilder: (context, index) {
                    final item = cluster.items[index];
                    return _MapResultCard(
                      item: item,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openItem(item);
                      },
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

  @override
  Widget build(BuildContext context) {
    final location = widget.filterState.nearCoord;
    final plottable = _plottableItems;
    final clusters = _clusterItems(plottable, _zoom);

    return LayoutBuilder(builder: (context, constraints) {
      final showResultsPreview =
          widget.session.items.isNotEmpty && constraints.maxWidth >= 720;
      final previewWidth =
          (constraints.maxWidth * 0.34).clamp(320.0, 420.0).toDouble();

      final mapCanvas = ColoredBox(
        color: _mapBackground,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: location == null
                    ? const ll.LatLng(20, 0)
                    : ll.LatLng(location.lat, location.lng),
                initialZoom:
                    location == null ? 2 : _zoomForRadius(location.radiusKm),
                minZoom: _minimumZoom,
                maxZoom: _maximumZoom,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all),
                onMapReady: _onMapReady,
                onTap: (_, point) => _searchAt(point),
                onPositionChanged: (camera, hasGesture) {
                  if (camera.zoom == _zoom && camera.rotation == _rotation) {
                    return;
                  }
                  setState(() {
                    _zoom = camera.zoom;
                    _rotation = camera.rotation;
                  });
                },
              ),
              children: [
                _SearchTileLayer(urlTemplate: _style.tileUrl),
                if (_style.overlayUrl case final overlayUrl?)
                  _SearchTileLayer(urlTemplate: overlayUrl),
                if (location != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: ll.LatLng(location.lat, location.lng),
                        radius: location.radiusKm * 1000,
                        useRadiusInMeter: true,
                        color: _mapAccent.withValues(alpha: 0.12),
                        borderColor: _mapAccent,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (location != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: ll.LatLng(location.lat, location.lng),
                        width: 14,
                        height: 14,
                        child: const _SearchCenterDot(),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: clusters
                      .map(
                        (cluster) => Marker(
                          key: ValueKey(
                              'map-cluster-${cluster.key}-${cluster.items.length}'),
                          point: cluster.center,
                          width: cluster.items.length > 1 ? 44 : 36,
                          height: cluster.items.length > 1 ? 44 : 36,
                          child: _SearchClusterMarker(
                            cluster: cluster,
                            onTap: () => cluster.items.length == 1
                                ? _openItem(cluster.items.first)
                                : _showCluster(cluster),
                          ),
                        ),
                      )
                      .toList(),
                ),
                SimpleAttributionWidget(
                  alignment: Alignment.bottomCenter,
                  backgroundColor: _mapBackground.withValues(alpha: 0.82),
                  source: Text(
                    _style.attribution,
                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(_style.attributionUrl),
                    mode: LaunchMode.platformDefault,
                    webOnlyWindowName: '_blank',
                  ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 310),
                child: _RadiusPanel(
                  controller: _radiusController,
                  focusNode: _radiusFocusNode,
                  hasLocation: location != null,
                  onApply: _applyRadiusToCurrentLocation,
                  onClear: widget.onClearLocation,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: _MapControlButton(
                icon: _style.icon,
                text: _style == _SearchMapStyle.englishStreet ? 'EN' : null,
                tooltip: '${_style.label} map — switch to ${_style.next.label}',
                onTap: () => setState(() => _style = _style.next),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 28,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _MapStatusPanel(
                  mappedCount: plottable.length,
                  totalCount: widget.session.items.length,
                  loading: widget.session.loading || widget.session.loadingMore,
                  hasMore: widget.session.hasMore,
                  onLoadMore: widget.onLoadMore,
                  onShowResults: widget.onShowResults,
                  showSwitchToGrid: !showResultsPreview,
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 28,
              child: _SearchMapNavigationControls(
                mapController: _mapController,
                currentRotation: _rotation,
                minimumZoom: _minimumZoom,
                maximumZoom: _maximumZoom,
              ),
            ),
            if (widget.session.loading)
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _mapAccent,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

      if (!showResultsPreview) return mapCanvas;

      return Row(
        children: [
          Expanded(child: mapCanvas),
          SizedBox(
            width: previewWidth,
            child: MapResultsPreview(
              session: widget.session,
              searchState: widget.filterState,
              onLoadMore: widget.onLoadMore,
              onShowResults: widget.onShowResults,
            ),
          ),
        ],
      );
    });
  }
}

enum _SearchMapStyle { street, englishStreet, satellite, hybrid }

extension on _SearchMapStyle {
  _SearchMapStyle get next => switch (this) {
        _SearchMapStyle.street => _SearchMapStyle.englishStreet,
        _SearchMapStyle.englishStreet => _SearchMapStyle.satellite,
        _SearchMapStyle.satellite => _SearchMapStyle.hybrid,
        _SearchMapStyle.hybrid => _SearchMapStyle.street,
      };

  IconData get icon => switch (this) {
        _SearchMapStyle.street => Icons.map_outlined,
        _SearchMapStyle.englishStreet => Icons.translate,
        _SearchMapStyle.satellite => Icons.satellite_alt,
        _SearchMapStyle.hybrid => Icons.layers,
      };

  String get label => switch (this) {
        _SearchMapStyle.street => 'Multilingual street',
        _SearchMapStyle.englishStreet => 'English street',
        _SearchMapStyle.satellite => 'Satellite',
        _SearchMapStyle.hybrid => 'Hybrid',
      };

  String get tileUrl => switch (this) {
        _SearchMapStyle.street =>
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        _SearchMapStyle.englishStreet =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
        _SearchMapStyle.satellite ||
        _SearchMapStyle.hybrid =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      };

  String? get overlayUrl => switch (this) {
        _SearchMapStyle.hybrid =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
        _ => null,
      };

  String get attribution => switch (this) {
        _SearchMapStyle.street => 'OpenStreetMap contributors',
        _SearchMapStyle.englishStreet =>
          'Esri, data providers, OpenStreetMap contributors',
        _SearchMapStyle.satellite ||
        _SearchMapStyle.hybrid =>
          'Esri and data providers',
      };

  String get attributionUrl => switch (this) {
        _SearchMapStyle.street => 'https://www.openstreetmap.org/copyright',
        _SearchMapStyle.englishStreet =>
          'https://goto.arcgisonline.com/maps/World_Street_Map',
        _SearchMapStyle.satellite ||
        _SearchMapStyle.hybrid =>
          'https://www.esri.com/en-us/legal/terms/data-attributions',
      };
}

class _MapCluster {
  final String key;
  final ll.LatLng center;
  final List<SearchItem> items;

  const _MapCluster({
    required this.key,
    required this.center,
    required this.items,
  });
}

List<_MapCluster> _clusterItems(List<SearchItem> items, double zoom) {
  if (items.isEmpty) return const [];
  final cellSize = (40 / math.pow(2, zoom)).clamp(0.0005, 40);
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
    final latitude =
        group.map((item) => item.resolvedLatitude!).reduce((a, b) => a + b) /
            group.length;
    final longitude =
        group.map((item) => item.resolvedLongitude!).reduce((a, b) => a + b) /
            group.length;
    return _MapCluster(
      key: entry.key,
      center: ll.LatLng(latitude, longitude),
      items: group,
    );
  }).toList();
}

class _SearchTileLayer extends StatefulWidget {
  final String urlTemplate;

  const _SearchTileLayer({required this.urlTemplate});

  @override
  State<_SearchTileLayer> createState() => _SearchTileLayerState();
}

class _SearchTileLayerState extends State<_SearchTileLayer> {
  late final CancellableNetworkTileProvider _tileProvider =
      CancellableNetworkTileProvider();

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: widget.urlTemplate,
      userAgentPackageName: 'com.commonslens.app',
      maxZoom: 19,
      tileProvider: _tileProvider,
    );
  }
}

class _RadiusPanel extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasLocation;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _RadiusPanel({
    required this.controller,
    required this.focusNode,
    required this.hasLocation,
    required this.onApply,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _mapPanel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _mapBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TAP THE MAP TO SEARCH A CIRCLE',
            style: TextStyle(
              color: Color(0xFF9A9A9A),
              fontSize: 9.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => hasLocation ? onApply() : null,
                  style: const TextStyle(color: Colors.white, fontSize: 12.5),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A1A1A),
                    hintText: 'Radius',
                    suffixText: 'km',
                    suffixStyle: const TextStyle(color: Colors.white54),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: hasLocation ? onApply : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _mapAccent,
                    disabledBackgroundColor: const Color(0xFF242424),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text('Apply',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              if (hasLocation) ...[
                const SizedBox(width: 3),
                IconButton(
                  tooltip: 'Clear location',
                  onPressed: onClear,
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 18),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MapStatusPanel extends StatelessWidget {
  final int mappedCount;
  final int totalCount;
  final bool loading;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final VoidCallback onShowResults;
  final bool showSwitchToGrid;

  const _MapStatusPanel({
    required this.mappedCount,
    required this.totalCount,
    required this.loading,
    required this.hasMore,
    required this.onLoadMore,
    required this.onShowResults,
    required this.showSwitchToGrid,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _mapPanel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _mapBorder),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$mappedCount OF $totalCount MAPPED',
            style: const TextStyle(
              color: Color(0xFFAAAAAA),
              fontSize: 9.5,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hasMore)
            TextButton(
              onPressed: loading ? null : onLoadMore,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8EAFFF),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(loading ? 'Loading…' : 'Load more'),
            ),
          if (showSwitchToGrid)
            OutlinedButton.icon(
              onPressed: onShowResults,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8EAFFF),
                side: const BorderSide(color: _mapAccent),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.grid_view_rounded, size: 14),
              label: const Text('Switch to grid',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class MapResultsPreview extends StatelessWidget {
  final SearchSession session;
  final SearchState searchState;
  final VoidCallback onLoadMore;
  final VoidCallback onShowResults;

  const MapResultsPreview({
    super.key,
    required this.session,
    required this.searchState,
    required this.onLoadMore,
    required this.onShowResults,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        border: Border(left: BorderSide(color: Color(0xFF242424))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${session.items.length} RESULT${session.items.length == 1 ? '' : 'S'}${session.hasMore ? '+' : ''}',
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onShowResults,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8EAFFF),
                    minimumSize: Size.zero,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.grid_view_rounded, size: 14),
                  label: const Text(
                    'Switch to grid',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF242424)),
          Expanded(
            child: session.error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        session.error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFF9B91),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : MediaResultsGrid(
                    items: session.items,
                    loadingMore: session.loadingMore,
                    searchState: searchState,
                    extraParams: const {'view': 'map'},
                    onNearEnd: onLoadMore,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 210,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.82,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchClusterMarker extends StatelessWidget {
  final _MapCluster cluster;
  final VoidCallback onTap;

  const _SearchClusterMarker({required this.cluster, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = cluster.items.length;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: count > 1 ? _mapAccent : const Color(0xFF1A1A1A),
          border: Border.all(
            color: count > 1 ? Colors.white : _mapAccent,
            width: 2,
          ),
        ),
        alignment: Alignment.center,
        child: count > 1
            ? Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              )
            : ClipOval(
                child: Image.network(
                  cluster.items.first.thumb,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.image_outlined,
                    color: Colors.white54,
                    size: 17,
                  ),
                ),
              ),
      ),
    );
  }
}

class _MapResultCard extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onTap;

  const _MapResultCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171717),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SizedBox.expand(
                child: Image.network(
                  item.thumb,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF202020),
                    child: Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white38),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Text(
                item.title.replaceFirst('File:', ''),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCenterDot extends StatelessWidget {
  const _SearchCenterDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _mapAccent,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String? text;
  final String tooltip;
  final VoidCallback onTap;

  const _MapControlButton({
    required this.icon,
    this.text,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _mapPanel.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: _mapBorder),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: text == null
                  ? Icon(icon, color: Colors.white, size: 20)
                  : Text(
                      text!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchMapNavigationControls extends StatelessWidget {
  final MapController mapController;
  final double currentRotation;
  final double minimumZoom;
  final double maximumZoom;

  const _SearchMapNavigationControls({
    required this.mapController,
    required this.currentRotation,
    required this.minimumZoom,
    required this.maximumZoom,
  });

  void _zoomBy(double delta) {
    final camera = mapController.camera;
    mapController.move(
      camera.center,
      (camera.zoom + delta).clamp(minimumZoom, maximumZoom),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: _mapPanel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _mapBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapNavButton(
              icon: Icons.add, tooltip: 'Zoom in', onTap: () => _zoomBy(1)),
          const Divider(height: 1, color: _mapBorder),
          _MapNavButton(
              icon: Icons.remove,
              tooltip: 'Zoom out',
              onTap: () => _zoomBy(-1)),
          const Divider(height: 1, color: _mapBorder),
          _MapNavButton(
            icon: Icons.rotate_left,
            tooltip: 'Rotate left',
            onTap: () => mapController.rotate(currentRotation - 15),
          ),
          const Divider(height: 1, color: _mapBorder),
          _MapNavButton(
            icon: Icons.rotate_right,
            tooltip: 'Rotate right',
            onTap: () => mapController.rotate(currentRotation + 15),
          ),
          const Divider(height: 1, color: _mapBorder),
          _MapNavButton(
            icon: Icons.explore,
            tooltip: 'Reset to north',
            onTap: () => mapController.rotate(0),
          ),
        ],
      ),
    );
  }
}

class _MapNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _MapNavButton({
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
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }
}
