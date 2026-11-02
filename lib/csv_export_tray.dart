import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'download_service.dart';
import 'pipeline_manifest.dart';
import 'search_models.dart';
import 'wikimedia_download_client.dart';
import 'legal_pages.dart';

final selectionModeProvider = StateProvider<bool>((ref) => false);
final selectedItemsProvider = StateProvider<Set<SearchItem>>((ref) => {});

/// Shared result-selection tray. Selection is deliberately limited to a
/// metadata CSV: no media bytes are fetched and no archive is constructed.
class CsvExportTray extends ConsumerStatefulWidget {
  final List<SearchItem> availableItems;
  final String fileName;

  const CsvExportTray({
    super.key,
    required this.availableItems,
    this.fileName = 'commonslens_export',
  });

  @override
  ConsumerState<CsvExportTray> createState() => _CsvExportTrayState();
}

class _CsvExportTrayState extends ConsumerState<CsvExportTray> {
  bool _fullResolutionLinks = true;
  bool _isExporting = false;

  Future<void> _exportCsv(List<SearchItem> items) async {
    if (items.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      final records = buildManifestRecords(
        items,
        metadataLevel: ManifestMetadataLevel.full,
        imageLinks: _fullResolutionLinks
            ? ManifestImageLinks.original
            : ManifestImageLinks.thumbnail,
      );
      await DownloadService.downloadCsvRecords(records, widget.fileName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'CSV ready: ${items.length} record${items.length == 1 ? '' : 's'}; no image files were downloaded.',
            ),
          ),
        );
      }
    } on DownloadSecurityException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: const Color(0xFF7A1F1F),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          ref.read(selectedItemsProvider.notifier).state = {};
          ref.read(selectionModeProvider.notifier).state = false;
        });
      }
    }
  }

  Widget _resolutionButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isExporting ? null : onTap,
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

  @override
  Widget build(BuildContext context) {
    final isSelectionMode = ref.watch(selectionModeProvider);
    final selectedItems = ref.watch(selectedItemsProvider);

    if (!isSelectionMode) return const SizedBox.shrink();

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
            const Text(
              'CSV EXPORT — metadata and one image URL per row',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            const Align(
              alignment: Alignment.centerLeft,
              child: CommonsLensDownloadSecurityButton(),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: _resolutionButton(
                    label: 'Full-size URL',
                    selected: _fullResolutionLinks,
                    onTap: () => setState(() => _fullResolutionLinks = true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _resolutionButton(
                    label: 'Web-optimized URL',
                    selected: !_fullResolutionLinks,
                    onTap: () => setState(() => _fullResolutionLinks = false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () {
                          ref.read(selectionModeProvider.notifier).state =
                              false;
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
                  onPressed: _isExporting || widget.availableItems.isEmpty
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
                  onPressed: selectedItems.isEmpty || _isExporting
                      ? null
                      : () => _exportCsv(selectedItems.toList()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D7EFF),
                  ),
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.table_chart_outlined,
                          size: 18, color: Colors.white),
                  label: Text(
                    _isExporting
                        ? 'Preparing CSV…'
                        : 'Download CSV (${selectedItems.length})',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
