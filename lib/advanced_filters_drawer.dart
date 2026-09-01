import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'search_models.dart';
import 'search_controller.dart';
import 'search_service.dart';

// -----------------------------------------------------------------------------
// Container: mobile-only Drawer wrapper. Desktop docks FilterPanelContent
// directly into search_page.dart's layout instead of going through a Drawer
// at all — see SearchPage.build's isDesktop branch. This file used to BE
// the drawer; now the drawer is just one of two shells around the same
// content, chosen by viewport width.
// -----------------------------------------------------------------------------

class AdvancedFiltersDrawer extends StatelessWidget {
  const AdvancedFiltersDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // Never the old hardcoded 600 — that overflowed on any phone-width
    // viewport. Caps at 420 on tablet/small-desktop widths that still fall
    // below the 900 docked-panel breakpoint in search_page.dart; shrinks to
    // 92% of the viewport below 480 so it never touches the screen edges.
    final drawerWidth = width < 480 ? width * 0.92 : 420.0;
    return Drawer(
      width: drawerWidth,
      backgroundColor: const Color(0xFF111111),
      child: const FilterPanelContent(showCloseButton: true),
    );
  }
}

// -----------------------------------------------------------------------------
// Content. Two behavioral classes of filter, on purpose:
//
// - Discrete picks (categories, depicts, templates, statements, license,
//   quality) apply the instant a value is added or removed — no local
//   staging, no "Apply" button to remember to press. Each of these reads
//   straight from searchControllerProvider's current filterState and
//   writes back through applyFilterUpdate, same pattern License/Quality's
//   dropdowns already used before this refactor.
// - Typed ranges (resolution, file size, color depth, geolocation, dates)
//   keep local TextEditingControllers — a half-typed number isn't a valid
//   filter yet — but each group gets its OWN small "Apply" button, scoped
//   to just that group's fields, instead of one 60-line dump covering all
//   25 fields at once.
//
// This widget is instantiated exactly once and stays alive for the app's
// lifetime on desktop (docked, not recreated per open/close) — so unlike
// the old drawer, initState-only seeding of the range controllers isn't
// enough; a URL hydrate or a chip removal happening elsewhere needs to be
// reflected here too. See _syncControllersFromState / the ref.listen in
// build for that.
// -----------------------------------------------------------------------------

class FilterPanelContent extends ConsumerStatefulWidget {
  final bool showCloseButton;
  const FilterPanelContent({super.key, this.showCloseButton = false});

  @override
  ConsumerState<FilterPanelContent> createState() => _FilterPanelContentState();
}

class _FilterPanelContentState extends ConsumerState<FilterPanelContent> {
  final SearchService _service = SearchService();

  late TextEditingController _minWidthCtrl;
  late TextEditingController _minHeightCtrl;
  late TextEditingController _maxWidthCtrl;
  late TextEditingController _maxHeightCtrl;
  late TextEditingController _minFileSizeCtrl;
  late TextEditingController _maxFileSizeCtrl;
  bool _fileSizeUnitMB = true;
  int? _colorDepthBits;

  late TextEditingController _latCtrl;
  late TextEditingController _lngCtrl;
  late TextEditingController _radiusCtrl;
  late TextEditingController _nearTitleCtrl;
  late TextEditingController _nearTitleRadiusCtrl;

  late TextEditingController _langCtrl;
  late TextEditingController _modelCtrl;
  late TextEditingController _createdFromCtrl;
  late TextEditingController _createdToCtrl;
  late TextEditingController _editedFromCtrl;
  late TextEditingController _editedToCtrl;

  @override
  void initState() {
    super.initState();
    _seedControllers(ref.read(searchControllerProvider).filterState);
  }

  String _bytesToMBText(int? bytes) =>
      bytes == null ? '' : (bytes / (1024 * 1024)).toString();

