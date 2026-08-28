import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_models.dart';
import 'search_url_codec.dart';

class SearchService {
  static const int pageSize = 50;
  
  static final http.Client _client = http.Client();

  static final RegExp _htmlTagRegex = RegExp(r'<[^>]*>');

  /// Single accessor for every extmetadata field SearchItem pulls out —
  /// used by all three fetch paths below so Artist/License/Categories/etc.
  /// are all read the exact same way in exactly one place.
  static String _extValue(Map<String, dynamic> ext, String key) {
    return ext[key]?['value']?.toString() ?? '';
  }

  /// Builds a [SearchItem] from one `imageinfo` entry (the shape returned
  /// by `iiprop=url|size|mime|extmetadata|user|dimensions`, regardless of
  /// which of the three call sites below fetched it — a single lookup, a
  /// search page, or an author's upload list all return this same shape).
  /// Every extmetadata field lives behind [_extValue] so Artist/License/
  /// Categories/etc. are read identically everywhere. Returns null when
  /// there's no usable original URL, mirroring what each call site already
  /// treated as "skip this result".
  static SearchItem? _itemFromImageInfo(
    Map<String, dynamic> info, {
    required String rawTitle,
    required String snippet,
    String? timestamp,
    String? descriptionUrl,
    String? uploaderFallback,
  }) {
    final originalUrl = info['url'] as String? ?? '';
    if (originalUrl.isEmpty) return null;

    final mime = (info['mime'] as String? ?? '').toLowerCase();
    final thumburl = info['thumburl'] as String? ?? '';
    final thumb = thumburl.isNotEmpty ? thumburl : originalUrl;
    final ext = info['extmetadata'] as Map<String, dynamic>? ?? {};

    return SearchItem(
      title: rawTitle.replaceFirst('File:', ''),
      url: originalUrl,
      thumb: thumb,
      commonsUrl:
          'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(rawTitle)}',
      snippet: snippet,
      mime: mime,
      isSvg: mime == 'image/svg+xml',
      timestamp: timestamp,
      descriptionUrl: descriptionUrl,
      artistHtml: _extValue(ext, 'Artist'),
      licenseShortName: _extValue(ext, 'LicenseShortName'),
      licenseUrl: _extValue(ext, 'LicenseUrl'),
      dateTimeOriginal: _extValue(ext, 'DateTimeOriginal'),
      uploader: info['user']?.toString() ?? (uploaderFallback ?? ''),
      width: info['width'] as int? ?? 0,
      height: info['height'] as int? ?? 0,
      categories: _extValue(ext, 'Categories'),
      assessments: _extValue(ext, 'Assessments'),
      imageDescriptionHtml: _extValue(ext, 'ImageDescription'),
      objectName: _extValue(ext, 'ObjectName'),
      creditHtml: _extValue(ext, 'Credit'),
      usageTerms: _extValue(ext, 'UsageTerms'),
      copyrighted: _extValue(ext, 'Copyrighted'),
      restrictions: _extValue(ext, 'Restrictions'),
      uploadDateTime: _extValue(ext, 'DateTime'),
      gpsLatitude: _extValue(ext, 'GPSLatitude'),
      gpsLongitude: _extValue(ext, 'GPSLongitude'),
      permissionHtml: _extValue(ext, 'Permission'),
      attributionRequired: _extValue(ext, 'AttributionRequired'),
    );
  }

  /// Splits a "cat + dog" query into independent segments — the single
  /// source of truth for what counts as a "+"-separator. fetchPage uses
  /// this to fan out parallel searches; SearchTopBar's autocomplete uses
  /// the exact same pattern to find the segment currently being typed, so
  /// the two can never drift out of sync with each other.
  static final RegExp multiQuerySeparator = RegExp(r'\s+\+\s+');

  
  static const Map<LicensePreset, String> _licenseClauses = {
    LicensePreset.cc0: 'haswbstatement:P275=Q6938433', // ~9.9M hits
    LicensePreset.ccBy4: 'haswbstatement:P275=Q20007257', // ~7.6M hits
    LicensePreset.ccBySa4: 'haswbstatement:P275=Q18199165', // ~34.5M hits
    LicensePreset.publicDomain: 'haswbstatement:P6216=Q88088423', // ~12.3M hits
  };

