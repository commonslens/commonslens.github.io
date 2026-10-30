part of 'pipeline_page.dart';

// -----------------------------------------------------------------------------
// Inspector panel — a tabbed per-node workspace: SETTINGS (the generic
// field-spec form + bespoke Depicts/Statement editor + sink actions),
// PREVIEW (this node's actual last-run output as a downloadable media
// grid — works for every node type, not just Preview sinks), and NOTES
// (a freeform per-node scratchpad, stored in node.config['_note']).
// -----------------------------------------------------------------------------

enum _InspectorTab { settings, preview, notes }

class _InspectorPanel extends ConsumerStatefulWidget {
  final String? nodeId;
  final void Function(String? error) onSinkResult;
  final void Function(String nodeId) onSendToSearch;
  final void Function(List<SearchItem> items, String zipName) onDownloadItems;

  const _InspectorPanel({
    required this.nodeId,
    required this.onSinkResult,
    required this.onSendToSearch,
    required this.onDownloadItems,
  });

  @override
  ConsumerState<_InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends ConsumerState<_InspectorPanel> {
  _InspectorTab _tab = _InspectorTab.settings;

  @override
  void didUpdateWidget(covariant _InspectorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeId != widget.nodeId) {
      setState(() => _tab = _InspectorTab.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.nodeId;
    if (id == null) return _buildEmptyState();

    final graph = ref.watch(pipelineControllerProvider.select((s) => s.graph));
    final node = graph.nodeById(id);
    if (node == null) return const SizedBox.shrink();

    final status =
        ref.watch(pipelineControllerProvider.select((s) => s.nodeStatus[id]));
    final controller = ref.read(pipelineControllerProvider.notifier);
    return Container(
      color: _kPanelBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(node, status, controller),
          _buildTabBar(),
          const Divider(color: _kBorder, height: 1),
          Expanded(child: _buildTabBody(node, controller)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: _kPanelBg,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.08),
                    shape: BoxShape.circle),
                child: const Icon(Icons.touch_app_outlined,
                    size: 28, color: _kAccent),
              ),
              const SizedBox(height: 16),
              const Text('Select a node',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text(
                'Tap any node on the canvas to edit its settings, preview its output, or leave yourself a note.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _kMuted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(PipelineNode node, PipelineNodeStatus? status,
      PipelineController controller) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _kBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: _kAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child:
                    Icon(_nodeTypeIcon(node.type), size: 15, color: _kAccent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  key: ValueKey('title-${node.id}'),
                  initialValue: node.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero),
                  onFieldSubmitted: (v) => controller.renameNode(
                      node.id, v.trim().isEmpty ? node.type.label : v.trim()),
                ),
              ),
              IconButton(
                tooltip: 'Duplicate node',
                icon: const Icon(Icons.copy_all_outlined,
                    size: 17, color: Colors.white54),
                onPressed: () => controller.duplicateNode(node.id),
              ),
              IconButton(
                tooltip: 'Delete node',
                icon:
                    const Icon(Icons.delete_outline, size: 17, color: _kError),
                onPressed: () => controller.removeNode(node.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(node.type.label,
                  style: const TextStyle(
                      color: _kMuted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6)),
              if (status != null) ...[
                const SizedBox(width: 8),
                Flexible(child: _StatusPill(status: status)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    Widget seg(String label, IconData icon, _InspectorTab tab) {
      final selected = _tab == tab;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = tab),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: selected ? _kAccent : Colors.transparent,
                      width: 2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 15, color: selected ? _kAccent : Colors.white38),
                const SizedBox(height: 3),
                Text(label,
                    style: TextStyle(
                        color: selected ? _kAccent : Colors.white38,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Row(children: [
      seg('SETTINGS', Icons.tune_rounded, _InspectorTab.settings),
      seg('PREVIEW', Icons.visibility_outlined, _InspectorTab.preview),
      seg('NOTES', Icons.notes_rounded, _InspectorTab.notes),
    ]);
  }

  Widget _buildTabBody(PipelineNode node, PipelineController controller) {
    switch (_tab) {
      case _InspectorTab.settings:
        return _buildSettingsTab(node, controller);
      case _InspectorTab.preview:
        return _buildPreviewTab(node, controller);
      case _InspectorTab.notes:
        return _buildNotesTab(node, controller);
    }
  }

  // ---- SETTINGS ----

  Widget _buildSettingsTab(PipelineNode node, PipelineController controller) {
    final specs = configSpecFor(node.type);
    final isEntriesType = node.type == PipelineNodeType.sourceDepicts ||
        node.type == PipelineNodeType.sourceStatement;

    final graph = ref.watch(pipelineControllerProvider.select((s) => s.graph));
    final inbound = graph.edges.where((e) => e.toNodeId == node.id).length;
    final outbound = graph.edges.where((e) => e.fromNodeId == node.id).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NodeOverviewCard(
          node: node,
          inbound: inbound,
          outbound: outbound,
        ),
        const SizedBox(height: 20),
        const Text(
          'CONFIGURATION',
          style: TextStyle(
            color: _kMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        if (isEntriesType)
          _EntriesEditor(node: node)
        else if (specs.isNotEmpty)
          for (final spec in specs) ...[
            _ConfigFieldWidget(
                key: ValueKey('config-${node.id}-${spec.key}'),
                node: node,
                spec: spec,
                onChanged: (value) => controller.updateNodeConfig(
                    node.id, {...node.config, spec.key: value})),
            const SizedBox(height: 16),
          ]
        else
          _buildNoConfigHint(node.type),
        if (node.type.isSink) ...[
          const SizedBox(height: 8),
          const Divider(color: _kBorder),
          const SizedBox(height: 12),
          const Text('ACTIONS',
              style: TextStyle(
                  color: _kMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 10),
          ..._sinkActions(node, controller),
        ],
      ],
    );
  }

  Widget _buildNoConfigHint(PipelineNodeType type) {
    String text;
    switch (type.category) {
      case PipelineNodeCategory.setOp:
        text = type == PipelineNodeType.setCombineAnd
            ? 'Connect two query-capable branches to A and B. Their constraints are combined into one Commons request before any results are fetched.'
            : 'Connect two upstream branches to ports A and B — this node combines them and has no settings of its own.';
        break;
      case PipelineNodeCategory.transform:
        text = type == PipelineNodeType.transformDedupe
            ? 'Dedupes its input by URL — no configuration needed.'
            : 'Not implemented yet — items pass through unchanged. See the PREVIEW tab once you run the pipeline.';
        break;
      case PipelineNodeCategory.sink:
        text = 'Connect an upstream branch, then use the action below.';
        break;
      default:
        text = 'This node has no configurable settings.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(text,
          style: const TextStyle(color: _kMuted, fontSize: 12, height: 1.5)),
    );
  }

  List<Widget> _sinkActions(PipelineNode node, PipelineController controller) {
    switch (node.type) {
      case PipelineNodeType.sinkCsvExport:
        return [
          _actionButton(
              Icons.table_chart_outlined,
              'Export CSV',
              () async => widget.onSinkResult(await controller.exportSinkCsv(
                  node.id,
                  fileName:
                      node.config['fileName'] as String? ?? 'pipeline_export')))
        ];
      case PipelineNodeType.sinkJsonExport:
        return [
          _actionButton(
              Icons.data_object_rounded,
              'Export JSON',
              () async => widget.onSinkResult(await controller.exportSinkJson(
                  node.id,
                  fileName:
                      node.config['fileName'] as String? ?? 'pipeline_export')))
        ];
      case PipelineNodeType.sinkZipExport:
        return [
          _actionButton(
              Icons.folder_zip_outlined,
              'Export Zip',
              () async => widget.onSinkResult(await controller.exportSinkZip(
                  node.id,
                  zipName: node.config['zipName'] as String? ??
                      'pipeline_export.zip',
                  fullRes: node.config['fullRes'] as bool? ?? true)))
        ];
      case PipelineNodeType.sinkSendToSearch:
        return [
          _actionButton(Icons.send_rounded, 'Send to Search',
              () => widget.onSendToSearch(node.id))
        ];
      case PipelineNodeType.sinkPreview:
        return [
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
                'This sink has no export of its own — open the PREVIEW tab above to browse and download its items.',
                style: TextStyle(color: _kMuted, fontSize: 11.5, height: 1.5)),
          ),
        ];
      default:
        return const [];
    }
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kAccent,
              side: const BorderSide(color: Color(0xFF2A4A8A)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(icon, size: 16),
            label: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ),
      );

  // ---- PREVIEW ----

  Widget _buildPreviewTab(PipelineNode node, PipelineController controller) {
    final output = controller.outputFor(node.id);

    if (output == null) {
      return _centeredHint(
          'Run the pipeline (▶ or the preview eye icon up top) to see this node\'s output here.',
          icon: Icons.play_circle_outline);
    }
    if (output.hasError) {
      return _centeredHint(output.error ?? 'This node failed.',
          color: _kError, icon: Icons.error_outline);
    }
    if (output.isPending) {
      return _centeredHint(
        'Folded into the upstream query — nothing fetched yet. Connect a Set-op, Transform, or Sink downstream to materialize it, then re-run.',
        icon: Icons.hourglass_empty_rounded,
      );
    }

    final items = output.items ?? const [];
    const renderCap = 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
          child: Row(
            children: [
              Text('${items.length} item${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700)),
              if (output.totalHits != null) ...[
                const SizedBox(width: 6),
                Text('of ~${output.totalHits}',
                    style: const TextStyle(color: _kMuted, fontSize: 11)),
              ],
              const Spacer(),
              if (items.isNotEmpty)
                TextButton.icon(
                  onPressed: () => widget.onDownloadItems(
                    items,
                    '${node.title.replaceAll(RegExp(r"[^\w\-]+"), "_")}.zip',
                  ),
                  icon: const Icon(Icons.archive_outlined, size: 15),
                  label: const Text('Download all',
                      style: TextStyle(fontSize: 11.5)),
                  style: TextButton.styleFrom(
                      foregroundColor: _kAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
            ],
          ),
        ),
        if (output.warning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: _kWarning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _kWarning.withValues(alpha: 0.4))),
              child: Text(output.warning!,
                  style: const TextStyle(
                      color: _kWarning, fontSize: 11, height: 1.4)),
            ),
          ),
        Expanded(
          child: items.isEmpty
              ? _centeredHint('No items matched at this stage.',
                  icon: Icons.filter_alt_off_outlined)
              : Column(
                  children: [
                    if (items.length > renderCap)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: Text(
                            'Showing the first $renderCap of ${items.length} — "Download all" still grabs every item.',
                            style: const TextStyle(
                                color: _kMuted, fontSize: 10.5)),
                      ),
                    Expanded(
                      child: MediaResultsGrid(
                        items: items,
                        itemLimit: renderCap,
                        searchState: const SearchState(),
                        extraParams: {
                          'from': 'pipeline',
                          'pipelineNode': node.id,
                        },
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.72,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _centeredHint(String text,
      {Color color = _kMuted, IconData icon = Icons.info_outline}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 10),
            Text(text,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 12, height: 1.5)),
          ],
        ),
      ),
    );
  }

  // ---- NOTES ----

  Widget _buildNotesTab(PipelineNode node, PipelineController controller) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NOTES',
              style: TextStyle(
                  color: _kMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2)),
          const SizedBox(height: 4),
          const Text(
              'Kept only in this pipeline — not part of the run, just for you.',
              style: TextStyle(color: _kMuted, fontSize: 10.5)),
          const SizedBox(height: 12),
          Expanded(
            child: _BufferedConfigTextField(
              key: ValueKey('note-${node.id}'),
              value: node.config['_note'] as String? ?? '',
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(
                  color: Colors.white, fontSize: 12.5, height: 1.5),
              decoration: InputDecoration(
                hintText:
                    'Why this node exists, a TODO, context for future-you…',
                hintStyle:
                    const TextStyle(color: Color(0xFF555566), fontSize: 12),
                filled: true,
                fillColor: _kFieldBg,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
              parse: (value) => value,
              onChanged: (value) => controller.updateNodeConfig(
                node.id,
                {...node.config, '_note': value},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeOverviewCard extends StatelessWidget {
  final PipelineNode node;
  final int inbound;
  final int outbound;

  const _NodeOverviewCard({
    required this.node,
    required this.inbound,
    required this.outbound,
  });

  @override
  Widget build(BuildContext context) {
    final color = _categoryColor(node.type.category);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _kFieldBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.42)),
                ),
                child: Text(
                  node.type.category.name.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const Spacer(),
              _TopologyStat(
                icon: Icons.login_rounded,
                value: '$inbound/${node.type.maxInputs}',
                tooltip: 'Connected inputs',
              ),
              const SizedBox(width: 10),
              _TopologyStat(
                icon: Icons.logout_rounded,
                value: outbound.toString(),
                tooltip: 'Connected outputs',
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            _nodeDescription(node.type),
            style: const TextStyle(
                color: Colors.white70, fontSize: 11.5, height: 1.45),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.data_object_rounded, size: 13, color: _kMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _nodeSummary(node),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopologyStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String tooltip;

  const _TopologyStat({
    required this.icon,
    required this.value,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _kMuted),
          const SizedBox(width: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final PipelineNodeStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status.status);
    final message = status.message ?? status.status.name;
    return Tooltip(
      message: message,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(message,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                      color: color,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Generic config field widgets — chip-based stringList editing and a
// segmented chip chooser for short dropdowns, so filter/source settings
// read as tappable pills rather than a bare comma-separated text box.
// -----------------------------------------------------------------------------

class _ConfigFieldWidget extends StatelessWidget {
  final PipelineNode node;
  final ConfigFieldSpec spec;
  final void Function(dynamic value) onChanged;
  const _ConfigFieldWidget(
      {super.key,
      required this.node,
      required this.spec,
      required this.onChanged});

  InputDecoration _decoration({String? hint}) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _kFieldBg,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF555566), fontSize: 11.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      );

  String _optionLabel(String value) {
    const labels = {
      'filtered': 'Filter results',
      'browse': 'Browse nearby',
      'any': 'Any quality',
      'qualityImage': 'Quality images',
      'valuedImage': 'Valued images',
      'featuredPicture': 'Featured pictures',
      'relevance': 'Relevance',
      'titleMatch': 'Title match',
      'newestEdited': 'Recently edited',
      'oldestEdited': 'Least recently edited',
      'newestCreated': 'Newest created',
      'oldestCreated': 'Oldest created',
      'created': 'Date created',
      'edited': 'Date edited',
    };
    return labels[value] ?? value;
  }

  Widget _labelText(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
      );

  @override
  Widget build(BuildContext context) {
    final current = node.config[spec.key];

    switch (spec.kind) {
      case ConfigFieldKind.bool:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: _kFieldBg, borderRadius: BorderRadius.circular(8)),
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: _kAccent,
            title: Text(spec.label,
                style: const TextStyle(color: Colors.white, fontSize: 12.5)),
            value: current as bool? ?? spec.defaultValue as bool? ?? false,
            onChanged: onChanged,
          ),
        );

      case ConfigFieldKind.dropdown:
        final options = spec.options ?? const [];
        final value =
            current as String? ?? (options.isNotEmpty ? options.first : '');
        if (options.length <= 4) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _labelText(spec.label),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: options.map((o) {
                  final selected = o == value;
                  return GestureDetector(
                    onTap: () => onChanged(o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? _kAccent.withValues(alpha: 0.18)
                            : _kFieldBg,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: selected ? _kAccent : _kBorder),
                      ),
                      child: Text(_optionLabel(o),
                          style: TextStyle(
                              color: selected ? _kAccent : Colors.white60,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelText(spec.label),
            DropdownButtonFormField<String>(
              dropdownColor: _kFieldBg,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: _decoration(),
              value: value.isEmpty ? null : value,
              items: options
                  .map((o) =>
                      DropdownMenuItem(value: o, child: Text(_optionLabel(o))))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ],
        );

      case ConfigFieldKind.multiChoice:
        return _MultiChoiceField(
          label: spec.label,
          options: spec.options ?? const [],
          selected: current is List
              ? current.map((e) => e.toString()).toSet()
              : <String>{},
          onChanged: onChanged,
        );

      case ConfigFieldKind.categoryList:
      case ConfigFieldKind.templateList:
        return _BrowseListField(
          label: spec.label,
          hint: spec.hint ?? 'Search and select',
          items: current is List
              ? current.map((e) => e.toString()).toList()
              : <String>[],
          categoryMode: spec.kind == ConfigFieldKind.categoryList,
          onChanged: onChanged,
        );

      case ConfigFieldKind.date:
        return _DateConfigField(
          label: spec.label,
          value: current as String?,
          onChanged: onChanged,
        );

      case ConfigFieldKind.stringList:
        final items = current is List
            ? current.map((e) => e.toString()).toList()
            : <String>[];
        return _StringListField(
          label: spec.label,
          hint: spec.hint,
          items: items,
          onChanged: onChanged,
        );

      case ConfigFieldKind.int:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelText(spec.label),
            _BufferedConfigTextField(
              value: current?.toString() ?? '',
              keyboardType: TextInputType.number,
              decoration: _decoration(hint: spec.hint),
              parse: int.tryParse,
              onChanged: onChanged,
            ),
          ],
        );

      case ConfigFieldKind.double:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelText(spec.label),
            _BufferedConfigTextField(
              value: current?.toString() ?? '',
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: _decoration(hint: spec.hint),
              parse: double.tryParse,
              onChanged: onChanged,
            ),
          ],
        );

      case ConfigFieldKind.text:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _labelText(spec.label),
            _BufferedConfigTextField(
              value: current as String? ?? '',
              decoration: _decoration(hint: spec.hint),
              parse: (value) => value,
              onChanged: onChanged,
            ),
          ],
        );
    }
  }
}

class _BufferedConfigTextField extends StatefulWidget {
  final String value;
  final TextInputType? keyboardType;
  final InputDecoration decoration;
  final dynamic Function(String value) parse;
  final void Function(dynamic value) onChanged;
  final int? maxLines;
  final bool expands;
  final TextAlignVertical? textAlignVertical;
  final TextStyle? style;

