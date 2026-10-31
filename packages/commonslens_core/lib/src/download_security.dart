import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// A rejected download is a security decision, not a transient network error.
/// Callers should show [message] and must not open the rejected URL directly.
class DownloadSecurityException implements Exception {
  final String code;
  final String message;

  const DownloadSecurityException(this.code, this.message);

  @override
  String toString() => message;
}

/// The result of validating a complete media response.
class VerifiedMedia {
  final String extension;
  final String contentType;

  const VerifiedMedia({
    required this.extension,
    required this.contentType,
  });
}

/// Fail-closed policy for every media byte stream CommonsLens saves.
///
/// The browser never trusts a URL, extension, or Content-Type in isolation.
/// The source, declared type, expected metadata, byte signature, byte count,
/// and (when Wikimedia supplies it) SHA-1 must agree.
class DownloadSecurityPolicy {
  DownloadSecurityPolicy._();

  static const int maxFileBytes = 256 * 1024 * 1024;
  static const int maxZipBytes = 1024 * 1024 * 1024;

  static const Set<String> _activeExtensions = {'svg', 'pdf', 'djvu'};
  static const Set<String> _allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'tif',
    'tiff',
    'mp3',
    'wav',
    'ogg',
    'oga',
    'ogv',
    'webm',
    'mp4',
  };

  /// Accepts only HTTPS media objects from Wikimedia Commons' upload origin.
  /// Exact host matching prevents lookalike and attacker-controlled subdomains.
  static Uri requireTrustedMediaUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw const DownloadSecurityException(
        'invalid_url',
        'Download blocked: the media URL is invalid.',
      );
    }
    if (uri.scheme.toLowerCase() != 'https') {
      throw const DownloadSecurityException(
        'insecure_url',
        'Download blocked: media must use HTTPS.',
      );
    }
    if (uri.host.toLowerCase() != 'upload.wikimedia.org' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw const DownloadSecurityException(
        'untrusted_origin',
        'Download blocked: the media stream is not from Wikimedia Commons.',
      );
    }
    if (!uri.path.startsWith('/wikipedia/commons/')) {
      throw const DownloadSecurityException(
        'untrusted_path',
        'Download blocked: the URL is outside Wikimedia Commons media storage.',
      );
    }
    return uri;
  }

  /// Validates that the URL names a passive media format this client can
  /// authenticate by signature. Active documents require server-side CDR or
  /// malware scanning and are therefore deliberately refused here.
  static String requireSafeDownloadExtension(Uri uri) {
    final extension = extensionFromUri(uri);
    if (_activeExtensions.contains(extension)) {
      throw DownloadSecurityException(
        'active_content',
        'Download blocked: .$extension can contain active content. Export its '
            'verified Commons URL in a manifest instead.',
      );
    }
    if (!_allowedExtensions.contains(extension)) {
      throw DownloadSecurityException(
        'unsupported_type',
        'Download blocked: .$extension is not on the verified media allowlist.',
      );
    }
    return extension;
  }

  static String extensionFromUri(Uri uri) {
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toLowerCase()
        : '';
  }

  static VerifiedMedia verifyMedia({
    required Uint8List bytes,
    required String declaredContentType,
    required String expectedExtension,
    String? expectedMime,
    String? expectedSha1,
    int? expectedLength,
    int maxBytes = maxFileBytes,
  }) {
    if (bytes.isEmpty) {
      throw const DownloadSecurityException(
        'empty_file',
        'Download blocked: Wikimedia returned an empty file.',
      );
    }
    if (bytes.length > maxBytes) {
      throw DownloadSecurityException(
        'file_too_large',
        'Download blocked: the file exceeds the ${_mib(maxBytes)} MiB safety limit.',
      );
    }
    if (expectedLength != null &&
        expectedLength > 0 &&
        bytes.length != expectedLength) {
      throw const DownloadSecurityException(
        'length_mismatch',
        'Download blocked: the received byte count does not match Wikimedia metadata.',
      );
    }

    _rejectExecutableOrArchive(bytes);
    final detected = _detectType(bytes);
    if (detected == null) {
      throw const DownloadSecurityException(
        'unknown_signature',
        'Download blocked: the file signature is not a supported passive media type.',
      );
    }

    final expected = _typeForExtension(expectedExtension.toLowerCase());
    if (expected == null || expected != detected) {
      throw const DownloadSecurityException(
        'extension_mismatch',
        'Download blocked: the file bytes do not match the expected extension.',
      );
    }

    final declared = _normalizeMime(declaredContentType);
    if (declared.isEmpty || !_mimeMatchesType(declared, detected)) {
      throw const DownloadSecurityException(
        'mime_mismatch',
        'Download blocked: Wikimedia\'s Content-Type does not match the file bytes.',
      );
    }
    final metadataMime = _normalizeMime(expectedMime ?? '');
    if (metadataMime.isNotEmpty && !_mimeMatchesType(metadataMime, detected)) {
      throw const DownloadSecurityException(
        'metadata_mismatch',
        'Download blocked: the file does not match Wikimedia metadata.',
      );
    }

    final expectedHash = (expectedSha1 ?? '').trim().toLowerCase();
    if (expectedHash.isNotEmpty) {
      final digest = crypto.sha1.convert(bytes);
      final hex = digest.toString();
      final base36 = BigInt.parse(hex, radix: 16).toRadixString(36);
      final hashMatches = RegExp(r'^[0-9a-f]{40}$').hasMatch(expectedHash)
          ? expectedHash == hex
          : RegExp(r'^[0-9a-z]+$').hasMatch(expectedHash) &&
              expectedHash.replaceFirst(RegExp(r'^0+'), '') == base36;
      if (!hashMatches) {
        throw const DownloadSecurityException(
          'integrity_mismatch',
          'Download blocked: the SHA-1 integrity check failed.',
        );
      }
    }

    return VerifiedMedia(
      extension: _canonicalExtension(detected, expectedExtension),
      contentType: _canonicalMime(detected),
    );
  }

  /// Safe browser/export filename with no path components, control characters,
  /// hidden-file prefix, reserved Windows device name, or executable suffix.
  static String safeFileName(
    String requestedName, {
    required String extension,
    String fallback = 'download',
  }) {
    final safeExtension = extension.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
    if (safeExtension.isEmpty ||
        (!_allowedExtensions.contains(safeExtension) &&
            !_activeExtensions.contains(safeExtension) &&
            !const {'csv', 'json', 'py', 'zip'}.contains(safeExtension))) {
      throw const DownloadSecurityException(
        'unsafe_filename',
        'Download blocked: the output filename has an unsafe extension.',
      );
    }

    var base = requestedName
        .replaceFirst(RegExp(r'^File:', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f]'), '_')
        .replaceAll(
          RegExp(r'[\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]'),
          '',
        )
        .trim();
    final existingSuffix = RegExp(r'\.[a-z0-9]{1,8}$', caseSensitive: false);
    base = base.replaceFirst(existingSuffix, '').trim();
    base = base.replaceFirst(
      RegExp(
        r'\.(exe|com|bat|cmd|scr|pif|msi|msp|ps1|js|jse|vbs|vbe|wsf|wsh|jar|class|apk|app|dmg|sh|bash|zsh|html?|xhtml)$',
        caseSensitive: false,
      ),
      '_blocked_suffix',
    );
    base = base.replaceAll(RegExp(r'[. ]+$'), '');
    if (base.isEmpty) base = fallback;
    if (base.startsWith('.')) base = '_$base';
    if (RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$', caseSensitive: false)
        .hasMatch(base)) {
      base = '_$base';
    }
    if (base.length > 160) base = base.substring(0, 160).trimRight();
    return '$base.$safeExtension';
  }

  /// RFC 4180 escaping plus spreadsheet-formula neutralization. Quoting alone
  /// does not stop spreadsheet applications from evaluating =, +, -, or @.
  static String safeCsvField(String value) {
    var safe = value;
    final firstMeaningful = safe
        .trimLeft()
        .replaceFirst(
          RegExp(r'^[\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]+'),
          '',
        )
        .trimLeft();
    if (firstMeaningful.isNotEmpty &&
        (const {'=', '+', '-', '@', '\t', '\r', '\n'}
                .contains(firstMeaningful[0]) ||
            firstMeaningful.codeUnitAt(0) == 0xFEFF)) {
      safe = "'$safe";
    }
    if (safe.contains(',') ||
        safe.contains('"') ||
        safe.contains('\n') ||
        safe.contains('\r')) {
      return '"${safe.replaceAll('"', '""')}"';
    }
    return safe;
  }

  static void _rejectExecutableOrArchive(Uint8List bytes) {
    final signatures = <List<int>>[
      [0x4d, 0x5a], // Windows PE
      [0x7f, 0x45, 0x4c, 0x46], // ELF
      [0x00, 0x61, 0x73, 0x6d], // WebAssembly
      [0x23, 0x21], // script shebang
      [0x50, 0x4b, 0x03, 0x04], // ZIP/JAR/APK/Office archive
      [0x52, 0x61, 0x72, 0x21], // RAR
      [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c], // 7z
      [0x1f, 0x8b], // gzip
      [0xca, 0xfe, 0xba, 0xbe], // Java class / universal Mach-O
      [0xfe, 0xed, 0xfa, 0xce], // Mach-O
      [0xce, 0xfa, 0xed, 0xfe],
      [0xfe, 0xed, 0xfa, 0xcf],
      [0xcf, 0xfa, 0xed, 0xfe],
    ];
    if (signatures.any((signature) => _startsWith(bytes, signature))) {
      throw const DownloadSecurityException(
        'executable_or_archive',
        'Download blocked: executable or archive content was detected.',
      );
    }
  }

  static String? _detectType(Uint8List bytes) {
    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) return 'jpeg';
    if (_startsWith(
        bytes, const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
      return 'png';
    }
    if (_startsWithAscii(bytes, 'GIF87a') ||
        _startsWithAscii(bytes, 'GIF89a')) {
      return 'gif';
    }
    if (bytes.length >= 12 &&
        _asciiAt(bytes, 0, 'RIFF') &&
        _asciiAt(bytes, 8, 'WEBP')) {
      return 'webp';
    }
    if (_startsWith(bytes, const [0x49, 0x49, 0x2a, 0x00]) ||
        _startsWith(bytes, const [0x4d, 0x4d, 0x00, 0x2a])) {
      return 'tiff';
    }
    if (_startsWithAscii(bytes, 'ID3') ||
        (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0)) {
      return 'mp3';
    }
    if (bytes.length >= 12 &&
        _asciiAt(bytes, 0, 'RIFF') &&
        _asciiAt(bytes, 8, 'WAVE')) {
      return 'wav';
    }
    if (_startsWithAscii(bytes, 'OggS')) return 'ogg';
    if (_startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3])) return 'webm';
    if (bytes.length >= 12 && _asciiAt(bytes, 4, 'ftyp')) return 'mp4';
    return null;
  }

  static String? _typeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'jpeg';
      case 'tif':
      case 'tiff':
        return 'tiff';
      case 'oga':
      case 'ogv':
      case 'ogg':
        return 'ogg';
      case 'png':
      case 'gif':
      case 'webp':
      case 'mp3':
      case 'wav':
      case 'webm':
      case 'mp4':
        return extension;
      default:
        return null;
    }
  }

  static bool _mimeMatchesType(String mime, String type) {
    switch (type) {
      case 'jpeg':
        return mime == 'image/jpeg' || mime == 'image/jpg';
      case 'png':
        return mime == 'image/png';
      case 'gif':
        return mime == 'image/gif';
      case 'webp':
        return mime == 'image/webp';
      case 'tiff':
        return mime == 'image/tiff';
      case 'mp3':
        return mime == 'audio/mpeg' || mime == 'audio/mp3';
      case 'wav':
        return mime == 'audio/wav' || mime == 'audio/x-wav';
      case 'ogg':
        return mime == 'audio/ogg' ||
            mime == 'video/ogg' ||
            mime == 'application/ogg';
      case 'webm':
        return mime == 'video/webm' || mime == 'audio/webm';
      case 'mp4':
        return mime == 'video/mp4' ||
            mime == 'audio/mp4' ||
            mime == 'application/mp4';
      default:
        return false;
    }
  }

  static String _canonicalExtension(String type, String expectedExtension) {
    if (type == 'jpeg') return 'jpg';
    if (type == 'tiff') return 'tiff';
    if (type == 'ogg' &&
        const {'oga', 'ogv', 'ogg'}.contains(expectedExtension)) {
      return expectedExtension;
    }
    return type;
  }

  static String _canonicalMime(String type) {
    switch (type) {
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
      case 'gif':
      case 'webp':
      case 'tiff':
        return 'image/$type';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'application/ogg';
      case 'webm':
        return 'video/webm';
      case 'mp4':
        return 'video/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  static String _normalizeMime(String value) =>
      value.split(';').first.trim().toLowerCase();

  static bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  static bool _startsWithAscii(Uint8List bytes, String text) =>
      _asciiAt(bytes, 0, text);

  static bool _asciiAt(Uint8List bytes, int offset, String text) {
    if (bytes.length < offset + text.length) return false;
    for (var i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _mib(int bytes) => bytes ~/ (1024 * 1024);
}
