import 'package:meta/meta.dart';

/// Parses [raw] as one of [values] by name, falling back to [fallback] for
/// anything missing, wrong-typed, or unrecognized — used by every
/// `fromJson` below so malformed input from an external caller (a JSON
/// server's request body, an agent's tool call) degrades to a sane default
/// instead of throwing and taking the whole parse down with it.
T _enumFromJson<T extends Enum>(List<T> values, dynamic raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}

/// Same as [_enumFromJson] but for list contexts (e.g. `formats`) where an
/// unrecognized entry should just be dropped from the set rather than
/// silently replaced with some fallback value.
T? _enumFromJsonOrNull<T extends Enum>(List<T> values, dynamic raw) {
  if (raw is! String) return null;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return null;
}

String? _stringOrNull(dynamic raw) => raw is String ? raw : null;

bool? _boolOrNull(dynamic raw) => raw is bool ? raw : null;

int? _intOrNull(dynamic raw) => raw is num ? raw.toInt() : null;

double? _doubleOrNull(dynamic raw) => raw is num ? raw.toDouble() : null;

Map<String, dynamic>? _jsonObject(dynamic raw) {
  if (raw is! Map) return null;
  return {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    identical(left, right) ||
    (left.length == right.length && left.containsAll(right));

int _setHash<T>(Set<T> values) => Object.hashAllUnordered(values);

enum MediaTabType {
  allMedia,
  images,
  vectors,
  audio,
  video,
  documents,
  threeD,
}

enum FileFormat {
  jpg,
  jpeg,
  png,
  svg,
  gif,
  tif,
  tiff,
  webp,
  xcf,
  pdf,
  djvu,
  ogg,
  oga,
  ogx,
  opus,
  ogv,
  mp3,
  flac,
  midi,
  wav,
  webm,
  mpg,
  mpeg,
  mp4,
  stl,
}

enum SortMode {
  relevance,
  newestEdited,
  oldestEdited,
  newestCreated,
  oldestCreated,
  titleMatch,
}

enum LicensePreset {
  cc0,
  ccBy1,
  ccBy2,
  ccBy25,
  ccBy3,
  ccBy4,
  ccBySa1,
  ccBySa2,
  ccBySa25,
  ccBySa3,
  ccBySa4,
  gfdl11,
  gfdl12,
  gfdl13,
  freeArt12,
  freeArt13,
  publicDomain,
}

String licensePresetLabel(LicensePreset preset) {
  switch (preset) {
    case LicensePreset.cc0:
      return 'CC0';
    case LicensePreset.ccBy1:
      return 'CC BY 1.0';
    case LicensePreset.ccBy2:
      return 'CC BY 2.0';
    case LicensePreset.ccBy25:
      return 'CC BY 2.5';
    case LicensePreset.ccBy3:
      return 'CC BY 3.0';
    case LicensePreset.ccBy4:
      return 'CC BY 4.0';
    case LicensePreset.ccBySa1:
      return 'CC BY-SA 1.0';
    case LicensePreset.ccBySa2:
      return 'CC BY-SA 2.0';
    case LicensePreset.ccBySa25:
      return 'CC BY-SA 2.5';
    case LicensePreset.ccBySa3:
      return 'CC BY-SA 3.0';
    case LicensePreset.ccBySa4:
      return 'CC BY-SA 4.0';
    case LicensePreset.gfdl11:
      return 'GFDL 1.1';
    case LicensePreset.gfdl12:
      return 'GFDL 1.2';
    case LicensePreset.gfdl13:
      return 'GFDL 1.3';
    case LicensePreset.freeArt12:
      return 'Free Art 1.2';
    case LicensePreset.freeArt13:
      return 'Free Art 1.3';
    case LicensePreset.publicDomain:
      return 'Public domain';
  }
}

enum QualityFilter {
  any,
  qualityImage,
  valuedImage,
  featuredPicture,
}

/// Controls how a selected quality assessment is interpreted.
///
/// Commons does not store these assessments as one server-side numeric grade,
/// so the "and above" mode is a CommonsLens convenience that expands the
/// selected assessment into a union of assessment searches.
enum QualityMatchMode {
  individual,
  andAbove,
}

/// Quality assessment types shown in the primary sidebar. Selecting all
/// types is the default and means that no quality restriction is applied.
const defaultQualityFilters = <QualityFilter>{
  QualityFilter.qualityImage,
  QualityFilter.valuedImage,
  QualityFilter.featuredPicture,
};

String qualityFilterLabel(QualityFilter filter) {
  switch (filter) {
    case QualityFilter.any:
      return 'Any quality';
    case QualityFilter.qualityImage:
      return 'Quality media';
    case QualityFilter.valuedImage:
      return 'Valued media';
    case QualityFilter.featuredPicture:
      return 'Featured media';
  }
}

String qualityMatchModeLabel(QualityMatchMode mode) {
  switch (mode) {
    case QualityMatchMode.individual:
      return 'Individual assessments';
    case QualityMatchMode.andAbove:
      return 'This tier and above';
  }
}

/// The product's convenience ordering for the quality picker. These are
/// separate Wikimedia assessments rather than a native Commons hierarchy.
const _qualityTierOrder = <QualityFilter>[
  QualityFilter.valuedImage,
  QualityFilter.qualityImage,
  QualityFilter.featuredPicture,
];

Set<QualityFilter> qualityFiltersAtOrAbove(QualityFilter selected) {
  final index = _qualityTierOrder.indexOf(selected);
  if (index < 0) return const {};
  return _qualityTierOrder.sublist(index).toSet();
}

enum MediaKind {
  image,
  vector,
  audio,
  video,
  document,
  unknown,
}

@immutable
class DateFilter {
  final String? from;
  final String? to;

  const DateFilter({this.from, this.to});

  bool get isEmpty =>
      (from == null || from!.trim().isEmpty) &&
      (to == null || to!.trim().isEmpty);

  DateFilter copyWith({
    String? from,
    String? to,
    bool clearFrom = false,
    bool clearTo = false,
  }) {
    return DateFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
    );
  }

  Map<String, dynamic> toJson() => {'from': from, 'to': to};

  static DateFilter fromJson(Map<String, dynamic> json) => DateFilter(
        from: _stringOrNull(json['from']),
        to: _stringOrNull(json['to']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DateFilter && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

@immutable
class NearCoordFilter {
  final double lat;
  final double lng;
  final double radiusKm;

  const NearCoordFilter({
    required this.lat,
    required this.lng,
    this.radiusKm = 2,
  });

  NearCoordFilter copyWith({double? lat, double? lng, double? radiusKm}) {
    return NearCoordFilter(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, 'radiusKm': radiusKm};

  static NearCoordFilter fromJson(Map<String, dynamic> json) => NearCoordFilter(
        lat: _doubleOrNull(json['lat']) ?? 0,
        lng: _doubleOrNull(json['lng']) ?? 0,
        radiusKm: _doubleOrNull(json['radiusKm']) ?? 2,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NearCoordFilter &&
          other.lat == lat &&
          other.lng == lng &&
          other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(lat, lng, radiusKm);
}

/// Geosearch near a page/entity title instead of raw coordinates — CirrusSearch's
/// neartitle: keyword sources the coordinates from the named page itself.
/// Mutually exclusive with NearCoordFilter in practice (the drawer enforces
/// this), but kept as a separate field rather than folded into one type so
/// each stays a simple, direct mirror of its own CirrusSearch keyword.
@immutable
class NearTitleFilter {
  final String title;
  final double radiusKm;

  const NearTitleFilter({
    required this.title,
    this.radiusKm = 10,
  });

  NearTitleFilter copyWith({String? title, double? radiusKm}) {
    return NearTitleFilter(
      title: title ?? this.title,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'radiusKm': radiusKm};

  static NearTitleFilter fromJson(Map<String, dynamic> json) => NearTitleFilter(
        title: _stringOrNull(json['title']) ?? '',
        radiusKm: _doubleOrNull(json['radiusKm']) ?? 10,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NearTitleFilter &&
          other.title == title &&
          other.radiusKm == radiusKm;

  @override
  int get hashCode => Object.hash(title, radiusKm);
}

class DepictsEntity {
  final String qid;
  final String label;
  final String? description;

  const DepictsEntity({
    required this.qid,
    required this.label,
    this.description,
  });

  @override
  bool operator ==(Object other) => other is DepictsEntity && other.qid == qid;

  @override
  int get hashCode => qid.hashCode;

  Map<String, dynamic> toJson() =>
      {'qid': qid, 'label': label, 'description': description};

  static DepictsEntity fromJson(Map<String, dynamic> json) {
    final qid = _stringOrNull(json['qid']) ?? '';
    return DepictsEntity(
      qid: qid,
      label: _stringOrNull(json['label']) ?? qid,
      description: _stringOrNull(json['description']),
    );
  }
}

/// An arbitrary Wikidata property=value pair, for haswbstatement: search
/// beyond the two hardcoded properties (P180 depicts, P275 license) that
/// depictsInclude/licensePresets already cover. Reuses DepictsEntity's shape
/// for both sides — the "property" field's .qid holds a P-code (e.g.
/// "P1071") rather than a Q-code, which is a minor naming imprecision
/// that's a fair trade for not duplicating an identical class.
class WikidataStatement {
  final DepictsEntity property; // .qid holds a P-code, e.g. "P1071"
  final DepictsEntity value; // .qid holds a Q-code, e.g. "Q90"

  const WikidataStatement({required this.property, required this.value});

  @override
  bool operator ==(Object other) =>
      other is WikidataStatement &&
      other.property.qid == property.qid &&
      other.value.qid == value.qid;

  @override
  int get hashCode => Object.hash(property.qid, value.qid);

  Map<String, dynamic> toJson() =>
      {'property': property.toJson(), 'value': value.toJson()};

  static WikidataStatement fromJson(Map<String, dynamic> json) {
    final property = _jsonObject(json['property']);
    final value = _jsonObject(json['value']);
    return WikidataStatement(
      property: DepictsEntity.fromJson(property ?? const {}),
      value: DepictsEntity.fromJson(value ?? const {}),
    );
  }
}

@immutable
class SearchState {
  final String queryText;
  final MediaTabType tab;
  final Set<FileFormat> formats;
  final Set<String> categories;
  final bool deepCategoryMode;
  // false (default) = intersection: a file must be in ALL included
  // categories (AND). true = union: a file in ANY included category
  // qualifies (OR). Same convention as statementsUnion below — excluded
  // categories are always subtracted regardless of this mode.
  final bool categoriesUnion;
  final bool titleOnly;
  final bool localOnly;
  final String? languageCode;
  final String? contentModel;

  /// When the file page was first created on Wikimedia Commons. This is the
  /// closest indexed proxy for the file's initial submission/upload date.
  final DateFilter? createdDate;
  final DateFilter? editedDate;

  /// When the media was made (for example, EXIF DateTimeOriginal). Unlike
  /// page creation/edit timestamps this is file metadata, so it is applied
  /// after Commons returns each result page.
  final DateFilter? originalDate;
  final SortMode sortMode;
  // Multiple licenses select ANY-match (union) — a single file only ever
  // carries one license, so there's no meaningful "AND" reading here, only
  // "match if it has any of these". Empty set = no license filter applied.
  final Set<LicensePreset> licensePresets;

  /// Multiple quality types match with OR semantics. Selecting every type is
  /// the default and is treated as no quality restriction.
  final Set<QualityFilter> qualityFilters;

  /// Compatibility field for older callers and serialized pipeline configs.
  /// New code should use [selectedQualityFilters].
  final QualityFilter qualityFilter;

  /// Whether the selected assessment is exact or expands to the product's
  /// "this tier and above" union.
  final QualityMatchMode qualityMatchMode;

  /// Explicitly keeps images without any quality assessment in the result.
  final bool allImages;

  bool get allImagesMode => allImages && qualityFilter == QualityFilter.any;

  Set<QualityFilter> get selectedQualityFilters {
    // Older callers pass only the singular field, which leaves the new set at
    // its default. Resolve that legacy shape without changing its API.
    if (qualityFilter != QualityFilter.any &&
        _setEquals(qualityFilters, defaultQualityFilters)) {
      return {qualityFilter};
    }
    return qualityFilters;
  }

  Set<QualityFilter> get effectiveQualityFilters {
    if (allImagesMode) return const {};
    if (qualityMatchMode == QualityMatchMode.individual) {
      return selectedQualityFilters;
    }
    return selectedQualityFilters.expand(qualityFiltersAtOrAbove).toSet();
  }

  // True = only files whose extmetadata AttributionRequired flag is set;
  // false = only files where it's explicitly not set; null = no filter.
  // There is no CirrusSearch keyword for this (it's a MediaWiki-computed
  // flag derived from the license, not a Wikidata statement) — see the
  // note in SearchService.buildQuery for how this is actually applied.
  final bool? attributionRequired;
  final int? minWidth;
  final int? minHeight;
  final Set<DepictsEntity> depictsInclude;
  final Set<DepictsEntity> depictsExclude;
  // Same convention as categoriesUnion/statementsUnion: false = a file must
  // depict ALL included subjects (AND); true = depicting ANY one qualifies
  // (OR). depictsExclude is always subtracted regardless of this mode.
  final bool depictsUnion;
  final Set<String> excludeCategories;
  final NearCoordFilter? nearCoord;
  final NearTitleFilter? nearTitle;
  final Set<WikidataStatement> statementsInclude;
  final Set<WikidataStatement> statementsExclude;
  // false (default) = intersection: all included statements must match (AND).
  // true = union: any included statement may match (OR). Excluded
  // statements are always subtracted regardless of this mode — i.e. "this
  // AND this AND NOT this" (intersection) vs "this OR this, but NOT this"
  // (union), matching how the two toggle buttons are meant to read.
  final bool statementsUnion;
  final Set<String> excludeTerms;

  // CirrusSearch's morelike: keyword — files similar to the given File:
  // title(s), e.g. {"File:Eiffel Tower at night.jpg"}. Combines with every
  // other active filter (AND), same as every other clause buildQuery emits.
  final Set<String> morelikeTitles;

  // CirrusSearch's insource: keyword — full-text/regex search over a
  // file's raw wikitext (its description-page source), which is a
  // different corpus than the free-text `queryText` field (that matches
  // the analyzed/indexed content, not literal source). insourceRegex
  // switches between insource:"literal text" and insource:/regex/.
  final String? insourceText;
  final bool insourceRegex;

  // Max-dimension counterparts to minWidth/minHeight above — filew:</fileh:<
  final int? maxWidth;
  final int? maxHeight;

  // filesize: — byte range. Values are always raw bytes; a UI can offer
  // MB/KB and convert client-side, but the wire format here never guesses
  // at unit suffixes.
  final int? minFileSizeBytes;
  final int? maxFileSizeBytes;

  // filebits: — color/bit depth (e.g. 1 for monochrome, 8/16 for color).
  final int? colorDepthBits;

  // hastemplate: generalized beyond the hardcoded QualityFilter presets —
  // GLAM/institutional sets (e.g. "Institution:Metropolitan Museum of Art"),
  // granular PD templates (e.g. "PD-USGov-NASA"), or any other template.
  final Set<String> templates;
  final Set<String> excludeTemplates;

  const SearchState({
    this.queryText = '',
    this.tab = MediaTabType.allMedia,
    this.formats = const {},
    this.categories = const {},
    this.deepCategoryMode = false,
    this.categoriesUnion = false,
    this.titleOnly = false,
    this.localOnly = false,
    this.languageCode,
    this.contentModel,
    this.createdDate,
    this.editedDate,
    this.originalDate,
    this.sortMode = SortMode.relevance,
    this.licensePresets = const {},
    this.qualityFilters = defaultQualityFilters,
    this.qualityFilter = QualityFilter.any,
    this.qualityMatchMode = QualityMatchMode.individual,
    this.allImages = true,
    this.attributionRequired,
    this.minWidth,
    this.minHeight,
    this.depictsInclude = const {},
    this.depictsExclude = const {},
    this.depictsUnion = false,
    this.excludeCategories = const {},
    this.nearCoord,
    this.nearTitle,
    this.statementsInclude = const {},
    this.statementsExclude = const {},
    this.statementsUnion = false,
    this.excludeTerms = const {},
    this.morelikeTitles = const {},
    this.insourceText,
    this.insourceRegex = false,
    this.maxWidth,
    this.maxHeight,
    this.minFileSizeBytes,
    this.maxFileSizeBytes,
    this.colorDepthBits,
    this.templates = const {},
    this.excludeTemplates = const {},
  });

  SearchState copyWith({
    String? queryText,
    MediaTabType? tab,
    Set<FileFormat>? formats,
    Set<String>? categories,
    bool? deepCategoryMode,
    bool? categoriesUnion,
    bool? titleOnly,
    bool? localOnly,
    String? languageCode,
    String? contentModel,
    DateFilter? createdDate,
    DateFilter? editedDate,
    DateFilter? originalDate,
    SortMode? sortMode,
    Set<LicensePreset>? licensePresets,
    Set<QualityFilter>? qualityFilters,
    QualityFilter? qualityFilter,
    QualityMatchMode? qualityMatchMode,
    bool? allImages,
    bool? attributionRequired,
    bool clearAttributionRequired = false,
    int? minWidth,
    int? minHeight,
    Set<DepictsEntity>? depictsInclude,
    Set<DepictsEntity>? depictsExclude,
    bool? depictsUnion,
    Set<String>? excludeCategories,
    NearCoordFilter? nearCoord,
    NearTitleFilter? nearTitle,
    Set<WikidataStatement>? statementsInclude,
    Set<WikidataStatement>? statementsExclude,
    bool? statementsUnion,
    Set<String>? excludeTerms,
    Set<String>? morelikeTitles,
    String? insourceText,
    bool? insourceRegex,
    int? maxWidth,
    int? maxHeight,
    int? minFileSizeBytes,
    int? maxFileSizeBytes,
    int? colorDepthBits,
    Set<String>? templates,
    Set<String>? excludeTemplates,
    bool clearLanguageCode = false,
    bool clearContentModel = false,
    bool clearCreatedDate = false,
    bool clearEditedDate = false,
    bool clearOriginalDate = false,
    bool clearMinWidth = false,
    bool clearMinHeight = false,
    bool clearNearCoord = false,
    bool clearNearTitle = false,
    bool clearInsourceText = false,
    bool clearMaxWidth = false,
    bool clearMaxHeight = false,
    bool clearMinFileSizeBytes = false,
    bool clearMaxFileSizeBytes = false,
    bool clearColorDepthBits = false,
  }) {
    return SearchState(
      queryText: queryText ?? this.queryText,
      tab: tab ?? this.tab,
      formats: formats ?? this.formats,
      categories: categories ?? this.categories,
      deepCategoryMode: deepCategoryMode ?? this.deepCategoryMode,
      categoriesUnion: categoriesUnion ?? this.categoriesUnion,
      titleOnly: titleOnly ?? this.titleOnly,
      localOnly: localOnly ?? this.localOnly,
      languageCode:
          clearLanguageCode ? null : (languageCode ?? this.languageCode),
      contentModel:
          clearContentModel ? null : (contentModel ?? this.contentModel),
      createdDate: clearCreatedDate ? null : (createdDate ?? this.createdDate),
      editedDate: clearEditedDate ? null : (editedDate ?? this.editedDate),
      originalDate:
          clearOriginalDate ? null : (originalDate ?? this.originalDate),
      sortMode: sortMode ?? this.sortMode,
      licensePresets: licensePresets ?? this.licensePresets,
      qualityFilters: qualityFilters ??
          (qualityFilter == null ? this.qualityFilters : defaultQualityFilters),
      qualityFilter: qualityFilters != null
          ? QualityFilter.any
          : (qualityFilter ?? this.qualityFilter),
      qualityMatchMode: qualityMatchMode ?? this.qualityMatchMode,
      allImages: allImages ??
          (qualityFilter == null
              ? this.allImages
              : qualityFilter == QualityFilter.any),
      attributionRequired: clearAttributionRequired
          ? null
          : (attributionRequired ?? this.attributionRequired),
      minWidth: clearMinWidth ? null : (minWidth ?? this.minWidth),
      minHeight: clearMinHeight ? null : (minHeight ?? this.minHeight),
      depictsInclude: depictsInclude ?? this.depictsInclude,
      depictsExclude: depictsExclude ?? this.depictsExclude,
      depictsUnion: depictsUnion ?? this.depictsUnion,
      excludeCategories: excludeCategories ?? this.excludeCategories,
      nearCoord: clearNearCoord ? null : (nearCoord ?? this.nearCoord),
      nearTitle: clearNearTitle ? null : (nearTitle ?? this.nearTitle),
      statementsInclude: statementsInclude ?? this.statementsInclude,
      statementsExclude: statementsExclude ?? this.statementsExclude,
      statementsUnion: statementsUnion ?? this.statementsUnion,
      excludeTerms: excludeTerms ?? this.excludeTerms,
      morelikeTitles: morelikeTitles ?? this.morelikeTitles,
      insourceText:
          clearInsourceText ? null : (insourceText ?? this.insourceText),
      insourceRegex: insourceRegex ?? this.insourceRegex,
      maxWidth: clearMaxWidth ? null : (maxWidth ?? this.maxWidth),
      maxHeight: clearMaxHeight ? null : (maxHeight ?? this.maxHeight),
      minFileSizeBytes: clearMinFileSizeBytes
          ? null
          : (minFileSizeBytes ?? this.minFileSizeBytes),
      maxFileSizeBytes: clearMaxFileSizeBytes
          ? null
          : (maxFileSizeBytes ?? this.maxFileSizeBytes),
      colorDepthBits:
          clearColorDepthBits ? null : (colorDepthBits ?? this.colorDepthBits),
      templates: templates ?? this.templates,
      excludeTemplates: excludeTemplates ?? this.excludeTemplates,
    );
  }

  /// Full, typed JSON representation — every field always present (with
  /// its default if unset), so a JSON server's response shape is stable
  /// and self-documenting rather than varying with which filters happen to
  /// be active. For a compact, defaults-omitted representation (e.g. for a
  /// URL), use [SearchUrlCodec] instead.
  Map<String, dynamic> toJson() => {
        'queryText': queryText,
        'tab': tab.name,
        'formats': formats.map((f) => f.name).toList(),
        'categories': categories.toList(),
        'deepCategoryMode': deepCategoryMode,
        'categoriesUnion': categoriesUnion,
        'titleOnly': titleOnly,
        'localOnly': localOnly,
        'languageCode': languageCode,
        'contentModel': contentModel,
        'createdDate': createdDate?.toJson(),
        'editedDate': editedDate?.toJson(),
        'originalDate': originalDate?.toJson(),
        'sortMode': sortMode.name,
        'licensePresets': licensePresets.map((l) => l.name).toList(),
        'qualityFilters': selectedQualityFilters.map((q) => q.name).toList(),
        // Retain the singular key for older pipeline/state consumers.
        'qualityFilter': selectedQualityFilters.length == 1
            ? selectedQualityFilters.single.name
            : QualityFilter.any.name,
        'qualityMatchMode': qualityMatchMode.name,
        'allImages': allImagesMode,
        'attributionRequired': attributionRequired,
        'minWidth': minWidth,
        'minHeight': minHeight,
        'depictsInclude': depictsInclude.map((e) => e.toJson()).toList(),
        'depictsExclude': depictsExclude.map((e) => e.toJson()).toList(),
        'depictsUnion': depictsUnion,
        'excludeCategories': excludeCategories.toList(),
        'nearCoord': nearCoord?.toJson(),
        'nearTitle': nearTitle?.toJson(),
        'statementsInclude': statementsInclude.map((s) => s.toJson()).toList(),
        'statementsExclude': statementsExclude.map((s) => s.toJson()).toList(),
        'statementsUnion': statementsUnion,
        'excludeTerms': excludeTerms.toList(),
        'morelikeTitles': morelikeTitles.toList(),
        'insourceText': insourceText,
        'insourceRegex': insourceRegex,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'minFileSizeBytes': minFileSizeBytes,
        'maxFileSizeBytes': maxFileSizeBytes,
        'colorDepthBits': colorDepthBits,
        'templates': templates.toList(),
        'excludeTemplates': excludeTemplates.toList(),
      };

  /// Parses a JSON request body (already `jsonDecode`d into
  /// `Map<String, dynamic>`) into a [SearchState]. Every field is read
  /// defensively — missing, wrong-typed, or unrecognized values fall back
  /// to [SearchState]'s own defaults rather than throwing, so one bad field
  /// in a caller's payload doesn't take down the whole parse. Unknown
  /// top-level keys are simply ignored.
  static SearchState fromJson(Map<String, dynamic> json) {
    Set<String> stringSet(dynamic raw) => raw is List
        ? raw.whereType<String>().where((s) => s.isNotEmpty).toSet()
        : const {};

    Set<DepictsEntity> depictsSet(dynamic raw) {
      if (raw is! List) return const {};
      return raw
          .map(_jsonObject)
          .whereType<Map<String, dynamic>>()
          .map(DepictsEntity.fromJson)
          .where((entity) => entity.qid.isNotEmpty)
          .toSet();
    }

    Set<WikidataStatement> statementsSet(dynamic raw) {
      if (raw is! List) return const {};
      return raw
          .map(_jsonObject)
          .whereType<Map<String, dynamic>>()
          .map(WikidataStatement.fromJson)
          .where((statement) =>
              statement.property.qid.isNotEmpty &&
              statement.value.qid.isNotEmpty)
          .toSet();
    }

    Set<FileFormat> formatsSet(dynamic raw) => raw is List
        ? raw
            .map((f) => _enumFromJsonOrNull(FileFormat.values, f))
            .whereType<FileFormat>()
            .toSet()
        : const {};

    Set<QualityFilter>? qualitySet(dynamic raw) => raw is List
        ? raw
            .map((q) => _enumFromJsonOrNull(QualityFilter.values, q))
            .whereType<QualityFilter>()
            .where((q) => q != QualityFilter.any)
            .toSet()
        : null;

    final createdDateRaw = _jsonObject(json['createdDate']);
    final editedDateRaw = _jsonObject(json['editedDate']);
    final originalDateRaw = _jsonObject(json['originalDate']);
    final nearCoordRaw = _jsonObject(json['nearCoord']);
    final nearTitleRaw = _jsonObject(json['nearTitle']);

    final qualityFilters = qualitySet(json['qualityFilters']);
    final legacyQuality = _enumFromJson(
        QualityFilter.values, json['qualityFilter'], QualityFilter.any);
    final qualityMatchMode = _enumFromJson(QualityMatchMode.values,
        json['qualityMatchMode'], QualityMatchMode.individual);
    final allImages = _boolOrNull(json['allImages']) ??
        (qualityFilters == null || legacyQuality == QualityFilter.any);

    return SearchState(
      queryText: _stringOrNull(json['queryText']) ?? '',
      tab: _enumFromJson(
          MediaTabType.values, json['tab'], MediaTabType.allMedia),
      formats: formatsSet(json['formats']),
      categories: stringSet(json['categories']),
      deepCategoryMode: _boolOrNull(json['deepCategoryMode']) ?? false,
      categoriesUnion: _boolOrNull(json['categoriesUnion']) ?? false,
      titleOnly: _boolOrNull(json['titleOnly']) ?? false,
      localOnly: _boolOrNull(json['localOnly']) ?? false,
      languageCode: _stringOrNull(json['languageCode']),
      contentModel: _stringOrNull(json['contentModel']),
      createdDate:
          createdDateRaw == null ? null : DateFilter.fromJson(createdDateRaw),
      editedDate:
          editedDateRaw == null ? null : DateFilter.fromJson(editedDateRaw),
      originalDate:
          originalDateRaw == null ? null : DateFilter.fromJson(originalDateRaw),
      sortMode:
          _enumFromJson(SortMode.values, json['sortMode'], SortMode.relevance),
      licensePresets: (json['licensePresets'] is List)
          ? (json['licensePresets'] as List)
              .map((l) => _enumFromJsonOrNull(LicensePreset.values, l))
              .whereType<LicensePreset>()
              .toSet()
          : const {},
      qualityFilters: qualityFilters ?? defaultQualityFilters,
      qualityFilter: qualityFilters == null ? legacyQuality : QualityFilter.any,
      qualityMatchMode: qualityMatchMode,
      allImages: allImages,
      attributionRequired: _boolOrNull(json['attributionRequired']),
      minWidth: _intOrNull(json['minWidth']),
      minHeight: _intOrNull(json['minHeight']),
      depictsInclude: depictsSet(json['depictsInclude']),
      depictsExclude: depictsSet(json['depictsExclude']),
      depictsUnion: _boolOrNull(json['depictsUnion']) ?? false,
      excludeCategories: stringSet(json['excludeCategories']),
      nearCoord:
          nearCoordRaw == null ? null : NearCoordFilter.fromJson(nearCoordRaw),
      nearTitle:
          nearTitleRaw == null ? null : NearTitleFilter.fromJson(nearTitleRaw),
      statementsInclude: statementsSet(json['statementsInclude']),
      statementsExclude: statementsSet(json['statementsExclude']),
      statementsUnion: _boolOrNull(json['statementsUnion']) ?? false,
      excludeTerms: stringSet(json['excludeTerms']),
      morelikeTitles: stringSet(json['morelikeTitles']),
      insourceText: _stringOrNull(json['insourceText']),
      insourceRegex: _boolOrNull(json['insourceRegex']) ?? false,
      maxWidth: _intOrNull(json['maxWidth']),
      maxHeight: _intOrNull(json['maxHeight']),
      minFileSizeBytes: _intOrNull(json['minFileSizeBytes']),
      maxFileSizeBytes: _intOrNull(json['maxFileSizeBytes']),
      colorDepthBits: _intOrNull(json['colorDepthBits']),
      templates: stringSet(json['templates']),
      excludeTemplates: stringSet(json['excludeTemplates']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchState &&
          other.queryText == queryText &&
          other.tab == tab &&
          _setEquals(other.formats, formats) &&
          _setEquals(other.categories, categories) &&
          other.deepCategoryMode == deepCategoryMode &&
          other.categoriesUnion == categoriesUnion &&
          other.titleOnly == titleOnly &&
          other.localOnly == localOnly &&
          other.languageCode == languageCode &&
          other.contentModel == contentModel &&
          other.createdDate == createdDate &&
          other.editedDate == editedDate &&
          other.originalDate == originalDate &&
          other.sortMode == sortMode &&
          _setEquals(other.licensePresets, licensePresets) &&
          _setEquals(other.selectedQualityFilters, selectedQualityFilters) &&
          other.qualityMatchMode == qualityMatchMode &&
          other.allImagesMode == allImagesMode &&
          other.attributionRequired == attributionRequired &&
          other.minWidth == minWidth &&
          other.minHeight == minHeight &&
          _setEquals(other.depictsInclude, depictsInclude) &&
          _setEquals(other.depictsExclude, depictsExclude) &&
          other.depictsUnion == depictsUnion &&
          _setEquals(other.excludeCategories, excludeCategories) &&
          other.nearCoord == nearCoord &&
          other.nearTitle == nearTitle &&
          _setEquals(other.statementsInclude, statementsInclude) &&
          _setEquals(other.statementsExclude, statementsExclude) &&
          other.statementsUnion == statementsUnion &&
          _setEquals(other.excludeTerms, excludeTerms) &&
          _setEquals(other.morelikeTitles, morelikeTitles) &&
          other.insourceText == insourceText &&
          other.insourceRegex == insourceRegex &&
          other.maxWidth == maxWidth &&
          other.maxHeight == maxHeight &&
          other.minFileSizeBytes == minFileSizeBytes &&
          other.maxFileSizeBytes == maxFileSizeBytes &&
          other.colorDepthBits == colorDepthBits &&
          _setEquals(other.templates, templates) &&
          _setEquals(other.excludeTemplates, excludeTemplates);

  @override
  int get hashCode => Object.hashAll([
        queryText,
        tab,
        _setHash(formats),
        _setHash(categories),
        deepCategoryMode,
        categoriesUnion,
        titleOnly,
        localOnly,
        languageCode,
        contentModel,
        createdDate,
        editedDate,
        originalDate,
        sortMode,
        _setHash(licensePresets),
        _setHash(selectedQualityFilters),
        qualityMatchMode,
        allImagesMode,
        attributionRequired,
        minWidth,
        minHeight,
        _setHash(depictsInclude),
        _setHash(depictsExclude),
        depictsUnion,
        _setHash(excludeCategories),
        nearCoord,
        nearTitle,
        _setHash(statementsInclude),
        _setHash(statementsExclude),
        statementsUnion,
        _setHash(excludeTerms),
        _setHash(morelikeTitles),
        insourceText,
        insourceRegex,
        maxWidth,
        maxHeight,
        minFileSizeBytes,
        maxFileSizeBytes,
        colorDepthBits,
        _setHash(templates),
        _setHash(excludeTemplates),
      ]);
}

class MediaTabConfig {
  final MediaTabType type;
  final String label;
  final Set<FileFormat> allowedFormats;
  final String emptyMessage;

  const MediaTabConfig({
    required this.type,
    required this.label,
    required this.allowedFormats,
    required this.emptyMessage,
  });
}

const mediaTabs = [
  MediaTabConfig(
    type: MediaTabType.allMedia,
    label: 'All',
    allowedFormats: {
      FileFormat.jpg,
      FileFormat.jpeg,
      FileFormat.png,
      FileFormat.svg,
      FileFormat.gif,
      FileFormat.tif,
      FileFormat.tiff,
      FileFormat.webp,
      FileFormat.xcf,
      FileFormat.pdf,
      FileFormat.djvu,
      FileFormat.ogg,
      FileFormat.oga,
      FileFormat.ogx,
      FileFormat.opus,
      FileFormat.ogv,
      FileFormat.mp3,
      FileFormat.flac,
      FileFormat.midi,
      FileFormat.wav,
      FileFormat.webm,
      FileFormat.mpg,
      FileFormat.mpeg,
      FileFormat.mp4,
      FileFormat.stl,
    },
    emptyMessage: 'No media found.',
  ),
  MediaTabConfig(
    type: MediaTabType.images,
    label: 'Images',
    allowedFormats: {
      FileFormat.jpg,
      FileFormat.jpeg,
      FileFormat.png,
      FileFormat.gif,
      FileFormat.webp,
      FileFormat.tif,
      FileFormat.tiff,
      FileFormat.xcf,
    },
    emptyMessage: 'No images found.',
  ),
  MediaTabConfig(
    type: MediaTabType.vectors,
    label: 'SVG / Diagrams',
    allowedFormats: {
      FileFormat.svg,
    },
    emptyMessage: 'No vector files found.',
  ),
  MediaTabConfig(
    type: MediaTabType.audio,
    label: 'Audio',
    allowedFormats: {
      FileFormat.ogg,
      FileFormat.oga,
      FileFormat.ogx,
      FileFormat.opus,
      FileFormat.mp3,
      FileFormat.flac,
      FileFormat.midi,
      FileFormat.wav,
      // WebM and Ogg containers can carry audio as well as video.
      FileFormat.webm,
    },
    emptyMessage: 'No audio found.',
  ),
  MediaTabConfig(
    type: MediaTabType.video,
    label: 'Video',
    allowedFormats: {
      // Ogg and WebM are shared audio/video containers.
      FileFormat.ogg,
      FileFormat.ogx,
      FileFormat.webm,
      FileFormat.ogv,
      FileFormat.mpg,
      FileFormat.mpeg,
      FileFormat.mp4,
    },
    emptyMessage: 'No videos found.',
  ),
  MediaTabConfig(
    type: MediaTabType.documents,
    label: 'Docs',
    allowedFormats: {
      FileFormat.pdf,
      FileFormat.djvu,
    },
    emptyMessage: 'No documents found.',
  ),
  MediaTabConfig(
    type: MediaTabType.threeD,
    label: '3D',
    allowedFormats: {
      FileFormat.stl,
    },
    emptyMessage: 'No 3D files found.',
  ),
];

MediaTabConfig configForTab(MediaTabType type) {
  return mediaTabs.firstWhere((tab) => tab.type == type);
}

String fileFormatLabel(FileFormat format) {
  switch (format) {
    case FileFormat.jpg:
      return 'JPG';
    case FileFormat.jpeg:
      return 'JPEG';
    case FileFormat.png:
      return 'PNG';
    case FileFormat.svg:
      return 'SVG';
    case FileFormat.gif:
      return 'GIF';
    case FileFormat.tif:
      return 'TIF';
    case FileFormat.tiff:
      return 'TIFF';
    case FileFormat.webp:
      return 'WEBP';
    case FileFormat.xcf:
      return 'XCF';
    case FileFormat.pdf:
      return 'PDF';
    case FileFormat.djvu:
      return 'DJVU';
    case FileFormat.ogg:
      return 'OGG';
    case FileFormat.oga:
      return 'OGA';
    case FileFormat.ogx:
      return 'OGX';
    case FileFormat.opus:
      return 'OPUS';
    case FileFormat.ogv:
      return 'OGV';
    case FileFormat.mp3:
      return 'MP3';
    case FileFormat.flac:
      return 'FLAC';
    case FileFormat.midi:
      return 'MIDI';
    case FileFormat.wav:
      return 'WAV';
    case FileFormat.webm:
      return 'WEBM';
    case FileFormat.mpg:
      return 'MPG';
    case FileFormat.mpeg:
      return 'MPEG';
    case FileFormat.mp4:
      return 'MP4';
    case FileFormat.stl:
      return 'STL';
  }
}

MediaKind mediaKindFromFormat(FileFormat format) {
  switch (format) {
    case FileFormat.jpg:
    case FileFormat.jpeg:
    case FileFormat.png:
    case FileFormat.gif:
    case FileFormat.tif:
    case FileFormat.tiff:
    case FileFormat.webp:
    case FileFormat.xcf:
      return MediaKind.image;
    case FileFormat.svg:
      return MediaKind.vector;
    case FileFormat.ogg:
    case FileFormat.oga:
    case FileFormat.ogx:
    case FileFormat.opus:
    case FileFormat.mp3:
    case FileFormat.flac:
    case FileFormat.midi:
    case FileFormat.wav:
      return MediaKind.audio;
    case FileFormat.webm:
    case FileFormat.ogv:
    case FileFormat.mpg:
    case FileFormat.mpeg:
    case FileFormat.mp4:
      return MediaKind.video;
    case FileFormat.pdf:
    case FileFormat.djvu:
      return MediaKind.document;
    case FileFormat.stl:
      return MediaKind.unknown;
  }
}

class QueryChipData {
  final String id;
  final String label;

  const QueryChipData({
    required this.id,
    required this.label,
  });

  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

class QueryBuildResult {
  final String srsearch;
  final List<QueryChipData> chips;
  final String debugPreview;

  const QueryBuildResult({
    required this.srsearch,
    required this.chips,
    required this.debugPreview,
  });

  Map<String, dynamic> toJson() => {
        'srsearch': srsearch,
        'chips': chips.map((c) => c.toJson()).toList(),
        'debugPreview': debugPreview,
      };
}

class SearchItem {
  final String title;
  final String url;
  final String thumb;
  final String commonsUrl;
  final String snippet;
  final String mime;
  final bool isSvg;
  final int? pageId;
  final String? timestamp;
  final String? descriptionUrl;

  final String artistHtml;
  final String licenseShortName;
  final String licenseUrl;
  final String dateTimeOriginal;
  final String uploader;
  final int width;
  final int height;
  final int fileSizeBytes;
  final String sha1;

  // Everything below comes from the same extmetadata block the fields
  // above are already pulled from — same iiprop=extmetadata request, no
  // extra network call. Commons doesn't guarantee any given key is
  // present on any given file, so these all default to '' rather than
  // being nullable; callers just check .isEmpty like the fields above.
  final String categories; // semicolon-separated, flat (not deepcat-aware)
  final String assessments; // e.g. "featured", "quality", "valued"
  final String imageDescriptionHtml;
  final String objectName;
  final String creditHtml;
  final String usageTerms;
  final String copyrighted;
  final String restrictions;
  final String
      uploadDateTime; // upload time — distinct from dateTimeOriginal (capture time)
  final String gpsLatitude;
  final String gpsLongitude;
  final String permissionHtml;
  final String attributionRequired;

  // Authoritative, backend-resolved coordinates — as opposed to
  // gpsLatitude/gpsLongitude above, which are the raw (often absent)
  // EXIF/template-derived extmetadata strings every ordinary search result
  // carries. Currently only populated by SearchService.geosearch(), which
  // requests MediaWiki's own `prop=coordinates` alongside imageinfo — the
  // one call site that's actually guaranteed to have real coordinates for
  // every returned page. Kept as a separate pair of fields rather than
  // overwriting gpsLatitude/gpsLongitude so it's always clear which source
  // an item's location came from; see [resolvedLatitude]/[resolvedLongitude]
  // for the "give me whatever's available" accessor most UI code wants.
  final double? latitude;
  final double? longitude;

  const SearchItem({
    required this.title,
    required this.url,
    required this.thumb,
    required this.commonsUrl,
    required this.snippet,
    required this.mime,
    required this.isSvg,
    this.pageId,
    this.timestamp,
    this.descriptionUrl,
    this.artistHtml = '',
    this.licenseShortName = '',
    this.licenseUrl = '',
    this.dateTimeOriginal = '',
    this.uploader = '',
    this.width = 0,
    this.height = 0,
    this.fileSizeBytes = 0,
    this.sha1 = '',
    this.categories = '',
    this.assessments = '',
    this.imageDescriptionHtml = '',
    this.objectName = '',
    this.creditHtml = '',
    this.usageTerms = '',
    this.copyrighted = '',
    this.restrictions = '',
    this.uploadDateTime = '',
    this.gpsLatitude = '',
    this.gpsLongitude = '',
    this.permissionHtml = '',
    this.attributionRequired = '',
    this.latitude,
    this.longitude,
  });

  /// Best-available coordinates for plotting this item on a map — the
  /// dedicated [latitude]/[longitude] fields when the backend already
  /// resolved them directly (currently: geosearch's `coordinates` prop),
  /// falling back to parsing the EXIF/template-derived GPSLatitude/
  /// GPSLongitude extmetadata strings that ordinary text/filter search
  /// results carry instead. Null when neither source has anything — most
  /// text/filter search results won't, and that's fine: the item itself is
  /// never dropped from the result set, it just can't be placed on a map.
  double? get resolvedLatitude => latitude ?? double.tryParse(gpsLatitude);
  double? get resolvedLongitude => longitude ?? double.tryParse(gpsLongitude);
  bool get hasCoordinates =>
      resolvedLatitude != null && resolvedLongitude != null;

  /// Returns a Wikimedia-hosted thumbnail resized to [width], when this item
  /// has one. The API normally supplies a 320px `thumburl`; Wikimedia accepts
  /// the same URL with a different width segment, so callers can request a
  /// display-sized asset without downloading the full original.
  ///
  /// If the thumbnail URL is not in Wikimedia's standard `/Npx-name` shape,
  /// the existing thumbnail is still preferable for an optimized preview.
  /// Null means no distinct preview exists and the original is the only safe
  /// choice.
  String? thumbnailUrlAtWidth(int width) {
    if (width <= 0 || thumb.isEmpty || thumb == url) return null;

    final widthSegment = RegExp(r'/\d+px-([^/?]+)(?=\?|$)');
    if (!widthSegment.hasMatch(thumb)) return thumb;

    return thumb.replaceFirstMapped(
      widthSegment,
      (match) => '/${width}px-${match.group(1)}',
    );
  }

  /// Returns a safe, display-sized preview URL even when the API response did
  /// not include a distinct `thumburl`. Search results can legitimately fall
  /// back to the original file URL after a thumbnail-scaling failure; using
  /// that original directly in a grid makes a large result set painfully slow.
  /// For standard Wikimedia upload URLs we can derive the equivalent thumb
  /// path locally without another API request.
  String? previewUrlAtWidth(int width) {
    final candidates = previewUrlCandidates(width);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Candidate URLs for a grid preview, ordered from the smallest derivative
  /// to the API-provided thumbnail and finally a locally-derived Wikimedia
  /// thumbnail. A derived URL can be invalid for unusual file names or media
  /// types, so callers should try the candidates rather than treating the
  /// first one as authoritative.
  List<String> previewUrlCandidates(int width) {
    if (width <= 0) return const [];

    final candidates = <String>[];
    void add(String? candidate) {
      if (candidate != null &&
          candidate.isNotEmpty &&
          !candidates.contains(candidate)) {
        candidates.add(candidate);
      }
    }

    add(thumbnailUrlAtWidth(width));
    if (thumb.isNotEmpty && thumb != url) add(thumb);
    add(_derivedPreviewUrlAtWidth(width));
    return candidates;
  }

  String? _derivedPreviewUrlAtWidth(int width) {
    if (width <= 0 || url.isEmpty) return null;

    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !parsed.host.toLowerCase().endsWith('wikimedia.org')) {
      return null;
    }
    final segments = parsed.pathSegments;
    final commonsIndex = segments.indexOf('commons');
    if (commonsIndex < 0 || commonsIndex >= segments.length - 1) return null;

    final fileSegments = segments.sublist(commonsIndex + 1);
    final fileName = fileSegments.last;
    return parsed.replace(
      pathSegments: [
        ...segments.take(commonsIndex + 1),
        'thumb',
        ...fileSegments,
        '${width}px-$fileName',
      ],
      query: null,
      fragment: null,
    ).toString();
  }

  /// Flat map of every field — every value here is already a JSON-native
  /// primitive (String/bool/int), no nested encoding needed.
  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'thumb': thumb,
        'commonsUrl': commonsUrl,
        'snippet': snippet,
        'mime': mime,
        'isSvg': isSvg,
        'pageId': pageId,
        'timestamp': timestamp,
        'descriptionUrl': descriptionUrl,
        'artistHtml': artistHtml,
        'licenseShortName': licenseShortName,
        'licenseUrl': licenseUrl,
        'dateTimeOriginal': dateTimeOriginal,
        'uploader': uploader,
        'width': width,
        'height': height,
        'fileSizeBytes': fileSizeBytes,
        'sha1': sha1,
        'categories': categories,
        'assessments': assessments,
        'imageDescriptionHtml': imageDescriptionHtml,
        'objectName': objectName,
        'creditHtml': creditHtml,
        'usageTerms': usageTerms,
        'copyrighted': copyrighted,
        'restrictions': restrictions,
        'uploadDateTime': uploadDateTime,
        'gpsLatitude': gpsLatitude,
        'gpsLongitude': gpsLongitude,
        'permissionHtml': permissionHtml,
        'attributionRequired': attributionRequired,
        'latitude': latitude,
        'longitude': longitude,
      };

  static SearchItem fromJson(Map<String, dynamic> json) => SearchItem(
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        thumb: json['thumb'] as String? ?? '',
        commonsUrl: json['commonsUrl'] as String? ?? '',
        snippet: json['snippet'] as String? ?? '',
        mime: json['mime'] as String? ?? '',
        isSvg: json['isSvg'] as bool? ?? false,
        pageId: (json['pageId'] as num?)?.toInt(),
        timestamp: json['timestamp'] as String?,
        descriptionUrl: json['descriptionUrl'] as String?,
        artistHtml: json['artistHtml'] as String? ?? '',
        licenseShortName: json['licenseShortName'] as String? ?? '',
        licenseUrl: json['licenseUrl'] as String? ?? '',
        dateTimeOriginal: json['dateTimeOriginal'] as String? ?? '',
        uploader: json['uploader'] as String? ?? '',
        width: (json['width'] as num?)?.toInt() ?? 0,
        height: (json['height'] as num?)?.toInt() ?? 0,
        fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
        sha1: json['sha1'] as String? ?? '',
        categories: json['categories'] as String? ?? '',
        assessments: json['assessments'] as String? ?? '',
        imageDescriptionHtml: json['imageDescriptionHtml'] as String? ?? '',
        objectName: json['objectName'] as String? ?? '',
        creditHtml: json['creditHtml'] as String? ?? '',
        usageTerms: json['usageTerms'] as String? ?? '',
        copyrighted: json['copyrighted'] as String? ?? '',
        restrictions: json['restrictions'] as String? ?? '',
        uploadDateTime: json['uploadDateTime'] as String? ?? '',
        gpsLatitude: json['gpsLatitude'] as String? ?? '',
        gpsLongitude: json['gpsLongitude'] as String? ?? '',
        permissionHtml: json['permissionHtml'] as String? ?? '',
        attributionRequired: json['attributionRequired'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );

  String get extension {
    final path = Uri.tryParse(url)?.path;

    if (path != null && path.isNotEmpty) {
      final fileName = path.split('/').last;
      final dotIndex = fileName.lastIndexOf('.');

      if (dotIndex > 0 && dotIndex < fileName.length - 1) {
        return fileName.substring(dotIndex + 1).toLowerCase();
      }
    }

    final cleanUrl = url.split('?').first.split('#').first;
    final dotIndex = cleanUrl.lastIndexOf('.');

    return dotIndex >= 0 && dotIndex < cleanUrl.length - 1
        ? cleanUrl.substring(dotIndex + 1).toLowerCase()
        : '';
  }

  String get fileTypeLabel {
    switch (mime.toLowerCase()) {
      case 'image/jpeg':
      case 'image/jpg':
        return 'JPG';
      case 'image/png':
        return 'PNG';
      case 'image/gif':
        return 'GIF';
      case 'image/webp':
        return 'WEBP';
      case 'image/svg+xml':
        return 'SVG';
      case 'image/tiff':
        return 'TIFF';
      case 'image/x-xcf':
        return 'XCF';
      case 'application/pdf':
        return 'PDF';
      case 'image/vnd.djvu':
      case 'application/vnd.djvu':
        return 'DJVU';
      case 'audio/ogg':
      case 'audio/ogg; codecs=opus':
      case 'application/ogg':
        return extension.isEmpty ? 'OGG' : extension.toUpperCase();
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'MP3';
      case 'audio/flac':
        return 'FLAC';
      case 'audio/midi':
        return 'MIDI';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'WAV';
      case 'audio/webm':
      case 'video/webm':
        return 'WEBM';
      case 'video/ogg':
      case 'video/ogg; codecs=theora':
        return extension.isEmpty ? 'OGV' : extension.toUpperCase();
      case 'video/mpeg':
        return extension.isEmpty ? 'MPEG' : extension.toUpperCase();
      case 'video/mp4':
        return 'MP4';
      case 'application/sla':
        return 'STL';
    }

    return extension.isEmpty ? mime.toUpperCase() : extension.toUpperCase();
  }

  MediaKind get mediaKind {
    final m = mime.toLowerCase();
    final normalizedExtension = extension.toLowerCase();

    final isPdf = m == 'application/pdf' || normalizedExtension == 'pdf';
    final isDjVu = m == 'image/vnd.djvu' ||
        m == 'application/vnd.djvu' ||
        normalizedExtension == 'djvu';

    if (isPdf || isDjVu) return MediaKind.document;
    if (m.startsWith('image/')) {
      if (m.contains('svg')) return MediaKind.vector;
      return MediaKind.image;
    }
    if (m.startsWith('video/') ||
        normalizedExtension == 'webm' ||
        normalizedExtension == 'ogv' ||
        normalizedExtension == 'mpg' ||
        normalizedExtension == 'mpeg' ||
        normalizedExtension == 'mp4') {
      return MediaKind.video;
    }
    if (m.startsWith('audio/') ||
        normalizedExtension == 'ogg' ||
        normalizedExtension == 'oga' ||
        normalizedExtension == 'ogx' ||
        normalizedExtension == 'opus' ||
        normalizedExtension == 'mp3' ||
        normalizedExtension == 'flac' ||
        normalizedExtension == 'mid' ||
        normalizedExtension == 'midi' ||
        normalizedExtension == 'wav') {
      return MediaKind.audio;
    }
    return MediaKind.unknown;
  }
}

class SearchResponse {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueParams;

  /// Non-fatal issues encountered while fetching this page. A pipeline export
  /// may continue after a page is skipped; the warning is carried into the
  /// resumable pipeline cache so a later run does not repeat that page.
  final String? warning;

  /// Wikimedia's own estimate of total matches for this query. Only ever
  /// set by the leaf request that actually hits the search API — a
  /// "+"-query or a union-mode filter fans out into several independent
  /// underlying searches merged together (see [SearchService._fanOutFetch]),
  /// and there's no single accurate total to report for those, so this
  /// stays null rather than showing a misleading number.
  final int? totalHits;

  /// CirrusSearch's "did you mean" spelling suggestion, if any. Same
  /// single-request caveat as [totalHits].
  final String? suggestion;

  const SearchResponse({
    required this.items,
    required this.continueParams,
    this.warning,
    this.totalHits,
    this.suggestion,
  });
}

@immutable
class SearchSessionKey {
  final MediaTabType tab;
  final String querySignature;

  const SearchSessionKey({
    required this.tab,
    required this.querySignature,
  });

  @override
  bool operator ==(Object other) {
    return other is SearchSessionKey &&
        other.tab == tab &&
        other.querySignature == querySignature;
  }

  @override
  int get hashCode => Object.hash(tab, querySignature);
}

class SearchSession {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueParams;
  final bool hasMore;
  final bool hasSearched;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final double scrollOffset;

  /// See [SearchResponse.totalHits] — carried through here so a
  /// [CommonsSearchSession] consumer gets the same data a direct
  /// [CommonsBackend] caller would, not just the stateless path.
  final int? totalHits;
  final String? suggestion;

  const SearchSession({
    this.items = const [],
    this.continueParams,
    this.hasMore = false,
    this.hasSearched = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.scrollOffset = 0,
    this.totalHits,
    this.suggestion,
  });

  SearchSession copyWith({
    List<SearchItem>? items,
    Map<String, dynamic>? continueParams,
    bool? hasMore,
    bool? hasSearched,
    bool? loading,
    bool? loadingMore,
    String? error,
    double? scrollOffset,
    int? totalHits,
    String? suggestion,
    bool clearContinueParams = false,
    bool clearError = false,
  }) {
    return SearchSession(
      items: items ?? this.items,
      continueParams:
          clearContinueParams ? null : (continueParams ?? this.continueParams),
      hasMore: hasMore ?? this.hasMore,
      hasSearched: hasSearched ?? this.hasSearched,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      scrollOffset: scrollOffset ?? this.scrollOffset,
      totalHits: totalHits ?? this.totalHits,
      suggestion: suggestion ?? this.suggestion,
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'continueParams': continueParams,
        'hasMore': hasMore,
        'hasSearched': hasSearched,
        'loading': loading,
        'loadingMore': loadingMore,
        'error': error,
        'scrollOffset': scrollOffset,
        'totalHits': totalHits,
        'suggestion': suggestion,
      };

  static SearchSession fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final continueParamsRaw = json['continueParams'];
    return SearchSession(
      items: itemsRaw is List
          ? itemsRaw
              .whereType<Map>()
              .map((m) => SearchItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      continueParams: continueParamsRaw is Map
          ? Map<String, dynamic>.from(continueParamsRaw)
          : null,
      hasMore: json['hasMore'] as bool? ?? false,
      hasSearched: json['hasSearched'] as bool? ?? false,
      loading: json['loading'] as bool? ?? false,
      loadingMore: json['loadingMore'] as bool? ?? false,
      error: json['error'] as String?,
      scrollOffset: (json['scrollOffset'] as num?)?.toDouble() ?? 0,
      totalHits: (json['totalHits'] as num?)?.toInt(),
      suggestion: json['suggestion'] as String?,
    );
  }
}

// -----------------------------------------------------------------------------
// Structured Data on Commons (SDC) read-back — see
// SearchService.fetchStructuredData. Distinct from WikidataStatement above,
// which is a property=value *filter* used to build a haswbstatement: query
// clause; these classes represent the *result* of reading a specific
// file's actual claims back (e.g. to display in the asset viewer).
// -----------------------------------------------------------------------------

/// One statement (claim) from a file's SDC entity — e.g. "creator: Ansel
/// Adams" or "coordinates of the depicted place: 48.85, 2.29".
class StructuredDataStatement {
  final String propertyId; // P-code, e.g. "P170" (creator)
  final String propertyLabel; // resolved label, or propertyId if unresolved
  final String valueDisplay; // best-effort human-readable value
  final String? valueEntityId; // Q-code if the value is itself a Wikibase item

  const StructuredDataStatement({
    required this.propertyId,
    required this.propertyLabel,
    required this.valueDisplay,
    this.valueEntityId,
  });

  Map<String, dynamic> toJson() => {
        'propertyId': propertyId,
        'propertyLabel': propertyLabel,
        'valueDisplay': valueDisplay,
        'valueEntityId': valueEntityId,
      };

  static StructuredDataStatement fromJson(Map<String, dynamic> json) =>
      StructuredDataStatement(
        propertyId: json['propertyId'] as String? ?? '',
        propertyLabel: json['propertyLabel'] as String? ?? '',
        valueDisplay: json['valueDisplay'] as String? ?? '',
        valueEntityId: json['valueEntityId'] as String?,
      );
}

/// The full SDC entity (`M<pageid>`) attached to one Commons file: its
/// multilingual captions (Wikibase labels — distinct from the legacy,
/// single free-text `ImageDescription` extmetadata field SearchItem
/// already carries) plus every structured statement.
class StructuredDataResult {
  final String mid; // e.g. "M12345"
  final Map<String, String> captions; // language code -> caption text
  final List<StructuredDataStatement> statements;

  /// The complete MediaInfo entity returned by Wikimedia. The typed fields
  /// above are convenient for UI/filtering; this raw object prevents
  /// qualifiers, references, ranks, revision data, and future API fields from
  /// being discarded during ETL.
  final Map<String, dynamic> raw;

  const StructuredDataResult({
    required this.mid,
    required this.captions,
    required this.statements,
    this.raw = const {},
  });

  Map<String, dynamic> toJson() => {
        'mid': mid,
        'captions': captions,
        'statements': statements.map((s) => s.toJson()).toList(),
        'raw': raw,
      };

  static StructuredDataResult fromJson(Map<String, dynamic> json) {
    final captionsRaw = json['captions'] as Map<String, dynamic>? ?? {};
    final statementsRaw = json['statements'] as List? ?? [];
    return StructuredDataResult(
      mid: json['mid'] as String? ?? '',
      captions: {
        for (final entry in captionsRaw.entries)
          entry.key: entry.value?.toString() ?? '',
      },
      statements: statementsRaw
          .whereType<Map>()
          .map((m) =>
              StructuredDataStatement.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      raw: json['raw'] is Map
          ? Map<String, dynamic>.from(json['raw'] as Map)
          : const {},
    );
  }
}

// -----------------------------------------------------------------------------
// Global usage — see SearchService.fetchGlobalUsage
// -----------------------------------------------------------------------------

/// One Wikimedia page (any language, any project) that currently embeds a
/// given Commons file — a real-world "is this actually used anywhere"
/// quality signal, distinct from anything CirrusSearch itself indexes.
class GlobalUsageEntry {
  final String wiki; // e.g. "en.wikipedia.org"
  final String title; // the page title on that wiki
  final String? url;
  final int? pageId;
  final int? namespace;

  /// Original usage object, retained so future API fields are not discarded.
  final Map<String, dynamic> raw;

  const GlobalUsageEntry({
    required this.wiki,
    required this.title,
    this.url,
    this.pageId,
    this.namespace,
    this.raw = const {},
  });

  Map<String, dynamic> toJson() => {
        ...raw,
        'wiki': wiki,
        'title': title,
        'url': url,
        'pageid': pageId,
        'namespace': namespace,
      };

  static GlobalUsageEntry fromJson(Map<String, dynamic> json) => (() {
        final rawNamespace = json['namespace'] ?? json['ns'];
        return GlobalUsageEntry(
          wiki: json['wiki'] as String? ?? '',
          title: json['title'] as String? ?? '',
          url: json['url'] as String?,
          pageId: (json['pageid'] as num?)?.toInt(),
          namespace: rawNamespace is num ? rawNamespace.toInt() : null,
          raw: Map<String, dynamic>.from(json),
        );
      })();
}
