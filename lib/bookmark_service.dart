// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_providers.dart';
import 'search_models.dart';

const _bookmarkStorageKey = 'commonslens.bookmarks.v2';
const _legacyBookmarkStorageKey = 'commonslens.bookmarks.v1';

class BookmarkFolder {
  final String id;
  final String name;
  final Set<String> urls;

  BookmarkFolder({
    required this.id,
    required this.name,
    Set<String>? urls,
  }) : urls = Set.unmodifiable(urls ?? <String>{});

  BookmarkFolder copyWith({String? name, Set<String>? urls}) => BookmarkFolder(
        id: id,
        name: name ?? this.name,
        urls: urls ?? this.urls,
      );
}

/// Keeps the user's bookmarks in this browser only.
///
/// Only the original media URL is persisted. The image and its metadata are
/// still loaded from Wikimedia when the app needs to display them, so this
/// store never becomes a second copy of the Commons catalogue.
class BookmarkStore extends ChangeNotifier {
  BookmarkStore() {
    _load();
  }

  final Set<String> _urls = <String>{};
  final List<BookmarkFolder> _folders = <BookmarkFolder>[];

  Set<String> get urls => Set.unmodifiable(_urls);

  List<BookmarkFolder> get folders => List.unmodifiable(_folders);

  bool isBookmarked(String url) => url.isNotEmpty && _urls.contains(url);

  bool isInFolder(String folderId, String url) {
    final folder = _folderById(folderId);
    return folder?.urls.contains(url) ?? false;
  }

  Set<String> urlsInFolder(String folderId) =>
      Set.unmodifiable(_folderById(folderId)?.urls ?? const <String>{});

  void toggle(String url) {
    if (url.isEmpty) return;

    if (!_urls.add(url)) {
      _urls.remove(url);
      for (var index = 0; index < _folders.length; index++) {
        final folder = _folders[index];
        if (folder.urls.contains(url)) {
          final updatedUrls = Set<String>.from(folder.urls)..remove(url);
          _folders[index] = folder.copyWith(urls: updatedUrls);
        }
      }
    }
    _persist();
    notifyListeners();
  }

  /// Creates a folder and returns its stable local id. Folder membership is
  /// deliberately separate from [_urls], so adding an item to a folder never
  /// removes it from All Bookmarked Media.
  String createFolder(String name) {
    final id =
        'folder-${DateTime.now().microsecondsSinceEpoch}-${_folders.length}';
    _folders.add(BookmarkFolder(id: id, name: name.trim(), urls: <String>{}));
    _persist();
    notifyListeners();
    return id;
  }

  void renameFolder(String folderId, String name) {
    final folderIndex = _folders.indexWhere((folder) => folder.id == folderId);
    if (folderIndex < 0 || name.trim().isEmpty) return;
    _folders[folderIndex] = _folders[folderIndex].copyWith(name: name.trim());
    _persist();
    notifyListeners();
  }

  void deleteFolder(String folderId) {
    final removed = _folders.any((folder) => folder.id == folderId);
    if (!removed) return;
    _folders.removeWhere((folder) => folder.id == folderId);
    _persist();
    notifyListeners();
  }

  void addToFolder(String folderId, String url) {
    addUrlsToFolder(folderId, [url]);
  }

  void addUrlsToFolder(String folderId, Iterable<String> urls) {
    addUrlsToFolders([folderId], urls);
  }

  void addUrlsToFolders(Iterable<String> folderIds, Iterable<String> urls) {
    final requestedUrls =
        urls.where((url) => url.isNotEmpty && _urls.contains(url)).toSet();
    if (requestedUrls.isEmpty) return;
    var changed = false;
    for (final folderId in folderIds.toSet()) {
      final folderIndex =
          _folders.indexWhere((folder) => folder.id == folderId);
      if (folderIndex < 0) continue;
      final updatedUrls = Set<String>.from(_folders[folderIndex].urls)
        ..addAll(requestedUrls);
      if (updatedUrls.length == _folders[folderIndex].urls.length) continue;
      _folders[folderIndex] = _folders[folderIndex].copyWith(urls: updatedUrls);
      changed = true;
    }
    if (!changed) return;
    _persist();
    notifyListeners();
  }

  void removeFromFolder(String folderId, String url) {
    final folderIndex = _folders.indexWhere((folder) => folder.id == folderId);
    if (folderIndex < 0 || !_folders[folderIndex].urls.contains(url)) return;
    final updatedUrls = Set<String>.from(_folders[folderIndex].urls)
      ..remove(url);
    _folders[folderIndex] = _folders[folderIndex].copyWith(urls: updatedUrls);
    _persist();
    notifyListeners();
  }

  BookmarkFolder? _folderById(String folderId) {
    for (final folder in _folders) {
      if (folder.id == folderId) return folder;
    }
    return null;
  }

