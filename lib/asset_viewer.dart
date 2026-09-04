// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:ui';
import 'download_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_service.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'map_controller.dart';
import 'analytics_service.dart';

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
  bool _showMobileInfo = false;

  bool _urlHydrated = false;
  bool _suppressUrlSync = false;

  late FocusNode _focusNode;
  final SearchService _service = SearchService();

  bool _isStandalone = false;
  SearchItem? _injectedTarget;
  bool _isFetchingInjected = false;
  String? _authorName;

  // Set when this viewer was opened from the map page (see
  // MapPage._openItem / _ResultsSheet's MediaCard extraParams, and
  // router.dart's 'from' == 'map' branch for the return route). When true,
  // the gallery is sourced from mapSearchControllerProvider's live session
  // instead of the main searchControllerProvider — that session already
  // has real results (browse or filtered mode) sitting in memory from the
  // map page, so there's nothing to re-fetch and, critically, no reason to
  // hijack the main page's search session the way hydrating it here used
  // to.
  bool _isMapMode = false;

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
      } else if (from == 'map') {
        // Map-originated navigation (see MapPage._openItem / _ResultsSheet's
        // MediaCard extraParams, and router.dart's 'from' == 'map' branch
        // for the return route). The gallery already lives in
        // mapSearchControllerProvider's session — populated by whatever the
        // person was looking at on the map, for both browse and filtered
        // geo modes — so there's nothing to fetch here. Crucially, this
        // must NOT fall into the hasSearchContext branch below: a
        // filtered-mode map result carries filterState params too, and
        // hydrating those into searchControllerProvider would hijack the
        // main page's session and re-run the query against the wrong
        // engine. If the map session is empty (e.g. this URL was opened
        // directly, or the app reloaded and the in-memory session never
        // got populated), fall back to a standalone single-item view
        // instead of showing an empty gallery.
        if (ref.read(mapSearchControllerProvider).session.items.isEmpty) {
          _isStandalone = true;
          _fetchInjectedTarget();
        } else {
          _isMapMode = true;
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

      // Now that _authorName/_isMapMode are resolved, find the tapped
      // image's index in the correct source — matching
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
      // gallery this viewer actually reads from (search/author/map)
      // populates for real, correcting the page if needed. Standalone
      // mode has no gallery to search against (a single injected item is
      // inserted at index 0 by _getCombinedItems), so it's always
      // considered resolved.
      final initialItems = _authorName != null
          ? ref.read(authorPortfolioProvider(_authorName!)).items
          : _isMapMode
              ? ref.read(mapSearchControllerProvider).session.items
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
    final found = items.indexWhere((it) => _normalizedTitle(it.title) == targetId);
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
    final item = await _service.fetchSingleItem(widget.fileId);
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
    } else if (_isMapMode) {
      gallery = ref.watch(mapSearchControllerProvider).session.items;
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
      } else if (_isMapMode) {
        // See GeoBrowseSession/CommonsSearchSession's loadMore docs (via
        // MapSearchController) — a no-op in most geosearch cases, but the
        // correct call regardless of geo mode.
        ref.read(mapSearchControllerProvider.notifier).loadMore();
      } else {
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(searchControllerProvider).activeSession;
    final portfolioSession = _authorName != null
        ? ref.watch(authorPortfolioProvider(_authorName!))
        : null;
    final mapSession =
        _isMapMode ? ref.watch(mapSearchControllerProvider).session : null;
    final items = _getCombinedItems();

    // Initial-load correction — see _maybeResolveInitialIndex's doc. No-op
    // after the first time it sees a populated list (found or not), so
    // this never fights ordinary page-swipe navigation.
    _maybeResolveInitialIndex(items);

    final isLoading = (_isStandalone && _isFetchingInjected) ||
        (portfolioSession != null &&
            portfolioSession.loading &&
            items.isEmpty) ||
        (mapSession != null && mapSession.loading && items.isEmpty) ||
        (_authorName == null &&
            !_isStandalone &&
            !_isMapMode &&
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
                            return _NativeMediaRenderer(item: items[index]);
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

class _NativeMediaRenderer extends StatefulWidget {
  final SearchItem item;

  const _NativeMediaRenderer({required this.item});

  @override
  State<_NativeMediaRenderer> createState() => _NativeMediaRendererState();
}

class _NativeMediaRendererState extends State<_NativeMediaRenderer> {
  late final String _viewId;
  bool _isNativeHtml = false;

  bool _isSafariWeb() {
    final userAgent = html.window.navigator.userAgent.toLowerCase();
    final hasSafari = userAgent.contains('safari');
    final hasChromeLike = userAgent.contains('chrome') ||
        userAgent.contains('chromium') ||
        userAgent.contains('crios');
    return hasSafari && !hasChromeLike;
  }

  bool _shouldRenderPdfInBrowser() {
    if (!kIsWeb) return false;

    final isPdf = widget.item.extension.toLowerCase() == 'pdf' ||
        widget.item.mime.toLowerCase() == 'application/pdf';
    final isDjVu = widget.item.extension.toLowerCase() == 'djvu' ||
        widget.item.mime.toLowerCase() == 'image/vnd.djvu';

    return isPdf && !isDjVu && !_isSafariWeb();
  }

  @override
  void initState() {
    super.initState();
    _viewId =
        'media-view-${widget.item.url.hashCode}-${DateTime.now().millisecondsSinceEpoch}';

    final isVideo = widget.item.mediaKind == MediaKind.video;
    final isAudio = widget.item.mediaKind == MediaKind.audio;
    final isImage = widget.item.mediaKind == MediaKind.image ||
        widget.item.mediaKind == MediaKind.vector;
    final shouldRenderPdf = widget.item.mediaKind == MediaKind.document &&
        _shouldRenderPdfInBrowser();

    // PDFs are safe to inline in Chrome/Web, but Safari does not reliably
    // render cross-origin PDFs inside a browser iframe. DjVu remains blocked
    // because the browser fallback is unreliable there.
    if (isVideo || isAudio || isImage || shouldRenderPdf) {
      _isNativeHtml = true;

      ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
        if (isImage) {
          return html.ImageElement()
            ..src = widget.item.url
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = 'transparent'
            ..style.outline = 'none';
        } else if (isVideo) {
          return html.VideoElement()
            ..src = widget.item.url
            ..controls = true
            ..autoplay = false
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.objectFit = 'contain'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else if (shouldRenderPdf) {
          return html.IFrameElement()
            ..src = widget.item.url
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.border = 'none'
            ..style.backgroundColor = '#070707'
            ..style.outline = 'none';
        } else {
          // isAudio — the only remaining branch.
          final container = html.DivElement()
            ..style.display = 'flex'
            ..style.alignItems = 'center'
            ..style.justifyContent = 'center'
            ..style.width = '100%'
            ..style.height = '100%';

          final audio = html.AudioElement()
            ..src = widget.item.url
            ..controls = true
            ..autoplay = false
            ..style.width = '80%'
            ..style.outline = 'none';

          container.append(audio);
          return container;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isNativeHtml) {
      final isDesktop = MediaQuery.of(context).size.width >= 800;
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: isDesktop ? 80.0 : 0.0),
        child: HtmlElementView(viewType: _viewId),
      );
    }

    return _buildFallbackUI(widget.item);
  }

  Widget _buildFallbackUI(SearchItem item) {
    IconData icon;
    String typeLabel;

    switch (item.mediaKind) {
      case MediaKind.vector:
        icon = Icons.polyline_outlined;
        typeLabel = 'VECTOR GRAPHIC';
        break;
      case MediaKind.document:
        icon = Icons.description_outlined;
        typeLabel = 'DOCUMENT (${item.extension.toUpperCase()})';
        break;
      default:
        icon = Icons.insert_drive_file_outlined;
        typeLabel = 'FILE';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (item.thumb.isNotEmpty) Image.network(item.thumb, fit: BoxFit.cover),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: Colors.black.withValues(alpha: 0.65),
          ),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 72, color: Colors.white60),
              const SizedBox(height: 16),
              Text(
                typeLabel,
                style: const TextStyle(
                  color: Color(0xFFAAAAAA),
                  fontSize: 12,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(item.url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.open_in_browser, size: 20),
                label: const Text(
                  'Open Media / Download',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetadataInspector extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _MetadataInspector({
    required this.item,
    required this.onLaunchCommons,
  });

  String _cleanHtml(String html) {
    if (html.isEmpty) return '';
    final exp = RegExp(r'<[^>]*>', multiLine: true, caseSensitive: true);
    return html.replaceAll(exp, '').trim();
  }

  /// Shared section header, used everywhere below instead of one-off
  /// Text+Divider blocks, so every section in the panel reads with the
  /// same rhythm as it flows from Title -> Author -> Download ->
  /// Description -> Dates -> Metadata -> Global Usage.
  Widget _sectionHeader(String label, {bool withDivider = true}) {
    return Padding(
      padding: EdgeInsets.only(top: withDivider ? 0 : 24, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (withDivider) ...[
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 24),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 1. TITLE
        SelectableText(
          item.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),

        // 2. AUTHOR — who made it and who uploaded it, together, right
        // under the title since that's the first thing after "what is
        // this" that a person orients on.
        _buildAuthorSection(context),

        // 3. DOWNLOAD — get the file, plus the one action that starts a
        // new exploration from this file: finding everything else shot
        // near it.
        _sectionHeader('DOWNLOAD & ACTIONS', withDivider: false),
        _DownloadSection(item: item, onLaunchCommons: onLaunchCommons),

        // 4. DESCRIPTION — every free-text descriptive field together,
        // rather than split between a top-level "snippet" and a buried
        // "Additional Details" entry.
        _buildDescriptionSection(),

        // 5. DATES — created vs. uploaded, side by side.
        _buildDatesSection(),

        // 6. METADATA — structural/technical facts (type, dimensions,
        // categories, license/rights, GPS) plus, lazily, Structured Data
        // on Commons statements (creator/institution/depicts and anything
        // else editors have added as SDC claims).
        _buildMetadataSection(context),

        // 7. RELATED MEDIA — CirrusSearch's own similarity engine
        // (morelike:), for "find me more like this" discovery.
        if (item.hasCoordinates) ...[
          const SizedBox(height: 10),
          _NearbyMediaButton(item: item),
        ],
        _RelatedMediaSection(fileTitle: item.title),

        // 8. GLOBAL USAGE — a real-world "is this used anywhere" signal,
        // the natural last stop after everything the file itself says
        // about itself.
        _GlobalUsageSection(fileTitle: item.title),
      ],
    );
  }

  Widget _buildAuthorSection(BuildContext context) {
    final cleanArtist = _cleanHtml(item.artistHtml);
    if (cleanArtist.isEmpty && item.uploader.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPropertyRow('AUTHOR / CREATOR', cleanArtist),
          _buildUploaderRow(context, item.uploader),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection() {
    final snippet = item.snippet.isEmpty ? '' : _cleanHtml(item.snippet);
    final imageDescription = _cleanHtml(item.imageDescriptionHtml);
    final objectName = item.objectName.trim();

    final hasAnyDescription = snippet.isNotEmpty ||
        imageDescription.isNotEmpty ||
        objectName.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('DESCRIPTION'),
          if (!hasAnyDescription)
            const Text(
              'No description provided by the archivist.',
              style: TextStyle(
                color: Color(0xFFB0B0B0),
                fontSize: 14,
                height: 1.6,
              ),
            )
          else ...[
            _buildPropertyRow('OBJECT NAME', objectName),
            _buildPropertyRow('IMAGE DESCRIPTION', imageDescription),
            if (snippet.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SelectableText(
                  snippet,
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatesSection() {
    final created = item.dateTimeOriginal.trim();
    final uploaded = item.uploadDateTime.trim().isNotEmpty
        ? item.uploadDateTime.trim()
        : (item.timestamp ?? '').trim();

    if (created.isEmpty && uploaded.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('DATES'),
          _buildPropertyRow('CREATED', created),
          _buildPropertyRow('UPLOADED', uploaded),
        ],
      ),
    );
  }

  /// Structural/technical facts, license/rights, and location — everything
  /// that isn't "who made it", "what does it show", or "when" — plus,
  /// lazily, the file's Structured Data on Commons statements (creator,
  /// institution, depicts, and anything else editors have added), fetched
  /// the same on-expand-only way as Global Usage below.
  Widget _buildMetadataSection(BuildContext context) {
    final dimensions = (item.width > 0 && item.height > 0)
        ? '${item.width} × ${item.height} px'
        : '';
    final coordinates = (item.gpsLatitude.trim().isNotEmpty &&
            item.gpsLongitude.trim().isNotEmpty)
        ? '${item.gpsLatitude}, ${item.gpsLongitude}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('METADATA'),
          _buildPropertyRow('FILE TYPE', item.mime.toUpperCase()),
          _buildPropertyRow('EXTENSION', item.extension.toUpperCase()),
          _buildPropertyRow('DIMENSIONS', dimensions),
          _buildPropertyRow('CATEGORIES', item.categories.trim()),
          _buildPropertyRow('ASSESSMENTS', item.assessments.trim()),
          _buildLicenseRow(
            context,
            'LICENSE',
            _cleanHtml(item.licenseShortName),
            item.licenseUrl,
          ),
          _buildPropertyRow('USAGE TERMS', item.usageTerms.trim()),
          _buildPropertyRow('COPYRIGHT STATUS', item.copyrighted.trim()),
          _buildPropertyRow('RESTRICTIONS', item.restrictions.trim()),
          _buildPropertyRow('CREDIT', _cleanHtml(item.creditHtml)),
          _buildPropertyRow('PERMISSION', _cleanHtml(item.permissionHtml)),
          _buildPropertyRow(
              'ATTRIBUTION REQUIRED', item.attributionRequired.trim()),
          _buildPropertyRow('GPS COORDINATES', coordinates),
          _StructuredDataSection(fileTitle: item.title),
        ],
      ),
    );
  }

  Widget _buildLicenseRow(
    BuildContext context,
    String label,
    String value,
    String? url,
  ) {
    if (value.isEmpty) return const SizedBox.shrink();

    final cleanUrl = (url ?? '').trim();
    final isClickable = cleanUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (isClickable)
            InkWell(
              onTap: () async {
                final uri = Uri.tryParse(cleanUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF7AABFF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF7AABFF),
                ),
              ),
            )
          else
            SelectableText(
              value,
              style: const TextStyle(
                color: Color(0xFFE0E0E0),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUploaderRow(BuildContext context, String uploader) {
    if (uploader.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UPLOADER',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  uploader,
                  style: const TextStyle(
                    color: Color(0xFFE0E0E0),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push(
                  Uri(path: '/author', queryParameters: {'name': uploader})
                      .toString(),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7AABFF),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.person_search_rounded, size: 15),
                label: const Text('Portfolio',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPropertyRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: const TextStyle(
              color: Color(0xFFE0E0E0),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deep-links into the map's browse mode around this file's coordinates.
/// Named for what geosearch actually returns — every media kind in the
/// File: namespace within range (see SearchService.geosearch's
/// ggsnamespace:'6' with no filetype: clause), not just images — so the
/// label doesn't overpromise "photos" when a document or video could
/// legitimately show up in the results too.
class _NearbyMediaButton extends StatelessWidget {
  final SearchItem item;
  const _NearbyMediaButton({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          AnalyticsService.nearbyMediaFromAssetOpened(item.title);
          context.push(
            Uri(path: '/map', queryParameters: {
              'lat': item.resolvedLatitude!.toStringAsFixed(6),
              'lng': item.resolvedLongitude!.toStringAsFixed(6),
              'radiusKm': '10',
            }).toString(),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF7AABFF),
          side: const BorderSide(color: Color(0xFF2A2A2A)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.travel_explore, size: 16),
        label: const Text('Search All Media Near This File',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Collapsed-by-default Structured Data on Commons read-back — captions
/// plus every claim (creator, institution, depicts, coordinates of
/// depicted place, and anything else editors have added), lazily fetched
/// via [structuredDataProvider] the same on-expand-only way as
/// [_GlobalUsageSection]. This is what actually backs "depicts" in the
/// panel — SearchItem itself never carries depicts, since that's an SDC
/// statement, not an extmetadata field.
class _StructuredDataSection extends ConsumerStatefulWidget {
  final String fileTitle;
  const _StructuredDataSection({required this.fileTitle});

  @override
  ConsumerState<_StructuredDataSection> createState() =>
      _StructuredDataSectionState();
}

class _StructuredDataSectionState
    extends ConsumerState<_StructuredDataSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              if (!_expanded) AnalyticsService.sectionExpanded('structured_data');
              setState(() => _expanded = !_expanded);
            },
            child: Row(
              children: [
                const Text(
                  'STRUCTURED DATA (WIKIDATA)',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: const Color(0xFF5C5C5C),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Consumer(builder: (context, ref, _) {
              final sdcAsync =
                  ref.watch(structuredDataProvider(widget.fileTitle));

              return sdcAsync.when(
                loading: () => const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                ),
                error: (_, __) => const Text(
                  'Could not load structured data.',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                ),
                data: (result) {
                  if (result == null || result.statements.isEmpty) {
                    return const Text(
                      'No structured data statements on this file.',
                      style: TextStyle(
                          color: Color(0xFF888888), fontSize: 13, height: 1.5),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.statements.map((s) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: '${s.propertyLabel}: ',
                                style: const TextStyle(
                                  color: Color(0xFF9A9A9A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              TextSpan(
                                text: s.valueDisplay,
                                style: const TextStyle(
                                  color: Color(0xFFE0E0E0),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Collapsed-by-default "find more like this" strip, backed by
/// [morelikeProvider] — CirrusSearch's own `morelike:` similarity engine,
/// the same mechanism the advanced filters drawer exposes as a manual
/// search input, run here as a one-off query against just this file.
/// Fetch only fires on first expand, same contract as every other lazy
/// section in this panel.
class _RelatedMediaSection extends ConsumerStatefulWidget {
  final String fileTitle;
  const _RelatedMediaSection({required this.fileTitle});

  @override
  ConsumerState<_RelatedMediaSection> createState() =>
      _RelatedMediaSectionState();
}

class _RelatedMediaSectionState extends ConsumerState<_RelatedMediaSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              if (!_expanded) AnalyticsService.sectionExpanded('related_media');
              setState(() => _expanded = !_expanded);
            },
            child: Row(
              children: [
                const Text(
                  'RELATED MEDIA',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: const Color(0xFF5C5C5C),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            Consumer(builder: (context, ref, _) {
              final relatedAsync =
                  ref.watch(morelikeProvider(widget.fileTitle));

              return relatedAsync.when(
                loading: () => const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                ),
                error: (_, __) => const Text(
                  'Could not load related media.',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Text(
                      'No related media found.',
                      style: TextStyle(
                          color: Color(0xFF888888), fontSize: 13, height: 1.5),
                    );
                  }
                  return SizedBox(
                    height: 96,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final related = items[i];
                        return Tooltip(
                          message: related.title,
                          child: GestureDetector(
                            onTap: () {
                              AnalyticsService.relatedMediaClicked(
                                fromTitle: widget.fileTitle,
                                toTitle: related.title,
                              );
                              context.push(
                                Uri(
                                        path: '/view',
                                        queryParameters: {'id': related.title})
                                    .toString(),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 96,
                                height: 96,
                                color: const Color(0xFF1A1A1A),
                                child: related.thumb.isNotEmpty
                                    ? Image.network(
                                        related.thumb,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.image,
                                                size: 24,
                                                color: Colors.white24),
                                      )
                                    : const Icon(Icons.image,
                                        size: 24, color: Colors.white24),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}

/// Collapsed-by-default section showing every Wikimedia page (any
/// language, any project) currently embedding this file — see
/// [CommonsBackend.globalUsage] / [globalUsageProvider]. The fetch only
/// fires the first time this is expanded (Riverpod's FutureProvider only
/// runs once something actually watches it), so browsing a results grid
/// or scrolling through the asset viewer never costs an extra request per
/// file — only opening this section does, and only once per file per
/// session.
class _GlobalUsageSection extends ConsumerStatefulWidget {
  final String fileTitle;
  const _GlobalUsageSection({required this.fileTitle});

  @override
  ConsumerState<_GlobalUsageSection> createState() =>
      _GlobalUsageSectionState();
}

class _GlobalUsageSectionState extends ConsumerState<_GlobalUsageSection> {
  bool _expanded = false;

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () {
              if (!_expanded) AnalyticsService.sectionExpanded('global_usage');
              setState(() => _expanded = !_expanded);
            },
            child: Row(
              children: [
                const Text(
                  'GLOBAL USAGE',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 16,
                  color: const Color(0xFF5C5C5C),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 14),
            Consumer(builder: (context, ref, _) {
              final usageAsync =
                  ref.watch(globalUsageProvider(widget.fileTitle));

              return usageAsync.when(
                loading: () => const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                ),
                error: (_, __) => const Text(
                  'Could not load usage data.',
                  style: TextStyle(color: Color(0xFF666666), fontSize: 13),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    // An explicit empty state, not a hidden section — for
                    // a dataset curator, "not used anywhere else" is
                    // itself a meaningful quality signal, not a null
                    // result worth suppressing.
                    return const Text(
                      'Not currently used on any Wikimedia project.',
                      style: TextStyle(
                          color: Color(0xFF888888), fontSize: 13, height: 1.5),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: entries.map((entry) {
                      final hasUrl = (entry.url ?? '').trim().isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: hasUrl ? () => _launch(entry.url!) : null,
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: '${entry.wiki}  ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                TextSpan(
                                  text: entry.title,
                                  style: TextStyle(
                                    color: hasUrl
                                        ? const Color(0xFF7AABFF)
                                        : const Color(0xFFB0B0B0),
                                    fontSize: 13,
                                    decoration: hasUrl
                                        ? TextDecoration.underline
                                        : null,
                                    decorationColor: const Color(0xFF7AABFF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _DownloadSection extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onLaunchCommons;

  const _DownloadSection({
    required this.item,
    required this.onLaunchCommons,
  });

  Future<void> _handleDownload(BuildContext context, String url) async {
    AnalyticsService.mediaDownloaded(
      title: item.title,
      size: url == item.url
          ? 'original'
          : url.contains('/640px-')
              ? 'small'
              : url.contains('/1280px-')
                  ? 'medium'
                  : url.contains('/1920px-')
                      ? 'large'
                      : 'original',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloading media...'),
        duration: Duration(seconds: 2),
      ),
    );

    await DownloadService.downloadSingleFile(url, item.title, item.extension);
  }

  String _getResizedUrl(int width) {
    if (item.thumb.isEmpty) return item.url;
    final regExp = RegExp(r'\/(\d+)px-([^/]+)$');
    if (regExp.hasMatch(item.thumb)) {
      return item.thumb.replaceAllMapped(
        regExp,
        (m) => '/${width}px-${m.group(2)}',
      );
    }
    return item.url;
  }

  @override
  Widget build(BuildContext context) {
    final isScalable =
        item.mediaKind == MediaKind.image || item.mediaKind == MediaKind.vector;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _handleDownload(context, item.url),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3D7EFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
          icon: const Icon(Icons.download, size: 18),
          label: const Text(
            'Download Original',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        if (isScalable) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SizeButton(
                  label: 'SMALL',
                  onTap: () => _handleDownload(context, _getResizedUrl(640)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'MEDIUM',
                  onTap: () => _handleDownload(context, _getResizedUrl(1280)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SizeButton(
                  label: 'LARGE',
                  onTap: () => _handleDownload(context, _getResizedUrl(1920)),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            AnalyticsService.sourcePageOpened(item.title);
            onLaunchCommons();
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFAAAAAA),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text(
            'View Source Page',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _SizeButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SizeButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: const Color(0xFFCCCCCC),
        padding: const EdgeInsets.symmetric(vertical: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _NavigationButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavigationButton({
    required this.icon,
    required this.onTap,
  });

  @override
  State<_NavigationButton> createState() => _NavigationButtonState();
}

class _NavigationButtonState extends State<_NavigationButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isHovered
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.transparent,
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHovered ? Colors.white : const Color(0xFFCCCCCC),
            size: 20,
          ),
        ),
      ),
    );
  }
}