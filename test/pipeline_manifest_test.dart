import 'package:commonslens/pipeline_manifest.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _item = SearchItem(
  title: 'Example.jpg',
  url: 'https://upload.wikimedia.org/example.jpg',
  thumb: 'https://upload.wikimedia.org/thumb/example.jpg',
  commonsUrl: 'https://commons.wikimedia.org/wiki/File:Example.jpg',
  snippet: 'Example',
  mime: 'image/jpeg',
  isSvg: false,
  width: 1920,
  height: 1080,
  fileSizeBytes: 456789,
  sha1: 'abcdef123456',
  uploader: 'Example user',
  licenseShortName: 'CC BY-SA 4.0',
  licenseUrl: 'https://creativecommons.org/licenses/by-sa/4.0/',
  artistHtml: 'Example artist',
  attributionRequired: 'true',
  categories: 'Example images',
);

void main() {
  test('essential manifest keeps identity, rights, and requested links', () {
    final row = buildManifestRecords(
      const [_item],
      metadataLevel: ManifestMetadataLevel.essential,
      imageLinks: ManifestImageLinks.original,
    ).single;

    expect(row['originalUrl'], _item.url);
    expect(row.containsKey('thumbnailUrl'), isFalse);
    expect(row['fileSizeBytes'], 456789);
    expect(row['sha1'], 'abcdef123456');
    expect(row['licenseShortName'], 'CC BY-SA 4.0');
    expect(row.containsKey('uploader'), isFalse);
  });

  test('detailed manifest includes descriptive metadata and both URLs', () {
    final row = buildManifestRecords(const [_item]).single;

    expect(row['originalUrl'], _item.url);
    expect(row['thumbnailUrl'], _item.thumb);
    expect(row['uploader'], 'Example user');
    expect(row['categories'], 'Example images');
  });

  test('field projection controls columns but cannot remove media identity',
      () {
    final row = buildManifestRecords(
      const [_item],
      projectedRecords: const [
        {'width': 1920}
      ],
    ).single;

    expect(row['width'], 1920);
    expect(row['title'], _item.title);
    expect(row['commonsUrl'], _item.commonsUrl);
    expect(row['originalUrl'], _item.url);
    expect(row['thumbnailUrl'], _item.thumb);
    expect(row.containsKey('uploader'), isFalse);
  });
}
