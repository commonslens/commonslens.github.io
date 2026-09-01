import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'search_service.dart';
import 'search_controller.dart';
import 'search_models.dart';

class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111111),
          title: const Text('Browse Directories', style: TextStyle(color: Colors.white, fontSize: 16)),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: const TabBar(
            indicatorColor: Color(0xFF3D7EFF),
            labelColor: Color(0xFF3D7EFF),
            unselectedLabelColor: Colors.white54,
            tabs: [
              Tab(text: 'Categories'),
              Tab(text: 'Templates'),
              Tab(text: 'Depicts (Q-Codes)'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            _CategoryTab(),
            _TemplateTab(),
            _DepictsTab(),
          ],
        ),
      ),
    );
  }
}

class _CategoryTab extends ConsumerStatefulWidget {
  const _CategoryTab();
  @override
  ConsumerState<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends ConsumerState<_CategoryTab> {
  final SearchService _service = SearchService();
  final List<CategoryItem> _items = [];
  String? _cursor;
  bool _loading = false;
  String _prefix = '';

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore({bool refresh = false}) async {
    if (_loading) return;
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    setState(() => _loading = true);
    final result = await _service.browseCategories(prefix: _prefix, cursor: _cursor);
    setState(() {
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      _loading = false;
    });
  }

  void _select(String category) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((c) => 
      c.copyWith(categories: {...c.categories, category})
    );
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
            decoration: _inputDecoration('Jump to category (e.g. "Architecture")'),
            onSubmitted: (val) {
              _prefix = val;
              _loadMore(refresh: true);
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length + (_cursor != null ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _items.length) {
                if (!_loading) Future.microtask(() => _loadMore());
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              }
              final item = _items[i];
              return _BrowseItemCard(
                title: item.name,
                subtitle: '${item.size} files in this category',
                onTap: () => _select(item.name),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TemplateTab extends ConsumerStatefulWidget {
  const _TemplateTab();
  @override
  ConsumerState<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends ConsumerState<_TemplateTab> {
  final SearchService _service = SearchService();
  final List<String> _items = [];
  String? _cursor;
  bool _loading = false;
  String _prefix = '';

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore({bool refresh = false}) async {
    if (_loading) return;
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    setState(() => _loading = true);
    final result = await _service.browseTemplates(prefix: _prefix, cursor: _cursor);
    setState(() {
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      _loading = false;
    });
  }

  void _select(String template) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((c) => 
      c.copyWith(templates: {...c.templates, template})
    );
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
            decoration: _inputDecoration('Jump to template (e.g. "PD-USGov")'),
            onSubmitted: (val) {
              _prefix = val;
              _loadMore(refresh: true);
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _items.length + (_cursor != null ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _items.length) {
                if (!_loading) Future.microtask(() => _loadMore());
                return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
              }
              final item = _items[i];
              return _BrowseItemCard(
                title: item,
                subtitle: 'MediaWiki Template',
                onTap: () => _select(item),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DepictsTab extends ConsumerStatefulWidget {
  const _DepictsTab();
  @override
  ConsumerState<_DepictsTab> createState() => _DepictsTabState();
}

class _DepictsTabState extends ConsumerState<_DepictsTab> {
  final SearchService _service = SearchService();
  List<DepictsEntity> _items = [];
  bool _loading = false;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() => _loading = true);
    final results = await _service.searchDepictsEntities(query, limit: 50);
    setState(() {
      _items = results;
      _loading = false;
    });
  }

  void _select(DepictsEntity entity) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate((c) => 
      c.copyWith(depictsInclude: {...c.depictsInclude, entity})
    );
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
            decoration: _inputDecoration('Search Wikidata items (e.g. "City")').copyWith(
              suffixIcon: const Icon(Icons.search, color: Colors.white54)
            ),
            onSubmitted: _search,
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_items.isEmpty)
          const Expanded(child: Center(child: Text('Search for a visual subject to apply as a filter.', style: TextStyle(color: Colors.white54))))
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
              color: _hovered ? const Color(0xFF3D7EFF) : const Color(0xFF202020),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title, 
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.subtitle!, 
                  style: const TextStyle(color: Colors.white54, fontSize: 12)
                ),
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
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
  );
}