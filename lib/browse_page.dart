import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'search_service.dart';
import 'search_controller.dart';
import 'search_models.dart';
import 'search_url_codec.dart';
import 'backend_providers.dart';
import 'legal_pages.dart';

void _openSearchWith(
  BuildContext context,
  WidgetRef ref,
  SearchState Function(SearchState current) update,
) {
  final current = ref.read(searchControllerProvider).filterState;
  final next = update(current);
  final params = SearchUrlCodec.toQueryParams(next);
  context.go(
    Uri(path: '/', queryParameters: params.isEmpty ? null : params).toString(),
  );
}

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
        actions: const [
          DocsSectionLink(
            section: 'browse',
            label: 'User Guide to Browse',
          ),
          SizedBox(width: 4),
        ],
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

class _CategoryTab extends ConsumerStatefulWidget {
  const _CategoryTab();

  @override
  ConsumerState<_CategoryTab> createState() => _CategoryTabState();
}

class _CategoryTabState extends ConsumerState<_CategoryTab> {
  static const _roots = <String>[
    'Topics',
    'Copyright statuses',
    'Media by source',
    'Media types',
    'Commons',
    'User categories',
  ];

  final List<CategoryTreeItem> _items = [];
  final List<String> _path = ['Topics'];
  final Set<String> _selectedCategories = <String>{};
  String? _cursor;
  String _query = '';
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategories.addAll(
      ref.read(searchControllerProvider).filterState.categories,
    );
    _loadChildren(refresh: true);
  }

  Future<void> _loadChildren({bool refresh = false}) async {
    if (_loading && !refresh) return;
    final generation = ++_generation;
    final cursor = refresh ? null : _cursor;
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result =
          await ref.read(commonsBackendProvider).browseCategoryChildren(
                category: _path.last,
                cursor: cursor,
              );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.items);
        _cursor = result.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load this category branch. Please try again.';
      });
    }
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) {
      setState(() => _query = '');
      _loadChildren(refresh: true);
      return;
    }
    final generation = ++_generation;
    setState(() {
      _query = query;
      _items.clear();
      _cursor = null;
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(commonsBackendProvider)
          .browseCategories(prefix: query, limit: 100);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.items.map((item) => (
              name: item.name,
              files: item.size,
              subcategories: 0,
            )));
        _cursor = result.nextCursor;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to search categories. Please try again.';
      });
    }
  }

  void _openRoot(String root) {
    _generation++;
    setState(() {
      _path
        ..clear()
        ..add(root);
      _query = '';
    });
    _loadChildren(refresh: true);
  }

  void _openChild(String child) {
    _generation++;
    setState(() {
      _path.add(child);
      _query = '';
    });
    _loadChildren(refresh: true);
  }

  void _openPath(int index) {
    if (index == _path.length - 1) return;
    _generation++;
    setState(() {
      _path.removeRange(index + 1, _path.length);
      _query = '';
    });
    _loadChildren(refresh: true);
  }

  void _toggleSelection(CategoryTreeItem item) {
    setState(() {
      if (!_selectedCategories.add(item.name)) {
        _selectedCategories.remove(item.name);
      }
    });
  }

  void _applySelection() {
    if (_selectedCategories.isEmpty) return;
    final selected = Set<String>.from(_selectedCategories);
    _openSearchWith(
      context,
      ref,
      (state) => state.copyWith(
        categories: selected,
        // Choosing from Browse starts with the fast direct-category search.
        // Nested descendants remain an explicit choice in Filters.
        deepCategoryMode: false,
      ),
    );
  }

  Widget _buildSelectionBar() {
    final selected = _selectedCategories.toList()..sort();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: const Color(0xFF3D7EFF).withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Selected categories (${selected.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _applySelection,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3D7EFF),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.check, size: 15),
                label: const Text('Apply'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 86),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in selected)
                    InputChip(
                      label: Text(category),
                      onDeleted: () => setState(
                        () => _selectedCategories.remove(category),
                      ),
                      backgroundColor: const Color(0xFF1A1A1A),
                      side: const BorderSide(color: Color(0xFF3D7EFF)),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                      deleteIconColor: const Color(0xFF75A3FF),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingSearch = _query.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'Search category names (or press Enter to jump)',
            ),
            onSubmitted: _search,
          ),
        ),
        if (!showingSearch) ...[
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final root in _roots)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(root),
                      selected: _path.first == root,
                      selectedColor: const Color(0xFF3D7EFF),
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(
                        color:
                            _path.first == root ? Colors.white : Colors.white70,
                      ),
                      side: BorderSide(
                        color: _path.first == root
                            ? const Color(0xFF3D7EFF)
                            : Colors.white54,
                      ),
                      onSelected: (_) => _openRoot(root),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < _path.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right,
                            size: 16, color: Colors.white38),
                      ),
                    TextButton(
                      onPressed: () => _openPath(i),
                      style: TextButton.styleFrom(
                        foregroundColor: i == _path.length - 1
                            ? Colors.white
                            : const Color(0xFF75A3FF),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(_path[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Matching categories',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
          ),
        if (_selectedCategories.isNotEmpty) _buildSelectionBar(),
        Expanded(child: _buildResults(showingSearch)),
      ],
    );
  }

  Widget _buildResults(bool showingSearch) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () =>
              showingSearch ? _search(_query) : _loadChildren(refresh: true),
          icon: const Icon(Icons.refresh),
          label: Text(_error!),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          showingSearch
              ? 'No matching categories found.'
              : 'No subcategories in this branch.',
          style: const TextStyle(color: Colors.white54),
        ),
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
        final counts = [
          if (item.files > 0) '${item.files} files',
          if (item.subcategories > 0)
            '${item.subcategories} subcategor${item.subcategories == 1 ? 'y' : 'ies'}',
        ];
        return _BrowseItemCard(
          title: item.name,
          selected: _selectedCategories.contains(item.name),
          subtitle: showingSearch
              ? item.files > 0
                  ? '${item.files} direct files'
                  : 'Container or empty category — direct files only'
              : counts.isEmpty
                  ? 'Category'
                  : item.subcategories > 0
                      ? '${counts.join(' · ')} · use nested mode for descendants'
                      : counts.join(' · '),
          onTap: () => _toggleSelection(item),
          onOpen: !showingSearch && item.subcategories > 0
              ? () => _openChild(item.name)
              : null,
        );
      },
    );
  }

  Future<void> _loadMore() async {
    if (_loading || _cursor == null) return;
    if (_query.isNotEmpty) {
      setState(() => _loading = true);
      try {
        final result = await ref.read(commonsBackendProvider).browseCategories(
              prefix: _query,
              cursor: _cursor,
              limit: 100,
            );
        if (!mounted) return;
        setState(() {
          _items.addAll(result.items.map((item) => (
                name: item.name,
                files: item.size,
                subcategories: 0,
              )));
          _cursor = result.nextCursor;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Unable to load more categories. Please try again.';
        });
      }
      return;
    }
    await _loadChildren();
  }
}

