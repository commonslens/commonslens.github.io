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
import 'search_controller.dart';
import 'backend_providers.dart';
import 'media_queue.dart';

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
  PageController? _pageController;
  int _currentIndex = 0;
  late _ViewerImageQuality _imageQuality;
  late FocusNode _focusNode;
  bool _showMobileInfo = false;
  bool _sourceReady = false;
  bool _loadingMoreForTarget = false;
  int _lastLoadAttemptCount = -1;
  bool _hydratingSearch = false;
  bool _fetchingTarget = false;
  String? _fetchedTitle;
  String? _pendingNavigationTitle;
  SearchItem? _standaloneItem;
  List<SearchItem> _visibleItems = const [];
  MediaQueueData _queueData = const MediaQueueData([]);
  late MediaQueueSource _source;
  String? _queueId;
  MediaQueueSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _imageQuality = _loadViewerImageQuality();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sourceReady) return;
    _sourceReady = true;
    final params = GoRouterState.of(context).uri.queryParameters;
    _source = MediaQueueSource.fromUrl(params);
    _queueId = params['queue'];
    _snapshot = ref.read(mediaQueueStoreProvider).get(_queueId, _source);
    final savedTarget = _snapshot?.items.any((item) =>
            normalizeMediaTitle(item.title) ==
            normalizeMediaTitle(widget.fileId)) ??
        false;
    if (_source.kind == 'search' && !savedTarget) _startSearchHydration();
  }

  void _startSearchHydration() {
    if (_hydratingSearch || _source.kind != 'search') return;
    if (MediaQueueResolver.searchIsLive(ref, _source)) return;
    _hydratingSearch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await MediaQueueResolver.hydrateSearch(ref, _source);
      } finally {
        if (mounted) setState(() => _hydratingSearch = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant AssetViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (normalizeMediaTitle(oldWidget.fileId) !=
        normalizeMediaTitle(widget.fileId)) {
      _pendingNavigationTitle = null;
      _fetchedTitle = null;
      _fetchingTarget = false;
      _standaloneItem = null;
      _lastLoadAttemptCount = -1;
    }
  }

  void _fetchStandaloneTarget() {
    final title = widget.fileId;
    if (_fetchingTarget || _fetchedTitle == title) return;
    _fetchingTarget = true;
    _fetchedTitle = title;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      SearchItem? item;
      try {
        item = await ref.read(commonsBackendProvider).fetchItem(title);
      } catch (_) {
        item = null;
      }
      if (!mounted || widget.fileId != title) return;
      setState(() {
        _standaloneItem = item;
        _fetchingTarget = false;
      });
    });
  }

  void _loadMoreForTarget(int currentCount) {
    if (_loadingMoreForTarget) return;
    _lastLoadAttemptCount = currentCount;
    _loadingMoreForTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await MediaQueueResolver.loadMore(ref, _source);
      } finally {
        if (mounted) setState(() => _loadingMoreForTarget = false);
      }
    });
  }

  void _resolvePage(List<SearchItem> items) {
    final title = normalizeMediaTitle(_pendingNavigationTitle ?? widget.fileId);
    final found =
        items.indexWhere((item) => normalizeMediaTitle(item.title) == title);
    if (found < 0) return;
    if (_pageController == null || !_pageController!.hasClients) {
      final oldController = _pageController;
      _currentIndex = found;
      _pageController = PageController(initialPage: found);
      if (oldController != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
    } else if (_currentIndex != found) {
      _currentIndex = found;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController?.hasClients == true) {
          _pageController!.jumpToPage(found);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPageChanged(int index, int totalLength) {
    if (index < 0 || index >= _visibleItems.length) return;
    final item = _visibleItems[index];
    setState(() => _currentIndex = index);
    _pendingNavigationTitle = item.title;
    if (_queueData.hasMore && index >= totalLength - 3) {
      if (_queueData.fromSnapshot) {
        _startSearchHydration();
      } else {
        MediaQueueResolver.loadMore(ref, _source);
      }
    }
    final nextUrl = _source.urlFor(item.title, queueId: _queueId);
    if (GoRouterState.of(context).uri.toString() != nextUrl) {
      context.replace(nextUrl);
    }
  }

  void _navigateToPage(int index, int totalLength) {
    if (index >= 0 && index < totalLength) {
      _pageController?.animateToPage(
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
    _snapshot = ref.read(mediaQueueStoreProvider).get(_queueId, _source);
    final data = MediaQueueResolver.watch(
      ref,
      _source,
      _snapshot,
      widget.fileId,
    );
    _queueData = data;
    final target = normalizeMediaTitle(widget.fileId);
    var items = data.items;
    var isStandalone = _source.kind == 'direct';
    final targetInQueue = items.any(
      (item) => normalizeMediaTitle(item.title) == target,
    );

    // A stored queue can display the requested position immediately while a
    // fresh search catches up through its earlier pages in the background.
    if (_source.kind == 'search' &&
        data.fromSnapshot &&
        MediaQueueResolver.searchIsLive(ref, _source)) {
      final live = ref.read(searchControllerProvider).activeSession;
      if (!live.loading &&
          !live.loadingMore &&
          live.hasMore &&
          !live.items
              .any((item) => normalizeMediaTitle(item.title) == target)) {
        if (live.items.length > _lastLoadAttemptCount) {
          _loadMoreForTarget(live.items.length);
        }
      }
    }

    if (!targetInQueue) {
      if (_source.kind == 'search' &&
          !MediaQueueResolver.searchIsLive(ref, _source)) {
        _startSearchHydration();
      }
      if (!isStandalone &&
          !data.loading &&
          data.hasMore &&
          items.length > _lastLoadAttemptCount) {
        _loadMoreForTarget(items.length);
        items = const [];
      } else if (isStandalone ||
          (!data.loading &&
              (!data.hasMore || items.length <= _lastLoadAttemptCount))) {
        _fetchStandaloneTarget();
        isStandalone = true;
        if (_standaloneItem != null &&
            normalizeMediaTitle(_standaloneItem!.title) == target) {
          items = [_standaloneItem!];
        } else {
          items = const [];
        }
      } else {
        items = const [];
      }
    }

    if (items.isEmpty &&
        ((data.loading && !isStandalone) ||
            _loadingMoreForTarget ||
            _hydratingSearch ||
            _fetchingTarget ||
            _fetchedTitle == null)) {
      return const Scaffold(
        backgroundColor: Color(0xFF070707),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3D7EFF)),
        ),
      );
    }

    if (!isStandalone &&
        !data.fromSnapshot &&
        _queueId != null &&
        items.isNotEmpty &&
        (_snapshot == null ||
            _snapshot!.hasMore != data.hasMore ||
            !listEquals(
              _snapshot!.items.map((item) => item.title).toList(),
              items.map((item) => item.title).toList(),
            ))) {
      ref.read(mediaQueueStoreProvider).update(
            _queueId!,
            _source,
            items,
            hasMore: data.hasMore,
          );
      _snapshot = ref.read(mediaQueueStoreProvider).get(_queueId, _source);
    }
    _visibleItems = items;
    if (items.isNotEmpty) _resolvePage(items);

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
                context.go(_source.kind == 'direct'
                    ? widget.returnUrl
                    : _source.returnUrl);
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
          onPressed: () => context.go(
              _source.kind == 'direct' ? widget.returnUrl : _source.returnUrl),
        ),
        title: Text(
          !isStandalone
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
                          controller: _pageController!,
                          physics: !isStandalone
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
                        if (hasPrevious && isDesktop && !isStandalone)
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
                        if (hasNext && isDesktop && !isStandalone)
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
