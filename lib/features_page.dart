import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'legal_pages.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  static const _groups = <_FeatureGroup>[
    _FeatureGroup(
      title: 'FIND & REFINE',
      description: 'Start with a broad idea, then make the result set precise.',
      links: [
        _FeatureLink(
            'Search',
            'Find Wikimedia Commons media by phrase, title, type, or format.',
            'search',
            route: '/'),
        _FeatureLink(
            'Advanced filters',
            'Narrow by subjects, categories, rights, quality, dates, and technical metadata.',
            'advanced-filters'),
        _FeatureLink(
            'Browse classifications',
            'Discover categories, templates, and Wikidata subjects when words are not enough.',
            'browse',
            route: '/browse'),
        _FeatureLink('Map discovery',
            'Find geotagged media near a place, radius, or point.', 'map',
            route: '/map'),
      ],
    ),
    _FeatureGroup(
      title: 'UNDERSTAND & REUSE',
      description:
          'Move from a promising result to a defensible reuse decision.',
      links: [
        _FeatureLink(
            'Inspect a file',
            'Read the viewer’s metadata, source context, related media, and usage information.',
            'inspect'),
        _FeatureLink(
            'Reuse and attribution',
            'Review reported rights and generate an attribution draft to verify.',
            'reuse'),
        _FeatureLink(
            'Author portfolios',
            'Explore an uploader’s public file collection and export its metadata.',
            'author-portfolios'),
      ],
    ),
    _FeatureGroup(
      title: 'SAVE & EXPORT',
      description:
          'Keep useful references local and move metadata into your next tool.',
      links: [
        _FeatureLink(
            'Bookmarks and folders',
            'Save public file references, organize them into folders, and search the local collection.',
            'bookmarks',
            route: '/bookmarks'),
        _FeatureLink(
            'Download and export',
            'Download supported media or export metadata and URLs as a CSV manifest.',
            'downloads'),
        _FeatureLink(
            'Download security',
            'See how direct media downloads are screened before a browser file is created.',
            'download-security'),
      ],
    ),
    _FeatureGroup(
      title: 'BUILD WORKFLOWS',
      description:
          'Turn a one-off search into a repeatable visual research process.',
      links: [
        _FeatureLink(
            'Pipelines',
            'Connect sources, filters, set operations, transforms, and export nodes on a canvas.',
            'pipelines',
            route: '/pipeline'),
        _FeatureLink(
            'Getting started with pipelines',
            'Build a first graph, preview its output, and understand what each node contributes.',
            'pipeline-getting-started',
            route: '/pipeline'),
      ],
    ),
    _FeatureGroup(
      title: 'DATA, SHARING & PRIVACY',
      description:
          'Know what the browser keeps, what URLs reveal, and which providers are contacted.',
      links: [
        _FeatureLink(
            'How your data moves',
            'Understand requests, browser storage, caches, clipboard use, and downloads.',
            'your-data'),
        _FeatureLink(
            'Sharing and local state',
            'Share searches and viewer context while keeping local work and sensitive terms in mind.',
            'sharing'),
        _FeatureLink(
            'Rights, privacy, and responsible use',
            'Read the boundaries around licensing, privacy, providers, and public infrastructure.',
            'rights',
            route: '/privacy'),
      ],
    ),
    _FeatureGroup(
      title: 'HELP & POLICIES',
      description:
          'Find the right starting point when something is unclear or fails.',
      links: [
        _FeatureLink(
            'Start here',
            'Follow the shortest complete path from discovery to inspection and reuse.',
            'start',
            route: '/'),
        _FeatureLink(
            'Troubleshooting',
            'Diagnose empty results, failed providers, missing previews, storage issues, and exports.',
            'troubleshooting'),
        _FeatureLink(
            'Terms of Use',
            'Read the CommonsLens rules, provider boundaries, and responsibility limits.',
            'rights',
            route: '/terms'),
        _FeatureLink(
            'Privacy Policy',
            'Read what CommonsLens stores locally and what external services receive.',
            'your-data',
            route: '/privacy'),
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
        actions: const [
          DocsSectionLink(
            section: 'index',
            label: 'User Guide',
          ),
          SizedBox(width: 4),
        ],
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
                    'Advanced search, semantic metadata, geographic discovery, responsible reuse, metadata CSV export, and visual data pipelines for Wikimedia Commons.',
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
    required this.links,
  });

  final String title;
  final String description;
  final List<_FeatureLink> links;
}

class _FeatureLink {
  const _FeatureLink(
    this.title,
    this.summary,
    this.docsSection, {
    this.route,
  });

  final String title;
  final String summary;
  final String docsSection;
  final String? route;
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
          ...group.links.map(
            (link) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    link.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    link.summary,
                    style: const TextStyle(
                      color: Color(0xFFAAAAAA),
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 0,
                    children: [
                      if (link.route != null)
                        TextButton(
                          onPressed: () {
                            if (link.route == '/') {
                              context.go('/');
                            } else {
                              context.push(link.route!);
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF7AABFF),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            link.route == '/'
                                ? 'Open Search'
                                : 'Open ${link.title}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      DocsSectionLink(
                        section: link.docsSection,
                        label: 'User guide',
                      ),
                    ],
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
