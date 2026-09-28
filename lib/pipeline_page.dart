/// Canvas page for the pipeline editor.
///
/// Package note: this project intentionally uses `arcane_nodes: ^1.0.2`.
/// Versions 1.0.3 and newer require Dart 3.7 through `artifact`, while the
/// current Flutter SDK provides Dart 3.6. Import the package through its
/// public `arcane_nodes.dart` entrypoint.
///
/// Architecture: [PipelineController]'s [PipelineGraph] is the single
/// source of truth (already fully built — Phases 0–3). This widget keeps
/// an `FlNodeEditorController` in sync with it in both directions:
///
/// - MODEL → CANVAS: a `ref.listen` on the graph diffs node/edge ids and
///   calls the fl_nodes controller's confirmed CRUD (`addNode`, `addLink`,
///   `removeNodeById`, `removeLinkById`) to match. Wrapped in
///   `_suppressFlEvents` so this doesn't echo back.
/// - CANVAS → MODEL: fl_nodes' `eventBus` fires on every user gesture
///   (drag a link, move a node, delete something). Rather than trust the
///   exact field layout of each event subtype (several of which aren't
///   fully confirmed), the handler just re-diffs the *confirmed* live
///   accessors (`nodes`, `linksById`, `selectedNodeIds`) against this
///   widget's own id-mapping table on any event at all — see
///   `_reconcileFromCanvas`.
///
/// Since fl_nodes generates its own node/link ids (not settable to ours),
/// `_ourIdToFlId`/`_flIdToOurId` and their edge equivalents are the
/// explicit bridge between the two id spaces.
///
/// VISUAL NOTE: the `arcane_nodes`/`fl_nodes` v1.x line this app is pinned
/// to renders each node's box itself — it does not expose a way to embed
/// arbitrary Flutter widgets *inside* a node on the canvas (confirmed
/// against the package's own successor's docs; see the project's
/// decisions log). So "widgets inside the node" is delivered here instead
/// as: (1) category-colored ports/links so a node's role is visible at a
/// glance on the canvas itself, (2) a live corner HUD, and, doing the
/// heaviest lifting, (3) a completely rebuilt inspector panel that turns
/// into a real per-node workspace — live status, an editable title, chip-
/// based settings, and, on every node type (not just Preview sinks), a
/// PREVIEW tab that renders that node's actual last-run output as a media
/// grid with instant per-item downloads plus a "download all" action.
library;

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:arcane_nodes/arcane_nodes.dart' as fln;
import 'package:go_router/go_router.dart';

import 'pipeline_controller.dart';
import 'pipeline_engine.dart';
import 'pipeline_models.dart';
import 'search_components.dart';
import 'search_models.dart';
import 'bulk_download_tray.dart';
import 'search_service.dart';

// -----------------------------------------------------------------------------
// Page palette. The surrounding editor follows the same restrained neutral
// surfaces and blue accent as the rest of Commons Lens. Category colors are
// deliberately reserved for the canvas, where they communicate graph roles.
// -----------------------------------------------------------------------------

const Color _kBg = Color(0xFF0B0B0B);
const Color _kPanelBg = Color(0xFF111111);
const Color _kFieldBg = Color(0xFF1A1A1A);
const Color _kChipBg = Color(0xFF1E1E1E);
const Color _kBorder = Color(0xFF242424);
const Color _kAccent = Color(0xFF3D7EFF);
const Color _kMuted = Color(0xFF7A7A7A);
const Color _kError = Color(0xFFFF6B6B);
const Color _kWarning = Color(0xFFE0B84C);
const Color _kSuccess = Color(0xFF3DDC97);

Color _categoryColor(PipelineNodeCategory c) {
  switch (c) {
    case PipelineNodeCategory.source:
      return const Color(0xFF3DDC97);
    case PipelineNodeCategory.filter:
      return const Color(0xFF3D9BFF);
    case PipelineNodeCategory.setOp:
      return const Color(0xFFFFA53D);
    case PipelineNodeCategory.transform:
      return const Color(0xFFB36DFF);
    case PipelineNodeCategory.sink:
      return const Color(0xFFFF5D8F);
  }
}

IconData _categoryIcon(PipelineNodeCategory c) {
  switch (c) {
    case PipelineNodeCategory.source:
      return Icons.input_rounded;
    case PipelineNodeCategory.filter:
      return Icons.filter_alt_rounded;
    case PipelineNodeCategory.setOp:
      return Icons.call_merge_rounded;
    case PipelineNodeCategory.transform:
      return Icons.auto_fix_high_rounded;
    case PipelineNodeCategory.sink:
      return Icons.output_rounded;
  }
}

