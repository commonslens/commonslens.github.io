/// Data model for the node-based ETL pipeline (the "Blender for Commons"
/// feature). Pure data + JSON serialization only — no execution logic here
/// (see pipeline_engine.dart), no UI (see pipeline_page.dart). This mirrors
/// how search_models.dart stays a plain data layer that search_service.dart
/// and search_controller.dart build behavior on top of.
library;

// -----------------------------------------------------------------------------
// Node types
// -----------------------------------------------------------------------------

/// Broad behavioral class of a node — drives both palette grouping in the
/// UI and, critically, how [PipelineEngine] executes it: [source] and
/// [filter] nodes are eligible for query-compilation (folded into a single
/// CirrusSearch request via SearchState.copyWith) as long as they sit in an
/// unbranched chain; [setOp] and [transform] nodes always operate on
/// already-materialized SearchItem lists; [sink] nodes are always terminal.
enum PipelineNodeCategory { source, filter, setOp, transform, sink }

enum PipelineNodeType {
  // --- Source (0 inputs, 1 output) ---
  sourceTextQuery,
  sourceCategory,
  sourceDepicts,
  sourceStatement,
  sourceTemplate,
  sourceGeosearch,
  sourceAuthor,
  sourceMorelike,

  // --- Filter (1 input, 1 output) — query-compilable: see
  // PipelineNodeCategory.filter's doc above. Each of these corresponds
  // directly to a SearchState field/copyWith call already in
  // search_models.dart, so compiling one into an upstream chain is just
  // accumulating copyWith calls, not new query-building logic. ---
  filterLicense,
  filterQuality,
  filterFormat,
  filterResolution,
  filterFileSize,
  filterColorDepth,
  filterDateRange,
  filterLanguage,
  filterExcludeTerms,

  // --- Set-op (2 inputs, 1 output). Combine Constraints keeps two pending
  // query branches server-side; the remaining operations merge materialized
  // item lists by URL. ---
  setCombineAnd,
  setUnion,
  setIntersect,
  setDifference,

  // --- Transform (1 input, 1 output) — always client-side. ---
  transformDedupe,
  transformSort,
  transformSample,
  transformFieldSelect,
  transformEnrich, // per-item Structured Data / Global Usage — opt-in, rate-limited

  // --- Sink (1 input, 0 outputs) — terminal. ---
  sinkCsvExport,
  sinkJsonExport,
  sinkZipExport,
  sinkPreview,
  sinkSendToSearch,
}

extension PipelineNodeTypeX on PipelineNodeType {
  PipelineNodeCategory get category {
    switch (this) {
      case PipelineNodeType.sourceTextQuery:
      case PipelineNodeType.sourceCategory:
      case PipelineNodeType.sourceDepicts:
      case PipelineNodeType.sourceStatement:
      case PipelineNodeType.sourceTemplate:
      case PipelineNodeType.sourceGeosearch:
      case PipelineNodeType.sourceAuthor:
      case PipelineNodeType.sourceMorelike:
        return PipelineNodeCategory.source;
      case PipelineNodeType.filterLicense:
      case PipelineNodeType.filterQuality:
      case PipelineNodeType.filterFormat:
      case PipelineNodeType.filterResolution:
      case PipelineNodeType.filterFileSize:
      case PipelineNodeType.filterColorDepth:
      case PipelineNodeType.filterDateRange:
      case PipelineNodeType.filterLanguage:
      case PipelineNodeType.filterExcludeTerms:
        return PipelineNodeCategory.filter;
      case PipelineNodeType.setCombineAnd:
      case PipelineNodeType.setUnion:
      case PipelineNodeType.setIntersect:
      case PipelineNodeType.setDifference:
        return PipelineNodeCategory.setOp;
      case PipelineNodeType.transformDedupe:
      case PipelineNodeType.transformSort:
      case PipelineNodeType.transformSample:
      case PipelineNodeType.transformFieldSelect:
      case PipelineNodeType.transformEnrich:
        return PipelineNodeCategory.transform;
      case PipelineNodeType.sinkCsvExport:
      case PipelineNodeType.sinkJsonExport:
      case PipelineNodeType.sinkZipExport:
      case PipelineNodeType.sinkPreview:
      case PipelineNodeType.sinkSendToSearch:
        return PipelineNodeCategory.sink;
    }
  }

