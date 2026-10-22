import 'dart:convert';
import 'dart:io';

const _siteUrl = 'https://commonslens.github.io';

const _pages = <_SeoPage>[
  _SeoPage(
    path: 'browse',
    title: 'Browse Wikimedia Categories & Subjects | CommonsLens',
    description:
        'Browse Wikimedia Commons categories, templates, and Wikidata subjects, then use them in precise media searches with include, exclude, AND, OR, and subcategory controls.',
    heading: 'Browse Wikimedia Commons categories, templates, and subjects',
    intro:
        'Explore the classification systems behind Wikimedia Commons before opening any directory entry as a focused CommonsLens media search.',
    sections: [
      _SeoSection(
        heading: 'Commons category directory',
        intro:
            'Find categories by prefix, see their file counts, and continue through the paginated Commons directory.',
        items: [
          'Open a category directly as a media-search filter.',
          'Include or exclude several categories in one search.',
          'Use intersection to require every category or union to match any category.',
          'Enable deep-category mode to include media filed in nested subcategories.',
        ],
      ),
      _SeoSection(
        heading: 'MediaWiki template directory',
        intro:
            'Browse and search Commons templates, including institutional, collection, and granular public-domain templates.',
        items: [
          'Jump to a template by name and continue through paginated results.',
          'Require several templates or explicitly exclude selected templates.',
          'Send a selected template directly to the main search interface.',
        ],
      ),
      _SeoSection(
        heading: 'Wikidata depicts subjects',
        intro:
            'Find exact Wikidata entities instead of relying on ambiguous keywords.',
        items: [
          'Search up to 50 matching entities with labels, Q-codes, and descriptions.',
          'Find media depicting all selected subjects or any selected subject.',
          'Maintain independent include and exclude subject sets.',
          'Search arbitrary Wikidata property-value statements when depicts alone is not specific enough.',
        ],
      ),
      _SeoSection(
        heading: 'Continue into advanced Commons search',
        intro:
            'Directory selections work with CommonsLens text, rights, quality, technical, date, and location filters.',
        items: [
          'Filter images, SVGs, audio, video, PDFs, DjVu files, and other documents.',
          'Restrict results to CC0, CC BY 4.0, CC BY-SA 4.0, or Public Domain media.',
          'Filter by attribution requirement, Quality Images, Valued Images, or Featured Pictures.',
          'Share the resulting filter state as a URL or inspect the generated CirrusSearch query.',
        ],
      ),
    ],
  ),
  _SeoPage(
    path: 'map',
    title: 'Wikimedia Commons Map Search | CommonsLens',
    description:
        'Discover geotagged Wikimedia Commons media with point, radius, place, and bounding-box searches, clustered previews, metadata filters, and downloadable results.',
    heading: 'Search Wikimedia Commons by location',
    intro:
        'Use an interactive map to discover geotagged Wikimedia Commons photos and media around any place in the world.',
    sections: [
      _SeoSection(
        heading: 'Point, radius, and place search',
        intro:
            'Tap the map or enter latitude, longitude, and a radius to find nearby Commons media.',
        items: [
          'Run an open geographic browse or combine the location with a text query.',
          'Search near a named Commons page or place with an adjustable radius.',
          'Open a nearby-media search directly from the coordinates of an asset.',
          'See the search centre and radius drawn on the map.',
        ],
      ),
      _SeoSection(
        heading: 'Bounding-box discovery',
        intro:
            'Choose two corners to search a custom rectangular geographic area.',
        items: [
          'Preview the selected polygon before searching.',
          'Cancel and redraw the area without leaving the map.',
          'Open the geographic query in the main search interface.',
        ],
      ),
      _SeoSection(
        heading: 'Search results on the map',
        intro:
            'Browse spatial and visual results together instead of switching between unrelated tools.',
        items: [
          'Plot an existing CommonsLens search and report how many results contain usable coordinates.',
          'Cluster nearby thumbnail markers according to zoom level.',
          'Open a cluster as a media grid or inspect a single file in the full asset viewer.',
          'Use a desktop split-screen result pane or a responsive mobile layout.',
        ],
      ),
      _SeoSection(
        heading: 'Map controls and filters',
        intro:
            'Refine and navigate the map without losing the active geographic search.',
        items: [
          'Switch between street, satellite, and hybrid layers.',
          'Zoom, rotate in 15-degree steps, reset north, and fit the camera to imported results.',
          'Filter by license, Commons quality assessment, and attribution requirement.',
          'Preserve relevant main-search context when moving between Search and Map.',
        ],
      ),
      _SeoSection(
        heading: 'Inspect, reuse, and download mapped media',
        intro:
            'Every map result connects to the same CommonsLens metadata and export workflow.',
        items: [
          'View creator, uploader, dates, dimensions, categories, assessments, coordinates, and structured data.',
          'Check global Wikimedia usage and related media.',
          'Copy attribution, HTML, or WikiText reuse snippets.',
          'Download individual files or build a bulk ZIP collection with a CSV metadata manifest.',
        ],
      ),
    ],
  ),
  _SeoPage(
    path: 'pipeline',
    title: 'Visual Wikimedia Data Pipelines | CommonsLens',
    description:
        'Build no-code visual Wikimedia Commons workflows with 31 source, filter, set-operation, transform, preview, and export nodes.',
    heading: 'Build visual Wikimedia Commons data pipelines',
    intro:
        'Create a repeatable research workflow by connecting Commons search, metadata, collection, transformation, and export nodes on a visual canvas.',
    sections: [
      _SeoSection(
        heading: 'Eight Wikimedia source nodes',
        intro:
            'Begin a branch from the source best suited to the research task.',
        items: [
          'Text Query, Category, Depicted Subject, and Wikidata Statement.',
          'Template, Geosearch, Author Uploads, and Related-to File.',
          'Category sources support AND or OR logic and recursive subcategories.',
          'Geosearch supports filtered and open browse modes.',
        ],
      ),
      _SeoSection(
        heading: 'Nine precision filter nodes',
        intro:
            'Refine a query branch before it is fetched whenever Wikimedia can apply the constraint server-side.',
        items: [
          'License, Commons Quality, and exact File Format.',
          'Resolution, File Size, and Color Depth.',
          'Creation or edit Date Range, Language, and Exclude Terms.',
          'Supported formats include common image, vector, audio, video, PDF, and DjVu types.',
        ],
      ),
      _SeoSection(
        heading: 'Four set-operation nodes',
        intro:
            'Express research logic that is difficult to represent in a single search form.',
        items: [
          'Combine Constraints merges compatible query branches before fetching.',
          'Union keeps items found by either branch.',
          'Intersect keeps only items shared by both branches.',
          'Difference A−B removes the second collection from the first.',
        ],
      ),
      _SeoSection(
        heading: 'Five transform nodes',
        intro:
            'Clean, order, reduce, reshape, and enrich materialized results.',
        items: [
          'Dedupe by URL and Sort by relevance, title, creation date, or edit date.',
          'Sample or limit a collection, with optional shuffling.',
          'Field Select chooses metadata columns for CSV and JSON export.',
          'Enrich adds Structured Data on Commons and global Wikimedia usage with configurable limits.',
        ],
      ),
      _SeoSection(
        heading: 'Five output and preview nodes',
        intro:
            'Inspect the workflow or turn its final collection into reusable files and data.',
        items: [
          'CSV Export and JSON Export for metadata records.',
          'ZIP Export for original or 1280px web-optimized media.',
          'Preview for a browsable media grid and full asset inspection.',
          'Send to Search to place the completed collection in the main result grid.',
        ],
      ),
      _SeoSection(
        heading: 'Visual graph editing and execution',
        intro:
            'The editor keeps complex workflows understandable while rejecting invalid graphs.',
        items: [
          'Search the node palette, drag nodes, connect colored ports, rename, duplicate, annotate, and delete nodes.',
          'Prevent self-connections, overfilled inputs, and cyclic graphs before execution.',
          'Inspect per-node settings, notes, previews, counts, warnings, and errors.',
          'Run a capped 20-item preview or a full run of up to 1,000 items per source.',
        ],
      ),
      _SeoSection(
        heading: 'Reusable and portable workflows',
        intro:
            'Pipeline work remains local to the browser unless the user explicitly exports it.',
        items: [
          'Autosave graphs in IndexedDB and reopen or delete saved pipelines.',
          'Rename workflows and import or export portable graph JSON.',
          'Cache Wikimedia query results for faster reruns and clear the cache independently of saved graphs.',
          'Run exports from the last materialized result without silently fetching the branch again.',
        ],
      ),
    ],
  ),
  _SeoPage(
    path: 'features',
    title: 'CommonsLens Features — Wikimedia Search, Map & Export',
    description:
        'Explore every CommonsLens feature: advanced Wikimedia search, Wikidata and license filters, map discovery, attribution tools, bulk downloads, and visual data pipelines.',
    heading: 'Everything you can do with CommonsLens',
    intro:
        'CommonsLens combines advanced Commons search, semantic metadata, geographic discovery, responsible reuse, bulk export, and visual data pipelines in one free browser application.',
    sections: [
      _SeoSection(
        heading: 'Advanced Wikimedia Commons search',
        intro:
            'Search large Commons collections visually without writing CirrusSearch syntax.',
        items: [
          'Search all media, images, SVG and vector graphics, audio, video, PDFs, DjVu files, and documents.',
          'Use direct file autocomplete, multi-term OR queries with +, or run a search entirely from filters.',
          'Filter 17 exact formats and sort by relevance, title, creation date, or edit date.',
          'Use infinite pagination, removable filter chips, query preview, responsive result grids, and shareable search URLs.',
        ],
      ),
      _SeoSection(
        heading: 'Semantic, rights, and technical filters',
        intro:
            'Search the descriptive structure and rights metadata attached to Commons files.',
        items: [
          'Include or exclude Wikidata depicts entities and property-value statements with AND or OR logic.',
          'Include or exclude categories and templates, with category union, intersection, and recursive subcategories.',
          'Filter CC0, CC BY 4.0, CC BY-SA 4.0, Public Domain, attribution requirement, and quality assessment.',
          'Filter language, content model, creation and edit dates, resolution, file size, color depth, and geographic proximity.',
        ],
      ),
      _SeoSection(
        heading: 'Directories, authors, and related discovery',
        intro:
            'Move between structured directories, contributors, and connected media.',
        items: [
          'Browse paginated category and template directories or search Wikidata subject Q-codes.',
          'Open every upload from a contributor and search another author from the portfolio view.',
          'Find related files through Commons similarity search and discover media near a geotagged asset.',
          'Check where a file is used across Wikimedia languages and projects.',
        ],
      ),
      _SeoSection(
        heading: 'Interactive geographic search',
        intro:
            'Search and inspect geotagged Commons media on a responsive world map.',
        items: [
          'Search by map tap, coordinates and radius, named place, or a two-point bounding box.',
          'Plot the current search, cluster thumbnail markers, browse cluster grids, and fit the camera to results.',
          'Use street, satellite, or hybrid layers with zoom, rotation, and north-reset controls.',
          'Refine map results by license, quality, and attribution or continue the query in main Search.',
        ],
      ),
      _SeoSection(
        heading: 'Native media viewer and detailed metadata',
        intro:
            'Inspect a file in its search, map, author, or pipeline gallery context.',
        items: [
          'View images, vectors, audio, video, and supported PDFs with fallbacks for DjVu and unsupported documents.',
          'Navigate by swipe, buttons, or keyboard and choose a 1920px or full-resolution image preview.',
          'Read title, creator, uploader, descriptions, dates, MIME type, dimensions, categories, assessments, and GPS coordinates.',
          'Lazily inspect complete Structured Data on Commons, related media, and global Wikimedia usage.',
        ],
      ),
      _SeoSection(
        heading: 'License understanding and reusable attribution',
        intro:
            'Turn machine-readable Commons rights fields into practical reuse information without pretending missing metadata is permission.',
        items: [
          'Review the license, attribution status, creator, preferred credit, usage terms, copyright status, permission, and restrictions.',
          'See warnings when machine-readable rights information is incomplete.',
          'Copy plain-text attribution, an HTML figure, or a WikiText file embed.',
          'Open the original Commons page, complete license, and official Wikimedia reuse guidance.',
        ],
      ),
      _SeoSection(
        heading: 'Individual, bulk, and dataset downloads',
        intro: 'Export files and research metadata entirely in the browser.',
        items: [
          'Download an original file or available 640px, 1280px, and 1920px derivatives.',
          'Select any subset or all loaded results and export originals or 1280px files as ZIP archives.',
          'Track, cancel, and run multiple jobs while large collections are split into manageable archive parts.',
          'Receive a data.csv manifest containing source links, descriptions, technical metadata, rights, attribution, dates, classifications, and coordinates.',
        ],
      ),
      _SeoSection(
        heading: 'No-code visual Wikimedia pipelines',
        intro:
            'Connect 31 source, filter, set-operation, transform, and output nodes into a repeatable workflow.',
        items: [
          'Source media from text, categories, subjects, statements, templates, locations, authors, or related files.',
          'Combine branches with constraints, union, intersection, or difference and transform them with dedupe, sort, sample, field selection, and enrichment.',
          'Preview intermediate results or export CSV, JSON, original media ZIPs, and web-optimized ZIPs.',
          'Autosave graphs, reopen saved pipelines, import or export JSON, cache queries, and send results to Search.',
        ],
      ),
      _SeoSection(
        heading: 'Responsive, shareable, and Wikimedia-friendly',
        intro:
            'CommonsLens is an open-source client that works directly with official Wikimedia services.',
        items: [
          'Use desktop and mobile layouts, clean deep links, and installable web-app metadata.',
          'No Commons account is required, and CommonsLens does not host or claim ownership of displayed media.',
          'Lazy loading, request deduplication, global concurrency limits, throttling cooldowns, retries, and cancellation protect the user experience and Wikimedia infrastructure.',
          'Route-specific static pages, canonical URLs, structured data, and a sitemap make the public tools understandable to search engines.',
        ],
      ),
    ],
  ),
];

