// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:ui';
import 'download_service.dart';
import 'asset_reuse_guide.dart';
import 'bookmark_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'pipeline_controller.dart';
import 'backend_providers.dart';

part 'asset_media_renderer.dart';
part 'asset_metadata_panel.dart';

enum _ViewerImageQuality { webOptimized, fullResolution }

const _viewerImageQualityStorageKey = 'commonslens.viewer.imageQuality';
const _viewerOptimizedImageWidth = 1920;

_ViewerImageQuality _loadViewerImageQuality() {
  try {
    final stored = html.window.localStorage[_viewerImageQualityStorageKey];
    return stored == _ViewerImageQuality.fullResolution.name
        ? _ViewerImageQuality.fullResolution
        : _ViewerImageQuality.webOptimized;
  } catch (_) {
    // Privacy modes can deny localStorage. Optimized remains the safe default.
    return _ViewerImageQuality.webOptimized;
  }
}

void _storeViewerImageQuality(_ViewerImageQuality quality) {
  try {
    html.window.localStorage[_viewerImageQualityStorageKey] = quality.name;
  } catch (_) {
    // The selection still works for this viewer session if storage is denied.
  }
}

class AssetViewer extends ConsumerStatefulWidget {
  final String fileId;
  final String returnUrl;

  const AssetViewer({
    super.key,
    required this.fileId,
    required this.returnUrl,
  });

  @override
  ConsumerState<AssetViewer> createState() => _AssetViewerState();
}