class _TemplateTreeNode {
  _TemplateTreeNode({required this.label, required this.prefix});

  final String label;
  String prefix;
  String? templateName;
  final List<_TemplateTreeNode> children = [];

  bool get isGroup => children.isNotEmpty;
}

class _TemplateTab extends ConsumerStatefulWidget {
  const _TemplateTab();

  @override
  ConsumerState<_TemplateTab> createState() => _TemplateTabState();
}

class _TemplateTabState extends ConsumerState<_TemplateTab> {
  final _templates = <String>[];
  final _roots = <_TemplateTreeNode>[];
  final _pathPrefixes = <String>[];
  String _query = '';
  String? _cursor;
  bool _loading = false;
  String? _error;
  int _generation = 0;

  @override
  void dispose() {
    super.dispose();
  }

  List<_TemplateTreeNode> get _visibleNodes {
    var nodes = _roots;
    for (final prefix in _pathPrefixes) {
      _TemplateTreeNode? match;
      for (final node in nodes) {
        if (node.prefix == prefix) {
          match = node;
          break;
        }
      }
      if (match == null) return const [];
      nodes = match.children;
    }
    return nodes;
  }

  _TemplateTreeNode? _findNode(String prefix) {
    _TemplateTreeNode? visit(Iterable<_TemplateTreeNode> nodes) {
      for (final node in nodes) {
        if (node.prefix == prefix) return node;
        final nested = visit(node.children);
        if (nested != null) return nested;
      }
      return null;
    }

    return visit(_roots);
  }

