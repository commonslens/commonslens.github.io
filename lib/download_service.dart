// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'pipeline_manifest.dart';
import 'search_models.dart';
import 'wikimedia_download_client.dart';

String _csvField(String value) => DownloadSecurityPolicy.safeCsvField(value);

/// Browser download boundary for CommonsLens.
///
/// Dataset exports are intentionally metadata-only CSV files. This service
/// never fetches media for a collection export and never creates archives.
class DownloadService {
  static final WikimediaDownloadClient _singleDownloadClient =
      WikimediaDownloadClient();

  /// Keeps the existing single-file reuse action available from the asset
  /// viewer and individual result cards. Collection exports use CSV only.
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
        revalidateTitle: isOriginal ? item.title : null,
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

  /// Builds a comprehensive, metadata-only CSV for result-card exports.
  /// [imageLinks] controls whether each row carries the full-size URL, the
  /// web-optimized URL, or both.
  static String buildManifestCsv(
    List<SearchItem> items, {
    ManifestImageLinks imageLinks = ManifestImageLinks.both,
  }) {
    final records = buildManifestRecords(
      items,
      metadataLevel: ManifestMetadataLevel.full,
      imageLinks: imageLinks,
    );
    return _buildCsv(records);
  }

  static String _buildCsv(List<Map<String, dynamic>> records) {
    final columns = <String>[];
    for (final record in records) {
      for (final key in record.keys) {
        if (!columns.contains(key)) columns.add(key);
      }
    }

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
    return chunks.join();
  }

  /// Downloads a metadata-only CSV without fetching any media bytes.
  static Future<void> downloadCsv(
    List<SearchItem> items,
    String fileName, {
    ManifestImageLinks imageLinks = ManifestImageLinks.both,
  }) async {
    await downloadCsvRecords(
      buildManifestRecords(
        items,
        metadataLevel: ManifestMetadataLevel.full,
        imageLinks: imageLinks,
      ),
      fileName,
    );
  }

  static Future<void> downloadCsvRecords(
    List<Map<String, dynamic>> records,
    String fileName,
  ) async {
    final blob = html.Blob(
      [utf8.encode(_buildCsv(records))],
      'text/csv;charset=utf-8',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final name = _safeExportName(fileName, 'csv', fallback: 'commons_export');
    html.AnchorElement(href: url)
      ..setAttribute('download', name)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
