// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:commonslens/advanced_filters_drawer.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'download_service.dart';
import 'search_models.dart';
import 'search_url_codec.dart';
import 'search_controller.dart';
import 'search_components.dart';
import 'analytics_service.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedItemsProvider = StateProvider<Set<SearchItem>>((ref) => {});

/// Tracks one in-flight (or just-finished) bulk download. Multiple of these
/// can exist at once — starting a new download never has to wait for a
/// prior one to finish, each just gets its own row in the progress list.
class _DownloadJob {
  final int id;
  int completed = 0;
  int total;
  List<String> failed = [];
  bool done = false;
  bool cancelled = false;
  final DownloadCancelToken cancelToken = DownloadCancelToken();

  _DownloadJob({required this.id, required this.total});
}

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
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final ScrollController _scrollController = ScrollController();

  bool _showQueryPreview = false;
  bool? _isFiltersExpanded;

  // Desktop-only: whether the docked filters sidebar (see build's
  // isDesktop branch) is minimized to a thin rail. Independent from
  // _isFiltersExpanded above, which toggles the FileType-filter row
  // beneath the top bar on every viewport — this instead hides the whole
  // 380px docked panel down to a reopen affordance, for when someone
  // wants the extra width back for results without losing their filter
  // state (unlike the mobile Drawer, collapsing never clears anything).
  bool _filtersSidebarCollapsed = false;

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

  final List<_DownloadJob> _downloadJobs = [];
  int _nextDownloadJobId = 0;
  bool _downloadFullRes = true;

  static const _examples = [
    'Apollo 11',
    'Pride and Prejudice',
    'Berlin',
    'DNA helix',
    'Charlie Chaplin',
    'Mitridate, Re di Ponto'
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    PaintingBinding.instance.imageCache.maximumSize = 80;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20;
  }

  bool _sameParams(Map<String, String> a, Map<String, String>? b) {
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final params = GoRouterState.of(context).uri.queryParameters;
    if (_sameParams(params, _lastSyncedParams)) return;
    _lastSyncedParams = Map<String, String>.from(params);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchControllerProvider.notifier).hydrateFromUrl(params);
    });
  }

  @override
  void dispose() {
    if (_scrollController.hasClients) {
      ref
          .read(searchControllerProvider.notifier)
          .saveScrollOffset(_scrollController.position.pixels);
    }
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;

    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  void _startBulkDownload(List<SearchItem> items) {
    AnalyticsService.bulkDownloadStarted(items.length);
    final job = _DownloadJob(id: _nextDownloadJobId++, total: items.length);
    setState(() => _downloadJobs.add(job));

    // Capture the current selection into this job, then clear it — so the
    // person can immediately select a fresh batch and start another
    // download without waiting on this one. This job keeps running
    // independently of whatever gets selected next.
    ref.read(selectedItemsProvider.notifier).state = {};

    DownloadService.downloadBulkZip(
      items,
      zipName: 'selected_commons_media.zip',
      maxWidth: _downloadFullRes ? null : 1280,
      cancelToken: job.cancelToken,
      onProgress: (completed, total, failedTitles) {
        if (!mounted) return;
        setState(() {
          job.completed = completed;
          job.total = total;
          job.failed = failedTitles;
        });
      },
    ).then((_) {
      if (!mounted) return;
      setState(() => job.done = true);
      AnalyticsService.bulkDownloadCompleted(
        total: job.total,
        failed: job.failed.length,
        cancelled: job.cancelled,
      );
      // Successful jobs clear themselves after a few seconds; failed and
      // cancelled ones stay visible until the person dismisses them, since
      // "silently vanished" is exactly what looked broken before — and a
      // cancelled job disappearing on its own would hide the confirmation
      // that it actually stopped.
      if (job.failed.isEmpty && !job.cancelled) {
        Future.delayed(const Duration(seconds: 4), () {
          if (!mounted) return;
          setState(() => _downloadJobs.remove(job));
        });
      }
    });
  }

  void _cancelDownload(_DownloadJob job) {
    job.cancelToken.cancel();
    setState(() => job.cancelled = true);
    // Auto-dismiss the cancelled row 5 seconds after it appears, instead
    // of leaving it sitting there greyed out forever.
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _downloadJobs.remove(job));
    });
  }

  Widget _buildResolutionButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3D7EFF).withOpacity(0.15)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF3D7EFF) : const Color(0xFF262626),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF3D7EFF) : Colors.white54,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildJobProgressRow(_DownloadJob job) {
    final fraction = job.total == 0 ? null : job.completed / job.total;
    final hasFailed = job.failed.isNotEmpty;
    final isActive = !job.done && !job.cancelled;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (job.done || job.cancelled) ? 1.0 : fraction,
                    minHeight: 5,
                    backgroundColor: const Color(0xFF2A2A2A),
                    valueColor: AlwaysStoppedAnimation(
                      job.cancelled
                          ? const Color(0xFF888888)
                          : hasFailed
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF3D7EFF),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  job.cancelled
                      ? 'Cancelled — ${job.completed} of ${job.total} downloaded'
                      : job.done
                          ? (hasFailed
                              ? 'Done — ${job.failed.length} of ${job.total} failed'
                              : 'Done — ${job.total} files')
                          : 'Downloading ${job.completed} / ${job.total}'
                              '${hasFailed ? ' — ${job.failed.length} failed' : ''}…',
                  style: TextStyle(
                    color: job.cancelled
                        ? const Color(0xFF888888)
                        : hasFailed
                            ? const Color(0xFFFF6B6B)
                            : const Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Only shown while the job is actually running — a finished,
          // failed, or already-cancelled job has nothing left to stop.
          // Deliberately a prominent labeled button (not a bare icon) so
          // it reads distinctly from the "Minimize" action in the bulk
          // action bar below.
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton.icon(
                onPressed: () => _cancelDownload(job),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B6B),
                  backgroundColor: const Color(0xFF2A1414),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.close, size: 15),
                label: const Text('Cancel download',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBulkActionBar(SearchSession session) {
    final isSelectionMode = ref.watch(selectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);

    // Keep showing download progress even if selection mode gets exited —
    // otherwise closing the selection bar would hide in-flight downloads.
    if (!isSelectionMode && _downloadJobs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131313),
        border: Border(top: BorderSide(color: Color(0xFF202020))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_downloadJobs.isNotEmpty) ...[
              ..._downloadJobs.map(_buildJobProgressRow),
              const SizedBox(height: 4),
            ],
            if (isSelectionMode) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildResolutionButton(
                      label: 'Full Resolution',
                      selected: _downloadFullRes,
                      onTap: () => setState(() => _downloadFullRes = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildResolutionButton(
                      label: 'Web-Optimized (1280px)',
                      selected: !_downloadFullRes,
                      onTap: () => setState(() => _downloadFullRes = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.read(selectionModeProvider.notifier).state = false;
                      ref.read(selectedItemsProvider.notifier).state = {};
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Minimize'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: session.items.isEmpty
                        ? null
                        : () {
                            ref.read(selectedItemsProvider.notifier).state =
                                session.items.toSet();
                          },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3D7EFF)),
                      foregroundColor: const Color(0xFF3D7EFF),
                    ),
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('Select All'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: selectedItems.isEmpty
                        ? null
                        : () => _startBulkDownload(selectedItems.toList()),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D7EFF)),
                    icon: const Icon(Icons.download,
                        size: 18, color: Colors.white),
                    label: Text(
                      'Download (${selectedItems.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _search(String query) =>
      ref.read(searchControllerProvider.notifier).search(query);

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
    // Bypasses applyFilterUpdate's diff tracking below (this calls
    // .search() directly with overrideState), so it needs its own event —
    // the chip id itself (e.g. "category:Paris", "license") is already a
    // decent coarse filter-type label once the value suffix is stripped.
    AnalyticsService.filterRemoved(chip.id.split(':').first);
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
    } else if (chip.id == 'license') {
      next = current.copyWith(licensePreset: LicensePreset.any);
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
            statementsExclude: Set<WikidataStatement>.from(current.statementsExclude)
              ..removeWhere(
                  (s) => s.property.qid == parts[0] && s.value.qid == parts[1]));
      }
    } else if (chip.id.startsWith('statement:')) {
      final parts = chip.id.substring('statement:'.length).split(':');
      if (parts.length == 2) {
        next = current.copyWith(
            statementsInclude: Set<WikidataStatement>.from(current.statementsInclude)
              ..removeWhere(
                  (s) => s.property.qid == parts[0] && s.value.qid == parts[1]));
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
        final params = SearchUrlCodec.toQueryParams(next);
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
    // alongside results, same split-screen shape map_page.dart already
    // uses for its own results pane; below it, screen space doesn't allow
    // a permanent dock, so it stays a Drawer, just no longer hardcoded to
    // an overflow-prone 600px.
    final isDesktop = screenWidth >= 900;

    final mainColumn = Column(
      children: [
        SearchTopBar(
          initialQuery: filterState.queryText,
          onSearch: _search,
          showFiltersButton: !isDesktop,
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
                    _buildQueryPreviewBar(
                        viewState.lastBuiltQuery, session.hasSearched),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
            child: session.hasSearched
                ? _buildResults(session, filterState)
                : _buildLanding()),
        if (session.hasSearched) _buildBulkActionBar(session),
      ],
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      endDrawer: isDesktop ? null : const AdvancedFiltersDrawer(),
      body: isDesktop
          ? Row(
              children: [
                Expanded(child: mainColumn),
                if (_filtersSidebarCollapsed)
                  _CollapsedFiltersRail(
                    onExpand: () =>
                        setState(() => _filtersSidebarCollapsed = false),
                  )
                else
                  Container(
                    width: 380,
                    decoration: const BoxDecoration(
                      color: Color(0xFF111111),
                      border:
                          Border(left: BorderSide(color: Color(0xFF1E1E1E))),
                    ),
                    child: FilterPanelContent(
                      onCollapse: () =>
                          setState(() => _filtersSidebarCollapsed = true),
                    ),
                  ),
              ],
            )
          : mainColumn,
    );
  }

  Widget _buildLanding() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. The Beautiful Background Image
        Image.network(
          'https://upload.wikimedia.org/wikipedia/commons/4/4d/Night_landscape_northern_lights_scenic_aurora_borealis.jpg',
          fit: BoxFit.cover,
          // Fade in the background smoothly
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(seconds: 3),
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
                const Color(0xFF0B0B0B).withValues(alpha: 0.65),
                const Color(0xFF0B0B0B).withValues(alpha: 0.85),
                const Color(0xFF0B0B0B),
              ],
            ),
          ),
        ),

        // 3. The Scrollable Content
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.95),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const WikiLogo(),
                  const SizedBox(height: 32),

                  // Hero Copy
                  const Text('CommonsLens',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -1.0,
                          height: 1.1)),
                  const SizedBox(height: 16),
                  const Text(
                      'A place to explore the world\'s largest free media archive: Wikimedia Commons\nStart your search using the textbox and filters above! No sign-up or payment needed; this tool is open-source and free forever.\nEngineered for explorers and researchers to navigate, filter, and extract media intuitively and effortlessly.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color(0xFFCCCCCC),
                          fontSize: 18,
                          height: 1.6,
                          fontWeight: FontWeight.w400)),

                  const SizedBox(height: 40),

                  // Search Examples
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: _examples
                        .map((q) =>
                            ExampleChip(label: q, onTap: () => _search(q)))
                        .toList(),
                  ),

                  const SizedBox(height: 80),

                  // Capability Index — every real, working feature in the
                  // engine, organized by function rather than a flat list.
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      final cardWidth = isMobile ? double.infinity : 270.0;

                      Widget group(String label, List<_FeatureCard> cards) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 40),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(label,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Color(0xFF3D7EFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 2.0)),
                              const SizedBox(height: 16),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 16,
                                children: cards,
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          group('SEMANTIC & METADATA SEARCH', [
                              _FeatureCard(
                                icon: Icons.travel_explore,
                                title: 'Wikidata Depicts Search',
                                description:
                                    'Search by exact visual subject via Wikidata Q-codes, with independent include and exclude sets.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.category_outlined,
                                title: 'Category Include / Exclude',
                                description:
                                    'Multi-select Commons categories: isolate or eliminate entire category trees, deep-traversal included.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.merge_type,
                                title: 'Multi-Term OR Search',
                                description:
                                    'Combine unrelated searches into one query with "+", e.g. "eiffel tower + colosseum".',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.filter_alt_outlined,
                                title: 'Filter-Only Search',
                                description:
                                    'Run a full search from filters alone: depicts, category, license, etc. No text query required.',
                                width: cardWidth,
                              ),
                            ]),
                            group('PRECISION FILTERING', [
                              _FeatureCard(
                                icon: Icons.copyright,
                                title: 'License Filtering',
                                description:
                                    'Restrict results to CC0, CC BY 4.0, CC BY-SA 4.0, or Public Domain.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.verified_outlined,
                                title: 'Quality Assessment',
                                description:
                                    'Isolate Commons-reviewed Quality Images and Valued Images.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.location_on_outlined,
                                title: 'Geolocation Search',
                                description:
                                    'Find media captured near an exact latitude and longitude, with adjustable radius.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.calendar_month_outlined,
                                title: 'Date Range Filtering',
                                description:
                                    'Filter by creation date and last-edited date, independently.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.perm_media_outlined,
                                title: 'File-Type Precision',
                                description:
                                    'Isolate exact formats: images, vectors, audio, video, documents.',
                                width: cardWidth,
                              ),
                            ]),
                            group('DISCOVERY', [
                              _FeatureCard(
                                icon: Icons.person_search_outlined,
                                title: 'Author Portfolios',
                                description:
                                    'Browse every upload from a single contributor, fully paginated.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.link,
                                title: 'Shareable Search State',
                                description:
                                    'Every query, filter combination, and asset view is a URL you can send.',
                                width: cardWidth,
                              ),
                            ]),
                            group('RESEARCH WORKFLOW', [
                              _FeatureCard(
                                icon: Icons.archive_outlined,
                                title: 'Bulk Export',
                                description:
                                    'Select any subset of results and download as one .zip, entirely in-browser.',
                                width: cardWidth,
                              ),
                              _FeatureCard(
                                icon: Icons.bolt,
                                title: 'High-Volume Rendering',
                                description:
                                    'Staggered lazy-loading handles large result sets without UI lockup.',
                                width: cardWidth,
                              ),
                            ]),
                          ],
                        );
                    },
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'CommonsLens is a non-commercial, fair-use research tool. All media and data are sourced directly from Wikimedia Commons. CommonsLens does not make, host, own, or claim copyright over any of the displayed content.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF555555),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
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
              style: const TextStyle(color: Color(0xFF484848), fontSize: 14)));
    if (session.items.isEmpty)
      return Center(
          child: Text(configForTab(filterState.tab).emptyMessage,
              style: const TextStyle(color: Color(0xFF404040), fontSize: 14)));

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      cacheExtent: 150,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 280,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.85),
      itemCount: session.items.length + (session.loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == session.items.length)
          return const Center(
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: Color(0xFF3D7EFF))));
        return RepaintBoundary(
          key: ValueKey(session.items[i].url),
          child: MediaCard(
            item: session.items[i],
            searchResultsNotifier: ValueNotifier(session.items),
            onLoadMore: () =>
                ref.read(searchControllerProvider.notifier).loadMore(),
            index: i,
            searchState: filterState,
          ),
        );
      },
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
            Text(
                '${session.items.length} RESULTS${session.hasMore ? '+' : ''}',
                style: const TextStyle(
                    color: Color(0xFF323232),
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
                        ? const Color(0xFF3D7EFF).withOpacity(0.12)
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
                        ? const Color(0xFF3D7EFF).withOpacity(0.14)
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

/// The desktop filters sidebar's minimized state — a thin 44px rail with a
/// single reopen affordance, replacing the full 380px docked
/// FilterPanelContent so the person can get results width back without
/// losing any filter state (unlike closing the mobile Drawer, which just
/// hides the same live FilterPanelContent — nothing here is torn down or
/// reset, it's purely a layout swap in SearchPage.build).
class _CollapsedFiltersRail extends StatelessWidget {
  final VoidCallback onExpand;
  const _CollapsedFiltersRail({required this.onExpand});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        border: Border(left: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Tooltip(
              message: 'Show filters',
              child: IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white54),
                onPressed: onExpand,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                onTap: onExpand,
                behavior: HitTestBehavior.opaque,
                child: const Center(
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'FILTERS',
                      style: TextStyle(
                        color: Color(0xFF555555),
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
