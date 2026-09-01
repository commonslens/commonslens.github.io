import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_controller.dart';
import 'search_service.dart';

class AdvancedFiltersDrawer extends ConsumerStatefulWidget {
  const AdvancedFiltersDrawer({super.key});

  @override
  ConsumerState<AdvancedFiltersDrawer> createState() =>
      _AdvancedFiltersDrawerState();
}

class _AdvancedFiltersDrawerState extends ConsumerState<AdvancedFiltersDrawer> {
  final SearchService _service = SearchService();

  late TextEditingController _minWidthCtrl;
  late TextEditingController _minHeightCtrl;
  late TextEditingController _maxWidthCtrl;
  late TextEditingController _maxHeightCtrl;
  late TextEditingController _minFileSizeCtrl;
  late TextEditingController _maxFileSizeCtrl;
  // true = values in the two fields above are MB, false = KB. Purely a
  // drawer-local display choice — SearchState.minFileSizeBytes/
  // maxFileSizeBytes are always raw bytes on the wire (see
  // search_service.dart's own comment on filesize:), so conversion only
  // happens once, at _applyFilters time.
  bool _fileSizeUnitMB = true;
  int? _colorDepthBits;
  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;
  late TextEditingController _radiusCtrl;
  late TextEditingController _nearTitleCtrl;
  late TextEditingController _nearTitleRadiusCtrl;

  Set<String> _categoriesInclude = {};
  Set<String> _categoriesExclude = {};
  bool _categoryExcludeMode = false;
  bool _deepCategoryMode = false;
  bool _categoriesUnionMode = false;
  TextEditingController? _categoryFieldController;

  // hastemplate: generalized beyond the hardcoded QualityFilter presets —
  // GLAM/institutional sets (e.g. "Institution:Metropolitan Museum of Art"),
  // granular PD templates (e.g. "PD-USGov-NASA"), or anything else a
  // template marks. Always AND'd (see buildQuery) — unlike categories/
  // depicts/statements there's no union/intersection toggle here. No
  // autocomplete backend exists for template names, so entry is manual
  // free text via the "+" button/Enter, same as excludeTerms elsewhere.
  Set<String> _templatesInclude = {};
  Set<String> _templatesExclude = {};
  bool _templateExcludeMode = false;
  TextEditingController? _templateFieldController;

  Set<DepictsEntity> _depictsInclude = {};
  Set<DepictsEntity> _depictsExclude = {};
  bool _depictsExcludeMode = false;
  bool _depictsUnionMode = false;
  TextEditingController? _depictsFieldController;

  Set<WikidataStatement> _statementsInclude = {};
  Set<WikidataStatement> _statementsExclude = {};
  bool _statementExcludeMode = false;
  bool _statementsUnionMode = false;
  DepictsEntity? _pendingProperty;
  TextEditingController? _propertyFieldController;
  TextEditingController? _statementValueFieldController;

  late TextEditingController _langCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _createdFromCtrl;
  late TextEditingController _createdToCtrl;
  late TextEditingController _editedFromCtrl;
  late TextEditingController _editedToCtrl;