  void _rebuildTree() {
    _roots.clear();
    for (final name in _templates) {
      final clean = name.trim();
      if (clean.isEmpty) continue;
      final parts = clean
          .split(':')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;

      var level = _roots;
      var path = '';
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        path = path.isEmpty ? part : '$path:$part';
        _TemplateTreeNode? node;
        for (final candidate in level) {
          if (candidate.label == part) {
            node = candidate;
            break;
          }
        }
        node ??= _TemplateTreeNode(label: part, prefix: path);
        if (!level.contains(node)) level.add(node);

        final isLeaf = i == parts.length - 1;
        if (isLeaf) {
          node.templateName = clean;
          if (node.children.isEmpty) node.prefix = clean;
        } else {
          node.prefix = '$path:';
        }
        level = node.children;
      }
    }

    void sortNodes(List<_TemplateTreeNode> nodes) {
      nodes.sort((a, b) {
        final groupOrder = (a.isGroup ? 0 : 1) - (b.isGroup ? 0 : 1);
        return groupOrder == 0
            ? a.label.toLowerCase().compareTo(b.label.toLowerCase())
            : groupOrder;
      });
      for (final node in nodes) {
        sortNodes(node.children);
      }
    }

    sortNodes(_roots);
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    final generation = ++_generation;
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _templates.clear();
        _roots.clear();
        _pathPrefixes.clear();
        _cursor = null;
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _query = query;
      _templates.clear();
      _roots.clear();
      _pathPrefixes.clear();
      _cursor = null;
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(commonsBackendProvider)
          .browseTemplates(prefix: query, limit: 500);
      if (!mounted || generation != _generation) return;
      setState(() {
        _templates.addAll(result.items);
        _cursor = result.nextCursor;
        _rebuildTree();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to search templates. Please try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _cursor == null || _query.isEmpty) return;
    final generation = _generation;
    setState(() => _loading = true);
    try {
      final result = await ref.read(commonsBackendProvider).browseTemplates(
            prefix: _query,
            cursor: _cursor,
            limit: 500,
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        _templates.addAll(result.items);
        _cursor = result.nextCursor;
        _rebuildTree();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load more templates. Please try again.';
      });
    }
  }

  void _openNode(_TemplateTreeNode node) {
    if (!node.isGroup) return;
    setState(() => _pathPrefixes.add(node.prefix));
  }

  void _select(_TemplateTreeNode node) {
    final name = node.templateName;
    if (name == null) {
      _openNode(node);
      return;
    }
    _openSearchWith(
      context,
      ref,
      (state) => state.copyWith(templates: {...state.templates, name}),
    );
  }

  int _leafCount(_TemplateTreeNode node) {
    final ownTemplate = node.templateName == null ? 0 : 1;
    return ownTemplate +
        node.children.fold(0, (sum, child) => sum + _leafCount(child));
  }

  Widget _buildBreadcrumbs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
              onPressed: _pathPrefixes.isEmpty
                  ? null
                  : () => setState(() => _pathPrefixes.clear()),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF75A3FF),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Results'),
            ),
            for (var i = 0; i < _pathPrefixes.length; i++) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child:
                    Icon(Icons.chevron_right, size: 16, color: Colors.white38),
              ),
              TextButton(
                onPressed: i == _pathPrefixes.length - 1
                    ? null
                    : () => setState(() =>
                        _pathPrefixes.removeRange(i + 1, _pathPrefixes.length)),
                style: TextButton.styleFrom(
                  foregroundColor: i == _pathPrefixes.length - 1
                      ? Colors.white
                      : const Color(0xFF75A3FF),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                    _findNode(_pathPrefixes[i])?.label ?? _pathPrefixes[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _visibleNodes;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
              'Search actual template names (e.g. "PD-USGov")',
            ),
            onSubmitted: _search,
          ),
        ),
        if (_query.isEmpty)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Search for a template family to browse it as a tree.\n\n'
                  'This lists real Template: pages only. Colon-separated names '
                  'are grouped together; selecting a leaf uses that exact '
                  'template. An institution value such as '
                  'Institution:Metropolitan Museum of Art is not automatically '
                  'a template page.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.5),
                ),
              ),
            ),
          )
        else ...[
          _buildBreadcrumbs(),
          Expanded(
            child: _buildTemplateResults(nodes),
          ),
        ],
      ],
    );
  }

  Widget _buildTemplateResults(List<_TemplateTreeNode> nodes) {
    if (nodes.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (nodes.isEmpty && _error != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () => _search(_query),
          icon: const Icon(Icons.refresh),
          label: Text(_error!),
        ),
      );
    }
    if (nodes.isEmpty) {
      final typedFamily = _query.contains(':');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            typedFamily
                ? 'No real Template:$_query pages were found.\n\n'
                    'Institution:Metropolitan Museum of Art is usually a value '
                    'inside {{Institution}}, not a template name. Try a real '
                    'template prefix such as Metropolitan or PD-USGov.'
                : 'No matching templates found.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.5),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: nodes.length + (_cursor != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == nodes.length) {
          if (!_loading) Future.microtask(_loadMore);
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          );
        }
        final node = nodes[index];
        final isGroup = node.isGroup;
        return _BrowseItemCard(
          title: node.label,
          subtitle: isGroup
              ? '${_leafCount(node)} template${_leafCount(node) == 1 ? '' : 's'} in this family'
              : 'Exact MediaWiki template',
          onTap: () => _select(node),
          onOpen: isGroup ? () => _openNode(node) : null,
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
  String? _error;

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref
          .read(commonsAutocompleteProvider)
          .wikidataEntities(query, limit: 50);
      if (!mounted) return;
      setState(() {
        _items = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load Wikidata suggestions. Please try again.';
      });
    }
  }

  void _select(DepictsEntity entity) {
    _openSearchWith(
      context,
      ref,
      (state) => state.copyWith(
        depictsInclude: {...state.depictsInclude, entity},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: _inputDecoration(
                    'Search Wikidata items or Q-codes (e.g. "City" or "Q146")')
                .copyWith(
                    suffixIcon:
                        const Icon(Icons.search, color: Colors.white54)),
            onSubmitted: _search,
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null)
          Expanded(
            child: Center(
              child:
                  Text(_error!, style: const TextStyle(color: Colors.white54)),
            ),
          )
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
  final VoidCallback? onOpen;
  final bool selected;

  const _BrowseItemCard({
    required this.title,
    this.subtitle,
    required this.onTap,
    this.onOpen,
    this.selected = false,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
        padding: EdgeInsets.zero,
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF191919) : const Color(0xFF131313),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.selected || _hovered
                ? const Color(0xFF3D7EFF)
                : const Color(0xFF202020),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(widget.title,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (widget.selected)
                            const Icon(Icons.check_circle,
                                size: 17, color: Color(0xFF3D7EFF)),
                        ],
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(widget.subtitle!,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (widget.onOpen != null)
              SizedBox(
                width: 82,
                height: 66,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onOpen,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chevron_right, color: Color(0xFF75A3FF)),
                        Text('Open',
                            style: TextStyle(
                                color: Color(0xFF75A3FF), fontSize: 10)),
                      ],
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
