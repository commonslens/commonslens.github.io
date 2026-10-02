part of 'search_service.dart';

mixin _SearchAutocompleteOperations {
  WikimediaTransport get _transport;

  Future<List<DepictsEntity>> _searchWikidataEntities(
    String text, {
    required String type, // 'item' or 'property'
    int limit = 8,
    String language = 'en',
  }) async {
    final query = text.trim();
    if (query.isEmpty) return [];

    try {
      final params = <String, String>{
        'action': 'wbsearchentities',
        'search': query,
        'language': language,
        'uselang': language,
        'type': type,
        'limit': '$limit',
        'format': 'json',
        'origin': '*',
      };

      final uri = Uri.https('www.wikidata.org', '/w/api.php', params);

      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['search'] as List? ?? [];

      return results
          .map((r) {
            final map = r as Map<String, dynamic>;
            return DepictsEntity(
              qid: map['id'] as String? ?? '',
              label: map['label'] as String? ?? (map['id'] as String? ?? ''),
              description: map['description'] as String?,
            );
          })
          .where((e) => e.qid.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<DepictsEntity>> searchDepictsEntities(
    String text, {
    int limit = 8,
    String language = 'en',
  }) {
    return _searchWikidataEntities(text,
        type: 'item', limit: limit, language: language);
  }

  /// For the generalized Wikidata property browser (haswbstatement: beyond
  /// just depicts/license) — searches Wikidata properties (P-codes) instead
  /// of items (Q-codes), e.g. "location of creation" -> P1071.
  ///
  /// P180 (depicts) and P275 (copyright status/license) are deliberately
  /// filtered out: both already have their own dedicated fields elsewhere
  /// in the drawer (Depicts, License), and letting either be picked here
  /// too would let a user represent the same underlying filter in two
  /// separate places — best case a harmless duplicate clause, worst case a
  /// direct contradiction (e.g. "Depicts: Cat" as include, "P180: Cat" as
  /// exclude via this picker), which would silently zero out all results
  /// with no visible explanation.
  static const Set<String> _reservedPropertyIds = {'P180', 'P275'};

  Future<List<DepictsEntity>> searchWikidataProperties(
    String text, {
    int limit = 8,
    String language = 'en',
  }) async {
    final results = await _searchWikidataEntities(text,
        type: 'property', limit: limit, language: language);
    return results.where((p) => !_reservedPropertyIds.contains(p.qid)).toList();
  }

  Future<List<String>> searchCategories(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'allcategories',
        'acprefix': clean,
        'format': 'json',
        'origin': '*',
      });
      final res =
          await _transport.get(uri, timeout: const Duration(seconds: 5));
      final data = jsonDecode(res.body);
      final cats = data['query']['allcategories'] as List? ?? [];
      return cats.map((c) => c['*'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  /// Same shape as [searchCategories] — `list=allpages` restricted to
  /// namespace 10 (Template:) instead of `list=allcategories` — for the
  /// Templates picker's hastemplate: autocomplete. Titles come back as
  /// "Template:Foo"; stripped to "Foo" to match how template names are
  /// already stored everywhere else in [SearchState.templates] /
  /// [SearchState.excludeTemplates] and embedded in hastemplate: clauses
  /// (see [buildQuery]) — bare, no namespace prefix.
  Future<List<String>> searchTemplates(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'allpages',
        'apnamespace': '10',
        'apprefix': clean,
        'format': 'json',
        'origin': '*',
      });
      final res = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final pages = data['query']?['allpages'] as List? ?? [];
      return pages
          .map((p) => ((p as Map<String, dynamic>)['title'] as String? ?? '')
              .replaceFirst('Template:', '')
              .trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Type-ahead suggestions for the main search bar, via MediaWiki's
  /// `action=opensearch` — the same endpoint that powers the suggestion
  /// dropdown on wikipedia.org/commons.wikimedia.org's own search box.
  /// Restricted to namespace 6 (File:) since this app only searches media.
  /// Callers pass in a single query *segment* (see
  /// [SearchService.multiQuerySeparator]) — this method has no opinion on
  /// "+"-splitting, that's the caller's job.
  Future<List<String>> searchTitleSuggestions(String text,
      {int limit = 8}) async {
    final query = text.trim();
    if (query.isEmpty) return [];
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'opensearch',
        'search': query,
        'namespace': '6',
        'limit': '$limit',
        'redirects': 'resolve',
        'format': 'json',
        'origin': '*',
      });

      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 5));

      if (response.statusCode != 200) return [];

      // opensearch's response shape is a fixed-position array, not an
      // object: [searchTerm, [titles...], [descriptions...], [urls...]].
      final data = jsonDecode(response.body) as List;
      if (data.length < 2) return [];

      final titles = data[1] as List? ?? [];
      return titles
          .map((t) => (t as String).replaceFirst('File:', '').trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