  void _seedControllers(SearchState state) {
    _minWidthCtrl = TextEditingController(text: state.minWidth?.toString() ?? '');
    _minHeightCtrl = TextEditingController(text: state.minHeight?.toString() ?? '');
    _maxWidthCtrl = TextEditingController(text: state.maxWidth?.toString() ?? '');
    _maxHeightCtrl = TextEditingController(text: state.maxHeight?.toString() ?? '');
    _minFileSizeCtrl = TextEditingController(text: _bytesToMBText(state.minFileSizeBytes));
    _maxFileSizeCtrl = TextEditingController(text: _bytesToMBText(state.maxFileSizeBytes));
    _colorDepthBits = state.colorDepthBits;

    _latCtrl = TextEditingController(text: state.nearCoord?.lat.toString() ?? '');
    _lngCtrl = TextEditingController(text: state.nearCoord?.lng.toString() ?? '');
    _radiusCtrl = TextEditingController(text: state.nearCoord?.radiusKm.toString() ?? '10');
    _nearTitleCtrl = TextEditingController(text: state.nearTitle?.title ?? '');
    _nearTitleRadiusCtrl = TextEditingController(text: state.nearTitle?.radiusKm.toString() ?? '10');

    _langCtrl = TextEditingController(text: state.languageCode ?? '');
    _modelCtrl = TextEditingController(text: state.contentModel ?? '');
    _createdFromCtrl = TextEditingController(text: state.createdDate?.from ?? '');
    _createdToCtrl = TextEditingController(text: state.createdDate?.to ?? '');
    _editedFromCtrl = TextEditingController(text: state.editedDate?.from ?? '');
    _editedToCtrl = TextEditingController(text: state.editedDate?.to ?? '');
  }

