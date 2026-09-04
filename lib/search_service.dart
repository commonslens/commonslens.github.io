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
  /// which of the call sites below fetched it — a single lookup, a search
  /// page, a geosearch page, or an author's upload list all return this
  /// same shape). Every extmetadata field lives behind [_extValue] so
  /// Artist/License/Categories/etc. are read identically everywhere.
  /// Returns null when there's no usable original URL, mirroring what each
  /// call site already treated as "skip this result".
  ///
  /// [latitude]/[longitude] are for the one call site (geosearch) that has
  /// authoritative, backend-resolved coordinates for every item (from
  /// MediaWiki's own `prop=coordinates`) rather than the often-absent
  /// GPSLatitude/GPSLongitude extmetadata strings every item already gets
  /// via [_extValue] below — see [SearchItem.resolvedLatitude] for how the
  /// two sources combine.

  static SearchItem? _itemFromImageInfo(
    Map<String, dynamic> info, {
    required String rawTitle,
    required String snippet,
    String? timestamp,
    String? descriptionUrl,
    String? uploaderFallback,
    double? latitude,
    double? longitude,
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
      latitude: latitude,
      longitude: longitude,
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

  /// Every stored revision of a file, newest first — its upload/edit
  /// history (re-uploads, crops, rotations, retouches), not the search
  /// result's current version. Passing `iilimit` above 1 is what turns a
  /// normal imageinfo request into a history request.
  Future<List<FileRevision>> fetchFileHistory(
    String filename, {
    int limit = 20,
  }) async {
    try {
      final title = filename.startsWith('File:') ? filename : 'File:$filename';
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'imageinfo',
        'iiprop': 'timestamp|url|user|size|comment|dimensions',
        'iilimit': '$limit',
        'iiurlwidth': '320',
      });

      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return const [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // Same failure class fetchPage/fetchAuthorImages guard against — a
      // batch imageinfo call can come back HTTP 200 with a top-level
      // `error` key instead of `query.pages` rather than throwing, so
      // check for it explicitly instead of letting a null pages map
      // silently look like "no history".
      if (data.containsKey('error')) return const [];

      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
      if (pages.isEmpty) return const [];
      final page = pages.values.first as Map<String, dynamic>;
      if (page.containsKey('missing')) return const [];

      final infoList = page['imageinfo'] as List? ?? [];
      return infoList
          .map((raw) {
            final info = raw as Map<String, dynamic>;
            final originalUrl = info['url'] as String? ?? '';
            final thumburl = info['thumburl'] as String? ?? '';
            return FileRevision(
              url: originalUrl,
              thumb: thumburl.isNotEmpty ? thumburl : originalUrl,
              timestamp: info['timestamp'] as String?,
              uploader: info['user']?.toString() ?? '',
              comment: info['comment'] as String? ?? '',
              size: info['size'] as int? ?? 0,
              width: info['width'] as int? ?? 0,
              height: info['height'] as int? ?? 0,
            );
          })
          .where((rev) => rev.url.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Reads a file's Structured Data on Commons (SDC) entity back — its
  /// multilingual captions and every structured statement (creator,
  /// institution, coordinates of depicted place, inception date, and
  /// anything else editors have added), as opposed to *filtering* on one
  /// of those via haswbstatement: (see buildQuery / SearchState's
  /// statementsInclude). Two requests: resolve the file's pageid (SDC
  /// entities are addressed as "M<pageid>", not by title), then fetch that
  /// entity from Commons' own Wikibase API. Property/value labels are
  /// resolved in a third, batched call against www.wikidata.org, since
  /// Commons SDC reuses Wikidata's own P-/Q-code space rather than
  /// maintaining a separate one.
  Future<StructuredDataResult?> fetchStructuredData(String filename) async {
    try {
      final title = filename.startsWith('File:') ? filename : 'File:$filename';

      final infoUri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'info',
      });
      final infoRes = await _client.get(infoUri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 10));
      if (infoRes.statusCode != 200) return null;

      final infoData = jsonDecode(infoRes.body) as Map<String, dynamic>;
      if (infoData.containsKey('error')) return null;
      final pages =
          (infoData['query']?['pages'] as Map<String, dynamic>?) ?? {};
      if (pages.isEmpty) return null;
      final page = pages.values.first as Map<String, dynamic>;
      if (page.containsKey('missing')) return null;
      final pageId = page['pageid'];
      if (pageId == null) return null;
      final mid = 'M$pageId';

      final entityUri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'wbgetentities',
        'format': 'json',
        'origin': '*',
        'ids': mid,
      });
      final entityRes = await _client.get(entityUri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 10));
      if (entityRes.statusCode != 200) return null;

      final entityData = jsonDecode(entityRes.body) as Map<String, dynamic>;
      if (entityData.containsKey('error')) return null;
      final entity = entityData['entities']?[mid] as Map<String, dynamic>?;
      if (entity == null) return null;

      final labelsRaw = entity['labels'] as Map<String, dynamic>? ?? {};
      final captions = <String, String>{
        for (final entry in labelsRaw.entries)
          entry.key:
              (entry.value as Map<String, dynamic>)['value'] as String? ?? '',
      };

      final statementsRaw = entity['statements'] as Map<String, dynamic>? ?? {};

      // Collect every P-code, plus every Q-code among the values — one
      // batched label lookup at the end instead of one request per claim.
      final idsToResolve = <String>{};
      final rawClaims = <MapEntry<String, Map<String, dynamic>>>[];

      for (final propEntry in statementsRaw.entries) {
        final propertyId = propEntry.key;
        idsToResolve.add(propertyId);
        final claims = propEntry.value as List? ?? [];
        for (final claim in claims) {
          final mainsnak = (claim as Map<String, dynamic>)['mainsnak']
              as Map<String, dynamic>?;
          if (mainsnak == null) continue;
          rawClaims.add(MapEntry(propertyId, mainsnak));
          final entityId = _entityIdFromSnak(mainsnak);
          if (entityId != null) idsToResolve.add(entityId);
        }
      }

      final labels = await _resolveWikidataLabels(idsToResolve);

      final statements = rawClaims.map((entry) {
        final propertyId = entry.key;
        final snak = entry.value;
        final valueEntityId = _entityIdFromSnak(snak);
        final display = valueEntityId != null
            ? (labels[valueEntityId] ?? valueEntityId)
            : _formatSnakValue(snak);
        return StructuredDataStatement(
          propertyId: propertyId,
          propertyLabel: labels[propertyId] ?? propertyId,
          valueDisplay: display,
          valueEntityId: valueEntityId,
        );
      }).toList();

      return StructuredDataResult(
          mid: mid, captions: captions, statements: statements);
    } catch (_) {
      return null;
    }
  }

  /// The Q-code of a claim's value, if that value is itself a Wikibase
  /// item (e.g. creator, institution) — null for literal values (text,
  /// dates, coordinates, quantities) and for novalue/somevalue snaks.
  String? _entityIdFromSnak(Map<String, dynamic> snak) {
    if (snak['snaktype'] != 'value') return null;
    final datavalue = snak['datavalue'] as Map<String, dynamic>?;
    if (datavalue == null || datavalue['type'] != 'wikibase-entityid') {
      return null;
    }
    final value = datavalue['value'] as Map<String, dynamic>?;
    return value?['id'] as String?;
  }

  /// Best-effort human-readable text for a literal (non-entity) claim
  /// value — covers every Wikibase datatype SDC statements commonly use.
  String _formatSnakValue(Map<String, dynamic> snak) {
    if (snak['snaktype'] == 'novalue') return '(no value)';
    if (snak['snaktype'] == 'somevalue') return '(unknown value)';

    final datavalue = snak['datavalue'] as Map<String, dynamic>?;
    if (datavalue == null) return '';
    final type = datavalue['type'] as String?;
    final value = datavalue['value'];

    switch (type) {
      case 'string':
        return value?.toString() ?? '';
      case 'monolingualtext':
        final map = value as Map<String, dynamic>?;
        return map?['text'] as String? ?? '';
      case 'time':
        final map = value as Map<String, dynamic>?;
        final raw = map?['time'] as String? ?? '';
        // Wikibase time strings look like "+2020-01-15T00:00:00Z" — strip
        // the leading sign and clock component for a readable date.
        return raw.replaceFirst('+', '').split('T').first;
      case 'globecoordinate':
        final map = value as Map<String, dynamic>?;
        final lat = map?['latitude'];
        final lon = map?['longitude'];
        return (lat != null && lon != null) ? '$lat, $lon' : '';
      case 'quantity':
        final map = value as Map<String, dynamic>?;
        final amount = map?['amount'] as String? ?? '';
        return amount.replaceFirst('+', '');
      default:
        return value?.toString() ?? '';
    }
  }

  /// Batched label lookup for a mix of Wikidata P-codes and Q-codes.
  /// Always queries www.wikidata.org regardless of which Commons file
  /// referenced the ids — Commons SDC statements point directly into
  /// Wikidata's own id space rather than maintaining a separate one.
  Future<Map<String, String>> _resolveWikidataLabels(
    Set<String> ids, {
    String language = 'en',
  }) async {
    if (ids.isEmpty) return {};
    final result = <String, String>{};
    try {
      final idList = ids.toList();
      // wbgetentities caps at 50 ids per request.
      for (var i = 0; i < idList.length; i += 50) {
        final batch = idList.skip(i).take(50).toList();
        final uri = Uri.https('www.wikidata.org', '/w/api.php', {
          'action': 'wbgetentities',
          'format': 'json',
          'origin': '*',
          'ids': batch.join('|'),
          'props': 'labels',
          'languages': language,
        });
        final res = await _client.get(uri, headers: {
          'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
        }).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data.containsKey('error')) continue;
        final entities = data['entities'] as Map<String, dynamic>? ?? {};
        for (final entry in entities.entries) {
          final labels = (entry.value as Map<String, dynamic>)['labels']
              as Map<String, dynamic>?;
          final label = labels?[language]?['value'] as String?;
          if (label != null) result[entry.key] = label;
        }
      }
    } catch (_) {
      // Best-effort — partial results (raw ids standing in for
      // unresolved labels) are still useful, so failures here don't
      // invalidate the whole fetchStructuredData call.
    }
    return result;
  }

  /// Pure geographic browse via MediaWiki's `list=geosearch` generator
  /// combined directly with `prop=imageinfo` AND `prop=coordinates` (one
  /// request, same shape as _fetchSingle's generator=search). Deliberately
  /// NOT routed through buildQuery/CirrusSearch: this returns whatever has
  /// coordinates in the requested area, with no relevance ranking and none
  /// of SearchState's other filters applied. nearcoord:/neartitle: (used
  /// elsewhere in buildQuery) are the CirrusSearch-keyword version of a
  /// radius search, but can only ever be one clause ANDed into a
  /// text/filter query — this is for "what's physically in this area",
  /// full stop.
  ///
  /// `prop=coordinates` is requested alongside imageinfo specifically so
  /// every returned [SearchItem] carries real, resolved
  /// [SearchItem.latitude]/[SearchItem.longitude] — without it, items would
  /// come back with no usable map coordinates at all (the `ggsprop=dist`
  /// value used for sorting below is a distance, not a position). A page
  /// can carry more than one coordinate entry (rare, but the API allows
  /// it); the primary one (`primary: ''`, or simply the first if none is
  /// marked primary) is what gets used.
  ///
  /// Exactly one of two modes:
  /// - Radius: pass [lat]/[lng] (with optional [radiusMeters]).
  /// - Rectangle: pass [boundingBox] as [northLat, westLng, southLat,
  ///   eastLng] — the real mechanism for a literal bounding-box search
  ///   (there is no "bounded:" CirrusSearch keyword; that name refers to
  ///   nearcoord:/neartitle:'s radius search in Wikimedia's own docs).
  Future<SearchResponse?> geosearch({
    double? lat,
    double? lng,
    double radiusMeters = 1000,
    List<double>? boundingBox,
    int limit = pageSize,
    Map<String, dynamic>? continueParams,
  }) async {
    final hasCoord = lat != null && lng != null;
    final hasBox = boundingBox != null && boundingBox.length == 4;
    if (!hasCoord && !hasBox) return null;

    try {
      final params = <String, String>{
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'generator': 'geosearch',
        'ggsnamespace': '6',
        'ggslimit': '$limit',
        'ggsprop': 'dist',
        'prop': 'coordinates|imageinfo',
        'coprop': 'type|dim',
        'colimit': '$limit',
        'inprop': 'url',
        'iiprop': 'url|size|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      if (hasBox) {
        // top-left lat|lng, then bottom-right lat|lng.
        params['ggsbbox'] =
            '${boundingBox[0]}|${boundingBox[1]}|${boundingBox[2]}|${boundingBox[3]}';
      } else {
        // GeoData's own documented radius ceiling.
        final clampedRadius = radiusMeters.clamp(10, 10000);
        params['ggscoord'] = '$lat|$lng';
        params['ggsradius'] = '$clampedRadius';
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
      if (data.containsKey('error')) return null;

      final nextContinue = data['continue'] as Map<String, dynamic>?;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      // (distance, item) pairs, sorted nearest-first for radius mode — page
      // iteration order over a Map isn't guaranteed to match geosearch's
      // own ordering. Bounding-box mode has no single "center" to sort by,
      // so items without a `dist` value (always true for bbox mode) fall
      // back to the order the API returned them in via their original
      // index, rather than being scattered by an infinite sort key.
      final scored = <MapEntry<double, SearchItem>>[];
      var fallbackIndex = 0.0;
      for (final page in pages.values) {
        final p = page as Map<String, dynamic>;
        final infoList = p['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) continue;
        final info = infoList.first as Map<String, dynamic>;
        final rawTitle = p['title'] as String? ?? '';

        // A page can carry more than one coordinate entry — take the one
        // explicitly marked primary, or fall back to the first if none is
        // (the overwhelming common case: exactly one entry, unmarked).
        final coordList = p['coordinates'] as List?;
        double? itemLat;
        double? itemLng;
        if (coordList != null && coordList.isNotEmpty) {
          final primary = coordList.firstWhere(
            (c) => (c as Map<String, dynamic>)['primary'] != null,
            orElse: () => coordList.first,
          ) as Map<String, dynamic>;
          itemLat = (primary['lat'] as num?)?.toDouble();
          itemLng = (primary['lon'] as num?)?.toDouble();
        }

        final item = _itemFromImageInfo(
          info,
          rawTitle: rawTitle,
          snippet: rawTitle,
          descriptionUrl: p['fullurl'] as String?,
          latitude: itemLat,
          longitude: itemLng,
        );
        if (item == null) continue;

        final dist = (p['dist'] as num?)?.toDouble() ?? fallbackIndex++;
        scored.add(MapEntry(dist, item));
      }
      scored.sort((a, b) => a.key.compareTo(b.key));

      return SearchResponse(
        items: scored.map((e) => e.value).toList(),
        continueParams: nextContinue,
      );
    } catch (_) {
      return null;
    }
  }

  /// Every Wikimedia page (any language, any project) that currently
  /// embeds [filename] — a real-world usage signal distinct from anything
  /// CirrusSearch indexes. `guprop=url` asks for a ready-to-open link per
  /// entry rather than making the caller reconstruct one from wiki+title.
  Future<List<GlobalUsageEntry>> fetchGlobalUsage(
    String filename, {
    int limit = 500,
  }) async {
    try {
      final title = filename.startsWith('File:') ? filename : 'File:$filename';
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'globalusage',
        'guprop': 'url',
        'gulimit': '$limit',
      });

      final response = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return const [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.containsKey('error')) return const [];

      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
      if (pages.isEmpty) return const [];
      final page = pages.values.first as Map<String, dynamic>;
      if (page.containsKey('missing')) return const [];

      final usageList = page['globalusage'] as List? ?? [];
      return usageList.map((raw) {
        final entry = raw as Map<String, dynamic>;
        return GlobalUsageEntry(
          wiki: entry['wiki'] as String? ?? '',
          title: entry['title'] as String? ?? '',
          url: entry['url'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
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
      final res = await _client.get(uri).timeout(const Duration(seconds: 5));
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
      final res = await _client.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 5));
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

  /// Human-readable label for a raw byte count — display only, never fed
  /// back into a query (filesize: clauses always use raw bytes, see
  /// buildQuery).
  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
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
          .map((c) =>
              state.deepCategoryMode ? 'deepcat:"$c"' : 'incategory:"$c"')
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
        chips.add(QueryChipData(
            id: 'excludeCategory:$safe', label: 'Not in deep category: $safe'));
      } else {
        parts.add('-incategory:"$safe"');
        chips.add(QueryChipData(
            id: 'excludeCategory:$safe', label: 'Not in category: $safe'));
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

    // License (structured-data statement — see _licenseClauses). A file
    // only ever carries one license, so selecting more than one is always
    // an OR match ("any of these"), never an AND. With 2+ selected, Cirrus
    // can't reliably OR this clause together with every other active
    // AND'd filter in one query string (same precedence hazard noted
    // elsewhere in this file), so this join is a preview only — the real
    // OR execution happens via per-license fan-out in _fetchPageForLicense
    // further down, same shape as categories/depicts/statements union mode.
    final selectedLicenses = state.licensePresets.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (selectedLicenses.length == 1) {
      final clause = _licenseClauses[selectedLicenses.first];
      if (clause != null) {
        parts.add(clause);
        chips.add(QueryChipData(
          id: 'license:${selectedLicenses.first.name}',
          label: licensePresetLabel(selectedLicenses.first),
        ));
      }
    } else if (selectedLicenses.length > 1) {
      final clauses = selectedLicenses
          .map((l) => _licenseClauses[l])
          .whereType<String>()
          .toList();
      if (clauses.isNotEmpty) parts.add(clauses.join(' OR '));
      for (final l in selectedLicenses) {
        chips.add(QueryChipData(id: 'license:${l.name}', label: licensePresetLabel(l)));
      }
    }

    // Attribution requirement — no CirrusSearch keyword exposes this
    // directly (it's a MediaWiki-computed extmetadata flag derived from
    // the license, not a Wikidata statement, and nothing in Cirrus's own
    // keyword docs/Phabricator covers it), so unlike every other filter in
    // this method it can't be folded into srsearch. It's applied as a
    // client-side post-filter instead — see _matchesAttribution and its
    // call site in _fetchSingleAttempt below. Still surfaced as a chip
    // here so it appears in the active filters bar like everything else.
    if (state.attributionRequired != null) {
      chips.add(QueryChipData(
        id: 'attributionRequired',
        label: state.attributionRequired!
            ? 'Attribution required'
            : 'No attribution required',
      ));
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
    if (state.maxWidth != null && state.maxWidth! > 0) {
      parts.add('filew:<${state.maxWidth}');
      chips.add(QueryChipData(
        id: 'maxWidth',
        label: 'Width ≤ ${state.maxWidth}px',
      ));
    }
    if (state.maxHeight != null && state.maxHeight! > 0) {
      parts.add('fileh:<${state.maxHeight}');
      chips.add(QueryChipData(
        id: 'maxHeight',
        label: 'Height ≤ ${state.maxHeight}px',
      ));
    }

    // filesize: — always raw bytes on the wire; a UI can offer MB/KB and
    // convert before this point, but this method never guesses at units.
    if (state.minFileSizeBytes != null && state.minFileSizeBytes! > 0) {
      parts.add('filesize:>${state.minFileSizeBytes}');
      chips.add(QueryChipData(
        id: 'minFileSize',
        label: 'Size ≥ ${_formatBytes(state.minFileSizeBytes!)}',
      ));
    }
    if (state.maxFileSizeBytes != null && state.maxFileSizeBytes! > 0) {
      parts.add('filesize:<${state.maxFileSizeBytes}');
      chips.add(QueryChipData(
        id: 'maxFileSize',
        label: 'Size ≤ ${_formatBytes(state.maxFileSizeBytes!)}',
      ));
    }

    if (state.colorDepthBits != null && state.colorDepthBits! > 0) {
      parts.add('filebits:${state.colorDepthBits}');
      chips.add(QueryChipData(
        id: 'colorDepth',
        label: '${state.colorDepthBits}-bit color depth',
      ));
    }

    // hastemplate: generalized beyond the hardcoded QualityFilter presets
    // further down — GLAM/institutional sets, granular PD templates, or
    // anything else a template marks. Quoted whenever the name contains a
    // space, same convention as excludeTerms below.
    for (final template in state.templates.toList()..sort()) {
      final safe = template.trim();
      if (safe.isEmpty) continue;
      final token = safe.contains(' ') ? '"$safe"' : safe;
      parts.add('hastemplate:$token');
      chips.add(QueryChipData(id: 'template:$safe', label: 'Template: $safe'));
    }
    for (final template in state.excludeTemplates.toList()..sort()) {
      final safe = template.trim();
      if (safe.isEmpty) continue;
      final token = safe.contains(' ') ? '"$safe"' : safe;
      parts.add('-hastemplate:$token');
      chips.add(QueryChipData(
          id: 'excludeTemplate:$safe', label: 'Not template: $safe'));
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
    // or contradict depictsInclude/Exclude or licensePresets.
    //
    // Union mode (OR) is NOT expressed as a single "A OR B" query string
    // here — mixed with other required clauses (category, license, etc.),
    // Cirrus's OR only binds to its immediately adjacent term, same
    // precedence hazard as the "+"-query bug elsewhere in this file. The
    // real OR execution happens via per-statement fan-out in fetchPage
    // below; this join is just an honest preview of intent.
    final includeStatements = state.statementsInclude.toList()
      ..sort((a, b) => '${a.property.qid}${a.value.qid}'
          .compareTo('${b.property.qid}${b.value.qid}'));

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
      ..sort((a, b) => '${a.property.qid}${a.value.qid}'
          .compareTo('${b.property.qid}${b.value.qid}'))) {
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

    // morelike: — "files similar to these" via CirrusSearch's own
    // similarity engine. Combines with every other clause above (AND),
    // same as everything else in this method; it's just one more term in
    // the joined query string, not a special standalone request.
    final morelike = state.morelikeTitles
        .map((t) {
          final trimmed = t.trim();
          if (trimmed.isEmpty) return '';
          return trimmed.startsWith('File:') ? trimmed : 'File:$trimmed';
        })
        .where((t) => t.isNotEmpty)
        .toList()
      ..sort();
    if (morelike.isNotEmpty) {
      parts.add('morelike:${morelike.join('|')}');
      chips.add(QueryChipData(
        id: 'morelike',
        label: morelike.length == 1
            ? 'Similar to: ${morelike.first.replaceFirst('File:', '')}'
            : 'Similar to ${morelike.length} files',
      ));
    }

    // insource: — matches the file description page's raw wikitext, a
    // different corpus than the analyzed/indexed text `queryText` matches
    // against. Regex mode uses insource:/.../, literal mode wraps in
    // quotes the same way excludeTerms does above.
    final insource = state.insourceText?.trim() ?? '';
    if (insource.isNotEmpty) {
      final token =
          state.insourceRegex ? 'insource:/$insource/' : 'insource:"$insource"';
      parts.add(token);
      chips.add(QueryChipData(id: 'insource', label: 'Source: $insource'));
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

      final listUri =
          Uri.https('commons.wikimedia.org', '/w/api.php', listParams);
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

      final infoUri =
          Uri.https('commons.wikimedia.org', '/w/api.php', infoParams);
      final infoResponse = await _client.get(infoUri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (infoResponse.statusCode != 200) return null;

      final infoData = jsonDecode(infoResponse.body) as Map<String, dynamic>;
      final pages =
          (infoData['query']?['pages'] as Map<String, dynamic>?) ?? {};

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
          // else: this branch is genuinely exhausted (a real, successful
          // response with no further pages) — correctly left out of
          // newMultiContinue so it's not retried again.
        } else {
          // This branch's fetch failed THIS round (network blip, a
          // transient API error that survived _fetchSingleAttempt's own
          // retries, etc.) — that is NOT the same thing as "no more
          // results for this branch." Previously, a failed branch was
          // silently dropped from newMultiContinue, which permanently
          // removed it from every future loadMore — discarding every item
          // still behind it with no error ever surfacing. Instead,
          // preserve its continuation token unchanged (or an empty map as
          // a "retry from page 1" marker, if this was itself page 1) so
          // the next loadMore retries this exact page for this branch
          // rather than abandoning it.
          newMultiContinue[key] = branchContinue ?? <String, dynamic>{};
          // ignore: avoid_print
          print(
              '🔍 [BRANCH FAILED] key=$key — will retry on next loadMore instead of dropping it');
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
      // ignore: avoid_print
      print(
          '🔍 [FETCHPAGE] single-segment path, queryText="${state.queryText}" tab=${state.tab.name} formats=${state.formats}');
      return _fetchPageForQuery(state, continueParams: continueParams);
    }

    // ignore: avoid_print
    print('🔍 [FETCHPAGE] multi-segment "+" path, segments=$segments');

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
      return _fetchPageForLicense(state, continueParams: continueParams);
    }

    return _fanOutFetch<WikidataStatement>(
      branches: includeStatements,
      keyOf: (stmt) => '${stmt.property.qid}=${stmt.value.qid}',
      stateFor: (stmt) => state.copyWith(statementsInclude: {stmt}),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForLicense(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_stmt',
      sortMode: state.sortMode,
    );
  }

  /// Fans out one independent search per selected license when 2+ are
  /// selected — see the note in buildQuery: a file only ever carries one
  /// license, so multi-select is always OR, and Cirrus can't reliably OR
  /// this clause together with the rest of an AND'd query. Every other
  /// active filter (category, depicts, quality, etc.) still applies
  /// identically to each per-license branch.
  Future<SearchResponse?> _fetchPageForLicense(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
  }) async {
    final licenses = state.licensePresets.toList();

    if (licenses.length <= 1) {
      return _fetchPageForCategory(state, continueParams: continueParams);
    }

    return _fanOutFetch<LicensePreset>(
      branches: licenses,
      keyOf: (l) => l.name,
      stateFor: (l) => state.copyWith(licensePresets: {l}),
      nextFetch: (_, branchState, branchContinue) =>
          _fetchPageForCategory(branchState, continueParams: branchContinue),
      continueParams: continueParams,
      continueBucketKey: '_license',
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
  }) {
    return _fetchSingleAttempt(
      state,
      continueParams: continueParams,
      overrideFormat: overrideFormat,
      includeThumbWidth: true,
    );
  }

  /// [includeThumbWidth] controls whether `iiurlwidth` is sent.
  ///
  /// MediaWiki's `generator=search` + `prop=imageinfo` batches every file in
  /// the page through ONE thumbnail-scaling pass. If scaling to
  /// `iiurlwidth` fails for even a single file in that batch — confirmed in
  /// practice with an oversized/malformed TIFF — the API doesn't just skip
  /// that file: the ENTIRE response comes back as a top-level `error`
  /// object (code `urlparamnormal`), still with HTTP 200, and with no
  /// `query` key at all. Previously nothing here checked for that `error`
  /// key, so `data['query']?['pages'] ?? {}` silently evaluated to `{}` —
  /// indistinguishable from a real "0 results" search. One unrelated broken
  /// file could wipe out an entire otherwise-valid page of results with no
  /// error surfaced anywhere.
  ///
  /// Fix: detect that specific error and retry the identical query once
  /// with `iiurlwidth` omitted entirely. With no scaling requested, nothing
  /// needs to be normalized, so nothing can fail this way — every file in
  /// the batch comes back with its full-resolution `url` and no `thumburl`.
  /// `_itemFromImageInfo` already falls back to the original url whenever
  /// `thumburl` is absent, so no items are lost; only that one page's grid
  /// thumbnails are briefly full-res instead of scaled.
  Future<SearchResponse?> _fetchSingleAttempt(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    FileFormat? overrideFormat,
    required bool includeThumbWidth,
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
        if (includeThumbWidth) 'iiurlwidth': '320',
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

      // ignore: avoid_print
      print(
          '🔍 [REQUEST] tab=${state.tab.name} formats=${state.formats} overrideFormat=$overrideFormat\n🔍 [REQUEST URL] $uri');

      // Transient failures (dropped connection, timeout, a momentary 5xx
      // from the API cluster) are common enough on a public API under load
      // that treating the first failure as final would routinely and
      // needlessly cost real results. Retry a couple of times with a short
      // backoff before giving up — only genuine, repeated failures fall
      // through to null (which _fanOutFetch now preserves for a later
      // retry rather than discarding, and a non-fan-out single search
      // surfaces as a real error rather than a false "no results").
      http.Response? response;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          final candidate = await _client.get(uri, headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          }).timeout(const Duration(seconds: 15));

          if (candidate.statusCode == 200 || candidate.statusCode < 500) {
            response = candidate;
            break;
          }
          // ignore: avoid_print
          print(
              '🔍 [RETRY $attempt/3] HTTP ${candidate.statusCode} — retrying');
        } catch (e) {
          // ignore: avoid_print
          print('🔍 [RETRY $attempt/3] network error: $e');
        }
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      if (response == null) {
        // ignore: avoid_print
        print('🔍 [GIVE UP] all 3 attempts failed');
        return null;
      }

      // ignore: avoid_print
      print('🔍 [RESPONSE ${response.statusCode}] ${response.body}');

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final apiError = data['error'] as Map<String, dynamic>?;
      if (apiError != null) {
        final errorCode = apiError['code'] as String?;

        // ignore: avoid_print
        print(
            '🔍 [API ERROR] code=$errorCode info=${apiError['info']} includeThumbWidth=$includeThumbWidth');

        // The one specific, recoverable case: retry once with thumbnail
        // scaling turned off entirely, so nothing can fail to normalize.
        if (errorCode == 'urlparamnormal' && includeThumbWidth) {
          // ignore: avoid_print
          print('🔍 [RETRY] retrying without iiurlwidth');
          return _fetchSingleAttempt(
            state,
            continueParams: continueParams,
            overrideFormat: overrideFormat,
            includeThumbWidth: false,
          );
        }

        // Any other API-level error (or a repeat failure even without
        // thumbnails) is a genuine failure, not an empty result — return
        // null so the caller surfaces a real error instead of a false
        // "no media found".
        return null;
      }

      final nextContinue = data['continue'] as Map<String, dynamic>?;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      // Requested via gsrinfo above; was previously fetched and silently
      // discarded. Only meaningful here, at the leaf request — see the
      // note on SearchResponse.totalHits for why fan-out doesn't try to
      // combine these across branches.
      final searchInfo = data['query']?['searchinfo'] as Map<String, dynamic>?;
      final totalHits = searchInfo?['totalhits'] as int?;
      final suggestion = searchInfo?['suggestion'] as String?;

      // ignore: avoid_print
      print(
          '🔍 [PARSE] pages.length=${pages.length} totalhits=$totalHits suggestion=$suggestion');

      final items = <SearchItem>[];
      for (final page in pages.values) {
        final infoList = page['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) {
          // ignore: avoid_print
          print(
              '🔍 [SKIP] title=${page['title']} — no imageinfo (missing=${page['missing']}, invalid=${page['invalid']})');
          continue;
        }

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

      var filteredItems = overrideFormat == null
          ? items
              .where((item) => _matchesMacroFormat(item, state.formats))
              .toList()
          : items;

      // Client-side only — see the note in buildQuery on why attribution
      // requirement can't be expressed as a CirrusSearch keyword. This can
      // only filter items already present on the page just fetched, so
      // (same limitation as the format filter above) a page can come back
      // with fewer than pageSize items even when more would exist further
      // into the underlying, unfiltered result set.
      if (state.attributionRequired != null) {
        filteredItems = filteredItems
            .where((item) =>
                _matchesAttribution(item, state.attributionRequired!))
            .toList();
      }

      // ignore: avoid_print
      print(
          '🔍 [RESULT] rawItems=${items.length} filteredItems=${filteredItems.length} hasMore=${nextContinue != null}');

      return SearchResponse(
        items: filteredItems,
        continueParams: nextContinue,
        totalHits: totalHits,
        suggestion: suggestion,
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('🔍 [EXCEPTION] $e\n$st');
      return null;
    }
  }

  List<SearchItem> _multiSort<K>(
      Map<K, List<SearchItem>> streams, SortMode mode) {
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
        result.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
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
      case FileFormat.jpeg:
        return 'image/jpeg';
      case FileFormat.png:
        return 'image/png';
      case FileFormat.svg:
        return 'image/svg+xml';
      case FileFormat.gif:
        return 'image/gif';
      case FileFormat.tif:
      case FileFormat.tiff:
        return 'image/tiff';
      case FileFormat.webp:
        return 'image/webp';
      case FileFormat.pdf:
        return 'application/pdf';
      case FileFormat.djvu:
        return 'image/vnd.djvu';
      case FileFormat.ogg:
      case FileFormat.oga:
        return 'audio/ogg';
      case FileFormat.ogv:
        return 'video/ogg';
      case FileFormat.mp3:
        return 'audio/mpeg';
      case FileFormat.wav:
        return 'audio/wav';
      case FileFormat.webm:
        return 'video/webm';
      case FileFormat.mp4:
        return 'video/mp4';
    }
  }

  /// Best-effort match against the extmetadata `AttributionRequired` flag
  /// — see the note in buildQuery for why this is a client-side filter
  /// rather than a query clause. A file with no value at all for this
  /// field (rare, but it happens) can't be confidently said to match
  /// either state, so it's excluded from both "required" and "not
  /// required" rather than guessed at.
  bool _matchesAttribution(SearchItem item, bool required) {
    final raw = item.attributionRequired.trim().toLowerCase();
    if (raw.isEmpty) return false;
    final isRequired = raw == 'true' || raw == 'yes' || raw == '1';
    return isRequired == required;
  }

  bool _matchesMacroFormat(SearchItem item, Set<FileFormat> formats) {
    if (formats.isEmpty) return true;
    final ext = item.extension;
    final mime = item.mime.toLowerCase();

    for (final format in formats) {
      switch (format) {
        case FileFormat.jpg:
          if (ext == 'jpg' || mime == 'image/jpeg') return true;
          break;
        case FileFormat.jpeg:
          if (ext == 'jpeg' || mime == 'image/jpeg') return true;
          break;
        case FileFormat.png:
          if (ext == 'png' || mime == 'image/png') return true;
          break;
        case FileFormat.svg:
          if (ext == 'svg' || mime == 'image/svg+xml') return true;
          break;
        case FileFormat.gif:
          if (ext == 'gif' || mime == 'image/gif') return true;
          break;
        case FileFormat.tif:
          if (ext == 'tif' || mime == 'image/tiff') return true;
          break;
        case FileFormat.tiff:
          if (ext == 'tiff' || mime == 'image/tiff') return true;
          break;
        case FileFormat.webp:
          if (ext == 'webp' || mime == 'image/webp') return true;
          break;
        case FileFormat.pdf:
          if (ext == 'pdf' || mime == 'application/pdf') return true;
          break;
        case FileFormat.djvu:
          if (ext == 'djvu') return true;
          break;
        case FileFormat.ogg:
          if (ext == 'ogg' || mime.contains('ogg')) return true;
          break;
        case FileFormat.oga:
          if (ext == 'oga' || mime.contains('ogg')) return true;
          break;
        case FileFormat.ogv:
          if (ext == 'ogv' || mime.contains('ogg')) return true;
          break;
        case FileFormat.mp3:
          if (ext == 'mp3' || mime.contains('mpeg') || mime.contains('mp3'))
            return true;
          break;
        case FileFormat.wav:
          if (ext == 'wav' || mime.contains('wav')) return true;
          break;
        case FileFormat.webm:
          if (ext == 'webm' || mime.contains('webm')) return true;
          break;
        case FileFormat.mp4:
          if (ext == 'mp4' || mime.contains('mp4')) return true;
          break;
      }
    }
    return false;
  }

  List<SearchItem> applyClientSort(List<SearchItem> items, SortMode sortMode) {
    if (sortMode != SortMode.titleMatch) return items;
    final sorted = List<SearchItem>.from(items);
    sorted
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return sorted;
  }

  static String _stripHtml(String s) {
    return s.replaceAll(_htmlTagRegex, '').trim();
  }
}

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
    if (prefix != null && prefix.trim().isNotEmpty)
      params['acprefix'] = prefix.trim();
    if (cursor != null) params['accontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await SearchService._client
          .get(uri); // Assumes _client is accessible or make it public
      if (res.statusCode != 200)
        return (items: <CategoryItem>[], nextCursor: null);

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
    if (prefix != null && prefix.trim().isNotEmpty)
      params['apprefix'] = prefix.trim();
    if (cursor != null) params['apcontinue'] = cursor;

    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);
      final res = await SearchService._client.get(uri);
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
