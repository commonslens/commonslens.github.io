import 'package:commonslens_core/commonslens_core.dart';
import 'package:test/test.dart';

void main() {
  test('core entrypoint exposes search compilation without Flutter', () {
    final backend = CommonsBackend();
    final built = backend.buildQuery(const SearchState(
      queryText: 'Eiffel Tower',
      categories: {'Architecture'},
      licensePresets: {LicensePreset.cc0},
    ));

    expect(built.srsearch, contains('Eiffel Tower'));
    expect(built.srsearch, contains('incategory:"Architecture"'));
    expect(built.srsearch, contains('haswbstatement:P275=Q6938433'));
  });

  test('query compiler is pure, deterministic, and injectable', () {
    const compiler = SearchQueryCompiler();
    const first = SearchState(
      queryText: 'cat + dog',
      categories: {'Zulu', 'Alpha'},
      templates: {'Two', 'One'},
    );
    const reordered = SearchState(
      queryText: 'cat + dog',
      categories: {'Alpha', 'Zulu'},
      templates: {'One', 'Two'},
    );

    expect(compiler.buildQuery(first).toJson(),
        compiler.buildQuery(reordered).toJson());
    expect(compiler.buildSignature(first), compiler.buildSignature(reordered));
    expect(
      'cat + dog'.split(SearchQueryCompiler.multiQuerySeparator),
      ['cat', 'dog'],
    );

    final service = SearchService(queryCompiler: compiler);
    expect(
      service.buildQuery(first).toJson(),
      compiler.buildQuery(first).toJson(),
    );
    expect(
      service.buildQuerySignature(first),
      compiler.buildSignature(first),
    );
  });

  test('pipeline models and engine are available from the same entrypoint', () {
    final graph = PipelineGraph(
      id: 'headless',
      name: 'Headless graph',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(id: 'source', type: PipelineNodeType.sourceTextQuery),
        PipelineNode(id: 'sink', type: PipelineNodeType.sinkPreview),
      ],
      edges: const [
        PipelineEdge(
          id: 'edge',
          fromNodeId: 'source',
          fromPortId: 'out',
          toNodeId: 'sink',
          toPortId: 'in',
        ),
      ],
    );

    expect(graph.topologicalOrder().map((node) => node.id), ['source', 'sink']);
  });
}
