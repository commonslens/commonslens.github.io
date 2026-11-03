import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'landing_tips.dart';
import 'legal_pages.dart';

/// The major workspaces that have their own first-visit explanation.
///
/// These values are deliberately about the workspace, not the current query
/// or username. A user should see the Map explanation once, even when they
/// open several different searches there.
enum WelcomeArea {
  grid,
  map,
  authorPortfolio,
  browseDirectories,
  pipelines,
  bookmarks,
  assetViewer,
}

class _WelcomeCopy {
  const _WelcomeCopy({
    required this.title,
    required this.description,
    required this.nextStep,
    required this.guideSection,
    required this.guideLabel,
    required this.icon,
  });

  final String title;
  final String description;
  final String nextStep;
  final String guideSection;
  final String guideLabel;
  final IconData icon;
}

class _FirstLandingWelcomeDialog extends StatelessWidget {
  const _FirstLandingWelcomeDialog({required this.onStartSearching});

  final VoidCallback onStartSearching;

  void _closeAnd(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  Widget _step({
    required String number,
    required String title,
    required String description,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF3D7EFF).withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3D7EFF)),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Color(0xFF9AB9FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _link({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton.icon(
      onPressed: () => _closeAnd(context, onPressed),
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF9AB9FF),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        textStyle: const TextStyle(fontSize: 11.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF171717),
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 570, maxHeight: 700),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D7EFF).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF8EAFFF),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to CommonsLens',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'A visual research desk for Wikimedia Commons.',
                          style: TextStyle(
                            color: Color(0xFFB8B8B8),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                decoration: BoxDecoration(
                  color: const Color(0xFF182032),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF3D7EFF).withValues(alpha: 0.65),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start with one question',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          color: Color(0xFFD7E2FF),
                          fontSize: 12,
                          height: 1.45,
                        ),
                        children: [
                          TextSpan(text: 'Type a phrase such as '),
                          TextSpan(
                            text: 'Apollo 11',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text:
                                ' into the search bar, then press Enter or the search button. CommonsLens will bring back a visual set of public Commons media to explore.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _step(
                number: '1',
                title: 'Search broadly',
                description:
                    'Start with an idea, title, place, person, or institution. You do not need the perfect Commons category name.',
              ),
              const SizedBox(height: 14),
              _step(
                number: '2',
                title: 'Refine what you see',
                description:
                    'Use media tabs and filters, or switch to Map for geographic discovery. Browse Directories can help when vocabulary is missing.',
              ),
              const SizedBox(height: 14),
              _step(
                number: '3',
                title: 'Inspect and keep useful references',
                description:
                    'Open a result to check its source and reuse information, then bookmark, download, export, or continue searching.',
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFF2A2A2A), height: 1),
              const SizedBox(height: 14),
              const Text(
                'Useful places to go next',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  _link(
                    context: context,
                    icon: Icons.account_tree_outlined,
                    label: 'Browse Directories',
                    onPressed: () => context.push('/browse'),
                  ),
                  _link(
                    context: context,
                    icon: Icons.auto_awesome_mosaic_outlined,
                    label: 'All features',
                    onPressed: () => context.push('/features'),
                  ),
                  _link(
                    context: context,
                    icon: Icons.person_search_outlined,
                    label: 'Search by author',
                    onPressed: () => context.push('/author'),
                  ),
                  _link(
                    context: context,
                    icon: Icons.account_tree_rounded,
                    label: 'Pipelines',
                    onPressed: () => context.push('/pipeline'),
                  ),
                  _link(
                    context: context,
                    icon: Icons.bookmark_border_rounded,
                    label: 'Bookmarks',
                    onPressed: () => context.push('/bookmarks'),
                  ),
                  _link(
                    context: context,
                    icon: Icons.menu_book_outlined,
                    label: 'User guide',
                    onPressed: openDocs,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _closeAnd(context, onStartSearching),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Start with a search'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3D7EFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeSnackBarContent extends StatefulWidget {
  const _WelcomeSnackBarContent({
    required this.copy,
    required this.onDismiss,
  });

  final _WelcomeCopy copy;
  final VoidCallback onDismiss;

  @override
  State<_WelcomeSnackBarContent> createState() =>
      _WelcomeSnackBarContentState();
}

class _WelcomeSnackBarContentState extends State<_WelcomeSnackBarContent> {
  Timer? _collapseTimer;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _collapseTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }

  Widget _buildGuideButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => openDocsSection(widget.copy.guideSection),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF8EAFFF),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(widget.copy.guideLabel),
      ),
    );
  }

  Widget _buildDismissButton() {
    return IconButton(
      tooltip: 'Dismiss',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      icon: const Icon(Icons.close, color: Colors.white54, size: 16),
      onPressed: widget.onDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _expanded
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(widget.copy.icon,
                    color: const Color(0xFF8EAFFF), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.copy.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.copy.description,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.copy.nextStep,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _buildGuideButton(),
                    ],
                  ),
                ),
                _buildDismissButton(),
              ],
            )
          : Row(
              children: [
                Icon(widget.copy.icon,
                    color: const Color(0xFF8EAFFF), size: 18),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.copy.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => openDocsSection(widget.copy.guideSection),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF8EAFFF),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(widget.copy.guideLabel),
                ),
                _buildDismissButton(),
              ],
            ),
    );
  }
}

