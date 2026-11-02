import 'package:flutter/material.dart';

import 'commons_backend.dart';

Future<void> showWikimediaRequestLog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _WikimediaRequestLogDialog(),
  );
}

class _WikimediaRequestLogDialog extends StatefulWidget {
  const _WikimediaRequestLogDialog();

  @override
  State<_WikimediaRequestLogDialog> createState() =>
      _WikimediaRequestLogDialogState();
}

class _WikimediaRequestLogDialogState
    extends State<_WikimediaRequestLogDialog> {
  final _logger = WikimediaRequestLogger.instance;

  @override
  void initState() {
    super.initState();
    _logger.addListener(_refresh);
  }

  @override
  void dispose() {
    _logger.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _logger.grouped;
    final categories = WikimediaRequestCategory.values
        .where((category) => grouped[category]?.isNotEmpty == true)
        .toList();
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;

    return AlertDialog(
      backgroundColor: const Color(0xFF111111),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'WIKIMEDIA REQUEST LOG',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear log',
            onPressed: _logger.entries.isEmpty ? null : () => _logger.clear(),
            icon: const Icon(Icons.delete_outline, size: 18),
          ),
        ],
      ),
      content: SizedBox(
        width: width < 760 ? width * 0.82 : 680,
        height: height < 700 ? height * 0.62 : 520,
        child: categories.isEmpty
            ? const Center(
                child: Text(
                  'No Wikimedia requests recorded yet.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              )
            : ListView(
                children: [
                  for (final category in categories) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                        category.name.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFF7AABFF),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    for (final entry in grouped[category]!)
                      SelectableText(
                        '${entry.url} ${entry.status}',
                        style: const TextStyle(
                          color: Color(0xFFD0D0D0),
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
