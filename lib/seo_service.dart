// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Keeps the browser document metadata aligned with client-side navigation.
///
/// The deploy build also contains route-specific static HTML so crawlers get
/// the right metadata before Flutter starts. This service covers navigation
/// after startup and marks user-generated/search-state URLs as non-indexable.
abstract final class SeoService {
  static const _origin = 'https://commonslens.github.io';

  static void syncCurrentRoute() {
    sync(_currentUri);
  }

  static Uri get _currentUri {
    final location = html.window.location;
    return Uri.parse('${location.pathname}${location.search}');
  }

  static void sync(Uri uri) {
    final page = _metadataFor(uri);
    _setMeta('name', 'description', page.description);
    _setMeta('name', 'robots', page.robots);
    _setMeta('property', 'og:title', page.title);
    _setMeta('property', 'og:description', page.description);
    _setMeta('property', 'og:url', page.canonical);
    _setMeta('name', 'twitter:title', page.title);
    _setMeta('name', 'twitter:description', page.description);
    _setCanonical(page.canonical);
  }

  static _SeoMetadata _metadataFor(Uri uri) {
    final path = _normalizedPath(uri.path);
    final hasSearchState = uri.queryParameters.isNotEmpty;

    if (path == '/' && !hasSearchState) {
      return const _SeoMetadata(
        title: 'CommonsLens: Explore Wikimedia',
        description:
            'Search and download reusable Wikimedia Commons images, SVGs, audio, video, and documents with advanced license, Wikidata, category, date, and map filters.',
        canonical: '$_origin/',
      );
    }

    if (path == '/browse') {
      return const _SeoMetadata(
        title: 'Browse Wikimedia Categories & Subjects | CommonsLens',
        description:
            'Browse Wikimedia Commons categories, templates, and Wikidata subjects, then use them in precise media searches with include, exclude, AND, OR, and subcategory controls.',
        canonical: '$_origin/browse/',
      );
    }

    if (path == '/map') {
      return const _SeoMetadata(
        title: 'Wikimedia Commons Map Search | CommonsLens',
        description:
            'Discover geotagged Wikimedia Commons media with point, radius, and place searches, clustered previews, metadata filters, and downloadable results.',
        canonical: '$_origin/map/',
      );
    }

    if (path == '/pipeline') {
      return const _SeoMetadata(
        title: 'Visual Wikimedia Data Pipelines | CommonsLens',
        description:
            'Build no-code visual Wikimedia Commons workflows with 31 source, filter, set-operation, transform, preview, and export nodes.',
        canonical: '$_origin/pipeline/',
      );
    }

    if (path == '/features') {
      return const _SeoMetadata(
        title: 'CommonsLens Features — Wikimedia Search, Map & Export',
        description:
            'Explore every CommonsLens feature: advanced Wikimedia search, Wikidata and license filters, map discovery, attribution tools, bulk downloads, and visual data pipelines.',
        canonical: '$_origin/features/',
      );
    }

    if (path == '/terms') {
      return const _SeoMetadata(
        title: 'Terms of Use | CommonsLens',
        description:
            'Read the CommonsLens terms for Wikimedia media attribution, licensing, responsible API use, third-party services, and legal responsibilities.',
        canonical: '$_origin/terms/',
      );
    }

    if (path == '/privacy') {
      return const _SeoMetadata(
        title: 'Privacy Policy | CommonsLens',
        description:
            'Learn how CommonsLens works without analytics or advertising trackers, what stays on your device, which providers receive necessary requests, and what is not collected.',
        canonical: '$_origin/privacy/',
      );
    }

    // Asset, author, and query-state URLs are useful to share, but they are
    // effectively unbounded and do not have server-rendered unique content.
    // Keep links followable without turning them into an indexing crawl trap.
    return const _SeoMetadata(
      title: 'CommonsLens: Explore Wikimedia',
      description:
          'Explore and download reusable media from Wikimedia Commons with advanced search, map, and visual pipeline tools.',
      canonical: '$_origin/',
      indexable: false,
    );
  }

  static String _normalizedPath(String path) {
    if (path.isEmpty || path == '/') return '/';
    return path.replaceFirst(RegExp(r'/+$'), '');
  }

  static void _setMeta(
    String attribute,
    String key,
    String content,
  ) {
    final selector = 'meta[$attribute="$key"]';
    var element = html.document.head?.querySelector(selector);
    if (element == null) {
      element = html.MetaElement()..setAttribute(attribute, key);
      html.document.head?.append(element);
    }
    element.setAttribute('content', content);
  }

  static void _setCanonical(String url) {
    var element = html.document.head?.querySelector('link[rel="canonical"]');
    if (element == null) {
      element = html.LinkElement()..rel = 'canonical';
      html.document.head?.append(element);
    }
    element.setAttribute('href', url);
  }
}

class _SeoMetadata {
  const _SeoMetadata({
    required this.title,
    required this.description,
    required this.canonical,
    this.indexable = true,
  });

  final String title;
  final String description;
  final String canonical;
  final bool indexable;

  String get robots => indexable
      ? 'index, follow, max-image-preview:large, max-snippet:-1, '
          'max-video-preview:-1'
      : 'noindex, follow';
}