const _welcomeCopy = <WelcomeArea, _WelcomeCopy>{
  WelcomeArea.grid: _WelcomeCopy(
    title: 'Welcome to Grid',
    description:
        'Search Wikimedia Commons and turn an idea into a useful set of files.',
    nextStep:
        'Start with the search field, then use media tabs and filters. Open a card to inspect, bookmark, or download it.',
    guideSection: 'search',
    guideLabel: 'How to search',
    icon: Icons.grid_view_rounded,
  ),
  WelcomeArea.map: _WelcomeCopy(
    title: 'Welcome to Map',
    description:
        'Explore geotagged Commons media by location. Map and Grid share the same search session.',
    nextStep:
        'Search first or tap the map, adjust the radius, then select a marker or cluster to inspect its files.',
    guideSection: 'map',
    guideLabel: 'Map guide',
    icon: Icons.map_outlined,
  ),
  WelcomeArea.authorPortfolio: _WelcomeCopy(
    title: 'Welcome to Author Portfolio',
    description: 'Review the public files uploaded under a Wikimedia username.',
    nextStep:
        'Enter an exact username, browse the upload grid, and open files to verify their creator, license, and source page.',
    guideSection: 'author-portfolios',
    guideLabel: 'Portfolio guide',
    icon: Icons.person_outline_rounded,
  ),
  WelcomeArea.browseDirectories: _WelcomeCopy(
    title: 'Welcome to Browse Directories',
    description:
        'Discover Commons categories, templates, and depicted subjects when you do not yet know the right search vocabulary.',
    nextStep:
        'Choose a directory, open a branch or search it, select useful entries, and apply them to Grid.',
    guideSection: 'browse',
    guideLabel: 'Browse guide',
    icon: Icons.account_tree_outlined,
  ),
  WelcomeArea.pipelines: _WelcomeCopy(
    title: 'Welcome to Pipelines',
    description:
        'Build repeatable visual workflows that find, refine, enrich, preview, and export Commons media.',
    nextStep:
        'Add nodes from the left palette, connect them on the canvas, configure the selected node on the right, then preview or export.',
    guideSection: 'pipeline-getting-started',
    guideLabel: 'Pipeline guide',
    icon: Icons.account_tree_rounded,
  ),
  WelcomeArea.bookmarks: _WelcomeCopy(
    title: 'Welcome to Bookmarks',
    description:
        'Keep local references to files you want to revisit and organize them into folders.',
    nextStep:
        'Bookmark files from Search, Map, or the viewer. Here you can search your collection, group files, and export a manifest.',
    guideSection: 'bookmarks',
    guideLabel: 'Bookmarks guide',
    icon: Icons.bookmark_outline_rounded,
  ),
  WelcomeArea.assetViewer: _WelcomeCopy(
    title: 'Welcome to Asset Viewer',
    description:
        'Inspect a file at full size while keeping its Commons context close at hand.',
    nextStep:
        'Read the metadata and reuse panel, open the original Commons page, then bookmark or download the file when it is ready for your work.',
    guideSection: 'inspect',
    guideLabel: 'Viewer guide',
    icon: Icons.visibility_outlined,
  ),
};

/// Tracks first visits in browser-local storage and presents the matching
/// workspace orientation message once per browser profile.
class PageWelcome {
  PageWelcome._();

  static const _storageKey = 'commonslens.visited-pages.v1';
  static const _firstLandingStorageKey = 'commonslens.first-landing-welcome.v1';
  static const _landingTipVisitStorageKey =
      'commonslens.landing-tip-visited.v1';
  static final Set<String> _pending = <String>{};
  static final Set<String> _sessionVisited = <String>{};
  static bool _firstLandingShownThisSession = false;
  static bool _landingTipPending = false;
  static bool _landingTipVisitRecordedThisSession = false;

  // The Grid welcome used to be shown on the landing surface before the
  // result grid was ready. Keep a new key for the result-grid version so users
  // who encountered that old notice can still get the corrected timing once.
  static String _key(WelcomeArea area) =>
      area == WelcomeArea.grid ? 'grid-results' : area.name;

  static Set<String> _readVisited() {
    try {
      final raw = html.window.localStorage[_storageKey];
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().toSet();
    } catch (_) {
      // Storage can be disabled or unavailable in private/restricted browser
      // contexts. The in-memory set below still prevents repeat notices for
      // the current app session.
      return <String>{};
    }
  }

