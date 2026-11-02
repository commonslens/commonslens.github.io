// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'wikimedia_download_client.dart';

const _downloadQueueStorageKey = 'commonslens.downloadQueue.v1';
const _downloadQueueVersion = 1;
const _maxQueueEntries = 500;
const _maxSourceLabels = 12;

enum DownloadQueueItemStatus { queued, downloading, completed, failed }

/// A persistent pointer to a public Wikimedia file. It intentionally contains
/// metadata only; media bytes are fetched afresh after the user presses an
/// export button and are never written to browser storage.
class DownloadQueueItem {
  final String id;
  final SearchItem item;
  final Set<String> sources;
  final DateTime addedAt;
  final DownloadQueueItemStatus status;
  final String? lastError;

  const DownloadQueueItem({
    required this.id,
    required this.item,
    required this.sources,
    required this.addedAt,
    this.status = DownloadQueueItemStatus.queued,
    this.lastError,
  });

  DownloadQueueItem copyWith({
    SearchItem? item,
    Set<String>? sources,
    DownloadQueueItemStatus? status,
    String? lastError,
    bool clearError = false,
  }) {
    return DownloadQueueItem(
      id: id,
      item: item ?? this.item,
      sources: Set.unmodifiable(sources ?? this.sources),
      addedAt: addedAt,
      status: status ?? this.status,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'item': item.toJson(),
        'sources': sources.toList(),
        'addedAt': addedAt.toIso8601String(),
        'status': status.name,
        if (lastError != null) 'lastError': lastError,
      };

  static DownloadQueueItem? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final rawItem = raw['item'];
    if (rawItem is! Map) return null;
    final item = SearchItem.fromJson(Map<String, dynamic>.from(rawItem));
    final id = raw['id'] is String ? raw['id'] as String : '';
    final canonical = _canonicalMediaId(item.url);
    if (id.isEmpty || canonical == null || id != canonical) return null;

    final rawDate = raw['addedAt'];
    final addedAt = rawDate is String
        ? DateTime.tryParse(rawDate) ?? DateTime.now()
        : DateTime.now();
    final rawSources = raw['sources'];
    final sources = rawSources is List
        ? rawSources
            .whereType<String>()
            .map(_cleanSource)
            .where((source) => source.isNotEmpty)
            .take(_maxSourceLabels)
            .toSet()
        : <String>{};

    // A page reload cannot safely resume a byte transfer. Reset transient
    // states to queued so no automatic work is performed on restoration.
    final rawStatus = raw['status'];
    final status = rawStatus == DownloadQueueItemStatus.completed.name
        ? DownloadQueueItemStatus.completed
        : rawStatus == DownloadQueueItemStatus.failed.name
            ? DownloadQueueItemStatus.failed
            : DownloadQueueItemStatus.queued;
    return DownloadQueueItem(
      id: canonical,
      item: item,
      sources: Set.unmodifiable(sources),
      addedAt: addedAt,
      status: status,
      lastError: raw['lastError'] is String
          ? (raw['lastError'] as String).substring(
              0,
              (raw['lastError'] as String).length > 400
                  ? 400
                  : (raw['lastError'] as String).length,
            )
          : null,
    );
  }
}

/// Cross-route download selection and persistence boundary.
///
/// The queue is deliberately metadata-only. The archive service must take a
/// snapshot from this store and independently revalidate every URL and byte
/// stream before adding anything to a ZIP.
class DownloadQueueStore extends ChangeNotifier {
  DownloadQueueStore() {
    _load();
  }

  final Map<String, DownloadQueueItem> _items = <String, DownloadQueueItem>{};
  Timer? _persistTimer;

  List<DownloadQueueItem> get items =>
      List.unmodifiable(_items.values.toList(growable: false));

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  bool contains(String url) {
    final id = _canonicalMediaId(url);
    return id != null && _items.containsKey(id);
  }

  DownloadQueueItem? itemFor(String url) {
    final id = _canonicalMediaId(url);
    return id == null ? null : _items[id];
  }

