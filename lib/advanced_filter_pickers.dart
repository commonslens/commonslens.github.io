part of 'advanced_filters_drawer.dart';

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
  final _requests = AutocompleteRequestCoordinator<String>();

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

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
              ...widget.include.map((c) => _filterChip(
                  label: c,
                  excluded: false,
                  onDeleted: () => widget.onRemoveInclude(c))),
              ...widget.exclude.map((c) => _filterChip(
                  label: c,
                  excluded: true,
                  onDeleted: () => widget.onRemoveExclude(c))),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Autocomplete<String>(
                optionsBuilder: (value) =>
                    _requests.load(value.text, widget.search),
                onSelected: (selection) {
                  widget.onAdd(selection, _excludeMode);
                  _fieldController?.clear();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
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
                                defaultTargetPlatform ==
                                    TargetPlatform.android))
                        ? TextInputType.text
                        : TextInputType.url,
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(
                            hint: _excludeMode
                                ? widget.excludeHint
                                : widget.addHint)
                        .copyWith(
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
                        constraints:
                            const BoxConstraints(maxHeight: 200, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option,
                                  style: const TextStyle(color: Colors.white)),
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
            _excludeModeToggle(
                excludeMode: _excludeMode,
                onChanged: (val) => setState(() => _excludeMode = val)),
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

class _EntitySetPickerState<T extends Object>
    extends State<_EntitySetPicker<T>> {
  bool _excludeMode = false;
  TextEditingController? _fieldController;
  final _requests = AutocompleteRequestCoordinator<T>();

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

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
              ...widget.include.map((d) => _filterChip(
                  label: widget.labelOf(d),
                  excluded: false,
                  onDeleted: () => widget.onRemoveInclude(d))),
              ...widget.exclude.map((d) => _filterChip(
                  label: widget.labelOf(d),
                  excluded: true,
                  onDeleted: () => widget.onRemoveExclude(d))),
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
                optionsBuilder: (value) =>
                    _requests.load(value.text, widget.search),
                onSelected: (selection) {
                  widget.onAdd(selection, _excludeMode);
                  _fieldController?.clear();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  _fieldController = controller;
                  return TextField(
                    keyboardType: (kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform ==
                                    TargetPlatform.android))
                        ? TextInputType.text
                        : TextInputType.url,
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: _fieldDecoration(
                        hint:
                            _excludeMode ? widget.excludeHint : widget.addHint),
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
                        constraints:
                            const BoxConstraints(maxHeight: 200, maxWidth: 300),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            final description =
                                widget.descriptionOf?.call(option);
                            return ListTile(
                              title: Text(widget.labelOf(option),
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: description != null
                                  ? Text(description,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11))
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
            _excludeModeToggle(
                excludeMode: _excludeMode,
                onChanged: (val) => setState(() => _excludeMode = val)),
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

class _StatementsPicker extends ConsumerStatefulWidget {
  final Set<WikidataStatement> include;
  final Set<WikidataStatement> exclude;
  final void Function(WikidataStatement stmt, bool exclude) onAdd;
  final void Function(WikidataStatement stmt) onRemoveInclude;
  final void Function(WikidataStatement stmt) onRemoveExclude;

  const _StatementsPicker({
    required this.include,
    required this.exclude,
    required this.onAdd,
    required this.onRemoveInclude,
    required this.onRemoveExclude,
  });

  @override
  ConsumerState<_StatementsPicker> createState() => _StatementsPickerState();
}

class _StatementsPickerState extends ConsumerState<_StatementsPicker> {
  bool _excludeMode = false;
  DepictsEntity? _pendingProperty;
  TextEditingController? _propertyFieldController;
  TextEditingController? _valueFieldController;
  final _requests = AutocompleteRequestCoordinator<DepictsEntity>();

  @override
  void dispose() {
    _requests.dispose();
    super.dispose();
  }

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
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFF3D7EFF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Property: ${_pendingProperty!.label} — now search a value',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, size: 16, color: Colors.white54),
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
                key: ValueKey(_pendingProperty == null
                    ? 'statement-property'
                    : 'statement-value'),
                displayStringForOption: (option) => option.label,
                optionsBuilder: (value) {
                  final propertySearch = _pendingProperty == null;
                  return _requests.load(value.text, (query) {
                    return propertySearch
                        ? ref
                            .read(commonsAutocompleteProvider)
                            .wikidataProperties(query)
                        : ref
                            .read(commonsAutocompleteProvider)
                            .wikidataEntities(query);
                  });
                },
                onSelected: (selection) {
                  _requests.cancel();
                  if (_pendingProperty == null) {
                    setState(() => _pendingProperty = selection);
                    _propertyFieldController?.clear();
                  } else {
                    final stmt = WikidataStatement(
                        property: _pendingProperty!, value: selection);
                    widget.onAdd(stmt, _excludeMode);
                    setState(() => _pendingProperty = null);
                    _valueFieldController?.clear();
                  }
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  if (_pendingProperty == null) {
                    _propertyFieldController = controller;
                  } else {
                    _valueFieldController = controller;
                  }
                  return TextField(
                    keyboardType: (kIsWeb &&
                            (defaultTargetPlatform == TargetPlatform.iOS ||
                                defaultTargetPlatform ==
                                    TargetPlatform.android))
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
                        constraints:
                            const BoxConstraints(maxHeight: 200, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(option.label,
                                  style: const TextStyle(color: Colors.white)),
                              subtitle: option.description != null
                                  ? Text(option.description!,
                                      style: const TextStyle(
                                          color: Colors.white54, fontSize: 11))
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
            _excludeModeToggle(
                excludeMode: _excludeMode,
                onChanged: (val) => setState(() => _excludeMode = val)),
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
            style: const TextStyle(
                color: Color(0xFF3D7EFF),
                fontSize: 12,
                letterSpacing: 1.8,
                fontWeight: FontWeight.w800)),
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
      style: const TextStyle(
          color: Color(0xFF7A7A7A),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5),
    ),
  );
}

Widget _filterChip(
    {required String label,
    required bool excluded,
    required VoidCallback onDeleted}) {
  return Chip(
    label: Text(
      excluded ? '− $label' : label,
      style: TextStyle(
          color: excluded ? const Color(0xFFFF6B6B) : Colors.white,
          fontSize: 11),
    ),
    backgroundColor:
        excluded ? const Color(0xFF2A1414) : const Color(0xFF222222),
    deleteIconColor: excluded ? const Color(0xFFFF6B6B) : Colors.white54,
    side:
        excluded ? const BorderSide(color: Color(0xFF4A2020)) : BorderSide.none,
    onDeleted: onDeleted,
  );
}

Widget _excludeModeToggle(
    {required bool excludeMode, required ValueChanged<bool> onChanged}) {
  return Container(
    decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8)),
    padding: const EdgeInsets.all(3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _toggleSegment(
            label: '+',
            selected: !excludeMode,
            color: const Color(0xFF3D7EFF),
            onTap: () => onChanged(false)),
        _toggleSegment(
            label: '−',
            selected: excludeMode,
            color: const Color(0xFFFF6B6B),
            onTap: () => onChanged(true)),
      ],
    ),
  );
}

Widget _toggleSegment(
    {required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? color : Colors.transparent),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? color : Colors.white38,
              fontWeight: FontWeight.bold,
              fontSize: 16)),
    ),
  );
}

Widget _combineModeButton(
    {required String label,
    required bool selected,
    required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF3D7EFF).withValues(alpha: 0.15)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color:
                selected ? const Color(0xFF3D7EFF) : const Color(0xFF262626)),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? const Color(0xFF3D7EFF) : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    ),
  );
}

Widget _licenseToggleChip(
    {required String label,
    required bool selected,
    required VoidCallback onTap}) {
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF3D7EFF).withValues(alpha: 0.15)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color:
                selected ? const Color(0xFF3D7EFF) : const Color(0xFF262626)),
      ),
      child: Text(label,
          style: TextStyle(
              color: selected ? const Color(0xFF3D7EFF) : Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w700)),
    ),
  );
}

InputDecoration _fieldDecoration({String? hint}) {
  return InputDecoration(
    filled: true,
    fillColor: const Color(0xFF1A1A1A),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white30),
  );
}