IconData _nodeTypeIcon(PipelineNodeType type) {
  switch (type) {
    case PipelineNodeType.sourceTextQuery:
      return Icons.text_fields_rounded;
    case PipelineNodeType.sourceCategory:
      return Icons.category_rounded;
    case PipelineNodeType.sourceDepicts:
      return Icons.travel_explore_rounded;
    case PipelineNodeType.sourceStatement:
      return Icons.data_object_rounded;
    case PipelineNodeType.sourceTemplate:
      return Icons.article_rounded;
    case PipelineNodeType.sourceGeosearch:
      return Icons.location_on_rounded;
    case PipelineNodeType.sourceAuthor:
      return Icons.person_rounded;
    case PipelineNodeType.sourceMorelike:
      return Icons.compare_rounded;
    case PipelineNodeType.filterLicense:
      return Icons.copyright_rounded;
    case PipelineNodeType.filterQuality:
      return Icons.verified_rounded;
    case PipelineNodeType.filterFormat:
      return Icons.perm_media_rounded;
    case PipelineNodeType.filterResolution:
      return Icons.photo_size_select_large_rounded;
    case PipelineNodeType.filterFileSize:
      return Icons.sd_storage_rounded;
    case PipelineNodeType.filterColorDepth:
      return Icons.gradient_rounded;
    case PipelineNodeType.filterDateRange:
      return Icons.date_range_rounded;
    case PipelineNodeType.filterLanguage:
      return Icons.language_rounded;
    case PipelineNodeType.filterExcludeTerms:
      return Icons.block_rounded;
    case PipelineNodeType.setCombineAnd:
      return Icons.merge_type_rounded;
    case PipelineNodeType.setUnion:
      return Icons.join_full_rounded;
    case PipelineNodeType.setIntersect:
      return Icons.join_inner_rounded;
    case PipelineNodeType.setDifference:
      return Icons.join_left_rounded;
    case PipelineNodeType.transformDedupe:
      return Icons.filter_none_rounded;
    case PipelineNodeType.transformSort:
      return Icons.sort_rounded;
    case PipelineNodeType.transformSample:
      return Icons.shuffle_rounded;
    case PipelineNodeType.transformFieldSelect:
      return Icons.view_column_rounded;
    case PipelineNodeType.transformEnrich:
      return Icons.auto_awesome_rounded;
    case PipelineNodeType.sinkCsvExport:
      return Icons.table_chart_rounded;
    case PipelineNodeType.sinkJsonExport:
      return Icons.data_object_rounded;
    case PipelineNodeType.sinkZipExport:
      return Icons.folder_zip_rounded;
    case PipelineNodeType.sinkPreview:
      return Icons.visibility_rounded;
    case PipelineNodeType.sinkSendToSearch:
      return Icons.send_rounded;
  }
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

Color _statusColor(NodeRunStatus status) {
  switch (status) {
    case NodeRunStatus.error:
      return _kError;
    case NodeRunStatus.warning:
      return _kWarning;
    case NodeRunStatus.success:
      return _kSuccess;
    case NodeRunStatus.running:
      return _kAccent;
    case NodeRunStatus.idle:
      return _kMuted;
  }
}

// -----------------------------------------------------------------------------
// Node prototypes — one per PipelineNodeType, built once. No FieldPrototypes
// here: config editing lives entirely in this file's own inspector panel
// (PipelineNode.config, via PipelineController.updateNodeConfig), not in
// fl_nodes' own field/data system — the whole reason the inspector-panel
// option was picked over fl_nodes_v2. Ports are colored per category so a
// node's role reads at a glance on the canvas itself.
// -----------------------------------------------------------------------------

String _nodeDescription(PipelineNodeType type) {
  switch (type) {
    case PipelineNodeType.sourceTextQuery:
      return 'Starts a Commons full-text search. Combine it with other sources to build a more precise request.';
    case PipelineNodeType.sourceCategory:
      return 'Finds files in Commons categories, with optional recursive subcategory matching.';
    case PipelineNodeType.sourceDepicts:
      return 'Finds media whose structured data depicts subjects selected by name.';
    case PipelineNodeType.sourceStatement:
      return 'Finds media with selected Wikidata property/value statements.';
    case PipelineNodeType.sourceTemplate:
      return 'Finds files that transclude one or more Commons templates.';
    case PipelineNodeType.sourceGeosearch:
      return 'Finds media near a latitude and longitude within a radius.';
    case PipelineNodeType.sourceAuthor:
      return 'Finds files uploaded by a Commons user.';
    case PipelineNodeType.sourceMorelike:
      return 'Finds media related to an existing Commons file.';
    case PipelineNodeType.setCombineAnd:
      return 'Combines two query branches as AND constraints before fetching, ideal for text plus depicts.';
    case PipelineNodeType.setUnion:
      return 'Keeps items present in either input branch.';
    case PipelineNodeType.setIntersect:
      return 'Keeps only items present in both materialized branches.';
    case PipelineNodeType.setDifference:
      return 'Keeps items from A that are not present in B.';
    case PipelineNodeType.transformDedupe:
      return 'Removes duplicate media items by URL.';
    case PipelineNodeType.transformSort:
      return 'Reorders the incoming media set using the selected sort mode.';
    case PipelineNodeType.transformSample:
      return 'Optionally shuffles, then limits the number of incoming items.';
    case PipelineNodeType.sinkPreview:
      return 'Materializes the branch so its media can be browsed in the Preview tab.';
    case PipelineNodeType.sinkSendToSearch:
      return 'Sends this branch to the main search workspace.';
    case PipelineNodeType.sinkCsvExport:
    case PipelineNodeType.sinkJsonExport:
    case PipelineNodeType.sinkZipExport:
      return 'Materializes this branch and exports its media or metadata.';
    default:
      return type.category == PipelineNodeCategory.filter
          ? 'Narrows the incoming media set using this filter.'
          : 'Processes the incoming media set at this point in the pipeline.';
  }
}

String _nodeSummary(PipelineNode node) {
  final c = node.config;
  String joined(String key) {
    final values = c[key];
    if (values is! List || values.isEmpty) return '';
    return '${values.take(2).join(', ')}${values.length > 2 ? ' +${values.length - 2}' : ''}';
  }

  switch (node.type) {
    case PipelineNodeType.sourceTextQuery:
      final query = (c['query'] as String?)?.trim() ?? '';
      return query.isEmpty ? 'Enter a search query' : query;
    case PipelineNodeType.sourceCategory:
      return joined('categories').isEmpty
          ? 'Choose categories'
          : joined('categories');
    case PipelineNodeType.sourceTemplate:
      return joined('templates').isEmpty
          ? 'Choose templates'
          : joined('templates');
    case PipelineNodeType.sourceDepicts:
    case PipelineNodeType.sourceStatement:
      final entries = c['entries'];
      if (entries is! List || entries.isEmpty) return 'Choose subjects';
      String label(dynamic entry) {
        if (entry is! Map) return '?';
        if (node.type == PipelineNodeType.sourceDepicts) {
          return (entry['label'] ?? entry['qid'] ?? '?').toString();
        }
        final property = entry['property'];
        final value = entry['value'];
        final p =
            property is Map ? (property['label'] ?? property['qid']) : '?';
        final v = value is Map ? (value['label'] ?? value['qid']) : '?';
        return '$p: $v';
      }
      return '${entries.take(2).map(label).join(', ')}${entries.length > 2 ? ' +${entries.length - 2}' : ''}';
    case PipelineNodeType.sourceGeosearch:
      return c['lat'] == null || c['lng'] == null
          ? 'Set a location'
          : '${c['lat']}, ${c['lng']} - ${c['radiusKm'] ?? 10} km';
    case PipelineNodeType.filterLicense:
      return joined('licenses').isEmpty ? 'Any license' : joined('licenses');
    case PipelineNodeType.filterFormat:
      return joined('formats').isEmpty
          ? 'Any format'
          : joined('formats').toUpperCase();
    case PipelineNodeType.filterQuality:
      return (c['quality'] ?? 'Any quality').toString();
    case PipelineNodeType.filterDateRange:
      return '${c['from'] ?? 'Any date'} to ${c['to'] ?? 'today'}';
    case PipelineNodeType.transformSort:
      return (c['sortMode'] ?? 'relevance').toString();
    case PipelineNodeType.sourceAuthor:
      return (c['username'] as String?)?.trim().isNotEmpty == true
          ? c['username'].toString()
          : 'Choose an uploader';
    case PipelineNodeType.sourceMorelike:
      return (c['title'] as String?)?.trim().isNotEmpty == true
          ? c['title'].toString()
          : 'Choose a Commons file';
    case PipelineNodeType.filterResolution:
      final min = c['minWidth'] == null && c['minHeight'] == null
          ? 'no minimum'
          : '${c['minWidth'] ?? 0} x ${c['minHeight'] ?? 0} px';
      final max = c['maxWidth'] == null && c['maxHeight'] == null
          ? 'no maximum'
          : '${c['maxWidth'] ?? 'any'} x ${c['maxHeight'] ?? 'any'} px';
      return '$min to $max';
    case PipelineNodeType.filterFileSize:
      return '${c['minBytes'] ?? 0} to ${c['maxBytes'] ?? 'any'} bytes';
    case PipelineNodeType.filterColorDepth:
      return c['bits'] == null ? 'Any color depth' : '${c['bits']}-bit';
    case PipelineNodeType.filterLanguage:
      return c['language'] == null
          ? 'Any language'
          : 'Language: ${c['language']}';
    case PipelineNodeType.filterExcludeTerms:
      return joined('terms').isEmpty ? 'No excluded terms' : joined('terms');
    case PipelineNodeType.transformSample:
      return 'Limit ${c['limit'] ?? 'not set'}${c['shuffle'] == true ? ' - shuffled' : ''}';
    case PipelineNodeType.sinkCsvExport:
    case PipelineNodeType.sinkJsonExport:
      return (c['fileName'] ?? 'pipeline_export').toString();
    case PipelineNodeType.sinkZipExport:
      return (c['zipName'] ?? 'pipeline_export.zip').toString() +
          (c['fullRes'] == false ? ' - previews' : ' - full resolution');
    case PipelineNodeType.setCombineAnd:
      return 'A + B before fetch';
    case PipelineNodeType.setUnion:
      return 'A or B';
    case PipelineNodeType.setIntersect:
      return 'A and B only';
    case PipelineNodeType.setDifference:
      return 'A minus B';
    case PipelineNodeType.transformDedupe:
      return 'Remove duplicate files';
    case PipelineNodeType.sinkPreview:
      return 'Browse output';
    case PipelineNodeType.sinkSendToSearch:
      return 'Open in Search';
    default:
      return node.type.label;
  }
}

fln.FlPortStyle Function(fln.PortState) _flPortStyleFor(Color color) {
  return (fln.PortState state) => fln.FlPortStyle(
        color: state.isHovered ? const Color(0xFFFFFFFF) : color,
        radius: 7,
        linkStyleBuilder: (_) => fln.FlLinkStyle(
          color: color,
          lineWidth: 3,
          drawMode: fln.FlLineDrawMode.solid,
          curveType: fln.FlLinkCurveType.bezier,
        ),
      );
}

dynamic _flPortsFor(PipelineNodeType type) {
  final color = _categoryColor(type.category);
  return defaultPortsFor(type).map((p) {
    return p.direction == PipelinePortDirection.input
        ? fln.DataInputPortPrototype(
            idName: p.id,
            displayName: p.label,
            styleBuilder: _flPortStyleFor(color),
          )
        : fln.DataOutputPortPrototype(
            idName: p.id,
            displayName: p.label,
            styleBuilder: _flPortStyleFor(color),
          );
    // dataType deliberately left at its default (dynamic) — every port
    // here carries the same conceptual payload (a MediaSet), and
    // addLink's own compatibility check short-circuits to "compatible"
    // whenever either side is dynamic, so there's no type-mismatch risk
    // to guard against.
  }).toList();
}

Map<String, fln.NodePrototype> _buildNodePrototypes() {
  return {
    for (final type in PipelineNodeType.values)
      type.name: fln.NodePrototype(
        idName: type.name,
        displayName: type.label,
        description: type.category.name,
        styleBuilder: (state) {
          final color = _categoryColor(type.category);
          return fln.FlNodeStyle(
            decoration: BoxDecoration(
              color: const Color(0xFF242424),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: color.withValues(alpha: state.isSelected ? 1 : 0.72),
                width: state.isSelected ? 2 : 1,
              ),
            ),
          );
        },
        headerStyleBuilder: (state) {
          final color = _categoryColor(type.category);
          return fln.defaultNodeHeaderStyle(state).copyWith(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(9),
                    topRight: const Radius.circular(9),
                    bottomLeft: Radius.circular(state.isCollapsed ? 9 : 0),
                    bottomRight: Radius.circular(state.isCollapsed ? 9 : 0),
                  ),
                ),
              );
        },
        ports: _flPortsFor(type),
        // The app runs PipelineEngine instead of arcane_nodes' graph runner,
        // so the required package callback is intentionally a no-op.
        onExecute: (ports, fields, execState, forward, put) async {},
      ),
  };
}

