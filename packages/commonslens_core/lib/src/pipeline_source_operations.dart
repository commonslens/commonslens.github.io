part of 'pipeline_engine.dart';

// Bump this whenever a previous pipeline execution could have stored a
// partial result. The old implementation cached a truncated result after a
// later continuation page failed; those entries must never satisfy an
// unlimited CSV run.
const _pipelineQueryCacheVersion = 'pipeline-query-v5';

int _resumePageSize(
  Map<String, dynamic>? continueToken, {
  required int targetPageSize,
}) {
  final rawOffset = continueToken?['gsroffset'];
  final offset = rawOffset is num
      ? rawOffset.toInt()
      : int.tryParse(rawOffset?.toString() ?? '');
  if (offset == null || offset <= 0) return targetPageSize;
  final remainder = targetPageSize - (offset % targetPageSize);
  return remainder == targetPageSize ? targetPageSize : remainder;
}

mixin _PipelineSourceOperations {
  Future<NodeOutput> _executeSource(
      PipelineNode node, PipelineExecutionContext ctx) async {
    final c = node.config;
    switch (node.type) {
      case PipelineNodeType.sourceTextQuery:
        final query = _cfgString(c, 'query');
        if (query.isEmpty) {
          return NodeOutput.errorResult('${node.title} needs a query.');
        }
        return NodeOutput.pending(SearchState(queryText: query));

      case PipelineNodeType.sourceCategory:
        final cats = _cfgStringList(c, 'categories').toSet();
        if (cats.isEmpty) {
          return NodeOutput.errorResult(
              '${node.title} needs at least one category.');
        }
        return NodeOutput.pending(SearchState(
          categories: cats,
          categoriesUnion: _cfgBool(c, 'union'),
          deepCategoryMode: _cfgBool(c, 'deep'),
        ));

      case PipelineNodeType.sourceDepicts:
        final entries = _depictsEntriesFrom(c['entries']);
        if (entries.isEmpty) {
          return NodeOutput.errorResult(
              '${node.title} needs at least one Q-code.');
        }
        return NodeOutput.pending(SearchState(
          depictsInclude: entries,
          depictsUnion: _cfgBool(c, 'union'),
        ));

      case PipelineNodeType.sourceStatement:
        final stmts = _statementsFrom(c['entries']);
        if (stmts.isEmpty) {
          return NodeOutput.errorResult(
              '${node.title} needs at least one property/value pair.');
        }
        return NodeOutput.pending(SearchState(
          statementsInclude: stmts,
          statementsUnion: _cfgBool(c, 'union'),
        ));

      case PipelineNodeType.sourceTemplate:
        final templates = _cfgStringList(c, 'templates').toSet();
        if (templates.isEmpty) {
          return NodeOutput.errorResult(
              '${node.title} needs at least one template name.');
        }
        return NodeOutput.pending(SearchState(templates: templates));

      case PipelineNodeType.sourceMorelike:
        final title = _cfgString(c, 'title');
        if (title.isEmpty) {
          return NodeOutput.errorResult('${node.title} needs a file title.');
        }
        return NodeOutput.pending(SearchState(morelikeTitles: {title}));

      case PipelineNodeType.sourceAuthor:
        final username = _cfgString(c, 'username');
        if (username.isEmpty) {
          return NodeOutput.errorResult('${node.title} needs a username.');
        }
        // Not a CirrusSearch query at all (list=allimages instead) — no
        // SearchState to be pending about, so this always materializes
        // immediately. Any Filter node chained after it necessarily falls
        // to the client-side path.
        return _materializeAuthor(username, ctx);

      case PipelineNodeType.sourceGeosearch:
        return _executeGeoSource(node, ctx);

      default:
        return NodeOutput.errorResult(
            'Unhandled source node type: ${node.type}');
    }
  }

  Set<DepictsEntity> _depictsEntriesFrom(dynamic raw) {
    if (raw is! List) return const {};
    return raw
        .whereType<Map>()
        .map((m) {
          final qid = m['qid']?.toString() ?? '';
          final label = m['label']?.toString() ?? qid;
          return DepictsEntity(qid: qid, label: label);
        })
        .where((e) => e.qid.isNotEmpty)
        .toSet();
  }

  Set<WikidataStatement> _statementsFrom(dynamic raw) {
    if (raw is! List) return const {};
    return raw
        .whereType<Map>()
        .map((m) {
          final prop = m['property'];
          final val = m['value'];
          if (prop is! Map || val is! Map) return null;
          final pid = prop['qid']?.toString() ?? '';
          final vid = val['qid']?.toString() ?? '';
          if (pid.isEmpty || vid.isEmpty) return null;
          return WikidataStatement(
            property: DepictsEntity(
                qid: pid, label: prop['label']?.toString() ?? pid),
            value:
                DepictsEntity(qid: vid, label: val['label']?.toString() ?? vid),
          );
        })
        .whereType<WikidataStatement>()
        .toSet();
  }

  /// [mode] 'filtered' sets `nearCoord` on a normal SearchState — stays
  /// compilable, still combines with License/Quality/etc. downstream, and
  /// goes through the ordinary CirrusSearch path (matches GeoMode.filtered
  /// in the integrated map search). [mode] 'browse' bypasses CirrusSearch
  /// entirely via `CommonsBackend.geosearch` (matches GeoMode.browse) — no
  /// relevance ranking, none of SearchState's other filters apply at fetch
  /// time, and it always materializes immediately, same as Author above.
  Future<NodeOutput> _executeGeoSource(
      PipelineNode node, PipelineExecutionContext ctx) async {
    final c = node.config;
    final mode = _cfgString(c, 'mode', 'filtered');
    final lat = _cfgDouble(c, 'lat');
    final lng = _cfgDouble(c, 'lng');
    final radiusKm = _cfgDouble(c, 'radiusKm') ?? 2;
    final boxRaw = c['box'];
    final box = boxRaw is List && boxRaw.length == 4
        ? boxRaw.map((v) => (v as num).toDouble()).toList()
        : null;

    if (mode == 'filtered') {
      if (lat == null || lng == null) {
        return NodeOutput.errorResult(
            '${node.title} (filtered) needs lat/lng.');
      }
      return NodeOutput.pending(
        SearchState(
            nearCoord: NearCoordFilter(lat: lat, lng: lng, radiusKm: radiusKm)),
      );
    }

    // MediaWiki's geosearch module has no continuation support and returns
    // at most 500 rows. "All available" therefore means the module maximum
    // for browse mode; filtered location searches use normal paginated
    // CirrusSearch and are not subject to this special case.
    final requestedLimit = ctx.effectiveMaxItems;
    final geosearchLimit = (requestedLimit ?? 500).clamp(1, 500);
    final result = box != null
        ? await ctx.backend.geosearch(boundingBox: box, limit: geosearchLimit)
        : (lat != null && lng != null)
            ? await ctx.backend.geosearch(
                lat: lat,
                lng: lng,
                radiusMeters: radiusKm * 1000,
                limit: geosearchLimit)
            : null;

    if (result == null) {
      return NodeOutput.errorResult(
          '${node.title} (browse) needs either lat/lng or a bounding box.');
    }
    if (!result.ok) return NodeOutput.errorResult(result.error!);
    final items = ctx.applyItemLimit(result.items);
    ctx.onFetchProgress?.call(items.length, result.totalHits);
    return NodeOutput.materialized(items, totalHits: result.totalHits);
  }

  Future<NodeOutput> _materializeAuthor(
      String username, PipelineExecutionContext ctx) async {
    // Not a CirrusSearch query, so there's no buildQuerySignature for it —
    // this synthetic signature is what lets the same query-result cache
    // (see PipelineCache) also cover author portfolios, which otherwise
    // wouldn't cache at all despite being just as re-run-heavy as any
    // other source during pipeline iteration.
    final signature =
        '$_pipelineQueryCacheVersion|author:$username|profile=${ctx.requestProfile.cacheKey}';

    var items = <SearchItem>[];
    Map<String, dynamic>? continueToken;
    int? totalHits;
    var complete = false;
    var cachedWarnings = <String>[];
    if (ctx.cache != null) {
      final cached = await ctx.cache!.getQuerySnapshot(signature);
      if (cached != null) {
        items = cached.items.toList();
        continueToken = cached.continueToken;
        totalHits = cached.totalHits;
        complete = cached.complete;
        cachedWarnings = cached.warnings.toList();
        if (complete || !ctx.shouldFetchMore(items.length)) {
          final capped = ctx.applyItemLimit(items);
          ctx.onFetchProgress?.call(capped.length, totalHits);
          return NodeOutput.materialized(
            capped,
            totalHits: totalHits,
            warning: cachedWarnings.isEmpty ? null : cachedWarnings.join(' '),
          );
        }
      }
    }

    String? error;
    var cancelled = false;
    final warnings = cachedWarnings;
    while (ctx.shouldFetchMore(items.length)) {
      if (ctx.beforeFetchPage != null && !await ctx.beforeFetchPage!.call()) {
        cancelled = true;
        break;
      }
      final result = await ctx.backend.authorUploads(
        username,
        continueToken: continueToken,
        requestProfile: ctx.requestProfile,
      );
      if (!result.ok) {
        error = result.error;
        break;
      }
      if (result.warning != null) warnings.add(result.warning!);
      items.addAll(result.items);
      ctx.onFetchProgress?.call(
          ctx.applyItemLimit(items).length, result.totalHits ?? totalHits);
      totalHits = result.totalHits ?? totalHits;
      if (!result.hasMore) {
        complete = true;
        continueToken = null;
        break;
      }
      continueToken = result.continueToken;
      if (ctx.cache != null && !cancelled) {
        await ctx.cache!.putQuerySnapshot(
          signature,
          PipelineQuerySnapshot(
            items: items,
            continueToken: continueToken,
            totalHits: totalHits,
            complete: false,
            warnings: warnings,
            pageSize: ctx.requestProfile.pageSize,
          ),
        );
      }
    }
    // Permanent failures must not turn a partial author result into a
    // successful export.
    if (error != null) return NodeOutput.errorResult(error);
    final capped = ctx.applyItemLimit(items);

    if (ctx.cache != null &&
        !cancelled &&
        (complete || !ctx.shouldFetchMore(items.length))) {
      await ctx.cache!.putQuerySnapshot(
        signature,
        PipelineQuerySnapshot(
          items: items,
          continueToken: continueToken,
          totalHits: totalHits,
          complete: complete,
          warnings: warnings,
          pageSize: ctx.requestProfile.pageSize,
        ),
      );
    }
    return NodeOutput.materialized(
      capped,
      warning: cancelled
          ? 'Run cancelled after ${capped.length} records were loaded.'
          : warnings.isEmpty
              ? null
              : warnings.join(' '),
    );
  }
}

