import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_queue.dart';
import 'download_service.dart';
import 'legal_pages.dart';
import 'media_archive_service.dart';
import 'pipeline_manifest.dart';
import 'wikimedia_download_client.dart';

/// The persistent cross-route selection tray. It is mounted once by the app
/// shell, not once by Search, Map, Bookmarks, or Author pages.
class DownloadQueueTray extends ConsumerStatefulWidget {
  const DownloadQueueTray({super.key});

  @override
  ConsumerState<DownloadQueueTray> createState() => _DownloadQueueTrayState();
}

class _DownloadQueueTrayState extends ConsumerState<DownloadQueueTray> {
  bool _busy = false;
  bool _minimized = false;
  int _completed = 0;
  int _total = 0;
  int _part = 1;
  String _currentTitle = '';
  String _phase = '';
  bool _cancelRequested = false;
  bool _zipJobActive = false;

  Future<void> _exportCsv(List<DownloadQueueItem> queue) async {
    if (queue.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _zipJobActive = false;
    });
    try {
      final records = buildManifestRecords(
        queue.map((entry) => entry.item).toList(growable: false),
        metadataLevel: ManifestMetadataLevel.full,
        imageLinks: ManifestImageLinks.original,
      );
      await DownloadService.downloadCsvRecords(
        records,
        'commonslens_download_queue',
      );
      _showMessage(
          'CSV ready: ${queue.length} media records; no media bytes were downloaded.');
    } on DownloadSecurityException catch (error) {
      _showMessage(error.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadZip(List<DownloadQueueItem> queue) async {
    if (queue.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _completed = 0;
      _total = queue.length;
      _part = 1;
      _currentTitle = '';
      _phase = 'starting';
      _cancelRequested = false;
      _zipJobActive = true;
    });
    try {
      final report = await MediaArchiveService.download(
        queue,
        fileName: 'commonslens_media',
        cancelled: () => _cancelRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _completed = progress.completed;
            _total = progress.total;
            _part = progress.part;
            _currentTitle = progress.title;
            _phase = progress.phase;
          });
        },
      );
      if (!mounted) return;
      if (report.cancelled) {
        _showMessage('Download cancelled; the queue will be cleared.');
      } else if (!report.hasOutput) {
        _showMessage('No selected files passed verification.', error: true);
      } else if (report.skipped.isEmpty) {
        _showMessage(
          '${report.included} verified file(s) added across ${report.parts} ZIP${report.parts == 1 ? '' : 's'}.${report.parts > 1 ? ' The browser may ask to allow multiple downloads.' : ''}',
        );
      } else {
        _showMessage(
          '${report.included} verified file(s) added across ${report.parts} ZIP${report.parts == 1 ? '' : 's'}; ${report.skipped.length} skipped. See each ZIP manifest.${report.parts > 1 ? ' The browser may ask to allow multiple downloads.' : ''}',
          error: true,
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          _cancelRequested
              ? 'Download cancelled; the queue will be cleared.'
              : 'The ZIP could not be created safely.',
          error: !_cancelRequested,
        );
      }
    } finally {
      if (_cancelRequested) {
        ref.read(downloadQueueProvider).clear();
        ref.read(selectionModeProvider.notifier).state = false;
        _minimized = false;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _cancelRequested = false;
          _zipJobActive = false;
        });
      }
    }
  }

  void _cancelDownload() {
    if (!_zipJobActive || _cancelRequested) return;
    setState(() => _cancelRequested = true);
    ref.read(downloadQueueProvider).clear();
    ref.read(selectionModeProvider.notifier).state = false;
    _showMessage('Cancelling download…');
  }

  void _clearQueue() {
    if (_busy) return;
    setState(() => _minimized = false);
    ref.read(downloadQueueProvider).clear();
    ref.read(selectionModeProvider.notifier).state = false;
  }

  void _minimize() {
    setState(() => _minimized = true);
    ref.read(selectionModeProvider.notifier).state = false;
  }

  void _restore() => setState(() => _minimized = false);

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? const Color(0xFF7A1F1F) : null,
      ),
    );
  }

  String _progressText(List<DownloadQueueItem> queue) {
    if (_busy && _total > 0) {
      return '$_completed/$_total · part $_part · $_phase${_currentTitle.isEmpty ? '' : ' · $_currentTitle'}';
    }
    return '${queue.length} selected';
  }

  Widget _buildExpandedTray(List<DownloadQueueItem> queue) {
    final progress = _progressText(queue);
    return SizedBox(
      width: double.infinity,
      child: Material(
        elevation: 18,
        color: const Color(0xFF131313),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return _buildCompactRow(queue, progress);
                }
                return _buildWideRow(queue, progress);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWideRow(List<DownloadQueueItem> queue, String progress) {
    return Row(
      children: [
        const Icon(Icons.download_rounded, color: Colors.white60, size: 18),
        const SizedBox(width: 7),
        Flexible(
          flex: 2,
          child: Text(
            'DOWNLOAD QUEUE · $progress',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const CommonsLensDownloadSecurityButton(),
        if (_zipJobActive) ...[
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: _cancelRequested ? null : _cancelDownload,
            child: Text(_cancelRequested ? 'Cancelling…' : 'Cancel'),
          ),
        ],
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: _minimize,
          child: const Text('Minimize'),
        ),
        const SizedBox(width: 4),
        OutlinedButton(
          onPressed: _busy ? null : _clearQueue,
          child: const Text('Clear'),
        ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _exportCsv(queue),
          icon: const Icon(Icons.table_chart_outlined, size: 16),
          label: const Text('CSV'),
        ),
        const SizedBox(width: 4),
        ElevatedButton.icon(
          onPressed: _busy ? null : () => _downloadZip(queue),
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.folder_zip_outlined, size: 16),
          label: Text(_busy ? 'Working…' : 'ZIP'),
        ),
      ],
    );
  }

  Widget _buildCompactRow(List<DownloadQueueItem> queue, String progress) {
    return Row(
      children: [
        const Icon(Icons.download_rounded, color: Colors.white60, size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            progress,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        IconButton(
          onPressed: () => openDocsSection('download-security'),
          icon: const Icon(Icons.shield_outlined, size: 17),
        ),
        if (_zipJobActive)
          IconButton(
            onPressed: _cancelRequested ? null : _cancelDownload,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
          ),
        IconButton(
          onPressed: _minimize,
          icon: const Icon(Icons.remove, size: 18),
        ),
        IconButton(
          onPressed: _busy ? null : _clearQueue,
          icon: const Icon(Icons.clear_all, size: 18),
        ),
        IconButton(
          onPressed: _busy ? null : () => _exportCsv(queue),
          icon: const Icon(Icons.table_chart_outlined, size: 18),
        ),
        IconButton(
          onPressed: _busy ? null : () => _downloadZip(queue),
          icon: _busy
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.folder_zip_outlined, size: 18),
        ),
      ],
    );
  }

  Widget _buildRestoreFab(List<DownloadQueueItem> queue) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 20),
          child: Semantics(
            button: true,
            label: _busy
                ? 'Show download progress'
                : 'Show download queue (${queue.length})',
            child: FloatingActionButton.small(
              heroTag: 'commonslens-download-queue-restore',
              onPressed: _restore,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(downloadQueueProvider).items;
    if (queue.isEmpty && !_busy) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.loose,
        alignment: Alignment.bottomCenter,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: _minimized
          ? KeyedSubtree(
              key: const ValueKey('download-queue-minimized'),
              child: _buildRestoreFab(queue),
            )
          : KeyedSubtree(
              key: const ValueKey('download-queue-expanded'),
              child: _buildExpandedTray(queue),
            ),
    );
  }
}
