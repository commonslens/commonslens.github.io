part of 'search_service.dart';

typedef CategoryItem = ({String name, int size});
typedef CategoryTreeItem = ({
  String name,
  int files,
  int subcategories,
});
typedef BrowseResult<T> = ({List<T> items, String? nextCursor});

bool _isPrimaryTemplatePage(String name) => !name.contains('/');

extension BrowseExtensions on SearchService {
  /// Lists the immediate child categories of [category]. Unlike
  /// [browseCategories], this follows Commons' actual category graph rather
  /// than enumerating every category in alphabetical order.
  Future<BrowseResult<CategoryTreeItem>> browseCategoryChildren({
    required String category,
    String? cursor,
    int limit = 100,
  }) async {
    final cleanCategory = category.trim();
    if (cleanCategory.isEmpty) {
      return (items: <CategoryTreeItem>[], nextCursor: null);
    }

    final categoryTitle = cleanCategory.toLowerCase().startsWith('category:')
        ? 'Category:${cleanCategory.substring('Category:'.length)}'
        : 'Category:$cleanCategory';
    final params = <String, String>{
      'action': 'query',
      'generator': 'categorymembers',
      'gcmtitle': categoryTitle,
      'gcmtype': 'subcat',
      'gcmlimit': '$limit',
      'prop': 'categoryinfo',
      'format': 'json',
      'formatversion': '2',
      'origin': '*',
    };
    if (cursor != null) params['gcmcontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await _transport.get(uri);
      if (res.statusCode != 200) {
        return (items: <CategoryTreeItem>[], nextCursor: null);
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final rawPages = data['query']?['pages'];
      final pages = rawPages is List
          ? rawPages
          : rawPages is Map
              ? rawPages.values.toList()
              : const <dynamic>[];
      final nextCursor = data['continue']?['gcmcontinue']?.toString();

      final items = <CategoryTreeItem>[];
      for (final raw in pages) {
        if (raw is! Map) continue;
        final page = Map<String, dynamic>.from(raw);
        final rawTitle = page['title'] as String? ?? '';
        if (rawTitle.isEmpty) continue;
        final info = page['categoryinfo'];
        final categoryInfo = info is Map
            ? Map<String, dynamic>.from(info)
            : const <String, dynamic>{};
        items.add((
          name: rawTitle
              .replaceFirst(RegExp(r'^Category:', caseSensitive: false), '')
              .trim(),
          files: (categoryInfo['files'] as num?)?.toInt() ?? 0,
          subcategories: (categoryInfo['subcats'] as num?)?.toInt() ?? 0,
        ));
      }

      return (items: items, nextCursor: nextCursor);
    } catch (_) {
      return (items: <CategoryTreeItem>[], nextCursor: null);
    }
  }

  Future<BrowseResult<CategoryItem>> browseCategories({
    String? prefix,
    String? cursor,
    int limit = 500,
  }) async {
    final params = <String, String>{
      'action': 'query',
      'list': 'allcategories',
      'acprop': 'size',
      'aclimit': '$limit',
      'format': 'json',
      'origin': '*',
    };
    if (prefix != null && prefix.trim().isNotEmpty) {
      params['acprefix'] = prefix.trim();
    }
    if (cursor != null) params['accontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await _transport.get(uri);
      if (res.statusCode != 200) {
        return (items: <CategoryItem>[], nextCursor: null);
      }

      final data = jsonDecode(res.body);
      final cats = data['query']?['allcategories'] as List? ?? [];
      final nextCursor = data['continue']?['accontinue'] as String?;

      final items = cats
          .map((c) =>
              (name: c['*'] as String, size: (c['size'] as num?)?.toInt() ?? 0))
          .toList();

      return (items: items, nextCursor: nextCursor);
    } catch (_) {
      return (items: <CategoryItem>[], nextCursor: null);
    }
  }

  Future<BrowseResult<String>> browseTemplates({
    String? prefix,
    String? cursor,
    int limit = 500,
  }) async {
    final rawPrefix = prefix?.trim() ?? '';
    // Templates are actual pages in namespace 10. Keep this directory tied to
    // that page index: the search module is full-text and happily returns
    // documentation/sandbox pages whose titles merely mention the word the
    // user typed. That made a pseudo-family such as `institution:` look like
    // a real set of templates when it is not one.
    final searchTerm = rawPrefix
        .replaceFirst(RegExp(r'^Template:\s*', caseSensitive: false), '')
        .trim();
    final params = <String, String>{
      'action': 'query',
      'list': 'allpages',
      'apnamespace': '10',
      'aplimit': '$limit',
      'format': 'json',
      'origin': '*',
    };
    if (searchTerm.isNotEmpty) params['apprefix'] = searchTerm;
    if (cursor != null) params['apcontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await _transport.get(uri);
      if (res.statusCode != 200) return (items: <String>[], nextCursor: null);

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pages = (data['query']?['allpages'] as List?) ?? const <dynamic>[];
      final nextCursor = data['continue']?['apcontinue']?.toString();

      final items = pages
          .map((p) => ((p as Map<String, dynamic>)['title'] as String? ?? '')
              .replaceFirst(RegExp(r'^Template:', caseSensitive: false), '')
              .trim())
          .where(_isPrimaryTemplatePage)
          .where((item) => item.isNotEmpty)
          .toList();

      return (items: items, nextCursor: nextCursor);
    } catch (_) {
      return (items: <String>[], nextCursor: null);
    }
  }
}