  const _BufferedConfigTextField({
    super.key,
    required this.value,
    required this.decoration,
    required this.parse,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.expands = false,
    this.textAlignVertical,
    this.style,
  });

  @override
  State<_BufferedConfigTextField> createState() =>
      _BufferedConfigTextFieldState();
}

class _BufferedConfigTextFieldState extends State<_BufferedConfigTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastCommittedText;

  @override
  void initState() {
    super.initState();
    _lastCommittedText = widget.value;
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _BufferedConfigTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _lastCommittedText = widget.value;
    }
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _saveNow();
  }

  void _saveNow() {
    final text = _controller.text;
    if (text == _lastCommittedText) return;
    _lastCommittedText = text;
    widget.onChanged(widget.parse(text));
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      expands: widget.expands,
      textAlignVertical: widget.textAlignVertical,
      style:
          widget.style ?? const TextStyle(color: Colors.white, fontSize: 12.5),
      decoration: widget.decoration,
      onSubmitted: (_) {
        _saveNow();
        _focusNode.unfocus();
      },
      onTapOutside: (_) => _focusNode.unfocus(),
    );
  }
}

class _MultiChoiceField extends StatelessWidget {
  final String label;
  final List<String> options;
  final Set<String> selected;
  final void Function(dynamic value) onChanged;

