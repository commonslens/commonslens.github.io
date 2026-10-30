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
import 'backend_providers.dart';
import 'autocomplete_request_coordinator.dart';

part 'pipeline_editor_widgets.dart';
part 'pipeline_inspector.dart';

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

  String joinedLicenses() {
    final values = c['licenses'];
    if (values is! List || values.isEmpty) return '';
    final labels = values.map((value) {
      for (final preset in LicensePreset.values) {
        if (preset.name == value) return licensePresetLabel(preset);
      }
      return value.toString();
    }).toList();
    return '${labels.take(2).join(', ')}${labels.length > 2 ? ' +${labels.length - 2}' : ''}';
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
      return joinedLicenses().isEmpty ? 'Any license' : joinedLicenses();
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
            options:
                LicensePreset.values.map((license) => license.name).toList())
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
