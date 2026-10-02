part of 'pipeline_page.dart';

// -----------------------------------------------------------------------------
// Palette — searchable and grouped by category. It stays neutral/blue like
// the rest of the app; category colors begin only once a node hits the canvas.
// -----------------------------------------------------------------------------

class _Palette extends StatefulWidget {
  final void Function(PipelineNodeType type) onAdd;
  const _Palette({required this.onAdd});

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final byCategory = <PipelineNodeCategory, List<PipelineNodeType>>{};
    for (final type in PipelineNodeType.values) {
      if (_query.isNotEmpty &&
          !type.label.toLowerCase().contains(_query.toLowerCase())) {
        continue;
      }
      byCategory.putIfAbsent(type.category, () => []).add(type);
    }

    return Container(
      color: _kPanelBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _kFieldBg,
                hintText: 'Search nodes…',
                hintStyle: const TextStyle(color: _kMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: _kMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: byCategory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No matching nodes.',
                        style: TextStyle(color: _kMuted, fontSize: 12)),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final entry in byCategory.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                          child: Row(
                            children: [
                              Icon(_categoryIcon(entry.key),
                                  size: 13, color: _kMuted),
                              const SizedBox(width: 6),
                              Text(entry.key.name.toUpperCase(),
                                  style: const TextStyle(
                                      color: _kMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2)),
                            ],
                          ),
                        ),
                        for (final type in entry.value)
                          _PaletteTile(
                            type: type,
                            onTap: () => widget.onAdd(type),
                          ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaletteTile extends StatefulWidget {
  final PipelineNodeType type;
  final VoidCallback onTap;
  const _PaletteTile({required this.type, required this.onTap});

  @override
  State<_PaletteTile> createState() => _PaletteTileState();
}

class _PaletteTileState extends State<_PaletteTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? _kFieldBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hovered ? _kBorder : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(_nodeTypeIcon(widget.type),
                  size: 15, color: _hovered ? _kAccent : Colors.white54),
              const SizedBox(width: 9),
              Expanded(
                child: Text(widget.type.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.add_circle_outline,
                  size: 14, color: _hovered ? _kAccent : Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Canvas — the fl_nodes / PipelineController bridge.
// -----------------------------------------------------------------------------

class _PipelineCanvas extends ConsumerStatefulWidget {
  final void Function(String? selectedOurNodeId) onSelectionChanged;
  const _PipelineCanvas({required this.onSelectionChanged});

  @override
  ConsumerState<_PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends ConsumerState<_PipelineCanvas> {
  late final fln.FlNodeEditorController _flController;
  bool _suppressFlEvents = false;

  final Map<String, String> _ourNodeIdToFlId = {};
  final Map<String, String> _flIdToOurNodeId = {};
  final Map<String, String> _ourEdgeIdToFlLinkId = {};
  final Map<String, String> _flLinkIdToOurEdgeId = {};

  @override
  void initState() {
    super.initState();
    _flController = fln.FlNodeEditorController();
    // Version 1.0.2 does not initialize its detail level from the initial zoom.
    _flController.updateViewportZoomFromUI(1.0);
    for (final prototype in _buildNodePrototypes().values) {
      _flController.registerNodePrototype(prototype);
    }
    _flController.eventBus.events.listen(_handleAnyFlEvent);

    // Initial sync — mirror whatever the controller already has (e.g. a
    // graph loaded from IndexedDB before this widget existed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncModelToCanvas(null, ref.read(pipelineControllerProvider).graph);
      }
    });
  }

  void _handleAnyFlEvent(fln.NodeEditorEvent event) {
    if (_suppressFlEvents) return;
    _reconcileFromCanvas();
  }

  /// Pushes MODEL changes onto the canvas. Diffs by id rather than
  /// rebuilding everything, so an unrelated edit (e.g. just moving one
  /// node) doesn't tear down and re-add every other node's fl_nodes
  /// instance (which would also lose their canvas selection/viewport
  /// feel).
  void _syncModelToCanvas(PipelineGraph? prev, PipelineGraph next) {
    _suppressFlEvents = true;
    try {
      final prevNodeIds = prev?.nodes.map((n) => n.id).toSet() ?? {};
      final nextNodeIds = next.nodes.map((n) => n.id).toSet();

      for (final id in prevNodeIds.difference(nextNodeIds)) {
        final flId = _ourNodeIdToFlId.remove(id);
        if (flId != null) {
          _flIdToOurNodeId.remove(flId);
          _flController.removeNodeById(flId);
        }
      }

      for (final node in next.nodes) {
        if (!_ourNodeIdToFlId.containsKey(node.id)) {
          final flNode = _flController.addNode(node.type.name,
              offset: Offset(node.x, node.y));
          _ourNodeIdToFlId[node.id] = flNode.id;
          _flIdToOurNodeId[flNode.id] = node.id;
        } else {
          // Position sync for a node fl_nodes already knows about — e.g.
          // an undo, or a graph freshly loaded from IndexedDB.
          final flId = _ourNodeIdToFlId[node.id]!;
          final flNode = _flController.nodes[flId];
          if (flNode != null && flNode.offset != Offset(node.x, node.y)) {
            flNode.offset = Offset(node.x, node.y);
          }
        }
      }

      final prevEdgeIds = prev?.edges.map((e) => e.id).toSet() ?? {};
      final nextEdgeIds = next.edges.map((e) => e.id).toSet();

      for (final id in prevEdgeIds.difference(nextEdgeIds)) {
        final flLinkId = _ourEdgeIdToFlLinkId.remove(id);
        if (flLinkId != null) {
          _flLinkIdToOurEdgeId.remove(flLinkId);
          _flController.removeLinkById(flLinkId);
        }
      }

      for (final edge in next.edges) {
        if (_ourEdgeIdToFlLinkId.containsKey(edge.id)) continue;
        final fromFlId = _ourNodeIdToFlId[edge.fromNodeId];
        final toFlId = _ourNodeIdToFlId[edge.toNodeId];
        if (fromFlId == null || toFlId == null) continue;
        final link = _flController.addLink(
            fromFlId, edge.fromPortId, toFlId, edge.toPortId);
        if (link != null) {
          _ourEdgeIdToFlLinkId[edge.id] = link.id;
          _flLinkIdToOurEdgeId[link.id] = edge.id;
        }
      }
    } finally {
      _suppressFlEvents = false;
    }
  }

  /// Pulls CANVAS changes into the model. Deliberately re-diffs the
  /// confirmed live accessors (`nodes`, `linksById`, `selectedNodeIds`)
  /// rather than parsing individual event payloads — see this file's top
  /// doc comment for why.
  void _reconcileFromCanvas() {
    final controller = ref.read(pipelineControllerProvider.notifier);
    final graph = ref.read(pipelineControllerProvider).graph;

    // Nodes removed on the canvas (e.g. Delete key / right-click menu).
    for (final ourId in _ourNodeIdToFlId.keys.toList()) {
      final flId = _ourNodeIdToFlId[ourId]!;
      if (!_flController.nodes.containsKey(flId)) {
        _ourNodeIdToFlId.remove(ourId);
        _flIdToOurNodeId.remove(flId);
        controller.removeNode(ourId);
      }
    }

    // Nodes moved on the canvas.
    for (final node in graph.nodes) {
      final flId = _ourNodeIdToFlId[node.id];
      final flNode = flId == null ? null : _flController.nodes[flId];
      if (flNode == null) continue;
      if (flNode.offset.dx != node.x || flNode.offset.dy != node.y) {
        controller.moveNode(node.id, flNode.offset.dx, flNode.offset.dy);
      }
    }

    // Links removed on the canvas.
    for (final ourEdgeId in _ourEdgeIdToFlLinkId.keys.toList()) {
      final flLinkId = _ourEdgeIdToFlLinkId[ourEdgeId]!;
      if (!_flController.linksById.containsKey(flLinkId)) {
        _ourEdgeIdToFlLinkId.remove(ourEdgeId);
        _flLinkIdToOurEdgeId.remove(flLinkId);
        controller.removeEdge(ourEdgeId);
      }
    }

    // Links drawn on the canvas.
    for (final entry in _flController.linksById.entries) {
      if (_flLinkIdToOurEdgeId.containsKey(entry.key)) continue;
      final link = entry.value;
      final fromOurId = _flIdToOurNodeId[link.fromTo.from];
      // In 1.0.2, fromPort is actually the destination node id and to is
      // the source port id; the record field names are misleading.
      final toOurId = _flIdToOurNodeId[link.fromTo.fromPort];
      if (fromOurId == null || toOurId == null) continue;

      final error = controller.addEdge(fromOurId, toOurId, link.fromTo.toPort);
      if (error != null) {
        // Our own cycle/port-arity check rejected something fl_nodes'
        // own (looser) validation allowed — undo it on the canvas too so
        // the two stay in sync, and tell the user why.
        _suppressFlEvents = true;
        _flController.removeLinkById(entry.key);
        _suppressFlEvents = false;
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
        continue;
      }
      // Find the just-created PipelineEdge by its (from,to,toPort) triple
      // to record the id mapping — addEdge doesn't hand the new id back
      // directly, so look it up from the freshly-updated graph instead.
      final newEdge =
          ref.read(pipelineControllerProvider).graph.edges.lastWhere(
                (e) =>
                    e.fromNodeId == fromOurId &&
                    e.toNodeId == toOurId &&
                    e.toPortId == link.fromTo.toPort,
              );
      _ourEdgeIdToFlLinkId[newEdge.id] = entry.key;
      _flLinkIdToOurEdgeId[entry.key] = newEdge.id;
    }

    // Selection → inspector panel.
    final selectedFlId = _flController.selectedNodeIds.isEmpty
        ? null
        : _flController.selectedNodeIds.first;
    widget.onSelectionChanged(
        selectedFlId == null ? null : _flIdToOurNodeId[selectedFlId]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pipelineControllerProvider.select((s) => s.graph), (prev, next) {
      _syncModelToCanvas(prev, next);
    });

    return Stack(
      children: [
        Positioned.fill(
          child: fln.FlNodeEditorWidget(
            controller: _flController,
            overlay: () => const [],
          ),
        ),
        // arcane_nodes paints a hard-coded red viewport outline in debug
        // builds. Its editor has 8px of internal padding, so this slightly
        // wider blue outline covers that package debug chrome exactly and
        // keeps the canvas consistent with the rest of Commons Lens.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                border: Border.all(color: _kAccent, width: 1.3),
              ),
            ),
          ),
        ),
        // Live legend/HUD — see this file's top doc comment: the canvas
        // package can't host widgets inside a node, so a persistent,
        // always-visible readout of what each port color means (plus a
        // running node/edge count) is delivered as a corner overlay
        // instead. IgnorePointer keeps it from stealing pan/drag gestures
        // meant for the canvas underneath.
        const Positioned(
          top: 14,
          right: 14,
          child: IgnorePointer(child: _CanvasStatsBadge()),
        ),
      ],
    );
  }
}

class _CanvasStatsBadge extends ConsumerWidget {
  const _CanvasStatsBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pipelineControllerProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _kPanelBg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${state.graph.nodes.length} nodes  ·  ${state.graph.edges.length} edges',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final cat in PipelineNodeCategory.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: _categoryColor(cat),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(cat.name,
                        style: const TextStyle(
                            color: _kMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
