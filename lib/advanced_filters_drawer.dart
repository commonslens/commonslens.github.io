import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'search_models.dart';
import 'search_controller.dart';
import 'backend_providers.dart';
import 'autocomplete_request_coordinator.dart';

part 'advanced_filter_pickers.dart';

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
    final drawerWidth = width < 480 ? width : 420.0;
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
  // Non-null only in the desktop docked layout (see search_page.dart's
  // isDesktop branch). Renders a collapse chevron in the header next to
  // (or instead of) the close button, so the sidebar can be minimized to a
  // thin rail without a Drawer to pop — a docked panel is never "closed",
  // only collapsed and re-expandable in place.
  final VoidCallback? onCollapse;
  const FilterPanelContent({
    super.key,
    this.showCloseButton = false,
    this.onCollapse,
  });

  @override
  ConsumerState<FilterPanelContent> createState() => _FilterPanelContentState();
}

class _FilterPanelContentState extends ConsumerState<FilterPanelContent> {
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
    _minWidthCtrl =
        TextEditingController(text: state.minWidth?.toString() ?? '');
    _minHeightCtrl =
        TextEditingController(text: state.minHeight?.toString() ?? '');
    _maxWidthCtrl =
        TextEditingController(text: state.maxWidth?.toString() ?? '');
    _maxHeightCtrl =
        TextEditingController(text: state.maxHeight?.toString() ?? '');
    _minFileSizeCtrl =
        TextEditingController(text: _bytesToMBText(state.minFileSizeBytes));
    _maxFileSizeCtrl =
        TextEditingController(text: _bytesToMBText(state.maxFileSizeBytes));
    _colorDepthBits = state.colorDepthBits;

    _latCtrl =
        TextEditingController(text: state.nearCoord?.lat.toString() ?? '');
    _lngCtrl =
        TextEditingController(text: state.nearCoord?.lng.toString() ?? '');
    _radiusCtrl = TextEditingController(
        text: state.nearCoord?.radiusKm.toString() ?? '10');
    _nearTitleCtrl = TextEditingController(text: state.nearTitle?.title ?? '');
    _nearTitleRadiusCtrl = TextEditingController(
        text: state.nearTitle?.radiusKm.toString() ?? '10');

    _langCtrl = TextEditingController(text: state.languageCode ?? '');
    _modelCtrl = TextEditingController(text: state.contentModel ?? '');
    _createdFromCtrl =
        TextEditingController(text: state.createdDate?.from ?? '');
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
    sync(_nearTitleRadiusCtrl,
        state.nearTitle?.radiusKm.toString() ?? _nearTitleRadiusCtrl.text);
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

