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
        'iiprop': 'url|size|sha1|mime|extmetadata|user',
        'iiurlwidth': '330',
      };

      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', params);

      var response = await _transport.get(uri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15),
          category: WikimediaRequestCategory.metadata);

      if (response.statusCode != 200) return null;

      var data = jsonDecode(response.body) as Map<String, dynamic>;
      final apiError = data['error'];
      if (apiError is Map && apiError['code'] == 'urlparamnormal') {
        // A malformed/oversized file can make Wikimedia reject only the
        // requested thumbnail width. The rights metadata is still usable, so
        // retry the same single-file lookup without thumbnail scaling.
        final fallbackParams = <String, String>{...params}
          ..remove('iiurlwidth');
        final fallbackUri =
            Uri.https('commons.wikimedia.org', '/w/api.php', fallbackParams);
        response = await _transport.get(fallbackUri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 15),
            category: WikimediaRequestCategory.metadata);
        if (response.statusCode != 200) return null;
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};

      if (pages.isEmpty) return null;

      final firstPage = pages.entries.first;
      final page = firstPage.value as Map<String, dynamic>;

      if (page.containsKey('missing')) return null;

      final infoList = page['imageinfo'] as List?;
      if (infoList == null || infoList.isEmpty) return null;

      final info = infoList.first as Map<String, dynamic>;
      final rawTitle = page['title'] as String? ?? '';

      return _responseMapper.itemFromImageInfo(
        info,
        rawTitle: rawTitle,
        snippet: rawTitle,
        pageId: (page['pageid'] as num?)?.toInt() ??
            int.tryParse(firstPage.key.toString()),
        timestamp: page['timestamp'] as String?,
        descriptionUrl: page['fullurl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Fetches non-extmetadata image information for a small batch of files.
  /// The raw imageinfo object is intentionally preserved so ETL consumers can
  /// inspect technical metadata without expanding SearchItem every time the
  /// MediaWiki API adds a field.
  Future<Map<String, Map<String, dynamic>>> fetchImageMetadataBatch(
    List<String> filenames, {
    WikimediaRequestCategory category = WikimediaRequestCategory.metadata,
  }) async {
    if (filenames.isEmpty) return {};
    try {
      final titles = filenames
          .map((filename) =>
              filename.startsWith('File:') ? filename : 'File:$filename')
          .toSet()
          .toList();
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': titles.join('|'),
        'prop': 'info|coordinates|imageinfo',
        'inprop': 'url',
        'coprop': 'type|name|dim|country|region',
        'coprimary': 'all',
        'iiprop':
            'timestamp|user|userid|comment|parsedcomment|canonicaltitle|url|size|sha1|mime|thumbmime|thumburls|mediatype|metadata|commonmetadata|bitdepth|archivename|badfile',
        'iilimit': '1',
      });
      final response = await _transport.get(uri,
          headers: {
            'Api-User-Agent':
                'CommonsLens/1.0 (https://github.com/commonslens/commonslens.github.io; Flutter Web)',
          },
          timeout: const Duration(seconds: 20),
          category: category);
      if (response.statusCode != 200) return {};

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data.containsKey('error')) return {};
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
      final result = <String, Map<String, dynamic>>{};
      for (final rawPage in pages.values) {
        if (rawPage is! Map) continue;
        final page = Map<String, dynamic>.from(rawPage);
        final infoList = page['imageinfo'];
        if (infoList is! List || infoList.isEmpty || infoList.first is! Map) {
          continue;
        }
        final info = Map<String, dynamic>.from(infoList.first as Map);
        final coordinates = page['coordinates'];
        result[page['title']?.toString() ?? ''] = {
          'pageid': page['pageid'],
          'title': page['title'],
          'fullurl': page['fullurl'],
          'coordinates': coordinates is List
              ? coordinates
                  .map((entry) =>
                      entry is Map ? Map<String, dynamic>.from(entry) : entry)
                  .toList()
              : null,
          'imageinfo': info,
        };
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  /// Reads one file's Structured Data on Commons (SDC) entity back. The
  /// single-file API is intentionally implemented through the batch API so
  /// callers cannot accidentally get a less efficient code path.
  Future<StructuredDataResult?> fetchStructuredData(String filename) async {
    final title = filename.startsWith('File:') ? filename : 'File:$filename';
    final results = await fetchStructuredDataBatch([title]);
    return results[title];
  }

  /// Reads SDC for many files using the MediaWiki batch limits:
  /// page IDs in groups of 50, MediaInfo entities in groups of 50, and one
  /// Wikidata label pass for all property/value IDs found in the batch.
  /// [pageIds] lets pipeline search results skip the otherwise redundant
  /// `prop=info` lookup when the source already returned page IDs.
  Future<Map<String, StructuredDataResult>> fetchStructuredDataBatch(
    List<String> filenames, {
    Map<String, int?>? pageIds,
    WikimediaRequestCategory category = WikimediaRequestCategory.metadata,
  }) async {
    final titles = filenames
        .map((filename) =>
            filename.startsWith('File:') ? filename : 'File:$filename')
        .toSet()
        .toList();
    if (titles.isEmpty) return {};

    final pageIdByTitle = <String, int>{};
    for (final entry in pageIds?.entries ?? const <MapEntry<String, int?>>[]) {
      final title =
          entry.key.startsWith('File:') ? entry.key : 'File:${entry.key}';
      final id = entry.value;
      if (id != null) pageIdByTitle[title] = id;
    }

    try {
      final missingTitles =
          titles.where((title) => !pageIdByTitle.containsKey(title)).toList();
      for (var start = 0; start < missingTitles.length; start += 50) {
        final batch = missingTitles.skip(start).take(50).toList();
        final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query',
          'format': 'json',
          'origin': '*',
          'titles': batch.join('|'),
          'prop': 'info',
        });
        final response = await _transport.get(uri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 10),
            category: category);
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('error')) continue;
        final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
        for (final rawPage in pages.values) {
          if (rawPage is! Map) continue;
          final page = Map<String, dynamic>.from(rawPage);
          final title = page['title']?.toString();
          final id = (page['pageid'] as num?)?.toInt();
          if (title != null && id != null && !page.containsKey('missing')) {
            pageIdByTitle[title] = id;
          }
        }
      }

      final entityByMid = <String, Map<String, dynamic>>{};
      final mids = pageIdByTitle.values.map((id) => 'M$id').toList();
      for (var start = 0; start < mids.length; start += 50) {
        final batch = mids.skip(start).take(50).toList();
        final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'wbgetentities',
          'format': 'json',
          'origin': '*',
          'ids': batch.join('|'),
        });
        final response = await _transport.get(uri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 15),
            category: category);
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('error')) continue;
        final entities = data['entities'] as Map<String, dynamic>? ?? {};
        for (final entry in entities.entries) {
          if (entry.value is Map) {
            entityByMid[entry.key] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }

      final idsToResolve = <String>{};
      for (final entity in entityByMid.values) {
        final rawStatements = entity['statements'];
        if (rawStatements is! Map) continue;
        for (final entry in rawStatements.entries) {
          idsToResolve.add(entry.key.toString());
          final claims = entry.value is List ? entry.value as List : const [];
          for (final rawClaim in claims) {
            if (rawClaim is! Map) continue;
            final rawSnak = rawClaim['mainsnak'];
            if (rawSnak is Map) {
              final snak = Map<String, dynamic>.from(rawSnak);
              final entityId = _responseMapper.entityIdFromSnak(snak);
              if (entityId != null) idsToResolve.add(entityId);
            }
          }
        }
      }
      final labels = await _resolveWikidataLabels(
        idsToResolve,
        category: category,
      );

      final results = <String, StructuredDataResult>{};
      for (final title in titles) {
        final pageId = pageIdByTitle[title];
        if (pageId == null) continue;
        final mid = 'M$pageId';
        final entity = entityByMid[mid];
        if (entity == null) continue;
        results[title] = _structuredDataFromEntity(entity, labels);
      }
      return results;
    } catch (_) {
      return {};
    }
  }

  StructuredDataResult _structuredDataFromEntity(
    Map<String, dynamic> entity,
    Map<String, String> labels,
  ) {
    final mid = entity['id']?.toString() ?? '';
    final labelsRaw = entity['labels'];
    final captions = <String, String>{};
    if (labelsRaw is Map) {
      for (final entry in labelsRaw.entries) {
        final value = entry.value;
        if (value is Map) {
          captions[entry.key.toString()] = value['value']?.toString() ?? '';
        }
      }
    }

    final statements = <StructuredDataStatement>[];
    final statementsRaw = entity['statements'];
    if (statementsRaw is Map) {
      for (final propEntry in statementsRaw.entries) {
        final propertyId = propEntry.key.toString();
        final claims =
            propEntry.value is List ? propEntry.value as List : const [];
        for (final rawClaim in claims) {
          if (rawClaim is! Map) continue;
          final rawSnak = rawClaim['mainsnak'];
          if (rawSnak is! Map) continue;
          final snak = Map<String, dynamic>.from(rawSnak);
          final valueEntityId = _responseMapper.entityIdFromSnak(snak);
          final display = valueEntityId != null
              ? (labels[valueEntityId] ?? valueEntityId)
              : _responseMapper.formatSnakValue(snak);
          statements.add(StructuredDataStatement(
            propertyId: propertyId,
            propertyLabel: labels[propertyId] ?? propertyId,
            valueDisplay: display,
            valueEntityId: valueEntityId,
          ));
        }
      }
    }

    return StructuredDataResult(
      mid: mid,
      captions: captions,
      statements: statements,
      raw: entity,
    );
  }

  /// Batched label lookup for a mix of Wikidata P-codes and Q-codes.
  /// Always queries www.wikidata.org regardless of which Commons file
  /// referenced the ids — Commons SDC statements point directly into
  /// Wikidata's own id space rather than maintaining a separate one.
  Future<Map<String, String>> _resolveWikidataLabels(
    Set<String> ids, {
    String language = 'en',
    WikimediaRequestCategory category = WikimediaRequestCategory.metadata,
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
            timeout: const Duration(seconds: 10),
            category: category);
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
    bool includeExtmetadata = true,
    WikimediaRequestCategory category = WikimediaRequestCategory.search,
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
        'iiprop': [
          'url|size|sha1|mime|user',
          if (includeExtmetadata) 'extmetadata',
        ].join('|'),
        'iiurlwidth': '330',
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
          timeout: const Duration(seconds: 15),
          category: category);

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
      for (final entry in pages.entries) {
        final p = Map<String, dynamic>.from(entry.value as Map);
        p['pageid'] ??= int.tryParse(entry.key.toString());
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
          pageId: (p['pageid'] as num?)?.toInt(),
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
    WikimediaRequestCategory category = WikimediaRequestCategory.metadata,
  }) async {
    final title = filename.startsWith('File:') ? filename : 'File:$filename';
    final batch = await fetchGlobalUsageBatch(
      [title],
      limit: limit,
      category: category,
    );
    return batch[title] ?? const [];
  }

  /// Batched global-usage lookup. A single `globalusage` property request can
  /// carry many file titles; use modest groups because the response contains
  /// one usage object for every matching wiki page.
  Future<Map<String, List<GlobalUsageEntry>>> fetchGlobalUsageBatch(
    List<String> filenames, {
    int limit = 500,
    WikimediaRequestCategory category = WikimediaRequestCategory.metadata,
  }) async {
    final titles = filenames
        .map((filename) =>
            filename.startsWith('File:') ? filename : 'File:$filename')
        .toSet()
        .toList();
    final result = <String, List<GlobalUsageEntry>>{};
    if (titles.isEmpty) return result;

    try {
      for (var start = 0; start < titles.length; start += 20) {
        final batch = titles.skip(start).take(20).toList();
        final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
          'action': 'query',
          'format': 'json',
          'origin': '*',
          'titles': batch.join('|'),
          'prop': 'globalusage',
          'guprop': 'url|pageid|namespace',
          'gulimit': '${limit.clamp(1, 500)}',
        });
        final response = await _transport.get(uri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 20),
            category: category);
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data.containsKey('error')) continue;
        final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
        final returnedTitles = <String>{};
        for (final rawPage in pages.values) {
          if (rawPage is! Map) continue;
          final page = Map<String, dynamic>.from(rawPage);
          final title = page['title']?.toString();
          if (title == null || page.containsKey('missing')) continue;
          returnedTitles.add(title);
          final usageList = page['globalusage'];
          if (usageList is! List) {
            result[title] = const [];
            continue;
          }
          result[title] = usageList.whereType<Map>().map((raw) {
            final entry = Map<String, dynamic>.from(raw);
            final rawNamespace = entry['namespace'] ?? entry['ns'];
            return GlobalUsageEntry(
              wiki: entry['wiki']?.toString() ?? '',
              title: entry['title']?.toString() ?? '',
              url: entry['url']?.toString(),
              pageId: (entry['pageid'] as num?)?.toInt(),
              namespace: rawNamespace is num ? rawNamespace.toInt() : null,
              raw: entry,
            );
          }).toList();
        }
        // A successful response with a page that has no usage still counts as
        // a valid empty result. Titles absent from the response are left out
        // so callers can distinguish a failed batch from "unused file".
        for (final title in returnedTitles) {
          result.putIfAbsent(title, () => const []);
        }
      }
    } catch (_) {
      // Return successful groups and empty lists for groups that failed.
    }
    return result;
  }
}