  bool toggle(SearchItem item, {String source = 'unknown'}) {
    final id = _canonicalMediaId(item.url);
    if (id == null) return false;
    if (_items.containsKey(id)) {
      remove(id);
      return false;
    }
    add(item, source: source);
    return true;
  }

  bool add(SearchItem item, {String source = 'unknown'}) {
    final id = _canonicalMediaId(item.url);
    if (id == null || item.url.trim().isEmpty) return false;
    if (!_items.containsKey(id) && _items.length >= _maxQueueEntries) {
      return false;
    }

    final existing = _items[id];
    final sources = <String>{
      ...?existing?.sources,
      if (_cleanSource(source).isNotEmpty) _cleanSource(source),
    };
    _items[id] = DownloadQueueItem(
      id: id,
      item: item,
      sources: Set.unmodifiable(sources.take(_maxSourceLabels).toSet()),
      addedAt: existing?.addedAt ?? DateTime.now(),
      status: DownloadQueueItemStatus.queued,
      lastError: existing?.lastError,
    );
    _schedulePersist();
    notifyListeners();
    return true;
  }

  void addAll(Iterable<SearchItem> items, {String source = 'unknown'}) {
    var changed = false;
    for (final item in items) {
      final id = _canonicalMediaId(item.url);
      if (id == null ||
          (_items.length >= _maxQueueEntries && !_items.containsKey(id))) {
        continue;
      }
      final existing = _items[id];
      final sources = <String>{
        ...?existing?.sources,
        if (_cleanSource(source).isNotEmpty) _cleanSource(source),
      };
      _items[id] = DownloadQueueItem(
        id: id,
        item: item,
        sources: Set.unmodifiable(sources.take(_maxSourceLabels).toSet()),
        addedAt: existing?.addedAt ?? DateTime.now(),
        status: DownloadQueueItemStatus.queued,
        lastError: existing?.lastError,
      );
      changed = true;
    }
    if (!changed) return;
    _schedulePersist();
    notifyListeners();
  }

  void remove(String idOrUrl) {
    final id = _canonicalMediaId(idOrUrl) ?? idOrUrl;
    if (_items.remove(id) == null) return;
    _schedulePersist();
    notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    _schedulePersist();
    notifyListeners();
  }

  void mark(String id, DownloadQueueItemStatus status, {String? error}) {
    final current = _items[id];
    if (current == null) return;
    _items[id] = current.copyWith(
      status: status,
      lastError: error,
      clearError: error == null && status != DownloadQueueItemStatus.failed,
    );
    _schedulePersist();
    notifyListeners();
  }

  void _load() {
    try {
      final raw = html.window.localStorage[_downloadQueueStorageKey];
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _downloadQueueVersion) {
        return;
      }
      final entries = decoded['entries'];
      if (entries is! List) return;
      for (final rawEntry in entries.take(_maxQueueEntries)) {
        final entry = DownloadQueueItem.fromJson(rawEntry);
        if (entry != null) _items[entry.id] = entry;
      }
    } catch (_) {
      // Storage is optional. A restricted or malformed store must not break
      // the current session.
    }
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 200), _persist);
  }

  void _persist() {
    try {
      html.window.localStorage[_downloadQueueStorageKey] = jsonEncode({
        'version': _downloadQueueVersion,
        'entries': _items.values.map((entry) => entry.toJson()).toList(),
      });
    } catch (_) {
      // Private browsing, quota, and storage policy failures degrade to the
      // in-memory queue without persisting media bytes or secrets.
    }
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}

final downloadQueueProvider =
    ChangeNotifierProvider<DownloadQueueStore>((ref) => DownloadQueueStore());

final selectionModeProvider = StateProvider<bool>((ref) => false);

String? _canonicalMediaId(String rawUrl) {
  try {
    return DownloadSecurityPolicy.requireTrustedMediaUri(rawUrl).toString();
  } on DownloadSecurityException {
    return null;
  }
}

String _cleanSource(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return '';
  return value.length > 40 ? value.substring(0, 40) : value;
}
