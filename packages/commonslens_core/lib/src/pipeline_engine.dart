/// Execution engine for the node pipeline. Two-phase per branch:
///
/// 1. COMPILE — walking forward from a Source node through an unbranched
///    chain of Filter nodes, each filter is folded into a single
///    [SearchState] via the same `copyWith` calls the advanced filters
///    drawer already uses (see [_applyFilterToState]). Nothing is fetched
///    yet — the branch stays a [NodeOutput.pending] the whole way.
/// 2. MATERIALIZE — the first time a branch hits something that can't stay
///    compiled (a Set-op's two-input join, a Transform, a Sink, or simply
///    the end of the graph). A Combine Constraints (AND) node is the exception:
///    it merges two still-pending branches into one pending [SearchState]. When
///    materialization is eventually required, that accumulated state is sent
///    to [CommonsBackend.search] (or `.geosearch`/`.authorUploads` for the
///    sources that don't go through CirrusSearch at all) and becomes a
///    plain `List<SearchItem>`.
///
/// Once a branch is materialized, any Filter node still downstream of it
/// falls back to a client-side predicate — but only for filter types where
/// [SearchItem] actually carries the field needed to check it honestly
/// (format, resolution, date range, exclude terms). License/Quality/
/// Language/Color-depth have no such field (SearchItem only carries a
/// human-readable license/assessments *string*, not the structured
/// statement or template CirrusSearch matched on), so those surface a
/// node-level warning and pass items through unfiltered rather than
/// silently mis-filtering — see [_hasClientSidePredicate].
///
/// This file is pure execution logic — no UI, no fl_nodes dependency, no
/// side-effecting exports. A Sink node here only validates/materializes
/// its input; actually writing a CSV/JSON/zip file or pushing into
/// searchControllerProvider is a UI-layer action performed by
/// PipelineController against this engine's result, the same separation
/// CommonsBackend already keeps from DownloadService.
library;

import 'search_models.dart';
import 'commons_backend.dart';
import 'pipeline_models.dart';

part 'pipeline_source_operations.dart';
part 'pipeline_collection_operations.dart';

// -----------------------------------------------------------------------------
// Node output
// -----------------------------------------------------------------------------

enum NodeRunStatus { idle, running, success, warning, error }

/// What one node produced. Exactly one of [pendingState] / [items] / [error]
/// is meaningful at a time — [isPending]/[isMaterialized]/[hasError] are the
/// checks every executor below actually uses rather than touching the
/// fields directly.
class NodeOutput {
  final SearchState? pendingState;
  final List<SearchItem>? items;
  final String? error;
  final String? warning;
  final int? totalHits;

  /// Export-oriented records aligned with [items]. Transforms may add
  /// enrichment fields or project columns without replacing SearchItem,
  /// which preview, ZIP download, and Send to Search still require.
  final List<Map<String, dynamic>>? records;

  const NodeOutput._({
    this.pendingState,
    this.items,
    this.error,
    this.warning,
    this.totalHits,
    this.records,
  });

  factory NodeOutput.pending(SearchState state) =>
      NodeOutput._(pendingState: state);

  factory NodeOutput.materialized(
    List<SearchItem> items, {
    int? totalHits,
    String? warning,
    List<Map<String, dynamic>>? records,
  }) =>
      NodeOutput._(
        items: items,
        totalHits: totalHits,
        warning: warning,
        records: records,
      );

  factory NodeOutput.errorResult(String message) =>
      NodeOutput._(error: message);

  bool get isPending => pendingState != null;
  bool get isMaterialized => items != null;
  bool get hasError => error != null;
}

class PipelineRunResult {
  final Map<String, NodeOutput> outputsByNodeId;
  final Map<String, NodeOutput> sinkOutputsByNodeId;

  const PipelineRunResult({
    required this.outputsByNodeId,
    required this.sinkOutputsByNodeId,
  });
}

// -----------------------------------------------------------------------------
// Cache — interface only. The IndexedDB-backed implementation lives in
// pipeline_cache.dart (next phase); tests / a headless run can pass null.
// -----------------------------------------------------------------------------

abstract class PipelineCache {
  /// Keyed by [CommonsBackend.buildQuerySignature] — the same stable
  /// signature already used elsewhere, so a query compiled by this engine
  /// hits the same cache entry a hand-run search with identical filters
  /// would.
  Future<List<SearchItem>?> getQueryResult(String signature);
  Future<void> putQueryResult(String signature, List<SearchItem> items);
}

// -----------------------------------------------------------------------------
// Execution context
// -----------------------------------------------------------------------------

class PipelineExecutionContext {
  final CommonsBackend backend;
  final PipelineCache? cache;

  /// Hard cap on items fetched per materialized branch. Commons has no
  /// concept of "give me everything" for a CirrusSearch query — this is
  /// the pipeline's own safety valve against an unbounded fetch loop.
  final int maxItemsPerSource;

  /// Preview mode swaps [maxItemsPerSource] for [previewCap] everywhere —
  /// the fast, cheap "see roughly what this looks like" run, as opposed to
  /// a full "Run" that respects the real per-source caps.
  final bool preview;
  final int previewCap;

