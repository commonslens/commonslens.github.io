part of 'search_service.dart';

mixin _SearchAssetOperations {
  WikimediaTransport get _transport;
  WikimediaResponseMapper get _responseMapper;

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
        'iiprop': 'url|size|sha1|mime|extmetadata|user|dimensions',
        'iiurlwidth': '320',
      };

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);

      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15));

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

      return _responseMapper.itemFromImageInfo(
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

      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15));

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
  /// entities are addressed as `M<pageid>`, not by title), then fetch that
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
      final infoRes = await _transport.get(infoUri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 10));
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
      final entityRes = await _transport.get(entityUri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 10));
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
          final entityId = _responseMapper.entityIdFromSnak(mainsnak);
          if (entityId != null) idsToResolve.add(entityId);
        }
      }

      final labels = await _resolveWikidataLabels(idsToResolve);

      final statements = rawClaims.map((entry) {
        final propertyId = entry.key;
        final snak = entry.value;
        final valueEntityId = _responseMapper.entityIdFromSnak(snak);
        final display = valueEntityId != null
            ? (labels[valueEntityId] ?? valueEntityId)
            : _responseMapper.formatSnakValue(snak);
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
        final res = await _transport.get(uri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 10));
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
    int limit = SearchService.pageSize,
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
        'iiprop': 'url|size|sha1|mime|extmetadata|user|dimensions',
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
      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15));

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

        final item = _responseMapper.itemFromImageInfo(
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

      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15));

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
}
