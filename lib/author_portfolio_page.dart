import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'download_service.dart';
import 'search_models.dart';
import 'search_controller.dart';
import 'search_components.dart';
import 'bulk_download_tray.dart'
    show selectionModeProvider, selectedItemsProvider;
import 'analytics_service.dart';

/// Tracks one in-flight (or just-finished) bulk download — see the same
/// class in search_page.dart for the full rationale. Duplicated locally
/// rather than shared/exported since it's small and UI-local.
class _DownloadJob {
  final int id;
  int completed = 0;
  int total;
  List<String> failed = [];
  bool done = false;

  _DownloadJob({required this.id, required this.total});
}

class AuthorPortfolioPage extends ConsumerStatefulWidget {
  final String username;

  const AuthorPortfolioPage({super.key, required this.username});

  @override
  ConsumerState<AuthorPortfolioPage> createState() =>
      _AuthorPortfolioPageState();
}

class _AuthorPortfolioPageState extends ConsumerState<AuthorPortfolioPage> {
  final ScrollController _scrollController = ScrollController();
  late final TextEditingController _authorCtrl =
      TextEditingController(text: widget.username);

  final List<_DownloadJob> _downloadJobs = [];
  int _nextDownloadJobId = 0;
  bool _downloadFullRes = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    AnalyticsService.authorPortfolioViewed(widget.username);
  }

  @override
  void didUpdateWidget(covariant AuthorPortfolioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      AnalyticsService.authorPortfolioViewed(widget.username);
      _authorCtrl.text = widget.username;
      // Switching authors — a bulk selection from the previous grid
      // shouldn't silently carry over into the new one.
      ref.read(selectionModeProvider.notifier).state = false;
      ref.read(selectedItemsProvider.notifier).state = {};
    }
  }

  @override
  void dispose() {
    _authorCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitAuthorSearch() {
    final name = _authorCtrl.text.trim();
    if (name.isEmpty || name == widget.username) return;
    // authorPortfolioProvider is keyed by username, so navigating here just
    // rebuilds this same page watching a different family instance — no
    // extra state plumbing needed, GoRouter + Riverpod already do the work.
    context
        .go(Uri(path: '/author', queryParameters: {'name': name}).toString());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 500) {
      ref
          .read(authorPortfolioProvider(widget.username).notifier)
          .loadMore(widget.username);
    }
  }

  Widget _buildAuthorSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _authorCtrl,
          textInputAction: TextInputAction.search,
          autocorrect: false,
          enableSuggestions: false,
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search uploads by author username…',
            hintStyle: const TextStyle(color: Color(0xFF3A3A3A), fontSize: 14),
            filled: true,
            fillColor: const Color(0xFF181818),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    const BorderSide(color: Color(0xFF3D7EFF), width: 1)),
            prefixIcon: const Icon(Icons.person_search_rounded,
                size: 18, color: Color(0xFF3A3A3A)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded,
                  size: 18, color: Color(0xFF3D7EFF)),
              onPressed: _submitAuthorSearch,
            ),
          ),
          onSubmitted: (_) => _submitAuthorSearch(),
        ),
      ),
    );
  }

  void _startBulkDownload(List<SearchItem> items) {
    AnalyticsService.bulkDownloadStarted(items.length);
    final job = _DownloadJob(id: _nextDownloadJobId++, total: items.length);
    setState(() => _downloadJobs.add(job));

    // Capture the selection into this job, then clear it so a fresh batch
    // can be selected and downloaded immediately without hitting Cancel.
    ref.read(selectedItemsProvider.notifier).state = {};

    DownloadService.downloadBulkZip(
      items,
      zipName: '${widget.username}_portfolio.zip',
      maxWidth: _downloadFullRes ? null : 1280,
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
        cancelled: false,
      );
      if (job.failed.isEmpty) {
        Future.delayed(const Duration(seconds: 4), () {
          if (!mounted) return;
          setState(() => _downloadJobs.remove(job));
        });
      }
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
              ? const Color(0xFF3D7EFF).withValues(alpha: 0.15)
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: job.done ? 1.0 : fraction,
              minHeight: 5,
              backgroundColor: const Color(0xFF2A2A2A),
              valueColor: AlwaysStoppedAnimation(
                hasFailed ? const Color(0xFFFF6B6B) : const Color(0xFF3D7EFF),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            job.done
                ? (hasFailed
                    ? 'Done — ${job.failed.length} of ${job.total} failed'
                    : 'Done — ${job.total} files')
                : 'Downloading ${job.completed} / ${job.total}'
                    '${hasFailed ? ' — ${job.failed.length} failed' : ''}…',
            style: TextStyle(
              color:
                  hasFailed ? const Color(0xFFFF6B6B) : const Color(0xFF888888),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionBar() {
    final isSelectionMode = ref.watch(selectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);
    final portfolioItems =
        ref.watch(authorPortfolioProvider(widget.username)).items;

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
                    onPressed: portfolioItems.isEmpty
                        ? null
                        : () {
                            ref.read(selectedItemsProvider.notifier).state =
                                portfolioItems.toSet();
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authorPortfolioProvider(widget.username));

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: const Text(
          'AUTHOR PORTFOLIO',
          style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildAuthorSearchBar(),
          Expanded(child: _buildBody(session)),
          _buildBulkActionBar(),
        ],
      ),
    );
  }

  Widget _buildBody(SearchSession session) {
    if (session.loading && session.items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
              strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
        ),
      );
    }
    if (session.error != null && session.items.isEmpty) {
      return Center(
        child: Text(session.error!,
            style: const TextStyle(color: Color(0xFF484848), fontSize: 14)),
      );
    }
    if (session.items.isEmpty) {
      return Center(
        child: Text('No uploads found for "${widget.username}".',
            style: const TextStyle(color: Color(0xFF404040), fontSize: 14)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Text(
            '${session.items.length} UPLOAD${session.items.length == 1 ? '' : 'S'}'
            '${session.hasMore ? '+' : ''}',
            style: const TextStyle(
                color: Color(0xFF323232),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            cacheExtent: 150,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 280,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85),
            itemCount: session.items.length + (session.loadingMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == session.items.length) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: Color(0xFF3D7EFF)),
                  ),
                );
              }
              return RepaintBoundary(
                key: ValueKey(session.items[i].url),
                child: MediaCard(
                  item: session.items[i],
                  searchResultsNotifier: ValueNotifier(session.items),
                  onLoadMore: () => ref
                      .read(authorPortfolioProvider(widget.username).notifier)
                      .loadMore(widget.username),
                  index: i,
                  searchState: const SearchState(),
                  extraParams: {'author': widget.username},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
