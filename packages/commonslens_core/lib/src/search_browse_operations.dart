part of 'search_service.dart';

typedef CategoryItem = ({String name, int size});
typedef BrowseResult<T> = ({List<T> items, String? nextCursor});

extension BrowseExtensions on SearchService {
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
    final params = <String, String>{
      'action': 'query',
      'list': 'allpages',
      'apnamespace': '10',
      'aplimit': '$limit',
      'format': 'json',
      'origin': '*',
    };
    if (prefix != null && prefix.trim().isNotEmpty) {
      params['apprefix'] = prefix.trim();
    }
    if (cursor != null) params['apcontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await _transport.get(uri);
      if (res.statusCode != 200) return (items: <String>[], nextCursor: null);

      final data = jsonDecode(res.body);
      final pages = data['query']?['allpages'] as List? ?? [];
      final nextCursor = data['continue']?['apcontinue'] as String?;

      final items = pages
          .map((p) =>
              (p['title'] as String).replaceFirst('Template:', '').trim())
          .toList();

      return (items: items, nextCursor: nextCursor);
    } catch (_) {
      return (items: <String>[], nextCursor: null);
    }
  }
}
