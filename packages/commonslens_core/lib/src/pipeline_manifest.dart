import 'search_models.dart';

/// Metadata presets exposed by the Dataset Manifest sink.
enum ManifestMetadataLevel { essential, detailed, full }

/// Which downloadable media URLs are included in each manifest row.
enum ManifestImageLinks { original, thumbnail, both }

ManifestMetadataLevel manifestMetadataLevelFromName(String? value) {
  for (final level in ManifestMetadataLevel.values) {
    if (level.name == value) return level;
  }
  return ManifestMetadataLevel.detailed;
}

ManifestImageLinks manifestImageLinksFromName(String? value) {
  for (final links in ManifestImageLinks.values) {
    if (links.name == value) return links;
  }
  return ManifestImageLinks.both;
}

/// Produces CSV-ready rows without downloading media binaries.
///
/// When [projectedRecords] is supplied, an upstream Field Select transform
/// owns the exported schema. Identity and requested download URLs are still
/// added so every row remains a useful dataset manifest. Otherwise the
/// selected [metadataLevel] determines the columns, and enrichment-only
/// fields from [additionalRecords] are retained by the Full preset.
List<Map<String, dynamic>> buildManifestRecords(
  List<SearchItem> items, {
  ManifestMetadataLevel metadataLevel = ManifestMetadataLevel.detailed,
  ManifestImageLinks imageLinks = ManifestImageLinks.both,
  List<Map<String, dynamic>>? projectedRecords,
  List<Map<String, dynamic>>? additionalRecords,
}) {
  return List<Map<String, dynamic>>.generate(items.length, (index) {
    final item = items[index];
    final projected =
        projectedRecords != null && index < projectedRecords.length
            ? projectedRecords[index]
            : null;

    final row = projected == null
        ? _recordForLevel(item, metadataLevel)
        : Map<String, dynamic>.from(projected);

    // Existing generic exports called these fields url/thumb. Remove them so
    // the manifest has one unambiguous schema regardless of its upstream
    // transforms or whether the row came from SearchItem.toJson().
    row.remove('url');
    row.remove('thumb');
    row['title'] = row['title'] ?? item.title;
    row['commonsUrl'] = row['commonsUrl'] ?? item.commonsUrl;

    switch (imageLinks) {
      case ManifestImageLinks.original:
        row.remove('thumbnailUrl');
        row['originalUrl'] = item.url;
        break;
      case ManifestImageLinks.thumbnail:
        row.remove('originalUrl');
        row['thumbnailUrl'] = item.thumb;
        break;
      case ManifestImageLinks.both:
        row['originalUrl'] = item.url;
        row['thumbnailUrl'] = item.thumb;
        break;
    }

    if (projected == null &&
        metadataLevel == ManifestMetadataLevel.full &&
        additionalRecords != null &&
        index < additionalRecords.length) {
      final extras = additionalRecords[index];
      for (final entry in extras.entries) {
        if (!item.toJson().containsKey(entry.key)) {
          row[entry.key] = entry.value;
        }
      }
    }

    return row;
  });
}

Map<String, dynamic> _recordForLevel(
  SearchItem item,
  ManifestMetadataLevel level,
) {
  final essential = <String, dynamic>{
    'title': item.title,
    'commonsUrl': item.commonsUrl,
    'mime': item.mime,
    'width': item.width,
    'height': item.height,
    'fileSizeBytes': item.fileSizeBytes,
    'sha1': item.sha1,
    'licenseShortName': item.licenseShortName,
    'licenseUrl': item.licenseUrl,
    'artistHtml': item.artistHtml,
    'attributionRequired': item.attributionRequired,
  };

  if (level == ManifestMetadataLevel.essential) return essential;

  final detailed = <String, dynamic>{
    ...essential,
    'uploader': item.uploader,
    'timestamp': item.timestamp,
    'uploadDateTime': item.uploadDateTime,
    'dateTimeOriginal': item.dateTimeOriginal,
    'descriptionUrl': item.descriptionUrl,
    'imageDescriptionHtml': item.imageDescriptionHtml,
    'objectName': item.objectName,
    'creditHtml': item.creditHtml,
    'usageTerms': item.usageTerms,
    'copyrighted': item.copyrighted,
    'restrictions': item.restrictions,
    'categories': item.categories,
    'assessments': item.assessments,
    'latitude': item.resolvedLatitude,
    'longitude': item.resolvedLongitude,
  };

  if (level == ManifestMetadataLevel.detailed) return detailed;

  return <String, dynamic>{
    ...item.toJson(),
    'fileSizeBytes': item.fileSizeBytes,
    'sha1': item.sha1,
  };
}
