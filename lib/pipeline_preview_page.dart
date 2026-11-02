import 'dart:convert';

import 'package:flutter/material.dart';

import 'media_queue.dart';
import 'pipeline_engine.dart';
import 'search_components.dart';
import 'search_models.dart';

const _previewBg = Color(0xFF0B0B0B);
const _previewPanel = Color(0xFF111111);
const _previewBorder = Color(0xFF292929);
const _previewAccent = Color(0xFF3D7EFF);
const _previewMuted = Color(0xFF888888);

Future<void> openPipelinePreview(
  BuildContext context, {
  required String nodeId,
  required String title,
  required NodeOutput output,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, animation, __) => PipelinePreviewPage(
        nodeId: nodeId,
        title: title,
        output: output,
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
}

class PipelinePreviewPage extends StatefulWidget {
  final String nodeId;
  final String title;
  final NodeOutput output;

  const PipelinePreviewPage({
    super.key,
    required this.nodeId,
    required this.title,
    required this.output,
  });

  @override
  State<PipelinePreviewPage> createState() => _PipelinePreviewPageState();
}

class _PipelinePreviewPageState extends State<PipelinePreviewPage> {
  int _view = 0;
  List<String>? _cachedTableColumns;

  List<SearchItem> get _items => widget.output.items ?? const [];

  Map<String, dynamic> _rowAt(int index) {
    final row = <String, dynamic>{..._items[index].toJson()};
    final extra = widget.output.records;
    if (extra != null && index < extra.length) row.addAll(extra[index]);
    return row;
  }

  List<String> get _tableColumns {
    final cached = _cachedTableColumns;
    if (cached != null) return cached;

    final keys = <String>{};
    for (final item in _items) {
      keys.addAll(item.toJson().keys);
    }
    for (final row in widget.output.records ?? const <Map<String, dynamic>>[]) {
      keys.addAll(row.keys);
    }

    const preferred = ['title', 'url', 'commonsUrl', 'mime', 'width', 'height'];
    final columns = [
      ...preferred.where(keys.contains),
      ...keys.where((key) => !preferred.contains(key)).toList()..sort(),
    ];
    _cachedTableColumns = columns;
    return columns;
  }

  @override
  Widget build(BuildContext context) {
    final output = widget.output;
    return Scaffold(
      backgroundColor: _previewBg,
      appBar: AppBar(
        backgroundColor: _previewBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close preview',
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text(
              '${_items.length} materialized records${output.totalHits == null ? '' : ' · approximately ${output.totalHits} matches'}',
              style: const TextStyle(color: _previewMuted, fontSize: 10.5),
            ),
          ],
        ),
        actions: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.grid_view_rounded),
                  label: Text('Grid')),
              ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.table_rows_rounded),
                  label: Text('Raw table')),
            ],
            selected: {_view},
            onSelectionChanged: (value) => setState(() => _view = value.first),
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Colors.white
                      : _previewMuted),
              backgroundColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? _previewAccent
                      : _previewPanel),
              side: WidgetStateProperty.all(
                  const BorderSide(color: _previewBorder)),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (output.warning != null) _WarningBanner(message: output.warning!),
          const _RightsDisclaimer(),
          Expanded(child: _view == 0 ? _buildGrid() : _buildRawTable()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('No records to preview.',
            style: TextStyle(color: _previewMuted)),
      );
    }
    return MediaResultsGrid(
      items: _items,
      queueSource: MediaQueueSource.pipeline(widget.nodeId),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        mainAxisExtent: 285,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      padding: const EdgeInsets.all(20),
      cacheExtent: 240,
    );
  }

  Widget _buildRawTable() {
    if (_items.isEmpty) {
      return const Center(
        child: Text('No records to preview.',
            style: TextStyle(color: _previewMuted)),
      );
    }
    final columns = _tableColumns;
    const columnWidth = 200.0;
    final tableWidth = columns.length * columnWidth;

    // DataTable measures and builds every cell. A preview may contain deeply
    // nested SDC/imageinfo payloads, so that approach blocks the browser UI.
    // This keeps the header and only the visible rows alive instead.
    return Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _RawTableHeader(columns: columns, columnWidth: columnWidth),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final row = _rowAt(index);
                          return RepaintBoundary(
                            child: _RawTableRow(
                              columns: columns,
                              row: row,
                              columnWidth: columnWidth,
                              onCellTap: (column, value) =>
                                  _showFullValue(column, value),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'Unavailable — verify Commons page';
    if (value is String) {
      return value.isEmpty ? 'Unavailable — verify Commons page' : value;
    }
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }

  Future<void> _showFullValue(String column, dynamic value) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _previewPanel,
        title: Text(column,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: SelectableText(
              _formatValue(value),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _compactTableValue(dynamic value) {
  if (value == null) return 'Unavailable — verify Commons page';
  if (value is Map) return '{${value.length} fields}  · tap to inspect';
  if (value is List) return '[${value.length} items]  · tap to inspect';
  final text = value is String
      ? (value.isEmpty ? 'Unavailable — verify Commons page' : value)
      : value.toString();
  return text.length > 260 ? '${text.substring(0, 257)}…' : text;
}

class _RawTableHeader extends StatelessWidget {
  final List<String> columns;
  final double columnWidth;

  const _RawTableHeader({
    required this.columns,
    required this.columnWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      color: _previewPanel,
      child: Row(
        children: [
          for (final column in columns)
            SizedBox(
              width: columnWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    column,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RawTableRow extends StatelessWidget {
  final List<String> columns;
  final Map<String, dynamic> row;
  final double columnWidth;
  final void Function(String column, dynamic value) onCellTap;

  const _RawTableRow({
    required this.columns,
    required this.row,
    required this.columnWidth,
    required this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _previewBorder)),
      ),
      child: Row(
        children: [
          for (final column in columns)
            SizedBox(
              width: columnWidth,
              child: InkWell(
                onTap: () => onCellTap(column, row[column]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      _compactTableValue(row[column]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message,
          style: const TextStyle(color: Colors.amber, fontSize: 11.5)),
    );
  }
}

class _RightsDisclaimer extends StatelessWidget {
  const _RightsDisclaimer();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        border: Border.all(color: _previewBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_outlined, color: Color(0xFFE7B75C), size: 15),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Rights reminder: a blank licence, credit, or attribution field does not mean reuse is unrestricted. Verify the original Commons file page and follow its licence terms before reuse.',
              style: TextStyle(
                color: Color(0xFFD8C48F),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
