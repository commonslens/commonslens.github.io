// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:commonslens/advanced_filters_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'search_components.dart';
import 'search_map_view.dart';
import 'bulk_download_tray.dart';
import 'media_queue.dart';
import 'legal_pages.dart';

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final double width;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.width,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.width,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF161616) : const Color(0xFF101010),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered
                ? const Color(0xFF3D7EFF).withValues(alpha: 0.5)
                : const Color(0xFF1E1E1E),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(widget.description,
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({
    super.key,
    this.queryParameters = const {},
  });

  /// The URL state supplied by the router. Keeping it as an explicit widget
  /// input guarantees [didUpdateWidget] runs when only the query string
  /// changes, even though the route path remains `/`.
  final Map<String, String> queryParameters;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchExample {
  final String category;
  final String label;
  final String tooltip;
  final IconData icon;
  final SearchState state;

  const _SearchExample({
    required this.category,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.state,
  });
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final ScrollController _scrollController = ScrollController();
  late final Widget _desktopFiltersPanel;

  bool _showQueryPreview = false;
  bool? _isFiltersExpanded;
  bool _showMap = false;
  bool _mapHasOpened = false;

  // Tracks the query params this page has already "consumed" — either by
  // hydrating from them, or by being the one that pushed them via the
  // ref.listen below. `null` means nothing has been synced yet (only true
  // on very first build).
  //
  // Previously this was a one-shot `_urlHydrated` bool: hydrate once on
  // first didChangeDependencies, then never again. That broke external
  // navigation back onto '/' with new params (e.g. "Open in main search"
  // from the map page, or a browser back/forward): GoRouter reuses this
  // same State instance when only the query string changes (the path '/'
  // didn't change), so `initState`/the old one-shot guard never re-ran —
  // the URL updated but the page kept showing whatever it last searched.
  // Comparing against the last-synced params instead means an externally
  // changed URL is correctly detected and re-hydrated, while our own
  // internally-generated URL echoes (from the ref.listen below) are
  // correctly recognized as "already in sync" and skipped — no infinite
  // loop, no redundant re-fetch on every internal filter change.
  Map<String, String>? _lastSyncedParams;

  static const _examples = <_SearchExample>[
    _SearchExample(
      category: 'AUDIO',
      label: 'Mozart',
      tooltip: 'Hear Commons audio results for Mozart',
      icon: Icons.graphic_eq_rounded,
      state: SearchState(
        queryText: 'Mozart',
        tab: MediaTabType.audio,
      ),
    ),
    _SearchExample(
      category: 'VIDEO',
      label: 'Apollo 11',
      tooltip: 'Watch Commons video results for Apollo 11',
      icon: Icons.video_library_outlined,
      state: SearchState(
        queryText: 'Apollo 11',
        tab: MediaTabType.video,
      ),
    ),
    _SearchExample(
      category: 'LOCATION',
      label: 'Near Eiffel Tower',
      tooltip: 'Find media geotagged within 500 m of the Eiffel Tower',
      icon: Icons.location_on_outlined,
      state: SearchState(
        nearCoord: NearCoordFilter(
          lat: 48.8583701,
          lng: 2.2944813,
          radiusKm: 0.5,
        ),
      ),
    ),
    _SearchExample(
      category: 'SVG',
      label: 'DNA helix',
      tooltip: 'Find SVG vector graphics of a DNA helix',
      icon: Icons.polyline_outlined,
      state: SearchState(
        queryText: 'DNA helix',
        tab: MediaTabType.vectors,
        formats: {FileFormat.svg},
      ),
    ),
    _SearchExample(
      category: 'DOCUMENTS',
      label: 'Pride and Prejudice',
      tooltip: 'Find PDF and DjVu editions of Pride and Prejudice',
      icon: Icons.menu_book_outlined,
      state: SearchState(
        queryText: 'Pride and Prejudice',
        tab: MediaTabType.documents,
        formats: {FileFormat.pdf, FileFormat.djvu},
      ),
    ),
    _SearchExample(
      category: 'GLAM',
      label: 'The Met collection',
      tooltip: 'Explore media contributed by The Metropolitan Museum of Art',
      icon: Icons.museum_outlined,
      state: SearchState(
        tab: MediaTabType.images,
        templates: {'Institution:Metropolitan Museum of Art'},
      ),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _showMap = widget.queryParameters['view'] == 'map';
    _mapHasOpened = _showMap;
    // Keep this exact widget instance across search/pagination rebuilds.
    // FilterPanelContent listens to filter-state changes itself, so making
    // its large widget tree rebuild for result loading changes only adds
    // work (and was particularly visible as scroll jank on Flutter web).
    _desktopFiltersPanel = FilterPanelContent(
      docked: true,
      onLocationSelected: _openMapFromLocation,
    );
    _scrollController.addListener(_onScroll);
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20;
    _consumeUrlParams(widget.queryParameters);
  }

  bool _sameParams(Map<String, String> a, Map<String, String>? b) {
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _consumeUrlParams(Map<String, String> incoming) {
    final params = Map<String, String>.from(incoming);
    if (_sameParams(params, _lastSyncedParams)) return;
    _lastSyncedParams = params;
    final requestedMap = params['view'] == 'map';
    if (_showMap != requestedMap) {
      if (mounted) {
        setState(() {
          _showMap = requestedMap;
          _mapHasOpened = _mapHasOpened || requestedMap;
        });
      } else {
        _showMap = requestedMap;
        _mapHasOpened = _mapHasOpened || requestedMap;
      }
    }
    final searchParams = Map<String, String>.from(params)..remove('view');
    final currentSearchParams = SearchUrlCodec.toQueryParams(
      ref.read(searchControllerProvider).filterState,
    );
    // Back/Forward between grid and map changes presentation only. If the
    // actual search parameters still match the live controller, do not rerun
    // the network query just because `view=map` appeared or disappeared.
    if (_sameParams(searchParams, currentSearchParams)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Back/Forward can move again before this frame runs. Only the newest
      // URL is allowed to hydrate the controller.
      if (!_sameParams(params, widget.queryParameters)) return;
      ref.read(searchControllerProvider.notifier).hydrateFromUrl(searchParams);
    });
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameParams(widget.queryParameters, oldWidget.queryParameters)) {
      _consumeUrlParams(widget.queryParameters);
    }
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      ref
          .read(searchControllerProvider.notifier)
          .saveScrollOffset(_scrollController.position.pixels);
    }
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels >= pos.maxScrollExtent - 500) {
      final session = ref.read(searchControllerProvider).activeSession;
      if (!session.loading && session.hasMore && !session.loadingMore) {
        ref.read(searchControllerProvider.notifier).loadMore();
      }
    }
  }

  void _search(String query) =>
      ref.read(searchControllerProvider.notifier).search(query);

  Map<String, String> _urlParamsFor(SearchState state) {
    final params = SearchUrlCodec.toQueryParams(state);
    if (_showMap) params['view'] = 'map';
    return params;
  }

  void _replaceSearchUrl() {
    final params = _urlParamsFor(
      ref.read(searchControllerProvider).filterState,
    );
    _lastSyncedParams = Map<String, String>.from(params);
    final nextUrl = Uri(
      path: '/',
      queryParameters: params.isEmpty ? null : params,
    ).toString();
    if (GoRouterState.of(context).uri.toString() != nextUrl) {
      context.replace(nextUrl);
    }
  }

  void _setMapVisible(bool visible) {
    if (_showMap == visible) return;
    setState(() {
      _showMap = visible;
      _mapHasOpened = _mapHasOpened || visible;
    });
    _replaceSearchUrl();
  }

  void _openMapFromLocation() => _setMapVisible(true);

  void _searchLocation(double lat, double lng, double radiusKm) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate(
          (current) => current.copyWith(
            nearCoord: NearCoordFilter(
              lat: lat,
              lng: lng,
              radiusKm: radiusKm,
            ),
            clearNearTitle: true,
          ),
        );
  }

  void _clearLocation() {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate(
          (current) => current.copyWith(
            clearNearCoord: true,
            clearNearTitle: true,
          ),
        );
  }

  void _runExample(_SearchExample example) => ref
      .read(searchControllerProvider.notifier)
      .search(example.state.queryText, overrideState: example.state);

  void _selectTab(MediaTabType tab) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((current) {
      final config = configForTab(tab);
      final nextFormats = current.formats
          .where((f) => config.allowedFormats.contains(f))
          .toSet();
      return current.copyWith(tab: tab, formats: nextFormats);
    });
  }

  void _toggleFormat(FileFormat format) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((current) {
      final next = Set<FileFormat>.from(current.formats);
      if (next.contains(format))
        next.remove(format);
      else
        next.add(format);
      return current.copyWith(formats: next);
    });
  }

  void _changeSortMode(SortMode mode) {
    ref
        .read(searchControllerProvider.notifier)
        .applyFilterUpdate((current) => current.copyWith(sortMode: mode));
  }

  void _removeChip(QueryChipData chip) {
    final current = ref.read(searchControllerProvider).filterState;
    SearchState next = current;

    if (chip.id.startsWith('format:')) {
      final formatName = chip.id.split(':').last;
      next = current.copyWith(
          formats: Set<FileFormat>.from(current.formats)
            ..removeWhere((f) => f.name == formatName));
    } else if (chip.id.startsWith('category:')) {
      final categoryName = chip.id.substring('category:'.length);
      next = current.copyWith(
          categories: Set<String>.from(current.categories)
            ..remove(categoryName));
    } else if (chip.id.startsWith('excludeCategory:')) {
      final categoryName = chip.id.substring('excludeCategory:'.length);
      next = current.copyWith(
          excludeCategories: Set<String>.from(current.excludeCategories)
            ..remove(categoryName));
    } else if (chip.id == 'titleOnly') {
      next = current.copyWith(titleOnly: false);
    } else if (chip.id == 'language') {
      next = current.copyWith(clearLanguageCode: true);
    } else if (chip.id == 'contentModel') {
      next = current.copyWith(clearContentModel: true);
    } else if (chip.id == 'localOnly') {
      next = current.copyWith(localOnly: false);
    } else if (chip.id == 'createdFrom' || chip.id == 'createdTo') {
      next = current.copyWith(clearCreatedDate: true);
    } else if (chip.id == 'editedFrom' || chip.id == 'editedTo') {
      next = current.copyWith(clearEditedDate: true);
    } else if (chip.id == 'originalFrom' || chip.id == 'originalTo') {
      next = current.copyWith(clearOriginalDate: true);
    } else if (chip.id.startsWith('depicts:')) {
      final qid = chip.id.substring('depicts:'.length);
      next = current.copyWith(
          depictsInclude: Set<DepictsEntity>.from(current.depictsInclude)
            ..removeWhere((d) => d.qid == qid));
    } else if (chip.id.startsWith('excludeDepicts:')) {
      final qid = chip.id.substring('excludeDepicts:'.length);
      next = current.copyWith(
          depictsExclude: Set<DepictsEntity>.from(current.depictsExclude)
            ..removeWhere((d) => d.qid == qid));
    } else if (chip.id.startsWith('license:')) {
      final name = chip.id.substring('license:'.length);
      next = current.copyWith(
          licensePresets: Set<LicensePreset>.from(current.licensePresets)
            ..removeWhere((l) => l.name == name));
    } else if (chip.id == 'attributionRequired') {
      next = current.copyWith(clearAttributionRequired: true);
    } else if (chip.id.startsWith('quality:')) {
      final qualityName = chip.id.substring('quality:'.length);
      next = current.copyWith(
          qualityFilters:
              Set<QualityFilter>.from(current.selectedQualityFilters)
                ..removeWhere((quality) => quality.name == qualityName));
    } else if (chip.id == 'quality') {
      next = current.copyWith(qualityFilter: QualityFilter.any);
    } else if (chip.id == 'minWidth') {
      next = current.copyWith(clearMinWidth: true);
    } else if (chip.id == 'minHeight') {
      next = current.copyWith(clearMinHeight: true);
    } else if (chip.id == 'maxWidth') {
      next = current.copyWith(clearMaxWidth: true);
    } else if (chip.id == 'maxHeight') {
      next = current.copyWith(clearMaxHeight: true);
    } else if (chip.id == 'minFileSize') {
      next = current.copyWith(clearMinFileSizeBytes: true);
    } else if (chip.id == 'maxFileSize') {
      next = current.copyWith(clearMaxFileSizeBytes: true);
    } else if (chip.id == 'colorDepth') {
      next = current.copyWith(clearColorDepthBits: true);
    } else if (chip.id.startsWith('template:')) {
      final templateName = chip.id.substring('template:'.length);
      next = current.copyWith(
          templates: Set<String>.from(current.templates)..remove(templateName));
    } else if (chip.id.startsWith('excludeTemplate:')) {
      final templateName = chip.id.substring('excludeTemplate:'.length);
      next = current.copyWith(
          excludeTemplates: Set<String>.from(current.excludeTemplates)
            ..remove(templateName));
    } else if (chip.id == 'nearCoord') {
      next = current.copyWith(clearNearCoord: true);
    } else if (chip.id == 'nearTitle') {
      next = current.copyWith(clearNearTitle: true);
    } else if (chip.id.startsWith('excludeStatement:')) {
      final parts = chip.id.substring('excludeStatement:'.length).split(':');
      if (parts.length == 2) {
        next = current.copyWith(
            statementsExclude:
                Set<WikidataStatement>.from(current.statementsExclude)
                  ..removeWhere((s) =>
                      s.property.qid == parts[0] && s.value.qid == parts[1]));
      }
    } else if (chip.id.startsWith('statement:')) {
      final parts = chip.id.substring('statement:'.length).split(':');
      if (parts.length == 2) {
        next = current.copyWith(
            statementsInclude:
                Set<WikidataStatement>.from(current.statementsInclude)
                  ..removeWhere((s) =>
                      s.property.qid == parts[0] && s.value.qid == parts[1]));
      }
    } else if (chip.id.startsWith('exclude:')) {
      final excludeName = chip.id.substring('exclude:'.length);
      next = current.copyWith(
          excludeTerms: Set<String>.from(current.excludeTerms)
            ..remove(excludeName));
    }

    ref
        .read(searchControllerProvider.notifier)
        .search(next.queryText, overrideState: next);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      searchControllerProvider.select((state) => state.filterState),
      (previous, next) {
        if (previous == next) return;
        final currentUri = GoRouterState.of(context).uri;
        if (currentUri.path != '/') return;
        final params = _urlParamsFor(next);
        // Mark these params as already synced *before* pushing the URL, so
        // the didChangeDependencies this triggers recognizes it as our own
        // echo (not an external change) and doesn't re-hydrate — see the
        // comment on _lastSyncedParams.
        _lastSyncedParams = Map<String, String>.from(params);
        final newUrl =
            Uri(path: '/', queryParameters: params.isEmpty ? null : params)
                .toString();
        if (currentUri.toString() != newUrl) context.replace(newUrl);
      },
    );

    final viewState = ref.watch(searchControllerProvider);
    final session = viewState.activeSession;
    final filterState = viewState.filterState;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    _isFiltersExpanded ??= !isMobile;

    // Filters stop being a thing you "open" once every pick applies
    // instantly (see FilterPanelContent) — at that point a modal Drawer
    // that covers the results you're trying to react to is actively in
    // the way. Above this breakpoint the filter panel docks permanently
    // alongside results and the integrated map; below it, screen space
    // doesn't allow a permanent dock, so it stays a Drawer, just no longer
    // hardcoded to an overflow-prone 600px.
    final isDesktop = screenWidth >= 900;
    final showSearchChrome = session.hasSearched || _showMap;

    final gridOrLanding = session.hasSearched
        ? _buildResults(session, filterState)
        : _showMap
            ? const SizedBox.shrink()
            : _buildLanding(
                filterState: filterState,
                isDesktop: isDesktop,
              );

    final resultSurface = IndexedStack(
      index: _showMap ? 1 : 0,
      sizing: StackFit.expand,
      children: [
        gridOrLanding,
        _mapHasOpened
            ? SearchMapView(
                session: session,
                filterState: filterState,
                onSearchLocation: _searchLocation,
                onClearLocation: _clearLocation,
                onLoadMore: () =>
                    ref.read(searchControllerProvider.notifier).loadMore(),
                onShowResults: () => _setMapVisible(false),
              )
            : const SizedBox.shrink(),
      ],
    );

    final mainColumn = Column(
      children: [
        AnimatedSwitcher(
          // Keep the top search bar and every filetype-filter row in one
          // animated block. When a search is cleared this lets the whole
          // block move down and shrink together instead of collapsing in
          // separate stages.
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return ClipRect(
              child: SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
            );
          },
          child: showSearchChrome
              ? Column(
                  key: const ValueKey('active-search-header'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: 0.8, end: 1.0),
                      builder: (context, widthFactor, child) {
                        return FractionallySizedBox(
                          widthFactor: widthFactor,
                          child: child,
                        );
                      },
                      child: SearchTopBar(
                        key: const ValueKey('top-search-bar'),
                        initialQuery: filterState.queryText,
                        onSearch: _search,
                        showFiltersButton: !isDesktop,
                      ),
                    ),
                    _buildHeaderBar(session, filterState),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _isFiltersExpanded!
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTabBar(filterState),
                                _buildFormatChips(filterState),
                                _buildActiveChipsBar(viewState.lastBuiltQuery),
                                _buildQueryPreviewBar(viewState.lastBuiltQuery,
                                    session.hasSearched),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                )
              : const SizedBox(
                  key: ValueKey('empty-search-header'),
                ),
        ),
        Expanded(child: resultSurface),
        BulkDownloadTray(availableItems: session.items),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      drawer: isDesktop
          ? null
          : AdvancedFiltersDrawer(onLocationSelected: _openMapFromLocation),
      body: isDesktop
          ? Row(
              children: [
                _desktopFiltersPanel,
                Expanded(child: mainColumn),
              ],
            )
          : mainColumn,
    );
  }

  /// The search control has two homes: the normal top bar once a search is
  /// active, and a hero/search prompt above the ETL button while the landing
  /// page is idle. Keeping the two slots animated makes the transition feel
  /// intentional while preserving the top-bar layout for result browsing.
  Widget _buildSearchSlot({
    required bool visible,
    required bool centered,
    required SearchState filterState,
    required bool isDesktop,
  }) {
    final emptyKey = ValueKey<String>(
        centered ? 'landing-search-empty' : 'top-search-empty');
    final searchKey =
        ValueKey<String>(centered ? 'landing-search-bar' : 'top-search-bar');

    final searchBar = centered
        ? FractionallySizedBox(
            key: searchKey,
            widthFactor: 0.8,
            child: SearchTopBar(
              initialQuery: filterState.queryText,
              onSearch: _search,
              autofocus: true,
              showFiltersButton: !isDesktop,
            ),
          )
        : SearchTopBar(
            key: searchKey,
            initialQuery: filterState.queryText,
            onSearch: _search,
            showFiltersButton: !isDesktop,
          );

    final slot = AnimatedSize(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final begin =
              centered ? const Offset(0, -0.08) : const Offset(0, 0.08);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: begin, end: Offset.zero)
                  .animate(animation),
              child: child,
            ),
          );
        },
        child: visible ? searchBar : SizedBox.shrink(key: emptyKey),
      ),
    );

    if (!centered) return slot;

    // The landing slot is mounted when returning from results, so give it a
    // small upward-to-center entrance of its own. This visually connects to
    // the active header's downward motion above it.
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, progress, child) {
        return Transform.translate(
          offset: Offset(0, -24 * (1 - progress)),
          child: child,
        );
      },
      child: slot,
    );
  }

  Widget _buildLanding({
    required SearchState filterState,
    required bool isDesktop,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. The Beautiful Background Image
        Image.network(
          // The original is 5059x3373 / 9.45 MB and decodes to roughly
          // 65 MB in the browser. This official Wikimedia derivative is
          // ample for the darkened hero while avoiding that startup hit.
          'https://upload.wikimedia.org/wikipedia/commons/thumb/8/86/Lofoten%2C_Norway_%28Unsplash%29.jpg/1280px-Lofoten%2C_Norway_%28Unsplash%29.jpg',
          fit: BoxFit.cover,
          // Keep this brief: a multi-second, full-screen opacity animation is
          // costly when CanvasKit has to use Chrome's software renderer.
          filterQuality: FilterQuality.low,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              child: child,
            );
          },
        ),

        // 2. Dark Gradient Overlay (Fades from translucent top to solid dark bottom)
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                const Color(0xFF0B0B0B).withValues(alpha: 0.55),
                const Color(0xFF0B0B0B).withValues(alpha: 0.80),
                const Color(0xFF0B0B0B),
              ],
            ),
          ),
        ),

        // 3. The Scrollable Content
        LayoutBuilder(
          builder: (context, constraints) {
            const contentPadding = EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 36,
            );
            final contentMinHeight =
                constraints.maxHeight > contentPadding.vertical
                    ? constraints.maxHeight - contentPadding.vertical
                    : 0.0;

            return SingleChildScrollView(
              padding: contentPadding,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: contentMinHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      const WikiLogo(),
                      const SizedBox(height: 32),

                      // Hero Copy
                      const Text('COMMONSLENS',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                              letterSpacing: 5,
                              height: 1.1)),
                      const SizedBox(height: 16),
                      const Text(
                          'Navigate, filter, and extract media from Wikimedia Commons intuitively and effortlessly.\nOpen source and free to use.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Color(0xFFCCCCCC),
                              fontSize: 18,
                              height: 1.6,
                              fontWeight: FontWeight.w400)),

                      const SizedBox(height: 32),

                      _buildSearchSlot(
                        visible: true,
                        centered: true,
                        filterState: filterState,
                        isDesktop: isDesktop,
                      ),

                      const SizedBox(height: 14),

                      // Search Examples
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        alignment: WrapAlignment.center,
                        children: _examples
                            .map((example) => ExampleChip(
                                  category: example.category,
                                  label: example.label,
                                  tooltip: example.tooltip,
                                  icon: example.icon,
                                  onTap: () => _runExample(example),
                                ))
                            .toList(),
                      ),

                      const SizedBox(height: 14),

                      TextButton.icon(
                        onPressed: () => context.push('/features'),
                        icon: const Icon(Icons.auto_awesome_mosaic_outlined,
                            size: 17),
                        label: const Text('Explore every CommonsLens feature'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF9AB9FF),
                        ),
                      ),

                      const Spacer(),
                      const Text(
                        'CommonsLens is an independent, non-commercial research interface.\nMedia and data are sourced directly from Wikimedia Commons.\nCommonsLens does not make, host, own, license, or claim copyright over displayed content.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: const SiteFooter(
                          showDivider: false,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildResults(SearchSession session, SearchState filterState) {
    if (session.loading)
      return const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: Color(0xFF3D7EFF))));
    if (session.error != null)
      return Center(
          child: Text(session.error!,
              style: const TextStyle(color: Color(0xFFFF9B91), fontSize: 14)));
    if (session.items.isEmpty)
      return Center(
          child: Text(configForTab(filterState.tab).emptyMessage,
              style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 14)));

    return MediaResultsGrid(
      controller: _scrollController,
      items: session.items,
      loadingMore: session.loadingMore,
      queueSource:
          ref.read(searchControllerProvider).externalQueueNodeId == null
              ? MediaQueueSource.search(filterState)
              : MediaQueueSource.pipeline(
                  ref.read(searchControllerProvider).externalQueueNodeId!,
                  returnUrl: '/',
                ),
      queueHasMore: session.hasMore,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
    );
  }

  /// Single combined header row: the FileType-filters expand/collapse
  /// toggle on the left, plus (once a search has actually run) the results
  /// count and sort menu on the right — replacing what used to be two
  /// separate stacked rows. The toggle only wraps its own text+icon in an
  /// InkWell rather than the full row, so tapping the sort menu on the
  /// right doesn't also fire the expand/collapse toggle underneath it.
  Widget _buildHeaderBar(SearchSession session, SearchState filterState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () =>
                setState(() => _isFiltersExpanded = !_isFiltersExpanded!),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isFiltersExpanded!
                        ? "Hide FileType Filters"
                        : "Show Filetype Filters",
                    style: const TextStyle(
                        color: Color(0xFF3D7EFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isFiltersExpanded!
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: const Color(0xFF3D7EFF),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (session.hasSearched) ...[
            Text('${session.items.length} RESULTS${session.hasMore ? '+' : ''}',
                style: const TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 14),
            _buildSortMenu(filterState.sortMode),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar(SearchState filterState) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0F0F0F),
          border: Border(bottom: BorderSide(color: Color(0xFF1A1A1A)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: mediaTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = mediaTabs[index];
          final selected = filterState.tab == tab.type;
          return Center(
            child: GestureDetector(
              onTap: () => _selectTab(tab.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3D7EFF).withValues(alpha: 0.12)
                        : const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF3D7EFF)
                            : const Color(0xFF242424))),
                child: Text(tab.label,
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFF7AABFF)
                            : const Color(0xFF6A6A6A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormatChips(SearchState filterState) {
    final formats = configForTab(filterState.tab).allowedFormats.toList()
      ..sort((a, b) => fileFormatLabel(a).compareTo(fileFormatLabel(b)));
    if (formats.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          border: Border(bottom: BorderSide(color: Color(0xFF181818)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: formats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final format = formats[index];
          final selected = filterState.formats.contains(format);
          return Center(
            child: GestureDetector(
              onTap: () => _toggleFormat(format),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF3D7EFF).withValues(alpha: 0.14)
                        : const Color(0xFF151515),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: selected
                            ? const Color(0xFF3D7EFF)
                            : const Color(0xFF242424))),
                child: Text(fileFormatLabel(format),
                    style: TextStyle(
                        color: selected
                            ? const Color(0xFF7AABFF)
                            : const Color(0xFF6A6A6A),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveChipsBar(QueryBuildResult? lastBuiltQuery) {
    final removable = (lastBuiltQuery?.chips ?? const <QueryChipData>[])
        .where((chip) => chip.id != 'scope' && chip.id != 'tab')
        .toList();
    if (removable.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
          color: Color(0xFF0B0B0B),
          border: Border(bottom: BorderSide(color: Color(0xFF171717)))),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: removable.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final chip = removable[index];
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xFF151515),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF252525))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(chip.label,
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  GestureDetector(
                      onTap: () => _removeChip(chip),
                      child: const Icon(Icons.close,
                          size: 14, color: Color(0xFF666666))),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQueryPreviewBar(
      QueryBuildResult? lastBuiltQuery, bool hasSearched) {
    if (lastBuiltQuery == null || !hasSearched) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
          color: Color(0xFF0A0A0A),
          border: Border(bottom: BorderSide(color: Color(0xFF151515)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _showQueryPreview = !_showQueryPreview),
            child: Row(
              children: [
                const Text('QUERY PREVIEW',
                    style: TextStyle(
                        color: Color(0xFF4E4E4E),
                        fontSize: 10,
                        letterSpacing: 1.8,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Icon(
                    _showQueryPreview
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: const Color(0xFF5C5C5C)),
              ],
            ),
          ),
          if (_showQueryPreview) ...[
            const SizedBox(height: 8),
            SelectableText(lastBuiltQuery.debugPreview,
                style: const TextStyle(
                    color: Color(0xFF8A8A8A), fontSize: 12, height: 1.5)),
          ],
        ],
      ),
    );
  }

  Widget _buildSortMenu(SortMode currentSort) {
    return PopupMenuButton<SortMode>(
      initialValue: currentSort,
      onSelected: _changeSortMode,
      color: const Color(0xFF161616),
      itemBuilder: (context) => const [
        PopupMenuItem(value: SortMode.relevance, child: Text('Relevance')),
        PopupMenuItem(value: SortMode.titleMatch, child: Text('Title A–Z')),
        PopupMenuItem(
            value: SortMode.newestEdited, child: Text('Recently edited')),
        PopupMenuItem(
            value: SortMode.oldestEdited, child: Text('Least recently edited')),
        PopupMenuItem(
            value: SortMode.newestCreated, child: Text('Recently created')),
        PopupMenuItem(
            value: SortMode.oldestCreated, child: Text('Oldest created')),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: const Color(0xFF151515),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF262626))),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_sortLabel(currentSort),
                style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 16, color: Color(0xFF777777)),
          ],
        ),
      ),
    );
  }

  String _sortLabel(SortMode mode) {
    switch (mode) {
      case SortMode.relevance:
        return 'Relevance';
      case SortMode.titleMatch:
        return 'Title A–Z';
      case SortMode.newestEdited:
        return 'Recently edited';
      case SortMode.oldestEdited:
        return 'Least edited';
      case SortMode.newestCreated:
        return 'Recently created';
      case SortMode.oldestCreated:
        return 'Oldest created';
    }
  }
}
