import 'dart:convert';
import 'package:http/http.dart' as http;
import 'search_models.dart';
import 'search_query_compiler.dart';
import 'search_request_profile.dart';
import 'wikimedia_transport.dart';
import 'wikimedia_response_mapper.dart';
import 'wikimedia_request_logger.dart';

part 'search_asset_operations.dart';
part 'search_autocomplete_operations.dart';
part 'search_browse_operations.dart';

/// A type-ahead request reached the provider but could not produce a valid
/// suggestion list. Callers can distinguish this from a valid empty result and
/// show a retry/connection message without exposing transport details.
class AutocompleteLookupException implements Exception {
  final String operation;
  final int? statusCode;
  final Object? cause;

  const AutocompleteLookupException(
    this.operation, {
    this.statusCode,
    this.cause,
  });

  @override
  String toString() => statusCode == null
      ? 'AutocompleteLookupException($operation)'
      : 'AutocompleteLookupException($operation, HTTP $statusCode)';
}

WikimediaRequestCategory _categoryForProfile(SearchRequestProfile profile) =>
    profile.isPipelineEtl || profile.isPipelinePreview
        ? WikimediaRequestCategory.pipeline
        : WikimediaRequestCategory.search;

class SearchService with _SearchAssetOperations, _SearchAutocompleteOperations {
  static const int pageSize = 50;

  static final WikimediaTransport _defaultTransport = GatedWikimediaTransport();

  final SearchQueryCompiler _queryCompiler;
  @override
  final WikimediaResponseMapper _responseMapper;
  @override
  final WikimediaTransport _transport;

  SearchService({
    SearchQueryCompiler? queryCompiler,
    WikimediaResponseMapper? responseMapper,
    WikimediaTransport? transport,
  })  : _queryCompiler = queryCompiler ?? const SearchQueryCompiler(),
        _responseMapper = responseMapper ?? const WikimediaResponseMapper(),
        _transport = transport ?? _defaultTransport;

  /// Splits a "cat + dog" query into independent segments — the single
  /// source of truth for what counts as a "+"-separator. fetchPage uses
  /// this to fan out parallel searches; SearchTopBar's autocomplete uses
  /// the exact same pattern to find the segment currently being typed, so
  /// the two can never drift out of sync with each other.
  static final RegExp multiQuerySeparator =
      SearchQueryCompiler.multiQuerySeparator;

