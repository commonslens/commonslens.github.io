import 'dart:async';

import 'package:commonslens/bulk_download_tray.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'search_models.dart';
import 'search_service.dart';
import 'search_url_codec.dart';
import 'backend_providers.dart';
import 'download_service.dart';
import 'autocomplete_request_coordinator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// -----------------------------------------------------------------------------
// Top Bar
// -----------------------------------------------------------------------------

class SearchTopBar extends ConsumerStatefulWidget {
  final String initialQuery;
  final ValueChanged<String> onSearch;
  final bool autofocus;

  // Hidden once the filter panel is permanently docked (desktop — see
  // SearchPage.build's isDesktop branch): there's nothing to "open" when
  // it's already visible on screen. True by default so the Drawer-based
  // mobile path (the only caller that matters below the dock breakpoint)
  // keeps its button without having to pass anything.
  final bool showFiltersButton;

  const SearchTopBar({
    super.key,
    required this.initialQuery,
    required this.onSearch,
    this.autofocus = false,
    this.showFiltersButton = true,
  });

  @override
  ConsumerState<SearchTopBar> createState() => _SearchTopBarState();
}

class _SearchTopBarState extends ConsumerState<SearchTopBar> {
  // The Autocomplete widget owns its internal TextEditingController; we
  // grab a reference in fieldViewBuilder so we can (a) push external
  // updates to widget.initialQuery into it — e.g. after a chip is removed
  // or a URL is hydrated — and (b) read/rewrite its text on suggestion
  // select, same pattern the drawer's category/depicts pickers use.
  TextEditingController? _fieldController;
  VoidCallback? _listener;
  bool _autofocusRequested = false;
  final _autocompleteRequests = AutocompleteRequestCoordinator<String>();

  @override
  void dispose() {
    _autocompleteRequests.dispose();
    if (_listener != null) _fieldController?.removeListener(_listener!);
    super.dispose();
  }

