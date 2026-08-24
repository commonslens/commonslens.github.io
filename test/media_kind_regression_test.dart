import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchItem mediaKind detection', () {
    test('DJVU mime types are treated as documents, not images', () {
      const djvuMimeItem = SearchItem(
        title: 'djvu-file',
        url: 'https://example.com/file.djvu',
        thumb: '',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:file.djvu',
        snippet: '',
        mime: 'image/vnd.djvu',
        isSvg: false,
      );

      const djvuAltMimeItem = SearchItem(
        title: 'djvu-file-alt',
        url: 'https://example.com/file.djvu',
        thumb: '',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:file.djvu',
        snippet: '',
        mime: 'application/vnd.djvu',
        isSvg: false,
      );

      expect(djvuMimeItem.mediaKind, MediaKind.document);
      expect(djvuAltMimeItem.mediaKind, MediaKind.document);
    });

    test('PDFs are still treated as documents', () {
      const pdfItem = SearchItem(
        title: 'pdf-file',
        url: 'https://example.com/file.pdf',
        thumb: '',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:file.pdf',
        snippet: '',
        mime: 'application/pdf',
        isSvg: false,
      );

      expect(pdfItem.mediaKind, MediaKind.document);
    });

    test('MP3 and OGV files are classified into the right media tabs', () {
      const mp3Item = SearchItem(
        title: 'audio-file',
        url: 'https://example.com/file.mp3',
        thumb: '',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:file.mp3',
        snippet: '',
        mime: 'audio/mpeg',
        isSvg: false,
      );

      const ogvItem = SearchItem(
        title: 'video-file',
        url: 'https://example.com/file.ogv',
        thumb: '',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:file.ogv',
        snippet: '',
        mime: 'video/ogg',
        isSvg: false,
      );

      expect(mp3Item.mediaKind, MediaKind.audio);
      expect(ogvItem.mediaKind, MediaKind.video);
    });
  });
}
