<div align="center">
  <img src="web/favicon.png" alt="CommonsLens logo" width="96" height="96">

  # CommonsLens

  **Search, map, inspect, reuse, and export media from Wikimedia Commons.**

  CommonsLens is a free browser-based research interface for finding reusable images, SVGs, audio, video, and documents through advanced metadata filters, geographic discovery, rights guidance, bulk downloads, and visual data pipelines.

  [Open CommonsLens](https://commonslens.github.io/) · [Explore all features](https://commonslens.github.io/features/) · [Terms](https://commonslens.github.io/terms/) · [Privacy](https://commonslens.github.io/privacy/) · [View the source](https://github.com/commonslens/commonslens.github.io)

  [![Deploy Flutter Web](https://github.com/commonslens/commonslens.github.io/actions/workflows/deploy.yml/badge.svg)](https://github.com/commonslens/commonslens.github.io/actions/workflows/deploy.yml)
</div>

---

<!--
Hero screenshot suggestion:
1. Save a wide homepage or search-results screenshot as docs/images/commonslens-hero.png
2. Uncomment the line below.

![CommonsLens search interface](docs/images/commonslens-hero.png)
-->

## Why CommonsLens?

Wikimedia Commons contains an extraordinary amount of reusable media, but finding a precise file can require knowledge of categories, templates, Wikidata statements, CirrusSearch syntax, licences, and Commons-specific metadata.

CommonsLens brings those systems into one visual application. It is designed for researchers, educators, journalists, designers, developers, archivists, cultural institutions, and anyone who needs to find and correctly reuse Commons media.

- No Wikimedia account is required.
- Media is fetched directly from Wikimedia Commons; CommonsLens does not re-host it.
- Every file retains links to its original Commons page and licence information.
- Searches and asset views can be shared as URLs.
- Search, metadata inspection, pipeline execution, and exports run in the browser.

## Table of contents

- [Search and discovery](#search-and-discovery)
- [Semantic and metadata filters](#semantic-and-metadata-filters)
- [Rights, quality, and technical filters](#rights-quality-and-technical-filters)
- [Directory browser](#directory-browser)
- [Interactive map search](#interactive-map-search)
- [Media viewer and metadata](#media-viewer-and-metadata)
- [Reuse and attribution guidance](#reuse-and-attribution-guidance)
- [Author portfolios](#author-portfolios)
- [Downloads and bulk export](#downloads-and-bulk-export)
- [Visual data pipelines](#visual-data-pipelines)
- [Sharing, responsive design, and PWA support](#sharing-responsive-design-and-pwa-support)
- [Architecture and reliability](#architecture-and-reliability)
- [SEO and static rendering](#seo-and-static-rendering)
- [Local development](#local-development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Project structure](#project-structure)
- [Contributing](#contributing)
- [Media rights and disclaimer](#media-rights-and-disclaimer)

## Search and discovery

CommonsLens provides a visual frontend for Wikimedia Commons and CirrusSearch.

### Search modes

- Full-text media search.
- Filter-only searches with no text query required.
- Multi-term OR search using `+`, for example `Eiffel Tower + Colosseum`.
- Direct file-title autocomplete.
- Autocomplete that understands the currently edited `+` segment.
- Infinite pagination as the user approaches the end of the result grid.
- Result counts that indicate when additional pages remain.
- A selectable preview of the generated CirrusSearch query.

### Media scopes

- All media
- Images
- SVGs, vectors, and diagrams
- Audio
- Video
- Documents

### Exact file formats

| Images and vectors | Audio and video | Documents |
| --- | --- | --- |
| JPG, JPEG, PNG, SVG, GIF, TIF, TIFF, WEBP | OGG, OGA, OGV, MP3, WAV, WEBM, MP4 | PDF, DJVU |

### Sorting

- Relevance
- Title A–Z
- Recently edited
- Least recently edited
- Recently created
- Oldest created

### Search result cards

- Responsive, staggered media grid.
- Lazy thumbnail loading and bounded browser image caching.
- File-type badges and non-image fallback previews.
- Human-friendly title fallback: object name, image description, then filename.
- Creation, upload, or revision date fallback.
- Licence summary.
- One-click original-file download.
- Long-press selection for bulk export.
- Full asset viewer on click.

<!--
Search screenshot suggestion:
Save as docs/images/search-results.png and uncomment:

![CommonsLens search results with active filters](docs/images/search-results.png)
-->

## Semantic and metadata filters

### Wikidata depicts search

- Search subjects by Wikidata label or Q-code.
- See entity descriptions before selecting a result.
- Include or exclude subjects independently.
- Require every subject with intersection/AND mode.
- Match any subject with union/OR mode.

### Wikidata property search

- Search arbitrary Structured Data on Commons property-value statements.
- Select the property first, then its entity value.
- Include or exclude individual statements.
- Combine multiple statements with AND or OR logic.

### Commons categories

- Category autocomplete.
- Multiple included and excluded categories.
- Intersection/AND or union/OR matching.
- Strict mode for exact categories.
- Deep mode for recursively nested subcategories.

### MediaWiki templates

- Template autocomplete.
- Multiple required templates.
- Independent template exclusions.
- Support for collection, institution, source, and granular rights templates.

## Rights, quality, and technical filters

### Licence filters

- CC0
- CC BY 4.0
- CC BY-SA 4.0
- Public Domain
- Multi-select matching across accepted licences

### Attribution and Commons assessments

- Any attribution status
- Attribution required
- No attribution required
- Quality Images
- Valued Images
- Featured Pictures

Attribution filtering is applied against returned rights metadata. CommonsLens does not infer that incomplete metadata means a file is unrestricted.

### Technical metadata

- Language code.
- Wikimedia content model.
- Creation-date range.
- Last-edited-date range.
- Minimum and maximum width.
- Minimum and maximum height.
- Minimum and maximum file size in KB or MB.
- 1, 8, 16, 24, or 32-bit colour depth.
- Latitude, longitude, and radius.
- Proximity to a named Commons page or place.

Every active constraint is represented by a removable filter chip and encoded in the shareable search URL.

## Directory browser

The `/browse` interface makes Commons classification systems directly explorable.

### Categories

- Paginated directory browsing.
- Prefix and jump search.
- File counts for directory entries.
- One-click transfer into the main search.

### Templates

- Paginated MediaWiki template directory.
- Prefix and jump search.
- One-click transfer into the main search.

### Depicted subjects

- Wikidata entity search with up to 50 matches.
- Labels, Q-codes, and descriptions.
- One-click transfer into the main search.

All directory tabs include loading, empty, error, and retry states.

## Interactive map search

CommonsLens supports geographic discovery as both a starting point and an extension of a normal search.

### Search modes

- **Map → Search:** tap the map or enter coordinates to begin a radius search.
- **Search → Map:** plot geotagged files from the active main search.
- **Filtered map search:** combine a geographic area with text and metadata filters.

### Geographic tools

- Tap-to-search radius.
- Manual latitude, longitude, and radius entry.
- Search near a named place.
- Two-point custom bounding box.
- Visible centre marker, radius circle, and bounding-box polygon.
- Bounding-box cancellation and redraw.
- Deep links from geotagged assets into nearby-media searches.

### Map presentation

- Dark Gray Canvas default map with reference labels.
- Street map.
- Satellite imagery.
- Hybrid satellite and labels.
- Thumbnail markers.
- Zoom-dependent marker clustering.
- Cluster media grids.
- Desktop split-screen map and result pane.
- Responsive mobile map and results layout.
- Camera fitting for imported results.
- Zoom, rotate-left, rotate-right, and reset-north controls.

### Map filters and actions

- Licence filtering.
- Quality filtering.
- Attribution filtering.
- Text queries combined with a geographic point.
- Import the current search session.
- Open a geographic query in the main Search interface.
- Open any map file in the full asset viewer without losing map context.

<!--
Map screenshot suggestion:
Save as docs/images/map-search.png and uncomment:

![CommonsLens geographic media search](docs/images/map-search.png)
-->

## Media viewer and metadata

The asset viewer preserves the gallery that opened it, whether the file came from Search, Map, an author portfolio, a pipeline preview, or a direct URL.

### Navigation

- Swipeable carousel.
- Previous and next buttons.
- Left and right keyboard navigation.
- Current position and result count.
- Automatic near-end pagination.
- URL updates as the selected file changes.
- Direct-link fallback that fetches a single file when the original in-memory gallery is unavailable.

### Native media rendering

- Images and SVG/vector graphics.
- Native browser video controls.
- Native browser audio controls.
- Inline PDFs in supported browsers.
- Safari and DjVu fallbacks.
- Open/download fallback for unsupported documents.
- Web-optimised 1920px or full-resolution image preview.
- Preview-quality preference stored locally in the browser.

### File metadata

- File title.
- Creator or author.
- Uploader and uploader portfolio link.
- Object name.
- Image description and search snippet.
- Original creation and upload dates.
- MIME type and extension.
- Pixel dimensions.
- Commons categories and assessments.
- GPS coordinates.

### Lazy discovery panels

- Complete Structured Data on Commons statements.
- Human-readable Wikidata property and value labels.
- Related media through Commons similarity search.
- Global usage across Wikimedia projects and languages.
- Links to individual pages using the file.
- Nearby-media discovery for geotagged assets.

<!--
Viewer screenshot suggestion:
Save as docs/images/asset-viewer.png and uncomment:

![CommonsLens asset viewer and metadata inspector](docs/images/asset-viewer.png)
-->

## Reuse and attribution guidance

CommonsLens turns machine-readable Commons fields into practical reuse information while keeping the original metadata authoritative.

- Licence name and full licence link.
- Attribution requirement.
- Creator details.
- Preferred credit.
- Usage terms.
- Copyright status.
- Special permission.
- Restrictions and warnings.
- Warning when machine-readable rights information is incomplete.
- Copy-ready plain-text attribution.
- Copy-ready HTML figure/embed.
- Copy-ready WikiText file embed.
- Links to the Commons source page and official Wikimedia reuse guidance.

The reuse panel is an aid, not legal advice. Users should verify the file page, licence, and any jurisdiction-specific restrictions before publication.

## Author portfolios

- Open an uploader’s portfolio directly from the asset viewer.
- Browse the contributor’s upload stream with infinite pagination.
- Search for another uploader by username.
- View upload counts.
- Open portfolio files in the full gallery viewer.
- Select and bulk-download portfolio media.
- Export to a contributor-named ZIP archive.
- Reset selection cleanly when changing authors.

## Downloads and bulk export

### Individual files

- Original file.
- Small 640px derivative.
- Medium 1280px derivative.
- Large 1920px derivative.
- Sanitised filenames.
- External-open fallback when direct browser downloading is unavailable.

### Bulk collections

- Long-press a media card to enter selection mode.
- Select individual files or all currently loaded files.
- Export original-resolution media.
- Export web-optimised 1280px media.
- Track several simultaneous download jobs independently.
- Cancel active downloads.
- Report failed files and errors.
- Split selections larger than 25 items into sequential ZIP parts.
- Request a browser wake lock during long, visible downloads when supported.
- Use a small rolling worker pool to limit UI and Wikimedia API pressure.

### Metadata manifest

Each ZIP includes `data.csv` with fields covering:

- Archive filename and Commons title.
- Original, thumbnail, Commons, and description URLs.
- Description, object name, and search snippet.
- MIME type, dimensions, and SVG status.
- Creator and uploader.
- Licence, licence URL, usage terms, copyright status, and attribution requirement.
- Permission, restrictions, and preferred credit.
- Original, upload, and revision dates.
- Categories and quality assessments.
- GPS latitude and longitude.

## Visual data pipelines

The `/pipeline` workspace is a no-code visual ETL and research environment for Wikimedia Commons.

### The 31 node types

| Category | Nodes |
| --- | --- |
| Sources | Text Query, Category, Depicted Subject, Wikidata Statement, Template, Geosearch, Author Uploads, Related-to File |
| Filters | Licence, Quality, Format, Resolution, File Size, Colour Depth, Date Range, Language, Exclude Terms |
| Set operations | Combine Constraints, Union, Intersect, Difference A−B |
| Transforms | Dedupe by URL, Sort, Sample/Limit, Field Select, Enrich |
| Outputs | CSV Export, JSON Export, ZIP Export, Preview, Send to Search |

### Graph editor

- Searchable node palette grouped by category.
- Coloured nodes and typed input/output ports.
- Drag, position, connect, rename, duplicate, annotate, and delete nodes.
- Remove individual edges.
- Prevent self-connections.
- Prevent multiple links into the same input.
- Prevent cycles before they enter the graph.
- Display node and edge counts.

### Node inspector

- Settings tab.
- Intermediate Preview tab.
- Per-node Notes tab.
- Input and output connection counts.
- Human-readable configuration summaries.
- Async category, template, Wikidata property, and entity pickers.
- Individual media downloads and full viewer access from previews.

### Execution model

- Compile compatible sources and filters into one server-side Commons query.
- Combine compatible constraint branches before fetching.
- Materialise collections only when required by a transform, set operation, preview, or export.
- Run safe topological execution.
- Show idle, running, successful, warning, and error states per node.
- Use 20 items per source for preview runs.
- Use up to 1,000 items per source for full runs.
- Preserve typed media records alongside projected or enriched export fields.
- Avoid silently rerunning the graph when exporting the last result.

### Collection operations

- Union collections while preserving order.
- Intersect collections by media URL.
- Subtract collection B from collection A.
- Deduplicate by URL.
- Sort results.
- Limit or randomly sample results.
- Select specific CSV/JSON fields.
- Enrich results with Structured Data on Commons.
- Enrich results with global Wikimedia usage and usage counts.

### Pipeline outputs

- CSV metadata.
- Pretty-printed JSON records.
- Original-resolution ZIP.
- Web-optimised 1280px ZIP.
- Browsable preview grid.
- Transfer the final collection into the main Search result grid.

### Persistence and portability

- Autosave every graph edit in IndexedDB.
- Browse, reopen, rename, and delete saved pipelines.
- Start a new pipeline without deleting older graphs.
- Export a portable `.pipeline.json` file.
- Import a previously exported pipeline.
- Preserve node configuration, position, ports, and connections.
- Cache Wikimedia query results for one hour.
- Clear result caches without deleting saved graphs.

<!--
Pipeline screenshot suggestion:
Save as docs/images/visual-pipeline.png and uncomment:

![CommonsLens visual Wikimedia data pipeline](docs/images/visual-pipeline.png)
-->

## Sharing, responsive design, and PWA support

- Clean path-based routes.
- Search state encoded in URL query parameters.
- Shareable file, author, map, directory, pipeline, and feature routes.
- GitHub Pages direct-link and refresh recovery.
- Desktop docked and collapsible filter panel.
- Mobile filter drawer and compact controls.
- Responsive result grids, map panes, metadata views, and feature catalogue.
- Installable web-app manifest.
- Standalone display mode and maskable icons.

## Architecture and reliability

CommonsLens is a Flutter web application backed by a reusable plain-Dart core package.

### Main technologies

- Flutter and Dart
- Riverpod for application state
- GoRouter for URL-aware navigation
- `flutter_map` for geographic discovery
- `arcane_nodes` for the pipeline canvas
- IndexedDB for pipeline persistence and caching
- Official Wikimedia Commons, Wikidata, and MediaWiki APIs

### Wikimedia request handling

All application-managed Wikimedia requests share one coordination layer:

- Maximum of two concurrent requests.
- Minimum spacing between request starts.
- Duplicate in-flight Action API GET requests are coalesced.
- Wikimedia `maxlag` support.
- API identification headers.
- `Retry-After` support.
- Exponential backoff with jitter.
- Retry handling for throttling, server failures, timeouts, and rejected responses.
- Global cooldown after a throttling response.
- Cancellation support for long-running work.

### Performance choices

- Expensive asset metadata loads only when its panel is expanded.
- Search thumbnails use staggered loading.
- Browser image-cache size is bounded.
- Pipeline query results are cached separately from saved graphs.
- Bulk downloads use a rolling worker pool.
- ZIP files are written incrementally without recompressing already compressed media.
- Large collections are split to reduce peak browser memory use.

## SEO and static rendering

Flutter’s canvas output alone is difficult for crawlers and no-JavaScript clients to understand, so CommonsLens also ships semantic HTML entry content.

- Readable static first render for the homepage.
- Dedicated static entry documents for `/browse/`, `/map/`, `/pipeline/`, and `/features/`.
- Unique titles, descriptions, canonical URLs, Open Graph, and Twitter metadata.
- Schema.org `WebSite`, `WebApplication`, `WebPage`, `BreadcrumbList`, and `ItemList` data.
- Crawlable navigation between primary tools.
- XML sitemap and robots declaration.
- Dynamic search, author, and asset URLs remain shareable but are kept out of the unbounded index surface.

The deployment workflow generates the route-specific documents after Flutter’s production build.

## Local development

### Requirements

- Flutter stable
- Dart SDK compatible with `^3.6.0`
- A modern browser, preferably Chrome or Chromium for development

### Install dependencies

```bash
flutter pub get
```

### Run locally

```bash
flutter run -d chrome
```

### Production web build

```bash
flutter build web --release --base-href /
dart run tool/generate_seo_pages.dart build/web
```

The second command creates the static Browse, Map, Pipeline, and Features entry documents inside `build/web`.

## Testing

Run static analysis:

```bash
flutter analyze
```

Run the application test suite:

```bash
flutter test
```

Run the reusable core package tests:

```bash
cd packages/commonslens_core
dart test
```

Live Wikimedia integration tests are opt-in so normal test runs remain deterministic:

```bash
flutter test --dart-define=RUN_LIVE_WIKIMEDIA_TESTS=true
```

## Deployment

Pushes to `master` trigger the GitHub Actions workflow in `.github/workflows/deploy.yml`.

The workflow:

1. Checks out the repository.
2. Installs Flutter stable.
3. Restores project dependencies.
4. Builds the release web application.
5. Generates route-specific static SEO pages.
6. Publishes `build/web` to GitHub Pages.

Live site: <https://commonslens.github.io/>

## Project structure

```text
commonslens/
├── lib/
│   ├── search_page.dart              # Main search and result experience
│   ├── advanced_filters_drawer.dart  # Semantic, rights, and technical filters
│   ├── asset_viewer.dart             # Fullscreen media viewer
│   ├── asset_metadata_panel.dart     # Metadata, discovery, reuse, downloads
│   ├── map_page.dart                 # Interactive geographic interface
│   ├── pipeline_page.dart            # Visual pipeline editor
│   ├── features_page.dart            # Public feature catalogue
│   ├── download_service.dart         # Individual, ZIP, CSV, and JSON export
│   ├── seo_service.dart              # Route-aware document metadata
│   └── router.dart                   # Application routes and SEO metadata sync
├── packages/commonslens_core/
│   └── lib/src/                      # Search, query, pipeline, transport, and models
├── test/                             # Flutter application tests
├── tool/generate_seo_pages.dart      # Static route-page generator
├── web/                              # Web shell, manifest, sitemap, icons, fallback HTML
└── .github/workflows/deploy.yml      # GitHub Pages deployment
```

## Adding screenshots later

Suggested image paths are already included as commented Markdown throughout this README. A simple structure is:

```text
docs/images/
├── commonslens-hero.png
├── search-results.png
├── map-search.png
├── asset-viewer.png
└── visual-pipeline.png
```

After adding an image, find its nearby commented Markdown block in this README and uncomment the image line. Wide screenshots around 1600×900 work well for GitHub, while compressed PNG or WebP files keep the repository lighter.

## Contributing

Contributions and well-scoped bug reports are welcome.

1. Fork the repository.
2. Create a focused branch.
3. Make the change and add or update tests where appropriate.
4. Run `flutter analyze` and `flutter test`.
5. Open a pull request explaining the behaviour and trade-offs.

For search or metadata changes, please preserve Wikimedia API courtesy limits and avoid inferring legal conclusions from missing rights fields.

Unless explicitly stated otherwise, contributions submitted for inclusion in CommonsLens are accepted under the Apache License 2.0.

## License

CommonsLens is open-source software licensed under the [Apache License 2.0](LICENSE).

Copyright © 2026 Pratham Shah.

The licence applies to the CommonsLens software in this repository. Third-party dependencies and bundled components remain under their respective licence notices. Wikimedia Commons media and metadata displayed or downloaded through the application are not part of the software licence; every file retains the rights and reuse requirements shown on its original source page.

The Apache License does not grant permission to use CommonsLens trade names, trademarks, service marks, or product identity except as needed to accurately describe the origin of the software.

## Media rights and disclaimer

CommonsLens is an independent interface and is not affiliated with or endorsed by the Wikimedia Foundation.

Files and metadata displayed by CommonsLens come from Wikimedia Commons and related Wikimedia services. Their individual licences, attribution requirements, personality rights, privacy considerations, trademarks, and other restrictions remain authoritative on the original file pages.

CommonsLens does not make, host, own, or claim copyright over the displayed media. Its reuse summaries are informational and are not legal advice.
