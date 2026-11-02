import 'dart:convert';
import 'dart:io';

const _siteUrl = 'https://commonslens.github.io';

// Keep the public feature catalogue aligned with the numbered sections in
// web/docs/index.html. The guide is the detailed source of truth; this list is
// intentionally only its compact, linked overview.
const _guideFeatureSections = <_SeoSection>[
  _SeoSection(
    heading: 'Start here',
    intro:
        'Build the correct mental model and complete your first search from discovery to reuse.',
    items: ['What CommonsLens is · first search · four main workflows'],
  ),
  _SeoSection(
    heading: 'How your data moves',
    intro:
        'See what leaves the browser, what stays local, what goes into URLs, and what clearing data removes.',
    items: ['Requests · local storage · cache · clipboard · downloads'],
  ),
  _SeoSection(
    heading: 'Search Wikimedia Commons',
    intro:
        'Turn a phrase, file title, or broad idea into a useful Commons result set.',
    items: ['Media scopes · formats · sorting · result cards · sharing'],
  ),
  _SeoSection(
    heading: 'Use advanced filters',
    intro:
        'Use subjects, categories, rights, quality, dates, technical fields, and location to make a precise query.',
    items: ['Include/exclude · AND/OR · Q-codes · filter glossary'],
  ),
  _SeoSection(
    heading: 'Browse categories, templates, and subjects',
    intro:
        'Find Commons vocabulary when you do not yet know the right category, template, or Wikidata subject.',
    items: ['Categories · templates · depicted subjects · file counts'],
  ),
  _SeoSection(
    heading: 'Search by map',
    intro:
        'Use geographic context to find media near a point, place, radius, or drawn area.',
    items: ['Markers · clusters · layers · map-to-search workflows'],
  ),
  _SeoSection(
    heading: 'Inspect a file',
    intro:
        'Read the file’s context, metadata, structured data, related media, and source page.',
    items: ['Viewer · creator · dates · coordinates · preview quality'],
  ),
  _SeoSection(
    heading: 'Check reuse and create attribution',
    intro:
        'Interpret the reported rights information and produce a starting point for attribution.',
    items: ['Licenses · attribution · HTML · WikiText · verification'],
  ),
  _SeoSection(
    heading: 'Save bookmarks and folders',
    intro:
        'Keep references to files you want to revisit without pretending to mirror the Commons catalogue.',
    items: ['Local collections · folders · search · export · recovery'],
  ),
  _SeoSection(
    heading: 'Explore an uploader’s portfolio',
    intro:
        'Explore an uploader’s files, inspect them, and export a portfolio-sized metadata set.',
    items: ['Uploader · portfolio search · viewer · export'],
  ),
  _SeoSection(
    heading: 'Download files and export metadata',
    intro:
        'Separate downloading media files from exporting metadata and URLs for research.',
    items: ['Originals · derivatives · CSV · selection · file fallbacks'],
  ),
  _SeoSection(
    heading: 'Build a visual pipeline',
    intro:
        'Build repeatable visual workflows that fetch, refine, enrich, and export collections.',
    items: ['Sources · filters · branches · transforms · outputs'],
  ),
  _SeoSection(
    heading: 'Share searches and understand local state',
    intro:
        'Know what a URL shares, what survives a reload, and how to move local work between devices.',
    items: ['Search URLs · asset URLs · map views · JSON backups'],
  ),
  _SeoSection(
    heading: 'Rights, privacy, and responsible use',
    intro:
        'Understand provider boundaries, local privacy, licensing risk, and respectful use of public infrastructure.',
    items: ['Storage · providers · sensitive terms · rate limits'],
  ),
  _SeoSection(
    heading: 'Troubleshooting',
    intro:
        'Diagnose empty results, missing media, unavailable metadata, lost local state, and slow workflows.',
    items: ['Search · maps · previews · storage · exports · pipelines'],
  ),
];

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
          'Filter by attribution requirement, Quality Media, Valued Media, or Featured Media.',
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
          'Switch between multilingual street, English-labelled street, satellite, and hybrid layers.',
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
        'Explore the CommonsLens features documented in the user guide: search, filters, maps, file inspection, reuse, bookmarks, exports, pipelines, sharing, privacy, and troubleshooting.',
    heading: 'Everything you can do with CommonsLens',
    intro:
        'CommonsLens is a visual research workspace for discovering Wikimedia Commons media, checking its context and reuse information, organizing files, and exporting the metadata you need.',
    sections: _guideFeatureSections,
  ),
  _SeoPage(
    path: 'terms',
    title: 'Terms of Use | CommonsLens',
    description:
        'Read the CommonsLens terms for Wikimedia media attribution, licensing, responsible API use, third-party services, and legal responsibilities.',
    heading: 'CommonsLens Terms of Use',
    intro:
        'Effective and last reviewed 22 October 2026. CommonsLens helps people find and understand reusable media, but every file keeps its own licence and attribution requirements. Users are responsible for checking and following them.',
    sections: [
      _SeoSection(
        heading: 'Agreement, scope, and independence',
        intro:
            'These terms apply to the website, search tools, map, viewer, downloads, exports, and visual pipelines. CommonsLens is independent and is not operated, sponsored, endorsed, or warranted by Wikimedia or any connected provider.',
        items: [
          'By using CommonsLens, you agree to these Terms; if you do not agree, do not use the service.',
          'CommonsLens does not own displayed files and does not grant a new licence when a file is viewed or downloaded.',
        ],
      ),
      _SeoSection(
        heading: 'Media licences and attribution are mandatory',
        intro:
            'You MUST follow every attribution, credit, source-link, licence notice, share-alike, modification disclosure, author-requested credit line, and other reuse requirement set by the file licence, Commons description page, and author or rightsholder. The original page and applicable licence control if a CommonsLens summary is incomplete or conflicts.',
        items: [
          'Open the original Commons file page before publishing or distributing a file.',
          'Credit the creator rather than merely the uploader unless the source says otherwise.',
          'Name or link the licence, indicate modifications, and apply share-alike terms whenever required.',
          'Do not remove credit, rights statements, watermarks, or notices in a way the licence forbids.',
        ],
      ),
      _SeoSection(
        heading: 'Rights beyond copyright',
        intro:
            'A free copyright licence does not clear every proposed use. Privacy, publicity or personality rights, moral rights, trademarks, patents, cultural restrictions, sensitive subjects, and local law may still apply.',
        items: [
          'Commercial, advertising, political, medical, and defamatory contexts can require extra care or permission.',
          'Rights filters, warnings, and generated attribution snippets are conveniences, not legal advice or a guarantee.',
        ],
      ),
      _SeoSection(
        heading: 'Responsible Wikimedia and map use',
        intro:
            'CommonsLens limits concurrency, spaces requests, caches some pipeline results, and backs off when Wikimedia asks it to slow down. Users should still avoid many continuous queries and pause between large batches.',
        items: [
          'Avoid rapid refreshes, several query-heavy tabs, repetitive searches, and repeated large pipeline runs.',
          'Do not bypass rate limits, retry signals, technical safeguards, or provider usage policies.',
          'Do not use the interactive site as a bot, scraper, crawler, or high-volume automation endpoint.',
          'Do not bulk-fetch or prefetch map tiles; use official APIs for sustained automated research and obey their rules.',
        ],
      ),
      _SeoSection(
        heading: 'Acceptable use and third-party services',
        intro:
            'Use CommonsLens lawfully without disrupting or attempting unauthorized access to CommonsLens or connected services. Users are responsible for their searches, exports, publications, and downstream media use.',
        items: [
          'Wikimedia, Wikidata, OpenStreetMap, Esri, GitHub Pages, and linked sites apply their own terms and policies.',
          'Do not infringe rights, distribute unlawful material, misrepresent authorship, evade access controls, or introduce malicious code.',
        ],
      ),
      _SeoSection(
        heading: 'Availability and limits of responsibility',
        intro:
            'CommonsLens is free and provided as is and as available. Search results, rights fields, snippets, maps, exports, and external APIs may be incomplete, inaccurate, changed, delayed, or unavailable.',
        items: [
          'No warranty is made about accuracy, fitness, non-infringement, uninterrupted availability, or preservation of local data, to the extent law permits.',
          'To the extent permitted by law, CommonsLens and its maintainers are not liable for loss from metadata, third-party services, unavailable data, or media reuse.',
          'CommonsLens source code is licensed under Apache License 2.0, except for third-party material under its own notices. That software licence does not apply to Wikimedia media or data displayed through the app.',
        ],
      ),
    ],
  ),
  _SeoPage(
    path: 'privacy',
    title: 'Privacy Policy | CommonsLens',
    description:
        'Learn how CommonsLens works without analytics or advertising trackers, what stays on your device, which providers receive necessary requests, and what is not collected.',
    heading: 'CommonsLens Privacy Policy',
    intro:
        'Effective and last reviewed 22 October 2026. CommonsLens has no analytics, advertising trackers, accounts, or private application database. Most work happens in the browser. Only the outside services needed for hosting, Wikimedia content, and map tiles receive ordinary web requests.',
    sections: [
      _SeoSection(
        heading: 'The short version',
        intro:
            'CommonsLens minimises data through local processing, no accounts, and no application backend, but does not claim that web use is invisible or fully anonymous.',
        items: [
          'No name, email address, password, payment method, or profile is requested.',
          'No visitor analytics, advertising, fingerprinting, session-recording, or behavioural-tracking service is used.',
          'Searches go to Wikimedia; map views request visible tiles from OpenStreetMap or Esri.',
          'Saved pipelines, notes, caches, and image-preview preferences stay in browser storage.',
          'CommonsLens does not sell personal information, run ads, create user profiles, or transmit interaction events to an analytics provider.',
        ],
      ),
      _SeoSection(
        heading: 'No analytics or behavioural tracking',
        intro:
            'CommonsLens does not load visitor analytics, tag managers, ad pixels, telemetry SDKs, session replay tools, or behavioural-tracking services. It does not send page views, searches, filters, file titles, downloads, clicks, map activity, device identifiers, or interaction events to CommonsLens or an analytics provider.',
        items: [
          'The static Google Search Console ownership file contains no executable code and is not loaded by ordinary pages; it only lets Google periodically confirm ownership.',
          'CommonsLens does not intentionally set tracking cookies.',
          'Browser storage supports preferences, saved pipelines, and caches only; it is not used to follow visitors across sites.',
        ],
      ),
      _SeoSection(
        heading: 'Information stored only on the device',
        intro:
            'CommonsLens does not sync this browser data to an account or application server.',
        items: [
          'Local storage remembers web-optimised or full-resolution image preview preference.',
          'IndexedDB stores saved pipeline graphs, node settings, positions, names and notes, and cached public Wikimedia query results.',
          'Browser and service-worker caches may retain application files, images, media, tiles, and responses.',
          'Downloaded files, ZIPs, CSV or JSON exports, and pipeline definitions are saved only where the user chooses.',
          'Cached results are fresh for one hour but can remain locally until cleared, overwritten, evicted, or removed with site data; saved graphs remain until deleted.',
        ],
      ),
      _SeoSection(
        heading: 'Direct requests to outside providers',
        intro:
            'The browser contacts providers directly. They normally receive the IP address, user agent, requested resource, time, referrer where supplied, and standard request information under their own policies.',
        items: [
          'GitHub Pages hosts the app and may log page requests and technical usage data.',
          'Wikimedia Commons and Wikidata receive search terms, filters, file names, API requests, and media requests.',
          'OpenStreetMap receives multilingual street-tile requests; Esri receives English street-map, satellite-imagery, and reference-tile requests when those layers are used.',
          'External source, licence, usage, and repository pages apply their own privacy policies.',
        ],
      ),
      _SeoSection(
        heading: 'What CommonsLens does not collect',
        intro:
            'CommonsLens does not maintain a private application database or identity profile.',
        items: [
          'No accounts, contact details, passwords, identity documents, profiles, payment information, contacts, messages, or private uploads.',
          'No camera, microphone, or clipboard-content access; the reuse tool only writes requested text to the clipboard.',
          'No device precise-location permission; map searches use user-chosen locations and public file coordinates.',
          'No page-view or interaction analytics, CommonsLens-owned server log, cloud database, advertising profile, data-broker feed, or cross-device identity.',
        ],
      ),
      _SeoSection(
        heading: 'Privacy choices, security, and contact',
        intro:
            'Users can clear browser site data to remove preferences, caches, and saved pipelines, or clear only the pipeline cache. Avoiding a map layer avoids requests to that provider.',
        items: [
          'No internet transmission or browser storage is perfectly secure, and providers may process data in other countries.',
          'This policy is updated when collection or providers materially change.',
          'Questions and corrections can be raised in the public source repository without posting sensitive information.',
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
      <a href="/docs/">Read the CommonsLens user guide</a>
      <a href="/terms/">Terms of Use</a>
      <a href="/privacy/">Privacy Policy</a>
      <a href="https://github.com/commonslens/commonslens.github.io">Source code on GitHub</a>
      <a href="https://github.com/commonslens/commonslens.github.io/blob/master/LICENSE">Apache License 2.0</a>
    </nav>

$sections

    <section>
      <h2>Free, open-source Wikimedia research tools</h2>
      <p>CommonsLens runs in the browser, requires no Commons account, and uses official Wikimedia and Wikidata APIs. Media remains hosted by Wikimedia Commons and retains its original source and rights information.</p>
      <p><a href="https://github.com/commonslens/commonslens.github.io">View the CommonsLens source code on GitHub</a>.</p>
    </section>

    <footer>
      <a href="/terms/">Terms of Use</a>
      <a href="/privacy/">Privacy Policy</a>
      <a href="https://github.com/commonslens/commonslens.github.io">CommonsLens source code</a>
      <a href="https://github.com/commonslens/commonslens.github.io/blob/master/LICENSE">Apache License 2.0</a>
    </footer>
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
