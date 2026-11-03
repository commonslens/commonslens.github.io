import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'bookmark_service.dart';
import 'download_queue.dart';
import 'media_queue.dart';
import 'search_components.dart';
import 'search_models.dart';
import 'legal_pages.dart';
import 'page_welcome.dart';

class BookmarksPage extends ConsumerStatefulWidget {
  final String initialQuery;
  final String? initialFolderId;

  const BookmarksPage({
    super.key,
    this.initialQuery = '',
    this.initialFolderId,
  });

  @override
  ConsumerState<BookmarksPage> createState() => _BookmarksPageState();
}

class _BookmarksPageState extends ConsumerState<BookmarksPage> {
  late final _searchController =
      TextEditingController(text: widget.initialQuery);
  final _scrollController = ScrollController();
  final Set<String> _selectedBookmarkUrls = <String>{};
  String? _selectedFolderId;
  bool _folderSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.initialFolderId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PageWelcome.maybeShow(context, WelcomeArea.bookmarks);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BookmarksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _searchController.text = widget.initialQuery;
    }
    if (oldWidget.initialFolderId != widget.initialFolderId) {
      _selectedFolderId = widget.initialFolderId;
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

  Future<String?> _showFolderNameDialog({String? initialName}) async {
    final controller = TextEditingController(text: initialName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          initialName == null ? 'Create folder' : 'Rename folder',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Folder name',
            labelStyle: TextStyle(color: Color(0xFF888888)),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF444444)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF3D7EFF)),
            ),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: Text(initialName == null ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
    // The dialog route and its focused text field are still being removed
    // when showDialog completes. Let that teardown finish before disposing
    // the controller or changing the bookmark tree.
    await Future<void>.delayed(const Duration(milliseconds: 220));
    controller.dispose();
    return result;
  }

  Future<void> _waitForDialogToClose() async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<String?> _createFolder() async {
    final name = await _showFolderNameDialog();
    if (!mounted || name == null || name.isEmpty) return null;
    final folderId = ref.read(bookmarkStoreProvider).createFolder(name);
    setState(() {
      _selectedFolderId = folderId;
      _folderSelectionMode = false;
      _selectedBookmarkUrls.clear();
    });
    return folderId;
  }

  void _selectFolder(String? folderId) {
    setState(() {
      _selectedFolderId = folderId;
      if (folderId != null) {
        _folderSelectionMode = false;
        _selectedBookmarkUrls.clear();
      }
    });
  }

  void _startFolderSelection() {
    if (_selectedFolderId != null) {
      _selectFolder(null);
    }
    ref.read(selectionModeProvider.notifier).state = false;
    setState(() => _folderSelectionMode = true);
  }

  void _stopFolderSelection() {
    setState(() {
      _folderSelectionMode = false;
      _selectedBookmarkUrls.clear();
    });
  }

  void _toggleFolderSelected(SearchItem item) {
    setState(() {
      if (!_selectedBookmarkUrls.add(item.url)) {
        _selectedBookmarkUrls.remove(item.url);
      }
    });
  }

  Future<void> _addSelectedToFolders() async {
    if (_selectedBookmarkUrls.isEmpty) return;
    final store = ref.read(bookmarkStoreProvider);
    final folderIds = <String>{};
    final selectedUrls = Set<String>.from(_selectedBookmarkUrls);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          title: Text(
            'Add ${selectedUrls.length} selected media to folders',
            style: const TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: SizedBox(
            width: 360,
            child: store.folders.isEmpty
                ? const Text(
                    'Create a folder first, then add the selected media to it.',
                    style: TextStyle(color: Color(0xFFB0B0B0), height: 1.4),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: store.folders.map((folder) {
                        final checked = folderIds.contains(folder.id);
                        return CheckboxListTile(
                          value: checked,
                          dense: true,
                          activeColor: const Color(0xFF3D7EFF),
                          title: Text(folder.name,
                              style: const TextStyle(color: Colors.white)),
                          subtitle: Text(
                            '${folder.urls.length} media',
                            style: const TextStyle(color: Color(0xFF777777)),
                          ),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                folderIds.add(folder.id);
                              } else {
                                folderIds.remove(folder.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _waitForDialogToClose();
                final folderId = await _createFolder();
                if (!mounted || folderId == null) return;
                store.addUrlsToFolder(folderId, selectedUrls);
                _stopFolderSelection();
              },
              child: const Text('Create folder'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: folderIds.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(
                        Set<String>.from(folderIds),
                      ),
              child: Text(
                  'Add to ${folderIds.length == 1 ? 'folder' : 'folders'}'),
            ),
          ],
        ),
      ),
    );
    await _waitForDialogToClose();
    if (!mounted || result == null || result.isEmpty) return;
    store.addUrlsToFolders(result, selectedUrls);
    _stopFolderSelection();
  }

  Future<void> _renameFolder(BookmarkFolder folder) async {
    final name = await _showFolderNameDialog(initialName: folder.name);
    if (!mounted || name == null || name.isEmpty) return;
    ref.read(bookmarkStoreProvider).renameFolder(folder.id, name);
  }

  Future<void> _deleteFolder(BookmarkFolder folder) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete folder?',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: Text(
          'This removes the folder, but keeps its media in All Bookmarked Media.',
          style: const TextStyle(color: Color(0xFFB0B0B0), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7A2727)),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    await _waitForDialogToClose();
    if (!mounted || shouldDelete != true) return;
    ref.read(bookmarkStoreProvider).deleteFolder(folder.id);
    if (_selectedFolderId == folder.id) {
      setState(() => _selectedFolderId = null);
    }
  }

  Widget _folderPreview(SearchItem? item) {
    if (item == null) {
      return const ColoredBox(
        color: Color(0xFF242424),
        child: Icon(Icons.folder_outlined, color: Color(0xFF777777), size: 22),
      );
    }
    // Use the same candidate/fallback path as the main media cards. A
    // resized Wikimedia URL can fail even when the item's normal thumbnail
    // works, which used to make populated folders look empty.
    return MediaPreview(item: item, index: 0);
  }

  SearchItem? _previewItem(BookmarkItemsState bookmarkState, Set<String> urls) {
    final itemsByUrl = <String, SearchItem>{
      for (final item in bookmarkState.items) item.url: item,
    };
    // Sets preserve insertion order here, so the first matching URL is the
    // first media added to this folder rather than the first global bookmark.
    for (final url in urls) {
      final item = itemsByUrl[url];
      if (item != null) return item;
    }
    return null;
  }

  Widget _buildAlbumTile({
    required String title,
    required String subtitle,
    required SearchItem? preview,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      selected: selected,
      selectedTileColor: const Color(0xFF203B70),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: 52, height: 52, child: _folderPreview(preview)),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildFolderPanel(BookmarkStore store,
      BookmarkItemsState bookmarkState, String? selectedFolderId) {
    final allPreview = _previewItem(bookmarkState, store.urls);
    return Container(
      width: 286,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(right: BorderSide(color: Color(0xFF252525))),
      ),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 20),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: Text(
                'BOOKMARK ALBUMS',
                style: TextStyle(
                  color: Color(0xFF777777),
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _buildAlbumTile(
              title: 'All Bookmarked Media',
              subtitle: '${store.urls.length} media',
              preview: allPreview,
              selected: selectedFolderId == null,
              onTap: () => _selectFolder(null),
              trailing: IconButton(
                tooltip: 'Select media to add to a folder',
                onPressed: _startFolderSelection,
                icon: const Icon(Icons.checklist_rtl,
                    size: 20, color: Color(0xFF8EB1FF)),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 2, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'FOLDERS',
                      style: TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 10,
                        letterSpacing: 1.6,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _createFolder,
                    icon:
                        const Icon(Icons.create_new_folder_outlined, size: 16),
                    label: const Text('Add folder'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF8EB1FF),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            if (store.folders.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Text(
                  'Create a folder to organize bookmarked media like albums.',
                  style: TextStyle(
                      color: Color(0xFF6D6D6D), fontSize: 12, height: 1.4),
                ),
              ),
            ...store.folders.map((folder) {
              final folderUrls = store.urlsInFolder(folder.id);
              return _buildAlbumTile(
                title: folder.name,
                subtitle: '${folderUrls.length} media',
                preview: _previewItem(bookmarkState, folderUrls),
                selected: selectedFolderId == folder.id,
                onTap: () => _selectFolder(folder.id),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Folder options',
                  icon: const Icon(Icons.more_vert,
                      size: 18, color: Color(0xFF777777)),
                  onSelected: (action) {
                    if (action == 'rename') _renameFolder(folder);
                    if (action == 'delete') _deleteFolder(folder);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionToolbar(
      String? selectedFolderId, BookmarkItemsState bookmarkState) {
    if (selectedFolderId != null || bookmarkState.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 7, 12, 7),
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(bottom: BorderSide(color: Color(0xFF202020))),
      ),
      child: Row(
        children: [
          if (_folderSelectionMode) ...[
            Text(
              '${_selectedBookmarkUrls.length} media selected',
              style: const TextStyle(
                color: Color(0xFFBDBDBD),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed:
                  _selectedBookmarkUrls.isEmpty ? null : _addSelectedToFolders,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('Add to folder'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Cancel media selection',
              onPressed: _stopFolderSelection,
              icon: const Icon(Icons.close, size: 19),
              color: const Color(0xFFAAAAAA),
            ),
          ] else ...[
            const Spacer(),
            TextButton.icon(
              onPressed: _startFolderSelection,
              icon: const Icon(Icons.checklist_rtl, size: 17),
              label: const Text('Select media to add to a folder'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8EB1FF),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(
      List<SearchItem> visibleItems,
      Set<String> bookmarkUrls,
      BookmarkItemsState bookmarkState,
      String query,
      String? folderId,
      Set<String>? folderUrls) {
    final folderSelectionActive = _folderSelectionMode && folderId == null;
    if (bookmarkUrls.isEmpty) {
      return const _BookmarksEmptyState(
        icon: Icons.bookmark_border,
        title: 'No bookmarks yet',
        message:
            'Bookmark media from the search grid or asset viewer and it will appear here.',
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
            '${visibleItems.length} OF ${folderId == null ? bookmarkState.items.length : bookmarkState.items.where((item) => folderUrls!.contains(item.url)).length} MEDIA'
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
          Expanded(
            child: _BookmarksEmptyState(
              icon: folderId == null ? Icons.search_off : Icons.folder_open,
              title: folderId == null
                  ? 'No matching bookmarks'
                  : 'Folder is empty',
              message: folderId == null
                  ? 'Try a different title, category, uploader, or URL.'
                  : 'Choose media from All Bookmarked Media to add it to this folder.',
              action: folderId == null
                  ? null
                  : FilledButton.icon(
                      onPressed: _startFolderSelection,
                      icon: const Icon(Icons.playlist_add, size: 17),
                      label: const Text('Add media from bookmarks'),
                    ),
            ),
          )
        else
          Expanded(
            child: MediaResultsGrid(
              controller: _scrollController,
              items: visibleItems,
              queueSource:
                  MediaQueueSource.bookmarks(query, folderId: folderId),
              showFolderAction: !folderSelectionActive,
              folderSelectionMode: folderSelectionActive,
              selectedFolderUrls: _selectedBookmarkUrls,
              onFolderSelectionToggle: _toggleFolderSelected,
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
    final bookmarkStore = ref.watch(bookmarkStoreProvider);
    final bookmarkUrls = bookmarkStore.urls;
    final bookmarkState = ref.watch(bookmarkItemsProvider);
    final folders = bookmarkStore.folders;
    final selectedFolderId =
        folders.any((folder) => folder.id == _selectedFolderId)
            ? _selectedFolderId
            : null;
    final folderUrls = selectedFolderId == null
        ? null
        : bookmarkStore.urlsInFolder(selectedFolderId);

    final query = _searchController.text.trim().toLowerCase();
    final visibleItems = bookmarkState.items
        .where((item) => folderUrls == null || folderUrls.contains(item.url))
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
        actions: const [
          DocsSectionLink(
            section: 'bookmarks',
            label: 'User Guide to Bookmarks',
          ),
          SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final panelWidth = constraints.maxWidth < 620 ? 238.0 : 286.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: panelWidth,
                child: _buildFolderPanel(
                    bookmarkStore, bookmarkState, selectedFolderId),
              ),
              Expanded(
                child: Column(
                  children: [
                    _buildSearchBar(),
                    _buildSelectionToolbar(selectedFolderId, bookmarkState),
                    Expanded(
                      child: _buildBody(
                        visibleItems,
                        bookmarkUrls,
                        bookmarkState,
                        query,
                        selectedFolderId,
                        folderUrls,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
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
