import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/pipeline_engine.dart';
import 'package:commonslens/pipeline_models.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingBackend extends CommonsBackend {
  final List<SearchState> searches = [];

  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) async {
    searches.add(filters);
    return const MediaSearchResult(
      items: [],
      hasMore: false,
      continueToken: null,
      queryUsed: '',
      totalHits: 0,
    );
  }
}

void main() {
  test('Combine Constraints sends text and depicts as one backend query',
      () async {
    final backend = _RecordingBackend();
    final graph = PipelineGraph(
      id: 'graph',
      name: 'Canary Wharf skyscrapers',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(
          id: 'text',
          type: PipelineNodeType.sourceTextQuery,
          config: const {'query': 'Canary Wharf'},
        ),
        PipelineNode(
          id: 'depicts',
          type: PipelineNodeType.sourceDepicts,
          config: const {
            'entries': [
              {'qid': 'Q11303', 'label': 'skyscraper'},
            ],
          },
        ),
        PipelineNode(id: 'and', type: PipelineNodeType.setCombineAnd),
        PipelineNode(id: 'preview', type: PipelineNodeType.sinkPreview),
      ],
      edges: const [
        PipelineEdge(
          id: 'text-and',
          fromNodeId: 'text',
          fromPortId: 'out',
          toNodeId: 'and',
          toPortId: 'a',
        ),
        PipelineEdge(
          id: 'depicts-and',
          fromNodeId: 'depicts',
          fromPortId: 'out',
          toNodeId: 'and',
          toPortId: 'b',
        ),
        PipelineEdge(
          id: 'and-preview',
          fromNodeId: 'and',
          fromPortId: 'out',
          toNodeId: 'preview',
          toPortId: 'in',
        ),
      ],
    );

    final result = await PipelineEngine().run(
      graph,
      PipelineExecutionContext(backend: backend),
    );

    expect(backend.searches, hasLength(1));
    expect(backend.searches.single.queryText, 'Canary Wharf');
    expect(
      backend.searches.single.depictsInclude,
      contains(const DepictsEntity(qid: 'Q11303', label: 'skyscraper')),
    );
    expect(result.outputsByNodeId['and']?.isPending, isTrue);
    expect(result.sinkOutputsByNodeId['preview']?.hasError, isFalse);
  });

  test('Combine Constraints survives graph JSON round-trip', () {
    final node = PipelineNode(id: 'and', type: PipelineNodeType.setCombineAnd);
    final restored = PipelineNode.fromJson(node.toJson());

    expect(restored.type, PipelineNodeType.setCombineAnd);
    expect(restored.ports.map((port) => port.id), ['a', 'b', 'out']);
  });

  test('Enrich adds bounded SDC and usage records without replacing items',
      () async {
    final item = SearchItem(
      title: 'File:Example.jpg',
      url: 'https://upload.wikimedia.org/example.jpg',
      thumb: 'https://upload.wikimedia.org/example-thumb.jpg',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:Example.jpg',
      snippet: 'Example',
      mime: 'image/jpeg',
      isSvg: false,
    );
    final backend = _EnrichmentBackend(item);
    final graph = PipelineGraph(
      id: 'enrich-graph',
      name: 'Enrichment',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(
          id: 'source',
          type: PipelineNodeType.sourceTextQuery,
          config: const {'query': 'example'},
        ),
        PipelineNode(
          id: 'enrich',
          type: PipelineNodeType.transformEnrich,
          config: const {
            'structuredData': true,
            'globalUsage': true,
            'maxEnrich': 1,
            'usageLimit': 10,
          },
        ),
        PipelineNode(id: 'sink', type: PipelineNodeType.sinkJsonExport),
      ],
      edges: const [
        PipelineEdge(
          id: 'source-enrich',
          fromNodeId: 'source',
          fromPortId: 'out',
          toNodeId: 'enrich',
          toPortId: 'in',
        ),
        PipelineEdge(
          id: 'enrich-sink',
          fromNodeId: 'enrich',
          fromPortId: 'out',
          toNodeId: 'sink',
          toPortId: 'in',
        ),
      ],
    );

    final result = await PipelineEngine().run(
      graph,
      PipelineExecutionContext(backend: backend),
    );
    final output = result.sinkOutputsByNodeId['sink']!;

    expect(output.items, [same(item)]);
    expect(output.records!.single['structuredData'], isA<Map>());
    expect(output.records!.single['globalUsageCount'], 1);
    expect(
        backend.calls, ['sdc:File:Example.jpg', 'usage:File:Example.jpg:10']);
  });

  test('Field Select projects export records and retains typed media',
      () async {
    final item = SearchItem(
      title: 'File:Projected.jpg',
      url: 'https://upload.wikimedia.org/projected.jpg',
      thumb: 'https://upload.wikimedia.org/projected-thumb.jpg',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:Projected.jpg',
      snippet: 'Projected',
      mime: 'image/jpeg',
      isSvg: false,
      width: 1600,
      height: 900,
    );
    final graph = PipelineGraph(
      id: 'fields-graph',
      name: 'Field projection',
      updatedAt: DateTime.utc(2026),
      nodes: [
        PipelineNode(
          id: 'source',
          type: PipelineNodeType.sourceTextQuery,
          config: const {'query': 'projected'},
        ),
        PipelineNode(
          id: 'fields',
          type: PipelineNodeType.transformFieldSelect,
          config: const {
            'fields': ['title', 'width'],
          },
        ),
        PipelineNode(id: 'sink', type: PipelineNodeType.sinkCsvExport),
      ],
      edges: const [
        PipelineEdge(
          id: 'source-fields',
          fromNodeId: 'source',
          fromPortId: 'out',
          toNodeId: 'fields',
          toPortId: 'in',
        ),
        PipelineEdge(
          id: 'fields-sink',
          fromNodeId: 'fields',
          fromPortId: 'out',
          toNodeId: 'sink',
          toPortId: 'in',
        ),
      ],
    );

    final result = await PipelineEngine().run(
      graph,
      PipelineExecutionContext(backend: _StaticBackend(item)),
    );
    final output = result.sinkOutputsByNodeId['sink']!;

    expect(output.items, [same(item)]);
    expect(output.records, [
      {'title': 'File:Projected.jpg', 'width': 1600},
    ]);
  });
}

class _StaticBackend extends CommonsBackend {
  final SearchItem item;
  _StaticBackend(this.item);

  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) async =>
      MediaSearchResult(
        items: [item],
        hasMore: false,
        continueToken: null,
        queryUsed: filters.queryText,
      );
}

class _EnrichmentBackend extends _StaticBackend {
  final List<String> calls = [];
  _EnrichmentBackend(super.item);

  @override
  Future<StructuredDataResult?> structuredData(String fileIdOrTitle) async {
    calls.add('sdc:$fileIdOrTitle');
    return const StructuredDataResult(
      mid: 'M1',
      captions: {'en': 'Example'},
      statements: [],
    );
  }

  @override
  Future<List<GlobalUsageEntry>> globalUsage(
    String fileIdOrTitle, {
    int limit = 500,
  }) async {
    calls.add('usage:$fileIdOrTitle:$limit');
    return const [
      GlobalUsageEntry(
        wiki: 'en.wikipedia.org',
        title: 'Example',
        url: 'https://en.wikipedia.org/wiki/Example',
      ),
    ];
  }
}