class _AssetViewerState extends ConsumerState<AssetViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late _ViewerImageQuality _imageQuality;
  bool _showMobileInfo = false;

  bool _urlHydrated = false;
  bool _suppressUrlSync = false;

  late FocusNode _focusNode;

  bool _isStandalone = false;
  SearchItem? _injectedTarget;
  bool _isFetchingInjected = false;
  String? _authorName;

  // Pipeline previews already own complete SearchItem objects in the
  // PipelineController's last-run output. Keep that exact in-memory list as
  // the viewer gallery instead of re-fetching a tapped title and losing the
  // surrounding results needed by the previous/next carousel.
  bool _isPipelineMode = false;
  String? _pipelineNodeId;

  // Whether _currentIndex has actually been located against a REAL,
  // populated gallery list yet — as opposed to just defaulted to 0
  // because the gallery hadn't loaded when didChangeDependencies first
  // ran. On a fresh page load/reload (the URL-hydrate branch below),
  // hydrateFromUrl's search is only *scheduled* (postFrameCallback) and
  // its network request hasn't resolved by the time the initial index
  // lookup happens synchronously right after — so that first lookup
  // always runs against an empty list, always finds nothing, and always
  // falls back to index 0. Previously nothing ever revisited that once
  // the real results streamed in, so a reload of e.g. "23 of 50" silently
  // reopened on "1 of 50" every time. See _maybeResolveInitialIndex,
  // called from build() once the gallery this viewer actually reads from
  // has items, which re-locates widget.fileId in the real list and jumps
  // the PageView to it if the initial guess (page 0) was wrong.
  bool _initialIndexResolved = false;

  @override
  void initState() {
    super.initState();

    _imageQuality = _loadViewerImageQuality();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    // _pageController and _currentIndex are set in didChangeDependencies —
    // computing the correct starting index needs GoRouterState.of(context),
    // which Flutter does not allow calling from initState() (it depends on
    // an InheritedWidget lookup that isn't valid until after initState
    // completes). didChangeDependencies is the earliest safe place, and it
    // always runs before the first build(), so `late` here is safe.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_urlHydrated) {
      _urlHydrated = true;
      final params = GoRouterState.of(context).uri.queryParameters;
      final author = params['author']?.trim();
      final from = params['from'];

      if (author != null && author.isNotEmpty) {
        // Gallery source is the author-portfolio provider (see
        // _getCombinedItems); nothing to hydrate up front, it loads itself
        // on first watch.
        _authorName = author;
      } else if (from == 'pipeline') {
        final nodeId = params['pipelineNode']?.trim();
        final pipelineItems = nodeId == null || nodeId.isEmpty
            ? null
            : ref
                .read(pipelineControllerProvider.notifier)
                .materializedItemsFor(nodeId);
        if (pipelineItems == null || pipelineItems.isEmpty) {
          // Pipeline run outputs are intentionally in-memory. A direct link
          // or browser reload may no longer have them, so retain the existing
          // single-file fallback for that case.
          _isStandalone = true;
          _fetchInjectedTarget();
        } else {
          _isPipelineMode = true;
          _pipelineNodeId = nodeId;
        }
      } else if (SearchUrlCodec.hasSearchContext(params)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;

          if (ref.read(searchControllerProvider).activeSession.items.isEmpty) {
            ref.read(searchControllerProvider.notifier).hydrateFromUrl(params);
          }
        });
      } else {
        _isStandalone = true;
        _fetchInjectedTarget();
      }

      // Now that the gallery source is resolved, find the tapped image's
      // index in the correct source — matching
      // _getCombinedItems()'s branching — instead of always reading the
      // main search session regardless of mode, which is what caused every
      // author-page (and, previously, map) tap to open on page 0.
      //
      // IMPORTANT: on a fresh page load via the hasSearchContext branch
      // above (a reload, or any direct/shared link), hydrateFromUrl's
      // actual network fetch hasn't run yet at this point — it's merely
      // scheduled. So `initialItems` here is very often still empty, and
      // this lookup can only ever fall back to index 0. That's expected
      // and fine: _initialIndexResolved below is left false whenever the
      // list we searched was empty, and build()'s
      // _maybeResolveInitialIndex re-runs this same lookup once the
      // gallery this viewer actually reads from (search/author)
      // populates for real, correcting the page if needed. Standalone
      // mode has no gallery to search against (a single injected item is
      // inserted at index 0 by _getCombinedItems), so it's always
      // considered resolved.
      final initialItems = _authorName != null
          ? ref.read(authorPortfolioProvider(_authorName!)).items
          : _isPipelineMode
              ? ref
                      .read(pipelineControllerProvider.notifier)
                      .materializedItemsFor(_pipelineNodeId!) ??
                  const <SearchItem>[]
              : ref.read(searchControllerProvider).activeSession.items;

      final targetId = _normalizedTitle(widget.fileId);
      final startIndex = initialItems
          .indexWhere((it) => _normalizedTitle(it.title) == targetId);

      _currentIndex = startIndex >= 0 ? startIndex : 0;
      _pageController = PageController(initialPage: _currentIndex);
      _initialIndexResolved =
          _isStandalone || startIndex >= 0 || initialItems.isNotEmpty;
    }
  }

  /// Re-locates widget.fileId inside [items] and jumps the PageView to it,
  /// if — and only if — the very first lookup in didChangeDependencies
  /// couldn't have been trusted (i.e. it ran against a still-empty
  /// gallery, see the comment there). This is what fixes a reload landing
  /// on "1 of N" instead of the linked position: build() re-runs
  /// automatically once the watched provider's items populate, giving
  /// this a real list to search the *first* time one exists.
  ///
  /// Only ever does something once (`_initialIndexResolved` latches true
  /// on the first real list it sees, found or not) — this is strictly an
  /// initial-load correction, not a general "keep re-syncing to the URL"
  /// mechanism. Ongoing file-to-file navigation within an already-loaded
  /// gallery is handled separately by didUpdateWidget.
  void _maybeResolveInitialIndex(List<SearchItem> items) {
    if (_initialIndexResolved) return;
    if (items.isEmpty) return; // still loading — nothing real to check yet
    _initialIndexResolved = true;

    final targetId = _normalizedTitle(widget.fileId);
    final found =
        items.indexWhere((it) => _normalizedTitle(it.title) == targetId);
    if (found < 0 || found == _currentIndex) return;

    _currentIndex = found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(found);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AssetViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newFileId = _normalizedTitle(widget.fileId);
    final oldFileId = _normalizedTitle(oldWidget.fileId);

    if (newFileId.isEmpty || newFileId == oldFileId) return;

    final items = _getCombinedItems();
    if (items.isEmpty) return;

    if (_currentIndex >= 0 && _currentIndex < items.length) {
      if (_normalizedTitle(items[_currentIndex].title) == newFileId) {
        return;
      }
    }

    int found =
        items.indexWhere((it) => _normalizedTitle(it.title) == newFileId);
    if (found != -1) {
      _suppressUrlSync = true;
      _currentIndex = found;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(found);
          setState(() {});
        }
      });
    } else if (!_isFetchingInjected) {
      _fetchInjectedTarget();
    }
  }

  String _normalizedTitle(String title) =>
      title.replaceFirst('File:', '').trim().toLowerCase();

  Future<void> _fetchInjectedTarget() async {
    setState(() => _isFetchingInjected = true);
    final item =
        await ref.read(commonsBackendProvider).fetchItem(widget.fileId);
    if (mounted) {
      setState(() {
        _injectedTarget = item;
        _isFetchingInjected = false;
      });
    }
  }

  List<SearchItem> _getCombinedItems() {
    List<SearchItem> gallery;
    if (_authorName != null) {
      gallery = ref.watch(authorPortfolioProvider(_authorName!)).items;
    } else if (_isStandalone) {
      gallery = const <SearchItem>[];
    } else if (_isPipelineMode) {
      // Watch the public pipeline state so this viewer rebuilds if the
      // controller is replaced, while reading the runtime output through
      // its dedicated accessor.
      ref.watch(pipelineControllerProvider);
      gallery = ref
              .read(pipelineControllerProvider.notifier)
              .materializedItemsFor(_pipelineNodeId!) ??
          const <SearchItem>[];
    } else {
      gallery = ref.watch(searchControllerProvider).activeSession.items;
    }

    List<SearchItem> items = List.from(gallery);

    if (_injectedTarget != null) {
      if (!items.any((it) =>
          _normalizedTitle(it.title) ==
          _normalizedTitle(_injectedTarget!.title))) {
        items.insert(0, _injectedTarget!);
      }
    }
    return items;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPageChanged(int index, int totalLength) {
    setState(() => _currentIndex = index);

    if (_suppressUrlSync) {
      _suppressUrlSync = false;
      return;
    }

    if (!_isStandalone && index >= totalLength - 3) {
      if (_authorName != null) {
        ref
            .read(authorPortfolioProvider(_authorName!).notifier)
            .loadMore(_authorName!);
      } else if (!_isPipelineMode) {
        ref.read(searchControllerProvider.notifier).loadMore();
      }
    }

    final items = _getCombinedItems();
    if (items.isNotEmpty) {
      final params = Map<String, String>.from(
          GoRouterState.of(context).uri.queryParameters);
      params['id'] = items[index].title;
      context.replace(Uri(path: '/view', queryParameters: params).toString());
    }
  }

  void _navigateToPage(int index, int totalLength) {
    if (index >= 0 && index < totalLength) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _launchCommonsUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _setImageQuality(_ViewerImageQuality quality) {
    if (quality == _imageQuality) return;
    setState(() => _imageQuality = quality);
    _storeViewerImageQuality(quality);
  }

  String? _optimizedImageUrl(SearchItem item) {
    if (item.mediaKind != MediaKind.image &&
        item.mediaKind != MediaKind.vector) {
      return null;
    }
    return item.thumbnailUrlAtWidth(_viewerOptimizedImageWidth);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchControllerProvider).activeSession;
    final portfolioSession = _authorName != null
        ? ref.watch(authorPortfolioProvider(_authorName!))
        : null;
    final items = _getCombinedItems();

    // Initial-load correction — see _maybeResolveInitialIndex's doc. No-op
    // after the first time it sees a populated list (found or not), so
    // this never fights ordinary page-swipe navigation.
    _maybeResolveInitialIndex(items);

    final isLoading = (_isStandalone && _isFetchingInjected) ||
        (portfolioSession != null &&
            portfolioSession.loading &&
            items.isEmpty) ||
        (_authorName == null &&
            !_isStandalone &&
            !_isPipelineMode &&
            session.loading &&
            items.isEmpty);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF070707),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF3D7EFF))),
      );
    }

    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF070707),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go(widget.returnUrl);
              }
            },
          ),
        ),
        body: const Center(
          child: Text('Media not found.',
              style: TextStyle(color: Color(0xFF555555))),
        ),
      );
    }

    if (_currentIndex >= items.length || _currentIndex < 0) {
      _currentIndex = 0;
    }

    final currentItem = items[_currentIndex];
    final currentOptimizedUrl = _optimizedImageUrl(currentItem);
    final isBookmarked = ref.watch(
      bookmarkStoreProvider.select(
        (store) => store.isBookmarked(currentItem.url),
      ),
    );
    final hasPrevious = _currentIndex > 0;
    final hasNext = _currentIndex < items.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF070707),
      appBar: AppBar(
        backgroundColor: const Color(0xFF070707),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.go(widget.returnUrl),
        ),
        title: Text(
          !_isStandalone
              ? '${_currentIndex + 1} OF ${items.length}'
              : 'DIRECT LINK',
          style: const TextStyle(
            color: Color(0xFF7A7A7A),
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: isBookmarked ? 'Remove bookmark' : 'Bookmark image',
            icon: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: isBookmarked ? const Color(0xFF3D7EFF) : Colors.white,
            ),
            onPressed: () =>
                ref.read(bookmarkStoreProvider).toggle(currentItem.url),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (MediaQuery.of(context).size.width < 800) {
                return IconButton(
                  icon: Icon(
                    _showMobileInfo ? Icons.info : Icons.info_outline,
                    color: _showMobileInfo
                        ? const Color(0xFF3D7EFF)
                        : Colors.white,
                  ),
                  onPressed: () =>
                      setState(() => _showMobileInfo = !_showMobileInfo),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: KeyboardListener(
          focusNode: _focusNode,
          onKeyEvent: (KeyEvent event) {
            if (event is KeyDownEvent) {
              if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                _navigateToPage(_currentIndex - 1, items.length);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                _navigateToPage(_currentIndex + 1, items.length);
              }
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 800;

              return Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          physics: !_isStandalone
                              ? const BouncingScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          itemCount: items.length,
                          onPageChanged: (index) =>
                              _onPageChanged(index, items.length),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final optimizedUrl = _optimizedImageUrl(item);
                            final imageUrl = _imageQuality ==
                                        _ViewerImageQuality.webOptimized &&
                                    optimizedUrl != null
                                ? optimizedUrl
                                : item.url;

                            return _NativeMediaRenderer(
                              key: ValueKey('${item.url}|$imageUrl'),
                              item: item,
                              imageUrl: imageUrl,
                            );
                          },
                        ),
                        if (hasPrevious && isDesktop && !_isStandalone)
                          Positioned(
                            left: 24,
                            top: 0,
                            bottom: 0,
                            child: _NavigationButton(
                              icon: Icons.arrow_back_ios_new,
                              onTap: () => _navigateToPage(
                                  _currentIndex - 1, items.length),
                            ),
                          ),
                        if (hasNext && isDesktop && !_isStandalone)
                          Positioned(
                            right: 24,
                            top: 0,
                            bottom: 0,
                            child: _NavigationButton(
                              icon: Icons.arrow_forward_ios,
                              onTap: () => _navigateToPage(
                                  _currentIndex + 1, items.length),
                            ),
                          ),
                        if (!isDesktop && _showMobileInfo)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * 0.6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF111111),
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(16)),
                                border: Border(
                                    top: BorderSide(color: Color(0xFF222222))),
                              ),
                              child: _MetadataInspector(
                                item: currentItem,
                                imageQuality: currentOptimizedUrl == null
                                    ? null
                                    : _imageQuality,
                                onImageQualityChanged:
                                    currentOptimizedUrl == null
                                        ? null
                                        : _setImageQuality,
                                onLaunchCommons: () =>
                                    _launchCommonsUrl(currentItem.commonsUrl),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isDesktop)
                    Container(
                      width: 380,
                      decoration: const BoxDecoration(
                        color: Color(0xFF111111),
                        border:
                            Border(left: BorderSide(color: Color(0xFF1E1E1E))),
                      ),
                      child: _MetadataInspector(
                        item: currentItem,
                        imageQuality:
                            currentOptimizedUrl == null ? null : _imageQuality,
                        onImageQualityChanged: currentOptimizedUrl == null
                            ? null
                            : _setImageQuality,
                        onLaunchCommons: () =>
                            _launchCommonsUrl(currentItem.commonsUrl),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
