part of 'pipeline_engine.dart';

mixin _PipelineCollectionOperations {
  Future<NodeOutput> _ensureMaterialized(
      NodeOutput output, PipelineExecutionContext ctx) async {
    if (output.hasError || output.isMaterialized) return output;
    return _materializeState(output.pendingState!, ctx);
  }

  Future<NodeOutput> _executeFilter(
    PipelineNode node,
    List<MapEntry<String, NodeOutput>> inputs,
    PipelineExecutionContext ctx,
  ) async {
    if (inputs.isEmpty) {
      return NodeOutput.errorResult('${node.title} has no input connected.');
    }
    final input = inputs.first.value;
    if (input.hasError) return input;

    if (input.isPending) {
      // Still an unbranched chain — fold into the pending SearchState
      // instead of fetching anything.
      return NodeOutput.pending(_applyFilterToState(node, input.pendingState!));
    }

    final items = input.items!;
    if (!_hasClientSidePredicate(node.type)) {
      return NodeOutput.materialized(
        items,
        records: input.records,
        warning:
            '"${node.title}" can\'t apply after a Union/Intersect or a source like '
            'Author/Geosearch-browse — reconnect it directly after a single Source instead. '
            'Passed through unfiltered.',
      );
    }

    final predicate = _clientPredicateFor(node);
    final kept = <int>[];
    for (var index = 0; index < items.length; index++) {
      if (predicate(items[index])) kept.add(index);
    }
    return _selectIndexes(input, kept);
  }

  SearchState _applyFilterToState(PipelineNode node, SearchState state) {
    final c = node.config;
    switch (node.type) {
      case PipelineNodeType.filterLicense:
        final presets = _cfgStringList(c, 'licenses')
            .map((n) =>
                _firstWhereOrNull(LicensePreset.values, (l) => l.name == n))
            .whereType<LicensePreset>()
            .toSet();
        return state
            .copyWith(licensePresets: {...state.licensePresets, ...presets});

      case PipelineNodeType.filterQuality:
        final name = _cfgString(c, 'quality');
        final q =
            _firstWhereOrNull(QualityFilter.values, (v) => v.name == name);
        if (q == null) return state;
        final mode = _firstWhereOrNull(
          QualityMatchMode.values,
          (value) => value.name == _cfgString(c, 'qualityMode', 'individual'),
        );
        return state.copyWith(
          qualityFilter: q,
          qualityMatchMode: mode ?? QualityMatchMode.individual,
        );

      case PipelineNodeType.filterFormat:
        final formats = _cfgStringList(c, 'formats')
            .map(
                (n) => _firstWhereOrNull(FileFormat.values, (f) => f.name == n))
            .whereType<FileFormat>()
            .toSet();
        return state.copyWith(formats: {...state.formats, ...formats});

      case PipelineNodeType.filterResolution:
        final minW = _cfgInt(c, 'minWidth');
        final minH = _cfgInt(c, 'minHeight');
        final maxW = _cfgInt(c, 'maxWidth');
        final maxH = _cfgInt(c, 'maxHeight');
        return state.copyWith(
          minWidth: minW,
          clearMinWidth: minW == null,
          minHeight: minH,
          clearMinHeight: minH == null,
          maxWidth: maxW,
          clearMaxWidth: maxW == null,
          maxHeight: maxH,
          clearMaxHeight: maxH == null,
        );

      case PipelineNodeType.filterFileSize:
        final minB = _cfgInt(c, 'minBytes');
        final maxB = _cfgInt(c, 'maxBytes');
        return state.copyWith(
          minFileSizeBytes: minB,
          clearMinFileSizeBytes: minB == null,
          maxFileSizeBytes: maxB,
          clearMaxFileSizeBytes: maxB == null,
        );

      case PipelineNodeType.filterColorDepth:
        final bits = _cfgInt(c, 'bits');
        return state.copyWith(
            colorDepthBits: bits, clearColorDepthBits: bits == null);

      case PipelineNodeType.filterDateRange:
        final from = _cfgString(c, 'from');
        final to = _cfgString(c, 'to');
        final field = _cfgString(c, 'field', 'created');
        final filter = (from.isEmpty && to.isEmpty)
            ? null
            : DateFilter(
                from: from.isEmpty ? null : from, to: to.isEmpty ? null : to);
        switch (field) {
          case 'edited':
            return state.copyWith(
                editedDate: filter, clearEditedDate: filter == null);
          case 'original': // Legacy pipeline value.
          case 'originalDate':
            return state.copyWith(
                originalDate: filter, clearOriginalDate: filter == null);
          default:
            return state.copyWith(
                createdDate: filter, clearCreatedDate: filter == null);
        }

      case PipelineNodeType.filterLanguage:
        final lang = _cfgString(c, 'language');
        return state.copyWith(
          languageCode: lang.isEmpty ? null : lang,
          clearLanguageCode: lang.isEmpty,
        );

      case PipelineNodeType.filterExcludeTerms:
        final terms = _cfgStringList(c, 'terms').toSet();
        return state.copyWith(excludeTerms: {...state.excludeTerms, ...terms});

      default:
        return state;
    }
  }

  /// Only called for the filter types [_hasClientSidePredicate] says are
  /// honest to check post-fetch.
  bool Function(SearchItem) _clientPredicateFor(PipelineNode node) {
    final c = node.config;
    switch (node.type) {
      case PipelineNodeType.filterFormat:
        final names = _cfgStringList(c, 'formats').toSet();
        if (names.isEmpty) return (_) => true;
        return (item) => names.any((n) =>
            item.extension.toLowerCase() == n.toLowerCase() ||
            item.fileTypeLabel.toLowerCase() == n.toLowerCase());

      case PipelineNodeType.filterResolution:
        final minW = _cfgInt(c, 'minWidth');
        final minH = _cfgInt(c, 'minHeight');
        final maxW = _cfgInt(c, 'maxWidth');
        final maxH = _cfgInt(c, 'maxHeight');
        return (item) =>
            (minW == null || item.width >= minW) &&
            (minH == null || item.height >= minH) &&
            (maxW == null || item.width <= maxW) &&
            (maxH == null || item.height <= maxH);

      case PipelineNodeType.filterDateRange:
        final from = _cfgString(c, 'from');
        final to = _cfgString(c, 'to');
        final field = _cfgString(c, 'field', 'created');
        final fromD = from.isEmpty ? null : DateTime.tryParse(from);
        final toD = to.isEmpty ? null : DateTime.tryParse(to);
        return (item) {
          final raw = field == 'edited'
              ? (item.uploadDateTime.isNotEmpty
                  ? item.uploadDateTime
                  : (item.timestamp ?? ''))
              : item.dateTimeOriginal;
          final dt = DateTime.tryParse(raw);
          if (dt == null) return false;
          if (fromD != null && dt.isBefore(fromD)) return false;
          if (toD != null && !dt.isBefore(toD)) return false;
          return true;
        };

      case PipelineNodeType.filterExcludeTerms:
        final terms =
            _cfgStringList(c, 'terms').map((t) => t.toLowerCase()).toList();
        if (terms.isEmpty) return (_) => true;
        return (item) {
          final haystack = '${item.title} ${item.snippet}'.toLowerCase();
          return !terms.any(haystack.contains);
        };

      default:
        return (_) => true;
    }
  }

  // ---------------------------------------------------------------------
  // Set operations. Combine Constraints (AND) is deliberately different
  // from the list operations: it combines two pending SearchStates before
  // either branch fetches, so Commons evaluates the full query server-side.
  // Union/Intersect/Difference retain their materialized URL-set behavior.
  // ---------------------------------------------------------------------

  bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  T _mergeDefaulted<T>(T a, T b, T neutral, String label) {
    if (a == neutral) return b;
    if (b == neutral || a == b) return a;
    throw StateError('Both branches specify different $label values.');
  }

  T? _mergeNullable<T>(T? a, T? b, String label) {
    if (a == null) return b;
    if (b == null || a == b) return a;
    throw StateError('Both branches specify different $label values.');
  }

  Set<T> _mergeAlternativeSet<T>(Set<T> a, Set<T> b, String label) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final overlap = a.intersection(b);
    if (overlap.isEmpty) {
      throw StateError('The two $label constraints have no overlap.');
    }
    return overlap;
  }

  ({Set<T> values, bool union}) _mergeGroupedSet<T>(
    Set<T> a,
    bool aUnion,
    Set<T> b,
    bool bUnion,
    String label,
  ) {
    if (a.isEmpty) return (values: b, union: bUnion);
    if (b.isEmpty) return (values: a, union: aUnion);
    if (!aUnion && !bUnion) {
      return (values: {...a, ...b}, union: false);
    }
    if (aUnion == bUnion && _sameSet(a, b)) {
      return (values: a, union: aUnion);
    }
    throw StateError(
      '$label contains separate OR groups that cannot be represented by one Commons query.',
    );
  }

  DateFilter? _mergeDateFilter(DateFilter? a, DateFilter? b, String label) {
    if (a == null || a.isEmpty) return b;
    if (b == null || b.isEmpty) return a;

    String? later(String? x, String? y) {
      if (x == null || x.isEmpty) return y;
      if (y == null || y.isEmpty) return x;
      final xd = DateTime.tryParse(x);
      final yd = DateTime.tryParse(y);
      if (xd != null && yd != null) return xd.isAfter(yd) ? x : y;
      return x.compareTo(y) >= 0 ? x : y;
    }

    String? earlier(String? x, String? y) {
      if (x == null || x.isEmpty) return y;
      if (y == null || y.isEmpty) return x;
      final xd = DateTime.tryParse(x);
      final yd = DateTime.tryParse(y);
      if (xd != null && yd != null) return xd.isBefore(yd) ? x : y;
      return x.compareTo(y) <= 0 ? x : y;
    }

    final from = later(a.from, b.from);
    final to = earlier(a.to, b.to);
    final fromDate = from == null ? null : DateTime.tryParse(from);
    final toDate = to == null ? null : DateTime.tryParse(to);
    if (fromDate != null && toDate != null && !fromDate.isBefore(toDate)) {
      throw StateError('The $label ranges do not overlap.');
    }
    return DateFilter(from: from, to: to);
  }

  NearCoordFilter? _mergeNearCoord(NearCoordFilter? a, NearCoordFilter? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.lat == b.lat && a.lng == b.lng && a.radiusKm == b.radiusKm) {
      return a;
    }
    throw StateError('Both branches specify different coordinate searches.');
  }

  NearTitleFilter? _mergeNearTitle(NearTitleFilter? a, NearTitleFilter? b) {
    if (a == null) return b;
    if (b == null) return a;
    if (a.title == b.title && a.radiusKm == b.radiusKm) return a;
    throw StateError('Both branches specify different nearby-title searches.');
  }

  SearchState _combinePendingStates(SearchState a, SearchState b) {
    final categories = _mergeGroupedSet(
      a.categories,
      a.categoriesUnion,
      b.categories,
      b.categoriesUnion,
      'Categories',
    );
    final depicts = _mergeGroupedSet(
      a.depictsInclude,
      a.depictsUnion,
      b.depictsInclude,
      b.depictsUnion,
      'Depicts',
    );
    final statements = _mergeGroupedSet(
      a.statementsInclude,
      a.statementsUnion,
      b.statementsInclude,
      b.statementsUnion,
      'Wikidata statements',
    );

    final nearCoord = _mergeNearCoord(a.nearCoord, b.nearCoord);
    final nearTitle = _mergeNearTitle(a.nearTitle, b.nearTitle);
    if (nearCoord != null && nearTitle != null) {
      throw StateError(
        'Coordinate and nearby-title searches cannot be combined in one query.',
      );
    }

    final insourceText = _mergeNullable(
      a.insourceText,
      b.insourceText,
      'insource',
    );
    if (a.insourceText != null &&
        b.insourceText != null &&
        a.insourceRegex != b.insourceRegex) {
      throw StateError('Both branches use incompatible insource modes.');
    }

    final minWidth = [a.minWidth, b.minWidth]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n > v ? n : v);
    final minHeight = [a.minHeight, b.minHeight]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n > v ? n : v);
    final maxWidth = [a.maxWidth, b.maxWidth]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n < v ? n : v);
    final maxHeight = [a.maxHeight, b.maxHeight]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n < v ? n : v);
    final minBytes = [a.minFileSizeBytes, b.minFileSizeBytes]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n > v ? n : v);
    final maxBytes = [a.maxFileSizeBytes, b.maxFileSizeBytes]
        .whereType<int>()
        .fold<int?>(null, (v, n) => v == null || n < v ? n : v);

    if (minWidth != null && maxWidth != null && minWidth > maxWidth) {
      throw StateError('The width constraints do not overlap.');
    }
    if (minHeight != null && maxHeight != null && minHeight > maxHeight) {
      throw StateError('The height constraints do not overlap.');
    }
    if (minBytes != null && maxBytes != null && minBytes > maxBytes) {
      throw StateError('The file-size constraints do not overlap.');
    }

    final leftQuery = a.queryText.trim();
    final rightQuery = b.queryText.trim();
    final queryText = leftQuery.isEmpty
        ? rightQuery
        : rightQuery.isEmpty || leftQuery == rightQuery
            ? leftQuery
            : '$leftQuery $rightQuery';

    return SearchState(
      queryText: queryText,
      tab: _mergeDefaulted(a.tab, b.tab, MediaTabType.allMedia, 'media type'),
      formats: _mergeAlternativeSet(a.formats, b.formats, 'file-format'),
      categories: categories.values,
      deepCategoryMode: a.deepCategoryMode || b.deepCategoryMode,
      categoriesUnion: categories.union,
      titleOnly: a.titleOnly || b.titleOnly,
      localOnly: a.localOnly || b.localOnly,
      languageCode: _mergeNullable(a.languageCode, b.languageCode, 'language'),
      contentModel:
          _mergeNullable(a.contentModel, b.contentModel, 'content model'),
      createdDate:
          _mergeDateFilter(a.createdDate, b.createdDate, 'creation-date'),
      editedDate: _mergeDateFilter(a.editedDate, b.editedDate, 'edit-date'),
      originalDate:
          _mergeDateFilter(a.originalDate, b.originalDate, 'original-date'),
      sortMode: _mergeDefaulted(
          a.sortMode, b.sortMode, SortMode.relevance, 'sort mode'),
      licensePresets:
          _mergeAlternativeSet(a.licensePresets, b.licensePresets, 'license'),
      qualityFilter: _mergeDefaulted(
          a.qualityFilter, b.qualityFilter, QualityFilter.any, 'quality'),
      attributionRequired: _mergeNullable(a.attributionRequired,
          b.attributionRequired, 'attribution requirement'),
      minWidth: minWidth,
      minHeight: minHeight,
      depictsInclude: depicts.values,
      depictsExclude: {...a.depictsExclude, ...b.depictsExclude},
      depictsUnion: depicts.union,
      excludeCategories: {...a.excludeCategories, ...b.excludeCategories},
      nearCoord: nearCoord,
      nearTitle: nearTitle,
      statementsInclude: statements.values,
      statementsExclude: {...a.statementsExclude, ...b.statementsExclude},
      statementsUnion: statements.union,
      excludeTerms: {...a.excludeTerms, ...b.excludeTerms},
      morelikeTitles: {...a.morelikeTitles, ...b.morelikeTitles},
      insourceText: insourceText,
      insourceRegex: a.insourceText != null ? a.insourceRegex : b.insourceRegex,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minFileSizeBytes: minBytes,
      maxFileSizeBytes: maxBytes,
      colorDepthBits:
          _mergeNullable(a.colorDepthBits, b.colorDepthBits, 'color depth'),
      templates: {...a.templates, ...b.templates},
      excludeTemplates: {...a.excludeTemplates, ...b.excludeTemplates},
    );
  }

  Future<NodeOutput> _executeSetOp(
    PipelineNode node,
    List<MapEntry<String, NodeOutput>> inputs,
    PipelineExecutionContext ctx,
  ) async {
    final aEntry = _firstWhereOrNull(inputs, (e) => e.key == 'a');
    final bEntry = _firstWhereOrNull(inputs, (e) => e.key == 'b');
    if (aEntry == null || bEntry == null) {
      return NodeOutput.errorResult(
          '${node.title} needs both A and B connected.');
    }

    if (aEntry.value.hasError) return aEntry.value;
    if (bEntry.value.hasError) return bEntry.value;

    if (node.type == PipelineNodeType.setCombineAnd) {
      if (!aEntry.value.isPending || !bEntry.value.isPending) {
        return NodeOutput.errorResult(
          '${node.title} can only combine query-capable branches before they are fetched. '
          'Use Intersect for materialized branches such as Author Uploads or Geosearch Browse.',
        );
      }
      try {
        return NodeOutput.pending(_combinePendingStates(
          aEntry.value.pendingState!,
          bEntry.value.pendingState!,
        ));
      } on StateError catch (error) {
        return NodeOutput.errorResult('${node.title}: ${error.message}');
      }
    }

    final aOut = await _ensureMaterialized(aEntry.value, ctx);
    if (aOut.hasError) return aOut;
    final bOut = await _ensureMaterialized(bEntry.value, ctx);
    if (bOut.hasError) return bOut;

    final aItems = aOut.items!;
    final bItems = bOut.items!;
    final bUrls = bItems.map((i) => i.url).toSet();

    switch (node.type) {
      case PipelineNodeType.setUnion:
        final seen = <String>{};
        final mergedItems = <SearchItem>[];
        final hasRecords = aOut.records != null || bOut.records != null;
        final mergedRecords = <Map<String, dynamic>>[];
        final aRecords = hasRecords ? _recordsFor(aOut) : null;
        final bRecords = hasRecords ? _recordsFor(bOut) : null;
        for (final entry in [
          (items: aItems, records: aRecords),
          (items: bItems, records: bRecords),
        ]) {
          for (var index = 0; index < entry.items.length; index++) {
            if (!seen.add(entry.items[index].url)) continue;
            mergedItems.add(entry.items[index]);
            if (entry.records != null) mergedRecords.add(entry.records![index]);
          }
        }
        return NodeOutput.materialized(
          mergedItems,
          records: hasRecords ? mergedRecords : null,
        );

      case PipelineNodeType.setIntersect:
        return _selectIndexes(
          aOut,
          [
            for (var index = 0; index < aItems.length; index++)
              if (bUrls.contains(aItems[index].url)) index,
          ],
        );

      case PipelineNodeType.setDifference:
        return _selectIndexes(
          aOut,
          [
            for (var index = 0; index < aItems.length; index++)
              if (!bUrls.contains(aItems[index].url)) index,
          ],
        );

      case PipelineNodeType.setCombineAnd:
        return NodeOutput.errorResult('Unhandled set-op: ${node.type}');

      default:
        return NodeOutput.errorResult('Unhandled set-op: ${node.type}');
    }
  }

  // ---------------------------------------------------------------------
  // Transform — always client-side, always materializes its input first.
  // ---------------------------------------------------------------------

  Future<NodeOutput> _executeTransform(
    PipelineNode node,
    List<MapEntry<String, NodeOutput>> inputs,
    PipelineExecutionContext ctx,
  ) async {
    if (inputs.isEmpty) {
      return NodeOutput.errorResult('${node.title} has no input connected.');
    }
    final input = await _ensureMaterialized(inputs.first.value, ctx);
    if (input.hasError) return input;
    final items = input.items!;
    final c = node.config;

    switch (node.type) {
      case PipelineNodeType.transformDedupe:
        final seen = <String>{};
        final kept = <int>[];
        for (var index = 0; index < items.length; index++) {
          if (seen.add(items[index].url)) kept.add(index);
        }
        return _selectIndexes(input, kept);

      case PipelineNodeType.transformSort:
        final modeName = _cfgString(c, 'sortMode', SortMode.relevance.name);
        final mode =
            _firstWhereOrNull(SortMode.values, (m) => m.name == modeName) ??
                SortMode.relevance;
        final sorted = _applySort(items, mode);
        return _reorderOutput(input, sorted);

      case PipelineNodeType.transformSample:
        final limit = _cfgInt(c, 'limit') ?? items.length;
        final indexes = List<int>.generate(items.length, (index) => index);
        if (_cfgBool(c, 'shuffle')) indexes.shuffle();
        return _selectIndexes(input, indexes.take(limit).toList());

      case PipelineNodeType.transformFieldSelect:
        final fields = _cfgStringList(c, 'fields');
        if (fields.isEmpty) {
          return NodeOutput.materialized(
            items,
            records: input.records,
            warning: 'Choose at least one field; all fields were kept.',
          );
        }
        final rows = _recordsFor(input);
        return NodeOutput.materialized(
          items,
          records: rows
              .map((row) => <String, dynamic>{
                    for (final field in fields)
                      if (row.containsKey(field)) field: row[field],
                  })
              .toList(),
        );

      case PipelineNodeType.transformEnrich:
        final includeImageInfo = _cfgBool(c, 'imageInfo', true);
        // Keep optional bundles opt-in so adding Enrich does not unexpectedly
        // fetch large payloads. The selected bundles are batched below.
        final includeSdc = _cfgBool(c, 'structuredData', false);
        final includeUsage = _cfgBool(c, 'globalUsage', false);
        final configuredCap = _cfgInt(c, 'maxEnrich') ?? 20;
        final cap = configuredCap.clamp(0, items.length);
        final batchSize = (_cfgInt(c, 'batchSize') ?? 10).clamp(1, 20);
        final usageLimit = (_cfgInt(c, 'usageLimit') ?? 50).clamp(1, 500);
        final rows = _recordsFor(input);
        final enrichWarnings = <String>[];

        // Technical imageinfo is batched because it is the part of this node
        // that can be fetched for several files in one request. extmetadata
        // is deliberately not requested here.
        if (includeImageInfo && cap > 0) {
          final pending = <int>[];
          for (var index = 0; index < cap; index++) {
            final item = items[index];
            final key = _enrichmentCacheKey('imageInfo', item);
            final cached =
                ctx.cache == null ? null : await ctx.cache!.getMetadata(key);
            if (cached != null) {
              rows[index]['imageInfo'] =
                  cached['_missing'] == true ? null : cached;
            } else {
              pending.add(index);
            }
          }

          for (var start = 0; start < pending.length; start += batchSize) {
            final indexes = pending.skip(start).take(batchSize).toList();
            late final Map<String, Map<String, dynamic>> fetched;
            try {
              fetched = await ctx.backend.imageMetadataBatch(
                indexes.map((index) => items[index].title).toList(),
              );
            } catch (e) {
              enrichWarnings.add(
                  'Skipped technical metadata batch at item ${indexes.first + 1} after retries: $e');
              for (final index in indexes) {
                rows[index]['imageInfo'] = null;
              }
              continue;
            }
            final batchSucceeded = fetched.isNotEmpty;
            for (final index in indexes) {
              final item = items[index];
              final payload = _metadataPayloadFor(fetched, item.title);
              rows[index]['imageInfo'] = payload;
              if (ctx.cache != null && (payload != null || batchSucceeded)) {
                await ctx.cache!.putMetadata(
                  _enrichmentCacheKey('imageInfo', item),
                  payload ?? {'_missing': true},
                );
              }
            }
          }
        }

        // Structured Data is a MediaInfo entity lookup, not an image-by-image
        // operation. Resolve all uncached entities in one batch, while
        // reusing page IDs already returned by the source search.
        if (includeSdc && cap > 0) {
          final pending = <int>[];
          final pageIds = <String, int?>{};
          for (var index = 0; index < cap; index++) {
            final item = items[index];
            final key = _enrichmentCacheKey('structuredData', item);
            final cached =
                ctx.cache == null ? null : await ctx.cache!.getMetadata(key);
            if (cached != null) {
              rows[index]['structuredData'] =
                  cached['_missing'] == true ? null : cached;
            } else {
              pending.add(index);
              pageIds[item.title] = item.pageId;
            }
          }

          if (pending.isNotEmpty) {
            late final Map<String, StructuredDataResult> fetched;
            try {
              fetched = await ctx.backend.structuredDataBatch(
                pending.map((index) => items[index].title).toList(),
                pageIds: pageIds,
              );
            } catch (e) {
              enrichWarnings.add(
                  'Skipped Structured Data batch at item ${pending.first + 1} after retries: $e');
              for (final index in pending) {
                rows[index]['structuredData'] = null;
              }
              fetched = const <String, StructuredDataResult>{};
            }
            final batchSucceeded = fetched.isNotEmpty;
            for (final index in pending) {
              final item = items[index];
              final title = item.title.startsWith('File:')
                  ? item.title
                  : 'File:${item.title}';
              final value = fetched[title]?.toJson();
              rows[index]['structuredData'] = value;
              if (ctx.cache != null && (value != null || batchSucceeded)) {
                await ctx.cache!.putMetadata(
                  _enrichmentCacheKey('structuredData', item),
                  value ?? {'_missing': true},
                );
              }
            }
          }
        }

        // Global usage also accepts multiple file titles in one request. The
        // configured usageLimit remains the user's explicit per-file bound;
        // batching changes only the number of API calls, not the data contract.
        if (includeUsage && cap > 0) {
          final pending = <int>[];
          for (var index = 0; index < cap; index++) {
            final item = items[index];
            final key = _enrichmentCacheKey('globalUsage:$usageLimit', item);
            final cached =
                ctx.cache == null ? null : await ctx.cache!.getMetadata(key);
            final usageJson = cached?['entries'];
            if (usageJson is List) {
              rows[index]['globalUsage'] = usageJson;
              rows[index]['globalUsageCount'] = usageJson.length;
            } else {
              pending.add(index);
            }
          }

          if (pending.isNotEmpty) {
            late final Map<String, List<GlobalUsageEntry>> fetched;
            try {
              fetched = await ctx.backend.globalUsageBatch(
                pending.map((index) => items[index].title).toList(),
                limit: usageLimit,
              );
            } catch (e) {
              enrichWarnings.add(
                  'Skipped global usage batch at item ${pending.first + 1} after retries: $e');
              for (final index in pending) {
                rows[index]['globalUsage'] = null;
                rows[index]['globalUsageCount'] = null;
              }
              fetched = const <String, List<GlobalUsageEntry>>{};
            }
            for (final index in pending) {
              final item = items[index];
              final title = item.title.startsWith('File:')
                  ? item.title
                  : 'File:${item.title}';
              final fetchedEntries = fetched[title];
              if (fetchedEntries == null) {
                // The batch itself failed; do not negative-cache a transport
                // failure as if Wikimedia had returned an empty usage list.
                rows[index]['globalUsage'] = null;
                rows[index]['globalUsageCount'] = null;
                continue;
              }
              final entries =
                  fetchedEntries.map((entry) => entry.toJson()).toList();
              rows[index]['globalUsage'] = entries;
              rows[index]['globalUsageCount'] = entries.length;
              if (ctx.cache != null) {
                await ctx.cache!.putMetadata(
                  _enrichmentCacheKey('globalUsage:$usageLimit', item),
                  {'entries': entries},
                );
              }
            }
          }
        }

        return NodeOutput.materialized(
          items,
          records: rows,
          warning: <String>[
            if (input.warning != null) input.warning!,
            if (cap < items.length)
              'Enriched $cap of ${items.length} items. Increase the cap to process more.',
            ...enrichWarnings,
          ].join(' ').trim().isEmpty
              ? null
              : <String>[
                  if (input.warning != null) input.warning!,
                  if (cap < items.length)
                    'Enriched $cap of ${items.length} items. Increase the cap to process more.',
                  ...enrichWarnings,
                ].join(' '),
        );

      default:
        return NodeOutput.errorResult('Unhandled transform: ${node.type}');
    }
  }

  List<Map<String, dynamic>> _recordsFor(NodeOutput output) {
    final existing = output.records;
    if (existing != null && existing.length == output.items!.length) {
      return existing.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    return output.items!
        .map((item) => Map<String, dynamic>.from(item.toJson()))
        .toList();
  }

  Map<String, dynamic>? _metadataPayloadFor(
      Map<String, Map<String, dynamic>> fetched, String title) {
    final bare = title.startsWith('File:') ? title.substring(5) : title;
    return fetched['File:$bare'] ?? fetched[bare];
  }

  String _enrichmentCacheKey(String bundle, SearchItem item) {
    final revisionKey = item.sha1.isNotEmpty
        ? item.sha1
        : '${item.pageId ?? ''}|${item.timestamp ?? item.uploadDateTime}';
    return 'pipeline-metadata-v2|$bundle|'
        '${Uri.encodeComponent(item.title)}|${Uri.encodeComponent(revisionKey)}';
  }

  NodeOutput _selectIndexes(NodeOutput input, List<int> indexes) {
    final items = input.items!;
    final records = input.records;
    return NodeOutput.materialized(
      indexes.map((index) => items[index]).toList(),
      totalHits: input.totalHits,
      warning: input.warning,
      records: records == null
          ? null
          : indexes.map((index) => records[index]).toList(),
    );
  }

  NodeOutput _reorderOutput(NodeOutput input, List<SearchItem> reordered) {
    if (input.records == null) return NodeOutput.materialized(reordered);
    final queues = <String, List<int>>{};
    for (var index = 0; index < input.items!.length; index++) {
      queues.putIfAbsent(input.items![index].url, () => []).add(index);
    }
    final indexes = <int>[];
    for (final item in reordered) {
      final queue = queues[item.url];
      if (queue != null && queue.isNotEmpty) indexes.add(queue.removeAt(0));
    }
    return _selectIndexes(input, indexes);
  }

  /// Mirrors SearchService._multiSort's non-relevance branches — same
  /// "sort by raw revision timestamp" limitation that engine already has
  /// for a client-side re-sort after merging pages, not a new one
  /// introduced here.
  List<SearchItem> _applySort(List<SearchItem> items, SortMode mode) {
    final sorted = List<SearchItem>.from(items);
    switch (mode) {
      case SortMode.relevance:
        break;
      case SortMode.titleMatch:
        sorted.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case SortMode.newestEdited:
      case SortMode.oldestEdited:
      case SortMode.newestCreated:
      case SortMode.oldestCreated:
        sorted.sort((a, b) {
          final cmp = (a.timestamp ?? '').compareTo(b.timestamp ?? '');
          final newest =
              mode == SortMode.newestCreated || mode == SortMode.newestEdited;
          return newest ? -cmp : cmp;
        });
        break;
    }
    return sorted;
  }

  // ---------------------------------------------------------------------
  // Sink — validates/materializes only. Writing files or pushing into
  // searchControllerProvider is PipelineController's job, not the engine's.
  // ---------------------------------------------------------------------

  Future<NodeOutput> _executeSink(
    PipelineNode node,
    List<MapEntry<String, NodeOutput>> inputs,
    PipelineExecutionContext ctx,
  ) async {
    if (inputs.isEmpty) {
      return NodeOutput.errorResult('${node.title} has no input connected.');
    }
    final output = await _ensureMaterialized(inputs.first.value, ctx);
    if (output.hasError || !output.isMaterialized) return output;

    if (!ctx.unlimitedCsvExport &&
        node.type == PipelineNodeType.sinkCsvExport &&
        _cfgString(node.config, 'resultScope', 'all') == 'custom') {
      final limit =
          (_cfgInt(node.config, 'maxRecords') ?? 1000).clamp(1, 1000000);
      if (output.items!.length > limit) {
        return _selectIndexes(
          output,
          List<int>.generate(limit, (index) => index),
        );
      }
    }

    return output;
  }
}
