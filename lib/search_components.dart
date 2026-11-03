import 'dart:async';

import 'download_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'search_models.dart';
import 'search_service.dart';
import 'media_queue.dart';
import 'backend_providers.dart';
import 'download_service.dart';
import 'bookmark_service.dart';
import 'autocomplete_request_coordinator.dart';
import 'legal_pages.dart';
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

  @override
  Widget build(BuildContext context) {
    // iOS Safari zooms a page when it focuses an input whose rendered text is
    // smaller than 16px. Keep the mobile query field at that threshold and
    // give it a little more height so it is comfortable to use with a thumb.
    final isMobile = MediaQuery.of(context).size.width < 600;
    final fieldHeight = isMobile ? 52.0 : 38.0;
    final fieldFontSize = isMobile ? 16.0 : 14.0;

    Widget clearButton(TextEditingController controller) {
      return IconButton(
        tooltip: 'Clear search',
        onPressed: () {
          controller.clear();
          widget.onSearch('');
        },
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: const Icon(Icons.close, size: 17, color: Color(0xFF777777)),
      );
    }

    Widget filtersButton() {
      return IconButton(
        tooltip: 'Filters',
        onPressed: () => Scaffold.of(context).openDrawer(),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.tune, size: 19, color: Color(0xFFB0B0B0)),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF101010),
        border: Border(bottom: BorderSide(color: Color(0xFF1C1C1C))),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 16,
        vertical: isMobile ? 8 : 10,
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: fieldHeight,
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
                      style: TextStyle(
                          fontSize: fieldFontSize, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: isMobile
                            ? 'Search Wikimedia Commons media'
                            : 'What would you like to find? The dropdown suggestions show direct file matches. To see all results for the search, just press enter/search.',
                        hintStyle:
                            const TextStyle(color: Colors.grey, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF181818),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 16 : 14,
                            vertical: isMobile ? 14 : 9),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: const BorderSide(
                                color: Color(0xFF3D7EFF), width: 1)),
                        // On a phone the filter action lives in the field,
                        // occupying the space where the desktop Search button
                        // would otherwise be. Search is submitted from the
                        // keyboard, so there is no second mobile button.
                        suffixIcon: isMobile && widget.showFiltersButton
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (controller.text.isNotEmpty)
                                    clearButton(controller),
                                  filtersButton(),
                                ],
                              )
                            : controller.text.isNotEmpty
                                ? clearButton(controller)
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
            if (widget.showFiltersButton && !isMobile) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2A2A2A)),
                      foregroundColor: const Color(0xFFB0B0B0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(horizontal: 14)),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('Filters',
                      style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (!isMobile) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Search',
                child: SizedBox(
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
                    child: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
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
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: SvgPicture.asset(
          'assets/branding/commonslens-icon.svg',
          semanticsLabel: 'CommonsLens',
        ),
      ),
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
    final securityNotice = showDownloadSecurityNotice(context);
    try {
      final failure = await DownloadService.downloadSingleFile(widget.item);
      if (failure != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure),
            backgroundColor: const Color(0xFF7A1F1F),
          ),
        );
      }
    } finally {
      securityNotice.close();
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

class _QuickBookmarkButton extends ConsumerWidget {
  final SearchItem item;

  const _QuickBookmarkButton({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBookmarked = ref.watch(
      bookmarkStoreProvider.select((store) => store.isBookmarked(item.url)),
    );

    return Tooltip(
      message: isBookmarked ? 'Remove bookmark' : 'Bookmark media',
      child: Material(
        color: isBookmarked
            ? const Color(0xFF3D7EFF).withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => ref.read(bookmarkStoreProvider).toggle(item.url),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              isBookmarked ? Icons.bookmark : Icons.bookmark_border,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderAssignmentButton extends ConsumerWidget {
  final SearchItem item;

  const _FolderAssignmentButton({required this.item});

  Future<void> _openFolderPicker(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _FolderPickerDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(bookmarkStoreProvider);
    final assigned =
        store.folders.any((folder) => folder.urls.contains(item.url));
    return Tooltip(
      message: 'Add to folder',
      child: Material(
        color: assigned
            ? const Color(0xFF3D7EFF).withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _openFolderPicker(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              assigned ? Icons.folder : Icons.create_new_folder_outlined,
              size: 15,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderPickerDialog extends ConsumerStatefulWidget {
  final SearchItem item;

  const _FolderPickerDialog({required this.item});

  @override
  ConsumerState<_FolderPickerDialog> createState() =>
      _FolderPickerDialogState();
}

class _FolderPickerDialogState extends ConsumerState<_FolderPickerDialog> {
  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Create folder',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Folder name',
            labelStyle: TextStyle(color: Color(0xFF888888)),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              FocusScope.of(dialogContext).unfocus();
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop(controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 220));
    controller.dispose();
    if (!mounted || name == null || name.isEmpty) return;
    ref.read(bookmarkStoreProvider).createFolder(name);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(bookmarkStoreProvider);
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Add to folder',
          style: TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 360,
        child: store.folders.isEmpty
            ? const Text(
                'Create a folder to organize this bookmarked media. It will remain in All Bookmarked Media too.',
                style: TextStyle(color: Color(0xFFB0B0B0), height: 1.4),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: store.folders.map((folder) {
                    final checked = folder.urls.contains(widget.item.url);
                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      activeColor: const Color(0xFF3D7EFF),
                      title: Text(folder.name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${folder.urls.length} ${folder.urls.length == 1 ? 'item' : 'items'}',
                        style: const TextStyle(color: Color(0xFF777777)),
                      ),
                      onChanged: (value) {
                        if (value == true) {
                          store.addToFolder(folder.id, widget.item.url);
                        } else {
                          store.removeFromFolder(folder.id, widget.item.url);
                        }
                      },
                    );
                  }).toList(),
                ),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _createFolder,
          icon: const Icon(Icons.create_new_folder_outlined, size: 17),
          label: const Text('Create folder'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Shared result grid used anywhere a collection of Commons media is shown.
///
/// The caller owns loading and pagination state. This widget coordinates the
/// visual grid, card navigation context, and an optional near-end callback.
class MediaResultsGrid extends StatelessWidget {
  final List<SearchItem> items;
  final MediaQueueSource? queueSource;
  final bool queueHasMore;
  final SliverGridDelegate gridDelegate;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;
  final bool loadingMore;
  final int? itemLimit;
  final double cacheExtent;
  final VoidCallback? onNearEnd;
  final double nearEndThreshold;
  final bool showFolderAction;
  final bool folderSelectionMode;
  final Set<String> selectedFolderUrls;
  final ValueChanged<SearchItem>? onFolderSelectionToggle;
  final VoidCallback? onFirstResultReady;

  const MediaResultsGrid({
    super.key,
    required this.items,
    required this.gridDelegate,
    this.queueSource,
    this.queueHasMore = false,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 20),
    this.controller,
    this.loadingMore = false,
    this.itemLimit,
    this.cacheExtent = 150,
    this.onNearEnd,
    this.nearEndThreshold = 400,
    this.showFolderAction = false,
    this.folderSelectionMode = false,
    this.selectedFolderUrls = const <String>{},
    this.onFolderSelectionToggle,
    this.onFirstResultReady,
  });

  @override
  Widget build(BuildContext context) {
    final source = queueSource ??
        MediaQueueSource.session(
          GoRouter.maybeOf(context)
                  ?.routeInformationProvider
                  .value
                  .uri
                  .toString() ??
              '/',
        );
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
            queueSource: source,
            queueItems: items,
            queueHasMore: queueHasMore,
            showFolderAction: showFolderAction,
            folderSelectionMode: folderSelectionMode,
            folderSelected: selectedFolderUrls.contains(item.url),
            onFolderSelectionToggle: onFolderSelectionToggle,
            onPreviewReady: onFirstResultReady,
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
  final MediaQueueSource queueSource;
  final List<SearchItem> queueItems;
  final bool queueHasMore;
  final bool showFolderAction;
  final bool folderSelectionMode;
  final bool folderSelected;
  final ValueChanged<SearchItem>? onFolderSelectionToggle;
  final VoidCallback? onPreviewReady;

  const MediaCard({
    super.key,
    required this.item,
    required this.index,
    required this.queueSource,
    required this.queueItems,
    this.queueHasMore = false,
    this.showFolderAction = false,
    this.folderSelectionMode = false,
    this.folderSelected = false,
    this.onFolderSelectionToggle,
    this.onPreviewReady,
  });

  @override
  ConsumerState<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends ConsumerState<MediaCard> {
  bool _hovered = false;

  Future<void> _handleTap() async {
    if (widget.folderSelectionMode) {
      widget.onFolderSelectionToggle?.call(widget.item);
      return;
    }

    final queue = ref.read(downloadQueueProvider);
    final isSelectionMode = ref.read(selectionModeProvider);
    // A restored queue item is still actionable even when the transient
    // selection-mode flag was reset by a page reload. Tapping its blue card
    // removes it instead of trapping the user in an uneditable queue.
    if (isSelectionMode || queue.contains(widget.item.url)) {
      _toggleQueueSelection();
      return;
    }

    // 2. Otherwise, normal navigation
    final source = widget.queueSource;
    final queueId = ref.read(mediaQueueStoreProvider).capture(
          source,
          widget.queueItems,
          hasMore: widget.queueHasMore,
        );
    context.push(source.urlFor(widget.item.title, queueId: queueId));
  }

  void _handleLongPress() {
    if (widget.folderSelectionMode) return;

    if (!ref.read(selectionModeProvider)) {
      ref.read(selectionModeProvider.notifier).state = true;
    }
    _toggleQueueSelection();
    HapticFeedback.lightImpact();
  }

  void _toggleQueueSelection() {
    final queue = ref.read(downloadQueueProvider);
    queue.toggle(
      widget.item,
      source: widget.queueSource.kind,
    );
    if (queue.isEmpty) {
      ref.read(selectionModeProvider.notifier).state = false;
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
      downloadQueueProvider.select((queue) => queue.contains(item.url)),
    );
    final isSelectionMode = ref.watch(selectionModeProvider);
    final isFolderSelectionMode = widget.folderSelectionMode;
    final showSelectionControls =
        isFolderSelectionMode || isSelectionMode || isSelected;
    final isCardSelected =
        isFolderSelectionMode ? widget.folderSelected : isSelected;

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
                  width: isCardSelected ? 3 : 1,
                  color: isCardSelected
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
                    MediaPreview(
                      item: item,
                      index: widget.index,
                      onPreviewReady: widget.onPreviewReady,
                    ),
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
                    if (!showSelectionControls &&
                        (_hovered || widget.showFolderAction))
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _QuickBookmarkButton(item: item),
                            if (widget.showFolderAction) ...[
                              const SizedBox(width: 6),
                              _FolderAssignmentButton(item: item),
                            ],
                            const SizedBox(width: 6),
                            _QuickDownloadButton(item: item),
                          ],
                        ),
                      ),
                    // Restored queue items also show the selection affordance;
                    // otherwise persistence would create blue cards with no
                    // visible way to remove an individual item.
                    if (showSelectionControls)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCardSelected
                                ? const Color(0xFF3D7EFF)
                                : Colors.black.withValues(alpha: 0.62),
                            border: Border.all(
                              color: isCardSelected
                                  ? const Color(0xFF79A4FF)
                                  : Colors.white38,
                            ),
                          ),
                          child: isCardSelected
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
  final VoidCallback? onPreviewReady;

  const MediaPreview({
    super.key,
    required this.item,
    required this.index,
    this.onPreviewReady,
  });
  @override
  State<MediaPreview> createState() => _MediaPreviewState();
}

class _MediaPreviewState extends State<MediaPreview> {
  bool _shouldLoad = false;
  int _candidateIndex = 0;
  Timer? _loadTimer;
  bool _previewReported = false;
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

  @override
  void didUpdateWidget(covariant MediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.url != widget.item.url) {
      _candidateIndex = 0;
      _shouldLoad = false;
      _previewReported = false;
      _loadTimer?.cancel();
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
  }

  void _reportPreviewReady() {
    if (_previewReported || widget.onPreviewReady == null) return;
    _previewReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPreviewReady!();
    });
  }

  /// Whether item.thumb is an actual rendered thumbnail worth showing as
  /// an image, rather than the raw original file. Commons' imageinfo API
  /// returns a real scaled thumburl for essentially every media type,
  /// including PDFs (page-1 render) and SVGs (rasterized) — SearchService
  /// only falls back to the original `url` when thumbnail generation
  /// itself failed for the whole batch (see the urlparamnormal retry in
  /// search_service.dart). The shared candidate list uses the exact thumbnail
  /// URL returned by Wikimedia; it returns an icon when no thumbnail exists.
  bool _hasRenderableThumb(SearchItem item) {
    if (item.mediaKind == MediaKind.audio) return false;
    if (item.mediaKind == MediaKind.unknown) return false;
    return item.previewUrlCandidates(330).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldLoad) return const PreviewLoading();
    final item = widget.item;
    if (!_hasRenderableThumb(item)) {
      // Audio and STL/other 3D files intentionally use a fallback card in the
      // search grid. They still count as a ready first result for onboarding.
      _reportPreviewReady();
      return PreviewFallback(item: item);
    }
    final candidates = item.previewUrlCandidates(330);
    if (_candidateIndex >= candidates.length) {
      _reportPreviewReady();
      return PreviewFallback(item: item);
    }

    final candidateIndex = _candidateIndex;
    final imageUrl = candidates[candidateIndex];
    final image = Image.network(imageUrl,
        key: ValueKey(imageUrl),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        cacheWidth: 640, errorBuilder: (_, __, ___) {
      if (candidateIndex + 1 < candidates.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _candidateIndex == candidateIndex) {
            setState(() => _candidateIndex++);
          }
        });
        return const PreviewLoading();
      }
      _reportPreviewReady();
      return PreviewFallback(item: item);
    }, loadingBuilder: (context, child, progress) {
      if (progress == null) {
        _reportPreviewReady();
        return child;
      }
      return const PreviewLoading();
    });

    // SVG thumbnails can have transparent regions. Keep those regions
    // legible against the same white backing used by the asset viewer.
    return _isSvgItem(item)
        ? Container(color: Colors.white, child: image)
        : image;
  }
}

bool _isSvgItem(SearchItem item) =>
    item.isSvg ||
    item.mediaKind == MediaKind.vector ||
    item.extension.toLowerCase() == 'svg' ||
    item.mime.toLowerCase() == 'image/svg+xml';

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
