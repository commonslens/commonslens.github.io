import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'search_service.dart';
import 'search_controller.dart';
import 'search_models.dart';
import 'backend_providers.dart';

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Browse Directories',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF3D7EFF),
          labelColor: const Color(0xFF3D7EFF),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Categories'),
            Tab(text: 'Templates'),
            Tab(text: 'Depicts (Q-Codes)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _CategoryTab(),
          _TemplateTab(),
          _DepictsTab(),
        ],
      ),
    );
  }
}

typedef _BrowseLoader<T> = Future<BrowseResult<T>> Function({
  String? prefix,
  String? cursor,
});

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedBrowseTab<CategoryItem>(
      searchHint: 'Jump to category (e.g. "Architecture")',
      loadPage: ({String? prefix, String? cursor}) => ref
          .read(commonsBackendProvider)
          .browseCategories(prefix: prefix, cursor: cursor),
      titleFor: (item) => item.name,
      subtitleFor: (item) => '${item.size} files in this category',
      onSelect: (item) {
        ref.read(searchControllerProvider.notifier).applyFilterUpdate((state) =>
            state.copyWith(categories: {...state.categories, item.name}));
        context.go('/');
      },
    );
  }
}

class _TemplateTab extends ConsumerWidget {
  const _TemplateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _PaginatedBrowseTab<String>(
      searchHint: 'Jump to template (e.g. "PD-USGov")',
      loadPage: ({String? prefix, String? cursor}) => ref
          .read(commonsBackendProvider)
          .browseTemplates(prefix: prefix, cursor: cursor),
      titleFor: (item) => item,
      subtitleFor: (_) => 'MediaWiki Template',
      onSelect: (item) {
        ref.read(searchControllerProvider.notifier).applyFilterUpdate(
            (state) => state.copyWith(templates: {...state.templates, item}));
        context.go('/');
      },
    );
  }
}

class _PaginatedBrowseTab<T> extends StatefulWidget {
  final String searchHint;
  final _BrowseLoader<T> loadPage;
  final String Function(T item) titleFor;
  final String? Function(T item) subtitleFor;
  final ValueChanged<T> onSelect;

  const _PaginatedBrowseTab({
    required this.searchHint,
    required this.loadPage,
    required this.titleFor,
    required this.subtitleFor,
    required this.onSelect,
  });

  @override
  State<_PaginatedBrowseTab<T>> createState() => _PaginatedBrowseTabState<T>();
}

class _PaginatedBrowseTabState<T> extends State<_PaginatedBrowseTab<T>> {
  final List<T> _items = [];
  String? _cursor;
  bool _loading = false;
  String? _error;
  String _prefix = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore({bool refresh = false}) async {
    if (_loading && !refresh) return;
    final requestGeneration = refresh ? ++_generation : _generation;
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.loadPage(prefix: _prefix, cursor: _cursor);
      if (!mounted || requestGeneration != _generation) return;
      setState(() {
        _items.addAll(result.items);
        _cursor = result.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || requestGeneration != _generation) return;
      setState(() {
        _cursor = null;
        _loading = false;
        _error = 'Unable to load this directory. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(widget.searchHint),
            onSubmitted: (value) {
              _prefix = value.trim();
              _loadMore(refresh: true);
            },
          ),
        ),
        Expanded(child: _buildResults()),
      ],
    );
  }

  Widget _buildResults() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () => _loadMore(refresh: true),
          icon: const Icon(Icons.refresh),
          label: Text(_error!),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('No directory entries found.',
            style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      itemCount: _items.length + (_cursor != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          if (!_loading) Future.microtask(_loadMore);
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final item = _items[index];
        return _BrowseItemCard(
          title: widget.titleFor(item),
          subtitle: widget.subtitleFor(item),
          onTap: () => widget.onSelect(item),
        );
      },
    );
  }
}

class _DepictsTab extends ConsumerStatefulWidget {
  const _DepictsTab();
  @override
  ConsumerState<_DepictsTab> createState() => _DepictsTabState();
}

class _DepictsTabState extends ConsumerState<_DepictsTab> {
  List<DepictsEntity> _items = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _loading = true);
    final results = await ref
        .read(commonsAutocompleteProvider)
        .wikidataEntities(query, limit: 50);
    setState(() {
      _items = results;
      _loading = false;
    });
  }

  void _select(DepictsEntity entity) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate(
        (c) => c.copyWith(depictsInclude: {...c.depictsInclude, entity}));
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration('Search Wikidata items (e.g. "City")')
                .copyWith(
                    suffixIcon:
                        const Icon(Icons.search, color: Colors.white54)),
            onSubmitted: _search,
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_items.isEmpty)
          const Expanded(
              child: Center(
                  child: Text(
                      'Search for a visual subject to apply as a filter.',
                      style: TextStyle(color: Colors.white54))))
        else
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                return _BrowseItemCard(
                  title: '${item.label} (${item.qid})',
                  subtitle: item.description ?? 'No description available',
                  onTap: () => _select(item),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _BrowseItemCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _BrowseItemCard({
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  State<_BrowseItemCard> createState() => _BrowseItemCardState();
}

class _BrowseItemCardState extends State<_BrowseItemCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF191919) : const Color(0xFF131313),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  _hovered ? const Color(0xFF3D7EFF) : const Color(0xFF202020),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(widget.subtitle!,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFF1A1A1A),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
  );
}
