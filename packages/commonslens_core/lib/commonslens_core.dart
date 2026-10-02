/// Pure Dart backend for CommonsLens.
///
/// This library intentionally exports no Flutter, browser, or platform UI
/// APIs. It can be embedded in Flutter, a command-line process, a server, or
/// tests running on the Dart VM.
library;

export 'src/commons_backend.dart';
export 'src/commons_engine.dart';
export 'src/pipeline_engine.dart';
export 'src/pipeline_models.dart';
export 'src/search_models.dart';
export 'src/search_query_compiler.dart';
export 'src/search_service.dart';
export 'src/search_url_codec.dart';
export 'src/wikimedia_download_client.dart';
export 'src/wikimedia_request_gate.dart';
export 'src/wikimedia_transport.dart';
export 'src/wikimedia_response_mapper.dart';