  // ignore: unused_element
  void _applyGeolocation() {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final rad = double.tryParse(_radiusCtrl.text) ?? 10.0;
    final nearTitleText = _nearTitleCtrl.text.trim();
    final nearTitleRad = double.tryParse(_nearTitleRadiusCtrl.text) ?? 10.0;

    NearCoordFilter? coordFilter;
    NearTitleFilter? titleFilter;
    if (nearTitleText.isNotEmpty) {
      titleFilter =
          NearTitleFilter(title: nearTitleText, radiusKm: nearTitleRad);
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
    final created = (cFrom.isNotEmpty || cTo.isNotEmpty)
        ? DateFilter(from: cFrom, to: cTo)
        : null;
    final edited = (eFrom.isNotEmpty || eTo.isNotEmpty)
        ? DateFilter(from: eFrom, to: eTo)
        : null;

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
    _update(
        (c) => c.copyWith(languageCode: lang, clearLanguageCode: lang == null));
  }

  void _applyContentModel(String text) {
    final model = text.trim().isEmpty ? null : text.trim();
    _update((c) =>
        c.copyWith(contentModel: model, clearContentModel: model == null));
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
            excludeCategories:
                c.excludeCategories.where((v) => v != value).toSet(),
          ));
  }

  void _removeCategoryInclude(String value) => _update((c) =>
      c.copyWith(categories: c.categories.where((v) => v != value).toSet()));
  void _removeCategoryExclude(String value) => _update((c) => c.copyWith(
      excludeCategories: c.excludeCategories.where((v) => v != value).toSet()));

  // ---- Templates (instant) ----

  void _addTemplate(String value, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            excludeTemplates: {...c.excludeTemplates, value},
            templates: c.templates.where((v) => v != value).toSet(),
          )
        : c.copyWith(
            templates: {...c.templates, value},
            excludeTemplates:
                c.excludeTemplates.where((v) => v != value).toSet(),
          ));
  }

  void _removeTemplateInclude(String value) => _update((c) =>
      c.copyWith(templates: c.templates.where((v) => v != value).toSet()));
  void _removeTemplateExclude(String value) => _update((c) => c.copyWith(
      excludeTemplates: c.excludeTemplates.where((v) => v != value).toSet()));

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

  void _removeDepictsInclude(DepictsEntity value) => _update((c) => c.copyWith(
      depictsInclude: c.depictsInclude.where((v) => v != value).toSet()));
  void _removeDepictsExclude(DepictsEntity value) => _update((c) => c.copyWith(
      depictsExclude: c.depictsExclude.where((v) => v != value).toSet()));

  void _setDepictsUnion(bool union) =>
      _update((c) => c.copyWith(depictsUnion: union));
  void _setCategoriesUnion(bool union) =>
      _update((c) => c.copyWith(categoriesUnion: union));
  void _setDeepCategoryMode(bool deep) =>
      _update((c) => c.copyWith(deepCategoryMode: deep));
  void _setStatementsUnion(bool union) =>
      _update((c) => c.copyWith(statementsUnion: union));

  // ---- License (instant, multi-select — a file only ever carries one
  // license, so this is always an OR/"matches any selected" filter) ----

  void _toggleLicense(LicensePreset preset) {
    _update((c) {
      final next = Set<LicensePreset>.from(c.licensePresets);
      if (next.contains(preset)) {
        next.remove(preset);
      } else {
        next.add(preset);
      }
      return c.copyWith(licensePresets: next);
    });
  }

  // ---- Statements (instant, two-step property -> value) ----

  void _addStatement(WikidataStatement stmt, bool exclude) {
    _update((c) => exclude
        ? c.copyWith(
            statementsExclude: {...c.statementsExclude, stmt},
            statementsInclude:
                c.statementsInclude.where((v) => v != stmt).toSet(),
          )
        : c.copyWith(
            statementsInclude: {...c.statementsInclude, stmt},
            statementsExclude:
                c.statementsExclude.where((v) => v != stmt).toSet(),
          ));
  }

  void _removeStatementInclude(WikidataStatement stmt) =>
      _update((c) => c.copyWith(
          statementsInclude:
              c.statementsInclude.where((v) => v != stmt).toSet()));
  void _removeStatementExclude(WikidataStatement stmt) =>
      _update((c) => c.copyWith(
          statementsExclude:
              c.statementsExclude.where((v) => v != stmt).toSet()));

  @override
  Widget build(BuildContext context) {
    // Keeps the range-filter controllers honest against external changes
    // (URL hydrate, chip removal on the main search page) even though this
    // widget itself may live far longer than any single search now.
    ref.listen(searchControllerProvider.select((s) => s.filterState),
        (previous, next) {
      if (previous == next) return;
      _syncControllersFromState(next);
    });

    // Pagination and result-loading changes do not affect this panel. Using
    // select prevents those high-frequency changes from rebuilding its large
    // form tree independently of the parent-side rebuild isolation.
    final state = ref.watch(
      searchControllerProvider.select((value) => value.filterState),
    );

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
                        color: Colors.white,
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onCollapse != null)
                      IconButton(
                        icon: const Icon(Icons.chevron_right,
                            color: Colors.white54),
                        tooltip: 'Collapse filters',
                        onPressed: widget.onCollapse,
                      ),
                    if (widget.showCloseButton)
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white54),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                  ],
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
                GestureDetector(
                  onTap: () => context.push('/browse'),
                  child: const Text(
                    'Browse the full directory of categories, templates and Q-codes →',
                    style: TextStyle(
                        color: Color(0xFF3D7EFF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionHeader('DEPICTS (SUBJECT)'),
                Row(
                  children: [
                    Expanded(
                      child: _combineModeButton(
                        label: 'Intersection',
                        selected: !state.depictsUnion,
                        onTap: () => _setDepictsUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union',
                        selected: state.depictsUnion,
                        onTap: () => _setDepictsUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _EntitySetPicker<DepictsEntity>(
                  include: state.depictsInclude,
                  exclude: state.depictsExclude,
                  labelOf: (d) => d.label,
                  descriptionOf: (d) => d.description,
                  search: (text) => ref
                      .read(commonsAutocompleteProvider)
                      .wikidataEntities(text),
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
                        label: 'Intersection',
                        selected: !state.statementsUnion,
                        onTap: () => _setStatementsUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union',
                        selected: state.statementsUnion,
                        onTap: () => _setStatementsUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatementsPicker(
                  include: state.statementsInclude,
                  exclude: state.statementsExclude,
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
                        label: 'Intersection',
                        selected: !state.categoriesUnion,
                        onTap: () => _setCategoriesUnion(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _combineModeButton(
                        label: 'Union',
                        selected: state.categoriesUnion,
                        onTap: () => _setCategoriesUnion(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StringSetPicker(
                  include: state.categories,
                  exclude: state.excludeCategories,
                  search: (text) =>
                      ref.read(commonsAutocompleteProvider).categories(text),
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
                          ? const Color(0xFF3D7EFF).withValues(alpha: 0.4)
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
                                color: state.deepCategoryMode
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              state.deepCategoryMode
                                  ? 'Deep: also pulls files from every subcategory nested beneath the categories above.'
                                  : 'Strict: only files filed directly in these exact categories. Nested subcategories are skipped.',
                              style: const TextStyle(
                                  color: Color(0xFF888888),
                                  fontSize: 11,
                                  height: 1.4),
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
                _sectionHeader('TEMPLATES'),
                _StringSetPicker(
                  include: state.templates,
                  exclude: state.excludeTemplates,
                  search: (text) =>
                      ref.read(commonsAutocompleteProvider).templates(text),
                  addHint: 'e.g. PD-USGov-NASA',
                  excludeHint: 'Exclude template name...',
                  onAdd: _addTemplate,
                  onRemoveInclude: _removeTemplateInclude,
                  onRemoveExclude: _removeTemplateExclude,
                ),
                const SizedBox(height: 24),
                _sectionHeader('QUALITY ASSESSMENT'),
                DropdownButtonFormField<QualityFilter>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _fieldDecoration(),
                  value: state.qualityFilter,
                  items: QualityFilter.values
                      .map((q) => DropdownMenuItem(
                          value: q,
                          child: Text(qualityFilterLabel(q),
                              style: const TextStyle(color: Colors.white))))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _update((c) => c.copyWith(qualityFilter: val));
                    }
                  },
                ),
                const SizedBox(height: 24),
                _sectionDivider('LICENSE'),
                const SizedBox(height: 20),
                _sectionHeader('LICENSE / RIGHTS'),
                Text(
                  'Select one or more.',
                  style: const TextStyle(
                      color: Color(0xFF555555), fontSize: 10.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: LicensePreset.values
                      .map((preset) => _licenseToggleChip(
                            label: licensePresetLabel(preset),
                            selected: state.licensePresets.contains(preset),
                            onTap: () => _toggleLicense(preset),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 24),
                _sectionHeader('ATTRIBUTION'),
                const SizedBox(height: 12),
                DropdownButtonFormField<bool?>(
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _fieldDecoration(),
                  value: state.attributionRequired,
                  items: const [
                    DropdownMenuItem(
                        value: null,
                        child: Text('Any attribution',
                            style: TextStyle(color: Colors.white70))),
                    DropdownMenuItem(
                        value: true,
                        child: Text('Attribution required',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: false,
                        child: Text('No attribution required',
                            style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (val) => _update((c) => c.copyWith(
                      attributionRequired: val,
                      clearAttributionRequired: val == null)),
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
                        onTapOutside: (_) =>
                            _applyContentModel(_modelCtrl.text),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _fieldDecoration(hint: 'Min width px'),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _fieldDecoration(hint: 'Max width px'),
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _fieldDecoration(
                            hint: _fileSizeUnitMB
                                ? 'Min size (MB)'
                                : 'Min size (KB)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _maxFileSizeCtrl,
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: _fieldDecoration(
                            hint: _fileSizeUnitMB
                                ? 'Max size (MB)'
                                : 'Max size (KB)'),
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
                    DropdownMenuItem(
                        value: null,
                        child: Text('Any color depth',
                            style: TextStyle(color: Colors.white70))),
                    DropdownMenuItem(
                        value: 1,
                        child: Text('1-bit (monochrome)',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 8,
                        child: Text('8-bit',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 16,
                        child: Text('16-bit',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 24,
                        child: Text('24-bit',
                            style: TextStyle(color: Colors.white))),
                    DropdownMenuItem(
                        value: 32,
                        child: Text('32-bit',
                            style: TextStyle(color: Colors.white))),
                  ],
                  onChanged: (val) => setState(() => _colorDepthBits = val),
                ),
                const SizedBox(height: 12),
                _groupApplyButton(
                    'Apply Resolution & Size', _applyResolutionAndSize),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: _fieldDecoration(hint: 'km'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextInputType _urlKeyboardType() {
    return (kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.android))
        ? TextInputType.text
        : TextInputType.url;
  }

  TextStyle _groupLabelStyle() => const TextStyle(
      color: Color(0xFF666666),
      fontSize: 9.5,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700);

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
        child: Text(label,
            style:
                const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
