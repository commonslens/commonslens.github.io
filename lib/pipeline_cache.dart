// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'search_models.dart';
import 'pipeline_engine.dart';
import 'pipeline_models.dart';

/// IndexedDB-backed [PipelineCache] plus graph persistence, all in one
/// database (`commonslens_pipeline`, 3 object stores). Values are stored
/// as JSON strings via dart:convert rather than raw nested Maps — sidesteps
/// any ambiguity in dart:html's Dart-to-JS structured-clone conversion for
/// IndexedDB.put, and matches this codebase's existing convention of
/// explicit jsonEncode/jsonDecode everywhere else (search_service.dart,
/// download_service.dart) rather than relying on implicit interop.
///
/// Every public method is best-effort: any failure (unsupported browser,
/// private-mode storage restrictions, quota, a corrupted entry) degrades
/// silently to "not cached" / "not saved" rather than throwing into the
/// pipeline run. Caching must never be why a pipeline fails.
class PipelineIndexedDbCache implements PipelineCache {
  static const _dbName = 'commonslens_pipeline';
  static const _dbVersion = 1;
  static const _queryStoreName = 'query_cache';
  static const _nodeStoreName = 'node_cache';
  static const _graphStoreName = 'graphs';

  final Duration queryTtl;
  final Duration nodeTtl;

  dynamic _db;
  Future<dynamic>? _opening;

  PipelineIndexedDbCache({
    this.queryTtl = const Duration(hours: 1),
    this.nodeTtl = const Duration(hours: 1),
  });

  /// Opens (or returns the already-open) database, creating all three
  /// object stores on first run. Guarded by [_opening] so concurrent
  /// callers during app startup share one open() call instead of racing
  /// separate upgrade transactions.
  Future<dynamic> _open() {
    final existing = _db;
    if (existing != null) return Future.value(existing);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;

    final future = () async {
      final factory = html.window.indexedDB;
      if (factory == null) {
        throw StateError('IndexedDB is not available in this browser.');
      }
      final db = await factory.open(
        _dbName,
        version: _dbVersion,
        onUpgradeNeeded: (event) {
          final upgradeDb = (event.target as dynamic).result;
          for (final store in [
            _queryStoreName,
            _nodeStoreName,
            _graphStoreName
          ]) {
            if (!(upgradeDb.objectStoreNames?.contains(store) ?? false)) {
              upgradeDb.createObjectStore(store);
            }
          }
        },
      );
      _db = db;
      return db;
    }();

    _opening = future;
    return future;
  }

