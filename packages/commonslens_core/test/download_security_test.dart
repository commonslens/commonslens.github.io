import 'dart:typed_data';

import 'package:commonslens_core/commonslens_core.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

void main() {
  group('trusted media origin', () {
    test('accepts the exact HTTPS Commons upload origin', () {
      final uri = DownloadSecurityPolicy.requireTrustedMediaUri(
        'https://upload.wikimedia.org/wikipedia/commons/a/a1/Test.png',
      );

      expect(uri.host, 'upload.wikimedia.org');
    });

    test('rejects injected, lookalike, insecure, and credentialed origins', () {
      const rejected = [
        'https://evil.example/file.png',
        'https://upload.wikimedia.org.evil.example/file.png',
        'http://upload.wikimedia.org/wikipedia/commons/file.png',
        'https://attacker@upload.wikimedia.org/wikipedia/commons/file.png',
        'https://upload.wikimedia.org:444/wikipedia/commons/file.png',
        'https://upload.wikimedia.org/not-commons/file.png',
      ];

      for (final url in rejected) {
        expect(
          () => DownloadSecurityPolicy.requireTrustedMediaUri(url),
          throwsA(isA<DownloadSecurityException>()),
          reason: url,
        );
      }
    });
  });

  group('media verification', () {
    final jpeg = Uint8List.fromList(
      const [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x00, 0xff, 0xd9],
    );

    test('requires extension, MIME, byte count, and hex SHA-1 to agree', () {
      final result = DownloadSecurityPolicy.verifyMedia(
        bytes: jpeg,
        declaredContentType: 'image/jpeg',
        expectedExtension: 'jpg',
        expectedMime: 'image/jpeg',
        expectedLength: jpeg.length,
        expectedSha1: crypto.sha1.convert(jpeg).toString(),
      );

      expect(result.extension, 'jpg');
      expect(result.contentType, 'image/jpeg');
    });

    test('accepts MediaWiki base-36 SHA-1 values', () {
      final digest = crypto.sha1.convert(jpeg).toString();
      final base36 = BigInt.parse(digest, radix: 16).toRadixString(36);

      expect(
        DownloadSecurityPolicy.verifyMedia(
          bytes: jpeg,
          declaredContentType: 'image/jpeg',
          expectedExtension: 'jpeg',
          expectedSha1: base36,
        ).extension,
        'jpg',
      );
    });

    test('rejects executable, archive, MIME, extension, and hash mismatches',
        () {
      final cases = <void Function()>[
        () => DownloadSecurityPolicy.verifyMedia(
              bytes: Uint8List.fromList(const [0x4d, 0x5a, 0, 0]),
              declaredContentType: 'image/jpeg',
              expectedExtension: 'jpg',
            ),
        () => DownloadSecurityPolicy.verifyMedia(
              bytes: Uint8List.fromList(const [0x50, 0x4b, 3, 4]),
              declaredContentType: 'image/jpeg',
              expectedExtension: 'jpg',
            ),
        () => DownloadSecurityPolicy.verifyMedia(
              bytes: jpeg,
              declaredContentType: 'image/png',
              expectedExtension: 'jpg',
            ),
        () => DownloadSecurityPolicy.verifyMedia(
              bytes: jpeg,
              declaredContentType: 'image/jpeg',
              expectedExtension: 'png',
            ),
        () => DownloadSecurityPolicy.verifyMedia(
              bytes: jpeg,
              declaredContentType: 'image/jpeg',
              expectedExtension: 'jpg',
              expectedSha1: '0000000000000000000000000000000000000000',
            ),
      ];

      for (final verify in cases) {
        expect(verify, throwsA(isA<DownloadSecurityException>()));
      }
    });

    test('blocks active documents before a request is made', () {
      final uri = DownloadSecurityPolicy.requireTrustedMediaUri(
        'https://upload.wikimedia.org/wikipedia/commons/a/a1/Active.svg',
      );

      expect(
        () => DownloadSecurityPolicy.requireSafeDownloadExtension(uri),
        throwsA(
          isA<DownloadSecurityException>()
              .having((error) => error.code, 'code', 'active_content'),
        ),
      );
    });
  });

  test('neutralizes spreadsheet formulas before RFC 4180 escaping', () {
    expect(DownloadSecurityPolicy.safeCsvField('=WEBSERVICE("https://evil")'),
        startsWith('"\'='));
    expect(DownloadSecurityPolicy.safeCsvField('+cmd'), "'+cmd");
    expect(DownloadSecurityPolicy.safeCsvField('ordinary'), 'ordinary');
  });

  test('safe filenames cannot create paths or executable double extensions',
      () {
    expect(
      DownloadSecurityPolicy.safeFileName(
        '../File:payload.exe.jpg\u202e',
        extension: 'jpg',
      ),
      '_.._File_payload_blocked_suffix.jpg',
    );
    expect(
      () => DownloadSecurityPolicy.safeFileName('payload', extension: 'exe'),
      throwsA(isA<DownloadSecurityException>()),
    );
  });
}