  static bool _markVisited(WelcomeArea area) {
    final key = _key(area);
    if (_sessionVisited.contains(key)) return false;

    final visited = _readVisited();
    if (visited.contains(key)) {
      _sessionVisited.add(key);
      return false;
    }

    visited.add(key);
    _sessionVisited.add(key);
    try {
      html.window.localStorage[_storageKey] = jsonEncode(visited.toList());
    } catch (_) {
      // Keep the session-level mark when persistent storage is unavailable.
    }
    return true;
  }

  static void _markFirstLandingSeen() {
    _firstLandingShownThisSession = true;
    try {
      html.window.localStorage[_firstLandingStorageKey] = '1';
    } catch (_) {
      // The session-level mark still prevents a repeat when storage is denied.
    }
  }

  /// Shows the richer orientation dialog the first time the landing surface
  /// is actually visible. The Grid result welcome stays independent so it can
  /// appear after the first result preview/card is ready.
  static void maybeShowFirstLanding(
    BuildContext context, {
    required VoidCallback onStartSearching,
  }) {
    if (_firstLandingShownThisSession) return;
    try {
      if (html.window.localStorage[_firstLandingStorageKey] == '1') {
        _firstLandingShownThisSession = true;
        return;
      }
    } catch (_) {
      // Fall through to the in-memory first-visit behavior.
    }

    final pendingKey = 'first-landing';
    if (_pending.contains(pendingKey)) return;
    _pending.add(pendingKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending.remove(pendingKey);
      if (!context.mounted || _firstLandingShownThisSession) return;
      _markFirstLandingSeen();
      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        builder: (_) => _FirstLandingWelcomeDialog(
          onStartSearching: onStartSearching,
        ),
      );
    });
  }

  /// Schedules a welcome notice after the current page has mounted.
  static void maybeShow(BuildContext context, WelcomeArea area) {
    final key = _key(area);
    if (_pending.contains(key) || _sessionVisited.contains(key)) return;
    _pending.add(key);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending.remove(key);
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null || !_markVisited(area)) return;

      final copy = _welcomeCopy[area]!;
      final width = math.min(MediaQuery.sizeOf(context).width - 32, 440.0);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            width: width.clamp(240.0, 440.0).toDouble(),
            duration: const Duration(seconds: 12),
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            content: _WelcomeSnackBarContent(
              copy: copy,
              onDismiss: () => messenger.hideCurrentSnackBar(),
            ),
          ),
        );
    });
  }

  /// Shows one random, non-persistent tip whenever a fresh landing page is
  /// initialized after the first visit. Unlike workspace welcomes, tips are
  /// intentionally shown again on later visits so the feature set stays
  /// discoverable over time.
  static void maybeShowLandingTip(BuildContext context) {
    if (_landingTipPending) return;
    if (!_markLandingTipVisit()) return;
    _landingTipPending = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _landingTipPending = false;
      if (!context.mounted) return;

      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;

      try {
        final tips = await LandingTips.load();
        if (!context.mounted || tips.isEmpty) return;

        final tip = LandingTips.pickRandom(tips);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              // The app-wide SnackBarTheme keeps ordinary notices compact;
              // tips need the full reading width for their longer copy.
              width: double.infinity,
              duration: const Duration(seconds: 10),
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              content: _LandingTipSnackBarContent(
                tip: tip,
                onDismiss: () => messenger.hideCurrentSnackBar(),
              ),
            ),
          );
      } catch (_) {
        // A missing or malformed optional tip asset should never affect the
        // landing page itself.
      }
    });
  }

  /// Records that the landing page has been opened, returning whether this
  /// visit is eligible for a tip. The older first-landing key is accepted as
  /// proof for people who used CommonsLens before tips were introduced.
  static bool _markLandingTipVisit() {
    if (_landingTipVisitRecordedThisSession) return true;

    try {
      final storage = html.window.localStorage;
      final alreadyVisited = storage[_landingTipVisitStorageKey] == '1' ||
          storage[_firstLandingStorageKey] == '1';
      _landingTipVisitRecordedThisSession = true;
      if (!alreadyVisited) {
        storage[_landingTipVisitStorageKey] = '1';
        return false;
      }
      storage[_landingTipVisitStorageKey] = '1';
      return true;
    } catch (_) {
      final alreadyVisited = _landingTipVisitRecordedThisSession;
      _landingTipVisitRecordedThisSession = true;
      return alreadyVisited;
    }
  }
}

class _LandingTipSnackBarContent extends StatelessWidget {
  const _LandingTipSnackBarContent({
    required this.tip,
    required this.onDismiss,
  });

  final LandingTip tip;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lightbulb_outline_rounded,
            color: Color(0xFF8EAFFF), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tip.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tip.message,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              TextButton(
                onPressed: () => openDocsSection(tip.guideSection),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF8EAFFF),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(tip.guideLabel),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Dismiss',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.close, color: Colors.white54, size: 16),
          onPressed: onDismiss,
        ),
      ],
    );
  }
}