  QueryBuildResult buildQuery(SearchState state,
          {FileFormat? overrideFormat}) =>
      _queryCompiler.buildQuery(state, overrideFormat: overrideFormat);

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
    SearchRequestProfile requestProfile = SearchRequestProfile.ui,
  }) async {
    final user = username.trim();
    if (user.isEmpty) return null;
    final category = _categoryForProfile(requestProfile);

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
        'ailimit': '${requestProfile.pageSize}',
        'aiprop': 'timestamp|canonicaltitle',
      };

      if (continueParams != null) {
        for (final entry in continueParams.entries) {
          listParams[entry.key] = entry.value.toString();
        }
      }

      final listUri =
          Uri.https('commons.wikimedia.org', '/w/api.php', listParams);
      final listResponse = await _transport.get(listUri,
          headers: {
            'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
          },
          timeout: const Duration(seconds: 15),
          category: category);

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
        'iiprop': [
          'url|size|sha1|mime|user',
          if (requestProfile.includeExtmetadata) 'extmetadata',
        ].join('|'),
        'iiurlwidth': '320',
      };

      final infoUri =
          Uri.https('commons.wikimedia.org', '/w/api.php', infoParams);
      late final http.Response infoResponse;
      try {
        infoResponse = await _transport.get(infoUri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 15),
            maxAttempts: 4,
            category: category);
      } catch (e) {
        if (requestProfile != SearchRequestProfile.ui) {
          return SearchResponse(
            items: const [],
            continueParams: nextContinue,
            warning:
                'Skipped the ${requestProfile.pageSize}-result uploader batch after 3 retries: $e',
          );
        }
        return null;
      }

      if (infoResponse.statusCode != 200) {
        if (requestProfile != SearchRequestProfile.ui) {
          return SearchResponse(
            items: const [],
            continueParams: nextContinue,
            warning:
                'Skipped the ${requestProfile.pageSize}-result uploader batch after 3 retries: HTTP ${infoResponse.statusCode}',
          );
        }
        return null;
      }

      final infoData = jsonDecode(infoResponse.body) as Map<String, dynamic>;
      if (infoData.containsKey('error')) {
        if (requestProfile != SearchRequestProfile.ui) {
          final error = infoData['error'];
          final code = error is Map ? error['code'] ?? 'unknown' : 'unknown';
          return SearchResponse(
            items: const [],
            continueParams: nextContinue,
            warning:
                'Skipped the ${requestProfile.pageSize}-result uploader batch after 3 retries: Wikimedia API error $code',
          );
        }
        return null;
      }
      final pages =
          (infoData['query']?['pages'] as Map<String, dynamic>?) ?? {};

      // pages is keyed by pageid with no guaranteed order — index by title
      // so we can rebuild the newest-first order from step 1.
      final byTitle = <String, Map<String, dynamic>>{};
      for (final entry in pages.entries) {
        final p = Map<String, dynamic>.from(entry.value as Map);
        p['pageid'] ??= int.tryParse(entry.key.toString());
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

        final item = _responseMapper.itemFromImageInfo(
          info,
          rawTitle: title,
          snippet: title,
          pageId: (page['pageid'] as num?)?.toInt(),
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

  /// Stable cache/session identity derived from the complete backend model.
  /// Map keys and set-backed JSON lists are canonicalized, so insertion order
  /// cannot create duplicate cache entries. URL compactness is deliberately
  /// kept out of this contract.
  String buildQuerySignature(SearchState state) =>
      _queryCompiler.buildSignature(state);

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
    final warnings = <String>[];
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
          if (result.warning != null) warnings.add(result.warning!);
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
      warning: warnings.isEmpty ? null : warnings.join(' '),
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
    bool includeThumbWidth = true,
    SearchRequestProfile requestProfile = SearchRequestProfile.ui,
    int? pageSizeOverride,
  }) async {
    final skipFailedPages = requestProfile != SearchRequestProfile.ui;
    final pageSize = pageSizeOverride ?? requestProfile.pageSize;
    final queryText = state.queryText.trim();
    final segments = queryText
        .split(multiQuerySeparator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.length <= 1) {
      return _fetchPageForQuery(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: requestProfile.includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<String>(
      branches: segments,
      keyOf: (segment) => segment,
      stateFor: (segment) => state.copyWith(queryText: segment),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForQuery(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: requestProfile.includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_query',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForQuery(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    // Union mode with 2+ include statements: Cirrus can't reliably OR a
    // statement clause together with the rest of the active filters in one
    // query string, so each statement runs as its own independent search
    // (with every other filter, including exclude-statements, still
    // applied) and results are merged client-side — see _fanOutFetch.
    final includeStatements = state.statementsInclude.toList();

    if (!state.statementsUnion || includeStatements.length <= 1) {
      return _fetchPageForQuality(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<WikidataStatement>(
      branches: includeStatements,
      keyOf: (stmt) => '${stmt.property.qid}=${stmt.value.qid}',
      stateFor: (stmt) => state.copyWith(statementsInclude: {stmt}),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForQuality(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_stmt',
      sortMode: state.sortMode,
    );
  }

  /// CirrusSearch documents that boolean operators do not interact
  /// predictably with special keywords such as `hastemplate:`. Quality
  /// assessments use those keywords, so a multi-assessment selection is
  /// executed as independent searches and merged here instead of relying on
  /// one `(... OR ...)` expression.
  Future<SearchResponse?> _fetchPageForQuality(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    if (state.allImagesMode) {
      return _fetchPageForLicense(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    final qualities = state.effectiveQualityFilters.toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    if (qualities.length <= 1) {
      return _fetchPageForLicense(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<QualityFilter>(
      branches: qualities,
      keyOf: (quality) => quality.name,
      stateFor: (quality) => state.copyWith(
        qualityFilters: {quality},
        qualityMatchMode: QualityMatchMode.individual,
      ),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForLicense(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_quality',
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
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    final licenses = state.licensePresets.toList();

    if (licenses.length <= 1) {
      return _fetchPageForCategory(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<LicensePreset>(
      branches: licenses,
      keyOf: (l) => l.name,
      stateFor: (l) => state.copyWith(licensePresets: {l}),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForCategory(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_license',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForCategory(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    // Same fan-out pattern for category union mode — deepCategoryMode,
    // excludeCategories, and everything else carry over unchanged onto
    // each single-category branch.
    // Deep category searches are deliberately one server-side CirrusSearch
    // request. The previous client-side expansion turned one category into
    // dozens of serial API calls because Wikimedia's request gate is global.
    // That made the image grid wait minutes before it received its first page.
    if (state.deepCategoryMode) {
      return _fetchPageForDepicts(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    final includeCategories = state.categories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (!state.categoriesUnion || includeCategories.length <= 1) {
      return _fetchPageForDepicts(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<String>(
      branches: includeCategories,
      keyOf: (cat) => cat,
      stateFor: (cat) => state.copyWith(categories: {cat}),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForDepicts(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_cat',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForDepicts(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    // Same fan-out pattern again for depicts union mode — depictsExclude
    // and everything else carry over unchanged onto each single-entity
    // branch.
    final includeDepicts = state.depictsInclude.toList();

    if (!state.depictsUnion || includeDepicts.length <= 1) {
      return _fetchPageForFormat(
        state,
        continueParams: continueParams,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      );
    }

    return _fanOutFetch<DepictsEntity>(
      branches: includeDepicts,
      keyOf: (entity) => entity.qid,
      stateFor: (entity) => state.copyWith(depictsInclude: {entity}),
      nextFetch: (_, branchState, branchContinue) => _fetchPageForFormat(
        branchState,
        continueParams: branchContinue,
        includeThumbWidth: includeThumbWidth,
        includeExtmetadata: includeExtmetadata,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
      ),
      continueParams: continueParams,
      continueBucketKey: '_depicts',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchPageForFormat(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) async {
    if (state.formats.isEmpty) {
      return _fetchSingle(state,
          continueParams: continueParams,
          overrideFormat: null,
          includeThumbWidth: includeThumbWidth,
          includeExtmetadata: includeExtmetadata,
          pageSize: pageSize,
          skipFailedPages: skipFailedPages);
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
          overrideFormat: format,
          includeThumbWidth: includeThumbWidth,
          includeExtmetadata: includeExtmetadata,
          pageSize: pageSize,
          skipFailedPages: skipFailedPages),
      continueParams: continueParams,
      continueBucketKey: '_multi',
      sortMode: state.sortMode,
    );
  }

  Future<SearchResponse?> _fetchSingle(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    FileFormat? overrideFormat,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
  }) {
    return _fetchSingleAttempt(
      state,
      continueParams: continueParams,
      overrideFormat: overrideFormat,
      includeThumbWidth: includeThumbWidth,
      includeExtmetadata: includeExtmetadata,
      pageSize: pageSize,
      skipFailedPages: skipFailedPages,
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
  /// `WikimediaResponseMapper.itemFromImageInfo` already falls back to the original url whenever
  /// `thumburl` is absent, so no items are lost; only that one page's grid
  /// thumbnails are briefly full-res instead of scaled.
  Future<SearchResponse?> _fetchSingleAttempt(
    SearchState state, {
    required Map<String, dynamic>? continueParams,
    FileFormat? overrideFormat,
    required bool includeThumbWidth,
    required bool includeExtmetadata,
    required int pageSize,
    required bool skipFailedPages,
    int originalDateScanPages = 0,
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
        'iiprop': [
          'url|size|sha1|mime|user',
          if (includeExtmetadata) 'extmetadata',
        ].join('|'),
        'iilimit': '$pageSize',
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

      // Wikimedia may split `prop=imageinfo` into several `iicontinue`
      // responses when thumbnail scaling is requested. Keep those requests
      // inside this logical page so callers see one profile-sized page rather
      // than a fake smaller page. The continuation returned below is therefore always
      // the generator continuation for the next logical page.
      Map<String, dynamic>? propertyContinue = continueParams;
      final pagesByKey = <String, Map<String, dynamic>>{};
      Map<String, dynamic>? nextContinue;
      int? totalHits;
      String? suggestion;
      String? searchWarning;

      for (var propertyPage = 0;; propertyPage++) {
        final requestParams = <String, String>{...params};
        if (propertyContinue != null) {
          for (final entry in propertyContinue.entries) {
            requestParams[entry.key] = entry.value.toString();
          }
        }

        final uri =
            Uri.https('commons.wikimedia.org', '/w/api.php', requestParams);

        // The shared gate owns retries, backoff, throttling, and maxlag so
        // callers cannot multiply traffic with their own retry loops.
        late final http.Response response;
        try {
          response = await _transport.get(
            uri,
            headers: {
              'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
            },
            timeout: const Duration(seconds: 15),
            category: skipFailedPages
                ? WikimediaRequestCategory.pipeline
                : WikimediaRequestCategory.search,
            // One initial request plus three retries. If all four attempts
            // fail, this logical page is skipped and pagination continues.
            maxAttempts: 4,
          );
        } catch (e) {
          return _failedPageResponse(
            continueParams: continueParams,
            pageSize: pageSize,
            skipFailedPages: skipFailedPages,
            reason:
                'request failed after the initial attempt plus 3 retries: $e',
          );
        }

        if (response.statusCode != 200) {
          return _failedPageResponse(
            continueParams: continueParams,
            pageSize: pageSize,
            skipFailedPages: skipFailedPages,
            reason: 'HTTP ${response.statusCode}',
          );
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawSearchWarning = (data['warnings'] as Map?)?['search'];
        if (rawSearchWarning is Map) {
          final fallbackWarning = rawSearchWarning.values.isEmpty
              ? null
              : rawSearchWarning.values.first;
          searchWarning =
              rawSearchWarning['*']?.toString() ?? fallbackWarning?.toString();
        } else if (rawSearchWarning != null) {
          searchWarning = rawSearchWarning.toString();
        }
        final apiError = data['error'] as Map<String, dynamic>?;
        if (apiError != null) {
          final errorCode = apiError['code'] as String?;

          // A bad thumbnail is recoverable for the whole logical page: retry
          // without scaling rather than returning an empty partial page.
          if (errorCode == 'urlparamnormal' && includeThumbWidth) {
            return _fetchSingleAttempt(
              state,
              continueParams: continueParams,
              overrideFormat: overrideFormat,
              includeThumbWidth: false,
              includeExtmetadata: includeExtmetadata,
              pageSize: pageSize,
              skipFailedPages: skipFailedPages,
              originalDateScanPages: originalDateScanPages,
            );
          }

          if (const {
            'cirrussearch-too-busy-error',
            'maxlag',
            'ratelimited',
            'urlparamnormal',
          }.contains(errorCode)) {
            return _failedPageResponse(
              continueParams: continueParams,
              pageSize: pageSize,
              skipFailedPages: skipFailedPages,
              reason: 'Wikimedia API error ${errorCode ?? 'unknown'}',
            );
          }

          return _failedPageResponse(
            continueParams: continueParams,
            pageSize: pageSize,
            skipFailedPages: skipFailedPages,
            reason: 'Wikimedia API error ${errorCode ?? 'unknown'}',
          );
        }

        final responseContinue = data['continue'] as Map<String, dynamic>?;
        final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
        for (final entry in pages.entries) {
          final page = entry.value;
          if (page is! Map) continue;
          final key = entry.key.toString();
          final merged = <String, dynamic>{
            ...?pagesByKey[key],
            ...Map<String, dynamic>.from(page),
          };
          merged['pageid'] ??= int.tryParse(key);
          final previousInfo = pagesByKey[key]?['imageinfo'];
          final currentInfo = page['imageinfo'];
          if (currentInfo is! List || currentInfo.isEmpty) {
            if (previousInfo is List && previousInfo.isNotEmpty) {
              merged['imageinfo'] = previousInfo;
            }
          }
          pagesByKey[key] = merged;
        }

        // Search metadata is normally present only on the first response.
        final searchInfo =
            data['query']?['searchinfo'] as Map<String, dynamic>?;
        totalHits ??= (searchInfo?['totalhits'] as num?)?.toInt();
        suggestion ??= searchInfo?['suggestion'] as String?;

        if (responseContinue?['iicontinue'] != null) {
          // A 200-record page normally needs at most four thumbnail property
          // responses. This guard prevents a malformed continuation from
          // creating an accidental infinite request loop.
          if (propertyPage >= 10) {
            return _failedPageResponse(
              continueParams: continueParams,
              pageSize: pageSize,
              skipFailedPages: skipFailedPages,
              reason: 'imageinfo continuation exceeded the safety limit',
            );
          }
          propertyContinue = responseContinue;
          continue;
        }

        nextContinue = responseContinue;
        break;
      }

      final items = <SearchItem>[];
      for (final page in pagesByKey.values) {
        final infoList = page['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) {
          continue;
        }

        final info = infoList.first as Map<String, dynamic>;
        final rawTitle = page['title'] as String? ?? '';

        final item = _responseMapper.itemFromImageInfo(
          info,
          rawTitle: rawTitle,
          snippet:
              _responseMapper.stripHtml(page['snippet'] as String? ?? rawTitle),
          pageId: (page['pageid'] as num?)?.toInt(),
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
            .where(
                (item) => _matchesAttribution(item, state.attributionRequired!))
            .toList();
      }

      // Commons indexes file-page creation and edit timestamps, but not the
      // date the pictured media was originally made. That value arrives as
      // DateTimeOriginal metadata with each imageinfo record, so this filter
      // necessarily runs after the page has been fetched. A missing or
      // unparseable original date is not a match: showing it would make the
      // selected range misleading.
      if (state.originalDate != null && !state.originalDate!.isEmpty) {
        filteredItems = filteredItems
            .where((item) => _matchesOriginalDate(item, state.originalDate!))
            .toList();

        // A metadata-date range cannot be sent to CirrusSearch. Do not make
        // a perfectly valid historical query look like "no results" merely
        // because the first relevance page had no dated matches. Scan up to
        // five underlying pages (250 candidates) to find the first visible
        // page, while keeping a hard cap so a sparse/undated corpus cannot
        // turn one user action into unbounded API traffic.
        if (filteredItems.isEmpty &&
            nextContinue != null &&
            originalDateScanPages < 4) {
          return _fetchSingleAttempt(
            state,
            continueParams: nextContinue,
            overrideFormat: overrideFormat,
            includeThumbWidth: includeThumbWidth,
            includeExtmetadata: includeExtmetadata,
            pageSize: pageSize,
            skipFailedPages: skipFailedPages,
            originalDateScanPages: originalDateScanPages + 1,
          );
        }
      }

      return SearchResponse(
        items: filteredItems,
        continueParams: nextContinue,
        warning: searchWarning,
        totalHits: totalHits,
        suggestion: suggestion,
      );
    } catch (e) {
      return _failedPageResponse(
        continueParams: continueParams,
        pageSize: pageSize,
        skipFailedPages: skipFailedPages,
        reason: 'unexpected response error: $e',
      );
    }
  }

  SearchResponse? _failedPageResponse({
    required Map<String, dynamic>? continueParams,
    required int pageSize,
    required bool skipFailedPages,
    required String reason,
  }) {
    if (!skipFailedPages) return null;
    return _skipFailedPage(
      continueParams: continueParams,
      pageSize: pageSize,
      reason: reason,
    );
  }

  /// Advance one logical generator page after its request exhausted retries.
  /// The generator exposes `gsroffset`; remove only `iicontinue`, which is
  /// the property-level cursor for the failed page rather than the next
  /// search page.
  SearchResponse? _skipFailedPage({
    required Map<String, dynamic>? continueParams,
    required int pageSize,
    required String reason,
  }) {
    final rawOffset = continueParams?['gsroffset'];
    final offset = rawOffset == null
        ? 0
        : rawOffset is num
            ? rawOffset.toInt()
            : int.tryParse(rawOffset.toString());
    if (offset == null) return null;

    final nextContinue = <String, dynamic>{...?continueParams};
    nextContinue.remove('iicontinue');
    nextContinue['gsroffset'] = offset + pageSize;
    nextContinue['continue'] ??= '-||';

    return SearchResponse(
      items: const [],
      continueParams: nextContinue,
      warning:
          'Skipped the $pageSize-result pipeline batch at offset $offset after 3 retries: $reason',
    );
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

  /// Normalizes the useful precision carried by Commons' heterogeneous date
  /// metadata to an ISO calendar day. EXIF commonly uses `YYYY:MM:DD`, while
  /// description templates may expose just a year or an ISO date.
  String? _originalDateDay(String raw) {
    final match =
        RegExp(r'(\d{4})(?:[-:](\d{1,2})(?:[-:](\d{1,2}))?)?').firstMatch(raw);
    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2) ?? '') ?? 1;
    final day = int.tryParse(match.group(3) ?? '') ?? 1;
    if (year == null || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  bool _matchesOriginalDate(SearchItem item, DateFilter range) {
    final day = _originalDateDay(item.dateTimeOriginal.trim());
    if (day == null) return false;
    final from = range.from?.trim() ?? '';
    final to = range.to?.trim() ?? '';
    return (from.isEmpty || day.compareTo(from) >= 0) &&
        (to.isEmpty || day.compareTo(to) < 0);
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
        case FileFormat.xcf:
          if (ext == 'xcf' || mime == 'image/x-xcf') return true;
          break;
        case FileFormat.pdf:
          if (ext == 'pdf' || mime == 'application/pdf') return true;
          break;
        case FileFormat.djvu:
          if (ext == 'djvu' ||
              mime == 'image/vnd.djvu' ||
              mime == 'application/vnd.djvu') {
            return true;
          }
          break;
        case FileFormat.ogg:
          if (ext == 'ogg' || (ext.isEmpty && mime.contains('ogg'))) {
            return true;
          }
          break;
        case FileFormat.oga:
          if (ext == 'oga' || (ext.isEmpty && mime.contains('ogg'))) {
            return true;
          }
          break;
        case FileFormat.ogx:
          if (ext == 'ogx' || (ext.isEmpty && mime.contains('ogg'))) {
            return true;
          }
          break;
        case FileFormat.opus:
          if (ext == 'opus' || (ext.isEmpty && mime.contains('ogg'))) {
            return true;
          }
          break;
        case FileFormat.ogv:
          if (ext == 'ogv' ||
              (ext.isEmpty &&
                  (mime == 'video/ogg' || mime == 'application/ogg'))) {
            return true;
          }
          break;
        case FileFormat.mp3:
          if (ext == 'mp3' || mime == 'audio/mpeg' || mime == 'audio/mp3') {
            return true;
          }
          break;
        case FileFormat.flac:
          if (ext == 'flac' || mime == 'audio/flac') return true;
          break;
        case FileFormat.midi:
          if (ext == 'mid' || ext == 'midi' || mime == 'audio/midi') {
            return true;
          }
          break;
        case FileFormat.wav:
          if (ext == 'wav' || mime == 'audio/wav' || mime == 'audio/x-wav') {
            return true;
          }
          break;
        case FileFormat.webm:
          if (ext == 'webm' || mime.contains('webm')) return true;
          break;
        case FileFormat.mpg:
          if (ext == 'mpg' || (ext.isEmpty && mime == 'video/mpeg')) {
            return true;
          }
          break;
        case FileFormat.mpeg:
          if (ext == 'mpeg' || (ext.isEmpty && mime == 'video/mpeg')) {
            return true;
          }
          break;
        case FileFormat.mp4:
          if (ext == 'mp4' || mime.contains('mp4')) return true;
          break;
        case FileFormat.stl:
          if (ext == 'stl' || mime == 'application/sla') return true;
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
}