  /// UI hook — called before a node starts, and once with its final
  /// status, so pipeline_page.dart can show a running/success/warning/
  /// error badge per node without the engine knowing anything about
  /// widgets.
  final void Function(String nodeId, NodeRunStatus status, {String? message})?
      onNodeStatus;

  PipelineExecutionContext({
    CommonsBackend? backend,
    this.cache,
    this.maxItemsPerSource = 500,
    this.preview = false,
    this.previewCap = 20,
    this.onNodeStatus,
  }) : backend = backend ?? CommonsBackend();

  int get effectiveMaxItems => preview ? previewCap : maxItemsPerSource;
}

// -----------------------------------------------------------------------------
// Small config-reading helpers — same defensive, never-throws style as
// SearchUrlCodec's parsing, since node.config is untyped JSON that may have
// been hand-edited in an exported graph file.
// -----------------------------------------------------------------------------

String _cfgString(Map<String, dynamic> c, String key, [String fallback = '']) =>
    c[key] as String? ?? fallback;

double? _cfgDouble(Map<String, dynamic> c, String key) =>
    (c[key] as num?)?.toDouble();

int? _cfgInt(Map<String, dynamic> c, String key) => (c[key] as num?)?.toInt();

bool _cfgBool(Map<String, dynamic> c, String key, [bool fallback = false]) =>
    c[key] as bool? ?? fallback;

List<String> _cfgStringList(Map<String, dynamic> c, String key) {
  final raw = c[key];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (raw is String && raw.isNotEmpty) return [raw];
  return const [];
}

T? _firstWhereOrNull<T>(Iterable<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Which filter types have an honest client-side predicate once a branch is
// already materialized — see this file's top doc comment for why the rest
// don't. Kept here rather than on PipelineNodeTypeX in pipeline_models.dart
// purely because it's an execution-engine concern, not a structural one.
// -----------------------------------------------------------------------------

bool _hasClientSidePredicate(PipelineNodeType type) {
  switch (type) {
    case PipelineNodeType.filterFormat:
    case PipelineNodeType.filterResolution:
    case PipelineNodeType.filterDateRange:
    case PipelineNodeType.filterExcludeTerms:
      return true;
    default:
      return false;
  }
}

// -----------------------------------------------------------------------------
// Engine
// -----------------------------------------------------------------------------

class PipelineEngine
    with _PipelineSourceOperations, _PipelineCollectionOperations {
  /// Runs every node in [graph] in dependency order. Throws
  /// [PipelineCycleError] (from [PipelineGraph.topologicalOrder]) if the
  /// graph isn't a DAG — callers should validate the graph before calling
  /// this, not rely on catching it here.
  Future<PipelineRunResult> run(
    PipelineGraph graph,
    PipelineExecutionContext ctx,
  ) async {
    final order = graph.topologicalOrder();
    final outputs = <String, NodeOutput>{};
    final sinkOutputs = <String, NodeOutput>{};

    for (final node in order) {
      ctx.onNodeStatus?.call(node.id, NodeRunStatus.running);

      NodeOutput output;
      try {
        final inputs = graph
            .incomingEdges(node.id)
            .map((e) => MapEntry(e.toPortId, outputs[e.fromNodeId]))
            .where((e) => e.value != null)
            .map((e) => MapEntry(e.key, e.value!))
            .toList();
        output = await _executeNode(node, inputs, ctx);
      } catch (e) {
        output = NodeOutput.errorResult(e.toString());
      }

      outputs[node.id] = output;
      if (node.type.isSink) sinkOutputs[node.id] = output;

      if (output.hasError) {
        ctx.onNodeStatus
            ?.call(node.id, NodeRunStatus.error, message: output.error);
      } else if (output.warning != null) {
        ctx.onNodeStatus
            ?.call(node.id, NodeRunStatus.warning, message: output.warning);
      } else {
        ctx.onNodeStatus?.call(
          node.id,
          NodeRunStatus.success,
          message: output.isMaterialized
              ? '${output.items!.length} items'
              : 'compiled',
        );
      }
    }

    return PipelineRunResult(
        outputsByNodeId: outputs, sinkOutputsByNodeId: sinkOutputs);
  }

  Future<NodeOutput> _executeNode(
    PipelineNode node,
    List<MapEntry<String, NodeOutput>> inputs,
    PipelineExecutionContext ctx,
  ) {
    switch (node.type.category) {
      case PipelineNodeCategory.source:
        return _executeSource(node, ctx);
      case PipelineNodeCategory.filter:
        return _executeFilter(node, inputs, ctx);
      case PipelineNodeCategory.setOp:
        return _executeSetOp(node, inputs, ctx);
      case PipelineNodeCategory.transform:
        return _executeTransform(node, inputs, ctx);
      case PipelineNodeCategory.sink:
        return _executeSink(node, inputs, ctx);
    }
  }

  // ---------------------------------------------------------------------
  // Source
  // ---------------------------------------------------------------------
}
