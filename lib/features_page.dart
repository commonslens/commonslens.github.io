import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'legal_pages.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  static const _groups = <_FeatureGroup>[
    _FeatureGroup(
      title: 'GET STARTED',
      description: 'Build the right mental model before you begin.',
      links: [
        _FeatureLink(
            'Start here',
            'Build the correct mental model and complete your first search from discovery to reuse.',
            'start',
            route: '/'),
        _FeatureLink(
            'How your data moves',
            'See what leaves the browser, what stays local, what goes into URLs, and what clearing data removes.',
            'your-data'),
      ],
    ),
    _FeatureGroup(
      title: 'FIND & REFINE',
      description: 'Start with a broad idea, then make the result set precise.',
      links: [
        _FeatureLink(
            'Search Wikimedia Commons',
            'Turn a phrase, file title, or broad idea into a useful Commons result set.',
            'search',
            route: '/'),
        _FeatureLink(
            'Use advanced filters',
            'Use subjects, categories, rights, quality, dates, technical fields, and location to make a precise query.',
            'advanced-filters'),
        _FeatureLink(
            'Browse categories, templates, and subjects',
            'Find Commons vocabulary when you do not yet know the right category, template, or Wikidata subject.',
            'browse',
            route: '/browse'),
        _FeatureLink(
            'Search by map',
            'Use geographic context to find media near a point, place, radius, or drawn area.',
            'map',
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
            'Read the file’s context, metadata, structured data, related media, and source page.',
            'inspect'),
        _FeatureLink(
            'Check reuse and create attribution',
            'Interpret the reported rights information and produce a starting point for attribution.',
            'reuse'),
      ],
    ),
    _FeatureGroup(
      title: 'SAVE & EXPORT',
      description:
          'Keep useful references local and move metadata into your next tool.',
      links: [
        _FeatureLink(
            'Save bookmarks and folders',
            'Keep references to files you want to revisit without pretending to mirror the Commons catalogue.',
            'bookmarks',
            route: '/bookmarks'),
        _FeatureLink(
            'Explore an uploader’s portfolio',
            'Explore an uploader’s files, inspect them, and export a portfolio-sized metadata set.',
            'author-portfolios'),
        _FeatureLink(
            'Download files and export metadata',
            'Separate downloading media files from exporting metadata and URLs for research.',
            'downloads'),
      ],
    ),
    _FeatureGroup(
      title: 'BUILD WORKFLOWS',
      description:
          'Turn a one-off search into a repeatable visual research process.',
      links: [
        _FeatureLink(
            'Build a visual pipeline',
            'Build repeatable visual workflows that fetch, refine, enrich, and export collections.',
            'pipelines',
            route: '/pipeline'),
      ],
    ),
    _FeatureGroup(
      title: 'SHARE & PROTECT',
      description:
          'Know what the browser keeps, what URLs reveal, and which providers are contacted.',
      links: [
        _FeatureLink(
            'Share searches and understand local state',
            'Know what a URL shares, what survives a reload, and how to move local work between devices.',
            'sharing'),
        _FeatureLink(
            'Rights, privacy, and responsible use',
            'Understand provider boundaries, local privacy, licensing risk, and respectful use of public infrastructure.',
            'rights'),
      ],
    ),
    _FeatureGroup(
      title: 'HELP',
      description:
          'Find the right starting point when something is unclear or fails.',
      links: [
        _FeatureLink(
            'Troubleshooting',
            'Diagnose empty results, missing media, unavailable metadata, lost local state, and slow workflows.',
            'troubleshooting'),
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
                    'CommonsLens is a visual research workspace for discovering Wikimedia Commons media, checking its context and reuse information, organizing files, and exporting the metadata you need.',
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