  /// Re-seeds every range-filter controller from a freshly-changed
  /// filterState — needed because, unlike the old per-open Drawer, this
  /// widget can outlive many searches (it's docked permanently on
  /// desktop). Only overwrites a field's text when it actually differs
  /// from the incoming state, so this never fights an in-progress
  /// keystroke in an unrelated field.
  void _syncControllersFromState(SearchState state) {
    void sync(TextEditingController ctrl, String value) {
      if (ctrl.text != value) ctrl.text = value;
    }

    sync(_minWidthCtrl, state.minWidth?.toString() ?? '');
    sync(_minHeightCtrl, state.minHeight?.toString() ?? '');
    sync(_maxWidthCtrl, state.maxWidth?.toString() ?? '');
    sync(_maxHeightCtrl, state.maxHeight?.toString() ?? '');
    sync(_minFileSizeCtrl, _bytesToMBText(state.minFileSizeBytes));
    sync(_maxFileSizeCtrl, _bytesToMBText(state.maxFileSizeBytes));
    if (_colorDepthBits != state.colorDepthBits) {
      setState(() => _colorDepthBits = state.colorDepthBits);
    }
    sync(_latCtrl, state.nearCoord?.lat.toString() ?? '');
    sync(_lngCtrl, state.nearCoord?.lng.toString() ?? '');
    sync(_radiusCtrl, state.nearCoord?.radiusKm.toString() ?? _radiusCtrl.text);
    sync(_nearTitleCtrl, state.nearTitle?.title ?? '');
    sync(_nearTitleRadiusCtrl, state.nearTitle?.radiusKm.toString() ?? _nearTitleRadiusCtrl.text);
    sync(_langCtrl, state.languageCode ?? '');
    sync(_modelCtrl, state.contentModel ?? '');
    sync(_createdFromCtrl, state.createdDate?.from ?? '');
    sync(_createdToCtrl, state.createdDate?.to ?? '');
    sync(_editedFromCtrl, state.editedDate?.from ?? '');
    sync(_editedToCtrl, state.editedDate?.to ?? '');
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

  void _update(SearchState Function(SearchState current) updater) {
    ref.read(searchControllerProvider.notifier).applyFilterUpdate(updater);
  }

  // ---- Resolution / file size / color depth ----

  void _applyResolutionAndSize() {
    final w = int.tryParse(_minWidthCtrl.text);
    final h = int.tryParse(_minHeightCtrl.text);
    final maxW = int.tryParse(_maxWidthCtrl.text);
    final maxH = int.tryParse(_maxHeightCtrl.text);
    final unitBytes = _fileSizeUnitMB ? 1024 * 1024 : 1024;
    int? parseFileSize(String text) {
      final value = double.tryParse(text.trim());
      if (value == null) return null;
      return (value * unitBytes).round();
    }

    final minFileSize = parseFileSize(_minFileSizeCtrl.text);
    final maxFileSize = parseFileSize(_maxFileSizeCtrl.text);

    _update((c) => c.copyWith(
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
        ));
  }

  // ---- Geolocation ----

  void _applyGeolocation() {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final rad = double.tryParse(_radiusCtrl.text) ?? 10.0;
    final nearTitleText = _nearTitleCtrl.text.trim();
    final nearTitleRad = double.tryParse(_nearTitleRadiusCtrl.text) ?? 10.0;

    NearCoordFilter? coordFilter;
    NearTitleFilter? titleFilter;
    if (nearTitleText.isNotEmpty) {
      titleFilter = NearTitleFilter(title: nearTitleText, radiusKm: nearTitleRad);
    } else if (lat != null && lng != null) {
      coordFilter = NearCoordFilter(lat: lat, lng: lng, radiusKm: rad);
    }

    _update((c) => c.copyWith(
          nearCoord: coordFilter,
          clearNearCoord: coordFilter == null,
          nearTitle: titleFilter,
          clearNearTitle: titleFilter == null,
        ));
  }

  // ---- Dates ----

  void _applyDates() {
    final cFrom = _createdFromCtrl.text.trim();
    final cTo = _createdToCtrl.text.trim();
    final eFrom = _editedFromCtrl.text.trim();
    final eTo = _editedToCtrl.text.trim();
    final created = (cFrom.isNotEmpty || cTo.isNotEmpty) ? DateFilter(from: cFrom, to: cTo) : null;
    final edited = (eFrom.isNotEmpty || eTo.isNotEmpty) ? DateFilter(from: eFrom, to: eTo) : null;

    _update((c) => c.copyWith(
          createdDate: created,
          clearCreatedDate: created == null,
          editedDate: edited,
          clearEditedDate: edited == null,
        ));
  }

  // ---- Language / content model — single free-text fields, applied
  // instantly on submit rather than batched, since there's nothing
  // multi-step about typing one code and hitting enter. ----

  void _applyLanguage(String text) {
    final lang = text.trim().isEmpty ? null : text.trim();
    _update((c) => c.copyWith(languageCode: lang, clearLanguageCode: lang == null));
  }

  void _applyContentModel(String text) {
    final model = text.trim().isEmpty ? null : text.trim();
    _update((c) => c.copyWith(contentModel: model, clearContentModel: model == null));
  }

  // ---- Categories (instant) ----

  void _addCategory(String value, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            excludeCategories: {...c.excludeCategories, value},
            categories: c.categories.where((v) => v != value).toSet(),
          )
        : c.copyWith(
            categories: {...c.categories, value},
            excludeCategories: c.excludeCategories.where((v) => v != value).toSet(),
          ));
  }

  void _removeCategoryInclude(String value) =>
      _update((c) => c.copyWith(categories: c.categories.where((v) => v != value).toSet()));
  void _removeCategoryExclude(String value) =>
      _update((c) => c.copyWith(excludeCategories: c.excludeCategories.where((v) => v != value).toSet()));

  // ---- Templates (instant) ----

  void _addTemplate(String value, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            excludeTemplates: {...c.excludeTemplates, value},
            templates: c.templates.where((v) => v != value).toSet(),
          )
        : c.copyWith(
            templates: {...c.templates, value},
            excludeTemplates: c.excludeTemplates.where((v) => v != value).toSet(),
          ));
  }

  void _removeTemplateInclude(String value) =>
      _update((c) => c.copyWith(templates: c.templates.where((v) => v != value).toSet()));
  void _removeTemplateExclude(String value) =>
      _update((c) => c.copyWith(excludeTemplates: c.excludeTemplates.where((v) => v != value).toSet()));

  // ---- Depicts (instant) ----

  void _addDepicts(DepictsEntity value, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            depictsExclude: {...c.depictsExclude, value},
            depictsInclude: c.depictsInclude.where((v) => v != value).toSet(),
          )
        : c.copyWith(
            depictsInclude: {...c.depictsInclude, value},
            depictsExclude: c.depictsExclude.where((v) => v != value).toSet(),
          ));
  }

  void _removeDepictsInclude(DepictsEntity value) =>
      _update((c) => c.copyWith(depictsInclude: c.depictsInclude.where((v) => v != value).toSet()));
  void _removeDepictsExclude(DepictsEntity value) =>
      _update((c) => c.copyWith(depictsExclude: c.depictsExclude.where((v) => v != value).toSet()));

  void _setDepictsUnion(bool union) => _update((c) => c.copyWith(depictsUnion: union));
  void _setCategoriesUnion(bool union) => _update((c) => c.copyWith(categoriesUnion: union));
  void _setDeepCategoryMode(bool deep) => _update((c) => c.copyWith(deepCategoryMode: deep));
  void _setStatementsUnion(bool union) => _update((c) => c.copyWith(statementsUnion: union));

  // ---- Statements (instant, two-step property -> value) ----

  void _addStatement(WikidataStatement stmt, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            statementsExclude: {...c.statementsExclude, stmt},
            statementsInclude: c.statementsInclude.where((v) => v != stmt).toSet(),
          )
        : c.copyWith(
            statementsInclude: {...c.statementsInclude, stmt},
            statementsExclude: c.statementsExclude.where((v) => v != stmt).toSet(),
          ));
  }

  void _removeStatementInclude(WikidataStatement stmt) =>
      _update((c) => c.copyWith(statementsInclude: c.statementsInclude.where((v) => v != stmt).toSet()));
  void _removeStatementExclude(WikidataStatement stmt) =>
      _update((c) => c.copyWith(statementsExclude: c.statementsExclude.where((v) => v != stmt).toSet()));

  @override
  Widget build(BuildContext context) {
    // Keeps the range-filter controllers honest against external changes
    // (URL hydrate, chip removal on the main search page) even though this
    // widget itself may live far longer than any single search now.
    ref.listen(searchControllerProvider.select((s) => s.filterState), (previous, next) {
      if (previous == next) return;
      _syncControllersFromState(next);
    });

    final state = ref.watch(searchControllerProvider).filterState;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('FILTERS',
                    style: TextStyle(
                        color: Colors.white, fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w800)),
                if (widget.showCloseButton)
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
                _sectionDivider('IMAGE CLASSIFICATION'),
                const SizedBox(height: 20),

                _sectionHeader('DEPICTS (SUBJECT)'),
                Row(
                  children: [
                    Expanded(
                      child: _combineModeButton(
                        label: 'Intersection (AND)',
                        selected: !state.depictsUnion,
                        onTap: () => _setDepictsUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union (OR)',
                        selected: state.depictsUnion,
                        onTap: () => _setDepictsUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  state.depictsUnion
                      ? 'Matches files depicting ANY selected subject below (this OR this), still excluding anything marked "not".'
                      : 'Matches files depicting ALL selected subjects below (this AND this), and excludes anything marked "not".',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _EntitySetPicker<DepictsEntity>(
                  include: state.depictsInclude,
                  exclude: state.depictsExclude,
                  labelOf: (d) => d.label,
                  descriptionOf: (d) => d.description,
                  search: (text) => _service.searchDepictsEntities(text),
                  addHint: 'e.g. Cat, Eiffel Tower...',
                  excludeHint: 'Exclude subject...',
                  onAdd: _addDepicts,
                  onRemoveInclude: _removeDepictsInclude,
                  onRemoveExclude: _removeDepictsExclude,
                ),
                const SizedBox(height: 24),

                _sectionHeader('WIKIDATA PROPERTY SEARCH'),
                Row(
                  children: [
                    Expanded(
                      child: _combineModeButton(
                        label: 'Intersection (AND)',
                        selected: !state.statementsUnion,
                        onTap: () => _setStatementsUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union (OR)',
                        selected: state.statementsUnion,
                        onTap: () => _setStatementsUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  state.statementsUnion
                      ? 'Matches ANY selected property below (this OR this), still excluding anything marked "not".'
                      : 'Matches ALL selected properties below (this AND this), and excludes anything marked "not".',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _StatementsPicker(
                  include: state.statementsInclude,
                  exclude: state.statementsExclude,
                  service: _service,
                  onAdd: _addStatement,
                  onRemoveInclude: _removeStatementInclude,
                  onRemoveExclude: _removeStatementExclude,
                ),
                const SizedBox(height: 24),

                _sectionHeader('CATEGORIES'),
                Row(
                  children: [
                    Expanded(
                      child: _combineModeButton(
                        label: 'Intersection (AND)',
                        selected: !state.categoriesUnion,
                        onTap: () => _setCategoriesUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union (OR)',
                        selected: state.categoriesUnion,
                        onTap: () => _setCategoriesUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  state.categoriesUnion
                      ? 'Matches files in ANY selected category below (this OR this), still excluding anything marked "not".'
                      : 'Matches files in ALL selected categories below (this AND this), and excludes anything marked "not".',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _StringSetPicker(
                  include: state.categories,
                  exclude: state.excludeCategories,
                  search: (text) => _service.searchCategories(text),
                  addHint: 'Search categories...',
                  excludeHint: 'Exclude category...',
                  onAdd: _addCategory,
                  onRemoveInclude: _removeCategoryInclude,
                  onRemoveExclude: _removeCategoryExclude,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: state.deepCategoryMode
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
                                color: state.deepCategoryMode ? Colors.white : Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state.deepCategoryMode
                                  ? 'Deep: also pulls files from every subcategory nested beneath the categories above.'
                                  : 'Strict: only files filed directly in the exact categories above — nested subcategories are skipped.',
                              style: const TextStyle(color: Color(0xFF888888), fontSize: 11, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Switch(
                        value: state.deepCategoryMode,
                        activeColor: const Color(0xFF3D7EFF),
                        onChanged: _setDeepCategoryMode,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                _sectionHeader('QUALITY ASSESSMENT'),
                DropdownButtonFormField<QualityFilter>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _fieldDecoration(),
                  value: state.qualityFilter,
                  items: QualityFilter.values
                      .map((q) => DropdownMenuItem(
                          value: q, child: Text(qualityFilterLabel(q), style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) _update((c) => c.copyWith(qualityFilter: val));
                  },
                ),
                const SizedBox(height: 24),

                _sectionDivider('LICENSE'),
                const SizedBox(height: 20),
                _sectionHeader('LICENSE / RIGHTS'),
                DropdownButtonFormField<LicensePreset>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _fieldDecoration(),
                  value: state.licensePreset,
                  items: LicensePreset.values
                      .map((preset) => DropdownMenuItem(
                          value: preset,
                          child: Text(licensePresetLabel(preset), style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) _update((c) => c.copyWith(licensePreset: val));
                  },
                ),
                const SizedBox(height: 24),

                _sectionDivider('METADATA AND LOCATION'),
                const SizedBox(height: 20),

                _sectionHeader('LANGUAGE & CONTENT'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _langCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'Lang (en)'),
                        onSubmitted: _applyLanguage,
                        onTapOutside: (_) => _applyLanguage(_langCtrl.text),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _modelCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'Model (wikitext)'),
                        onSubmitted: _applyContentModel,
                        onTapOutside: (_) => _applyContentModel(_modelCtrl.text),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                _sectionHeader('DATES (YYYY-MM-DD)'),
                Text('CREATED', style: _groupLabelStyle()),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _createdFromCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'From'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _createdToCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'To'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('EDITED', style: _groupLabelStyle()),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _editedFromCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'From'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _editedToCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'To'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _groupApplyButton('Apply Dates', _applyDates),
                const SizedBox(height: 24),

                _sectionHeader('RESOLUTION BOUNDS'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minWidthCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'Min width px'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _minHeightCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'Min height px'),
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
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'Max width px'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxHeightCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'Max height px'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('FILE SIZE & COLOR DEPTH', style: _groupLabelStyle()),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _combineModeButton(
                        label: 'MB',
                        selected: _fileSizeUnitMB,
                        onTap: () => setState(() => _fileSizeUnitMB = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            _fieldDecoration(hint: _fileSizeUnitMB ? 'Min size (MB)' : 'Min size (KB)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxFileSizeCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration:
                            _fieldDecoration(hint: _fileSizeUnitMB ? 'Max size (MB)' : 'Max size (KB)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _fieldDecoration(hint: 'Any color depth'),
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
                const SizedBox(height: 12),
                _groupApplyButton('Apply Resolution & Size', _applyResolutionAndSize),
                const SizedBox(height: 24),

                _sectionHeader('TEMPLATES'),
                Text(
                  'Matches files carrying a specific template — e.g. a GLAM/institutional '
                  'set ("Institution:Metropolitan Museum of Art") or a granular PD template '
                  '("PD-USGov-NASA"). Always required (AND), no union mode.',
                  style: const TextStyle(color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _StringSetPicker(
                  include: state.templates,
                  exclude: state.excludeTemplates,
                  search: (text) => _service.searchTemplates(text),
                  addHint: 'e.g. PD-USGov-NASA',
                  excludeHint: 'Exclude template name...',
                  onAdd: _addTemplate,
                  onRemoveInclude: _removeTemplateInclude,
                  onRemoveExclude: _removeTemplateExclude,
                ),
                const SizedBox(height: 24),

                _sectionHeader('GEOLOCATION (LAT / LNG / RADIUS KM)'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _latCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'Lat'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        keyboardType: _urlKeyboardType(),
                        controller: _lngCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'Lng'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _radiusCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'km'),
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
                              color: Color(0xFF555555), fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
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
                        keyboardType: _urlKeyboardType(),
                        controller: _nearTitleCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _fieldDecoration(hint: 'e.g. Eiffel Tower'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _nearTitleRadiusCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: _fieldDecoration(hint: 'km'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _groupApplyButton('Apply Geolocation', _applyGeolocation),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextInputType _urlKeyboardType() {
    return (kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android))
        ? TextInputType.text
        : TextInputType.url;
  }

  TextStyle _groupLabelStyle() => const TextStyle(
      color: Color(0xFF666666), fontSize: 9.5, letterSpacing: 1.2, fontWeight: FontWeight.w700);

  Widget _groupApplyButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF7AABFF),
          side: const BorderSide(color: Color(0xFF2A4A8A)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Generic string include/exclude picker — replaces the near-identical
// Categories and Templates blocks that used to be copy-pasted by hand.
// Applies instantly via widget.onAdd/onRemoveInclude/onRemoveExclude;
// only the exclude-mode toggle and the text-entry field are local UI state.
// -----------------------------------------------------------------------------

class _StringSetPicker extends StatefulWidget {
  final Set<String> include;
  final Set<String> exclude;
  final Future<List<String>> Function(String query) search;
  final String addHint;
  final String excludeHint;
  final void Function(String value, bool exclude) onAdd;
  final void Function(String value) onRemoveInclude;
  final void Function(String value) onRemoveExclude;

  const _StringSetPicker({
    required this.include,
    required this.exclude,
    required this.search,
    required this.addHint,
    required this.excludeHint,
    required this.onAdd,
    required this.onRemoveInclude,
    required this.onRemoveExclude,
  });

  @override
  State<_StringSetPicker> createState() => _StringSetPickerState();
}

class _StringSetPickerState extends State<_StringSetPicker> {
  bool _excludeMode = false;
  TextEditingController? _fieldController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.include.isNotEmpty || widget.exclude.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...widget.include.map((c) => _filterChip(label: c, excluded: false, onDeleted: () => widget.onRemoveInclude(c))),
              ...widget.exclude.map((c) => _filterChip(label: c, excluded: true, onDeleted: () => widget.onRemoveExclude(c))),
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
                  if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
                  return await widget.search(textEditingValue.text);
                },
                onSelected: (selection) {
                  widget.onAdd(selection, _excludeMode);
                  _fieldController?.clear();
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  _fieldController = controller;
                  void addFromField() {
                    final val = controller.text.trim();
                    if (val.isEmpty) return;
                    widget.onAdd(val, _excludeMode);
                    controller.clear();
                  }

                  return TextField(
                    keyboardType: (kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android))
                        ? TextInputType.text
                        : TextInputType.url,
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(hint: _excludeMode ? widget.excludeHint : widget.addHint).copyWith(
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add, color: Colors.white54, size: 18),
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
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option, style: const TextStyle(color: Colors.white)),
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
            _excludeModeToggle(excludeMode: _excludeMode, onChanged: (val) => setState(() => _excludeMode = val)),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Generic entity (Wikidata Q-code) include/exclude picker — used for Depicts.
// Same shape as _StringSetPicker but for typed entities that carry a QID +
// label rather than bare strings.
// -----------------------------------------------------------------------------

class _EntitySetPicker<T extends Object> extends StatefulWidget {
  final Set<T> include;
  final Set<T> exclude;
  final String Function(T) labelOf;
  final String? Function(T)? descriptionOf;
  final Future<List<T>> Function(String query) search;
  final String addHint;
  final String excludeHint;
  final void Function(T value, bool exclude) onAdd;
  final void Function(T value) onRemoveInclude;
  final void Function(T value) onRemoveExclude;

  const _EntitySetPicker({
    required this.include,
    required this.exclude,
    required this.labelOf,
    this.descriptionOf,
    required this.search,
    required this.addHint,
    required this.excludeHint,
    required this.onAdd,
    required this.onRemoveInclude,
    required this.onRemoveExclude,
  });

  @override
  State<_EntitySetPicker<T>> createState() => _EntitySetPickerState<T>();
}

class _EntitySetPickerState<T extends Object> extends State<_EntitySetPicker<T>> {
  bool _excludeMode = false;
  TextEditingController? _fieldController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.include.isNotEmpty || widget.exclude.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...widget.include.map((d) =>
                  _filterChip(label: widget.labelOf(d), excluded: false, onDeleted: () => widget.onRemoveInclude(d))),
              ...widget.exclude.map((d) =>
                  _filterChip(label: widget.labelOf(d), excluded: true, onDeleted: () => widget.onRemoveExclude(d))),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Autocomplete<T>(
                displayStringForOption: widget.labelOf,
                optionsBuilder: (textEditingValue) async {
                  if (textEditingValue.text.isEmpty) return const Iterable<Never>.empty();
                  return await widget.search(textEditingValue.text);
                },
                onSelected: (selection) {
                  widget.onAdd(selection, _excludeMode);
                  _fieldController?.clear();
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  _fieldController = controller;
                  return TextField(
                    keyboardType: (kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android))
                        ? TextInputType.text
                        : TextInputType.url,
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(hint: _excludeMode ? widget.excludeHint : widget.addHint),
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
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final description = widget.descriptionOf?.call(option);
                            return ListTile(
                              title: Text(widget.labelOf(option), style: const TextStyle(color: Colors.white)),
                              subtitle: description != null
                                  ? Text(description, style: const TextStyle(color: Colors.white54, fontSize: 11))
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
            _excludeModeToggle(excludeMode: _excludeMode, onChanged: (val) => setState(() => _excludeMode = val)),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Statements — kept bespoke rather than folded into _EntitySetPicker: it's a
// genuine two-step flow (pick a property, then pick a value for it) rather
// than a single-entity add, so forcing it into the generic shape would cost
// more than it saves. Still instant-apply, same as everything else here.
// -----------------------------------------------------------------------------

class _StatementsPicker extends StatefulWidget {
  final Set<WikidataStatement> include;
  final Set<WikidataStatement> exclude;
  final SearchService service;
  final void Function(WikidataStatement stmt, bool exclude) onAdd;
  final void Function(WikidataStatement stmt) onRemoveInclude;
  final void Function(WikidataStatement stmt) onRemoveExclude;

  const _StatementsPicker({
    required this.include,
    required this.exclude,
    required this.service,
    required this.onAdd,
    required this.onRemoveInclude,
    required this.onRemoveExclude,
  });

  @override
  State<_StatementsPicker> createState() => _StatementsPickerState();
}

class _StatementsPickerState extends State<_StatementsPicker> {
  bool _excludeMode = false;
  DepictsEntity? _pendingProperty;
  TextEditingController? _propertyFieldController;
  TextEditingController? _valueFieldController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.include.isNotEmpty || widget.exclude.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...widget.include.map((s) => _filterChip(
                  label: '${s.property.label}: ${s.value.label}',
                  excluded: false,
                  onDeleted: () => widget.onRemoveInclude(s))),
              ...widget.exclude.map((s) => _filterChip(
                  label: '${s.property.label}: ${s.value.label}',
                  excluded: true,
                  onDeleted: () => widget.onRemoveExclude(s))),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (_pendingProperty != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF13203A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF3D7EFF)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 14, color: Color(0xFF3D7EFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Property: ${_pendingProperty!.label} — now search a value',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                  onPressed: () => setState(() => _pendingProperty = null),
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
                key: ValueKey(_pendingProperty == null ? 'statement-property' : 'statement-value'),
                displayStringForOption: (option) => option.label,
                optionsBuilder: (textEditingValue) async {
                  if (textEditingValue.text.isEmpty) return const Iterable<DepictsEntity>.empty();
                  return _pendingProperty == null
                      ? await widget.service.searchWikidataProperties(textEditingValue.text)
                      : await widget.service.searchDepictsEntities(textEditingValue.text);
                },
                onSelected: (selection) {
                  if (_pendingProperty == null) {
                    setState(() => _pendingProperty = selection);
                    _propertyFieldController?.clear();
                  } else {
                    final stmt = WikidataStatement(property: _pendingProperty!, value: selection);
                    widget.onAdd(stmt, _excludeMode);
                    setState(() => _pendingProperty = null);
                    _valueFieldController?.clear();
                  }
                },
                fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                  if (_pendingProperty == null) {
                    _propertyFieldController = controller;
                  } else {
                    _valueFieldController = controller;
                  }
                  return TextField(
                    keyboardType: (kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform == TargetPlatform.android))
                        ? TextInputType.text
                        : TextInputType.url,
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(
                        hint: _pendingProperty == null
                            ? 'Search property (e.g. location of creation)...'
                            : 'Search value (e.g. Paris)...'),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      color: const Color(0xFF1E1E1E),
                      elevation: 4,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option.label, style: const TextStyle(color: Colors.white)),
                              subtitle: option.description != null
                                  ? Text(option.description!, style: const TextStyle(color: Colors.white54, fontSize: 11))
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
            _excludeModeToggle(excludeMode: _excludeMode, onChanged: (val) => setState(() => _excludeMode = val)),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Shared presentational helpers — top-level (library-private) so every
// picker widget above can use them without an instance.
// -----------------------------------------------------------------------------

Widget _sectionDivider(String label) {
  return Row(
    children: [
      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label,
            style: const TextStyle(color: Color(0xFF3D7EFF), fontSize: 12, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
      ),
      const Expanded(child: Divider(color: Color(0xFF2A2A2A), thickness: 1.2)),
    ],
  );
}

Widget _sectionHeader(String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(color: Color(0xFF7A7A7A), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5),
    ),
  );
}

Widget _filterChip({required String label, required bool excluded, required VoidCallback onDeleted}) {
  return Chip(
    label: Text(
      excluded ? '− $label' : label,
      style: TextStyle(color: excluded ? const Color(0xFFFF6B6B) : Colors.white, fontSize: 11),
    ),
    backgroundColor: excluded ? const Color(0xFF2A1414) : const Color(0xFF222222),
    deleteIconColor: excluded ? const Color(0xFFFF6B6B) : Colors.white54,
    side: excluded ? const BorderSide(color: Color(0xFF4A2020)) : BorderSide.none,
    onDeleted: onDeleted,
  );
}

Widget _excludeModeToggle({required bool excludeMode, required ValueChanged<bool> onChanged}) {
  return Container(
    decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.all(3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toggleSegment(label: '+', selected: !excludeMode, color: const Color(0xFF3D7EFF), onTap: () => onChanged(false)),
        _toggleSegment(label: '−', selected: excludeMode, color: const Color(0xFFFF6B6B), onTap: () => onChanged(true)),
      ],
    ),
  );
}

Widget _toggleSegment({required String label, required bool selected, required Color color, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? color : Colors.transparent),
      ),
      child: Text(label, style: TextStyle(color: selected ? color : Colors.white38, fontWeight: FontWeight.bold, fontSize: 16)),
    ),
  );
}

Widget _combineModeButton({required String label, required bool selected, required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF3D7EFF).withOpacity(0.15) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: selected ? const Color(0xFF3D7EFF) : const Color(0xFF262626)),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? const Color(0xFF3D7EFF) : Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
    ),
  );
}

InputDecoration _fieldDecoration({String? hint}) {
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFF1A1A1A),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
  );
}