  Future<T?> _get<T>(
    String storeName,
    String key,
    T? Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, 'readonly');
      final store = txn.objectStore(storeName);
      final raw = await store.getObject(key);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decode(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _put(
      String storeName, String key, Map<String, dynamic> value) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, 'readwrite');
      final store = txn.objectStore(storeName);
      await store.put(jsonEncode(value), key);
    } catch (_) {
      // Best-effort — see class doc.
    }
  }

  Future<void> _delete(String storeName, String key) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, 'readwrite');
      await txn.objectStore(storeName).delete(key);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _listAll(String storeName) async {
    try {
      final db = await _open();
      final txn = db.transaction(storeName, 'readonly');
      final store = txn.objectStore(storeName);
      final entries = <Map<String, dynamic>>[];
      // autoAdvance:true means the stream itself walks every entry — do
      // not call cursor.next() manually here, that double-advances.
      await for (final cursor in store.openCursor(autoAdvance: true)) {
        final raw = cursor.value;
        if (raw is String) {
          try {
            entries.add(jsonDecode(raw) as Map<String, dynamic>);
          } catch (_) {
            // One corrupted entry shouldn't take down the whole listing.
          }
        }
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  bool _isFresh(String? cachedAtIso, Duration ttl) {
    if (cachedAtIso == null) return false;
    final cachedAt = DateTime.tryParse(cachedAtIso);
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) < ttl;
  }

  List<SearchItem>? _decodeItems(Map<String, dynamic> map, Duration ttl) {
    if (!_isFresh(map['cachedAt'] as String?, ttl)) return null;
    final itemsRaw = map['items'];
    if (itemsRaw is! List) return null;
    return itemsRaw
        .whereType<Map>()
        .map((m) => SearchItem.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // PipelineCache — query-result cache. Also what the engine's Author and
  // geosearch-browse source paths reuse via a synthetic signature (see
  // their doc comments in pipeline_engine.dart), since neither goes
  // through buildQuerySignature.
  // ---------------------------------------------------------------------

  @override
  Future<List<SearchItem>?> getQueryResult(String signature) =>
      _get(_queryStoreName, signature, (map) => _decodeItems(map, queryTtl));

  @override
  Future<void> putQueryResult(String signature, List<SearchItem> items) => _put(
        _queryStoreName,
        signature,
        {
          'cachedAt': DateTime.now().toIso8601String(),
          'items': items.map((i) => i.toJson()).toList(),
        },
      );

  // ---------------------------------------------------------------------
  // Node-output cache — for memoizing a whole node's result (a Set-op or
  // Transform's output) keyed by the caller's own cache key, e.g.
  // hash(node type + config + upstream keys). Not wired into
  // PipelineEngine yet — set-op/transform work is cheap in-memory list
  // manipulation over already-fetched items, not a network call, so it's
  // lower priority than the query-result cache above. Kept here as
  // ready-to-use infrastructure for when a future graph run gets large
  // enough (thousands of items through several Union/Sort stages) that
  // re-running them on every edit is worth skipping.
  // ---------------------------------------------------------------------

  Future<List<SearchItem>?> getNodeOutput(String nodeCacheKey) =>
      _get(_nodeStoreName, nodeCacheKey, (map) => _decodeItems(map, nodeTtl));

  Future<void> putNodeOutput(String nodeCacheKey, List<SearchItem> items) =>
      _put(
        _nodeStoreName,
        nodeCacheKey,
        {
          'cachedAt': DateTime.now().toIso8601String(),
          'items': items.map((i) => i.toJson()).toList(),
        },
      );

  /// Clears both cache stores — leaves saved graphs untouched. Surfaced in
  /// the UI as a "Force Refresh" / "Clear Cache" action distinct from
  /// deleting a pipeline.
  Future<void> clearCache() async {
    try {
      final db = await _open();
      for (final store in [_queryStoreName, _nodeStoreName]) {
        final txn = db.transaction(store, 'readwrite');
        await txn.objectStore(store).clear();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------
  // Graph persistence
  // ---------------------------------------------------------------------

  Future<void> saveGraph(PipelineGraph graph) =>
      _put(_graphStoreName, graph.id, graph.toJson());

  Future<PipelineGraph?> loadGraph(String id) =>
      _get(_graphStoreName, id, (map) => PipelineGraph.fromJson(map));

  Future<void> deleteGraph(String id) => _delete(_graphStoreName, id);

  Future<List<PipelineGraph>> listGraphs() async {
    final raw = await _listAll(_graphStoreName);
    final graphs = raw.map(PipelineGraph.fromJson).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return graphs;
  }

  /// Whole-store export for a "download all my pipelines as JSON" action —
  /// distinct from exporting a single [PipelineGraph] (that's just
  /// `graph.toJson()`, already handled at the call site with no need for
  /// this class).
  Future<Map<String, dynamic>> exportAllGraphs() async {
    final graphs = await listGraphs();
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'graphs': graphs.map((g) => g.toJson()).toList(),
    };
  }

  /// Inverse of [exportAllGraphs] — imports every graph in the bundle,
  /// overwriting any existing graph with the same id.
  Future<void> importGraphs(Map<String, dynamic> bundle) async {
    final graphsRaw = bundle['graphs'];
    if (graphsRaw is! List) return;
    for (final raw in graphsRaw) {
      if (raw is! Map) continue;
      final graph = PipelineGraph.fromJson(Map<String, dynamic>.from(raw));
      if (graph.id.isEmpty) continue;
      await saveGraph(graph);
    }
  }
}