// -----------------------------------------------------------------------------
// Inspector field spec — a lightweight per-node-type schema so one generic
// form builder covers every node type instead of ~20 hand-written forms.
// Depicts/Statement sources use a bespoke entries editor instead (their
// config shape — a list of qid/label pairs — doesn't fit a flat spec), same
// as advanced_filters_drawer.dart treats those as dedicated pickers rather
// than plain text fields.
// -----------------------------------------------------------------------------

enum ConfigFieldKind {
  text,
  int,
  double,
  bool,
  stringList,
  dropdown,
  multiChoice,
  categoryList,
  templateList,
  date,
}

class ConfigFieldSpec {
  final String key;
  final String label;
  final ConfigFieldKind kind;
  final List<String>? options;
  final String? hint;
  final dynamic defaultValue;

  const ConfigFieldSpec({
    required this.key,
    required this.label,
    required this.kind,
    this.options,
    this.hint,
    this.defaultValue,
  });
}

List<ConfigFieldSpec> configSpecFor(PipelineNodeType type) {
  const cf = ConfigFieldSpec.new;
  switch (type) {
    case PipelineNodeType.sourceTextQuery:
      return [
        cf(key: 'query', label: 'Query text', kind: ConfigFieldKind.text)
      ];
    case PipelineNodeType.sourceCategory:
      return [
        cf(
            key: 'categories',
            label: 'Categories',
            kind: ConfigFieldKind.categoryList,
            hint: 'Search categories, e.g. Architecture'),
        cf(
            key: 'union',
            label: 'Union (OR) instead of AND',
            kind: ConfigFieldKind.bool),
        cf(
            key: 'deep',
            label: 'Include subcategories',
            kind: ConfigFieldKind.bool),
      ];
    case PipelineNodeType.sourceTemplate:
      return [
        cf(
            key: 'templates',
            label: 'Templates',
            kind: ConfigFieldKind.templateList,
            hint: 'Search templates, e.g. PD-USGov')
      ];
    case PipelineNodeType.sourceMorelike:
      return [
        cf(
            key: 'title',
            label: 'File title',
            kind: ConfigFieldKind.text,
            hint: 'File:Example.jpg')
      ];
    case PipelineNodeType.sourceAuthor:
      return [
        cf(
            key: 'username',
            label: 'Uploader username',
            kind: ConfigFieldKind.text)
      ];
    case PipelineNodeType.sourceGeosearch:
      return [
        cf(
            key: 'mode',
            label: 'Mode',
            kind: ConfigFieldKind.dropdown,
            options: ['filtered', 'browse']),
        cf(key: 'lat', label: 'Latitude', kind: ConfigFieldKind.double),
        cf(key: 'lng', label: 'Longitude', kind: ConfigFieldKind.double),
        cf(key: 'radiusKm', label: 'Radius (km)', kind: ConfigFieldKind.double),
      ];
    case PipelineNodeType.filterLicense:
      return [
        cf(
            key: 'licenses',
            label: 'Licenses',
            kind: ConfigFieldKind.multiChoice,
            options: ['cc0', 'ccBy4', 'ccBySa4', 'publicDomain'])
      ];
    case PipelineNodeType.filterQuality:
      return [
        cf(
            key: 'quality',
            label: 'Quality',
            kind: ConfigFieldKind.dropdown,
            options: ['any', 'qualityImage', 'valuedImage', 'featuredPicture'])
      ];
    case PipelineNodeType.filterFormat:
      return [
        cf(
            key: 'formats',
            label: 'Formats',
            kind: ConfigFieldKind.multiChoice,
            options: [
              'jpg',
              'jpeg',
              'png',
              'svg',
              'gif',
              'tif',
              'tiff',
              'webp',
              'pdf',
              'djvu',
              'ogg',
              'oga',
              'ogv',
              'mp3',
              'wav',
              'webm',
              'mp4'
            ])
      ];
    case PipelineNodeType.filterResolution:
      return [
        cf(key: 'minWidth', label: 'Min width (px)', kind: ConfigFieldKind.int),
        cf(
            key: 'minHeight',
            label: 'Min height (px)',
            kind: ConfigFieldKind.int),
        cf(key: 'maxWidth', label: 'Max width (px)', kind: ConfigFieldKind.int),
        cf(
            key: 'maxHeight',
            label: 'Max height (px)',
            kind: ConfigFieldKind.int),
      ];
    case PipelineNodeType.filterFileSize:
      return [
        cf(
            key: 'minBytes',
            label: 'Min size (bytes)',
            kind: ConfigFieldKind.int),
        cf(
            key: 'maxBytes',
            label: 'Max size (bytes)',
            kind: ConfigFieldKind.int),
      ];
    case PipelineNodeType.filterColorDepth:
      return [
        cf(key: 'bits', label: 'Color depth (bits)', kind: ConfigFieldKind.int)
      ];
    case PipelineNodeType.filterDateRange:
      return [
        cf(
            key: 'field',
            label: 'Field',
            kind: ConfigFieldKind.dropdown,
            options: ['created', 'edited']),
        cf(key: 'from', label: 'From date', kind: ConfigFieldKind.date),
        cf(key: 'to', label: 'To date', kind: ConfigFieldKind.date),
      ];
    case PipelineNodeType.filterLanguage:
      return [
        cf(
            key: 'language',
            label: 'Language code',
            kind: ConfigFieldKind.text,
            hint: 'en')
      ];
    case PipelineNodeType.filterExcludeTerms:
      return [
        cf(
            key: 'terms',
            label: 'Exclude terms',
            kind: ConfigFieldKind.stringList,
            hint: 'Type a term, press enter')
      ];
    case PipelineNodeType.transformSort:
      return [
        cf(
            key: 'sortMode',
            label: 'Sort by',
            kind: ConfigFieldKind.dropdown,
            options: [
              'relevance',
              'titleMatch',
              'newestEdited',
              'oldestEdited',
              'newestCreated',
              'oldestCreated',
            ])
      ];
    case PipelineNodeType.transformSample:
      return [
        cf(key: 'limit', label: 'Limit', kind: ConfigFieldKind.int),
        cf(
            key: 'shuffle',
            label: 'Shuffle before limiting',
            kind: ConfigFieldKind.bool),
      ];
    case PipelineNodeType.transformFieldSelect:
      return [
        cf(
          key: 'fields',
          label: 'Export fields',
          kind: ConfigFieldKind.multiChoice,
          options: [
            'title',
            'url',
            'thumb',
            'commonsUrl',
            'snippet',
            'mime',
            'timestamp',
            'artistHtml',
            'licenseShortName',
            'licenseUrl',
            'dateTimeOriginal',
            'uploader',
            'width',
            'height',
            'categories',
            'assessments',
            'objectName',
            'usageTerms',
            'uploadDateTime',
            'latitude',
            'longitude',
            'structuredData',
            'globalUsage',
            'globalUsageCount',
          ],
        ),
      ];
    case PipelineNodeType.transformEnrich:
      return [
        cf(
          key: 'structuredData',
          label: 'Structured Data on Commons',
          kind: ConfigFieldKind.bool,
          defaultValue: true,
        ),
        cf(
          key: 'globalUsage',
          label: 'Global Wikimedia usage',
          kind: ConfigFieldKind.bool,
          defaultValue: true,
        ),
        cf(
          key: 'maxEnrich',
          label: 'Maximum items to enrich',
          kind: ConfigFieldKind.int,
          hint: '20',
        ),
        cf(
          key: 'usageLimit',
          label: 'Usage pages per item',
          kind: ConfigFieldKind.int,
          hint: '50',
        ),
      ];
    case PipelineNodeType.sinkCsvExport:
    case PipelineNodeType.sinkJsonExport:
      return [
        cf(key: 'fileName', label: 'File name', kind: ConfigFieldKind.text)
      ];
    case PipelineNodeType.sinkZipExport:
      return [
        cf(key: 'zipName', label: 'Zip file name', kind: ConfigFieldKind.text),
        cf(
            key: 'fullRes',
            label: 'Full resolution',
            kind: ConfigFieldKind.bool),
      ];
    default:
      // sourceDepicts / sourceStatement (bespoke entries editor below),
      // setUnion/setIntersect/setDifference (no config, just two inputs),
      // transformDedupe (no config),
      // sinkPreview/sinkSendToSearch (no config — see the PREVIEW tab).
      return const [];
  }
}

