import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'legal_pages.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  static const _groups = <_FeatureGroup>[
    _FeatureGroup(
      title: 'SEARCH & DISCOVERY',
      description:
          'Build precise Wikimedia Commons searches without learning CirrusSearch syntax.',
      features: [
        'Search images, SVG and vector graphics, audio, video, PDFs, DjVu files, and other documents.',
        'Combine unrelated text searches with +, run filter-only searches, and use direct file-title autocomplete.',
        'Filter exact formats, sort by relevance, title, creation date, or edit date, and keep loading results as you scroll.',
        'Share complete searches as URLs, remove active filters individually, and inspect the generated CirrusSearch query.',
      ],
    ),
    _FeatureGroup(
      title: 'SEMANTIC & METADATA FILTERS',
      description:
          'Use Commons categories and structured Wikidata metadata as first-class search controls.',
      features: [
        'Include or exclude Wikidata depicts subjects and combine several subjects with AND or OR logic.',
        'Search arbitrary Wikidata property-value statements with independent include and exclude rules.',
        'Include or exclude multiple Commons categories, switch between AND and OR, and recursively include subcategories.',
        'Filter by MediaWiki templates, language, content model, creation and edit dates, resolution, file size, and color depth.',
        'Restrict results to CC0, CC BY 4.0, CC BY-SA 4.0, Public Domain, attribution status, or Commons quality assessments.',
      ],
    ),
    _FeatureGroup(
      title: 'MAP & LOCATION SEARCH',
      description:
          'Discover geotagged Commons media spatially instead of relying only on words.',
      features: [
        'Search by tapping a map, entering coordinates and a radius, searching near a named place, or drawing a bounding box.',
        'Plot the current search on a map, cluster thumbnail markers, inspect clusters, and open results in a split-screen grid.',
        'Use a dark default basemap or switch to street, satellite, and hybrid layers, with zoom, rotation, north reset, camera fitting, and responsive mobile controls.',
        'Carry search context into the map, apply license, quality, and attribution filters, or send a map query back to Search.',
      ],
    ),
    _FeatureGroup(
      title: 'MEDIA VIEWER & REUSE',
      description:
          'Inspect, understand, credit, and download a Commons file from one viewer.',
      features: [
        'View images, vectors, audio, video, and supported PDFs natively, with browser fallbacks for DjVu and unsupported files.',
        'Navigate result galleries by swipe, buttons, or keyboard and switch images between a web-optimized and full-resolution preview.',
        'Read creator, uploader, dates, dimensions, categories, assessments, coordinates, Structured Data on Commons, and global usage.',
        'Find related files, explore nearby geotagged media, and browse every upload from a contributor portfolio.',
        'Generate copy-ready plain-text attribution, HTML, and WikiText with links to the source, license, and official reuse guidance.',
      ],
    ),
    _FeatureGroup(
      title: 'DOWNLOADS & DATA EXPORT',
      description:
          'Move from discovery to a reusable media collection entirely in the browser.',
      features: [
        'Download originals or 640px, 1280px, and 1920px derivatives when available.',
        'Long-press result cards, select any subset or all loaded files, and export originals or 1280px web-optimized media as ZIP files.',
        'Track, cancel, and run multiple downloads while large selections are split into manageable archive parts.',
        'Receive a data.csv manifest with every bulk ZIP, including source URLs, descriptions, dimensions, rights, attribution, dates, categories, assessments, and coordinates.',
      ],
    ),
    _FeatureGroup(
      title: 'VISUAL DATA PIPELINES',
      description:
          'Create repeatable, no-code Wikimedia research and export workflows on a node canvas.',
      features: [
        'Start from text, categories, depicted subjects, Wikidata statements, templates, geosearch, author uploads, or a related file.',
        'Filter license, quality, format, resolution, size, color depth, dates, language, and excluded terms.',
        'Combine branches with query constraints, union, intersection, or difference; then deduplicate, sort, sample, select fields, or enrich metadata.',
        'Preview intermediate results and send outputs to CSV, JSON, ZIP, a media preview, or the main Search grid.',
        'Autosave pipelines in IndexedDB, reopen saved graphs, import or export portable JSON, preview capped runs, cache queries, and clear cached results.',
      ],
    ),
    _FeatureGroup(
      title: 'WEB, SHARING & RELIABILITY',
      description:
          'A responsive, open-source web application designed to work directly with Wikimedia services.',
      features: [
        'Use clean deep links for searches, assets, authors, maps, directories, pipelines, and this feature guide.',
        'Install CommonsLens as a standalone web app on supported devices and use desktop or mobile-specific layouts.',
        'Benefit from lazy metadata loading, staggered result rendering, request deduplication, Wikimedia-aware throttling, retries, and cancellable transfers.',
        'No Commons account is required, and CommonsLens does not host or claim ownership of the media it displays.',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101010),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: 'Back to search',
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
        ),
        title: const Text(
          'COMMONSLENS FEATURES',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
      ),
      body: SelectionArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 72),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1060),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Everything you can do with CommonsLens',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Advanced search, semantic metadata, geographic discovery, responsible reuse, bulk export, and visual data pipelines for Wikimedia Commons.',
                    style: TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _RouteButton(
                        label: 'Search media',
                        icon: Icons.search,
                        onPressed: () => context.go('/'),
                      ),
                      _RouteButton(
                        label: 'Browse directories',
                        icon: Icons.category_outlined,
                        onPressed: () => context.push('/browse'),
                      ),
                      _RouteButton(
                        label: 'Open map',
                        icon: Icons.map_outlined,
                        onPressed: () => context.push('/map'),
                      ),
                      _RouteButton(
                        label: 'Build a pipeline',
                        icon: Icons.account_tree_outlined,
                        onPressed: () => context.push('/pipeline'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 42),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 850 ? 2 : 1;
                      final width = columns == 2
                          ? (constraints.maxWidth - 18) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        children: _groups
                            .map((group) => _FeatureCard(
                                  group: group,
                                  width: width,
                                ))
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 44),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureGroup {
  const _FeatureGroup({
    required this.title,
    required this.description,
    required this.features,
  });

  final String title;
  final String description;
  final List<String> features;
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.group, required this.width});

  final _FeatureGroup group;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.title,
            style: const TextStyle(
              color: Color(0xFF7AABFF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            group.description,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ...group.features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 5,
                      color: Color(0xFF3D7EFF),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      feature,
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteButton extends StatelessWidget {
  const _RouteButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Color(0xFF303030)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      icon: Icon(icon, size: 17, color: const Color(0xFF3D7EFF)),
      label: Text(label),
    );
  }
}