void main(List<String> arguments) {
  final outputRoot = Directory(arguments.isEmpty ? 'build/web' : arguments[0]);
  final source = File('${outputRoot.path}/index.html');

  if (!source.existsSync()) {
    stderr.writeln(
      'Missing ${source.path}. Build Flutter web before generating SEO pages.',
    );
    exitCode = 64;
    return;
  }

  final rootHtml = source.readAsStringSync();
  for (final page in _pages) {
    final directory = Directory('${outputRoot.path}/${page.path}')
      ..createSync(recursive: true);
    final output = File('${directory.path}/index.html');
    output.writeAsStringSync(_renderPage(rootHtml, page));
    stdout.writeln('Generated ${output.path}');
  }
}

String _renderPage(String html, _SeoPage page) {
  final canonical = '$_siteUrl/${page.path}/';
  var result = html
      .replaceFirst(
        RegExp(r'<title>.*?</title>', dotAll: true),
        '<title>${_escape(page.title)}</title>',
      )
      .replaceFirst(
        RegExp(r'<link rel="canonical" href="[^"]*">'),
        '<link rel="canonical" href="$canonical">',
      );

  result = _replaceMeta(result, 'name', 'description', page.description);
  result = _replaceMeta(result, 'property', 'og:title', page.title);
  result = _replaceMeta(
    result,
    'property',
    'og:description',
    page.description,
  );
  result = _replaceMeta(result, 'property', 'og:url', canonical);
  result = _replaceMeta(result, 'name', 'twitter:title', page.title);
  result = _replaceMeta(
    result,
    'name',
    'twitter:description',
    page.description,
  );

  result = result.replaceFirst(
    RegExp(
      r'<script id="structured-data" type="application/ld\+json">.*?</script>',
      dotAll: true,
    ),
    '<script id="structured-data" type="application/ld+json">\n'
    '${const JsonEncoder.withIndent('  ').convert(_structuredData(page))}\n'
    '  </script>',
  );

  return result.replaceFirst(
    RegExp(r'<main id="seo-fallback".*?</main>', dotAll: true),
    _fallbackContent(page),
  );
}

