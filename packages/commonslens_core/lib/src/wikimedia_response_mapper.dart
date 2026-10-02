import 'search_models.dart';

/// Converts Wikimedia API payload fragments into typed CommonsLens models.
///
/// This class performs no networking. Keeping API-shape normalization here
/// gives every transport path the same defensive parsing rules.
class WikimediaResponseMapper {
  const WikimediaResponseMapper();

  static final RegExp _htmlTagPattern = RegExp(r'<[^>]*>');

  Map<String, dynamic> _object(dynamic raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  String _string(dynamic raw) => raw is String ? raw : '';

  String _metadataValue(Map<String, dynamic> metadata, String key) {
    final field = _object(metadata[key]);
    return field['value']?.toString() ?? '';
  }

  /// Maps one `imageinfo` object returned by any Commons endpoint.
  SearchItem? itemFromImageInfo(
    Map<String, dynamic> info, {
    required String rawTitle,
    required String snippet,
    String? timestamp,
    String? descriptionUrl,
    String? uploaderFallback,
    double? latitude,
    double? longitude,
  }) {
    final originalUrl = _string(info['url']);
    if (originalUrl.isEmpty) return null;

    final mime = _string(info['mime']).toLowerCase();
    final thumbnailUrl = _string(info['thumburl']);
    final metadata = _object(info['extmetadata']);

    return SearchItem(
      title: rawTitle.replaceFirst('File:', ''),
      url: originalUrl,
      thumb: thumbnailUrl.isNotEmpty ? thumbnailUrl : originalUrl,
      commonsUrl:
          'https://commons.wikimedia.org/wiki/${Uri.encodeComponent(rawTitle)}',
      snippet: snippet,
      mime: mime,
      isSvg: mime == 'image/svg+xml',
      timestamp: timestamp,
      descriptionUrl: descriptionUrl,
      artistHtml: _metadataValue(metadata, 'Artist'),
      licenseShortName: _metadataValue(metadata, 'LicenseShortName'),
      licenseUrl: _metadataValue(metadata, 'LicenseUrl'),
      dateTimeOriginal: _metadataValue(metadata, 'DateTimeOriginal'),
      uploader: info['user']?.toString() ?? (uploaderFallback ?? ''),
      width: info['width'] is num ? (info['width'] as num).toInt() : 0,
      height: info['height'] is num ? (info['height'] as num).toInt() : 0,
      categories: _metadataValue(metadata, 'Categories'),
      assessments: _metadataValue(metadata, 'Assessments'),
      imageDescriptionHtml: _metadataValue(metadata, 'ImageDescription'),
      objectName: _metadataValue(metadata, 'ObjectName'),
      creditHtml: _metadataValue(metadata, 'Credit'),
      usageTerms: _metadataValue(metadata, 'UsageTerms'),
      copyrighted: _metadataValue(metadata, 'Copyrighted'),
      restrictions: _metadataValue(metadata, 'Restrictions'),
      uploadDateTime: _metadataValue(metadata, 'DateTime'),
      gpsLatitude: _metadataValue(metadata, 'GPSLatitude'),
      gpsLongitude: _metadataValue(metadata, 'GPSLongitude'),
      permissionHtml: _metadataValue(metadata, 'Permission'),
      attributionRequired: _metadataValue(metadata, 'AttributionRequired'),
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Returns the Q-code for entity-valued Wikibase claims.
  String? entityIdFromSnak(Map<String, dynamic> snak) {
    if (snak['snaktype'] != 'value') return null;
    final dataValue = _object(snak['datavalue']);
    if (dataValue['type'] != 'wikibase-entityid') return null;
    final value = _object(dataValue['value']);
    return value['id'] is String ? value['id'] as String : null;
  }

  /// Formats common literal Wikibase values for display.
  String formatSnakValue(Map<String, dynamic> snak) {
    if (snak['snaktype'] == 'novalue') return '(no value)';
    if (snak['snaktype'] == 'somevalue') return '(unknown value)';

    final dataValue = _object(snak['datavalue']);
    if (dataValue.isEmpty) return '';
    final value = dataValue['value'];

    switch (dataValue['type']) {
      case 'string':
        return value?.toString() ?? '';
      case 'monolingualtext':
        return _string(_object(value)['text']);
      case 'time':
        final raw = _string(_object(value)['time']);
        return raw.replaceFirst('+', '').split('T').first;
      case 'globecoordinate':
        final coordinate = _object(value);
        final latitude = coordinate['latitude'];
        final longitude = coordinate['longitude'];
        return latitude != null && longitude != null
            ? '$latitude, $longitude'
            : '';
      case 'quantity':
        return _string(_object(value)['amount']).replaceFirst('+', '');
      default:
        return value?.toString() ?? '';
    }
  }

  String stripHtml(String value) =>
      value.replaceAll(_htmlTagPattern, '').trim();
}