// ---------------------------------------------------------------------
// Materialize — the one place a compiled SearchState actually becomes a
// network fetch (+ cache lookup). Loops CommonsBackend.search's
// continueToken until either the effective item cap is hit or the
// backend runs out of pages.
// ---------------------------------------------------------------------

Future<NodeOutput> _materializeState(
    SearchState state, PipelineExecutionContext ctx) async {
  final baseSignature = ctx.backend.buildQuerySignature(state);
  // The cap and page size are deliberately excluded: a 100-item preview and
  // an unlimited export are two consumers of the same source stream. The
  // cached continuation token lets the latter resume after the preview prefix
  // instead of replaying it. The first ETL request bridges any partial
  // preview page boundary; subsequent ETL requests are 200 rows.
  final signature =
      '$_pipelineQueryCacheVersion|$baseSignature|profile=${ctx.requestProfile.cacheKey}';

  var items = <SearchItem>[];
  Map<String, dynamic>? continueToken;
  int? totalHits;
  var complete = false;
  var warnings = <String>[];
  final targetPageSize = ctx.requestProfile.pageSize;
  var requestPageSize = targetPageSize;
  if (ctx.cache != null) {
    final cached = await ctx.cache!.getQuerySnapshot(signature);
    if (cached != null) {
      items = cached.items.toList();
      continueToken = cached.continueToken;
      totalHits = cached.totalHits;
      complete = cached.complete;
      warnings = cached.warnings.toList();
      if (ctx.requestProfile == SearchRequestProfile.pipelineEtl &&
          cached.pageSize != null &&
          cached.pageSize! < targetPageSize &&
          continueToken != null) {
        // Preview pages are 50 while ETL pages are 200. The first ETL
        // request after a preview uses only the number needed to reach the
        // next 200-row boundary, avoiding both overlap and a duplicate API
        // download. Later requests use the normal 200-row page.
        requestPageSize = _resumePageSize(
          continueToken,
          targetPageSize: targetPageSize,
        );
      }
      if (complete || !ctx.shouldFetchMore(items.length)) {
        final capped = ctx.applyItemLimit(items);
        ctx.onFetchProgress?.call(capped.length, totalHits);
        return NodeOutput.materialized(
          capped,
          totalHits: totalHits,
          warning: warnings.isEmpty ? null : warnings.join(' '),
        );
      }
    }
  }

  String? error;
  var cancelled = false;
  final seenUrls = items.map((item) => item.url).toSet();

  while (ctx.shouldFetchMore(items.length)) {
    if (ctx.beforeFetchPage != null && !await ctx.beforeFetchPage!.call()) {
      cancelled = true;
      break;
    }
    final result = await ctx.backend.search(
      state,
      continueToken: continueToken,
      includeThumbnailUrls: ctx.includeThumbnailUrls,
      requestProfile: ctx.requestProfile,
      pageSizeOverride: requestPageSize,
    );
    if (!result.ok) {
      error = result.error;
      break;
    }
    if (result.warning != null) warnings.add(result.warning!);
    for (final item in result.items) {
      if (seenUrls.add(item.url)) items.add(item);
    }
    totalHits = result.totalHits ?? totalHits;
    ctx.onFetchProgress?.call(ctx.applyItemLimit(items).length, totalHits);
    if (!result.hasMore) {
      complete = true;
      continueToken = null;
      break;
    }
    continueToken = result.continueToken;
    requestPageSize = targetPageSize;
    if (ctx.cache != null && !cancelled) {
      await ctx.cache!.putQuerySnapshot(
        signature,
        PipelineQuerySnapshot(
          items: items,
          continueToken: continueToken,
          totalHits: totalHits,
          complete: false,
          warnings: warnings,
          pageSize: requestPageSize,
        ),
      );
    }
  }

  // Never turn a failed continuation page into a successful partial result.
  if (error != null) return NodeOutput.errorResult(error);

  final capped = ctx.applyItemLimit(items);

  if (ctx.cache != null &&
      !cancelled &&
      (complete || !ctx.shouldFetchMore(items.length))) {
    await ctx.cache!.putQuerySnapshot(
      signature,
      PipelineQuerySnapshot(
        items: items,
        continueToken: continueToken,
        totalHits: totalHits,
        complete: complete,
        warnings: warnings,
        pageSize: requestPageSize,
      ),
    );
  }

  return NodeOutput.materialized(
    capped,
    totalHits: totalHits,
    warning: [
      ...warnings,
      if (cancelled)
        'Run cancelled after ${capped.length} records were loaded.',
    ].join(' ').trim().isEmpty
        ? null
        : [
            ...warnings,
            if (cancelled)
              'Run cancelled after ${capped.length} records were loaded.',
          ].join(' '),
  );
}