  @override
  void didUpdateWidget(SearchTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autofocus && widget.autofocus) {
      _autofocusRequested = false;
    }
    if (oldWidget.initialQuery != widget.initialQuery &&
        _fieldController != null &&
        _fieldController!.text != widget.initialQuery) {
      _fieldController!.text = widget.initialQuery;
    }
  }

  /// The "+"-segment the user is currently typing — i.e. everything after
  /// the last "cat + " separator, or the whole string if there isn't one.
  /// Mirrors SearchService.multiQuerySeparator exactly, so this can never
  /// disagree with how fetchPage itself splits the query.
  String _activeSegment(String fullText) {
    final matches = SearchService.multiQuerySeparator.allMatches(fullText);
    if (matches.isEmpty) return fullText;
    return fullText.substring(matches.last.end);
  }

  /// Splices a chosen suggestion into just the active segment, leaving
  /// every earlier "segment + segment" part untouched — including its
  /// exact original spacing around each "+".
  String _applySuggestion(String fullText, String suggestion) {
    final matches = SearchService.multiQuerySeparator.allMatches(fullText);
    if (matches.isEmpty) return suggestion;
    return fullText.substring(0, matches.last.end) + suggestion;
  }

  String _cleanSuggestionLabel(String value) {
    return value.replaceAll(
      RegExp(r'\.(jpg|png|svg|jpeg|gif|webm|tiff|djvu|pdf|oga|ogg|tif|webp)$',
          caseSensitive: false),
      '',
    );
  }

  FutureOr<Iterable<String>> _optionsBuilder(TextEditingValue value) {
    final segment = _activeSegment(value.text).trim();
    return _autocompleteRequests.load(segment, (query) async {
      final results =
          await ref.read(commonsAutocompleteProvider).queries(query);
      return results
          .map(_cleanSuggestionLabel)
          .where((title) => title.isNotEmpty)
          .toSet()
          .toList();
    });
  }

  /// Compact icon-only variant of the Filters button, used once the bar
  /// drops to mobile width (see build's isMobile).
  Widget _iconOnlyButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 38,
        height: 38,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF2A2A2A)),
              foregroundColor: const Color(0xFFB0B0B0),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6))),
          onPressed: onPressed,
          child: Icon(icon, size: 17),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Below this width the Filters control collapses to icon-only, and the
    // Search button disappears entirely. Enter/the field submit action
    // already triggers a search and leaves more room for the query.
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 38,
                child: Autocomplete<String>(
                  optionsBuilder: _optionsBuilder,
                  onSelected: (String suggestion) {
                    final newText = _applySuggestion(
                        _fieldController?.text ?? '', suggestion);
                    _fieldController?.value = TextEditingValue(
                      text: newText,
                      selection:
                          TextSelection.collapsed(offset: newText.length),
                    );
                    widget.onSearch(newText);
                  },
                  fieldViewBuilder:
                      (context, controller, focusNode, onFieldSubmitted) {
                    if (_fieldController != controller) {
                      if (_listener != null) {
                        _fieldController?.removeListener(_listener!);
                      }
                      _fieldController = controller;
                      if (controller.text != widget.initialQuery) {
                        controller.text = widget.initialQuery;
                      }
                      _listener = () => setState(() {});
                      controller.addListener(_listener!);
                    }

                    if (widget.autofocus && !_autofocusRequested) {
                      _autofocusRequested = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && widget.autofocus) {
                          focusNode.requestFocus();
                        }
                      });
                    }

                    return TextField(
                      keyboardType: (kIsWeb &&
                              (defaultTargetPlatform == TargetPlatform.iOS ||
                                  defaultTargetPlatform ==
                                      TargetPlatform.android))
                          ? TextInputType.text
                          : TextInputType.url,
                      textInputAction: TextInputAction.search,
                      autofocus: widget.autofocus,
                      autocorrect: false,
                      enableSuggestions: false,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(fontSize: 14, color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            'What would you like to find? The dropdown suggestions show direct file matches. To see all results for the search, just press enter/search.',
                        hintStyle:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF181818),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                                color: Color(0xFF3D7EFF), width: 1)),
                        suffixIcon: controller.text.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  controller.clear();
                                  widget.onSearch('');
                                },
                                child: const Icon(Icons.close,
                                    size: 15, color: Color(0xFF3A3A3A)))
                            : null,
                      ),
                      onSubmitted: (_) => widget.onSearch(controller.text),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: const Color(0xFF1E1E1E),
                        elevation: 4,
                        borderRadius: BorderRadius.circular(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              maxHeight: 260, maxWidth: 460),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.image_search,
                                    size: 16, color: Color(0xFF3D7EFF)),
                                title: Text(option,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13)),
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
            ),
            if (widget.showFiltersButton) ...[
              const SizedBox(width: 8),
              isMobile
                  ? _iconOnlyButton(
                      icon: Icons.tune,
                      tooltip: 'Filters',
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    )
                  : SizedBox(
                      height: 38,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF2A2A2A)),
                            foregroundColor: const Color(0xFFB0B0B0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14)),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        child: const Text('Filters',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ),
            ],
            if (!isMobile) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3D7EFF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 18)),
                  onPressed: () =>
                      widget.onSearch(_fieldController?.text ?? ''),
                  child: const Text('Search',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Landing / Empty State UI
// -----------------------------------------------------------------------------

class WikiLogo extends StatelessWidget {
  const WikiLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E1E1E)),
          color: const Color(0xFF141414)),
      child: const Icon(Icons.perm_media_rounded,
          size: 26, color: Color(0xFF3D7EFF)),
    );
  }
}

