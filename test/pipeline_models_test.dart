import 'package:commonslens/pipeline_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('topologicalOrder places every dependency before its consumer', () {
    final graph = PipelineGraph(
      id: 'graph',
      name: 'Ordered graph',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(id: 'sink', type: PipelineNodeType.sinkPreview),
        PipelineNode(id: 'filter', type: PipelineNodeType.filterLicense),
        PipelineNode(id: 'source', type: PipelineNodeType.sourceTextQuery),
      ],
      edges: const [
        PipelineEdge(
          id: 'source-filter',
          fromNodeId: 'source',
          fromPortId: 'out',
          toNodeId: 'filter',
          toPortId: 'in',
        ),
        PipelineEdge(
          id: 'filter-sink',
          fromNodeId: 'filter',
          fromPortId: 'out',
          toNodeId: 'sink',
          toPortId: 'in',
        ),
      ],
    );

    expect(graph.topologicalOrder().map((node) => node.id), [
      'source',
      'filter',
      'sink',
    ]);
  });

  test('topologicalOrder reports a cycle instead of hanging', () {
    final graph = PipelineGraph(
      id: 'cycle',
      name: 'Cyclic graph',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(id: 'a', type: PipelineNodeType.transformDedupe),
        PipelineNode(id: 'b', type: PipelineNodeType.transformDedupe),
      ],
      edges: const [
        PipelineEdge(
          id: 'a-b',
          fromNodeId: 'a',
          fromPortId: 'out',
          toNodeId: 'b',
          toPortId: 'in',
        ),
        PipelineEdge(
          id: 'b-a',
          fromNodeId: 'b',
          fromPortId: 'out',
          toNodeId: 'a',
          toPortId: 'in',
        ),
      ],
    );

    expect(graph.topologicalOrder, throwsA(isA<PipelineCycleError>()));
  });

  test('graph JSON round-trip preserves node config, positions, and ports', () {
    final original = PipelineGraph(
      id: 'graph',
      name: 'Serializable graph',
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5),
      nodes: [
        PipelineNode(
          id: 'source',
          type: PipelineNodeType.sourceCategory,
          title: 'Historic categories',
          x: 12.5,
          y: 45.5,
          config: const {
            'categories': ['Architecture', 'Paris'],
            'union': true,
            'deep': false,
          },
        ),
      ],
    );

    final restored = PipelineGraph.fromJson(original.toJson());

    expect(restored.toJson(), original.toJson());
    expect(restored.nodes.single.ports.map((port) => port.id), ['out']);
  });

  test('set operations receive two inputs and one output', () {
    final ports = defaultPortsFor(PipelineNodeType.setUnion);

    expect(ports.map((port) => port.id), ['a', 'b', 'out']);
    expect(
      ports.map((port) => port.direction),
      [
        PipelinePortDirection.input,
        PipelinePortDirection.input,
        PipelinePortDirection.output,
      ],
    );
  });
}