  @override
  void initState() {
    super.initState();
    final state = ref.read(searchControllerProvider).filterState;

    _minWidthCtrl =
        TextEditingController(text: state.minWidth?.toString() ?? '');
    _minHeightCtrl =
        TextEditingController(text: state.minHeight?.toString() ?? '');
    _maxWidthCtrl =
        TextEditingController(text: state.maxWidth?.toString() ?? '');
    _maxHeightCtrl =
        TextEditingController(text: state.maxHeight?.toString() ?? '');

    // SearchState's bytes are converted to MB for display up front — the
    // unit toggle only affects how _applyFilters converts back, not how
    // this initial value is read.
    String bytesToMBText(int? bytes) =>
        bytes == null ? '' : (bytes / (1024 * 1024)).toString();
    _minFileSizeCtrl =
        TextEditingController(text: bytesToMBText(state.minFileSizeBytes));
    _maxFileSizeCtrl =
        TextEditingController(text: bytesToMBText(state.maxFileSizeBytes));
    _colorDepthBits = state.colorDepthBits;

    _templatesInclude = Set.from(state.templates);
    _templatesExclude = Set.from(state.excludeTemplates);

    _latCtrl =
        TextEditingController(text: state.nearCoord?.lat.toString() ?? '');
    _lngCtrl =
        TextEditingController(text: state.nearCoord?.lng.toString() ?? '');
    _radiusCtrl = TextEditingController(
        text: state.nearCoord?.radiusKm.toString() ?? '10');
    _nearTitleCtrl = TextEditingController(text: state.nearTitle?.title ?? '');
    _nearTitleRadiusCtrl = TextEditingController(
        text: state.nearTitle?.radiusKm.toString() ?? '10');

    _categoriesInclude = Set.from(state.categories);
    _categoriesExclude = Set.from(state.excludeCategories);
    _deepCategoryMode = state.deepCategoryMode;
    _categoriesUnionMode = state.categoriesUnion;
    _depictsInclude = Set.from(state.depictsInclude);
    _depictsExclude = Set.from(state.depictsExclude);
    _depictsUnionMode = state.depictsUnion;
    _statementsInclude = Set.from(state.statementsInclude);
    _statementsExclude = Set.from(state.statementsExclude);
    _statementsUnionMode = state.statementsUnion;

    _langCtrl = TextEditingController(text: state.languageCode ?? '');
    _modelCtrl = TextEditingController(text: state.contentModel ?? '');
    _createdFromCtrl =
        TextEditingController(text: state.createdDate?.from ?? '');
    _createdToCtrl = TextEditingController(text: state.createdDate?.to ?? '');
    _editedFromCtrl = TextEditingController(text: state.editedDate?.from ?? '');
    _editedToCtrl = TextEditingController(text: state.editedDate?.to ?? '');
  }

  @override
  void dispose() {
    _minWidthCtrl.dispose();
    _minHeightCtrl.dispose();
    _maxWidthCtrl.dispose();
    _maxHeightCtrl.dispose();
    _minFileSizeCtrl.dispose();
    _maxFileSizeCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    _nearTitleCtrl.dispose();
    _nearTitleRadiusCtrl.dispose();
    _langCtrl.dispose();
    _modelCtrl.dispose();
    _createdFromCtrl.dispose();
    _createdToCtrl.dispose();
    _editedFromCtrl.dispose();
    _editedToCtrl.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final w = int.tryParse(_minWidthCtrl.text);
    final h = int.tryParse(_minHeightCtrl.text);
    final maxW = int.tryParse(_maxWidthCtrl.text);
    final maxH = int.tryParse(_maxHeightCtrl.text);

    // filesize: is always raw bytes on the wire (see
    // search_service.dart) — convert from whichever display unit is
    // currently selected only here, at commit time.
    final unitBytes = _fileSizeUnitMB ? 1024 * 1024 : 1024;
    int? parseFileSize(String text) {
      final value = double.tryParse(text.trim());
      if (value == null) return null;
      return (value * unitBytes).round();
    }

    final minFileSize = parseFileSize(_minFileSizeCtrl.text);
    final maxFileSize = parseFileSize(_maxFileSizeCtrl.text);

    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final rad = double.tryParse(_radiusCtrl.text) ?? 10.0;
    final nearTitleText = _nearTitleCtrl.text.trim();
    final nearTitleRad = double.tryParse(_nearTitleRadiusCtrl.text) ?? 10.0;

    // Mutually exclusive geo modes — a place name takes priority if both
    // happen to be filled in, since it's the more specific/intentional entry.
    NearCoordFilter? coordFilter;
    NearTitleFilter? titleFilter;
    if (nearTitleText.isNotEmpty) {
      titleFilter = NearTitleFilter(title: nearTitleText, radiusKm: nearTitleRad);
    } else if (lat != null && lng != null) {
      coordFilter = NearCoordFilter(lat: lat, lng: lng, radiusKm: rad);
    }

    final lang = _langCtrl.text.trim().isEmpty ? null : _langCtrl.text.trim();
    final model =
        _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim();
    final cFrom = _createdFromCtrl.text.trim();
    final cTo = _createdToCtrl.text.trim();
    final eFrom = _editedFromCtrl.text.trim();
    final eTo = _editedToCtrl.text.trim();

    final created = (cFrom.isNotEmpty || cTo.isNotEmpty)
        ? DateFilter(from: cFrom, to: cTo)
        : null;
    final edited = (eFrom.isNotEmpty || eTo.isNotEmpty)
        ? DateFilter(from: eFrom, to: eTo)
        : null;

    final currentState = ref.read(searchControllerProvider).filterState;

    final nextState = currentState.copyWith(
      minWidth: w,
      clearMinWidth: w == null,
      minHeight: h,
      clearMinHeight: h == null,
      maxWidth: maxW,
      clearMaxWidth: maxW == null,
      maxHeight: maxH,
      clearMaxHeight: maxH == null,
      minFileSizeBytes: minFileSize,
      clearMinFileSizeBytes: minFileSize == null,
      maxFileSizeBytes: maxFileSize,
      clearMaxFileSizeBytes: maxFileSize == null,
      colorDepthBits: _colorDepthBits,
      clearColorDepthBits: _colorDepthBits == null,
      templates: _templatesInclude,
      excludeTemplates: _templatesExclude,
      nearCoord: coordFilter,
      clearNearCoord: coordFilter == null,
      nearTitle: titleFilter,
      clearNearTitle: titleFilter == null,
      categories: _categoriesInclude,
      excludeCategories: _categoriesExclude,
      deepCategoryMode: _deepCategoryMode,
      categoriesUnion: _categoriesUnionMode,
      depictsInclude: _depictsInclude,
      depictsExclude: _depictsExclude,
      depictsUnion: _depictsUnionMode,
      statementsInclude: _statementsInclude,
      statementsExclude: _statementsExclude,
      statementsUnion: _statementsUnionMode,
      languageCode: lang,
      clearLanguageCode: lang == null,
      contentModel: model,
      clearContentModel: model == null,
      createdDate: created,
      clearCreatedDate: created == null,
      editedDate: edited,
      clearEditedDate: edited == null,
    );

    ref
        .read(searchControllerProvider.notifier)
        .search(nextState.queryText, overrideState: nextState);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider).filterState;

