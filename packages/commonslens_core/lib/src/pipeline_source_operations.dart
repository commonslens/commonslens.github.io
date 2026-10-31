part of 'pipeline_engine.dart';

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
    final radiusKm = _cfgDouble(c, 'radiusKm') ?? 10;
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
    final cap = ctx.effectiveMaxItems;
    // Not a CirrusSearch query, so there's no buildQuerySignature for it —
    // this synthetic signature is what lets the same query-result cache
    // (see PipelineCache) also cover author portfolios, which otherwise
    // wouldn't cache at all despite being just as re-run-heavy as any
    // other source during pipeline iteration.
    final signature = 'author:$username|pipelineCap=${cap ?? "all"}';

    if (ctx.cache != null) {
      final cached = await ctx.cache!.getQueryResult(signature);
      if (cached != null) {
        final items = ctx.applyItemLimit(cached);
        ctx.onFetchProgress?.call(items.length, null);
        return NodeOutput.materialized(items);
      }
    }

    final items = <SearchItem>[];
    Map<String, dynamic>? continueToken;
    String? error;
    var cancelled = false;
    while (ctx.shouldFetchMore(items.length)) {
      if (ctx.beforeFetchPage != null && !await ctx.beforeFetchPage!.call()) {
        cancelled = true;
        break;
      }
      final result = await ctx.backend
          .authorUploads(username, continueToken: continueToken);
      if (!result.ok) {
        error = result.error;
        break;
      }
      items.addAll(result.items);
      ctx.onFetchProgress
          ?.call(ctx.applyItemLimit(items).length, result.totalHits);
      if (!result.hasMore) break;
      continueToken = result.continueToken;
    }
    if (error != null && items.isEmpty) return NodeOutput.errorResult(error);
    final capped = ctx.applyItemLimit(items);

    if (ctx.cache != null && !cancelled) {
      await ctx.cache!.putQueryResult(signature, capped);
    }
    return NodeOutput.materialized(
      capped,
      warning: cancelled
          ? 'Run cancelled after ${capped.length} records were loaded.'
          : null,
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
  final cap = ctx.effectiveMaxItems;
  final signature = '$baseSignature|pipelineCap=${cap ?? "all"}';

  if (ctx.cache != null) {
    final cached = await ctx.cache!.getQueryResult(signature);
    if (cached != null) {
      final items = ctx.applyItemLimit(cached);
      ctx.onFetchProgress?.call(items.length, null);
      return NodeOutput.materialized(items);
    }
  }

  final items = <SearchItem>[];
  Map<String, dynamic>? continueToken;
  int? totalHits;
  String? error;
  var cancelled = false;

  while (ctx.shouldFetchMore(items.length)) {
    if (ctx.beforeFetchPage != null && !await ctx.beforeFetchPage!.call()) {
      cancelled = true;
      break;
    }
    final result =
        await ctx.backend.search(state, continueToken: continueToken);
    if (!result.ok) {
      error = result.error;
      break;
    }
    items.addAll(result.items);
    totalHits = result.totalHits ?? totalHits;
    ctx.onFetchProgress?.call(ctx.applyItemLimit(items).length, totalHits);
    if (!result.hasMore) break;
    continueToken = result.continueToken;
  }

  if (error != null && items.isEmpty) return NodeOutput.errorResult(error);

  final capped = ctx.applyItemLimit(items);

  if (ctx.cache != null && !cancelled) {
    await ctx.cache!.putQueryResult(signature, capped);
  }

  return NodeOutput.materialized(
    capped,
    totalHits: totalHits,
    warning: cancelled
        ? 'Run cancelled after ${capped.length} records were loaded.'
        : null,
  );
}
