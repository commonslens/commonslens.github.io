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
          timeout: const Duration(seconds: 10),
          category: WikimediaRequestCategory.autocomplete);

      if (response.statusCode != 200) {
        throw AutocompleteLookupException('Wikidata entity search',
            statusCode: response.statusCode);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AutocompleteLookupException('Wikidata entity search');
      }
      final apiError = decoded['error'];
      if (apiError != null) {
        throw const AutocompleteLookupException('Wikidata entity search');
      }
      final results = decoded['search'];
      if (results is! List) {
        throw const AutocompleteLookupException('Wikidata entity search');
      }

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
    } catch (error) {
      if (error is AutocompleteLookupException) rethrow;
      throw AutocompleteLookupException('Wikidata entity search', cause: error);
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
      final res = await _transport.get(
        uri,
        timeout: const Duration(seconds: 5),
        category: WikimediaRequestCategory.autocomplete,
      );
      if (res.statusCode != 200) {
        throw AutocompleteLookupException('Category search',
            statusCode: res.statusCode);
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw const AutocompleteLookupException('Category search');
      }
      if (decoded['error'] != null) {
        throw const AutocompleteLookupException('Category search');
      }
      final query = decoded['query'];
      final cats = query is Map ? query['allcategories'] : null;
      if (cats is! List) {
        throw const AutocompleteLookupException('Category search');
      }
      return cats
          .whereType<Map>()
          .map((c) => c['*']?.toString() ?? '')
          .where((category) => category.isNotEmpty)
          .toList();
    } catch (error) {
      if (error is AutocompleteLookupException) rethrow;
      throw AutocompleteLookupException('Category search', cause: error);
    }
  }

  /// Template-name autocomplete for the Templates picker's hastemplate:
  /// filter. This is deliberately an actual namespace-10 prefix lookup, not
  /// full-text search: documentation and sandbox pages are not templates a
  /// file can transclude, and returning them makes a selected hastemplate:
  /// filter misleading. Titles come back as "Template:Foo"; stripped to
  /// "Foo" to match [SearchState.templates].
  Future<List<String>> searchTemplates(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];
    final searchTerm = clean
        .replaceFirst(RegExp(r'^Template:\s*', caseSensitive: false), '')
        .trim();
    if (searchTerm.isEmpty) return [];
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'list': 'allpages',
        'apnamespace': '10',
        'apprefix': searchTerm,
        'aplimit': '8',
        'format': 'json',
        'origin': '*',
      });
      final res = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 5),
          category: WikimediaRequestCategory.autocomplete);
      if (res.statusCode != 200) {
        throw AutocompleteLookupException('Template search',
            statusCode: res.statusCode);
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) {
        throw const AutocompleteLookupException('Template search');
      }
      if (decoded['error'] != null) {
        throw const AutocompleteLookupException('Template search');
      }
      final query = decoded['query'];
      final pages = query is Map ? query['allpages'] : null;
      if (pages is! List) {
        throw const AutocompleteLookupException('Template search');
      }
      return pages
          .whereType<Map>()
          .map((p) => (p['title']?.toString() ?? '')
              .replaceFirst('Template:', '')
              .trim())
          .where(_isPrimaryTemplatePage)
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (error) {
      if (error is AutocompleteLookupException) rethrow;
      throw AutocompleteLookupException('Template search', cause: error);
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
          timeout: const Duration(seconds: 5),
          category: WikimediaRequestCategory.autocomplete);

      if (response.statusCode != 200) {
        throw AutocompleteLookupException('File title search',
            statusCode: response.statusCode);
      }

      // opensearch's response shape is a fixed-position array, not an
      // object: [searchTerm, [titles...], [descriptions...], [urls...]].
      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.length < 2 || decoded[1] is! List) {
        throw const AutocompleteLookupException('File title search');
      }

      final titles = decoded[1] as List;
      return titles
          .whereType<String>()
          .map((t) => t.replaceFirst('File:', '').trim())
          .where((t) => t.isNotEmpty)
          .toList();
    } catch (error) {
      if (error is AutocompleteLookupException) rethrow;
      throw AutocompleteLookupException('File title search', cause: error);
    }
  }
}
