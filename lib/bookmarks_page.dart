import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bookmark_service.dart';
import 'bulk_download_tray.dart';
import 'media_queue.dart';
import 'search_components.dart';
import 'search_models.dart';

class BookmarksPage extends ConsumerStatefulWidget {
  final String initialQuery;

  const BookmarksPage({super.key, this.initialQuery = ''});

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  late final _searchController =
      TextEditingController(text: widget.initialQuery);
  final _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant BookmarksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _searchController.text = widget.initialQuery;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _searchController,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search your bookmarks…',
            hintStyle: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF181818),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3D7EFF), width: 1),
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 18,
              color: Color(0xFF5A5A5A),
            ),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear bookmark search',
                    icon: const Icon(Icons.close, size: 17),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
    );
  }

  Widget _buildBody(List<SearchItem> visibleItems, Set<String> bookmarkUrls,
      BookmarkItemsState bookmarkState, String query) {
    if (bookmarkUrls.isEmpty) {
      return const _BookmarksEmptyState(
        icon: Icons.bookmark_border,
        title: 'No bookmarks yet',
        message:
            'Bookmark an image from the search grid or asset viewer and it will appear here.',
      );
    }

    if (bookmarkState.loading && bookmarkState.items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Color(0xFF3D7EFF),
          ),
        ),
      );
    }

    if (!bookmarkState.loading && bookmarkState.items.isEmpty) {
      return _BookmarksEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Bookmarks unavailable',
        message: 'The saved links could not be loaded right now.',
        action: TextButton.icon(
          onPressed: () => ref.read(bookmarkItemsProvider.notifier).reload(),
          icon: const Icon(Icons.refresh, size: 17),
          label: const Text('Retry'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Text(
            '${visibleItems.length} OF ${bookmarkState.items.length} BOOKMARK${bookmarkState.items.length == 1 ? '' : 'S'}'
            '${bookmarkState.failedCount == 0 ? '' : '  •  ${bookmarkState.failedCount} UNAVAILABLE'}',
            style: const TextStyle(
              color: Color(0xFF5A5A5A),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (visibleItems.isEmpty)
          const Expanded(
            child: _BookmarksEmptyState(
              icon: Icons.search_off,
              title: 'No matching bookmarks',
              message: 'Try a different title, category, uploader, or URL.',
            ),
          )
        else
          Expanded(
            child: MediaResultsGrid(
              controller: _scrollController,
              items: visibleItems,
              queueSource: MediaQueueSource.bookmarks(query),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookmarkUrls = ref.watch(bookmarkStoreProvider).urls;
    final bookmarkState = ref.watch(bookmarkItemsProvider);

    final query = _searchController.text.trim().toLowerCase();
    final visibleItems = bookmarkState.items
        .where((item) => bookmarkMatchesSearch(item, query))
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          tooltip: 'Back to search',
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'BOOKMARKS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
              child:
                  _buildBody(visibleItems, bookmarkUrls, bookmarkState, query)),
          BulkDownloadTray(
            availableItems: visibleItems,
            zipName: 'commonslens_bookmarks.zip',
          ),
        ],
      ),
    );
  }
}

class _BookmarksEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const _BookmarksEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: const Color(0xFF3B3B3B)),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFBDBDBD),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