  /// How many upstream connections this node type accepts. Source nodes
  /// take none (they originate a branch); set-ops take exactly two
  /// (the two branches being combined); everything else takes exactly one.
  int get maxInputs {
    switch (category) {
      case PipelineNodeCategory.source:
        return 0;
      case PipelineNodeCategory.setOp:
        return 2;
      case PipelineNodeCategory.filter:
      case PipelineNodeCategory.transform:
      case PipelineNodeCategory.sink:
        return 1;
    }
  }

  /// Whether PipelineEngine may fold this node into an upstream SearchState
  /// via copyWith rather than materializing a separate fetch for it. Only
  /// true for filter nodes — and even then only actually folded when the
  /// engine finds an unbranched chain; see pipeline_engine.dart.
  bool get isQueryCompilable => category == PipelineNodeCategory.filter;

  bool get isSink => category == PipelineNodeCategory.sink;

  String get label {
    switch (this) {
      case PipelineNodeType.sourceTextQuery:
        return 'Text Query';
      case PipelineNodeType.sourceCategory:
        return 'Category';
      case PipelineNodeType.sourceDepicts:
        return 'Depicted Subject';
      case PipelineNodeType.sourceStatement:
        return 'Wikidata Statement';
      case PipelineNodeType.sourceTemplate:
        return 'Template';
      case PipelineNodeType.sourceGeosearch:
        return 'Geosearch';
      case PipelineNodeType.sourceAuthor:
        return 'Author Uploads';
      case PipelineNodeType.sourceMorelike:
        return 'Related To (morelike)';
      case PipelineNodeType.filterLicense:
        return 'License';
      case PipelineNodeType.filterQuality:
        return 'Quality';
      case PipelineNodeType.filterFormat:
        return 'Format';
      case PipelineNodeType.filterResolution:
        return 'Resolution';
      case PipelineNodeType.filterFileSize:
        return 'File Size';
      case PipelineNodeType.filterColorDepth:
        return 'Color Depth';
      case PipelineNodeType.filterDateRange:
        return 'Date Range';
      case PipelineNodeType.filterLanguage:
        return 'Language';
      case PipelineNodeType.filterExcludeTerms:
        return 'Exclude Terms';
      case PipelineNodeType.setCombineAnd:
        return 'Combine Constraints (AND)';
      case PipelineNodeType.setUnion:
        return 'Union';
      case PipelineNodeType.setIntersect:
        return 'Intersect';
      case PipelineNodeType.setDifference:
        return 'Difference';
      case PipelineNodeType.transformDedupe:
        return 'Dedupe';
      case PipelineNodeType.transformSort:
        return 'Sort';
      case PipelineNodeType.transformSample:
        return 'Sample / Limit';
      case PipelineNodeType.transformFieldSelect:
        return 'Field Select';
      case PipelineNodeType.transformEnrich:
        return 'Enrich (SDC / Usage)';
      case PipelineNodeType.sinkCsvExport:
        return 'Export CSV';
      case PipelineNodeType.sinkJsonExport:
        return 'Export JSON';
      case PipelineNodeType.sinkZipExport:
        return 'Export Zip';
      case PipelineNodeType.sinkPreview:
        return 'Preview';
      case PipelineNodeType.sinkSendToSearch:
        return 'Send to Search';
    }
  }
}

