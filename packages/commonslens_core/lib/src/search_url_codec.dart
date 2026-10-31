import 'dart:convert';

import 'search_models.dart';

/// Compact, flat URL serialization for [SearchState].
///
/// New collection values are JSON arrays, which safely preserve punctuation
/// in user-entered labels. The reader also accepts the older `|`/`~`
/// delimiter format so existing shared links remain valid.
class SearchUrlCodec {
  const SearchUrlCodec._();

  static String? _encodeStrings(Iterable<String> values) {
    final normalized = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList()
      ..sort();
    return normalized.isEmpty ? null : jsonEncode(normalized);
  }

  static List<dynamic>? _decodeList(String raw) {
    if (!raw.trimLeft().startsWith('[')) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _jsonObject(dynamic raw) {
    if (raw is! Map) return null;
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static Set<String> _parseStrings(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = _decodeList(raw);
    final values = decoded ?? raw.split('|');
    return values
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  static Set<DepictsEntity> _parseDepicts(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = _decodeList(raw);
    if (decoded != null) {
      return decoded
          .map(_jsonObject)
          .whereType<Map<String, dynamic>>()
          .map(DepictsEntity.fromJson)
          .where((entity) => entity.qid.isNotEmpty)
          .toSet();
    }

    return raw
        .split('|')
        .where((entry) => entry.isNotEmpty)
        .map((entry) {
          final separator = entry.indexOf('~');
          if (separator < 0) return DepictsEntity(qid: entry, label: entry);
          return DepictsEntity(
            qid: entry.substring(0, separator),
            label: entry.substring(separator + 1),
          );
        })
        .where((entity) => entity.qid.isNotEmpty)
        .toSet();
  }

  static Set<WikidataStatement> _parseStatements(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    final decoded = _decodeList(raw);
    if (decoded != null) {
      return decoded
          .map(_jsonObject)
          .whereType<Map<String, dynamic>>()
          .map(WikidataStatement.fromJson)
          .where((statement) =>
              statement.property.qid.isNotEmpty &&
              statement.value.qid.isNotEmpty)
          .toSet();
    }

    return raw
        .split('|')
        .where((entry) => entry.isNotEmpty)
        .map((entry) {
          final parts = entry.split('~');
          if (parts.length != 4) return null;
          return WikidataStatement(
            property: DepictsEntity(qid: parts[0], label: parts[1]),
            value: DepictsEntity(qid: parts[2], label: parts[3]),
          );
        })
        .whereType<WikidataStatement>()
        .toSet();
  }

  static Map<String, String> toQueryParams(SearchState state) {
    final params = <String, String>{};

    final query = state.queryText.trim();
    if (query.isNotEmpty) params['q'] = query;
    if (state.tab != MediaTabType.allMedia) params['tab'] = state.tab.name;

    if (state.formats.isNotEmpty) {
      final formats = state.formats.map((format) => format.name).toList()
        ..sort();
      params['formats'] = formats.join(',');
    }

    final categories = _encodeStrings(state.categories);
    if (categories != null) params['cats'] = categories;
    final excludedCategories = _encodeStrings(state.excludeCategories);
    if (excludedCategories != null) {
      params['catsExclude'] = excludedCategories;
    }
    if (state.categoriesUnion) params['catsUnion'] = '1';

    if (state.depictsInclude.isNotEmpty) {
      final entries = state.depictsInclude.toList()
        ..sort((left, right) => left.qid.compareTo(right.qid));
      params['depictsIn'] =
          jsonEncode(entries.map((entity) => entity.toJson()).toList());
    }
    if (state.depictsExclude.isNotEmpty) {
      final entries = state.depictsExclude.toList()
        ..sort((left, right) => left.qid.compareTo(right.qid));
      params['depictsEx'] =
          jsonEncode(entries.map((entity) => entity.toJson()).toList());
    }
    if (state.depictsUnion) params['depictsUnion'] = '1';

    if (state.statementsInclude.isNotEmpty) {
      final entries = state.statementsInclude.toList()
        ..sort((left, right) => '${left.property.qid}:${left.value.qid}'
            .compareTo('${right.property.qid}:${right.value.qid}'));
      params['statementsIn'] =
          jsonEncode(entries.map((statement) => statement.toJson()).toList());
    }
    if (state.statementsExclude.isNotEmpty) {
      final entries = state.statementsExclude.toList()
        ..sort((left, right) => '${left.property.qid}:${left.value.qid}'
            .compareTo('${right.property.qid}:${right.value.qid}'));
      params['statementsEx'] =
          jsonEncode(entries.map((statement) => statement.toJson()).toList());
    }
    if (state.statementsUnion) params['statementsUnion'] = '1';

    if (state.deepCategoryMode) params['deepcat'] = '1';
    if (state.titleOnly) params['titleOnly'] = '1';
    if (state.localOnly) params['local'] = '1';

    final language = state.languageCode?.trim() ?? '';
    if (language.isNotEmpty) params['lang'] = language;
    final contentModel = state.contentModel?.trim() ?? '';
    if (contentModel.isNotEmpty) params['model'] = contentModel;

    final createdFrom = state.createdDate?.from?.trim() ?? '';
    if (createdFrom.isNotEmpty) params['createdFrom'] = createdFrom;
    final createdTo = state.createdDate?.to?.trim() ?? '';
    if (createdTo.isNotEmpty) params['createdTo'] = createdTo;
    final editedFrom = state.editedDate?.from?.trim() ?? '';
    if (editedFrom.isNotEmpty) params['editedFrom'] = editedFrom;
    final editedTo = state.editedDate?.to?.trim() ?? '';
    if (editedTo.isNotEmpty) params['editedTo'] = editedTo;

    if (state.sortMode != SortMode.relevance) {
      params['sort'] = state.sortMode.name;
    }
    if (state.licensePresets.isNotEmpty) {
      final licenses =
          state.licensePresets.map((license) => license.name).toList()..sort();
      params['licenses'] = licenses.join(',');
    }
    if (state.attributionRequired != null) {
      params['attrReq'] = state.attributionRequired! ? '1' : '0';
    }
    final selectedQualities = state.selectedQualityFilters
        .where((quality) => quality != QualityFilter.any)
        .toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    if (!state.allImagesMode &&
        selectedQualities.isNotEmpty &&
        selectedQualities.length < defaultQualityFilters.length) {
      params['quality'] =
          selectedQualities.map((quality) => quality.name).join(',');
    }

    void addPositiveInt(String key, int? value) {
      if (value != null && value > 0) params[key] = value.toString();
    }

    addPositiveInt('minW', state.minWidth);
    addPositiveInt('minH', state.minHeight);
    addPositiveInt('maxW', state.maxWidth);
    addPositiveInt('maxH', state.maxHeight);
    addPositiveInt('minBytes', state.minFileSizeBytes);
    addPositiveInt('maxBytes', state.maxFileSizeBytes);
    addPositiveInt('bits', state.colorDepthBits);

    if (state.nearCoord != null) {
      final coordinate = state.nearCoord!;
      params['lat'] = coordinate.lat.toString();
      params['lng'] = coordinate.lng.toString();
      params['radius'] = coordinate.radiusKm.toString();
    }
    if (state.nearTitle != null) {
      params['nearTitle'] = state.nearTitle!.title;
      params['nearTitleRadius'] = state.nearTitle!.radiusKm.toString();
    }

    final excludedTerms = _encodeStrings(state.excludeTerms);
    if (excludedTerms != null) params['exclude'] = excludedTerms;
    final morelike = _encodeStrings(state.morelikeTitles);
    if (morelike != null) params['morelike'] = morelike;
    final templates = _encodeStrings(state.templates);
    if (templates != null) params['templates'] = templates;
    final excludedTemplates = _encodeStrings(state.excludeTemplates);
    if (excludedTemplates != null) {
      params['templatesExclude'] = excludedTemplates;
    }

    final insource = state.insourceText?.trim() ?? '';
    if (insource.isNotEmpty) params['insource'] = insource;
    if (state.insourceRegex) params['insourceRegex'] = '1';

    return params;
  }

  static SearchState fromQueryParams(
    Map<String, String> params,
    SearchState base,
  ) {
    T enumValue<T extends Enum>(List<T> values, String? raw, T fallback) {
      if (raw == null) return fallback;
      return values.firstWhere(
        (value) => value.name == raw,
        orElse: () => fallback,
      );
    }

    Set<QualityFilter>? qualitySet(String? raw) {
      if (raw == null) return null;
      final parsed = raw
          .split(',')
          .map((value) => enumValue(
                QualityFilter.values,
                value,
                QualityFilter.any,
              ))
          .where((quality) => quality != QualityFilter.any)
          .toSet();
      return parsed;
    }

    final tab = enumValue(MediaTabType.values, params['tab'], base.tab);
    final formats = <FileFormat>{};
    for (final name in (params['formats'] ?? '').split(',')) {
      for (final format in FileFormat.values) {
        if (format.name == name) formats.add(format);
      }
    }

    final createdFrom = params['createdFrom'];
    final createdTo = params['createdTo'];
    final createdDate = createdFrom == null && createdTo == null
        ? null
        : DateFilter(from: createdFrom, to: createdTo);
    final editedFrom = params['editedFrom'];
    final editedTo = params['editedTo'];
    final editedDate = editedFrom == null && editedTo == null
        ? null
        : DateFilter(from: editedFrom, to: editedTo);

    final licenses = <LicensePreset>{};
    final licensesParam = params['licenses'];
    if (licensesParam != null && licensesParam.isNotEmpty) {
      for (final name in licensesParam.split(',')) {
        for (final license in LicensePreset.values) {
          if (license.name == name) licenses.add(license);
        }
      }
    } else {
      final legacyLicense = params['license'];
      if (legacyLicense != null) {
        for (final license in LicensePreset.values) {
          if (license.name == legacyLicense) licenses.add(license);
        }
      } else {
        licenses.addAll(base.licensePresets);
      }
    }

    final attributionParam = params['attrReq'];
    final attribution = attributionParam == null
        ? base.attributionRequired
        : attributionParam == '1';

    final latitude = double.tryParse(params['lat'] ?? '');
    final longitude = double.tryParse(params['lng'] ?? '');
    final radius = double.tryParse(params['radius'] ?? '') ?? 10;
    final nearCoord = latitude == null || longitude == null
        ? null
        : NearCoordFilter(
            lat: latitude,
            lng: longitude,
            radiusKm: radius,
          );

    final nearTitleValue = params['nearTitle'];
    final nearTitle = nearTitleValue == null || nearTitleValue.trim().isEmpty
        ? null
        : NearTitleFilter(
            title: nearTitleValue,
            radiusKm: double.tryParse(params['nearTitleRadius'] ?? '') ?? 10,
          );

    final insource = params['insource'];
    final minWidth = int.tryParse(params['minW'] ?? '');
    final minHeight = int.tryParse(params['minH'] ?? '');
    final maxWidth = int.tryParse(params['maxW'] ?? '');
    final maxHeight = int.tryParse(params['maxH'] ?? '');
    final minBytes = int.tryParse(params['minBytes'] ?? '');
    final maxBytes = int.tryParse(params['maxBytes'] ?? '');
    final colorDepth = int.tryParse(params['bits'] ?? '');

    final rawQuality = params['quality'];
    final parsedQuality = qualitySet(rawQuality);
    final allImages = rawQuality == null
        ? base.allImagesMode
        : parsedQuality == null || parsedQuality.isEmpty;

    return base.copyWith(
      queryText: params['q'] ?? base.queryText,
      tab: tab,
      formats: formats,
      categories: _parseStrings(params['cats']),
      excludeCategories: _parseStrings(params['catsExclude']),
      categoriesUnion: params['catsUnion'] == '1',
      deepCategoryMode: params['deepcat'] == '1',
      depictsInclude: _parseDepicts(params['depictsIn']),
      depictsExclude: _parseDepicts(params['depictsEx']),
      depictsUnion: params['depictsUnion'] == '1',
      statementsInclude: _parseStatements(params['statementsIn']),
      statementsExclude: _parseStatements(params['statementsEx']),
      statementsUnion: params['statementsUnion'] == '1',
      titleOnly: params['titleOnly'] == '1',
      localOnly: params['local'] == '1',
      languageCode: params['lang'],
      contentModel: params['model'],
      createdDate: createdDate,
      editedDate: editedDate,
      sortMode: enumValue(SortMode.values, params['sort'], SortMode.relevance),
      licensePresets: licenses,
      qualityFilters: parsedQuality ?? base.selectedQualityFilters,
      allImages: allImages,
      attributionRequired: attribution,
      clearAttributionRequired: attribution == null,
      minWidth: minWidth,
      clearMinWidth: minWidth == null,
      minHeight: minHeight,
      clearMinHeight: minHeight == null,
      maxWidth: maxWidth,
      clearMaxWidth: maxWidth == null,
      maxHeight: maxHeight,
      clearMaxHeight: maxHeight == null,
      minFileSizeBytes: minBytes,
      clearMinFileSizeBytes: minBytes == null,
      maxFileSizeBytes: maxBytes,
      clearMaxFileSizeBytes: maxBytes == null,
      colorDepthBits: colorDepth,
      clearColorDepthBits: colorDepth == null,
      nearCoord: nearCoord,
      clearNearCoord: nearCoord == null,
      nearTitle: nearTitle,
      clearNearTitle: nearTitle == null,
      excludeTerms: _parseStrings(params['exclude']),
      morelikeTitles: _parseStrings(params['morelike']),
      templates: _parseStrings(params['templates']),
      excludeTemplates: _parseStrings(params['templatesExclude']),
      insourceText: insource,
      clearInsourceText: insource == null,
      insourceRegex: params['insourceRegex'] == '1',
    );
  }

  static bool hasSearchContext(Map<String, String> params) {
    final relevant = Map<String, String>.from(params)
      ..remove('id')
      ..remove('view')
      ..remove('from');
    return relevant.isNotEmpty;
  }
}
