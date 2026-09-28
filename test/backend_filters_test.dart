import 'package:flutter_test/flutter_test.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/search_models.dart';

/// Hits the live Commons API. Each case: apply exactly one filter (plus a
/// minimal query/context where CirrusSearch requires one), assert a clean
/// fetch (no error — our stand-in for "status 200") and a non-zero result
/// count. Not a correctness suite for match quality — just "does this
/// filter still resolve to a working CirrusSearch/MediaWiki call."
///
/// Known-flaky by nature: depends on live data (category sizes, template
/// usage, uploader activity) staying non-trivial. If a case starts failing,
/// check whether the underlying Commons data still exists before assuming
/// a code regression.
final _backend = CommonsBackend();

Future<MediaSearchResult> _run(SearchState state) => _backend.search(state);

void _expectOk(MediaSearchResult result, String label) {
  expect(result.error, isNull,
      reason: '[$label] fetch failed: ${result.error}');
  expect(result.items, isNotEmpty, reason: '[$label] zero results');
}

void main() {
  const runLive = bool.fromEnvironment('RUN_LIVE_WIKIMEDIA_TESTS');
  if (!runLive) {
    test(
      'live Wikimedia backend smoke tests',
      () {},
      skip: 'Opt in with --dart-define=RUN_LIVE_WIKIMEDIA_TESTS=true.',
    );
    return;
  }

  // The shared request gate deliberately paces Commons calls. Keep this
  // comfortably above one request window so safety throttling is not
  // mistaken for a backend regression.
  const timeout = Timeout(Duration(seconds: 90));

  group('text & tab', () {
    test('plain text query', () async {
      final r = await _run(const SearchState(queryText: 'Eiffel Tower'));
      _expectOk(r, 'plain text');
    }, timeout: timeout);

    test('tab: images', () async {
      final r = await _run(const SearchState(
        queryText: 'mountain',
        tab: MediaTabType.images,
      ));
      _expectOk(r, 'tab images');
    }, timeout: timeout);

    test('format filter: jpg', () async {
      final r = await _run(const SearchState(
        queryText: 'mountain',
        tab: MediaTabType.images,
        formats: {FileFormat.jpg},
      ));
      _expectOk(r, 'format jpg');
    }, timeout: timeout);

    test('multi-term "+" query', () async {
      final r = await _run(const SearchState(queryText: 'cat + dog'));
      _expectOk(r, 'multi-term +');
    }, timeout: timeout);

    test('title-only search', () async {
      final r = await _run(const SearchState(
        queryText: 'Paris',
        titleOnly: true,
      ));
      _expectOk(r, 'title-only');
    }, timeout: timeout);
  });

  group('categories', () {
    test('category include', () async {
      final r = await _run(const SearchState(categories: {'Cats'}));
      _expectOk(r, 'category include');
    }, timeout: timeout);

    test('deep category mode', () async {
      final r = await _run(const SearchState(
        categories: {'Cats'},
        deepCategoryMode: true,
      ));
      _expectOk(r, 'deep category');
    }, timeout: timeout);

    test('category union (OR)', () async {
      final r = await _run(const SearchState(
        categories: {'Cats', 'Dogs'},
        categoriesUnion: true,
      ));
      _expectOk(r, 'category union');
    }, timeout: timeout);

    test('category exclude still returns results', () async {
      final r = await _run(const SearchState(
        categories: {'Cats'},
        excludeCategories: {'Kittens'},
      ));
      _expectOk(r, 'category exclude');
    }, timeout: timeout);
  });

  group('depicts (P180)', () {
    test('depicts include', () async {
      // Q146 = house cat
      final r = await _run(SearchState(
        depictsInclude: {DepictsEntity(qid: 'Q146', label: 'cat')},
      ));
      _expectOk(r, 'depicts include');
    }, timeout: timeout);

    test('depicts union (OR)', () async {
      final r = await _run(SearchState(
        depictsInclude: {
          DepictsEntity(qid: 'Q146', label: 'cat'),
          DepictsEntity(qid: 'Q144', label: 'dog'),
        },
        depictsUnion: true,
      ));
      _expectOk(r, 'depicts union');
    }, timeout: timeout);
  });

  group('templates', () {
    test('template include', () async {
      final r = await _run(const SearchState(templates: {'PD-USGov'}));
      _expectOk(r, 'template include');
    }, timeout: timeout);
  });

  group('license & quality', () {
    test('quality: Quality images', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        qualityFilter: QualityFilter.qualityImage,
      ));
      _expectOk(r, 'quality image');
    }, timeout: timeout);

    test('quality: Featured pictures', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        qualityFilter: QualityFilter.featuredPicture,
      ));
      _expectOk(r, 'featured picture');
    }, timeout: timeout);
  });

  group('resolution / size / color depth', () {
    test('min width', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        minWidth: 4000,
      ));
      _expectOk(r, 'min width');
    }, timeout: timeout);

    test('min file size', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        minFileSizeBytes: 5 * 1024 * 1024,
      ));
      _expectOk(r, 'min file size');
    }, timeout: timeout);

    test('color depth: 24-bit', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        colorDepthBits: 24,
      ));
      _expectOk(r, 'color depth');
    }, timeout: timeout);
  });

  group('dates', () {
    test('created date range', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        createdDate: DateFilter(from: '2020-01-01', to: '2021-01-01'),
      ));
      _expectOk(r, 'created date range');
    }, timeout: timeout);

    test('edited date range', () async {
      final r = await _run(const SearchState(
        queryText: 'landscape',
        editedDate: DateFilter(from: '2023-01-01'),
      ));
      _expectOk(r, 'edited date range');
    }, timeout: timeout);
  });

  group('geolocation (CirrusSearch nearcoord/neartitle)', () {
    test('nearCoord', () async {
      final r = await _run(const SearchState(
        nearCoord: NearCoordFilter(lat: 48.8584, lng: 2.2945, radiusKm: 5),
      ));
      _expectOk(r, 'nearCoord');
    }, timeout: timeout);

    test('nearTitle', () async {
      final r = await _run(const SearchState(
        nearTitle: NearTitleFilter(title: 'Eiffel Tower', radiusKm: 5),
      ));
      _expectOk(r, 'nearTitle');
    }, timeout: timeout);
  });

  group('text-corpus keywords', () {
    test('insource', () async {
      final r = await _run(const SearchState(
        insourceText: 'Paris',
      ));
      _expectOk(r, 'insource');
    }, timeout: timeout);

    test('exclude term still returns results', () async {
      final r = await _run(const SearchState(
        queryText: 'cat',
        excludeTerms: {'kitten'},
      ));
      _expectOk(r, 'exclude term');
    }, timeout: timeout);

    test('morelike', () async {
      // Resolve a real, currently-existing title first rather than
      // hardcoding one that could get renamed/deleted.
      final seed = await _run(const SearchState(queryText: 'Eiffel Tower'));
      _expectOk(seed, 'morelike seed search');
      final seedTitle = seed.items.first.title;

      final r = await _run(SearchState(morelikeTitles: {seedTitle}));
      _expectOk(r, 'morelike');
    }, timeout: timeout);
  });

  group('geosearch (bypasses CirrusSearch — MediaWiki geosearch index)', () {
    test('radius', () async {
      final r = await _backend.geosearch(
        lat: 48.8584,
        lng: 2.2945,
        radiusMeters: 2000,
      );
      expect(r.error, isNull, reason: 'geosearch radius failed: ${r.error}');
      expect(r.items, isNotEmpty, reason: 'geosearch radius: zero results');
    }, timeout: timeout);

    test('bounding box', () async {
      // Small box around the Eiffel Tower.
      final r = await _backend.geosearch(
        boundingBox: [48.861, 2.290, 48.856, 2.300],
      );
      expect(r.error, isNull, reason: 'geosearch bbox failed: ${r.error}');
      expect(r.items, isNotEmpty, reason: 'geosearch bbox: zero results');
    }, timeout: timeout);
  });

  group('author uploads', () {
    test('authorUploads for a known active uploader', () async {
      final r = await _backend.authorUploads('Jebulon');
      expect(r.error, isNull, reason: 'authorUploads failed: ${r.error}');
      expect(r.items, isNotEmpty, reason: 'authorUploads: zero results');
    }, timeout: timeout);
  });
}
