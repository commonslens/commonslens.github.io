import 'dart:convert';
import 'dart:html' as html;
import 'dart:async';
import 'dart:js_util' as js_util;
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'search_models.dart';

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
      await js_util.promiseToFuture(js_util.callMethod(sentinel, 'release', []));
    } catch (_) {
      // Already released by the browser (e.g. tab was backgrounded) — fine.
    }
  }
}

class DownloadService {
  static Future<void> downloadSingleFile(String url, String title, String extension) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final cleanTitle = title
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll('File:', '')
            .trim();
        final fileName = '$cleanTitle.${extension.toLowerCase()}';

        final blob = html.Blob([response.bodyBytes], response.headers['content-type'] ?? 'application/octet-stream');
        final objectUrl = html.Url.createObjectUrlFromBlob(blob);

        html.AnchorElement(href: objectUrl)
          ..setAttribute("download", fileName)
          ..click();

        html.Url.revokeObjectUrl(objectUrl);
      }
    } catch (e) {
      print('Download failed: $e');
      html.window.open(url, '_blank');
    }
  }

  /// Looks up a scaled thumbnail URL for [title] at [maxWidth] via
  /// prop=imageinfo&iiurlwidth — the same proven-reliable mechanism used
  /// elsewhere in this app (not a hand-built thumb URL). Goes to
  /// commons.wikimedia.org/w/api.php, NOT upload.wikimedia.org, so the
  /// Api-User-Agent header is safe here — see the note on _fetchWithRetry
  /// for why it's deliberately omitted on the raw media server.
  /// Falls back to null (caller uses the full-res original) on any failure.
  static Future<String?> _fetchScaledUrl(String title, int maxWidth) async {
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'origin': '*',
        'titles': title,
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '$maxWidth',
      });

      final response = await http.get(uri, headers: {
        'Api-User-Agent': 'CommonslensApp/1.0 (Flutter Web)',
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
      for (final page in pages.values) {
        final infoList = (page as Map<String, dynamic>)['imageinfo'] as List?;
        if (infoList == null || infoList.isEmpty) continue;
        final thumb = (infoList.first as Map<String, dynamic>)['thumburl'] as String?;
        if (thumb != null && thumb.isNotEmpty) return thumb;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches one file with a timeout and a couple of retries on transient
  /// failure (timeout, dropped connection, 5xx). Does NOT retry on 4xx —
  /// that's a real rejection (e.g. gone/forbidden), not a transient blip.
  ///
  /// Deliberately sends NO custom headers — upload.wikimedia.org is the raw
  /// media storage layer, not the MediaWiki API. Unlike
  /// commons.wikimedia.org/w/api.php and www.wikidata.org/w/api.php (which
  /// do support a custom Api-User-Agent header), a plain simple GET is what
  /// actually works here: any custom header turns this into a "non-simple"
  /// cross-origin request, forcing a CORS preflight — if that preflight
  /// isn't explicitly allowed, the browser blocks the request before it
  /// ever reaches the network, silently and identically for every file.
  static Future<http.Response?> _fetchWithRetry(
    String url, {
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.get(Uri.parse(url)).timeout(timeout);

        if (response.statusCode == 200) return response;
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return null;
        }
      } catch (_) {
        // Timeout or network error — fall through to retry.
      }

      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }
    return null;
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
  static Future<void> downloadBulkZip(
    List<SearchItem> items, {
    String zipName = 'commons_export.zip',
    int concurrency = 3,
    int chunkSize = 50,
    int? maxWidth,
    void Function(int completed, int total, List<String> failedTitles)? onProgress,
  }) async {
    if (items.isEmpty) return;

    await _WakeLock.acquire();
    try {
      final failedTitles = <String>[];
      var completed = 0;

      final baseName =
          zipName.toLowerCase().endsWith('.zip') ? zipName.substring(0, zipName.length - 4) : zipName;

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

        Future<void> fetchOne(SearchItem item) async {
          var downloadUrl = item.url;
          if (maxWidth != null) {
            final scaled = await _fetchScaledUrl(item.title, maxWidth);
            if (scaled != null) downloadUrl = scaled;
          }

          final response = await _fetchWithRetry(downloadUrl);

          if (response != null) {
            final cleanTitle = item.title
                .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
                .replaceAll('File:', '')
                .trim();

            final fileName = '$cleanTitle.${item.extension.toLowerCase()}';

            // level: 0 makes this a plain store (memcpy + CRC32), skipping
            // Deflate entirely for this entry — there's no compression
            // work left to defer to a big final pass. Since fetches
            // interleave via Future.wait, each add() call lands as soon
            // as (and only as soon as) that particular file's bytes are
            // in hand; Dart's single-threaded event loop means these
            // calls can never overlap each other, so no locking is
            // needed.
            final archiveFile =
                ArchiveFile(fileName, response.bodyBytes.length, response.bodyBytes);
            encoder.add(archiveFile, level: 0);
            filesWritten++;

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
          } else {
            failedTitles.add(item.title);
          }

          completed++;
          onProgress?.call(completed, items.length, failedTitles);
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
            if (nextIndex >= chunk.length) return;
            final item = chunk[nextIndex++];
            await fetchOne(item);
          }
        }

        await Future.wait(
          List.generate(concurrency, (_) => worker()),
        );

        if (filesWritten == 0) continue;

        // Just writes the central directory (file names/offsets/CRCs
        // already computed) — no compression happens here, so this is
        // fast regardless of chunk size.
        encoder.endEncode();
        final zipData = output.getBytes();

        final thisZipName = chunks.length > 1
            ? '${baseName}_part${chunkIndex + 1}of${chunks.length}.zip'
            : zipName;

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
      await _WakeLock.release();
    }
  }
}