T _enumFromName<T extends Enum>(List<T> values, dynamic raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

// -----------------------------------------------------------------------------
// Ports
// -----------------------------------------------------------------------------

enum PipelinePortDirection { input, output }

/// A single connection point on a node. Every node currently deals in one
/// data kind (a list of SearchItem, i.e. a "MediaSet") so ports don't carry
/// a type tag yet — [id] is unique only within its own node, used to
/// disambiguate set-op nodes' two inputs ('a' / 'b') from each other.
class NodePort {
  final String id;
  final String label;
  final PipelinePortDirection direction;

  const NodePort({
    required this.id,
    required this.label,
    required this.direction,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'direction': direction.name,
      };

  static NodePort fromJson(Map<String, dynamic> json) => NodePort(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        direction: _enumFromName(PipelinePortDirection.values,
            json['direction'], PipelinePortDirection.input),
      );
}

/// Default port set for a node type — set-ops get two labeled inputs ('a'
/// nd 'b'), sources get no input, everything else gets one unlabeled
/// input. Every non-sink node gets a single output.
List<NodePort> defaultPortsFor(PipelineNodeType type) {
  final ports = <NodePort>[];
  switch (type.maxInputs) {
    case 0:
      break;
    case 2:
      ports.add(const NodePort(
          id: 'a', label: 'A', direction: PipelinePortDirection.input));
      ports.add(const NodePort(
          id: 'b', label: 'B', direction: PipelinePortDirection.input));
      break;
    default:
      ports.add(const NodePort(
          id: 'in', label: '', direction: PipelinePortDirection.input));
  }
  if (!type.isSink) {
    ports.add(const NodePort(
        id: 'out', label: '', direction: PipelinePortDirection.output));
  }
  return ports;
}

// -----------------------------------------------------------------------------
// Node
// -----------------------------------------------------------------------------

/// One node in the graph. [config] is intentionally a raw, node-type-specific
/// bag of JSON-primitive values rather than a typed subclass per node —
/// same "flat map, typed accessors read it" shape SearchUrlCodec already
/// uses for SearchState, which keeps serialization trivial and means adding
/// a new node type never requires touching the (de)serialization code here.
/// PipelineEngine's per-type executor is what actually knows how to read a
/// given node's config.
class PipelineNode {
  final String id;
  final PipelineNodeType type;
  final String title; // user-editable label, defaults to type.label
  final double x;
  final double y;
  final Map<String, dynamic> config;
  final List<NodePort> ports;

  PipelineNode({
    required this.id,
    required this.type,
    String? title,
    this.x = 0,
    this.y = 0,
    Map<String, dynamic>? config,
    List<NodePort>? ports,
  })  : title = title ?? type.label,
        config = config ?? const {},
        ports = ports ?? defaultPortsFor(type);

  PipelineNode copyWith({
    String? title,
    double? x,
    double? y,
    Map<String, dynamic>? config,
  }) {
    return PipelineNode(
      id: id,
      type: type,
      title: title ?? this.title,
      x: x ?? this.x,
      y: y ?? this.y,
      config: config ?? this.config,
      ports: ports,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'x': x,
        'y': y,
        'config': config,
        'ports': ports.map((p) => p.toJson()).toList(),
      };

  static PipelineNode fromJson(Map<String, dynamic> json) {
    final type = _enumFromName(PipelineNodeType.values, json['type'],
        PipelineNodeType.sourceTextQuery);
    final portsRaw = json['ports'];
    return PipelineNode(
      id: json['id'] as String? ?? '',
      type: type,
      title: json['title'] as String?,
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      config: json['config'] is Map
          ? Map<String, dynamic>.from(json['config'] as Map)
          : const {},
      ports: portsRaw is List
          ? portsRaw
              .whereType<Map>()
              .map((m) => NodePort.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : defaultPortsFor(type),
    );
  }
}

// -----------------------------------------------------------------------------
// Edge
// -----------------------------------------------------------------------------

class PipelineEdge {
  final String id;
  final String fromNodeId;
  final String
      fromPortId; // always 'out' today, kept explicit for future multi-output nodes
  final String toNodeId;
  final String toPortId; // 'in', or 'a'/'b' for set-op nodes

  const PipelineEdge({
    required this.id,
    required this.fromNodeId,
    required this.fromPortId,
    required this.toNodeId,
    required this.toPortId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromNodeId': fromNodeId,
        'fromPortId': fromPortId,
        'toNodeId': toNodeId,
        'toPortId': toPortId,
      };

  static PipelineEdge fromJson(Map<String, dynamic> json) => PipelineEdge(
        id: json['id'] as String? ?? '',
        fromNodeId: json['fromNodeId'] as String? ?? '',
        fromPortId: json['fromPortId'] as String? ?? 'out',
        toNodeId: json['toNodeId'] as String? ?? '',
        toPortId: json['toPortId'] as String? ?? 'in',
      );
}

// -----------------------------------------------------------------------------
// Graph
// -----------------------------------------------------------------------------

class PipelineCycleError extends Error {
  final String message;
  PipelineCycleError(this.message);
  @override
  String toString() => 'PipelineCycleError: $message';
}

/// The full graph — what gets stored in IndexedDB and what gets
/// exported/imported as a shareable JSON file (same "everything is a
/// portable flat document" philosophy as SearchUrlCodec).
class PipelineGraph {
  final String id;
  final String name;
  final List<PipelineNode> nodes;
  final List<PipelineEdge> edges;
  final DateTime updatedAt;

  const PipelineGraph({
    required this.id,
    required this.name,
    this.nodes = const [],
    this.edges = const [],
    required this.updatedAt,
  });

  PipelineGraph copyWith({
    String? name,
    List<PipelineNode>? nodes,
    List<PipelineEdge>? edges,
    DateTime? updatedAt,
  }) {
    return PipelineGraph(
      id: id,
      name: name ?? this.name,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  PipelineNode? nodeById(String nodeId) {
    for (final n in nodes) {
      if (n.id == nodeId) return n;
    }
    return null;
  }

  List<PipelineEdge> incomingEdges(String nodeId) =>
      edges.where((e) => e.toNodeId == nodeId).toList();

  List<PipelineEdge> outgoingEdges(String nodeId) =>
      edges.where((e) => e.fromNodeId == nodeId).toList();

  /// Nodes in dependency order (every node appears after all of its
  /// upstream inputs) — what PipelineEngine walks to execute the graph.
  /// Throws [PipelineCycleError] if the graph isn't a DAG; the UI should
  /// catch this and surface it as a validation error rather than letting
  /// execution hang.
  List<PipelineNode> topologicalOrder() {
    final inDegree = <String, int>{for (final n in nodes) n.id: 0};
    for (final e in edges) {
      inDegree[e.toNodeId] = (inDegree[e.toNodeId] ?? 0) + 1;
    }

    final queue = [
      for (final n in nodes)
        if (inDegree[n.id] == 0) n
    ];
    final result = <PipelineNode>[];
    final remaining = Map<String, int>.from(inDegree);

    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      result.add(n);
      for (final e in outgoingEdges(n.id)) {
        remaining[e.toNodeId] = (remaining[e.toNodeId] ?? 0) - 1;
        if (remaining[e.toNodeId] == 0) {
          final next = nodeById(e.toNodeId);
          if (next != null) queue.add(next);
        }
      }
    }

    if (result.length != nodes.length) {
      throw PipelineCycleError(
          'Graph "$name" contains a cycle — ${nodes.length - result.length} node(s) unreachable.');
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static PipelineGraph fromJson(Map<String, dynamic> json) {
    final nodesRaw = json['nodes'];
    final edgesRaw = json['edges'];
    return PipelineGraph(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Pipeline',
      nodes: nodesRaw is List
          ? nodesRaw
              .whereType<Map>()
              .map((m) => PipelineNode.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      edges: edgesRaw is List
          ? edgesRaw
              .whereType<Map>()
              .map((m) => PipelineEdge.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