String _replaceMeta(
  String html,
  String attribute,
  String key,
  String content,
) {
  return html.replaceFirst(
    RegExp('<meta $attribute="${RegExp.escape(key)}"[^>]*>', dotAll: true),
    '<meta $attribute="$key" content="${_escape(content)}">',
  );
}

Map<String, Object> _structuredData(_SeoPage page) {
  final canonical = '$_siteUrl/${page.path}/';
  final features = page.sections.expand((section) => section.items).toList();
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        '@id': '$canonical#webpage',
        'url': canonical,
        'name': page.title,
        'description': page.description,
        'inLanguage': 'en',
        'isPartOf': {'@id': '$_siteUrl/#website'},
        'about': {'@id': '$_siteUrl/#app'},
        'mainEntity': {
          '@type': 'ItemList',
          'name': '${page.heading} features',
          'numberOfItems': features.length,
          'itemListElement': [
            for (var i = 0; i < features.length; i++)
              {
                '@type': 'ListItem',
                'position': i + 1,
                'name': features[i],
              },
          ],
        },
      },
      {
        '@type': 'BreadcrumbList',
        'itemListElement': [
          {
            '@type': 'ListItem',
            'position': 1,
            'name': 'CommonsLens',
            'item': '$_siteUrl/',
          },
          {
            '@type': 'ListItem',
            'position': 2,
            'name': page.heading,
            'item': canonical,
          },
        ],
      },
      {
        '@type': 'WebSite',
        '@id': '$_siteUrl/#website',
        'url': '$_siteUrl/',
        'name': 'CommonsLens',
        'alternateName': 'Commons Lens',
        'inLanguage': 'en',
      },
      {
        '@type': 'WebApplication',
        '@id': '$_siteUrl/#app',
        'name': 'CommonsLens',
        'url': '$_siteUrl/',
        'description':
            'Advanced search, map discovery, reuse guidance, bulk export, and visual data pipelines for Wikimedia Commons.',
        'applicationCategory': 'MultimediaApplication',
        'operatingSystem': 'Any',
        'browserRequirements': 'Requires JavaScript and a modern web browser.',
        'isAccessibleForFree': true,
        'featureList': features,
        'offers': {
          '@type': 'Offer',
          'price': 0,
          'priceCurrency': 'USD',
        },
      },
    ],
  };
}

