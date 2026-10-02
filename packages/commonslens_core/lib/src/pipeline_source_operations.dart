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
  /// in map_controller.dart). [mode] 'browse' bypasses CirrusSearch
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

    final result = box != null
        ? await ctx.backend
            .geosearch(boundingBox: box, limit: ctx.effectiveMaxItems)
        : (lat != null && lng != null)
            ? await ctx.backend.geosearch(
                lat: lat,
                lng: lng,
                radiusMeters: radiusKm * 1000,
                limit: ctx.effectiveMaxItems)
            : null;

    if (result == null) {
      return NodeOutput.errorResult(
          '${node.title} (browse) needs either lat/lng or a bounding box.');
    }
    if (!result.ok) return NodeOutput.errorResult(result.error!);
    return NodeOutput.materialized(
      result.items.take(ctx.effectiveMaxItems).toList(),
      totalHits: result.totalHits,
    );
  }

  Future<NodeOutput> _materializeAuthor(
      String username, PipelineExecutionContext ctx) async {
    final cap = ctx.effectiveMaxItems;
    // Not a CirrusSearch query, so there's no buildQuerySignature for it —
    // this synthetic signature is what lets the same query-result cache
    // (see PipelineCache) also cover author portfolios, which otherwise
    // wouldn't cache at all despite being just as re-run-heavy as any
    // other source during pipeline iteration.
    final signature = 'author:$username|pipelineCap=$cap';

    if (ctx.cache != null) {
      final cached = await ctx.cache!.getQueryResult(signature);
      if (cached != null) {
        return NodeOutput.materialized(cached.take(cap).toList());
      }
    }

    final items = <SearchItem>[];
    Map<String, dynamic>? continueToken;
    String? error;
    while (items.length < cap) {
      final result = await ctx.backend
          .authorUploads(username, continueToken: continueToken);
      if (!result.ok) {
        error = result.error;
        break;
      }
      items.addAll(result.items);
      if (!result.hasMore) break;
      continueToken = result.continueToken;
    }
    if (error != null && items.isEmpty) return NodeOutput.errorResult(error);
    final capped = items.length > cap ? items.sublist(0, cap) : items;

    if (ctx.cache != null) await ctx.cache!.putQueryResult(signature, capped);
    return NodeOutput.materialized(capped);
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
  final signature = '$baseSignature|pipelineCap=$cap';

  if (ctx.cache != null) {
    final cached = await ctx.cache!.getQueryResult(signature);
    if (cached != null) {
      return NodeOutput.materialized(cached.take(cap).toList());
    }
  }

  final items = <SearchItem>[];
  Map<String, dynamic>? continueToken;
  int? totalHits;
  String? error;

  while (items.length < cap) {
    final result =
        await ctx.backend.search(state, continueToken: continueToken);
    if (!result.ok) {
      error = result.error;
      break;
    }
    items.addAll(result.items);
    totalHits = result.totalHits ?? totalHits;
    if (!result.hasMore) break;
    continueToken = result.continueToken;
  }

  if (error != null && items.isEmpty) return NodeOutput.errorResult(error);

  final capped = items.length > cap ? items.sublist(0, cap) : items;

  if (ctx.cache != null) {
    await ctx.cache!.putQueryResult(signature, capped);
  }

  return NodeOutput.materialized(capped, totalHits: totalHits);
}
