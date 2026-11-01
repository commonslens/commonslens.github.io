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
/// its input; actually writing a metadata CSV or pushing into
/// searchControllerProvider is a UI-layer action performed by
/// PipelineController against this engine's result, the same separation
/// CommonsBackend already keeps from DownloadService.
library;

import 'search_models.dart';
import 'search_request_profile.dart';
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
  /// which preview and Send to Search still require.
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

/// A resumable source-cache snapshot. [items] is the exact prefix already
/// fetched, [continueToken] is Wikimedia's opaque cursor for the next page,
/// and [complete] distinguishes "we reached the end" from "we stopped at a
/// preview/run cap". Keeping the cursor is what lets a full run continue a
/// preview without replaying or skipping its first page(s). [pageSize] records
/// the source request size so a 200-row ETL run can bridge a cached 50-row
/// preview at the boundary without overlapping API results.
class PipelineQuerySnapshot {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueToken;
  final int? totalHits;
  final bool complete;
  final List<String> warnings;
  final int? pageSize;

  const PipelineQuerySnapshot({
    required this.items,
    required this.continueToken,
    required this.totalHits,
    required this.complete,
    this.warnings = const [],
    this.pageSize,
  });
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
  Future<PipelineQuerySnapshot?> getQuerySnapshot(String signature);
  Future<void> putQuerySnapshot(
      String signature, PipelineQuerySnapshot snapshot);

  /// Raw non-extmetadata enrichment payload keyed by file revision and the
  /// selected metadata bundle. Keeping this separate prevents large
  /// enrichment responses from being duplicated in every query cache entry.
  Future<Map<String, dynamic>?> getMetadata(String key);
  Future<void> putMetadata(String key, Map<String, dynamic> metadata);
}

// -----------------------------------------------------------------------------
// Execution context
// -----------------------------------------------------------------------------

class PipelineExecutionContext {
  final CommonsBackend backend;
  final PipelineCache? cache;

  /// Hard cap on items fetched per materialized branch. Null remains available
  /// to non-UI callers that explicitly need continuation exhaustion; the
  /// browser controller always supplies the 1,000-record safety cap.
  final int? maxItemsPerSource;

  /// Dataset CSV generation deliberately exhausts continuation pages. The
  /// controller still caps media-oriented views separately before they reach
  /// Preview or Send to Search.
  final bool unlimitedCsvExport;

  /// Whether the source request needs Wikimedia-scaled image URLs. Full-size
  /// CSV manifests do not need them; omitting thumbnail scaling lets Commons
  /// return the complete 200-row imageinfo batch instead of applying its
  /// 50-scaled-image performance limit.
  final bool includeThumbnailUrls;

  /// Pipeline previews remain UI-sized. The manifest ETL run opts into the
  /// larger batch explicitly through the caller.
  final SearchRequestProfile requestProfile;

  /// Preview mode swaps [maxItemsPerSource] for [previewCap] everywhere —
  /// the fast, cheap "see roughly what this looks like" run, as opposed to
  /// a full "Run" that respects the real per-source caps.
  final bool preview;
  final int previewCap;

  /// Called after each fetched page so the UI can report record progress.
  final void Function(int fetched, int? totalHits)? onFetchProgress;

  /// Called before each network page. It may wait while a run is paused;
  /// false asks the engine to stop pagination and retain the partial result.
  final Future<bool> Function()? beforeFetchPage;

  /// UI hook — called before a node starts, and once with its final
  /// status, so pipeline_page.dart can show a running/success/warning/
  /// error badge per node without the engine knowing anything about
  /// widgets.
  final void Function(String nodeId, NodeRunStatus status, {String? message})?
      onNodeStatus;

  PipelineExecutionContext({
    CommonsBackend? backend,
    this.cache,
    this.maxItemsPerSource = 1000,
    this.unlimitedCsvExport = false,
    this.includeThumbnailUrls = true,
    this.requestProfile = SearchRequestProfile.ui,
    this.preview = false,
    this.previewCap = 100,
    this.onFetchProgress,
    this.beforeFetchPage,
    this.onNodeStatus,
  }) : backend = backend ?? CommonsBackend();

  int? get effectiveMaxItems => preview ? previewCap : maxItemsPerSource;

  bool shouldFetchMore(int itemCount) =>
      effectiveMaxItems == null || itemCount < effectiveMaxItems!;

  List<SearchItem> applyItemLimit(List<SearchItem> items) {
    final limit = effectiveMaxItems;
    if (limit == null || items.length <= limit) return items;
    return items.sublist(0, limit);
  }
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