    return Drawer(
      width: 600,
      backgroundColor: const Color(0xFF111111),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'FILTERS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF222222), height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [

                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('IMAGE CLASSIFICATION',
                            style: const TextStyle(
                                color: Color(0xFF3D7EFF),
                                fontSize: 12,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w800)),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _buildSectionHeader('DEPICTS (SUBJECT)'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Intersection (AND)',
                          selected: !_depictsUnionMode,
                          onTap: () =>
                              setState(() => _depictsUnionMode = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Union (OR)',
                          selected: _depictsUnionMode,
                          onTap: () =>
                              setState(() => _depictsUnionMode = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _depictsUnionMode
                        ? 'Matches files depicting ANY selected subject below (this OR this), still excluding anything marked "not".'
                        : 'Matches files depicting ALL selected subjects below (this AND this), and excludes anything marked "not".',
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_depictsInclude.isNotEmpty || _depictsExclude.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._depictsInclude.map((d) => _buildFilterChip(
                              label: d.label,
                              excluded: false,
                              onDeleted: () =>
                                  setState(() => _depictsInclude.remove(d)),
                            )),
                        ..._depictsExclude.map((d) => _buildFilterChip(
                              label: d.label,
                              excluded: true,
                              onDeleted: () =>
                                  setState(() => _depictsExclude.remove(d)),
                            )),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Autocomplete<DepictsEntity>(
                          displayStringForOption: (option) => option.label,
                          optionsBuilder:
                              (TextEditingValue textEditingValue) async {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<DepictsEntity>.empty();
                            }
                            return await _service
                                .searchDepictsEntities(textEditingValue.text);
                          },
                          onSelected: (DepictsEntity selection) {
                            setState(() {
                              if (_depictsExcludeMode) {
                                _depictsInclude.remove(selection);
                                _depictsExclude.add(selection);
                              } else {
                                _depictsExclude.remove(selection);
                                _depictsInclude.add(selection);
                              }
                            });
                            // Autocomplete auto-fills the field with the
                            // selected label and leaves it there — fine for
                            // single-select, but blocks typing the next
                            // entry in multi-select. Clear it so the box is
                            // ready for the next search immediately.
                            _depictsFieldController?.clear();
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onEditingComplete) {
                            _depictsFieldController = controller;
                            return TextField(
                              keyboardType: (kIsWeb &&
                                      (defaultTargetPlatform ==
                                              TargetPlatform.iOS ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.android))
                                  ? TextInputType.text
                                  : TextInputType.url,
                              controller: controller,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration().copyWith(
                                hintText: _depictsExcludeMode
                                    ? 'Exclude subject...'
                                    : 'e.g. Cat, Eiffel Tower...',
                              ),
                              onSubmitted: (_) => controller.clear(),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: const Color(0xFF1E1E1E),
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxHeight: 200, maxWidth: 300),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option.label,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        subtitle: option.description != null
                                            ? Text(option.description!,
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11))
                                            : null,
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildExcludeModeToggle(
                        excludeMode: _depictsExcludeMode,
                        onChanged: (val) =>
                            setState(() => _depictsExcludeMode = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('WIKIDATA PROPERTY SEARCH'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Intersection (AND)',
                          selected: !_statementsUnionMode,
                          onTap: () =>
                              setState(() => _statementsUnionMode = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Union (OR)',
                          selected: _statementsUnionMode,
                          onTap: () =>
                              setState(() => _statementsUnionMode = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _statementsUnionMode
                        ? 'Matches ANY selected property below (this OR this), still excluding anything marked "not".'
                        : 'Matches ALL selected properties below (this AND this), and excludes anything marked "not".',
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_statementsInclude.isNotEmpty ||
                      _statementsExclude.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._statementsInclude.map((s) => _buildFilterChip(
                              label: '${s.property.label}: ${s.value.label}',
                              excluded: false,
                              onDeleted: () =>
                                  setState(() => _statementsInclude.remove(s)),
                            )),
                        ..._statementsExclude.map((s) => _buildFilterChip(
                              label: '${s.property.label}: ${s.value.label}',
                              excluded: true,
                              onDeleted: () =>
                                  setState(() => _statementsExclude.remove(s)),
                            )),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_pendingProperty != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF13203A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF3D7EFF)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              size: 14, color: Color(0xFF3D7EFF)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Property: ${_pendingProperty!.label} — now search a value',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close,
                                size: 16, color: Colors.white54),
                            onPressed: () =>
                                setState(() => _pendingProperty = null),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Autocomplete<DepictsEntity>(
                          key: ValueKey(_pendingProperty == null
                              ? 'statement-property'
                              : 'statement-value'),
                          displayStringForOption: (option) => option.label,
                          optionsBuilder:
                              (TextEditingValue textEditingValue) async {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<DepictsEntity>.empty();
                            }
                            return _pendingProperty == null
                                ? await _service.searchWikidataProperties(
                                    textEditingValue.text)
                                : await _service.searchDepictsEntities(
                                    textEditingValue.text);
                          },
                          onSelected: (DepictsEntity selection) {
                            if (_pendingProperty == null) {
                              setState(() => _pendingProperty = selection);
                              _propertyFieldController?.clear();
                            } else {
                              final stmt = WikidataStatement(
                                  property: _pendingProperty!,
                                  value: selection);
                              setState(() {
                                if (_statementExcludeMode) {
                                  _statementsInclude.remove(stmt);
                                  _statementsExclude.add(stmt);
                                } else {
                                  _statementsExclude.remove(stmt);
                                  _statementsInclude.add(stmt);
                                }
                                _pendingProperty = null;
                              });
                              _statementValueFieldController?.clear();
                            }
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onEditingComplete) {
                            if (_pendingProperty == null) {
                              _propertyFieldController = controller;
                            } else {
                              _statementValueFieldController = controller;
                            }
                            return TextField(
                              keyboardType: (kIsWeb &&
                                      (defaultTargetPlatform ==
                                              TargetPlatform.iOS ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.android))
                                  ? TextInputType.text
                                  : TextInputType.url,
                              controller: controller,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration().copyWith(
                                hintText: _pendingProperty == null
                                    ? 'Search property (e.g. location of creation)...'
                                    : 'Search value (e.g. Paris)...',
                              ),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: const Color(0xFF1E1E1E),
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxHeight: 200, maxWidth: 360),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option.label,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        subtitle: option.description != null
                                            ? Text(option.description!,
                                                style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11))
                                            : null,
                                        onTap: () => onSelected(option),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildExcludeModeToggle(
                        excludeMode: _statementExcludeMode,
                        onChanged: (val) =>
                            setState(() => _statementExcludeMode = val),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),


                  _buildSectionHeader('CATEGORIES'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Intersection (AND)',
                          selected: !_categoriesUnionMode,
                          onTap: () =>
                              setState(() => _categoriesUnionMode = false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'Union (OR)',
                          selected: _categoriesUnionMode,
                          onTap: () =>
                              setState(() => _categoriesUnionMode = true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _categoriesUnionMode
                        ? 'Matches files in ANY selected category below (this OR this), still excluding anything marked "not".'
                        : 'Matches files in ALL selected categories below (this AND this), and excludes anything marked "not".',
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_categoriesInclude.isNotEmpty ||
                      _categoriesExclude.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._categoriesInclude.map((c) => _buildFilterChip(
                              label: c,
                              excluded: false,
                              onDeleted: () =>
                                  setState(() => _categoriesInclude.remove(c)),
                            )),
                        ..._categoriesExclude.map((c) => _buildFilterChip(
                              label: c,
                              excluded: true,
                              onDeleted: () =>
                                  setState(() => _categoriesExclude.remove(c)),
                            )),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Autocomplete<String>(
                          optionsBuilder: (textEditingValue) async {
                            if (textEditingValue.text.isEmpty) {
                              return const Iterable<String>.empty();
                            }
                            return await _service
                                .searchCategories(textEditingValue.text);
                          },
                          onSelected: (String selection) {
                            setState(() {
                              if (_categoryExcludeMode) {
                                _categoriesInclude.remove(selection);
                                _categoriesExclude.add(selection);
                              } else {
                                _categoriesExclude.remove(selection);
                                _categoriesInclude.add(selection);
                              }
                            });
                            // Same fix as depicts: Autocomplete leaves the
                            // selected label in the field after a dropdown
                            // tap. The manual "+"/Enter path already clears
                            // below; the dropdown-tap path needs it too.
                            _categoryFieldController?.clear();
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onEditingComplete) {
                            _categoryFieldController = controller;
                            void addFromField() {
                              final val = controller.text.trim();
                              if (val.isEmpty) return;
                              setState(() {
                                if (_categoryExcludeMode) {
                                  _categoriesInclude.remove(val);
                                  _categoriesExclude.add(val);
                                } else {
                                  _categoriesExclude.remove(val);
                                  _categoriesInclude.add(val);
                                }
                              });
                              controller.clear();
                            }

                            return TextField(
                              keyboardType: (kIsWeb &&
                                      (defaultTargetPlatform ==
                                              TargetPlatform.iOS ||
                                          defaultTargetPlatform ==
                                              TargetPlatform.android))
                                  ? TextInputType.text
                                  : TextInputType.url,
                              controller: controller,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration().copyWith(
                                hintText: _categoryExcludeMode
                                    ? 'Exclude category...'
                                    : 'Search categories...',
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.add,
                                      color: Colors.white54, size: 18),
                                  onPressed: addFromField,
                                ),
                              ),
                              onSubmitted: (_) => addFromField(),
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                color: const Color(0xFF1E1E1E),
                                elevation: 4,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                      maxHeight: 200, maxWidth: 360),
                                  child: ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: options.length,
                                    itemBuilder: (context, index) {
                                      final option = options.elementAt(index);
                                      return ListTile(
                                        title: Text(option,
                                            style: const TextStyle(
                                                color: Colors.white)),
                                        onTap: () {
                                          onSelected(option);
                                          FocusScope.of(context).unfocus();
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildExcludeModeToggle(
                        excludeMode: _categoryExcludeMode,
                        onChanged: (val) =>
                            setState(() => _categoryExcludeMode = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // deepcat: vs incategory: — strict mode only matches files
                  // filed directly in the exact category node; deep mode
                  // tells CirrusSearch to recurse into every subcategory
                  // branching beneath it too. Scoped right under the
                  // category picker since it changes how EVERY category
                  // above (include and exclude alike) gets matched.
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _deepCategoryMode
                            ? const Color(0xFF3D7EFF).withOpacity(0.4)
                            : const Color(0xFF262626),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Include subcategories',
                                style: TextStyle(
                                  color: _deepCategoryMode
                                      ? Colors.white
                                      : Colors.white70,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _deepCategoryMode
                                    ? 'Deep: also pulls files from every subcategory nested beneath the categories above.'
                                    : 'Strict: only files filed directly in the exact categories above — nested subcategories are skipped.',
                                style: const TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 11,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Switch(
                          value: _deepCategoryMode,
                          activeColor: const Color(0xFF3D7EFF),
                          onChanged: (val) =>
                              setState(() => _deepCategoryMode = val),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('QUALITY ASSESSMENT'),
                  DropdownButtonFormField<QualityFilter>(
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: _inputDecoration(),
                    value: state.qualityFilter,
                    items: QualityFilter.values.map((q) {
                      return DropdownMenuItem(
                          value: q,
                          child: Text(qualityFilterLabel(q),
                              style: const TextStyle(color: Colors.white)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final nextState = state.copyWith(qualityFilter: val);
                        ref.read(searchControllerProvider.notifier).search(
                            nextState.queryText,
                            overrideState: nextState);
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('LICENSE',
                            style: const TextStyle(
                                color: Color(0xFF3D7EFF),
                                fontSize: 12,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w800)),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _buildSectionHeader('LICENSE / RIGHTS'),
                  DropdownButtonFormField<LicensePreset>(
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration: _inputDecoration(),
                    value: state.licensePreset,
                    items: LicensePreset.values.map((preset) {
                      return DropdownMenuItem(
                          value: preset,
                          child: Text(licensePresetLabel(preset),
                              style: const TextStyle(color: Colors.white)));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        final nextState = state.copyWith(licensePreset: val);
                        ref.read(searchControllerProvider.notifier).search(
                            nextState.queryText,
                            overrideState: nextState);
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('METADATA AND LOCATION',
                            style: const TextStyle(
                                color: Color(0xFF3D7EFF),
                                fontSize: 12,
                                letterSpacing: 1.8,
                                fontWeight: FontWeight.w800)),
                      ),
                      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _buildSectionHeader('LANGUAGE & CONTENT'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _langCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Lang (en)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _modelCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Model (wikitext)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('CREATED DATE (YYYY-MM-DD)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _createdFromCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'From'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _createdToCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'To'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('EDITED DATE (YYYY-MM-DD)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _editedFromCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'From'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _editedToCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'To'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('RESOLUTION BOUNDS'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minWidthCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Min width px'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _minHeightCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Min height px'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _maxWidthCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Max width px'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxHeightCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'Max height px'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('FILE SIZE & COLOR DEPTH'),
                  Row(
                    children: [
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'MB',
                          selected: _fileSizeUnitMB,
                          onTap: () => setState(() => _fileSizeUnitMB = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildCombineModeButton(
                          label: 'KB',
                          selected: !_fileSizeUnitMB,
                          onTap: () => setState(() => _fileSizeUnitMB = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minFileSizeCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: _inputDecoration().copyWith(
                              hintText: _fileSizeUnitMB ? 'Min size (MB)' : 'Min size (KB)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxFileSizeCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: _inputDecoration().copyWith(
                              hintText: _fileSizeUnitMB ? 'Max size (MB)' : 'Max size (KB)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    dropdownColor: const Color(0xFF1E1E1E),
                    decoration:
                        _inputDecoration().copyWith(hintText: 'Any color depth'),
                    value: _colorDepthBits,
                    items: const [
                      DropdownMenuItem(value: null, child: Text('Any color depth', style: TextStyle(color: Colors.white70))),
                      DropdownMenuItem(value: 1, child: Text('1-bit (monochrome)', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 8, child: Text('8-bit', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 16, child: Text('16-bit', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 24, child: Text('24-bit', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 32, child: Text('32-bit', style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (val) => setState(() => _colorDepthBits = val),
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('TEMPLATES'),
                  Text(
                    'Matches files carrying a specific template — e.g. a GLAM/institutional '
                    'set ("Institution:Metropolitan Museum of Art") or a granular PD template '
                    '("PD-USGov-NASA"). Always required (AND), no union mode.',
                    style: const TextStyle(
                        color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  if (_templatesInclude.isNotEmpty || _templatesExclude.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ..._templatesInclude.map((t) => _buildFilterChip(
                              label: t,
                              excluded: false,
                              onDeleted: () =>
                                  setState(() => _templatesInclude.remove(t)),
                            )),
                        ..._templatesExclude.map((t) => _buildFilterChip(
                              label: t,
                              excluded: true,
                              onDeleted: () =>
                                  setState(() => _templatesExclude.remove(t)),
                            )),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Builder(builder: (context) {
                          final controller = _templateFieldController ??=
                              TextEditingController();
                          void addFromField() {
                            final val = controller.text.trim();
                            if (val.isEmpty) return;
                            setState(() {
                              if (_templateExcludeMode) {
                                _templatesInclude.remove(val);
                                _templatesExclude.add(val);
                              } else {
                                _templatesExclude.remove(val);
                                _templatesInclude.add(val);
                              }
                            });
                            controller.clear();
                          }

                          return TextField(
                            keyboardType: (kIsWeb &&
                                    (defaultTargetPlatform ==
                                            TargetPlatform.iOS ||
                                        defaultTargetPlatform ==
                                            TargetPlatform.android))
                                ? TextInputType.text
                                : TextInputType.url,
                            controller: controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: _inputDecoration().copyWith(
                              hintText: _templateExcludeMode
                                  ? 'Exclude template name...'
                                  : 'e.g. PD-USGov-NASA',
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.add,
                                    color: Colors.white54, size: 18),
                                onPressed: addFromField,
                              ),
                            ),
                            onSubmitted: (_) => addFromField(),
                          );
                        }),
                      ),
                      const SizedBox(width: 10),
                      _buildExcludeModeToggle(
                        excludeMode: _templateExcludeMode,
                        onChanged: (val) =>
                            setState(() => _templateExcludeMode = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  _buildSectionHeader('GEOLOCATION (LAT / LNG / RADIUS KM)'),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _latCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Lat'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _lngCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration:
                              _inputDecoration().copyWith(hintText: 'Lng'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _radiusCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              _inputDecoration().copyWith(hintText: 'km'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: const [
                      Expanded(child: Divider(color: Color(0xFF222222))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text('OR SEARCH NEAR A PLACE',
                            style: TextStyle(
                                color: Color(0xFF555555),
                                fontSize: 9,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700)),
                      ),
                      Expanded(child: Divider(color: Color(0xFF222222))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          keyboardType: (kIsWeb &&
                                  (defaultTargetPlatform ==
                                          TargetPlatform.iOS ||
                                      defaultTargetPlatform ==
                                          TargetPlatform.android))
                              ? TextInputType.text
                              : TextInputType.url,
                          controller: _nearTitleCtrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration()
                              .copyWith(hintText: 'e.g. Eiffel Tower'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: _nearTitleRadiusCtrl,
                          style: const TextStyle(color: Colors.white),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration:
                              _inputDecoration().copyWith(hintText: 'km'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF222222))),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _applyFilters,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3D7EFF),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Apply Manual Filters',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF7A7A7A),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool excluded,
    required VoidCallback onDeleted,
  }) {
    return Chip(
      label: Text(
        excluded ? '− $label' : label,
        style: TextStyle(
          color: excluded ? const Color(0xFFFF6B6B) : Colors.white,
          fontSize: 11,
        ),
      ),
      backgroundColor: excluded
          ? const Color(0xFF2A1414)
          : const Color(0xFF222222),
      deleteIconColor: excluded ? const Color(0xFFFF6B6B) : Colors.white54,
      side: excluded
          ? const BorderSide(color: Color(0xFF4A2020))
          : BorderSide.none,
      onDeleted: onDeleted,
    );
  }

  Widget _buildExcludeModeToggle({
    required bool excludeMode,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleSegment(
            label: '+',
            selected: !excludeMode,
            color: const Color(0xFF3D7EFF),
            onTap: () => onChanged(false),
          ),
          _toggleSegment(
            label: '−',
            selected: excludeMode,
            color: const Color(0xFFFF6B6B),
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _toggleSegment({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : Colors.white38,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildCombineModeButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3D7EFF).withOpacity(0.15)
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
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: Colors.white30),
    );
  }
}