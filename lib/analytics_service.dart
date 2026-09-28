// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

/// Thin wrapper around the `gtag` function installed by web/index.html's
/// GA4 snippet. Every call site in the app goes through this — nothing
/// else touches `window.gtag` directly, so the wiring lives in exactly
/// one place.
///
/// Every method is a safe no-op if gtag isn't present (blocked by an
/// adblocker, script failed to load, or this is a non-web build target —
/// dart:html itself would fail to compile there, but that's already true
/// of asset_viewer.dart/download_service.dart elsewhere in this app, so
/// consistent with the existing web-only assumption). Analytics failing
/// must never break the app, so every call is wrapped defensively.
class AnalyticsService {
  AnalyticsService._();

  static bool _checked = false;
  static bool _available = false;

  static bool get _hasGtag {
    if (!_checked) {
      _checked = true;
      try {
        _available = js_util.hasProperty(html.window, 'gtag');
      } catch (_) {
        _available = false;
      }
    }
    return _available;
  }

  /// Raw escape hatch: gtag('event', name, params). Every typed method
  /// below is a thin wrapper over this — prefer those for consistent
  /// naming, but this is here for anything one-off.
  static void event(String name, [Map<String, Object?> params = const {}]) {
    if (!_hasGtag) return;
    try {
      if (params.isEmpty) {
        js_util.callMethod(html.window, 'gtag', ['event', name]);
      } else {
        js_util.callMethod(
            html.window, 'gtag', ['event', name, js_util.jsify(params)]);
      }
    } catch (_) {
      // Never let a broken analytics call take down the app.
    }
  }

  /// Manual SPA page_view. GA4's automatic page_view only fires once, on
  /// the initial script load — go_router route changes never re-trigger
  /// it. Call this from the router's navigation listener (see router.dart)
  /// so GA sees every screen the person actually visits, not just the
  /// first one. Requires `send_page_view: false` in index.html's gtag
  /// config so the automatic and manual pings don't double-count the
  /// first load — see the index.html note below.
  static void pageView(String path, {String? title}) {
    if (!_hasGtag) return;
    event('page_view', {
      'page_location': html.window.location.href,
      'page_path': path,
      if (title != null) 'page_title': title,
    });
  }

  // ---------------------------------------------------------------------
  // Search & filters
  // ---------------------------------------------------------------------

  static void search({
    required String query,
    required String tab,
    int? resultCount,
  }) =>
      event('search', {
        'search_term': query,
        'tab': tab,
        if (resultCount != null) 'result_count': resultCount,
      });

  static void filterApplied(String filterType, String value) => event(
      'filter_applied', {'filter_type': filterType, 'filter_value': value});

  static void filterRemoved(String filterType) =>
      event('filter_removed', {'filter_type': filterType});

  static void sortChanged(String sortMode) =>
      event('sort_changed', {'sort_mode': sortMode});

  static void tabChanged(String tab) => event('tab_changed', {'tab': tab});

  static void formatToggled(String format, bool selected) =>
      event('format_toggled', {'format': format, 'selected': selected});

  // ---------------------------------------------------------------------
  // Media interaction
  // ---------------------------------------------------------------------

  /// [source] distinguishes where the open happened from — worth knowing
  /// whether people mostly browse from search results, the map, an author
  /// portfolio, the "related media" strip, or a direct/shared link.
  static void mediaOpened({
    required String title,
    required String mediaKind,
    required String source,
  }) =>
      event('media_opened', {
        'file_title': title,
        'media_kind': mediaKind,
        'source': source,
      });

  static void mediaDownloaded({
    required String title,
    required String size, // 'original' | 'small' | 'medium' | 'large'
  }) =>
      event('media_downloaded', {'file_title': title, 'download_size': size});

  static void sourcePageOpened(String title) =>
      event('source_page_opened', {'file_title': title});

  static void bulkDownloadStarted(int count) =>
      event('bulk_download_started', {'file_count': count});

  static void bulkDownloadCompleted({
    required int total,
    required int failed,
    required bool cancelled,
  }) =>
      event('bulk_download_completed', {
        'total': total,
        'failed': failed,
        'cancelled': cancelled,
      });

  // ---------------------------------------------------------------------
  // Asset viewer lazy sections — tells you which panels people actually
  // dig into (structured data, related media, global usage) vs. ignore.
  // ---------------------------------------------------------------------

  static void sectionExpanded(String section) =>
      event('section_expanded', {'section': section});

  static void relatedMediaClicked({
    required String fromTitle,
    required String toTitle,
  }) =>
      event('related_media_clicked',
          {'from_file': fromTitle, 'to_file': toTitle});

  // ---------------------------------------------------------------------
  // Map
  // ---------------------------------------------------------------------

  static void mapModeChanged(String mode) =>
      event('map_mode_changed', {'mode': mode});

  static void mapRadiusSearch({
    required double radiusMeters,
    required bool filtered,
  }) =>
      event('map_radius_search', {
        'radius_meters': radiusMeters,
        'filtered': filtered,
      });

  static void mapBoundingBoxSearch() => event('map_bbox_search');

  static void mapStyleChanged(String style) =>
      event('map_style_changed', {'style': style});

  static void mapOpenedInMainSearch() => event('map_opened_in_main_search');

  static void mapClusterOpened(int fileCount) =>
      event('map_cluster_opened', {'file_count': fileCount});

  /// "Search All Media Near This File" — the asset viewer's deep-link into
  /// a browse-mode radius search on the map, kept distinct from
  /// [mediaOpened] since it's a navigation action, not an open of another
  /// file's own detail view.
  static void nearbyMediaFromAssetOpened(String fromTitle) =>
      event('nearby_media_from_asset', {'from_file': fromTitle});

  // ---------------------------------------------------------------------
  // Browse directory
  // ---------------------------------------------------------------------

  static void browseTabOpened(String tab) =>
      event('browse_tab_opened', {'tab': tab});

  static void browseItemSelected(String kind, String value) =>
      event('browse_item_selected', {'kind': kind, 'value': value});

  // ---------------------------------------------------------------------
  // Author portfolio
  // ---------------------------------------------------------------------

  static void authorPortfolioViewed(String username) =>
      event('author_portfolio_viewed', {'username': username});
}
