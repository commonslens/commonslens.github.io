import 'package:commonslens_core/commonslens_core.dart';
import 'package:test/test.dart';

void main() {
  const mapper = WikimediaResponseMapper();

  test('maps imageinfo metadata through one defensive contract', () {
    final item = mapper.itemFromImageInfo(
      {
        'url': 'https://upload.wikimedia.org/example.jpg',
        'thumburl': 'https://upload.wikimedia.org/thumb/example.jpg',
        'mime': 'IMAGE/JPEG',
        'width': 1200.0,
        'height': 800,
        'size': 123456,
        'sha1': 'abc123',
        'user': 'Example user',
        'extmetadata': {
          'Artist': {'value': '<b>Example artist</b>'},
          'LicenseShortName': {'value': 'CC BY-SA 4.0'},
          'AttributionRequired': {'value': 'true'},
        },
      },
      rawTitle: 'File:Example.jpg',
      snippet: 'Example',
      latitude: 12.5,
      longitude: 77.5,
    );

    expect(item, isNotNull);
    expect(item!.title, 'Example.jpg');
    expect(item.mime, 'image/jpeg');
    expect(item.width, 1200);
    expect(item.height, 800);
    expect(item.fileSizeBytes, 123456);
    expect(item.sha1, 'abc123');
    expect(item.artistHtml, '<b>Example artist</b>');
    expect(item.licenseShortName, 'CC BY-SA 4.0');
    expect(item.attributionRequired, 'true');
    expect(item.resolvedLatitude, 12.5);
    expect(item.resolvedLongitude, 77.5);
  });

  test('rejects unusable imageinfo without throwing on malformed fields', () {
    expect(
      mapper.itemFromImageInfo(
        {
          'url': 42,
          'width': 'wide',
          'extmetadata': ['not', 'an', 'object'],
        },
        rawTitle: 'File:Broken.jpg',
        snippet: '',
      ),
      isNull,
    );
  });

  test('normalizes entity and literal structured-data values', () {
    final entitySnak = <String, dynamic>{
      'snaktype': 'value',
      'datavalue': {
        'type': 'wikibase-entityid',
        'value': {'id': 'Q90'},
      },
    };

    expect(mapper.entityIdFromSnak(entitySnak), 'Q90');
    expect(
      mapper.formatSnakValue({
        'snaktype': 'value',
        'datavalue': {
          'type': 'time',
          'value': {'time': '+2020-01-15T00:00:00Z'},
        },
      }),
      '2020-01-15',
    );
    expect(
      mapper.formatSnakValue({
        'snaktype': 'value',
        'datavalue': {
          'type': 'globecoordinate',
          'value': {'latitude': 1.5, 'longitude': 2.5},
        },
      }),
      '1.5, 2.5',
    );
    expect(mapper.formatSnakValue({'snaktype': 'novalue'}), '(no value)');
    expect(mapper.entityIdFromSnak({'snaktype': 'somevalue'}), isNull);
    expect(mapper.stripHtml('<b>Hello</b> <i>world</i>'), 'Hello world');
  });
}
