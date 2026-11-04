/// Riverpod wrapper around [PipelineEngine] + [PipelineIndexedDbCache] —
/// same "engine is plain Dart, this just adapts it onto Notifier" split as
/// SearchController does for CommonsSearchSession. Owns the live
/// [PipelineGraph] being edited, per-node run status for the canvas UI's
/// badges, and the side-effecting half of Sink nodes (writing files,
/// pushing into the main search grid) that [PipelineEngine] deliberately
/// leaves undone — see that file's class doc.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_service.dart';
import 'pipeline_cache.dart';
import 'pipeline_engine.dart';
import 'pipeline_manifest.dart';
import 'pipeline_models.dart';
import 'search_controller.dart';
import 'search_models.dart';
import 'backend_providers.dart';
import 'wikimedia_download_client.dart';

// -----------------------------------------------------------------------------
// View state
// -----------------------------------------------------------------------------

/// One node's last-known run status + human-readable message (item count,
/// warning, or error) — what the canvas's per-node badges read.
class PipelineNodeStatus {
  final NodeRunStatus status;
  final String? message;

  const PipelineNodeStatus({this.status = NodeRunStatus.idle, this.message});
}

class PipelineViewState {
  final PipelineGraph graph;
  final Map<String, PipelineNodeStatus> nodeStatus;
  final bool isRunning;
  final bool isPaused;
  final bool preview;
  final int fetchedRecords;
  final int? totalRecords;
  final bool runCancelled;

  /// Top-level failure surfaced by the controller: graph validation failures
  /// or uncaught execution failures. Node-level failures remain attached to
  /// their node so independent branches can still finish.
  final String? runError;

  final List<PipelineGraph> savedGraphs;
  final bool loadingSavedGraphs;

  const PipelineViewState({
    required this.graph,
    this.nodeStatus = const {},
    this.isRunning = false,
    this.isPaused = false,
    this.preview = false,
    this.fetchedRecords = 0,
    this.totalRecords,
    this.runCancelled = false,
    this.runError,
    this.savedGraphs = const [],
    this.loadingSavedGraphs = false,
  });

  PipelineViewState copyWith({
    PipelineGraph? graph,
    Map<String, PipelineNodeStatus>? nodeStatus,
    bool? isRunning,
    bool? isPaused,
    bool? preview,
    int? fetchedRecords,
    int? totalRecords,
    bool clearTotalRecords = false,
    bool? runCancelled,
    String? runError,
    bool clearRunError = false,
    List<PipelineGraph>? savedGraphs,
    bool? loadingSavedGraphs,
  }) {
    return PipelineViewState(
      graph: graph ?? this.graph,
      nodeStatus: nodeStatus ?? this.nodeStatus,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      preview: preview ?? this.preview,
      fetchedRecords: fetchedRecords ?? this.fetchedRecords,
      totalRecords:
          clearTotalRecords ? null : (totalRecords ?? this.totalRecords),
      runCancelled: runCancelled ?? this.runCancelled,
      runError: clearRunError ? null : (runError ?? this.runError),
      savedGraphs: savedGraphs ?? this.savedGraphs,
      loadingSavedGraphs: loadingSavedGraphs ?? this.loadingSavedGraphs,
    );
  }
}

// -----------------------------------------------------------------------------
// Id generation — timestamp + a per-run counter, unique enough for a
// client-only graph editor with no concurrent multi-user writers.
// -----------------------------------------------------------------------------

int _idCounter = 0;
String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

PipelineGraph _newStarterGraph() {
  final queryId = _newId('node');
  final formatFilterId = _newId('node');
  final manifestId = _newId('node');

  return PipelineGraph(
    id: _newId('graph'),
    name: 'Untitled Pipeline',
    updatedAt: DateTime.now(),
    nodes: [
      PipelineNode(
        id: queryId,
        type: PipelineNodeType.sourceTextQuery,
        x: -360,
        y: -96,
        config: const {'query': 'Wikipedia'},
      ),
      PipelineNode(
        id: formatFilterId,
        type: PipelineNodeType.filterFormat,
        x: 0,
        y: -96,
        config: const {
          'formats': ['png'],
        },
      ),
      PipelineNode(
        id: manifestId,
        type: PipelineNodeType.sinkCsvExport,
        x: 360,
        y: -96,
        config: const {'imageLinks': 'both'},
      ),
    ],
    edges: [
      PipelineEdge(
        id: _newId('edge'),
        fromNodeId: queryId,
        fromPortId: 'out',
        toNodeId: formatFilterId,
        toPortId: 'in',
      ),
      PipelineEdge(
        id: _newId('edge'),
        fromNodeId: formatFilterId,
        fromPortId: 'out',
        toNodeId: manifestId,
        toPortId: 'in',
      ),
    ],
  );
}

