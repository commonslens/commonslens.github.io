import 'package:commonslens/asset_reuse_guide.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SearchItem item({
    String title = 'File:Sun & Moon.jpg',
    String artistHtml = '<a href="/wiki/User:Ada">Ada &amp; Bob</a>',
    String licenseShortName = 'CC BY-SA 4.0',
    String licenseUrl = 'https://creativecommons.org/licenses/by-sa/4.0/',
    String attributionRequired = 'true',
    String creditHtml = '',
    String restrictions = '',
  }) {
    return SearchItem(
      title: title,
      url: 'https://upload.wikimedia.org/original/Sun_Moon.jpg',
      thumb: 'https://upload.wikimedia.org/thumb/320px-Sun_Moon.jpg',
      commonsUrl:
          'https://commons.wikimedia.org/wiki/File:Sun_%26_Moon.jpg?oldid=1&x=2',
      snippet: '',
      mime: 'image/jpeg',
      isSvg: false,
      artistHtml: artistHtml,
      uploader: 'Uploader',
      licenseShortName: licenseShortName,
      licenseUrl: licenseUrl,
      attributionRequired: attributionRequired,
      creditHtml: creditHtml,
      objectName: 'A solar and lunar study',
      restrictions: restrictions,
    );
  }

  test('builds a human-readable attribution from Commons metadata', () {
    final guide = AssetReuseGuide(item());

    expect(guide.fileName, 'Sun & Moon.jpg');
    expect(guide.creator, 'Ada & Bob');
    expect(guide.attributionRequired, isTrue);
    expect(
      guide.attributionText,
      contains('“Sun & Moon.jpg” by Ada & Bob — CC BY-SA 4.0'),
    );
    expect(guide.attributionText, contains('via Wikimedia Commons'));
  });

  test('escapes generated HTML and includes license and source links', () {
    final guide = AssetReuseGuide(item(creditHtml: 'Photo by Ada &amp; Bob'));

    expect(guide.htmlEmbed, contains('alt="Sun &amp; Moon.jpg"'));
    expect(guide.htmlEmbed, contains('Ada &amp; Bob'));
    expect(guide.htmlEmbed, contains('credit: Photo by Ada &amp; Bob'));
    expect(guide.htmlEmbed, contains('CC BY-SA 4.0'));
    expect(guide.htmlEmbed, contains('?oldid=1&amp;x=2'));
    expect(guide.htmlEmbed, contains('<figcaption>'));
  });

  test('generates conventional WikiText using the Commons filename', () {
    final guide = AssetReuseGuide(item());

    expect(
      guide.wikiText,
      '[[File:Sun & Moon.jpg|thumb|A solar and lunar study]]',
    );
  });

  test('does not infer missing attribution or licensing information', () {
    final guide = AssetReuseGuide(item(
      artistHtml: '',
      licenseShortName: '',
      licenseUrl: '',
      attributionRequired: '',
    ));

    expect(guide.creator, isEmpty);
    expect(guide.hasCompleteReuseMetadata, isFalse);
    expect(guide.attributionRequired, isNull);
    expect(guide.attributionText, isNot(contains('licensed under')));
  });
}