class ExampleChip extends StatefulWidget {
  final String category;
  final String label;
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  const ExampleChip({
    super.key,
    required this.category,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  @override
  State<ExampleChip> createState() => _ExampleChipState();
}

class _ExampleChipState extends State<ExampleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(18),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  color: _hovered
                      ? const Color(0xFF182032)
                      : const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _hovered
                        ? const Color(0xFF3D7EFF)
                        : const Color(0xFF292929),
                  ),
                  boxShadow: _hovered
                      ? const [
                          BoxShadow(
                            color: Color(0x263D7EFF),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 18,
                      color: const Color(0xFF7AABFF),
                    ),
                    const SizedBox(width: 9),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.category,
                          style: const TextStyle(
                            color: Color(0xFF6F8FC9),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.15,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            color: Color(0xFFD0D0D0),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Media Card Ecosystem
// -----------------------------------------------------------------------------

final RegExp _cardHtmlTagRegex = RegExp(r'<[^>]*>');

String _stripHtmlForCard(String value) =>
    value.isEmpty ? '' : value.replaceAll(_cardHtmlTagRegex, '').trim();

/// Object Name when available, falling back to Image Description, then the
/// filename.
String _displayTitle(SearchItem item) {
  final objectName = _stripHtmlForCard(item.objectName);
  if (objectName.isNotEmpty) return objectName;
  final desc = _stripHtmlForCard(item.imageDescriptionHtml);
  return desc.isNotEmpty ? desc : item.title;
}

const _cardMonthAbbrev = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "29 Aug '26" — tries the date of creation (capture time) first, since
/// that's what the person actually cares about, but some files have
/// dateTimeOriginal populated with junk (free text, "circa 1920", stray
/// annotations) that isn't a real parseable date. In that case this falls
/// through to the upload date, then the raw revision timestamp — each
/// candidate is try-parsed in turn and the first one that actually parses
/// wins, rather than committing to whichever field is merely non-empty.
String _formatPublishedDate(SearchItem item) {
  DateTime? dt;
  for (final candidate in [
    item.dateTimeOriginal.trim(),
    item.uploadDateTime.trim(),
    (item.timestamp ?? '').trim(),
  ]) {
    if (candidate.isEmpty) continue;
    dt = DateTime.tryParse(candidate);
    if (dt != null) break;
  }
  if (dt == null) return '';
  final yy = (dt.year % 100).toString().padLeft(2, '0');
  return "${dt.day} ${_cardMonthAbbrev[dt.month - 1]} '$yy";
}

const TextStyle _cardSubtitleStyle =
    TextStyle(color: Color(0xFFB0B0B0), fontSize: 11, height: 1.35);

/// Date pinned left, license pinned right, falling back to the original
/// snippet/mime as a single line when neither is available.
Widget _buildCardSubtitle(SearchItem item) {
  final date = _formatPublishedDate(item);
  final license = _stripHtmlForCard(item.licenseShortName);

  if (date.isEmpty && license.isEmpty) {
    final fallback = item.snippet.isEmpty ? item.mime : item.snippet;
    return Text(fallback,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _cardSubtitleStyle);
  }

  return Row(
    children: [
      Text(date,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cardSubtitleStyle),
      const Expanded(child: SizedBox.shrink()),
      Text(license,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _cardSubtitleStyle),
    ],
  );
}

/// A small always-tappable circular button overlaid on a [MediaCard]'s
/// thumbnail so any file the search grid, map, author portfolio, or
/// pipeline preview produces can be grabbed immediately — no need to open
/// the asset viewer first just to get the file. Single choke point: every
/// surface in the app renders media through [MediaCard], so this one
/// widget is what makes media "downloadable on the spot" everywhere at
/// once. Downloads the original file, same as the asset viewer's
/// "Download Original" action.
class _QuickDownloadButton extends StatefulWidget {
  final SearchItem item;
  const _QuickDownloadButton({required this.item});

  @override
  State<_QuickDownloadButton> createState() => _QuickDownloadButtonState();
}

class _QuickDownloadButtonState extends State<_QuickDownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DownloadService.downloadSingleFile(
          widget.item.url, widget.item.title, widget.item.extension);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Download original',
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _download,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.6, color: Color(0xFF3D7EFF)),
                  )
                : const Icon(Icons.download_rounded,
                    size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Shared result grid used anywhere a collection of Commons media is shown.
///
/// The caller owns loading and pagination state. This widget coordinates the
/// visual grid, card navigation context, and an optional near-end callback.
class MediaResultsGrid extends StatelessWidget {
  final List<SearchItem> items;
  final SearchState searchState;
  final Map<String, String> extraParams;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final bool loadingMore;
  final int? itemLimit;
  final double cacheExtent;
  final VoidCallback? onNearEnd;
  final double nearEndThreshold;

  const MediaResultsGrid({
    super.key,
    required this.items,
    required this.searchState,
    required this.gridDelegate,
    this.extraParams = const {},
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 20),
    this.controller,
    this.loadingMore = false,
    this.itemLimit,
    this.cacheExtent = 150,
    this.onNearEnd,
    this.nearEndThreshold = 400,
  });

  @override
  Widget build(BuildContext context) {
    final visibleCount = itemLimit == null
        ? items.length
        : itemLimit!.clamp(0, items.length).toInt();
    final grid = GridView.builder(
      controller: controller,
      padding: padding,
      cacheExtent: cacheExtent,
      gridDelegate: gridDelegate,
      itemCount: visibleCount + (loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == visibleCount) {
          return const Center(
            key: ValueKey('media-results-loading'),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Color(0xFF3D7EFF),
              ),
            ),
          );
        }
        final item = items[index];
        return RepaintBoundary(
          key: ValueKey(item.url),
          child: MediaCard(
            item: item,
            index: index,
            searchState: searchState,
            extraParams: extraParams,
          ),
        );
      },
    );

    if (onNearEnd == null) return grid;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - nearEndThreshold) {
          onNearEnd!();
        }
        return false;
      },
      child: grid,
    );
  }
}

