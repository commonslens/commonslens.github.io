import 'search_models.dart';

enum AssetReuseFormat { attribution, html, wikiText }

/// Turns Wikimedia's extmetadata fields into practical, copy-ready reuse
/// guidance. The source metadata remains authoritative: this class never
/// guesses that attribution is optional or that a restriction does not apply.
class AssetReuseGuide {
  final SearchItem item;

  const AssetReuseGuide(this.item);

  String get fileName => item.title
      .replaceFirst(RegExp(r'^File:', caseSensitive: false), '')
      .trim();

  String get creator {
    return plainText(item.artistHtml);
  }

  String get creditLine => plainText(item.creditHtml);
  String get permission => plainText(item.permissionHtml);
  String get licenseName => plainText(item.licenseShortName);
  String get licenseUrl => item.licenseUrl.trim();
  String get sourceUrl => item.commonsUrl.trim().isNotEmpty
      ? item.commonsUrl.trim()
      : (item.descriptionUrl ?? '').trim();
  String get restrictions => plainText(item.restrictions);
  String get usageTerms => plainText(item.usageTerms);
  String get copyrightStatus => plainText(item.copyrighted);

  bool? get copyrightProtected => _parseBooleanFlag(copyrightStatus);

  String get copyrightProtectionLabel => switch (copyrightProtected) {
        true => 'Yes',
        false => 'No',
        null => copyrightStatus,
      };

  bool get hasCompleteReuseMetadata =>
      creator.isNotEmpty && licenseName.isNotEmpty;

  bool? get attributionRequired =>
      _parseBooleanFlag(item.attributionRequired.trim());

  static bool? _parseBooleanFlag(String value) {
    switch (value.toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'required':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'not required':
        return false;
      default:
        return null;
    }
  }

  String get attributionText {
    final parts = <String>[
      creator.isEmpty ? '“$fileName”' : '“$fileName” by $creator',
      if (creditLine.isNotEmpty) 'Credit: $creditLine',
      if (licenseName.isNotEmpty) licenseName,
      if (sourceUrl.isNotEmpty) 'via Wikimedia Commons ($sourceUrl)',
    ];
    return parts.join(' — ');
  }

  String get attributionHtml {
    final title = sourceUrl.isEmpty
        ? escapeHtml(fileName)
        : '<a href="${escapeHtml(sourceUrl)}">${escapeHtml(fileName)}</a>';
    final byline = creator.isEmpty ? title : '$title by ${escapeHtml(creator)}';
    final credit =
        creditLine.isEmpty ? '' : ', credit: ${escapeHtml(creditLine)}';
    final license = licenseName.isEmpty
        ? ''
        : licenseUrl.isEmpty
            ? ', ${escapeHtml(licenseName)}'
            : ', licensed under <a href="${escapeHtml(licenseUrl)}">${escapeHtml(licenseName)}</a>';
    final source = sourceUrl.isEmpty ? '' : ', via Wikimedia Commons';
    return '$byline$credit$license$source.';
  }

  String get htmlEmbed {
    final mediaUrl = item.thumbnailUrlAtWidth(1280) ?? item.url;
    final escapedMediaUrl = escapeHtml(mediaUrl);
    final escapedSourceUrl = escapeHtml(sourceUrl);
    final escapedTitle = escapeHtml(fileName);
    final sourceOpen = sourceUrl.isEmpty ? '' : '<a href="$escapedSourceUrl">';
    final sourceClose = sourceUrl.isEmpty ? '' : '</a>';

    final mediaMarkup = switch (item.mediaKind) {
      MediaKind.image ||
      MediaKind.vector =>
        '$sourceOpen<img src="$escapedMediaUrl" alt="$escapedTitle" loading="lazy">$sourceClose',
      MediaKind.video =>
        '<video controls src="${escapeHtml(item.url)}"></video>',
      MediaKind.audio =>
        '<audio controls src="${escapeHtml(item.url)}"></audio>',
      MediaKind.document || MediaKind.unknown => sourceUrl.isEmpty
          ? '<a href="${escapeHtml(item.url)}">View $escapedTitle</a>'
          : '<a href="$escapedSourceUrl">View $escapedTitle</a>',
    };

    return '<figure>\n  $mediaMarkup\n  <figcaption>$attributionHtml</figcaption>\n</figure>';
  }

  String get wikiText {
    final description = plainText(item.objectName).isNotEmpty
        ? plainText(item.objectName)
        : fileName.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final safeCaption = description.replaceAll('|', '{{!}}');
    return '[[File:$fileName|thumb|$safeCaption]]';
  }

  String snippetFor(AssetReuseFormat format) => switch (format) {
        AssetReuseFormat.attribution => attributionText,
        AssetReuseFormat.html => htmlEmbed,
        AssetReuseFormat.wikiText => wikiText,
      };

  static String escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static String plainText(String value) {
    if (value.isEmpty) return '';
    var text = value.replaceAll(RegExp(r'<[^>]*>', multiLine: true), ' ');

    const entities = <String, String>{
      '&amp;': '&',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&nbsp;': ' ',
      '&ndash;': '–',
      '&mdash;': '—',
    };
    for (final entry in entities.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    text = text.replaceAllMapped(
        RegExp(r'&#(x[0-9a-f]+|\d+);', caseSensitive: false), (match) {
      final raw = match.group(1)!;
      final codePoint = raw.toLowerCase().startsWith('x')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
