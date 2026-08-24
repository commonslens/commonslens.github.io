import 'package:flutter/foundation.dart';

enum MediaTabType {
  allMedia,
  images,
  vectors,
  audio,
  video,
  documents,
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
  pdf,
  djvu,
  ogg,
  oga,
  ogv,
  mp3,
  wav,
  webm,
  mp4,
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
  any,
  cc0,
  ccBy4,
  ccBySa4,
  publicDomain,
}

String licensePresetLabel(LicensePreset preset) {
  switch (preset) {
    case LicensePreset.any:
      return 'Any license';
    case LicensePreset.cc0:
      return 'CC0';
    case LicensePreset.ccBy4:
      return 'CC BY 4.0';
    case LicensePreset.ccBySa4:
      return 'CC BY-SA 4.0';
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

String qualityFilterLabel(QualityFilter filter) {
  switch (filter) {
    case QualityFilter.any:
      return 'Any quality';
    case QualityFilter.qualityImage:
      return 'Quality images';
    case QualityFilter.valuedImage:
      return 'Valued images';
    case QualityFilter.featuredPicture:
      return 'Featured pictures';
  }
}

enum MediaKind {
  image,
  vector,
  audio,
  video,
  document,
  unknown,
}

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
}

class NearCoordFilter {
  final double lat;
  final double lng;
  final double radiusKm;

  const NearCoordFilter({
    required this.lat,
    required this.lng,
    this.radiusKm = 10,
  });

  NearCoordFilter copyWith({double? lat, double? lng, double? radiusKm}) {
    return NearCoordFilter(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusKm: radiusKm ?? this.radiusKm,
    );
  }
}

/// Geosearch near a page/entity title instead of raw coordinates — CirrusSearch's
/// neartitle: keyword sources the coordinates from the named page itself.
/// Mutually exclusive with NearCoordFilter in practice (the drawer enforces
/// this), but kept as a separate field rather than folded into one type so
/// each stays a simple, direct mirror of its own CirrusSearch keyword.
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
  bool operator ==(Object other) =>
      other is DepictsEntity && other.qid == qid;

  @override
  int get hashCode => qid.hashCode;
}

/// An arbitrary Wikidata property=value pair, for haswbstatement: search
/// beyond the two hardcoded properties (P180 depicts, P275 license) that
/// depictsInclude/licensePreset already cover. Reuses DepictsEntity's shape
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
}

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
  final DateFilter? createdDate;
  final DateFilter? editedDate;
  final SortMode sortMode;
  final LicensePreset licensePreset;
  final QualityFilter qualityFilter;
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
    this.sortMode = SortMode.relevance,
    this.licensePreset = LicensePreset.any,
    this.qualityFilter = QualityFilter.any,
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
    SortMode? sortMode,
    LicensePreset? licensePreset,
    QualityFilter? qualityFilter,
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
    bool clearLanguageCode = false,
    bool clearContentModel = false,
    bool clearCreatedDate = false,
    bool clearEditedDate = false,
    bool clearMinWidth = false,
    bool clearMinHeight = false,
    bool clearNearCoord = false,
    bool clearNearTitle = false,
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
      createdDate:
          clearCreatedDate ? null : (createdDate ?? this.createdDate),
      editedDate:
          clearEditedDate ? null : (editedDate ?? this.editedDate),
      sortMode: sortMode ?? this.sortMode,
      licensePreset: licensePreset ?? this.licensePreset,
      qualityFilter: qualityFilter ?? this.qualityFilter,
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
    );
  }
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
      FileFormat.pdf,
      FileFormat.djvu,
      FileFormat.ogg,
      FileFormat.oga,
      FileFormat.ogv,
      FileFormat.mp3,
      FileFormat.wav,
      FileFormat.webm,
      FileFormat.mp4,
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
      FileFormat.mp3,
      FileFormat.wav,
    },
    emptyMessage: 'No audio found.',
  ),
  MediaTabConfig(
    type: MediaTabType.video,
    label: 'Video',
    allowedFormats: {
      FileFormat.webm,
      FileFormat.ogv,
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
    case FileFormat.pdf:
      return 'PDF';
    case FileFormat.djvu:
      return 'DJVU';
    case FileFormat.ogg:
      return 'OGG';
    case FileFormat.oga:
      return 'OGA';
    case FileFormat.ogv:
      return 'OGV';
    case FileFormat.mp3:
      return 'MP3';
    case FileFormat.wav:
      return 'WAV';
    case FileFormat.webm:
      return 'WEBM';
    case FileFormat.mp4:
      return 'MP4';
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
      return MediaKind.image;
    case FileFormat.svg:
      return MediaKind.vector;
    case FileFormat.ogg:
    case FileFormat.oga:
    case FileFormat.mp3:
    case FileFormat.wav:
      return MediaKind.audio;
    case FileFormat.webm:
    case FileFormat.ogv:
    case FileFormat.mp4:
      return MediaKind.video;
    case FileFormat.pdf:
    case FileFormat.djvu:
      return MediaKind.document;
  }
}

class QueryChipData {
  final String id;
  final String label;

  const QueryChipData({
    required this.id,
    required this.label,
  });
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
}

class SearchItem {
  final String title;
  final String url;
  final String thumb;
  final String commonsUrl;
  final String snippet;
  final String mime;
  final bool isSvg;
  final String? timestamp;
  final String? descriptionUrl;
  
  final String artistHtml;
  final String licenseShortName;
  final String licenseUrl;
  final String dateTimeOriginal;
  final String uploader;
  final int width;
  final int height;

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
  final String uploadDateTime; // upload time — distinct from dateTimeOriginal (capture time)
  final String gpsLatitude;
  final String gpsLongitude;
  final String permissionHtml;
  final String attributionRequired;

  const SearchItem({
    required this.title,
    required this.url,
    required this.thumb,
    required this.commonsUrl,
    required this.snippet,
    required this.mime,
    required this.isSvg,
    this.timestamp,
    this.descriptionUrl,
    this.artistHtml = '',
    this.licenseShortName = '',
    this.licenseUrl = '',
    this.dateTimeOriginal = '',
    this.uploader = '',
    this.width = 0,
    this.height = 0,
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
  });

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
      case 'application/pdf':
        return 'PDF';
      case 'image/vnd.djvu':
      case 'application/vnd.djvu':
        return 'DJVU';
      case 'audio/ogg':
      case 'audio/ogg; codecs=opus':
        return 'OGG';
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'MP3';
      case 'audio/wav':
      case 'audio/x-wav':
        return 'WAV';
      case 'video/webm':
        return 'WEBM';
      case 'video/ogg':
      case 'video/ogg; codecs=theora':
        return 'OGV';
      case 'video/mp4':
        return 'MP4';
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
        normalizedExtension == 'mp4') {
      return MediaKind.video;
    }
    if (m.startsWith('audio/') ||
        normalizedExtension == 'ogg' ||
        normalizedExtension == 'oga' ||
        normalizedExtension == 'mp3' ||
        normalizedExtension == 'wav') {
      return MediaKind.audio;
    }
    return MediaKind.unknown;
  }
}

class SearchResponse {
  final List<SearchItem> items;
  final Map<String, dynamic>? continueParams;

  const SearchResponse({
    required this.items,
    required this.continueParams,
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

  const SearchSession({
    this.items = const [],
    this.continueParams,
    this.hasMore = false,
    this.hasSearched = false,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.scrollOffset = 0,
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
    );
  }
}