class MediaCard extends ConsumerStatefulWidget {
  final SearchItem item;
  final int index;
  final SearchState searchState;
  final Map<String, String> extraParams;

  const MediaCard({
    super.key,
    required this.item,
    required this.index,
    required this.searchState,
    this.extraParams = const {},
  });

  @override
  ConsumerState<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends ConsumerState<MediaCard> {
  bool _hovered = false;

  Future<void> _handleTap() async {
    // 1. Intercept tap if we are in selection mode
    final isSelectionMode = ref.read(selectionModeProvider);
    if (isSelectionMode) {
      final selectedItems = ref.read(selectedItemsProvider);
      final isSelected = selectedItems.contains(widget.item);

      if (isSelected) {
        ref.read(selectedItemsProvider.notifier).state = {...selectedItems}
          ..remove(widget.item);
      } else {
        ref.read(selectedItemsProvider.notifier).state = {...selectedItems}
          ..add(widget.item);
      }
      return;
    }

    // 2. Otherwise, normal navigation
    final params = <String, String>{
      'id': widget.item.title,
      ...SearchUrlCodec.toQueryParams(widget.searchState),
      ...widget.extraParams,
    };
    final uniqueUrl = Uri(path: '/view', queryParameters: params).toString();

    context.push(uniqueUrl, extra: widget.index);
  }

  void _handleLongPress() {
    final isSelectionMode = ref.read(selectionModeProvider);

    if (!isSelectionMode) {
      // 1. Turn on selection mode
      ref.read(selectionModeProvider.notifier).state = true;

      // 2. Add this specific item to the selection immediately
      ref.read(selectedItemsProvider.notifier).state = {widget.item};

      // 3. Trigger a tiny physical buzz on mobile devices! (Requires flutter/services.dart)
      HapticFeedback.lightImpact();
    }
  }

  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image:
        return Icons.image_outlined;
      case MediaKind.vector:
        return Icons.polyline_outlined;
      case MediaKind.audio:
        return Icons.graphic_eq_outlined;
      case MediaKind.video:
        return Icons.videocam_outlined;
      case MediaKind.document:
        return Icons.description_outlined;
      case MediaKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final kind = item.mediaKind;

    // A selection change should rebuild this card only when this card's own
    // membership changes. Watching the full set rebuilt every visible card
    // for each click, which becomes expensive in Chrome on dense grids.
    final isSelected = ref.watch(
      selectedItemsProvider.select((items) => items.contains(item)),
    );
    final isSelectionMode = ref.watch(selectionModeProvider);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        onLongPress: _handleLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: const Color(0xFF131313),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  // Draw a thick blue border if selected!
                  width: isSelected ? 3 : 1,
                  color: isSelected
                      ? const Color(0xFF3D7EFF)
                      : _hovered
                          ? const Color(0xFF3D7EFF).withValues(alpha: 0.55)
                          : const Color(0xFF202020))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. TOP SECTION: Image + Badge
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MediaPreview(item: item, index: widget.index),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2A2A2A))),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconForKind(kind),
                                size: 12, color: const Color(0xFFCACACA)),
                            const SizedBox(width: 5),
                            Text(item.fileTypeLabel,
                                style: const TextStyle(
                                    color: Color(0xFFE0E0E0),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.7)),
                          ],
                        ),
                      ),
                    ),
                    // Keep quick download available without leaving an
                    // unexplained permanent circle on every card.
                    if (!isSelectionMode && _hovered)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _QuickDownloadButton(item: item),
                      ),
                    // Selection state is only shown while bulk selection is
                    // active, so the circle has a single, obvious meaning.
                    if (isSelectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? const Color(0xFF3D7EFF)
                                : Colors.black.withValues(alpha: 0.62),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF79A4FF)
                                  : Colors.white38,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white, size: 17)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),

              // 2. BOTTOM SECTION: Text Metadata
              Container(
                padding: const EdgeInsets.only(
                    left: 10, top: 10, bottom: 10, right: 10),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF202020))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_displayTitle(item),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25)),
                    const SizedBox(height: 4),
                    _buildCardSubtitle(item),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MediaPreview extends StatefulWidget {
  final SearchItem item;
  final int index;
  const MediaPreview({super.key, required this.item, required this.index});
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  bool _shouldLoad = false;
  Timer? _loadTimer;
  @override
  void initState() {
    super.initState();
    final slot = widget.index % 25;
    if (slot == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shouldLoad = true);
      });
    } else {
      _loadTimer = Timer(Duration(milliseconds: slot * 30), () {
        if (mounted) setState(() => _shouldLoad = true);
      });
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  /// Whether item.thumb is an actual rendered thumbnail worth showing as
  /// an image, rather than the raw original file. Commons' imageinfo API
  /// returns a real scaled thumburl for essentially every media type,
  /// including PDFs (page-1 render) and SVGs (rasterized) — SearchService
  /// only falls back to the original `url` when thumbnail generation
  /// itself failed for the whole batch (see the urlparamnormal retry in
  /// search_service.dart), so `thumb == url` is the correct signal to
  /// fall back to the icon UI — not the file extension.
  bool _hasRenderableThumb(SearchItem item) {
    if (item.thumb.isEmpty) return false;
    if (item.mediaKind == MediaKind.audio) return false;
    if (item.mediaKind == MediaKind.unknown) return false;
    if (item.thumb == item.url) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) return const PreviewLoading();
    final item = widget.item;
    if (!_hasRenderableThumb(item)) return PreviewFallback(item: item);
    return Image.network(item.thumb,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => PreviewFallback(item: item),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const PreviewLoading();
        });
  }
}

class PreviewLoading extends StatelessWidget {
  const PreviewLoading({super.key});
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
        decoration: BoxDecoration(color: Color(0xFF121212)),
        child: Center(
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 1.4, color: Color(0xFF3D7EFF)))));
  }
}

class PreviewFallback extends StatelessWidget {
  final SearchItem item;
  const PreviewFallback({super.key, required this.item});
  IconData _iconForKind(MediaKind kind) {
    switch (kind) {
      case MediaKind.image:
        return Icons.image_outlined;
      case MediaKind.vector:
        return Icons.polyline_outlined;
      case MediaKind.audio:
        return Icons.graphic_eq_outlined;
      case MediaKind.video:
        return Icons.videocam_outlined;
      case MediaKind.document:
        return Icons.description_outlined;
      case MediaKind.unknown:
        return Icons.insert_drive_file_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF101010), Color(0xFF171717)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Center(
            child: Icon(_iconForKind(item.mediaKind),
                size: 34, color: const Color(0xFF555555))));
  }
}
