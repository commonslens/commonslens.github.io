import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commonslens_core/commonslens_core.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln('''
CommonsLens headless backend

Pass one JSON request on stdin. Supported operations:
  search, authorUploads, fetchItem, geosearch, pipeline

Example:
  echo '{"operation":"search","filters":{"queryText":"Eiffel Tower"}}' |
    dart run bin/commonslens.dart
'''
        .trim());
    return;
  }

  try {
    final raw = await stdin.transform(utf8.decoder).join();
    if (raw.trim().isEmpty) {
      throw const FormatException('Expected a JSON request on stdin.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The request must be a JSON object.');
    }

    final request = Map<String, dynamic>.from(decoded);
    final response = await runZoned(
      () => _dispatch(request),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => stderr.writeln(line),
      ),
    );
    stdout.writeln(jsonEncode(response));
  } catch (error) {
    stderr.writeln('commonslens_core: $error');
    exitCode = 1;
  }
}

Future<Object?> _dispatch(Map<String, dynamic> request) async {
  final backend = CommonsBackend();
  switch (request['operation'] as String? ?? 'search') {
    case 'search':
      final filters = _map(request['filters'], field: 'filters');
      final cursor = _optionalMap(request['continueToken']);
      return (await backend.search(
        SearchState.fromJson(filters),
        continueToken: cursor,
      ))
          .toJson();
    case 'authorUploads':
      final username = request['username'] as String? ?? '';
      return (await backend.authorUploads(
        username,
        continueToken: _optionalMap(request['continueToken']),
      ))
          .toJson();
    case 'fetchItem':
      final title = request['title'] as String? ?? '';
      return (await backend.fetchItem(title))?.toJson();
    case 'geosearch':
      final box = request['boundingBox'];
      return (await backend.geosearch(
        lat: (request['lat'] as num?)?.toDouble(),
        lng: (request['lng'] as num?)?.toDouble(),
        radiusMeters: (request['radiusMeters'] as num?)?.toDouble() ?? 1000,
        boundingBox: box is List
            ? box.whereType<num>().map((value) => value.toDouble()).toList()
            : null,
        limit: (request['limit'] as num?)?.toInt() ?? 500,
        continueToken: _optionalMap(request['continueToken']),
      ))
          .toJson();
    case 'pipeline':
      final graph = PipelineGraph.fromJson(
        _map(request['graph'], field: 'graph'),
      );
      final result = await PipelineEngine().run(
        graph,
        PipelineExecutionContext(
          backend: backend,
          preview: request['preview'] as bool? ?? false,
          maxItemsPerSource:
              (request['maxItemsPerSource'] as num?)?.toInt() ?? 1000,
          previewCap: (request['previewCap'] as num?)?.toInt() ?? 20,
        ),
      );
      return {
        'outputs': result.outputsByNodeId.map(
          (id, output) => MapEntry(id, _nodeOutputJson(output)),
        ),
        'sinks': result.sinkOutputsByNodeId.keys.toList(),
      };
    default:
      throw FormatException(
        'Unsupported operation: ${request['operation']}',
      );
  }
}

Map<String, dynamic> _map(Object? value, {required String field}) {
  if (value is! Map) throw FormatException('$field must be a JSON object.');
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic>? _optionalMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

Map<String, dynamic> _nodeOutputJson(NodeOutput output) => {
      'pendingState': output.pendingState?.toJson(),
      'items': output.items?.map((item) => item.toJson()).toList(),
      'records': output.records,
      'error': output.error,
      'warning': output.warning,
      'totalHits': output.totalHits,
    };
