import 'package:commonslens/search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchState JSON contract', () {
    test('round-trips every backend filter field', () {
      const property = DepictsEntity(
        qid: 'P1071',
        label: 'location of creation',
        description: 'place where a work was created',
      );
      const value = DepictsEntity(
        qid: 'Q90',
        label: 'Paris',
        description: 'capital of France',
      );
      const depicts = DepictsEntity(
        qid: 'Q146',
        label: 'house cat',
        description: 'domesticated feline',
      );

      final original = SearchState(
        queryText: 'historic architecture',
        tab: MediaTabType.images,
        formats: {FileFormat.jpg, FileFormat.png},
        categories: {'Architecture', 'Paris'},
        deepCategoryMode: true,
        categoriesUnion: true,
        titleOnly: true,
        localOnly: true,
        languageCode: 'en',
        contentModel: 'wikitext',
        createdDate: DateFilter(from: '1900-01-01', to: '1950-01-01'),
        editedDate: DateFilter(from: '2020-01-01', to: '2025-01-01'),
        sortMode: SortMode.newestCreated,
        licensePresets: {LicensePreset.cc0, LicensePreset.ccBy4},
        qualityFilter: QualityFilter.featuredPicture,
        attributionRequired: true,
        minWidth: 800,
        minHeight: 600,
        maxWidth: 8000,
        maxHeight: 6000,
        depictsInclude: {depicts},
        depictsExclude: {
          DepictsEntity(qid: 'Q144', label: 'dog'),
        },
        depictsUnion: true,
        excludeCategories: {'Low quality images'},
        nearCoord: NearCoordFilter(lat: 48.8566, lng: 2.3522, radiusKm: 5),
        nearTitle: NearTitleFilter(title: 'Paris', radiusKm: 10),
        statementsInclude: {
          WikidataStatement(property: property, value: value),
        },
        statementsExclude: {
          WikidataStatement(
            property: DepictsEntity(qid: 'P195', label: 'collection'),
            value: DepictsEntity(qid: 'Q160236', label: 'Louvre'),
          ),
        },
        statementsUnion: true,
        excludeTerms: {'modern'},
        morelikeTitles: {'File:Example.jpg'},
        insourceText: 'monument historique',
        insourceRegex: true,
        minFileSizeBytes: 1024,
        maxFileSizeBytes: 10485760,
        colorDepthBits: 24,
        templates: {'Quality image'},
        excludeTemplates: {'Delete'},
      );

      final restored = SearchState.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
    });

    test('uses safe defaults for missing and unrecognized enum values', () {
      final state = SearchState.fromJson({
        'tab': 'not-a-tab',
        'sortMode': 42,
        'qualityFilter': 'not-a-quality-filter',
        'formats': ['jpg', 'not-a-format'],
        'queryText': 7,
        'deepCategoryMode': 'yes',
        'minWidth': 'wide',
        'nearCoord': {'lat': 'north', 'lng': 12},
        'depictsInclude': [
          {'qid': 146, 'label': true},
        ],
        'statementsInclude': [
          {'property': 'bad', 'value': {}},
        ],
      });

      expect(state.tab, MediaTabType.allMedia);
      expect(state.sortMode, SortMode.relevance);
      expect(state.qualityFilter, QualityFilter.any);
      expect(state.formats, {FileFormat.jpg});
      expect(state.queryText, isEmpty);
      expect(state.deepCategoryMode, isFalse);
      expect(state.minWidth, isNull);
      expect(state.nearCoord, const NearCoordFilter(lat: 0, lng: 12));
      expect(state.depictsInclude, isEmpty);
      expect(state.statementsInclude, isEmpty);
    });

    test('compares complete state by value independent of set order', () {
      const first = SearchState(
        categories: {'Zulu', 'Alpha'},
        formats: {FileFormat.png, FileFormat.jpg},
        createdDate: DateFilter(from: '1900-01-01'),
        nearCoord: NearCoordFilter(lat: 1, lng: 2, radiusKm: 3),
        templates: {'One', 'Two'},
      );
      const second = SearchState(
        categories: {'Alpha', 'Zulu'},
        formats: {FileFormat.jpg, FileFormat.png},
        createdDate: DateFilter(from: '1900-01-01'),
        nearCoord: NearCoordFilter(lat: 1, lng: 2, radiusKm: 3),
        templates: {'Two', 'One'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.copyWith(queryText: 'different'), isNot(second));
    });
  });

  group('SearchItem contract', () {
    test('round-trips metadata and derives media identity helpers', () {
      const original = SearchItem(
        title: 'Example.webm',
        url: 'https://upload.wikimedia.org/example/Example.webm?download=1',
        thumb: 'https://upload.wikimedia.org/example/thumb.jpg',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:Example.webm',
        snippet: 'Example video',
        mime: 'video/webm',
        isSvg: false,
        timestamp: '2026-01-02T03:04:05Z',
        uploader: 'Example user',
        width: 1920,
        height: 1080,
        latitude: 12.5,
        longitude: 77.5,
      );

      final restored = SearchItem.fromJson(original.toJson());

      expect(restored.toJson(), original.toJson());
      expect(restored.extension, 'webm');
      expect(restored.fileTypeLabel, 'WEBM');
      expect(restored.mediaKind, MediaKind.video);
      expect(restored.hasCoordinates, isTrue);
    });

    test('falls back to metadata coordinates when resolved values are absent',
        () {
      const item = SearchItem(
        title: 'Map.jpg',
        url: 'https://upload.wikimedia.org/Map.jpg',
        thumb: 'https://upload.wikimedia.org/thumb/Map.jpg',
        commonsUrl: 'https://commons.wikimedia.org/wiki/File:Map.jpg',
        snippet: '',
        mime: 'image/jpeg',
        isSvg: false,
        gpsLatitude: '51.5007',
        gpsLongitude: '-0.1246',
      );

      expect(item.resolvedLatitude, 51.5007);
      expect(item.resolvedLongitude, -0.1246);
      expect(item.hasCoordinates, isTrue);
    });
  });

  test('SearchSession JSON preserves result and pagination state', () {
    const item = SearchItem(
      title: 'Example.jpg',
      url: 'https://upload.wikimedia.org/Example.jpg',
      thumb: 'https://upload.wikimedia.org/thumb/Example.jpg',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:Example.jpg',
      snippet: 'Example',
      mime: 'image/jpeg',
      isSvg: false,
    );
    const original = SearchSession(
      items: [item],
      continueParams: {'continue': 'next'},
      hasMore: true,
      hasSearched: true,
      loadingMore: true,
      error: 'partial failure',
      scrollOffset: 125.5,
      totalHits: 99,
      suggestion: 'examples',
    );

    expect(
        SearchSession.fromJson(original.toJson()).toJson(), original.toJson());
  });
}