// -----------------------------------------------------------------------------
// Page
// -----------------------------------------------------------------------------

class PipelinePage extends ConsumerStatefulWidget {
  const PipelinePage({super.key});

  @override
  ConsumerState<PipelinePage> createState() => _PipelinePageState();
}

class _PipelinePageState extends ConsumerState<PipelinePage> {
  String? _selectedNodeId;
  final _downloadTrayKey = GlobalKey<BulkDownloadTrayState>();

  void _leavePipeline() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  void _handleRun({required bool preview}) async {
    await ref.read(pipelineControllerProvider.notifier).run(preview: preview);
    final error = ref.read(pipelineControllerProvider).runError;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _handleSinkResult(String? error) {
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _startPipelineDownload(List<SearchItem> items, String zipName) {
    _downloadTrayKey.currentState?.startDownload(items, zipName: zipName);
  }

  void _handleSendToSearch(String nodeId) {
    final error =
        ref.read(pipelineControllerProvider.notifier).sendToSearch(nodeId);
    if (error != null) {
      _handleSinkResult(error);
      return;
    }
    _leavePipeline();
  }

  void _showRenameDialog() {
    final current = ref.read(pipelineControllerProvider).graph.name;
    final ctrl = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _kPanelBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Rename pipeline',
            style: TextStyle(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: _kFieldBg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final name = ctrl.text.trim();
              ref
                  .read(pipelineControllerProvider.notifier)
                  .renameGraph(name.isEmpty ? 'Untitled Pipeline' : name);
              Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSavedGraphsDialog() {
    ref.read(pipelineControllerProvider.notifier).refreshSavedGraphs();
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: _kPanelBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 480),
          child: Consumer(builder: (context, ref, _) {
            final s = ref.watch(pipelineControllerProvider);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_open_rounded,
                          color: _kAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text('Saved pipelines',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.white54, size: 18),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                const Divider(color: _kBorder, height: 1),
                if (s.loadingSavedGraphs)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kAccent)),
                  )
                else if (s.savedGraphs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'No saved pipelines yet — every edit here autosaves as you go, and shows up in this list.',
                        style: TextStyle(
                            color: _kMuted, fontSize: 12, height: 1.5)),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: s.savedGraphs.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: _kBorder, height: 1),
                      itemBuilder: (context, i) {
                        final g = s.savedGraphs[i];
                        final isCurrent = g.id == s.graph.id;
                        return ListTile(
                          dense: true,
                          selected: isCurrent,
                          selectedTileColor: _kAccent.withValues(alpha: 0.08),
                          title: Text(g.name,
                              style: TextStyle(
                                  color: isCurrent ? _kAccent : Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${g.nodes.length} nodes · ${g.edges.length} edges · ${_relativeTime(g.updatedAt)}',
                              style: const TextStyle(
                                  color: _kMuted, fontSize: 10.5)),
                          onTap: () {
                            ref
                                .read(pipelineControllerProvider.notifier)
                                .loadGraph(g.id);
                            Navigator.pop(dialogContext);
                          },
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline,
                                size: 17, color: _kError),
                            onPressed: () => ref
                                .read(pipelineControllerProvider.notifier)
                                .deleteGraph(g.id),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            );
          }),
        ),
      ),
    );
  }

  void _exportGraphJson() {
    final graph = ref.read(pipelineControllerProvider).graph;
    final jsonStr = const JsonEncoder.withIndent('  ').convert(graph.toJson());
    final bytes = utf8.encode(jsonStr);
    final blob = html.Blob([bytes], 'application/json');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final safeName = graph.name.replaceAll(RegExp(r'[^\w\-]+'), '_');
    html.AnchorElement(href: url)
      ..setAttribute('download',
          '${safeName.isEmpty ? "pipeline" : safeName}.pipeline.json')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  void _importGraphJson() {
    final input = html.FileUploadInputElement()
      ..accept = '.json,application/json';
    input.click();
    input.onChange.listen((_) {
      final file = input.files?.isNotEmpty == true ? input.files!.first : null;
      if (file == null) return;
      final reader = html.FileReader();
      reader.readAsText(file);
      reader.onLoadEnd.listen((_) {
        try {
          final text = reader.result as String;
          final json = jsonDecode(text) as Map<String, dynamic>;
          ref.read(pipelineControllerProvider.notifier).importGraph(json);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Could not read that pipeline file — is it valid JSON exported from here?')));
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pipelineControllerProvider);
    final controller = ref.read(pipelineControllerProvider.notifier);
    final selectedOutput = _selectedNodeId == null
        ? const <SearchItem>[]
        : controller.materializedItemsFor(_selectedNodeId!) ??
            const <SearchItem>[];

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: BulkDownloadTray(
        key: _downloadTrayKey,
        availableItems: selectedOutput,
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close pipeline',
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: _leavePipeline,
        ),
        backgroundColor: _kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        shape: const Border(bottom: BorderSide(color: _kBorder)),
        title: GestureDetector(
          onTap: _showRenameDialog,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.graph.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700)),
                  Text(
                    '${state.graph.nodes.length} nodes  ·  ${state.graph.edges.length} edges'
                    '${state.preview ? "  ·  preview mode" : ""}',
                    style: const TextStyle(color: _kMuted, fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Preview run (capped sample)',
            icon: const Icon(Icons.visibility_outlined, color: Colors.white70),
            onPressed: state.isRunning ? null : () => _handleRun(preview: true),
          ),
          IconButton(
            tooltip: 'Run',
            icon: state.isRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _kAccent))
                : const Icon(Icons.play_arrow, color: _kAccent),
            onPressed:
                state.isRunning ? null : () => _handleRun(preview: false),
          ),
          IconButton(
            tooltip: 'Saved pipelines',
            icon: const Icon(Icons.folder_open_rounded,
                color: Colors.white70, size: 20),
            onPressed: _showSavedGraphsDialog,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            color: _kPanelBg,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  controller.newGraph();
                  break;
                case 'rename':
                  _showRenameDialog();
                  break;
                case 'export':
                  _exportGraphJson();
                  break;
                case 'import':
                  _importGraphJson();
                  break;
                case 'clear_cache':
                  controller.clearCache();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'new',
                  child: Text('New pipeline',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
              PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename…',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'export',
                  child: Text('Export as JSON',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
              PopupMenuItem(
                  value: 'import',
                  child: Text('Import from JSON',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
              PopupMenuDivider(),
              PopupMenuItem(
                  value: 'clear_cache',
                  child: Text('Clear cache',
                      style: TextStyle(color: Colors.white, fontSize: 13))),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 240,
            child: _Palette(
                onAdd: (type) => controller.addNode(type,
                    x: 80.0 + 40 * (state.graph.nodes.length % 8),
                    y: 80.0 + 70 * (state.graph.nodes.length ~/ 8))),
          ),
          const VerticalDivider(width: 1, color: _kBorder),
          Expanded(
            child: _PipelineCanvas(
              onSelectionChanged: (id) => setState(() => _selectedNodeId = id),
            ),
          ),
          const VerticalDivider(width: 1, color: _kBorder),
          SizedBox(
            width: 380,
            child: _InspectorPanel(
              nodeId: _selectedNodeId,
              onSinkResult: _handleSinkResult,
              onSendToSearch: _handleSendToSearch,
              onDownloadItems: _startPipelineDownload,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Palette — searchable and grouped by category. It stays neutral/blue like
// the rest of the app; category colors begin only once a node hits the canvas.
// -----------------------------------------------------------------------------

class _Palette extends StatefulWidget {
  final void Function(PipelineNodeType type) onAdd;
  const _Palette({required this.onAdd});

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final byCategory = <PipelineNodeCategory, List<PipelineNodeType>>{};
    for (final type in PipelineNodeType.values) {
      if (_query.isNotEmpty &&
          !type.label.toLowerCase().contains(_query.toLowerCase())) {
        continue;
      }
      byCategory.putIfAbsent(type.category, () => []).add(type);
    }

    return Container(
      color: _kPanelBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: _kFieldBg,
                hintText: 'Search nodes…',
                hintStyle: const TextStyle(color: _kMuted, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: _kMuted),
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: byCategory.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No matching nodes.',
                        style: TextStyle(color: _kMuted, fontSize: 12)),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final entry in byCategory.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                          child: Row(
                            children: [
                              Icon(_categoryIcon(entry.key),
                                  size: 13, color: _kMuted),
                              const SizedBox(width: 6),
                              Text(entry.key.name.toUpperCase(),
                                  style: const TextStyle(
                                      color: _kMuted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2)),
                            ],
                          ),
                        ),
                        for (final type in entry.value)
                          _PaletteTile(
                            type: type,
                            onTap: () => widget.onAdd(type),
                          ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaletteTile extends StatefulWidget {
  final PipelineNodeType type;
  final VoidCallback onTap;
  const _PaletteTile({required this.type, required this.onTap});

  @override
  State<_PaletteTile> createState() => _PaletteTileState();
}

class _PaletteTileState extends State<_PaletteTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: _hovered ? _kFieldBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _hovered ? _kBorder : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(_nodeTypeIcon(widget.type),
                  size: 15, color: _hovered ? _kAccent : Colors.white54),
              const SizedBox(width: 9),
              Expanded(
                child: Text(widget.type.label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500)),
              ),
              Icon(Icons.add_circle_outline,
                  size: 14, color: _hovered ? _kAccent : Colors.transparent),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Canvas — the fl_nodes / PipelineController bridge.
// -----------------------------------------------------------------------------

class _PipelineCanvas extends ConsumerStatefulWidget {
  final void Function(String? selectedOurNodeId) onSelectionChanged;
  const _PipelineCanvas({required this.onSelectionChanged});

  @override
  ConsumerState<_PipelineCanvas> createState() => _PipelineCanvasState();
}

class _PipelineCanvasState extends ConsumerState<_PipelineCanvas> {
  late final fln.FlNodeEditorController _flController;
  bool _suppressFlEvents = false;

  final Map<String, String> _ourNodeIdToFlId = {};
  final Map<String, String> _flIdToOurNodeId = {};
  final Map<String, String> _ourEdgeIdToFlLinkId = {};
  final Map<String, String> _flLinkIdToOurEdgeId = {};

  @override
  void initState() {
    super.initState();
    _flController = fln.FlNodeEditorController();
    // Version 1.0.2 does not initialize its detail level from the initial zoom.
    _flController.updateViewportZoomFromUI(1.0);
    for (final prototype in _buildNodePrototypes().values) {
      _flController.registerNodePrototype(prototype);
    }
    _flController.eventBus.events.listen(_handleAnyFlEvent);

    // Initial sync — mirror whatever the controller already has (e.g. a
    // graph loaded from IndexedDB before this widget existed).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncModelToCanvas(null, ref.read(pipelineControllerProvider).graph);
      }
    });
  }

  void _handleAnyFlEvent(fln.NodeEditorEvent event) {
    if (_suppressFlEvents) return;
    _reconcileFromCanvas();
  }

  /// Pushes MODEL changes onto the canvas. Diffs by id rather than
  /// rebuilding everything, so an unrelated edit (e.g. just moving one
  /// node) doesn't tear down and re-add every other node's fl_nodes
  /// instance (which would also lose their canvas selection/viewport
  /// feel).
  void _syncModelToCanvas(PipelineGraph? prev, PipelineGraph next) {
    _suppressFlEvents = true;
    try {
      final prevNodeIds = prev?.nodes.map((n) => n.id).toSet() ?? {};
      final nextNodeIds = next.nodes.map((n) => n.id).toSet();

      for (final id in prevNodeIds.difference(nextNodeIds)) {
        final flId = _ourNodeIdToFlId.remove(id);
        if (flId != null) {
          _flIdToOurNodeId.remove(flId);
          _flController.removeNodeById(flId);
        }
      }

      for (final node in next.nodes) {
        if (!_ourNodeIdToFlId.containsKey(node.id)) {
          final flNode = _flController.addNode(node.type.name,
              offset: Offset(node.x, node.y));
          _ourNodeIdToFlId[node.id] = flNode.id;
          _flIdToOurNodeId[flNode.id] = node.id;
        } else {
          // Position sync for a node fl_nodes already knows about — e.g.
          // an undo, or a graph freshly loaded from IndexedDB.
          final flId = _ourNodeIdToFlId[node.id]!;
          final flNode = _flController.nodes[flId];
          if (flNode != null && flNode.offset != Offset(node.x, node.y)) {
            flNode.offset = Offset(node.x, node.y);
          }
        }
      }

      final prevEdgeIds = prev?.edges.map((e) => e.id).toSet() ?? {};
      final nextEdgeIds = next.edges.map((e) => e.id).toSet();

      for (final id in prevEdgeIds.difference(nextEdgeIds)) {
        final flLinkId = _ourEdgeIdToFlLinkId.remove(id);
        if (flLinkId != null) {
          _flLinkIdToOurEdgeId.remove(flLinkId);
          _flController.removeLinkById(flLinkId);
        }
      }

      for (final edge in next.edges) {
        if (_ourEdgeIdToFlLinkId.containsKey(edge.id)) continue;
        final fromFlId = _ourNodeIdToFlId[edge.fromNodeId];
        final toFlId = _ourNodeIdToFlId[edge.toNodeId];
        if (fromFlId == null || toFlId == null) continue;
        final link = _flController.addLink(
            fromFlId, edge.fromPortId, toFlId, edge.toPortId);
        if (link != null) {
          _ourEdgeIdToFlLinkId[edge.id] = link.id;
          _flLinkIdToOurEdgeId[link.id] = edge.id;
        }
      }
    } finally {
      _suppressFlEvents = false;
    }
  }

  /// Pulls CANVAS changes into the model. Deliberately re-diffs the
  /// confirmed live accessors (`nodes`, `linksById`, `selectedNodeIds`)
  /// rather than parsing individual event payloads — see this file's top
  /// doc comment for why.
  void _reconcileFromCanvas() {
    final controller = ref.read(pipelineControllerProvider.notifier);
    final graph = ref.read(pipelineControllerProvider).graph;

    // Nodes removed on the canvas (e.g. Delete key / right-click menu).
    for (final ourId in _ourNodeIdToFlId.keys.toList()) {
      final flId = _ourNodeIdToFlId[ourId]!;
      if (!_flController.nodes.containsKey(flId)) {
        _ourNodeIdToFlId.remove(ourId);
        _flIdToOurNodeId.remove(flId);
        controller.removeNode(ourId);
      }
    }

    // Nodes moved on the canvas.
    for (final node in graph.nodes) {
      final flId = _ourNodeIdToFlId[node.id];
      final flNode = flId == null ? null : _flController.nodes[flId];
      if (flNode == null) continue;
      if (flNode.offset.dx != node.x || flNode.offset.dy != node.y) {
        controller.moveNode(node.id, flNode.offset.dx, flNode.offset.dy);
      }
    }

    // Links removed on the canvas.
    for (final ourEdgeId in _ourEdgeIdToFlLinkId.keys.toList()) {
      final flLinkId = _ourEdgeIdToFlLinkId[ourEdgeId]!;
      if (!_flController.linksById.containsKey(flLinkId)) {
        _ourEdgeIdToFlLinkId.remove(ourEdgeId);
        _flLinkIdToOurEdgeId.remove(flLinkId);
        controller.removeEdge(ourEdgeId);
      }
    }

    // Links drawn on the canvas.
    for (final entry in _flController.linksById.entries) {
      if (_flLinkIdToOurEdgeId.containsKey(entry.key)) continue;
      final link = entry.value;
      final fromOurId = _flIdToOurNodeId[link.fromTo.from];
      // In 1.0.2, fromPort is actually the destination node id and to is
      // the source port id; the record field names are misleading.
      final toOurId = _flIdToOurNodeId[link.fromTo.fromPort];
      if (fromOurId == null || toOurId == null) continue;

      final error = controller.addEdge(fromOurId, toOurId, link.fromTo.toPort);
      if (error != null) {
        // Our own cycle/port-arity check rejected something fl_nodes'
        // own (looser) validation allowed — undo it on the canvas too so
        // the two stay in sync, and tell the user why.
        _suppressFlEvents = true;
        _flController.removeLinkById(entry.key);
        _suppressFlEvents = false;
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
        continue;
      }
      // Find the just-created PipelineEdge by its (from,to,toPort) triple
      // to record the id mapping — addEdge doesn't hand the new id back
      // directly, so look it up from the freshly-updated graph instead.
      final newEdge =
          ref.read(pipelineControllerProvider).graph.edges.lastWhere(
                (e) =>
                    e.fromNodeId == fromOurId &&
                    e.toNodeId == toOurId &&
                    e.toPortId == link.fromTo.toPort,
              );
      _ourEdgeIdToFlLinkId[newEdge.id] = entry.key;
      _flLinkIdToOurEdgeId[entry.key] = newEdge.id;
    }

    // Selection → inspector panel.
    final selectedFlId = _flController.selectedNodeIds.isEmpty
        ? null
        : _flController.selectedNodeIds.first;
    widget.onSelectionChanged(
        selectedFlId == null ? null : _flIdToOurNodeId[selectedFlId]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pipelineControllerProvider.select((s) => s.graph), (prev, next) {
      _syncModelToCanvas(prev, next);
    });

    return Stack(
      children: [
        Positioned.fill(
          child: fln.FlNodeEditorWidget(
            controller: _flController,
            overlay: () => const [],
          ),
        ),
        // arcane_nodes paints a hard-coded red viewport outline in debug
        // builds. Its editor has 8px of internal padding, so this slightly
        // wider blue outline covers that package debug chrome exactly and
        // keeps the canvas consistent with the rest of Commons Lens.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                border: Border.all(color: _kAccent, width: 1.3),
              ),
            ),
          ),
        ),
        // Live legend/HUD — see this file's top doc comment: the canvas
        // package can't host widgets inside a node, so a persistent,
        // always-visible readout of what each port color means (plus a
        // running node/edge count) is delivered as a corner overlay
        // instead. IgnorePointer keeps it from stealing pan/drag gestures
        // meant for the canvas underneath.
        const Positioned(
          top: 14,
          right: 14,
          child: IgnorePointer(child: _CanvasStatsBadge()),
        ),
      ],
    );
  }
}

class _CanvasStatsBadge extends ConsumerWidget {
  const _CanvasStatsBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pipelineControllerProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _kPanelBg.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${state.graph.nodes.length} nodes  ·  ${state.graph.edges.length} edges',
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              for (final cat in PipelineNodeCategory.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: _categoryColor(cat),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(cat.name,
                        style: const TextStyle(
                            color: _kMuted,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

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
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.72,
                        ),
                        itemCount:
                            items.length > renderCap ? renderCap : items.length,
                        itemBuilder: (context, i) => MediaCard(
                          key: ValueKey(items[i].url),
                          item: items[i],
                          searchResultsNotifier: ValueNotifier(items),
                          onLoadMore: () {},
                          index: i,
                          searchState: const SearchState(),
                          extraParams: {
                            'from': 'pipeline',
                            'pipelineNode': node.id
                          },
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
    const licenses = {
      'cc0': 'CC0',
      'ccBy4': 'CC BY 4.0',
      'ccBySa4': 'CC BY-SA 4.0',
      'publicDomain': 'Public domain',
    };
    return licenses[value] ?? value.toUpperCase();
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

class _BrowseListField extends StatefulWidget {
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
  State<_BrowseListField> createState() => _BrowseListFieldState();
}

class _BrowseListFieldState extends State<_BrowseListField> {
  final SearchService _service = SearchService();
  TextEditingController? _fieldController;

  Future<Iterable<_BrowseChoice>> _search(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return const <_BrowseChoice>[];
    if (widget.categoryMode) {
      final result = await _service.browseCategories(prefix: query);
      return result.items
          .take(30)
          .map((item) => _BrowseChoice(item.name, '${item.size} files'));
    }
    final result = await _service.browseTemplates(prefix: query);
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
          optionsBuilder: (value) => _search(value.text),
          onSelected: (choice) {
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
  final SearchService _service = SearchService();
  DepictsEntity? _pendingProperty;
  TextEditingController? _fieldController;

  @override
  void didUpdateWidget(covariant _EntriesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _pendingProperty = null;
      _fieldController?.clear();
    }
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
      optionsBuilder: (value) async {
        final query = value.text.trim();
        if (query.isEmpty) return const <DepictsEntity>[];
        return propertySearch
            ? _service.searchWikidataProperties(query)
            : _service.searchDepictsEntities(query);
      },
      onSelected: onSelected,
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