  const _MultiChoiceField({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  String _display(String value) {
    for (final preset in LicensePreset.values) {
      if (preset.name == value) return licensePresetLabel(preset);
    }
    return value.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in options)
              FilterChip(
                label: Text(_display(option)),
                selected: selected.contains(option),
                showCheckmark: true,
                checkmarkColor: _kAccent,
                selectedColor: _kAccent.withValues(alpha: 0.15),
                backgroundColor: _kFieldBg,
                side: BorderSide(
                    color: selected.contains(option) ? _kAccent : _kBorder),
                labelStyle: TextStyle(
                    color:
                        selected.contains(option) ? _kAccent : Colors.white70,
                    fontSize: 11),
                onSelected: (enabled) {
                  final next = {...selected};
                  enabled ? next.add(option) : next.remove(option);
                  onChanged(next.toList());
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _BrowseChoice {
  final String value;
  final String detail;
  const _BrowseChoice(this.value, this.detail);
}

class _BrowseListField extends ConsumerStatefulWidget {
  final String label;
  final String hint;
  final List<String> items;
  final bool categoryMode;
  final void Function(dynamic value) onChanged;

  const _BrowseListField({
    required this.label,
    required this.hint,
    required this.items,
    required this.categoryMode,
    required this.onChanged,
  });

  @override
  ConsumerState<_BrowseListField> createState() => _BrowseListFieldState();
}

class _BrowseListFieldState extends ConsumerState<_BrowseListField> {
  TextEditingController? _fieldController;
  final _requests = AutocompleteRequestCoordinator<_BrowseChoice>();

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

  Future<Iterable<_BrowseChoice>> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return const <_BrowseChoice>[];
    if (widget.categoryMode) {
      final result = await ref
          .read(commonsBackendProvider)
          .browseCategories(prefix: query);
      return result.items
          .take(30)
          .map((item) => _BrowseChoice(item.name, '${item.size} files'));
    }
    final result =
        await ref.read(commonsBackendProvider).browseTemplates(prefix: query);
    return result.items
        .take(30)
        .map((item) => _BrowseChoice(item, 'Commons template'));
  }

  void _remove(String value) =>
      widget.onChanged(widget.items.where((item) => item != value).toList());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in widget.items)
                InputChip(
                  label: Text(item),
                  onDeleted: () => _remove(item),
                  deleteIconColor: Colors.white54,
                  backgroundColor: _kChipBg,
                  side: BorderSide.none,
                  labelStyle:
                      const TextStyle(color: Colors.white, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Autocomplete<_BrowseChoice>(
          displayStringForOption: (option) => option.value,
          optionsBuilder: (value) => _requests.load(value.text, _search),
          onSelected: (choice) {
            _requests.cancel();
            if (!widget.items.contains(choice.value)) {
              widget.onChanged([...widget.items, choice.value]);
            }
            _fieldController?.clear();
          },
          fieldViewBuilder: (context, controller, focusNode, onComplete) {
            _fieldController = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _kFieldBg,
                hintText: widget.hint,
                hintStyle: const TextStyle(color: _kMuted, fontSize: 11.5),
                prefixIcon:
                    const Icon(Icons.search_rounded, size: 17, color: _kMuted),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: _kFieldBg,
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: 240, maxWidth: 360),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      dense: true,
                      title: Text(option.value,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12.5)),
                      subtitle: Text(option.detail,
                          style:
                              const TextStyle(color: _kMuted, fontSize: 10.5)),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateConfigField extends StatelessWidget {
  final String label;
  final String? value;
  final void Function(dynamic value) onChanged;

  const _DateConfigField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = value == null ? null : DateTime.tryParse(value!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: _kBorder),
            backgroundColor: _kFieldBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: parsed ?? DateTime.now(),
              firstDate: DateTime(1800),
              lastDate: DateTime.now(),
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(primary: _kAccent),
                ),
                child: child!,
              ),
            );
            if (date != null) {
              onChanged(date.toIso8601String().split('T').first);
            }
          },
          child: Row(
            children: [
              const Icon(Icons.calendar_month_outlined,
                  size: 17, color: _kAccent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(value ?? 'Choose date',
                    style: TextStyle(
                        color: value == null ? _kMuted : Colors.white,
                        fontSize: 12.5)),
              ),
              if (value != null)
                InkWell(
                  onTap: () => onChanged(null),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.white54),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Chip-based editor for a stringList config field — shows the current
/// values as removable chips, plus a single add-field, instead of one
/// comma-separated text box.
class _StringListField extends StatefulWidget {
  final String label;
  final String? hint;
  final List<String> items;
  final void Function(dynamic value) onChanged;
  const _StringListField(
      {required this.label,
      required this.hint,
      required this.items,
      required this.onChanged});

  @override
  State<_StringListField> createState() => _StringListFieldState();
}

class _StringListFieldState extends State<_StringListField> {
  final _ctrl = TextEditingController();

  void _add() {
    final v = _ctrl.text.trim();
    if (v.isEmpty) return;
    if (widget.items.contains(v)) {
      _ctrl.clear();
      return;
    }
    widget.onChanged([...widget.items, v]);
    _ctrl.clear();
  }

  void _remove(String v) =>
      widget.onChanged(widget.items.where((e) => e != v).toList());

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 8),
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.items
                .map((v) => Chip(
                      label: Text(v,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11)),
                      backgroundColor: _kChipBg,
                      deleteIconColor: Colors.white54,
                      onDeleted: () => _remove(v),
                      side: BorderSide.none,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint ?? 'Add value…',
            hintStyle:
                const TextStyle(color: Color(0xFF555566), fontSize: 11.5),
            filled: true,
            fillColor: _kFieldBg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
            suffixIcon: IconButton(
                icon: const Icon(Icons.add, size: 17, color: Colors.white54),
                onPressed: _add),
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    );
  }
}

/// Bespoke editor for Depicts/Statement sources' `entries` config. It reuses
/// the same live Wikidata entity/property lookup as the Browse experience,
/// while preserving QIDs in the saved graph for stable execution.
class _EntriesEditor extends ConsumerStatefulWidget {
  final PipelineNode node;
  const _EntriesEditor({required this.node});

  @override
  ConsumerState<_EntriesEditor> createState() => _EntriesEditorState();
}

class _EntriesEditorState extends ConsumerState<_EntriesEditor> {
  DepictsEntity? _pendingProperty;
  TextEditingController? _fieldController;
  final _requests = AutocompleteRequestCoordinator<DepictsEntity>();

  @override
  void didUpdateWidget(covariant _EntriesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _requests.cancel();
      _pendingProperty = null;
      _fieldController?.clear();
    }
  }

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

  List<dynamic> get _entries =>
      (widget.node.config['entries'] as List?)?.toList() ?? <dynamic>[];

  void _save(List<dynamic> entries) {
    ref.read(pipelineControllerProvider.notifier).updateNodeConfig(
      widget.node.id,
      {...widget.node.config, 'entries': entries},
    );
  }

  void _addDepicts(DepictsEntity entity) {
    final duplicate = _entries
        .whereType<Map>()
        .any((entry) => entry['qid']?.toString() == entity.qid);
    if (!duplicate) _save([..._entries, entity.toJson()]);
    _fieldController?.clear();
  }

  void _addStatement(DepictsEntity value) {
    final property = _pendingProperty;
    if (property == null) return;
    final duplicate = _entries.whereType<Map>().any((entry) {
      final p = entry['property'];
      final v = entry['value'];
      return p is Map &&
          v is Map &&
          p['qid'] == property.qid &&
          v['qid'] == value.qid;
    });
    if (!duplicate) {
      _save([
        ..._entries,
        {'property': property.toJson(), 'value': value.toJson()}
      ]);
    }
    setState(() => _pendingProperty = null);
    _fieldController?.clear();
  }

  String _entrySummary(dynamic entry, bool statement) {
    if (entry is! Map) return '?';
    if (!statement) {
      return (entry['label'] ?? entry['qid'] ?? '?').toString();
    }
    final property = entry['property'];
    final value = entry['value'];
    final p = property is Map ? (property['label'] ?? property['qid']) : '?';
    final v = value is Map ? (value['label'] ?? value['qid']) : '?';
    return '$p: $v';
  }

  Widget _entitySearch({
    required String hint,
    required bool propertySearch,
    required void Function(DepictsEntity) onSelected,
  }) {
    return Autocomplete<DepictsEntity>(
      key: ValueKey(propertySearch
          ? 'property'
          : _pendingProperty?.qid ?? 'depicts-value'),
      displayStringForOption: (option) => option.label,
      optionsBuilder: (value) {
        return _requests.load(value.text, (query) {
          return propertySearch
              ? ref.read(commonsAutocompleteProvider).wikidataProperties(query)
              : ref.read(commonsAutocompleteProvider).wikidataEntities(query);
        });
      },
      onSelected: (selection) {
        _requests.cancel();
        onSelected(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onComplete) {
        _fieldController = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _kFieldBg,
            hintText: hint,
            hintStyle: const TextStyle(color: _kMuted, fontSize: 11.5),
            prefixIcon:
                const Icon(Icons.search_rounded, size: 17, color: _kMuted),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: _kFieldBg,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 370),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options.elementAt(index);
                return ListTile(
                  dense: true,
                  title: Text(option.label,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12.5)),
                  subtitle: Text(
                    [
                      if (option.description?.isNotEmpty == true)
                        option.description!,
                      option.qid,
                    ].join(' - '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _kMuted, fontSize: 10.5),
                  ),
                  onTap: () => onSelected(option),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final statement = node.type == PipelineNodeType.sourceStatement;
    final entries = _entries;
    final controller = ref.read(pipelineControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(statement ? 'Wikidata statements' : 'Depicted subjects',
            style: const TextStyle(
                color: _kMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6)),
        const SizedBox(height: 5),
        Text(
          statement
              ? 'Search for a property by name, then choose its value. The Wikidata IDs are filled in automatically.'
              : 'Search for what the image should visually depict. Choose a labelled result; no Q-code knowledge is needed.',
          style: const TextStyle(color: _kMuted, fontSize: 10.5, height: 1.4),
        ),
        const SizedBox(height: 10),
        if (entries.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < entries.length; i++)
                InputChip(
                  avatar: Icon(
                    statement
                        ? Icons.data_object_rounded
                        : Icons.travel_explore_rounded,
                    size: 14,
                    color: _kAccent,
                  ),
                  label: Text(_entrySummary(entries[i], statement)),
                  labelStyle:
                      const TextStyle(color: Colors.white, fontSize: 11),
                  backgroundColor: _kChipBg,
                  deleteIconColor: Colors.white54,
                  side: BorderSide.none,
                  onDeleted: () => _save([...entries]..removeAt(i)),
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (!statement)
          _entitySearch(
            hint: 'Search subjects, e.g. skyscraper',
            propertySearch: false,
            onSelected: _addDepicts,
          )
        else ...[
          if (_pendingProperty != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kAccent.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      size: 15, color: _kAccent),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Property: ${_pendingProperty!.label}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _pendingProperty = null),
                    child:
                        const Text('Change', style: TextStyle(fontSize: 10.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          _entitySearch(
            hint: _pendingProperty == null
                ? '1. Search a property, e.g. location of creation'
                : '2. Search its value, e.g. London',
            propertySearch: _pendingProperty == null,
            onSelected: (entity) {
              if (_pendingProperty == null) {
                setState(() => _pendingProperty = entity);
                _fieldController?.clear();
              } else {
                _addStatement(entity);
              }
            },
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              color: _kFieldBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder)),
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: _kAccent,
            title: Text(
              node.config['union'] == true
                  ? 'Match any selected item (OR)'
                  : 'Match every selected item (AND)',
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
            subtitle: const Text('Combination mode',
                style: TextStyle(color: _kMuted, fontSize: 10.5)),
            value: node.config['union'] as bool? ?? false,
            onChanged: (value) => controller.updateNodeConfig(
              node.id,
              {...node.config, 'union': value},
            ),
          ),
        ),
      ],
    );
  }
}
