// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
