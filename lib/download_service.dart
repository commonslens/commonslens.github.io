// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';
import 'package:archive/archive.dart';
import 'search_models.dart';
import 'wikimedia_download_client.dart';

/// Screen Wake Lock — prevents the screen from dimming/locking while a
/// download is in progress and the tab stays open and visible.
///
/// Honest limits: per MDN and every current browser vendor's own docs, the
/// lock is released automatically the instant the tab is backgrounded,
/// minimized, or loses focus — and it has no effect on the OS suspending
/// the machine outright (closing a laptop lid, manual sleep). This is NOT
/// a "survive running in the background overnight" fix. It only helps the
/// case where someone keeps the tab open and visible but would otherwise
/// have the screen auto-dim/lock partway through a long download.
///
/// Implemented via dart:js_util rather than a typed dart:html binding,
/// since Wake Lock is a newer API (Baseline "newly available" as of March
/// 2025) that older Dart SDK bindings may not expose yet.
class _WakeLock {
  static int _activeCount = 0;
  static Object? _sentinel;

  /// Reference-counted so multiple concurrent downloads can each acquire
  /// and release independently without one finishing early releasing the
  /// lock out from under the others still running.
  static Future<void> acquire() async {
    _activeCount++;
    if (_sentinel != null) return; // already held

    try {
      final nav = html.window.navigator;
      if (!js_util.hasProperty(nav, 'wakeLock')) return; // unsupported browser
      final wakeLock = js_util.getProperty(nav, 'wakeLock');
      final sentinel = await js_util.promiseToFuture<Object?>(
        js_util.callMethod(wakeLock, 'request', ['screen']),
      );
      _sentinel = sentinel;
    } catch (_) {
      // Denied (low battery, power-save mode, page not visible, etc.) or
      // unsupported — downloads still work fine without it.
    }
  }

  static Future<void> release() async {
    _activeCount--;
    if (_activeCount > 0) return; // other downloads still active
    _activeCount = 0;

    final sentinel = _sentinel;
    if (sentinel == null) return;
    _sentinel = null;
    try {
      await js_util
          .promiseToFuture(js_util.callMethod(sentinel, 'release', []));
    } catch (_) {
      // Already released by the browser (e.g. tab was backgrounded) — fine.
    }
  }
}

/// Passed into [DownloadService.downloadBulkZip] to allow stopping it
/// mid-run. Calling [cancel] does two things: flips [isCancelled] (checked
/// between files/chunks so nothing new gets started) AND closes the shared
/// headless download client used by every in-flight fetch. Closing it aborts
/// its owned HTTP client while the cancellation flag prevents new work.
class DownloadCancelToken {
  bool _cancelled = false;
  WikimediaDownloadClient? _client;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close();
  }
}

String _csvField(String value) => DownloadSecurityPolicy.safeCsvField(value);

class DownloadService {
  static final WikimediaDownloadClient _singleDownloadClient =
      WikimediaDownloadClient();