  static const Map<QualityFilter, String> _qualityClauses = {
    QualityFilter.qualityImage: 'hastemplate:"Quality image"', // ~444.6k hits
    QualityFilter.valuedImage: 'hastemplate:"Valued image"', // ~55.6k hits
    // Featured Pictures are recorded via the shared {{Assessments}} template
    // (the same one Quality/Valued status can also route through), so
    // hastemplate:"Assessments" can't isolate just featured status —
    // it would also match quality/valued-assessed files. The FP category
    // is the unambiguous, community-maintained marker instead.
    QualityFilter.featuredPicture:
        'incategory:"Featured pictures on Wikimedia Commons"',
  };

  Future<SearchItem?> fetchSingleItem(String filename) async {
    try {
      final title = filename.startsWith('File:') ? filename : 'File:$filename';
      
      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'info|imageinfo',
        'inprop': 'url',
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      
      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      if (pages.isEmpty) return null;

      final page = pages.values.first;
      
      if (page.containsKey('missing')) return null;

      final infoList = page['imageinfo'] as List?;
      if (infoList == null || infoList.isEmpty) return null;

      final info = infoList.first as Map<String, dynamic>;
      final rawTitle = page['title'] as String? ?? '';

      return _itemFromImageInfo(
        info,
        rawTitle: rawTitle,
        snippet: rawTitle,
        timestamp: page['timestamp'] as String?,
        descriptionUrl: page['fullurl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

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

      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['search'] as List? ?? [];

      return results.map((r) {
        final map = r as Map<String, dynamic>;
        return DepictsEntity(
          qid: map['id'] as String? ?? '',
          label: map['label'] as String? ?? (map['id'] as String? ?? ''),
          description: map['description'] as String?,
        );
      }).where((e) => e.qid.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<DepictsEntity>> searchDepictsEntities(
    String text, {
    int limit = 8,
    String language = 'en',
  }) {
    return _searchWikidataEntities(text, type: 'item', limit: limit, language: language);
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
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
      final data = jsonDecode(res.body);
      final cats = data['query']['allcategories'] as List? ?? [];
      return cats.map((c) => c['*'] as String).toList();
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
  Future<List<String>> searchTitleSuggestions(String text, {int limit = 8}) async {
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

      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 5));

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

  QueryBuildResult buildQuery(SearchState state, {FileFormat? overrideFormat}) {
    final parts = <String>[];
    final chips = <QueryChipData>[];

    if (state.localOnly) {
      parts.add('local:');
      chips.add(const QueryChipData(id: 'localOnly', label: 'Local only'));
    }

    final queryText = state.queryText.trim();
    if (queryText.isNotEmpty) {
      if (state.titleOnly) {
        parts.add('intitle:"$queryText"');
        chips.add(const QueryChipData(id: 'titleOnly', label: 'Title only'));
      } else {
        parts.add(queryText);
      }
    }

    switch (state.tab) {
      case MediaTabType.allMedia:
        chips.add(const QueryChipData(id: 'tab', label: 'All media'));
        break;
      case MediaTabType.images:
        chips.add(const QueryChipData(id: 'tab', label: 'Images'));
        parts.add('filetype:bitmap');
        break;
      case MediaTabType.vectors:
        chips.add(const QueryChipData(id: 'tab', label: 'SVG / Diagrams'));
        parts.add('filetype:drawing');
        break;
      case MediaTabType.audio:
        chips.add(const QueryChipData(id: 'tab', label: 'Audio'));
        parts.add('filetype:audio');
        break;
      case MediaTabType.video:
        chips.add(const QueryChipData(id: 'tab', label: 'Video'));
        parts.add('filetype:video');
        break;
      case MediaTabType.documents:
        chips.add(const QueryChipData(id: 'tab', label: 'Docs'));
        parts.add('filetype:office');
        break;
    }

    for (final format in state.formats.toList()
      ..sort((a, b) => a.name.compareTo(b.name))) {
      chips.add(
        QueryChipData(
          id: 'format:${format.name}',
          label: fileFormatLabel(format),
        ),
      );
    }

    if (overrideFormat != null) {
      parts.add('filemime:"${_getMimeString(overrideFormat)}"');
    }

    // Union mode (OR) for categories works exactly like statementsUnion
    // below: this join is just an honest preview of intent for the display
    // query / chips. The actual OR execution — same precedence problem as
    // statements have when mixed into one big AND'd query string — happens
    // via per-category fan-out in _fetchPageForCategory further down.
    final includeCategories = (state.categories.toList()..sort())
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (state.categoriesUnion && includeCategories.length > 1) {
      final clauses = includeCategories
          .map((c) => state.deepCategoryMode ? 'deepcat:"$c"' : 'incategory:"$c"')
          .toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final c in includeCategories) {
        parts.add(state.deepCategoryMode ? 'deepcat:"$c"' : 'incategory:"$c"');
      }
    }
    for (final c in includeCategories) {
      chips.add(QueryChipData(
        id: 'category:$c',
        label: state.deepCategoryMode ? 'Deep category: $c' : 'Category: $c',
      ));
    }

    for (final category in state.excludeCategories.toList()..sort()) {
      final safe = category.trim();
      if (safe.isEmpty) continue;

      if (state.deepCategoryMode) {
        parts.add('-deepcat:"$safe"');
        chips.add(QueryChipData(id: 'excludeCategory:$safe', label: 'Not in deep category: $safe'));
      } else {
        parts.add('-incategory:"$safe"');
        chips.add(QueryChipData(id: 'excludeCategory:$safe', label: 'Not in category: $safe'));
      }
    }

    if (state.languageCode != null && state.languageCode!.trim().isNotEmpty) {
      final lang = state.languageCode!.trim();
      parts.add('inlanguage:$lang');
      chips.add(QueryChipData(id: 'language', label: 'Language: $lang'));
    }

    if (state.contentModel != null && state.contentModel!.trim().isNotEmpty) {
      final model = state.contentModel!.trim();
      parts.add('contentmodel:$model');
      chips.add(QueryChipData(id: 'contentModel', label: 'Model: $model'));
    }

    if (state.createdDate != null) {
      final created = state.createdDate!;
      if (created.from != null && created.from!.trim().isNotEmpty) {
        final from = created.from!.trim();
        parts.add('creationdate:>=$from');
        chips.add(QueryChipData(id: 'createdFrom', label: 'Created ≥ $from'));
      }
      if (created.to != null && created.to!.trim().isNotEmpty) {
        final to = created.to!.trim();
        parts.add('creationdate:<$to');
        chips.add(QueryChipData(id: 'createdTo', label: 'Created < $to'));
      }
    }

    if (state.editedDate != null) {
      final edited = state.editedDate!;
      if (edited.from != null && edited.from!.trim().isNotEmpty) {
        final from = edited.from!.trim();
        parts.add('lasteditdate:>=$from');
        chips.add(QueryChipData(id: 'editedFrom', label: 'Edited ≥ $from'));
      }
      if (edited.to != null && edited.to!.trim().isNotEmpty) {
        final to = edited.to!.trim();
        parts.add('lasteditdate:<$to');
        chips.add(QueryChipData(id: 'editedTo', label: 'Edited < $to'));
      }
    }

    // License (structured-data statement — see _licenseClauses)
    if (state.licensePreset != LicensePreset.any) {
      final clause = _licenseClauses[state.licensePreset];
      if (clause != null) {
        parts.add(clause);
        chips.add(QueryChipData(
          id: 'license',
          label: licensePresetLabel(state.licensePreset),
        ));
      }
    }

    if (state.qualityFilter != QualityFilter.any) {
      final clause = _qualityClauses[state.qualityFilter];
      if (clause != null) {
        parts.add(clause);
        chips.add(QueryChipData(
          id: 'quality',
          label: qualityFilterLabel(state.qualityFilter),
        ));
      }
    }

    if (state.minWidth != null && state.minWidth! > 0) {
      parts.add('filew:>${state.minWidth}');
      chips.add(QueryChipData(
        id: 'minWidth',
        label: 'Width ≥ ${state.minWidth}px',
      ));
    }
    if (state.minHeight != null && state.minHeight! > 0) {
      parts.add('fileh:>${state.minHeight}');
      chips.add(QueryChipData(
        id: 'minHeight',
        label: 'Height ≥ ${state.minHeight}px',
      ));
    }

    // Union mode for depicts — same pattern and same reasoning as
    // categoriesUnion/statementsUnion: this is a preview join for the
    // display query / chips, real OR execution happens via per-entity
    // fan-out in _fetchPageForDepicts further down.
    final includeDepicts = state.depictsInclude.toList()
      ..sort((a, b) => a.qid.compareTo(b.qid));

    if (state.depictsUnion && includeDepicts.length > 1) {
      final clauses =
          includeDepicts.map((e) => 'haswbstatement:P180=${e.qid}').toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final entity in includeDepicts) {
        parts.add('haswbstatement:P180=${entity.qid}');
      }
    }
    for (final entity in includeDepicts) {
      chips.add(QueryChipData(
        id: 'depicts:${entity.qid}',
        label: 'Depicts: ${entity.label}',
      ));
    }

    for (final entity in state.depictsExclude.toList()
      ..sort((a, b) => a.qid.compareTo(b.qid))) {
      parts.add('-haswbstatement:P180=${entity.qid}');
      chips.add(QueryChipData(
        id: 'excludeDepicts:${entity.qid}',
        label: 'Not depicting: ${entity.label}',
      ));
    }

    // Generalized Wikidata property search — same haswbstatement: mechanism
    // as depicts (P180) above, but for any property the user picks. P180
    // and P275 (license) are deliberately excluded from the property picker
    // itself (see searchWikidataProperties) so this set can never overlap
    // or contradict depictsInclude/Exclude or licensePreset.
    //
    // Union mode (OR) is NOT expressed as a single "A OR B" query string
    // here — mixed with other required clauses (category, license, etc.),
    // Cirrus's OR only binds to its immediately adjacent term, same
    // precedence hazard as the "+"-query bug elsewhere in this file. The
    // real OR execution happens via per-statement fan-out in fetchPage
    // below; this join is just an honest preview of intent.
    final includeStatements = state.statementsInclude.toList()
      ..sort((a, b) =>
          '${a.property.qid}${a.value.qid}'.compareTo('${b.property.qid}${b.value.qid}'));

    if (state.statementsUnion && includeStatements.length > 1) {
      final clauses = includeStatements
          .map((s) => 'haswbstatement:${s.property.qid}=${s.value.qid}')
          .toList();
      parts.add(clauses.join(' OR '));
    } else {
      for (final stmt in includeStatements) {
        parts.add('haswbstatement:${stmt.property.qid}=${stmt.value.qid}');
      }
    }
    for (final stmt in includeStatements) {
      chips.add(QueryChipData(
        id: 'statement:${stmt.property.qid}:${stmt.value.qid}',
        label: '${stmt.property.label}: ${stmt.value.label}',
      ));
    }

    for (final stmt in state.statementsExclude.toList()
      ..sort((a, b) =>
          '${a.property.qid}${a.value.qid}'.compareTo('${b.property.qid}${b.value.qid}'))) {
      parts.add('-haswbstatement:${stmt.property.qid}=${stmt.value.qid}');
      chips.add(QueryChipData(
        id: 'excludeStatement:${stmt.property.qid}:${stmt.value.qid}',
        label: 'Not ${stmt.property.label}: ${stmt.value.label}',
      ));
    }

    if (state.nearCoord != null) {
      final coord = state.nearCoord!;
      final radius = coord.radiusKm.toStringAsFixed(0);
      parts.add('nearcoord:${radius}km,${coord.lat},${coord.lng}');
      chips.add(QueryChipData(
        id: 'nearCoord',
        label: 'Near ${coord.lat.toStringAsFixed(3)}, '
            '${coord.lng.toStringAsFixed(3)} (${radius}km)',
      ));
    } else if (state.nearTitle != null) {
      final nt = state.nearTitle!;
      final radius = nt.radiusKm.toStringAsFixed(0);
      parts.add('neartitle:"${radius}km,${nt.title}"');
      chips.add(QueryChipData(
        id: 'nearTitle',
        label: 'Near "${nt.title}" (${radius}km)',
      ));
    }

    for (final term in state.excludeTerms.toList()..sort()) {
      final safe = term.trim();
      if (safe.isEmpty) continue;
      final needsQuotes = safe.contains(' ');
      final token = needsQuotes ? '"$safe"' : safe;
      parts.add('-$token');
      chips.add(QueryChipData(id: 'exclude:$safe', label: 'Exclude: $safe'));
    }

    final srsearch = parts.join(' ').trim();

    return QueryBuildResult(
      srsearch: srsearch,
      chips: chips,
      debugPreview: srsearch,
    );
  }

  /// Paginated list of everything a single uploader has contributed, via
  /// MediaWiki's `list=allimages&aiuser=` — a purpose-built, natively
  /// paginated index of one user's uploads. Deliberately separate from
  /// `_fetchSingle`: this isn't a CirrusSearch query, it's a different API
  /// module with its own (flat, non-generator) response shape.
  /// Manually builds a Commons-standard thumbnail URL from a full-resolution
  /// original, e.g. .../commons/a/a9/File.jpg -> .../commons/thumb/a/a9/File.jpg/320px-File.jpg
  /// Used as a fallback for when the API doesn't hand back `thumburl` (see
  /// note on fetchAuthorImages) — so a missing thumbnail never means silently
  /// loading the full-res original as a grid preview.
  Future<SearchResponse?> fetchAuthorImages(
    String username, {
    Map<String, dynamic>? continueParams,
  }) async {
    final user = username.trim();
    if (user.isEmpty) return null;

    try {
      // Step 1: just the ordered list of this user's uploads — titles and
      // timestamps only, no thumbnail request here. list=allimages' own
      // aiurlwidth-based thumbnail scaling has a documented history of
      // being unreliable (phabricator.wikimedia.org/T109125 — thumburl
      // silently missing for some/all entries in a batch), which is what
      // was causing the full-res/placeholder issues.
      final listParams = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'list': 'allimages',
        'aiuser': user,
        'aisort': 'timestamp',
        'aidir': 'older', // newest uploads first
        'ailimit': '$pageSize',
        'aiprop': 'timestamp|canonicaltitle',
      };

      if (continueParams != null) {
        for (final entry in continueParams.entries) {
          listParams[entry.key] = entry.value.toString();
        }
      }

      final listUri = Uri.https('commons.wikimedia.org', '/w/api.php', listParams);
      final listResponse = await _client.get(listUri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (listResponse.statusCode != 200) return null;

      final listData = jsonDecode(listResponse.body) as Map<String, dynamic>;
      final nextContinue = listData['continue'] as Map<String, dynamic>?;
      final images = (listData['query']?['allimages'] as List?) ?? [];

      if (images.isEmpty) {
        return SearchResponse(items: const [], continueParams: nextContinue);
      }

      final orderedTitles = <String>[];
      final timestamps = <String, String>{};
      for (final raw in images) {
        final info = raw as Map<String, dynamic>;
        final canonicalTitle = info['canonicaltitle'] as String? ?? '';
        final name = info['name'] as String? ?? '';
        final title = canonicalTitle.isNotEmpty ? canonicalTitle : 'File:$name';
        orderedTitles.add(title);
        final ts = info['timestamp'] as String?;
        if (ts != null) timestamps[title] = ts;
      }

      // Step 2: batch-fetch thumbnails/metadata for exactly these titles via
      // prop=imageinfo — the same call shape _fetchSingle and the main
      // search already use, which is the one that actually loads fast.
      final infoParams = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': orderedTitles.join('|'),
        'prop': 'imageinfo',
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      final infoUri = Uri.https('commons.wikimedia.org', '/w/api.php', infoParams);
      final infoResponse = await _client.get(infoUri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (infoResponse.statusCode != 200) return null;

      final infoData = jsonDecode(infoResponse.body) as Map<String, dynamic>;
      final pages = (infoData['query']?['pages'] as Map<String, dynamic>?) ?? {};

      // pages is keyed by pageid with no guaranteed order — index by title
      // so we can rebuild the newest-first order from step 1.
      final byTitle = <String, Map<String, dynamic>>{};
      for (final page in pages.values) {
        final p = page as Map<String, dynamic>;
        final t = p['title'] as String?;
        if (t != null) byTitle[t] = p;
      }

      final items = <SearchItem>[];
      for (final title in orderedTitles) {
        final page = byTitle[title];
        if (page == null || page.containsKey('missing')) continue;

        final infoList = page['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) continue;
        final info = infoList.first as Map<String, dynamic>;

        final item = _itemFromImageInfo(
          info,
          rawTitle: title,
          snippet: title,
          timestamp: timestamps[title],
          uploaderFallback: user,
        );
        if (item != null) items.add(item);
      }

      return SearchResponse(items: items, continueParams: nextContinue);
    } catch (_) {
      return null;
    }
  }


  /// A stable signature for [state] — identical filters always produce the
  /// same signature, safe to use as a cache/session key.
  ///
  /// Derived from [SearchUrlCodec.toQueryParams] rather than maintaining
  /// its own hand-written list of fields: that codec already has to stay
  /// complete (it's how filters survive a shared URL), so reusing it here
  /// means a newly added [SearchState] field can't silently be missing
  /// from signatures the way a second, independently-maintained field list
  /// could.
  String buildQuerySignature(SearchState state) {
    final params = SearchUrlCodec.toQueryParams(state);
    final sortedKeys = params.keys.toList()..sort();
    return jsonEncode({for (final k in sortedKeys) k: params[k]});
  }

  /// Shared shape behind every fan-out stage below (query segments,
  /// statements, categories, depicts, formats): split [branches] into
  /// independent parallel searches, each identified by [keyOf] and
  /// resolved to its own [SearchState] via [stateFor], run them all
  /// concurrently via [nextFetch], then merge the results — interleaved by
  /// [sortMode] the same way relevance results always were — and dedupe by
  /// URL, since the same file can genuinely satisfy more than one branch.
  ///
  /// [continueBucketKey] namespaces this stage's continuation tokens inside
  /// the opaque [continueParams] map (e.g. `_stmt`, `_cat`, `_depicts`,
  /// `_multi`) so a `loadMore` only re-fetches branches that still have a
  /// page left, and never confuses one stage's tokens for another's when
  /// stages are nested (as they always are here — query segments contain
  /// statement branches, which contain category branches, and so on).
  ///
  /// This is pure plumbing extracted from five call sites that were
  /// otherwise identical apart from what they branch on — the actual
  /// CirrusSearch query strings built at the bottom of the chain
  /// ([buildQuery]) are completely untouched by this.
  Future<SearchResponse?> _fanOutFetch<T>({
    required List<T> branches,
    required String Function(T branch) keyOf,
    required SearchState Function(T branch) stateFor,
    required Future<SearchResponse?> Function(
            T branch, SearchState state, Map<String, dynamic>? continueParams)
        nextFetch,
    required Map<String, dynamic>? continueParams,
    required String continueBucketKey,
    required SortMode sortMode,
  }) async {
    final streams = <String, List<SearchItem>>{};
    final newMultiContinue = <String, dynamic>{};
    bool anySuccess = false;

    final branchTokens =
        continueParams?[continueBucketKey] as Map<String, dynamic>?;
    final futures = <Future<void>>[];

    for (final branch in branches) {
      final key = keyOf(branch);

      // Once a branch runs out of pages (no continuation token left for
      // it), stop re-fetching it on subsequent loadMore calls.
      if (continueParams != null &&
          branchTokens != null &&
          !branchTokens.containsKey(key)) {
        continue;
      }

      final branchContinue = branchTokens?[key] as Map<String, dynamic>?;

      futures.add(() async {
        final result =
            await nextFetch(branch, stateFor(branch), branchContinue);
        if (result != null) {
          anySuccess = true;
          streams[key] = result.items;
          if (result.continueParams != null) {
            newMultiContinue[key] = result.continueParams;
          }
        }
      }());
    }

    await Future.wait(futures);

    if (!anySuccess) return null;

    final interleaved = _multiSort<String>(streams, sortMode);
    final seen = <String>{};
    final deduped = <SearchItem>[];
    for (final item in interleaved) {
      if (seen.add(item.url)) deduped.add(item);
    }

    return SearchResponse(
      items: deduped,
      continueParams: newMultiContinue.isNotEmpty
          ? {continueBucketKey: newMultiContinue}
          : null,
    );
  }

  /// "hrithik roshan + shahid kapoor" cannot be expressed as a single
  /// CirrusSearch query — see the note above buildQuery. So instead: split
  /// on "+", run each segment as its own fully independent search (with
  /// every other filter — category, depicts, license, format, etc. — still
  /// applied identically to each), then merge and dedupe client-side. This
  /// nests naturally with every stage below it: each segment's own request
  /// still fans out per statement/category/depicts/format further down.
  Future<SearchResponse?> fetchPage(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    final queryText = state.queryText.trim();
    final segments = queryText
        .split(multiQuerySeparator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.length <= 1) {
      return _fetchPageForQuery(state, continueParams: continueParams);
    }

    return _fanOutFetch<String>(
      branches: segments,
      keyOf: (segment) => segment,
      stateFor: (segment) => state.copyWith(queryText: segment),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForQuery(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_query',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForQuery(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    // Union mode with 2+ include statements: Cirrus can't reliably OR a
    // statement clause together with the rest of the active filters in one
    // query string, so each statement runs as its own independent search
    // (with every other filter, including exclude-statements, still
    // applied) and results are merged client-side — see _fanOutFetch.
    final includeStatements = state.statementsInclude.toList();

    if (!state.statementsUnion || includeStatements.length <= 1) {
      return _fetchPageForCategory(state, continueParams: continueParams);
    }

    return _fanOutFetch<WikidataStatement>(
      branches: includeStatements,
      keyOf: (stmt) => '${stmt.property.qid}=${stmt.value.qid}',
      stateFor: (stmt) => state.copyWith(statementsInclude: {stmt}),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForCategory(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_stmt',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForCategory(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    // Same fan-out pattern for category union mode — deepCategoryMode,
    // excludeCategories, and everything else carry over unchanged onto
    // each single-category branch.
    final includeCategories = state.categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (!state.categoriesUnion || includeCategories.length <= 1) {
      return _fetchPageForDepicts(state, continueParams: continueParams);
    }

    return _fanOutFetch<String>(
      branches: includeCategories,
      keyOf: (cat) => cat,
      stateFor: (cat) => state.copyWith(categories: {cat}),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForDepicts(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_cat',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForDepicts(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    // Same fan-out pattern again for depicts union mode — depictsExclude
    // and everything else carry over unchanged onto each single-entity
    // branch.
    final includeDepicts = state.depictsInclude.toList();

    if (!state.depictsUnion || includeDepicts.length <= 1) {
      return _fetchPageForFormat(state, continueParams: continueParams);
    }

    return _fanOutFetch<DepictsEntity>(
      branches: includeDepicts,
      keyOf: (entity) => entity.qid,
      stateFor: (entity) => state.copyWith(depictsInclude: {entity}),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForFormat(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_depicts',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForFormat(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    if (state.formats.isEmpty) {
      return _fetchSingle(state,
          continueParams: continueParams, overrideFormat: null);
    }

    // Same fan-out pattern once more, this time branching on selected file
    // format rather than a SearchState field — the format is applied via
    // _fetchSingle's overrideFormat argument instead of a copyWith, so
    // stateFor leaves the shared state untouched and nextFetch uses the
    // branch (the format itself) directly.
    return _fanOutFetch<FileFormat>(
      branches: state.formats.toList(),
      keyOf: (format) => format.name,
      stateFor: (_) => state,
      nextFetch: (format, branchState, branchContinue) => _fetchSingle(
          branchState,
          continueParams: branchContinue,
          overrideFormat: format),
      continueParams: continueParams,
      continueBucketKey: '_multi',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchSingle(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    FileFormat? overrideFormat,
  }) async {
    try {
      final built = buildQuery(state, overrideFormat: overrideFormat);

      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'uselang': 'en',
        'generator': 'search',
        'gsrsearch': built.srsearch,
        'gsrlimit': '$pageSize',
        'gsrinfo': 'totalhits|suggestion',
        'gsrprop': 'size|wordcount|timestamp|snippet',
        'prop': 'info|imageinfo',
        'inprop': 'url',
        'gsrnamespace': '6',
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      switch (state.sortMode) {
        case SortMode.relevance:
        case SortMode.titleMatch:
          break;
        case SortMode.newestEdited:
          params['gsrsort'] = 'last_edit_desc';
          break;
        case SortMode.oldestEdited:
          params['gsrsort'] = 'last_edit_asc';
          break;
        case SortMode.newestCreated:
          params['gsrsort'] = 'create_timestamp_desc';
          break;
        case SortMode.oldestCreated:
          params['gsrsort'] = 'create_timestamp_asc';
          break;
      }

      if (continueParams != null) {
        for (final entry in continueParams.entries) {
          params[entry.key] = entry.value.toString();
        }
      }

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      
      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextContinue = data['continue'] as Map<String, dynamic>?;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      // Requested via gsrinfo above; was previously fetched and silently
      // discarded. Only meaningful here, at the leaf request — see the
      // note on SearchResponse.totalHits for why fan-out doesn't try to
      // combine these across branches.
      final searchInfo = data['query']?['searchinfo'] as Map<String, dynamic>?;
      final totalHits = searchInfo?['totalhits'] as int?;
      final suggestion = searchInfo?['suggestion'] as String?;

      final items = <SearchItem>[];
      for (final page in pages.values) {
        final infoList = page['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) continue;

        final info = infoList.first as Map<String, dynamic>;
        final rawTitle = page['title'] as String? ?? '';

        final item = _itemFromImageInfo(
          info,
          rawTitle: rawTitle,
          snippet: _stripHtml(page['snippet'] as String? ?? rawTitle),
          timestamp: page['timestamp'] as String?,
          descriptionUrl: page['fullurl'] as String?,
        );
        if (item != null) items.add(item);
      }

      final filteredItems = overrideFormat == null
          ? items.where((item) => _matchesMacroFormat(item, state.formats)).toList()
          : items;

      return SearchResponse(
        items: filteredItems,
        continueParams: nextContinue,
        totalHits: totalHits,
        suggestion: suggestion,
      );
    } catch (_) {
      return null;
    }
  }

  List<SearchItem> _multiSort<K>(Map<K, List<SearchItem>> streams, SortMode mode) {
    final result = <SearchItem>[];

    if (mode == SortMode.relevance) {
      bool added = true;
      int i = 0;
      while (added) {
        added = false;
        for (final list in streams.values) {
          if (i < list.length) {
            result.add(list[i]);
            added = true;
          }
        }
        i++;
      }
    } else {
      for (final list in streams.values) {
        result.addAll(list);
      }

      if (mode == SortMode.titleMatch) {
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      } else {
        result.sort((a, b) {
          final tA = a.timestamp ?? '';
          final tB = b.timestamp ?? '';
          final cmp = tA.compareTo(tB);
          if (mode == SortMode.newestCreated || mode == SortMode.newestEdited) {
            return -cmp; 
          }
          return cmp; 
        });
      }
    }

    return result;
  }

  String _getMimeString(FileFormat format) {
    switch (format) {
      case FileFormat.jpg:
      case FileFormat.jpeg: return 'image/jpeg';
      case FileFormat.png: return 'image/png';
      case FileFormat.svg: return 'image/svg+xml';
      case FileFormat.gif: return 'image/gif';
      case FileFormat.tif:
      case FileFormat.tiff: return 'image/tiff';
      case FileFormat.webp: return 'image/webp';
      case FileFormat.pdf: return 'application/pdf';
      case FileFormat.djvu: return 'image/vnd.djvu'; 
      case FileFormat.ogg:
      case FileFormat.oga: return 'audio/ogg';
      case FileFormat.ogv: return 'video/ogg';
      case FileFormat.mp3: return 'audio/mpeg';
      case FileFormat.wav: return 'audio/wav';
      case FileFormat.webm: return 'video/webm';
      case FileFormat.mp4: return 'video/mp4';
    }
  }

  bool _matchesMacroFormat(SearchItem item, Set<FileFormat> formats) {
    if (formats.isEmpty) return true;
    final ext = item.extension;
    final mime = item.mime.toLowerCase();

    for (final format in formats) {
      switch (format) {
        case FileFormat.jpg: if (ext == 'jpg' || mime == 'image/jpeg') return true; break;
        case FileFormat.jpeg: if (ext == 'jpeg' || mime == 'image/jpeg') return true; break;
        case FileFormat.png: if (ext == 'png' || mime == 'image/png') return true; break;
        case FileFormat.svg: if (ext == 'svg' || mime == 'image/svg+xml') return true; break;
        case FileFormat.gif: if (ext == 'gif' || mime == 'image/gif') return true; break;
        case FileFormat.tif: if (ext == 'tif' || mime == 'image/tiff') return true; break;
        case FileFormat.tiff: if (ext == 'tiff' || mime == 'image/tiff') return true; break;
        case FileFormat.webp: if (ext == 'webp' || mime == 'image/webp') return true; break;
        case FileFormat.pdf: if (ext == 'pdf' || mime == 'application/pdf') return true; break;
        case FileFormat.djvu: if (ext == 'djvu') return true; break;
        case FileFormat.ogg: if (ext == 'ogg' || mime.contains('ogg')) return true; break;
        case FileFormat.oga: if (ext == 'oga' || mime.contains('ogg')) return true; break;
        case FileFormat.ogv: if (ext == 'ogv' || mime.contains('ogg')) return true; break;
        case FileFormat.mp3: if (ext == 'mp3' || mime.contains('mpeg') || mime.contains('mp3')) return true; break;
        case FileFormat.wav: if (ext == 'wav' || mime.contains('wav')) return true; break;
        case FileFormat.webm: if (ext == 'webm' || mime.contains('webm')) return true; break;
        case FileFormat.mp4: if (ext == 'mp4' || mime.contains('mp4')) return true; break;
      }
    }
    return false;
  }

  List<SearchItem> applyClientSort(List<SearchItem> items, SortMode sortMode) {
    if (sortMode != SortMode.titleMatch) return items;
    final sorted = List<SearchItem>.from(items);
    sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return sorted;
  }

  static String _stripHtml(String s) {
    return s.replaceAll(_htmlTagRegex, '').trim();
  }
}