// -----------------------------------------------------------------------------
// Providers
// -----------------------------------------------------------------------------

final pipelineCacheProvider =
    Provider<PipelineIndexedDbCache>((ref) => PipelineIndexedDbCache());

final pipelineControllerProvider =
    NotifierProvider<PipelineController, PipelineViewState>(
        PipelineController.new);

// -----------------------------------------------------------------------------
// Controller
// -----------------------------------------------------------------------------

class PipelineController extends Notifier<PipelineViewState> {
  final PipelineEngine _engine = PipelineEngine();
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  /// The last run's materialized outputs, keyed by node id — read by the
  /// sink actions and the full-screen dataset preview. Deliberately not
  /// part of [PipelineViewState] (not serialized, not persisted): runtime
  /// scratch only, rebuilt from scratch by every [run].
  Map<String, NodeOutput> _lastOutputs = {};

  PipelineIndexedDbCache get _cache => ref.read(pipelineCacheProvider);

  @override
  PipelineViewState build() {
    final graph = _newStarterGraph();
    // Fire-and-forget — the editor is usable immediately; savedGraphs
    // populates once IndexedDB responds.
    unawaited(Future<void>.microtask(_loadSavedGraphs));
    return PipelineViewState(graph: graph);
  }

  Future<void> _loadSavedGraphs() async {
    state = state.copyWith(loadingSavedGraphs: true);
    final graphs = await _cache.listGraphs();
    state = state.copyWith(savedGraphs: graphs, loadingSavedGraphs: false);
  }

  /// Autosave — matches the "IndexedDB, survives reload" persistence
  /// decision: there is no separate explicit "Save" step for the graph
  /// currently being edited (only for a named export via [exportGraph]).
  /// Fire-and-forget; a failed write just means this particular edit
  /// isn't persisted, never blocks the UI (see
  /// [PipelineIndexedDbCache]'s own best-effort contract).
  void _persist() => unawaited(_cache.saveGraph(state.graph));

  // ---------------------------------------------------------------------
  // Graph editing — called from the canvas UI's node/edge callbacks.
  // ---------------------------------------------------------------------

  String addNode(
    PipelineNodeType type, {
    double x = 0,
    double y = 0,
    String? title,
    Map<String, dynamic>? config,
  }) {
    final node = PipelineNode(
      id: _newId('node'),
      type: type,
      title: title,
      x: x,
      y: y,
      config: config,
    );
    state = state.copyWith(
      graph: state.graph.copyWith(
          nodes: [...state.graph.nodes, node], updatedAt: DateTime.now()),
    );
    _persist();
    return node.id;
  }

  /// Copies [nodeId]'s type and config (but not its edges — a duplicate
  /// starts unconnected) into a new node offset slightly down-right so it
  /// doesn't sit exactly on top of the original. Surfaced from the
  /// inspector panel's header as a quick per-node action.
  void duplicateNode(String nodeId) {
    final original = state.graph.nodeById(nodeId);
    if (original == null) return;
    final copy = PipelineNode(
      id: _newId('node'),
      type: original.type,
      title: '${original.title} copy',
      x: original.x + 48,
      y: original.y + 48,
      config: Map<String, dynamic>.from(original.config),
    );
    state = state.copyWith(
      graph: state.graph.copyWith(
          nodes: [...state.graph.nodes, copy], updatedAt: DateTime.now()),
    );
    _persist();
  }

