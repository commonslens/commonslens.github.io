// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_providers.dart';
import 'search_models.dart';

const _bookmarkStorageKey = 'commonslens.bookmarks.v1';

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

  Set<String> get urls => Set.unmodifiable(_urls);

  bool isBookmarked(String url) => url.isNotEmpty && _urls.contains(url);

  void toggle(String url) {
    if (url.isEmpty) return;

    if (!_urls.add(url)) {
      _urls.remove(url);
    }
    _persist();
    notifyListeners();
  }

  void _load() {
    try {
      final stored = html.window.localStorage[_bookmarkStorageKey];
      if (stored == null || stored.isEmpty) return;

      final decoded = jsonDecode(stored);
      if (decoded is List) {
        _urls
            .addAll(decoded.whereType<String>().where((url) => url.isNotEmpty));
      }
    } catch (_) {
      // A malformed value or a storage-restricted browser should not prevent
      // the rest of the app from working. The bookmarks can still live for
      // this session in memory.
    }
  }

  void _persist() {
    try {
      html.window.localStorage[_bookmarkStorageKey] =
          jsonEncode(_urls.toList());
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