  void _load() {
    try {
      final stored = html.window.localStorage[_bookmarkStorageKey] ??
          html.window.localStorage[_legacyBookmarkStorageKey];
      if (stored == null || stored.isEmpty) return;

      final decoded = jsonDecode(stored);
      if (decoded is List) {
        _urls
            .addAll(decoded.whereType<String>().where((url) => url.isNotEmpty));
      } else if (decoded is Map) {
        final storedUrls = decoded['urls'];
        if (storedUrls is List) {
          _urls.addAll(
              storedUrls.whereType<String>().where((url) => url.isNotEmpty));
        }
        final storedFolders = decoded['folders'];
        if (storedFolders is List) {
          for (final rawFolder in storedFolders) {
            if (rawFolder is! Map) continue;
            final id = rawFolder['id'];
            final name = rawFolder['name'];
            final rawUrls = rawFolder['urls'];
            if (id is! String || id.isEmpty || name is! String) continue;
            final folderUrls = rawUrls is List
                ? rawUrls.whereType<String>().where(_urls.contains).toSet()
                : <String>{};
            _folders.add(BookmarkFolder(
              id: id,
              name: name.trim().isEmpty ? 'Untitled folder' : name.trim(),
              urls: folderUrls,
            ));
          }
        }
      }
    } catch (_) {
      // A malformed value or a storage-restricted browser should not prevent
      // the rest of the app from working. The bookmarks can still live for
      // this session in memory.
    }
  }

  void _persist() {
    try {
      html.window.localStorage[_bookmarkStorageKey] = jsonEncode({
        'version': 2,
        'urls': _urls.toList(),
        'folders': _folders
            .map((folder) => {
                  'id': folder.id,
                  'name': folder.name,
                  'urls': folder.urls.toList(),
                })
            .toList(),
      });
    } catch (_) {
      // Private browsing and storage policies can deny writes. In that case
      // the current session remains usable without creating a sync fallback.
    }
  }
}

final bookmarkStoreProvider =
    ChangeNotifierProvider<BookmarkStore>((ref) => BookmarkStore());

class BookmarkItemsState {
  final List<SearchItem> items;
  final bool loading;
  final int failedCount;

  const BookmarkItemsState({
    this.items = const [],
    this.loading = false,
    this.failedCount = 0,
  });
}

/// Shared by the bookmarks grid and viewer so a filtered bookmark queue can
/// be reconstructed after navigating away from the page or reloading a URL.
final bookmarkItemsProvider =
    StateNotifierProvider<BookmarkItemsController, BookmarkItemsState>((ref) {
  final controller = BookmarkItemsController(ref);
  ref.listen<Set<String>>(
    bookmarkStoreProvider.select((store) => store.urls),
    (_, urls) => controller.load(urls),
  );
  controller.load(ref.read(bookmarkStoreProvider).urls);
  return controller;
});

class BookmarkItemsController extends StateNotifier<BookmarkItemsState> {
  BookmarkItemsController(this.ref) : super(const BookmarkItemsState());

  final Ref ref;
  int _generation = 0;

  Future<void> reload() => load(ref.read(bookmarkStoreProvider).urls);

  Future<void> load(Set<String> urls) async {
    final generation = ++_generation;
    if (urls.isEmpty) {
      state = const BookmarkItemsState();
      return;
    }
    state = BookmarkItemsState(items: state.items, loading: true);
    final loaded = await Future.wait(urls.map((url) async {
      try {
        return await ref.read(commonsBackendProvider).fetchItem(
              fileTitleFromBookmarkUrl(url),
            );
      } catch (_) {
        return null;
      }
    }));
    if (!mounted || generation != _generation) return;
    if (!setEquals(ref.read(bookmarkStoreProvider).urls, urls)) return;
    state = BookmarkItemsState(
      items: loaded.whereType<SearchItem>().toList(growable: false),
      failedCount: loaded.where((item) => item == null).length,
    );
  }
}

String fileTitleFromBookmarkUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.pathSegments.isNotEmpty) {
      final filename = Uri.decodeComponent(uri.pathSegments.last);
      if (filename.isNotEmpty) {
        return filename.startsWith('File:') ? filename : 'File:$filename';
      }
    }
  } catch (_) {
    // The backend will report a missing file for an invalid bookmark.
  }
  return url.startsWith('File:') ? url : 'File:$url';
}

bool bookmarkMatchesSearch(SearchItem item, String query) {
  if (query.isEmpty) return true;
  final haystack = [
    item.title,
    item.url,
    item.snippet,
    item.objectName,
    item.uploader,
    item.categories,
  ].join(' ').toLowerCase();
  return haystack.contains(query.trim().toLowerCase());
}