  /// Downloads one fully verified media object. A non-null return value is a
  /// user-facing failure reason; rejected URLs are never opened as a fallback.
  static Future<String?> downloadSingleFile(
    SearchItem item, {
    String? url,
  }) async {
    final downloadUrl = url ?? item.url;
    final isOriginal = downloadUrl == item.url;
    try {
      final payload = await _singleDownloadClient.fetchMedia(
        downloadUrl,
        timeout: const Duration(seconds: 30),
        expectedMime: isOriginal ? item.mime : null,
        expectedSha1: isOriginal ? item.sha1 : null,
        expectedLength: isOriginal ? item.fileSizeBytes : null,
      );

      if (payload == null) {
        return 'Download failed: Wikimedia did not return a valid media response.';
      }

      final fileName = DownloadSecurityPolicy.safeFileName(
        item.title,
        extension: payload.extension,
      );
      final blob = html.Blob([payload.bytes], payload.contentType);
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);

      html.AnchorElement(href: objectUrl)
        ..setAttribute('download', fileName)
        ..click();

      html.Url.revokeObjectUrl(objectUrl);
      return null;
    } on DownloadSecurityException catch (error) {
      debugPrint('Download blocked: ${error.code}');
      return error.message;
    } catch (error) {
      debugPrint('Download failed: $error');
      return 'Download failed before the file could be verified.';
    }
  }

  /// A file's data-export filename — sanitized title + lowercase
  /// extension. Single source of truth for this so the bulk-zip's
  /// in-archive filenames, its data.csv `filename` column, and a
  /// standalone CSV export (which has no zip entries to derive it from)
  /// always agree with each other.
  static String _sanitizedFileName(
    SearchItem item, {
    String? extension,
  }) {
    return DownloadSecurityPolicy.safeFileName(
      item.title,
      extension: extension ?? item.extension,
    );
  }

  static String _safeExportName(
    String requested,
    String extension, {
    required String fallback,
  }) =>
      DownloadSecurityPolicy.safeFileName(
        requested,
        extension: extension,
        fallback: fallback,
      );

  static void _validateManifestItem(SearchItem item) {
    DownloadSecurityPolicy.requireTrustedMediaUri(item.url);
    if (item.thumb.isNotEmpty) {
      DownloadSecurityPolicy.requireTrustedMediaUri(item.thumb);
    }
  }

  static void _validateRecordMediaUrls(List<Map<String, dynamic>> records) {
    const mediaUrlKeys = {
      'url',
      'thumb',
      'originalurl',
      'thumbnailurl',
      'mediaurl',
    };
    for (final record in records) {
      for (final entry in record.entries) {
        if (!mediaUrlKeys.contains(entry.key.toLowerCase())) continue;
        final value = entry.value;
        if (value == null || value == '') continue;
        if (value is! String) {
          throw const DownloadSecurityException(
            'invalid_manifest_url',
            'Export blocked: a media URL field is not valid text.',
          );
        }
        DownloadSecurityPolicy.requireTrustedMediaUri(value);
      }
    }
  }

  static String _plainText(String html) =>
      html.replaceAll(RegExp(r'<[^>]*>'), '').trim();

  /// Builds the manifest CSV — the exact same column set embedded as
  /// data.csv inside every bulk-zip download (see [downloadBulkZip]),
  /// extracted here so a standalone CSV export (no zip, no file bytes
  /// fetched — just metadata already on each [SearchItem]) uses one
  /// schema instead of a second hand-maintained column list that could
  /// drift out of sync with it.
  static String buildManifestCsv(List<SearchItem> items) {
    final csvBuffer = StringBuffer()
      ..writeln([
        'filename',
        'title',
        'source_url',
        'thumb_url',
        'commons_url',
        'description_url',
        'snippet',
        'mime',
        'is_svg',
        'width',
        'height',
        'file_size_bytes',
        'sha1',
        'author',
        'uploader',
        'license',
        'license_url',
        'usage_terms',
        'copyright_status',
        'attribution_required',
        'permission',
        'restrictions',
        'credit',
        'date_original',
        'upload_datetime',
        'revision_timestamp',
        'object_name',
        'image_description',
        'categories',
        'assessments',
        'gps_latitude',
        'gps_longitude',
      ].join(','));

    for (final item in items) {
      _validateManifestItem(item);
      csvBuffer.writeln([
        _csvField(_sanitizedFileName(item)),
        _csvField(item.title),
        _csvField(item.url),
        _csvField(item.thumb),
        _csvField(item.commonsUrl),
        _csvField(item.descriptionUrl ?? ''),
        _csvField(item.snippet),
        _csvField(item.mime),
        item.isSvg.toString(),
        item.width.toString(),
        item.height.toString(),
        item.fileSizeBytes.toString(),
        _csvField(item.sha1),
        _csvField(_plainText(item.artistHtml)),
        _csvField(item.uploader),
        _csvField(item.licenseShortName),
        _csvField(item.licenseUrl),
        _csvField(item.usageTerms),
        _csvField(item.copyrighted),
        _csvField(item.attributionRequired),
        _csvField(_plainText(item.permissionHtml)),
        _csvField(item.restrictions),
        _csvField(_plainText(item.creditHtml)),
        _csvField(item.dateTimeOriginal),
        _csvField(item.uploadDateTime),
        _csvField(item.timestamp ?? ''),
        _csvField(item.objectName),
        _csvField(_plainText(item.imageDescriptionHtml)),
        _csvField(item.categories),
        _csvField(item.assessments),
        _csvField(item.gpsLatitude),
        _csvField(item.gpsLongitude),
      ].join(','));
    }

    return csvBuffer.toString();
  }

  /// Standalone CSV export — no zip, no file bytes fetched, just the
  /// manifest. Used by dataset exports and equally usable
  /// anywhere a plain CSV of results is wanted without a bulk download.
  static Future<void> downloadCsv(
      List<SearchItem> items, String fileName) async {
    final csvBytes = utf8.encode(buildManifestCsv(items));
    final blob = html.Blob([csvBytes], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final name = _safeExportName(fileName, 'csv', fallback: 'commons_export');

    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  /// Standalone JSON export — every field [SearchItem.toJson] carries,
  /// same "complete record, not a curated subset" philosophy as
  /// [buildManifestCsv]. Used by the pipeline's JSON Export sink.
  static Future<void> downloadJson(
      List<SearchItem> items, String fileName) async {
    for (final item in items) {
      _validateManifestItem(item);
    }
    await downloadJsonRecords(
        items.map((item) => item.toJson()).toList(), fileName);
  }

  static Future<void> downloadJsonRecords(
      List<Map<String, dynamic>> records, String fileName) async {
    _validateRecordMediaUrls(records);
    final jsonStr = const JsonEncoder.withIndent('  ').convert(records);
    final blob = html.Blob([utf8.encode(jsonStr)], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final name = _safeExportName(fileName, 'json', fallback: 'commons_export');

    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static Future<void> downloadCsvRecords(
      List<Map<String, dynamic>> records, String fileName) async {
    _validateRecordMediaUrls(records);
    final columns = <String>[];
    for (final record in records) {
      for (final key in record.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }
    // Keep CSV construction chunked. The pipeline still owns its metadata
    // rows, but this avoids creating one additional giant Dart String before
    // handing the manifest to the browser's Blob implementation.
    final chunks = <Object>["${columns.map(_csvField).join(',')}\n"];
    var buffer = StringBuffer();
    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      buffer.writeln(columns.map((column) {
        final value = record[column];
        final text = value is Map || value is List
            ? jsonEncode(value)
            : value?.toString() ?? '';
        return _csvField(text);
      }).join(','));
      if ((index + 1) % 1000 == 0) {
        chunks.add(buffer.toString());
        buffer = StringBuffer();
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    final blob = html.Blob(chunks, 'text/csv;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final name = _safeExportName(fileName, 'csv', fallback: 'commons_export');
    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Downloads a dependency-free, sequential downloader for a CommonsLens
  /// manifest. Users may ignore it and consume the CSV with their own tools;
  /// it is provided so the URL-manifest workflow is useful out of the box.
  static void downloadManifestPythonHelper(String csvFileName) {
    final safeManifestName =
        _safeExportName(csvFileName, 'csv', fallback: 'commonslens_manifest');
    final defaultManifest = jsonEncode(safeManifestName);
    final script = '''#!/usr/bin/env python3
"""Strictly verify and download media from a CommonsLens manifest."""

import argparse
import csv
import hashlib
import pathlib
import re
import time
import urllib.request
from urllib.parse import unquote, urlparse

DEFAULT_MANIFEST = $defaultManifest
USER_AGENT = "CommonsLensManifestDownloader/1.0 (personal dataset download)"
MAX_BYTES = 256 * 1024 * 1024
TRUSTED_HOST = "upload.wikimedia.org"
ALLOWED_EXTENSIONS = {
    "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff",
    "mp3", "wav", "ogg", "oga", "ogv", "webm", "mp4",
}
ACTIVE_EXTENSIONS = {"svg", "pdf", "djvu"}


def require_trusted_url(value):
    parsed = urlparse(value)
    if parsed.scheme.lower() != "https":
        raise ValueError("media URL is not HTTPS")
    if parsed.hostname != TRUSTED_HOST or parsed.username or parsed.password:
        raise ValueError("media URL is not from Wikimedia Commons")
    try:
        if parsed.port not in (None, 443):
            raise ValueError("media URL uses an untrusted port")
    except ValueError as error:
        raise ValueError("media URL has an invalid port") from error
    if not parsed.path.startswith("/wikipedia/commons/"):
        raise ValueError("media URL is outside Commons media storage")
    extension = pathlib.PurePosixPath(unquote(parsed.path)).suffix.lower()[1:]
    if extension in ACTIVE_EXTENSIONS:
        raise ValueError(
            f".{extension} is active content; use the manifest URL manually"
        )
    if extension not in ALLOWED_EXTENSIONS:
        raise ValueError(f".{extension or 'unknown'} is not on the allowlist")
    return extension


class StrictRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        require_trusted_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


OPENER = urllib.request.build_opener(StrictRedirectHandler())


def safe_name(value):
    value = unquote(value).replace("File:", "")
    value = re.sub(r'[\\\\/:*?"<>|\\x00-\\x1f\\x7f]+', "_", value)
    value = re.sub(r'[\\u200b-\\u200f\\u202a-\\u202e\\u2060-\\u206f\\ufeff]', "", value)
    value = re.sub(r"\\.[A-Za-z0-9]{1,8}\$", "", value).strip(" .")
    value = re.sub(
        r"\\.(exe|com|bat|cmd|scr|pif|msi|msp|ps1|js|jse|vbs|vbe|wsf|wsh|jar|class|apk|app|dmg|sh|bash|zsh|html?|xhtml)\$",
        "_blocked_suffix",
        value,
        flags=re.IGNORECASE,
    )
    return value[:160] or "download"


def sniff_type(data):
    blocked = (
        b"MZ", b"\\x7fELF", b"\\x00asm", b"#!", b"PK\\x03\\x04",
        b"Rar!", b"7z\\xbc\\xaf\\x27\\x1c", b"\\x1f\\x8b",
        b"\\xca\\xfe\\xba\\xbe",
    )
    if data.startswith(blocked):
        raise ValueError("executable or archive signature detected")
    if data.startswith(b"\\xff\\xd8\\xff"):
        return "jpeg"
    if data.startswith(b"\\x89PNG\\r\\n\\x1a\\n"):
        return "png"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "gif"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    if data.startswith((b"II*\\x00", b"MM\\x00*")):
        return "tiff"
    if data.startswith(b"ID3") or (
        len(data) >= 2 and data[0] == 0xff and data[1] & 0xe0 == 0xe0
    ):
        return "mp3"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return "wav"
    if data.startswith(b"OggS"):
        return "ogg"
    if data.startswith(b"\\x1aE\\xdf\\xa3"):
        return "webm"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "mp4"
    raise ValueError("unknown or unsupported file signature")


def expected_type(extension):
    if extension in ("jpg", "jpeg"):
        return "jpeg"
    if extension in ("tif", "tiff"):
        return "tiff"
    if extension in ("ogg", "oga", "ogv"):
        return "ogg"
    return extension


def mime_matches(mime, media_type):
    accepted = {
        "jpeg": {"image/jpeg", "image/jpg"},
        "png": {"image/png"},
        "gif": {"image/gif"},
        "webp": {"image/webp"},
        "tiff": {"image/tiff"},
        "mp3": {"audio/mpeg", "audio/mp3"},
        "wav": {"audio/wav", "audio/x-wav"},
        "ogg": {"audio/ogg", "video/ogg", "application/ogg"},
        "webm": {"video/webm", "audio/webm"},
        "mp4": {"video/mp4", "audio/mp4", "application/mp4"},
    }
    return mime.split(";", 1)[0].strip().lower() in accepted[media_type]


def base36(number):
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    if number == 0:
        return "0"
    output = ""
    while number:
        number, remainder = divmod(number, 36)
        output = alphabet[remainder] + output
    return output


def verify_hash(data, expected):
    expected = expected.strip().lower()
    if not expected:
        return
    digest = hashlib.sha1(data).hexdigest()
    actual = (digest if re.fullmatch(r"[0-9a-f]{40}", expected)
              else base36(int(digest, 16)))
    if expected.lstrip("0") != actual.lstrip("0"):
        raise ValueError("SHA-1 integrity check failed")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", nargs="?", default=DEFAULT_MANIFEST)
    parser.add_argument("--output", default="commonslens_dataset")
    parser.add_argument("--delay", type=float, default=0.25)
    args = parser.parse_args()

    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)

    with open(args.manifest, newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        for number, row in enumerate(rows, start=1):
            original = row.get("originalUrl") or row.get("url")
            url = original or row.get("thumbnailUrl") or row.get("thumb")
            if not url:
                print(f"[{number}] skipped: no media URL")
                continue

            try:
                extension = require_trusted_url(url)
                request = urllib.request.Request(
                    url, headers={"User-Agent": USER_AGENT}
                )
                with OPENER.open(request, timeout=60) as response:
                    if response.status != 200:
                        raise ValueError(f"unexpected HTTP status {response.status}")
                    final_extension = require_trusted_url(response.geturl())
                    if final_extension != extension:
                        raise ValueError("redirect changed the expected file type")
                    content_encoding = response.headers.get(
                        "Content-Encoding", "identity"
                    ).lower()
                    if content_encoding not in ("", "identity"):
                        raise ValueError("encoded responses are not accepted")
                    declared = response.headers.get("Content-Length")
                    if declared and int(declared) > MAX_BYTES:
                        raise ValueError("file exceeds the 256 MiB safety limit")
                    content_type = response.headers.get_content_type()
                    data = response.read(MAX_BYTES + 1)

                if len(data) > MAX_BYTES:
                    raise ValueError("file exceeds the 256 MiB safety limit")
                if declared and int(declared) != len(data):
                    raise ValueError("received byte count does not match headers")
                media_type = sniff_type(data)
                if media_type != expected_type(extension):
                    raise ValueError("file bytes do not match the URL extension")
                if not mime_matches(content_type, media_type):
                    raise ValueError("Content-Type does not match the file bytes")

                if original:
                    expected_size = (row.get("fileSizeBytes") or
                                     row.get("file_size_bytes"))
                    if expected_size and int(expected_size) != len(data):
                        raise ValueError("byte count does not match manifest metadata")
                    verify_hash(data, row.get("sha1") or "")

                fallback = pathlib.PurePosixPath(urlparse(url).path).name
                base = safe_name(row.get("title") or fallback)
                target = output / f"{base}.{extension}"
                if target.exists() or target.is_symlink():
                    print(f"[{number}] exists: {target.name}")
                    continue
                with target.open("xb") as output_file:
                    output_file.write(data)
                print(f"[{number}] downloaded: {target.name}")
            except Exception as error:
                print(f"[{number}] blocked/failed: {error}")
            time.sleep(max(0, args.delay))


if __name__ == "__main__":
    main()
''';

    final blob = html.Blob([script], 'text/x-python;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', 'download_commonslens_manifest.py')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  /// Downloads [items] as one or more zip archives. Safe to call again
  /// while a previous call is still running — each call is fully
  /// self-contained (its own streaming encoder, its own progress callback),
  /// so multiple batches can download concurrently without interfering.
  ///
  /// - [maxWidth]: when set, downloads a scaled version of each file
  ///   (looked up via imageinfo) instead of the full-resolution original.
  ///   For dataset/ML use this is usually what's actually wanted — a
  ///   1280px batch can be a small fraction of the size of full-res
  ///   originals. Null (default) downloads full-resolution originals.
  /// - [chunkSize]: once [items] exceeds this count, the batch splits into
  ///   multiple sequential zip downloads instead of one giant archive held
  ///   entirely in memory — a fresh Archive per chunk, not accumulated
  ///   across the whole run. Each chunk triggers its own browser download
  ///   (`name_part1of4.zip`, etc). Note: some browsers prompt to allow
  ///   "multiple downloads" after the first couple of automatic ones —
  ///   that's a browser-level permission prompt this can't bypass.
  /// - [concurrency]: fetches per chunk running in parallel. Lower this
  ///   (rather than raise it) if the UI feels sluggish mid-download — each
  ///   completed fetch does a synchronous CRC32 + memory copy on the main
  ///   thread (see fetchOne below), and more concurrent fetches means more
  ///   of those synchronous chunks landing close together with less room
  ///   for the browser to repaint in between. Fewer concurrent fetches
  ///   means a slower download, not a smoother-but-still-fast one — that's
  ///   the actual trade-off being made here.
  /// - [onProgress]: (completed, total, failedTitles) for THIS call's
  ///   batch, reported after every file regardless of chunking.
  /// - [cancelToken]: optional. Calling `.cancel()` on it stops this run:
  ///   in-flight requests get aborted (see [DownloadCancelToken]), no new
  ///   fetches start, and the chunk that was in progress when cancel was
  ///   called is discarded rather than downloaded partially — any EARLIER
  ///   chunks that already finished and triggered their own browser
  ///   download stay downloaded, since that can't be undone.
  static Future<void> downloadBulkZip(
    List<SearchItem> items, {
    String zipName = 'commons_export.zip',
    int concurrency = 2,
    int chunkSize = 25,
    int? maxWidth,
    void Function(int completed, int total, List<String> failedTitles)?
        onProgress,
    DownloadCancelToken? cancelToken,
  }) async {
    if (items.isEmpty) return;
    if (cancelToken?.isCancelled == true) return;

    final client = WikimediaDownloadClient();
    cancelToken?._client = client;

    await _WakeLock.acquire();
    try {
      final failedTitles = <String>[];
      var completed = 0;

      final safeZipName =
          _safeExportName(zipName, 'zip', fallback: 'commons_export');
      final baseName =
          safeZipName.substring(0, safeZipName.length - '.zip'.length);

      final chunks = <List<SearchItem>>[];
      for (var i = 0; i < items.length; i += chunkSize) {
        chunks.add(items.skip(i).take(chunkSize).toList());
      }

      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        final chunk = chunks[chunkIndex];

        // Streaming encoder, not a batch Archive. add() writes that file's
        // local header + bytes straight into `output` immediately when
        // called — it does not wait for the rest of the chunk. That's the
        // key change: previously every file sat in an in-memory Archive
        // and the entire chunk was encoded in one blocking call after the
        // last fetch resolved (the "freeze right at the end"). Now each
        // file's write happens right after ITS OWN fetch completes, spread
        // across the whole chunk instead of bunched at the finish.
        //
        // package:archive 4.x API: OutputStream is abstract — the
        // in-memory concrete type is OutputMemoryStream. The incremental
        // per-file write method on ZipEncoder is `add` (not `addFile`
        // from the pre-4.0 API), and per-file compression is controlled
        // via `add`'s `level` argument rather than a field on ArchiveFile.
        final output = OutputMemoryStream(byteOrder: ByteOrder.littleEndian);
        final encoder = ZipEncoder()..startEncode(output, level: 0);
        var filesWritten = 0;
        var mediaBytesWritten = 0;
        // (in-zip filename, source item) for every file that actually made
        // it into this chunk's zip — this is what data.csv is built from,
        // so a failed file never shows up describing bytes that aren't
        // actually in the archive.
        final manifestEntries = <MapEntry<String, SearchItem>>[];

        Future<void> fetchOne(SearchItem item) async {
          try {
            DownloadSecurityPolicy.requireTrustedMediaUri(item.url);
            var downloadUrl = item.url;
            if (maxWidth != null) {
              final scaled = await client.fetchScaledUrl(
                item.title,
                maxWidth,
                cancelled: () => cancelToken?.isCancelled == true,
              );
              if (scaled != null) downloadUrl = scaled;
            }

            final isOriginal = downloadUrl == item.url;
            final response = await client.fetchMedia(
              downloadUrl,
              cancelled: () => cancelToken?.isCancelled == true,
              expectedMime: isOriginal ? item.mime : null,
              expectedSha1: isOriginal ? item.sha1 : null,
              expectedLength: isOriginal ? item.fileSizeBytes : null,
            );

            if (response == null) {
              failedTitles.add(item.title);
              return;
            }
            if (mediaBytesWritten + response.bytes.length >
                DownloadSecurityPolicy.maxZipBytes) {
              throw const DownloadSecurityException(
                'archive_too_large',
                'Download blocked: this ZIP chunk exceeds the 1 GiB safety limit.',
              );
            }

            final fileName = _sanitizedFileName(
              item,
              extension: response.extension,
            );

            // level: 0 makes this a plain store (memcpy + CRC32), skipping
            // Deflate entirely for this entry — there's no compression
            // work left to defer to a big final pass. Since fetches
            // interleave via Future.wait, each add() call lands as soon
            // as (and only as soon as) that particular file's bytes are
            // in hand; Dart's single-threaded event loop means these
            // calls can never overlap each other, so no locking is
            // needed.
            final archiveFile =
                ArchiveFile(fileName, response.bytes.length, response.bytes);
            encoder.add(archiveFile, level: 0);
            filesWritten++;
            mediaBytesWritten += response.bytes.length;
            manifestEntries.add(MapEntry(fileName, item));

            // Explicit yield. encoder.add() just did synchronous CPU work
            // (CRC32 + a memory copy) proportional to this file's size,
            // fully blocking the main thread while it ran. Without a yield
            // here, a worker that immediately grabs its next file can
            // chain straight into ANOTHER synchronous block with no gap —
            // that chaining, not any single file, is what reads as "UI
            // goes sluggish mid-download." Future.delayed(Duration.zero)
            // (a macrotask) gives the browser an actual chance to paint a
            // frame and process input here, unlike Future.microtask/
            // scheduleMicrotask, which run before rendering gets a turn.
            await Future.delayed(Duration.zero);
          } on DownloadSecurityException catch (error) {
            debugPrint('${item.title}: ${error.message}');
            failedTitles.add('${item.title} (security blocked)');
          } catch (error) {
            debugPrint('${item.title}: download failed: $error');
            failedTitles.add(item.title);
          } finally {
            completed++;
            onProgress?.call(completed, items.length, failedTitles);
          }
        }

        // Rolling worker pool, not lockstep batching. The previous version
        // downloaded in fixed groups of `concurrency` and awaited the
        // WHOLE group before starting the next one — so if one file in a
        // group of 5 was unusually slow (bigger file, slower edge, a
        // retry), the other 4 workers sat idle waiting on it instead of
        // pulling the next file. That's what the remaining "hangs near
        // the end" was: near the tail of a run it only takes one slow
        // straggler in the last group to stall everything behind it. A
        // pool of workers pulling from one shared queue keeps all
        // `concurrency` slots continuously busy — the instant a worker
        // finishes, it grabs the next queued file rather than waiting on
        // its group-mates.
        var nextIndex = 0;
        Future<void> worker() async {
          while (true) {
            if (cancelToken?.isCancelled == true) return;
            if (nextIndex >= chunk.length) return;
            final item = chunk[nextIndex++];
            await fetchOne(item);
          }
        }

        // This setting can tune downward but cannot bypass the shared
        // Wikimedia-wide concurrency ceiling.
        final workerCount =
            concurrency.clamp(1, WikimediaDownloadClient.maxConcurrent).toInt();
        await Future.wait(
          List.generate(workerCount, (_) => worker()),
        );

        if (cancelToken?.isCancelled == true) {
          // Stop entirely rather than moving to the next chunk — and skip
          // triggering a browser download for THIS chunk, since it's
          // whatever partial set of files happened to land before cancel
          // was called, not a complete, intentional batch.
          break;
        }

        if (filesWritten == 0) continue;

        final csvBytes = utf8.encode(
          buildManifestCsv(manifestEntries.map((e) => e.value).toList()),
        );
        encoder.add(
          ArchiveFile('data.csv', csvBytes.length, csvBytes),
          level: 0,
        );

        // Just writes the central directory (file names/offsets/CRCs
        // already computed) — no compression happens here, so this is
        // fast regardless of chunk size.
        encoder.endEncode();
        final zipData = output.getBytes();

        final thisZipName = chunks.length > 1
            ? '${baseName}_part${chunkIndex + 1}of${chunks.length}.zip'
            : safeZipName;

        final blob = html.Blob([zipData], 'application/zip');
        final url = html.Url.createObjectUrlFromBlob(blob);

        html.AnchorElement(href: url)
          ..setAttribute("download", thisZipName)
          ..click();

        html.Url.revokeObjectUrl(url);

        // Small gap between triggered downloads — back-to-back
        // programmatic downloads with zero delay are more likely to hit a
        // browser's "block multiple automatic downloads" heuristic.
        if (chunkIndex < chunks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }
    } finally {
      client.close();
      await _WakeLock.release();
    }
  }
}
