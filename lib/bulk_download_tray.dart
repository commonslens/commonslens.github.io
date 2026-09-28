import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analytics_service.dart';
import 'download_service.dart';
import 'search_models.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedItemsProvider = StateProvider<Set<SearchItem>>((ref) => {});

/// Tracks one in-flight (or just-finished) bulk download. Multiple of these
/// can exist at once — starting a new download never has to wait for a
/// prior one to finish, each just gets its own row in the progress list.
class _DownloadJob {
  final int id;
  int completed = 0;
  int total;
  List<String> failed = [];
  bool done = false;
  bool cancelled = false;
  String? error;
  final DownloadCancelToken cancelToken = DownloadCancelToken();

  _DownloadJob({required this.id, required this.total});
}

class BulkDownloadTray extends ConsumerStatefulWidget {
  final List<SearchItem> availableItems;

  const BulkDownloadTray({
    super.key,
    required this.availableItems,
  });

  @override
  ConsumerState<BulkDownloadTray> createState() => BulkDownloadTrayState();
}

class BulkDownloadTrayState extends ConsumerState<BulkDownloadTray> {
  final List<_DownloadJob> _downloadJobs = [];
  int _nextDownloadJobId = 0;
  bool _downloadFullRes = true;

  Future<void> startDownload(
    List<SearchItem> items, {
    String zipName = 'selected_commons_media.zip',
  }) async {
    if (items.isEmpty) return;

    AnalyticsService.bulkDownloadStarted(items.length);
    final job = _DownloadJob(id: _nextDownloadJobId++, total: items.length);
    setState(() => _downloadJobs.add(job));
    ref.read(selectedItemsProvider.notifier).state = {};

    try {
      await DownloadService.downloadBulkZip(
        items,
        zipName: zipName,
        maxWidth: _downloadFullRes ? null : 1280,
        cancelToken: job.cancelToken,
        onProgress: (completed, total, failedTitles) {
          if (!mounted) return;
          setState(() {
            job.completed = completed;
            job.total = total;
            job.failed = List<String>.from(failedTitles);
          });
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() => job.error = 'Download stopped: $error');
      }
    } finally {
      if (mounted) {
        setState(() => job.done = true);
        AnalyticsService.bulkDownloadCompleted(
          total: job.total,
          failed: job.failed.length,
          cancelled: job.cancelled,
        );
        if (job.failed.isEmpty && job.error == null && !job.cancelled) {
          Future.delayed(const Duration(seconds: 4), () {
            if (!mounted) return;
            setState(() => _downloadJobs.remove(job));
          });
        }
      }
    }
  }

  void _cancelDownload(_DownloadJob job) {
    job.cancelToken.cancel();
    setState(() => job.cancelled = true);
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _downloadJobs.remove(job));
    });
  }

  Widget _resolutionButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3D7EFF).withValues(alpha: 0.15)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? const Color(0xFF3D7EFF) : const Color(0xFF262626),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF3D7EFF) : Colors.white54,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _jobProgressRow(_DownloadJob job) {
    final fraction = job.total == 0 ? null : job.completed / job.total;
    final hasFailed = job.failed.isNotEmpty || job.error != null;
    final isActive = !job.done && !job.cancelled;

    final String status;
    if (job.cancelled) {
      status = 'Cancelled - ${job.completed} of ${job.total} downloaded';
    } else if (job.error != null) {
      status = job.error!;
    } else if (job.done) {
      status = job.failed.isEmpty
          ? 'Done - ${job.total} files'
          : 'Done - ${job.failed.length} of ${job.total} failed; the rest were saved';
    } else {
      status = 'Downloading ${job.completed} / ${job.total}'
          '${job.failed.isEmpty ? '' : ' - ${job.failed.length} failed'}...';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (job.done || job.cancelled) ? 1.0 : fraction,
                    minHeight: 5,
                    backgroundColor: const Color(0xFF2A2A2A),
                    valueColor: AlwaysStoppedAnimation(
                      job.cancelled
                          ? const Color(0xFF888888)
                          : hasFailed
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF3D7EFF),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasFailed
                        ? const Color(0xFFFF6B6B)
                        : const Color(0xFF888888),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: isActive
                ? TextButton.icon(
                    onPressed: () => _cancelDownload(job),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B6B),
                      backgroundColor: const Color(0xFF2A1414),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text('Cancel download',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  )
                : IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => setState(() => _downloadJobs.remove(job)),
                    icon: const Icon(Icons.close_rounded,
                        size: 17, color: Colors.white38),
                    visualDensity: VisualDensity.compact,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = ref.watch(selectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);

    if (!isSelectionMode && _downloadJobs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF131313),
        border: Border(top: BorderSide(color: Color(0xFF202020))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_downloadJobs.isNotEmpty) ...[
              ..._downloadJobs.map(_jobProgressRow),
              const SizedBox(height: 4),
            ],
            if (isSelectionMode) ...[
              Row(
                children: [
                  Expanded(
                    child: _resolutionButton(
                      label: 'Full Resolution',
                      selected: _downloadFullRes,
                      onTap: () => setState(() => _downloadFullRes = true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _resolutionButton(
                      label: 'Web-Optimized (1280px)',
                      selected: !_downloadFullRes,
                      onTap: () => setState(() => _downloadFullRes = false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.read(selectionModeProvider.notifier).state = false;
                      ref.read(selectedItemsProvider.notifier).state = {};
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: const Text('Minimize'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.availableItems.isEmpty
                        ? null
                        : () {
                            ref.read(selectedItemsProvider.notifier).state =
                                widget.availableItems.toSet();
                          },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF3D7EFF)),
                      foregroundColor: const Color(0xFF3D7EFF),
                    ),
                    icon: const Icon(Icons.select_all, size: 18),
                    label: const Text('Select All'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: selectedItems.isEmpty
                        ? null
                        : () => startDownload(selectedItems.toList()),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3D7EFF)),
                    icon: const Icon(Icons.download,
                        size: 18, color: Colors.white),
                    label: Text(
                      'Download (${selectedItems.length})',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