  void removeNode(String nodeId) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes.where((n) => n.id != nodeId).toList(),
        edges: state.graph.edges
            .where((e) => e.fromNodeId != nodeId && e.toNodeId != nodeId)
            .toList(),
        updatedAt: DateTime.now(),
      ),
      nodeStatus: {...state.nodeStatus}..remove(nodeId),
    );
    _persist();
  }

  void moveNode(String nodeId, double x, double y) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes
            .map((n) => n.id == nodeId ? n.copyWith(x: x, y: y) : n)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
  }

  void updateNodeConfig(String nodeId, Map<String, dynamic> config) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes
            .map((n) => n.id == nodeId ? n.copyWith(config: config) : n)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
  }

  void renameNode(String nodeId, String title) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        nodes: state.graph.nodes
            .map((n) => n.id == nodeId ? n.copyWith(title: title) : n)
            .toList(),
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
  }

  /// Checks whether a candidate edge is legal, without adding it — the
  /// canvas UI should call this from its own "would-connect" hook (fl_nodes
  /// fires one before actually drawing a link) and reject the gesture
  /// itself, rather than calling [addEdge] and rolling back on failure.
  /// Every input port ([defaultPortsFor] in pipeline_models.dart never
  /// hands out more than one 'in', 'a', or 'b' per node) accepts exactly
  /// one edge — a second edge into the same port must replace the first
  /// via [removeEdge], not stack silently.
  String? validateEdge(String fromNodeId, String toNodeId, String toPortId) {
    if (fromNodeId == toNodeId) return "A node can't connect to itself.";

    final toNode = state.graph.nodeById(toNodeId);
    if (toNode == null) return 'Unknown target node.';
    if (toNode.type.maxInputs == 0) return '${toNode.title} has no input port.';

    final alreadyOnPort = state.graph.edges
        .any((e) => e.toNodeId == toNodeId && e.toPortId == toPortId);
    if (alreadyOnPort) {
      return '${toNode.title}\'s "$toPortId" input is already connected.';
    }

    final trial = state.graph.copyWith(edges: [
      ...state.graph.edges,
      PipelineEdge(
        id: '_trial',
        fromNodeId: fromNodeId,
        fromPortId: 'out',
        toNodeId: toNodeId,
        toPortId: toPortId,
      ),
    ]);
    try {
      trial.topologicalOrder();
    } on PipelineCycleError {
      return 'That connection would create a cycle.';
    }
    return null;
  }

  /// Returns an error message on failure (for the UI to surface as a
  /// snackbar/toast), or null on success.
  String? addEdge(String fromNodeId, String toNodeId, String toPortId) {
    final error = validateEdge(fromNodeId, toNodeId, toPortId);
    if (error != null) return error;

    state = state.copyWith(
      graph: state.graph.copyWith(
        edges: [
          ...state.graph.edges,
          PipelineEdge(
            id: _newId('edge'),
            fromNodeId: fromNodeId,
            fromPortId: 'out',
            toNodeId: toNodeId,
            toPortId: toPortId,
          ),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
    return null;
  }

  void removeEdge(String edgeId) {
    state = state.copyWith(
      graph: state.graph.copyWith(
        edges: state.graph.edges.where((e) => e.id != edgeId).toList(),
        updatedAt: DateTime.now(),
      ),
    );
    _persist();
  }

  // ---------------------------------------------------------------------
  // Run / Preview
  // ---------------------------------------------------------------------

  Future<void> run({
    bool preview = false,
    bool unlimitedCsvExport = false,
    bool includeThumbnailUrls = true,
    bool includeAttributionMetadata = true,
  }) async {
    if (state.isRunning) return;

    if (!state.graph.nodes
        .any((node) => node.type == PipelineNodeType.sinkCsvExport)) {
      state = state.copyWith(
        runError:
            'Add a Dataset Manifest (CSV) sink before running the pipeline.',
      );
      return;
    }

    // Cycle-check up front rather than letting PipelineEngine.run throw
    // past this method — same check, just surfaced as a single top-level
    // runError instead of an uncaught exception mid-execution.
    try {
      state.graph.topologicalOrder();
    } on PipelineCycleError catch (e) {
      state = state.copyWith(runError: e.message);
      return;
    }

    _pauseRequested = false;
    _cancelRequested = false;
    state = state.copyWith(
      isRunning: true,
      isPaused: false,
      preview: preview,
      fetchedRecords: 0,
      clearTotalRecords: true,
      runCancelled: false,
      clearRunError: true,
      nodeStatus: {
        for (final n in state.graph.nodes) n.id: const PipelineNodeStatus(),
      },
    );

    final ctx = PipelineExecutionContext(
      backend: ref.read(commonsBackendProvider),
      cache: _cache,
      maxItemsPerSource: unlimitedCsvExport ? null : _maxItemsPerSourceForRun(),
      unlimitedCsvExport: unlimitedCsvExport,
      includeThumbnailUrls: includeThumbnailUrls,
      requestProfile: _requestProfile(
        preview: preview,
        includeAttributionMetadata: includeAttributionMetadata,
      ),
      preview: preview,
      beforeFetchPage: _waitForFetchPermission,
      onFetchProgress: (fetched, totalHits) {
        state = state.copyWith(
          fetchedRecords: fetched,
          totalRecords: totalHits,
        );
      },
      onNodeStatus: (nodeId, status, {message}) {
        state = state.copyWith(nodeStatus: {
          ...state.nodeStatus,
          nodeId: PipelineNodeStatus(status: status, message: message),
        });
      },
    );

    try {
      final result = await _engine.run(state.graph, ctx);
      _lastOutputs = result.outputsByNodeId;
    } catch (e) {
      state = state.copyWith(runError: e.toString());
    } finally {
      state = state.copyWith(
        isRunning: false,
        isPaused: false,
        runCancelled: _cancelRequested,
      );
      _pauseRequested = false;
    }
  }

  /// Keep media-oriented browser runs bounded. CSV generation opts into its
  /// own unlimited continuation mode and never sends all those records to an
  /// image grid or the main Search page.
  int _maxItemsPerSourceForRun() => 1000;

  SearchRequestProfile _requestProfile({
    required bool preview,
    required bool includeAttributionMetadata,
  }) {
    if (preview) {
      return includeAttributionMetadata
          ? SearchRequestProfile.pipelinePreviewWithRights
          : SearchRequestProfile.pipelinePreview;
    }
    return includeAttributionMetadata
        ? SearchRequestProfile.pipelineEtlWithRights
        : SearchRequestProfile.pipelineEtl;
  }

  Future<bool> _waitForFetchPermission() async {
    while (_pauseRequested && !_cancelRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return !_cancelRequested;
  }

  void pauseRun() {
    if (!state.isRunning || state.isPaused) return;
    _pauseRequested = true;
    state = state.copyWith(isPaused: true);
  }

  void resumeRun() {
    if (!state.isRunning || !state.isPaused) return;
    _pauseRequested = false;
    state = state.copyWith(isPaused: false);
  }

  void cancelRun() {
    if (!state.isRunning) return;
    _cancelRequested = true;
    _pauseRequested = false;
    state = state.copyWith(isPaused: false, runCancelled: true);
  }

  // ---------------------------------------------------------------------
  // Reading a node's last result — for the full-screen dataset preview and
  // the sink actions below. Public because pipeline_page.dart needs it too,
  // not just this controller.
  // ---------------------------------------------------------------------

  NodeOutput? outputFor(String nodeId) => _lastOutputs[nodeId];

  List<SearchItem>? materializedItemsFor(String nodeId) {
    final output = _lastOutputs[nodeId];
    if (output == null || !output.isMaterialized) return null;
    // CSV export reads the raw sink output directly. Every media-oriented
    // consumer gets an audit-sized window even when the preceding CSV run
    // fetched every continuation page.
    return output.items!.take(1000).toList();
  }

  /// Raw count for export confirmations. Unlike [materializedItemsFor], this
  /// is not capped because a CSV generation run may have fetched every page.
  int? materializedItemCountFor(String nodeId) {
    final output = _lastOutputs[nodeId];
    return (output != null && output.isMaterialized)
        ? output.items!.length
        : null;
  }

  // ---------------------------------------------------------------------
  // Sink actions — the side-effecting half of a Sink node that
  // PipelineEngine deliberately leaves undone (see its class doc). Each
  // reads _lastOutputs from the most recent [run] rather than re-running
  // the graph, so exporting never triggers a second fetch.
  // ---------------------------------------------------------------------

  Future<String?> exportSinkCsv(String nodeId,
      {String fileName = 'pipeline_export'}) async {
    final output = _lastOutputs[nodeId];
    if (output?.hasError == true) return output!.error;
    if (output == null || !output.isMaterialized) {
      return 'Run the pipeline before exporting.';
    }
    final node = state.graph.nodeById(nodeId);
    if (node == null) return 'That manifest node no longer exists.';

    final links =
        manifestImageLinksFromName(node.config['imageLinks'] as String?);
    final hasFieldSelect =
        _hasUpstreamType(nodeId, PipelineNodeType.transformFieldSelect);
    final records = buildManifestRecords(
      output.items!,
      metadataLevel: ManifestMetadataLevel.detailed,
      imageLinks: links,
      projectedRecords: hasFieldSelect ? output.records : null,
      additionalRecords: hasFieldSelect ? null : output.records,
    );
    try {
      await DownloadService.downloadCsvRecords(records, fileName);
      final warning = output.warning;
      return warning == null ? null : 'CSV downloaded with warning: $warning';
    } on DownloadSecurityException catch (error) {
      return error.message;
    }
  }

  /// Runs at manifest scale and then starts the browser download. Keeping
  /// this as one action means users do not need to understand the internal
  /// split between pipeline execution and sink side effects.
  Future<String?> generateManifest(String nodeId,
      {String fileName = 'commonslens_manifest'}) async {
    if (state.isRunning) return 'A pipeline run is already in progress.';
    final node = state.graph.nodeById(nodeId);
    if (node == null) return 'That manifest node no longer exists.';
    final links =
        manifestImageLinksFromName(node.config['imageLinks'] as String?);
    await run(
      preview: false,
      unlimitedCsvExport: true,
      includeThumbnailUrls: links != ManifestImageLinks.original,
      includeAttributionMetadata: attributionMetadataRequestedFor(nodeId),
    );
    if (state.runCancelled) {
      return 'Manifest generation was cancelled; no file was downloaded.';
    }
    if (state.runError != null) return state.runError;
    final outputError = _lastOutputs[nodeId]?.error;
    if (outputError != null) return outputError;
    return exportSinkCsv(nodeId, fileName: fileName);
  }

  bool _hasUpstreamType(String nodeId, PipelineNodeType type) {
    final pending = <String>[nodeId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      for (final edge in state.graph.incomingEdges(current)) {
        final upstream = state.graph.nodeById(edge.fromNodeId);
        if (upstream == null) continue;
        if (upstream.type == type) return true;
        pending.add(upstream.id);
      }
    }
    return false;
  }

  /// Rights metadata is enabled by default on a Dataset Manifest. An upstream
  /// Enrich node that explicitly asks for attribution also forces it on, so a
  /// user cannot accidentally configure the graph to request rights data and
  /// then omit it from the manifest run.
  bool attributionMetadataRequestedFor(String nodeId) {
    final node = state.graph.nodeById(nodeId);
    if (node == null) return true;
    final manifestEnabled = node.config['includeAttribution'] as bool? ?? true;
    return manifestEnabled || _hasUpstreamAttributionRequest(nodeId);
  }

  bool _hasUpstreamAttributionRequest(String nodeId) {
    final pending = <String>[nodeId];
    final visited = <String>{};
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      for (final edge in state.graph.incomingEdges(current)) {
        final upstream = state.graph.nodeById(edge.fromNodeId);
        if (upstream == null) continue;
        if (upstream.type == PipelineNodeType.transformEnrich &&
            upstream.config['attribution'] == true) {
          return true;
        }
        pending.add(upstream.id);
      }
    }
    return false;
  }

  /// Pipes a Sink node's result into the main SearchPage's results grid —
  /// see SearchController.loadExternalResults for why this is a
  /// non-paginated, filter-chip-clearing display rather than a real
  /// search.
  String? sendToSearch(String nodeId) {
    final items = materializedItemsFor(nodeId);
    if (items == null) return 'Run the pipeline before sending to Search.';
    ref
        .read(searchControllerProvider.notifier)
        .loadExternalResults(items, sourceNodeId: nodeId);
    return null;
  }

  // ---------------------------------------------------------------------
  // Named saves / new / load / delete / export / import
  // ---------------------------------------------------------------------

  void newGraph() {
    state = PipelineViewState(
      graph: _newStarterGraph(),
      savedGraphs: state.savedGraphs,
    );
    _lastOutputs = {};
  }

  void renameGraph(String name) {
    state = state.copyWith(
        graph: state.graph.copyWith(name: name, updatedAt: DateTime.now()));
    _persist();
  }

  Future<void> loadGraph(String id) async {
    final graph = await _cache.loadGraph(id);
    if (graph == null) return;
    state =
        state.copyWith(graph: graph, nodeStatus: const {}, clearRunError: true);
    _lastOutputs = {};
  }

  Future<void> deleteGraph(String id) async {
    await _cache.deleteGraph(id);
    await _loadSavedGraphs();
  }

  Future<void> refreshSavedGraphs() => _loadSavedGraphs();

  /// The "shareable file" half of the persistence decision, independent
  /// of the IndexedDB autosave — a plain [PipelineGraph.toJson] the UI
  /// hands off to a file download.
  Map<String, dynamic> exportGraph() => state.graph.toJson();

  void importGraph(Map<String, dynamic> json) {
    final graph = PipelineGraph.fromJson(json);
    state =
        state.copyWith(graph: graph, nodeStatus: const {}, clearRunError: true);
    _lastOutputs = {};
    _persist();
  }

  Future<void> clearCache() => _cache.clearCache();
}
