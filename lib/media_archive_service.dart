// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'download_queue.dart';
import 'wikimedia_download_client.dart';

class ArchiveProgress {
  final int completed;
  final int total;
  final String title;
  final String phase;
  final int part;

  const ArchiveProgress({
    required this.completed,
    required this.total,
    required this.title,
    this.phase = 'verifying',
    this.part = 1,
  });
}

class ArchiveSkip {
  final DownloadQueueItem item;
  final String reason;

  const ArchiveSkip(this.item, this.reason);
}

class MediaArchiveReport {
  final int included;
  final List<ArchiveSkip> skipped;
  final bool cancelled;
  final int parts;

  const MediaArchiveReport({
    required this.included,
    required this.skipped,
    this.cancelled = false,
    this.parts = 0,
  });

  bool get hasOutput => included > 0;
}

/// Builds one or more bounded local ZIPs from independently verified Wikimedia
/// byte streams. A large selection is split by entry count and verified media
/// bytes so the browser never has to retain the entire selection in one job.
///
/// The ZIP writer deliberately uses the store method rather than compressing
/// content in the browser. Most media is already compressed, and keeping the
/// writer simple avoids introducing a second content transformation into the
/// security boundary. Only [DownloadPayload] values returned by the verified
/// download client enter the archive.
class MediaArchiveService {
  static Future<MediaArchiveReport> download(
    List<DownloadQueueItem> queue, {
    String fileName = 'commonslens_media',
    void Function(ArchiveProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (queue.isEmpty) {
      return const MediaArchiveReport(included: 0, skipped: []);
    }

    final unique = <String, DownloadQueueItem>{
      for (final item in queue) item.id: item,
    }.values.toList(growable: false);
    final total = unique.length;
    final skipped = <ArchiveSkip>[];
    var batch = _ArchiveBatch();
    var completed = 0;
    var included = 0;
    var partNumber = 1;
    var parts = 0;
    final client = WikimediaDownloadClient();

    try {
      for (final queued in unique) {
        if (cancelled?.call() == true) break;
        final item = queued.item;
        onProgress?.call(ArchiveProgress(
          completed: completed,
          total: total,
          title: item.title,
          phase: 'downloading and verifying',
          part: partNumber,
        ));

        DownloadPayload? payload;
        String? failure;
        try {
          payload = await client.fetchMedia(
            item.url,
            allowComplex: true,
            revalidateTitle: item.title,
            maxBytes: DownloadSecurityPolicy.maxFileBytes,
          );
          if (payload == null) {
            failure = 'Wikimedia did not return a verifiable media response.';
          }
        } on DownloadSecurityException catch (error) {
          failure = error.message;
        } catch (_) {
          failure = 'The file could not be verified before archiving.';
        }

        if (payload == null) {
          final reason = failure ?? 'Verification failed.';
          skipped.add(ArchiveSkip(queued, reason));
          batch.rows.add(_ManifestRow.skipped(queued, reason));
          completed++;
          continue;
        }

        if (!batch.canFit(payload.bytes.length)) {
          if (batch.hasMedia) {
            await _emitBatch(
              batch,
              fileName: fileName,
              part: partNumber,
              completed: completed,
              total: total,
              onProgress: onProgress,
              cancelled: cancelled,
            );
            parts++;
            partNumber++;
            batch = _ArchiveBatch();
            // Give the browser a turn to start the previous download and make
            // the old batch eligible for garbage collection before fetching
            // the next large payload.
            await Future<void>.delayed(Duration.zero);
          }

          if (!batch.canFit(payload.bytes.length)) {
            final payloadMiB =
                DownloadSecurityPolicy.maxZipPayloadBytes ~/ (1024 * 1024);
            final reason =
                'Skipped: this file is larger than the $payloadMiB MiB media budget for one ZIP part.';
            skipped.add(ArchiveSkip(queued, reason));
            batch.rows.add(_ManifestRow.skipped(queued, reason));
            completed++;
            continue;
          }
        }

        final entryName = batch.entryName(item.title, payload.extension);
        onProgress?.call(ArchiveProgress(
          completed: completed,
          total: total,
          title: item.title,
          phase: 'packing',
          part: partNumber,
        ));
        await batch.add(
          entryName,
          queued,
          payload,
          cancelled: cancelled,
        );
        included++;
        completed++;
      }

      // Cancellation must never turn already-verified entries into a partial
      // archive. The caller clears the queue after this report is returned.
      if (cancelled?.call() == true) {
        return MediaArchiveReport(
          included: 0,
          skipped: skipped,
          cancelled: true,
          parts: parts,
        );
      }

      if (batch.hasMedia) {
        await _emitBatch(
          batch,
          fileName: fileName,
          part: partNumber,
          completed: completed,
          total: total,
          onProgress: onProgress,
          cancelled: cancelled,
        );
        parts++;
      }
      return MediaArchiveReport(
        included: included,
        skipped: skipped,
        parts: parts,
      );
    } finally {
      client.close();
    }
  }

  static Future<void> _emitBatch(
    _ArchiveBatch batch, {
    required String fileName,
    required int part,
    required int completed,
    required int total,
    void Function(ArchiveProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) {
      throw const DownloadSecurityException(
        'cancelled',
        'Download cancelled before the ZIP was finalized.',
      );
    }

    final manifest = _buildManifest(batch.rows);
    await batch.writer.add(
      'commonslens_verification_manifest.csv',
      Uint8List.fromList(utf8.encode(manifest)),
      cancelled: cancelled,
    );
    await batch.writer.add(
      'README.txt',
      Uint8List.fromList(utf8.encode(_buildReadme(batch.rows))),
      cancelled: cancelled,
    );

    onProgress?.call(ArchiveProgress(
      completed: completed,
      total: total,
      title: '',
      phase: 'finalizing ZIP part $part',
      part: part,
    ));
    final archiveParts = await batch.writer.finish(cancelled: cancelled);
    if (cancelled?.call() == true) {
      throw const DownloadSecurityException(
        'cancelled',
        'Download cancelled before the ZIP was downloaded.',
      );
    }

    final partSuffix = part.toString().padLeft(3, '0');
    final safeName = DownloadSecurityPolicy.safeFileName(
      '$fileName.part-$partSuffix',
      extension: 'zip',
      fallback: 'commonslens_media.part-$partSuffix',
    );
    final blob = html.Blob(archiveParts, 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', safeName)
      ..click();
    // Let the browser observe the click before releasing the object URL. The
    // Blob and all entry references then become eligible for collection when
    // this batch returns and the caller rotates to the next one.
    await Future<void>.delayed(Duration.zero);
    html.Url.revokeObjectUrl(url);
  }

  static String _uniqueName(String requested, Set<String> existing) {
    if (!existing.contains(requested)) return requested;
    final dot = requested.lastIndexOf('.');
    final stem = dot > 0 ? requested.substring(0, dot) : requested;
    final extension = dot > 0 ? requested.substring(dot) : '';
    var index = 2;
    var candidate = '$stem ($index)$extension';
    while (existing.contains(candidate)) {
      index++;
      candidate = '$stem ($index)$extension';
    }
    return candidate;
  }

  static String _buildManifest(List<_ManifestRow> rows) {
    final buffer = StringBuffer();
    buffer.writeln(
        'WARNING: CommonsLens verified these files, but your safety is your responsibility.');
    buffer.writeln();
    buffer.writeln(
        'This manifest records the checks performed before each entry was added to this ZIP. Verification is not antivirus scanning, rights clearance, or a guarantee that a file is harmless to open.');
    buffer.writeln();
    const columns = [
      'status',
      'zipEntry',
      'title',
      'sourcePage',
      'mediaUrl',
      'mime',
      'expectedMime',
      'detectedType',
      'verificationLevel',
      'checksPerformed',
      'warnings',
      'expectedBytes',
      'observedBytes',
      'expectedSha1',
      'observedSha1',
      'license',
      'licenseUrl',
      'attribution',
      'selectedFrom',
      'failureReason',
    ];
    buffer.writeln(columns.map(DownloadSecurityPolicy.safeCsvField).join(','));
    for (final row in rows) {
      buffer.writeln(
          row.values.map(DownloadSecurityPolicy.safeCsvField).join(','));
    }
    return buffer.toString();
  }

  static String _buildReadme(List<_ManifestRow> rows) {
    final complexCount = rows
        .where((row) => row.verified && row.verificationLevel == 'complex')
        .length;
    return [
      'WARNING: VERIFIED FILES — YOUR SAFETY IS YOUR RESPONSIBILITY.',
      '',
      'CommonsLens checked each included file before placing it in this ZIP.',
      'Large selections may be split across multiple bounded ZIP parts; each',
      'part carries its own verification manifest and safety warning.',
      'Those checks establish file origin, declared type, byte structure, and',
      'available Wikimedia integrity metadata. They are not antivirus scanning',
      'and do not guarantee that a file is harmless to open.',
      if (complexCount > 0)
        '$complexCount complex document/vector/3D file(s) are included as opaque bytes. Be especially careful when opening them.',
      '',
      'Open the Commons source page for the authoritative licence and attribution information.',
    ].join('\n');
  }
}

class _ManifestRow {
  final bool verified;
  final String entry;
  final DownloadQueueItem queued;
  final DownloadPayload? payload;
  final String? failure;

  const _ManifestRow._({
    required this.verified,
    required this.entry,
    required this.queued,
    required this.payload,
    required this.failure,
  });

  factory _ManifestRow.verified(
      DownloadQueueItem queued, DownloadPayload payload, String entry) {
    return _ManifestRow._(
      verified: true,
      entry: entry,
      queued: queued,
      payload: payload,
      failure: null,
    );
  }

  factory _ManifestRow.skipped(DownloadQueueItem queued, String reason) {
    return _ManifestRow._(
      verified: false,
      entry: '',
      queued: queued,
      payload: null,
      failure: reason,
    );
  }

  String get verificationLevel {
    if (!verified) return 'not-verified';
    return payload?.riskLevel == DownloadRiskLevel.complex
        ? 'complex'
        : 'passive';
  }

  String get warnings {
    if (!verified) return '';
    final warnings = <String>[];
    if (payload!.riskLevel == DownloadRiskLevel.complex) {
      warnings.add('Not malware-scanned; opening it is your responsibility');
    }
    if (queued.item.sha1.isEmpty) {
      warnings.add('Wikimedia SHA-1 was unavailable');
    }
    if (queued.item.fileSizeBytes <= 0) {
      warnings.add('Wikimedia byte-length metadata was unavailable');
    }
    return warnings.join(' | ');
  }

  List<String> get values {
    final item = queued.item;
    final payloadValue = payload;
    final expectedLength = payloadValue?.expectedLength;
    return [
      verified ? 'verified' : 'skipped',
      entry,
      item.title,
      item.commonsUrl,
      payloadValue?.verifiedUrl ?? item.url,
      payloadValue?.contentType ?? item.mime,
      payloadValue?.expectedMime ?? (verified ? item.mime : ''),
      payloadValue?.detectedType ?? '',
      verificationLevel,
      payloadValue?.verificationChecks.join(' | ') ?? '',
      warnings,
      expectedLength == null
          ? (verified && item.fileSizeBytes > 0 ? '${item.fileSizeBytes}' : '')
          : '$expectedLength',
      payloadValue == null ? '' : '${payloadValue.bytes.length}',
      payloadValue?.expectedSha1 ?? (verified ? item.sha1 : ''),
      payloadValue?.sha1 ?? '',
      item.licenseShortName,
      item.licenseUrl,
      item.artistHtml,
      queued.sources.join(' | '),
      failure ?? '',
    ];
  }
}

class _ArchiveBatch {
  final _ZipWriter writer = _ZipWriter();
  final List<_ManifestRow> rows = <_ManifestRow>[];
  final Set<String> names = <String>{};
  var mediaCount = 0;
  var mediaBytes = 0;

  bool get hasMedia => mediaCount > 0;

  bool canFit(int byteLength) {
    return mediaCount < DownloadSecurityPolicy.maxZipEntries &&
        byteLength <= DownloadSecurityPolicy.maxZipPayloadBytes - mediaBytes;
  }

  String entryName(String title, String extension) {
    final baseName = DownloadSecurityPolicy.safeFileName(
      title,
      extension: extension,
    );
    final entry = MediaArchiveService._uniqueName(baseName, names);
    names.add(entry);
    return entry;
  }

  Future<void> add(
    String entryName,
    DownloadQueueItem queued,
    DownloadPayload payload, {
    bool Function()? cancelled,
  }) async {
    await writer.add(entryName, payload.bytes, cancelled: cancelled);
    rows.add(_ManifestRow.verified(queued, payload, entryName));
    mediaCount++;
    mediaBytes += payload.bytes.length;
  }
}

class _ZipWriter {
  final List<_ZipEntry> _entries = [];

  bool get isEmpty => _entries.isEmpty;

  Future<void> add(
    String name,
    Uint8List bytes, {
    bool Function()? cancelled,
  }) async {
    final crc = await _crc32Cooperatively(bytes, cancelled: cancelled);
    _entries.add(_ZipEntry(name, bytes, crc));
  }

  /// Returns ZIP parts instead of concatenating payloads into one more giant
  /// byte array. Blob accepts parts directly, so the browser can assemble the
  /// download without a Dart-side full-archive copy.
  Future<List<Uint8List>> finish({bool Function()? cancelled}) async {
    final parts = <Uint8List>[];
    final central = BytesBuilder(copy: false);
    var offset = 0;
    for (final entry in _entries) {
      if (cancelled?.call() == true) {
        throw const DownloadSecurityException(
          'cancelled',
          'Download cancelled before the ZIP was finalized.',
        );
      }
      final name = Uint8List.fromList(utf8.encode(entry.name));
      final localHeader = BytesBuilder(copy: false);
      _u32(localHeader, 0x04034b50);
      _u16(localHeader, 20);
      _u16(localHeader, 0x0800);
      _u16(localHeader, 0);
      _u16(localHeader, 0);
      _u16(localHeader, 0);
      _u32(localHeader, entry.crc);
      _u32(localHeader, entry.bytes.length);
      _u32(localHeader, entry.bytes.length);
      _u16(localHeader, name.length);
      _u16(localHeader, 0);
      localHeader.add(name);
      final localHeaderBytes = localHeader.takeBytes();
      parts.add(localHeaderBytes);
      parts.add(entry.bytes);

      _u32(central, 0x02014b50);
      _u16(central, 20);
      _u16(central, 20);
      _u16(central, 0x0800);
      _u16(central, 0);
      _u16(central, 0);
      _u16(central, 0);
      _u32(central, entry.crc);
      _u32(central, entry.bytes.length);
      _u32(central, entry.bytes.length);
      _u16(central, name.length);
      _u16(central, 0);
      _u16(central, 0);
      _u16(central, 0);
      _u16(central, 0);
      _u32(central, 0);
      _u32(central, offset);
      central.add(name);
      offset += localHeaderBytes.length + entry.bytes.length;
      await Future<void>.delayed(Duration.zero);
    }

    final centralBytes = central.takeBytes();
    parts.add(centralBytes);
    final end = BytesBuilder(copy: false);
    _u32(end, 0x06054b50);
    _u16(end, 0);
    _u16(end, 0);
    _u16(end, _entries.length);
    _u16(end, _entries.length);
    _u32(end, centralBytes.length);
    _u32(end, offset);
    _u16(end, 0);
    parts.add(end.takeBytes());
    return parts;
  }

  static void _u16(BytesBuilder output, int value) {
    output.add(Uint8List.fromList([value & 0xff, (value >> 8) & 0xff]));
  }

  static void _u32(BytesBuilder output, int value) {
    output.add(Uint8List.fromList([
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ]));
  }
}

class _ZipEntry {
  final String name;
  final Uint8List bytes;
  final int crc;

  const _ZipEntry(this.name, this.bytes, this.crc);
}

Future<int> _crc32Cooperatively(
  Uint8List bytes, {
  bool Function()? cancelled,
}) async {
  var crc = 0xffffffff;
  const chunkBytes = 256 * 1024;
  for (var offset = 0; offset < bytes.length; offset += chunkBytes) {
    if (cancelled?.call() == true) {
      throw const DownloadSecurityException(
        'cancelled',
        'Download cancelled while the ZIP was being prepared.',
      );
    }
    final end =
        offset + chunkBytes > bytes.length ? bytes.length : offset + chunkBytes;
    for (var index = offset; index < end; index++) {
      crc = _crc32Table[(crc ^ bytes[index]) & 0xff] ^ (crc >> 8);
    }
    if (end < bytes.length) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

final List<int> _crc32Table = List<int>.generate(256, (index) {
  var value = index;
  for (var bit = 0; bit < 8; bit++) {
    value = (value & 1) == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1;
  }
  return value;
}, growable: false);