String _fallbackContent(_SeoPage page) {
  final sections = page.sections.map((section) {
    final items = section.items
        .map((item) => '        <li>${_escape(item)}</li>')
        .join('\n');
    return '''    <section>
      <h2>${_escape(section.heading)}</h2>
      <p>${_escape(section.intro)}</p>
      <ul>
$items
      </ul>
    </section>''';
  }).join('\n\n');

  return '''<main id="seo-fallback">
    <h1>${_escape(page.heading)}</h1>
    <p>${_escape(page.intro)}</p>

    <nav aria-label="CommonsLens tools">
      <a href="/">Advanced media search</a>
      <a href="/browse/">Browse Wikimedia categories, templates, and subjects</a>
      <a href="/map/">Search Wikimedia Commons by location</a>
      <a href="/pipeline/">Build visual Wikimedia data pipelines</a>
      <a href="/features/">Explore all CommonsLens features</a>
    </nav>

$sections

    <section>
      <h2>Free, open-source Wikimedia research tools</h2>
      <p>CommonsLens runs in the browser, requires no Commons account, and uses official Wikimedia and Wikidata APIs. Media remains hosted by Wikimedia Commons and retains its original source and rights information.</p>
      <p><a href="https://github.com/commonslens/commonslens.github.io">View the CommonsLens source code on GitHub</a>.</p>
    </section>
  </main>''';
}

String _escape(String value) => const HtmlEscape(HtmlEscapeMode.attribute)
    .convert(value)
    .replaceAll('&#39;', '&apos;');

class _SeoPage {
  const _SeoPage({
    required this.path,
    required this.title,
    required this.description,
    required this.heading,
    required this.intro,
    required this.sections,
  });

  final String path;
  final String title;
  final String description;
  final String heading;
  final String intro;
  final List<_SeoSection> sections;
}

class _SeoSection {
  const _SeoSection({
    required this.heading,
    required this.intro,
    required this.items,
  });

  final String heading;
  final String intro;
  final List<String> items;
}
