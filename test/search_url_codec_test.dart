import 'package:commonslens/search_models.dart';
import 'package:commonslens/search_url_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips the complete shareable filter contract', () {
    final state = SearchState(
      queryText: 'Eiffel Tower',
      tab: MediaTabType.images,
      formats: {FileFormat.jpg, FileFormat.png},
      categories: {'Architecture|historic', 'Paris'},
      excludeCategories: {'Night~photographs'},
      categoriesUnion: true,
      deepCategoryMode: true,
      titleOnly: true,
      localOnly: true,
      languageCode: 'fr',
      contentModel: 'wikitext',
      createdDate: DateFilter(from: '1900-01-01', to: '1950-01-01'),
      editedDate: DateFilter(from: '2020-01-01', to: '2025-01-01'),
      sortMode: SortMode.oldestCreated,
      licensePresets: {LicensePreset.cc0, LicensePreset.ccBy4},
      qualityFilter: QualityFilter.featuredPicture,
      attributionRequired: false,
      minWidth: 1024,
      minHeight: 768,
      maxWidth: 8192,
      maxHeight: 4096,
      minFileSizeBytes: 1024,
      maxFileSizeBytes: 10485760,
      colorDepthBits: 24,
      depictsInclude: {
        DepictsEntity(qid: 'Q146', label: 'cat|feline~domestic'),
      },
      depictsExclude: {DepictsEntity(qid: 'Q144', label: 'dog')},
      depictsUnion: true,
      statementsInclude: {
        WikidataStatement(
          property: DepictsEntity(
            qid: 'P1071',
            label: 'location~of|creation',
          ),
          value: DepictsEntity(qid: 'Q90', label: 'Paris'),
        ),
      },
      statementsExclude: {
        WikidataStatement(
          property: DepictsEntity(qid: 'P195', label: 'collection'),
          value: DepictsEntity(qid: 'Q160236', label: 'Louvre'),
        ),
      },
      statementsUnion: true,
      nearCoord: NearCoordFilter(lat: 48.8584, lng: 2.2945, radiusKm: 5),
      nearTitle: NearTitleFilter(title: 'Eiffel Tower', radiusKm: 8),
      excludeTerms: {'replica|copy'},
      morelikeTitles: {'File:Example|One.jpg'},
      insourceText: 'monument historique',
      insourceRegex: true,
      templates: {'Institution:Example|Museum'},
      excludeTemplates: {'Delete~candidate'},
    );

    final params = SearchUrlCodec.toQueryParams(state);
    final encoded = Uri(queryParameters: params).query;
    final decodedParams = Uri(query: encoded).queryParameters;
    final restored = SearchUrlCodec.fromQueryParams(
      decodedParams,
      const SearchState(),
    );

    expect(restored, state);
    expect(SearchUrlCodec.toQueryParams(restored), params);
  });

  test('decodes legacy singular license links', () {
    final restored = SearchUrlCodec.fromQueryParams(
      {'q': 'example', 'license': 'ccBySa4'},
      const SearchState(),
    );

    expect(restored.queryText, 'example');
    expect(restored.licensePresets, {LicensePreset.ccBySa4});
  });

  test('continues to decode legacy delimiter-based links', () {
    final restored = SearchUrlCodec.fromQueryParams(
      {
        'cats': 'Architecture|Paris',
        'depictsIn': 'Q146~cat|Q144~dog',
        'statementsIn': 'P1071~location of creation~Q90~Paris',
        'exclude': 'replica|modern',
      },
      const SearchState(),
    );

    expect(restored.categories, {'Architecture', 'Paris'});
    expect(
      restored.depictsInclude.map((entity) => entity.qid),
      {'Q146', 'Q144'},
    );
    expect(restored.statementsInclude.single.property.qid, 'P1071');
    expect(restored.statementsInclude.single.value.qid, 'Q90');
    expect(restored.excludeTerms, {'replica', 'modern'});
  });

  test('ignores unknown enum values rather than throwing', () {
    final restored = SearchUrlCodec.fromQueryParams(
      {
        'tab': 'unknown-tab',
        'sort': 'unknown-sort',
        'quality': 'unknown-quality',
        'formats': 'jpg,unknown-format',
      },
      const SearchState(),
    );

    expect(restored.tab, MediaTabType.allMedia);
    expect(restored.sortMode, SortMode.relevance);
    expect(restored.qualityFilter, QualityFilter.any);
    expect(restored.formats, {FileFormat.jpg});
  });

  test('view-only navigation parameters are not search context', () {
    expect(SearchUrlCodec.hasSearchContext({'view': 'map'}), isFalse);
    expect(
      SearchUrlCodec.hasSearchContext({'from': 'map', 'view': 'map'}),
      isFalse,
    );
    expect(
      SearchUrlCodec.hasSearchContext({'q': 'aurora', 'view': 'map'}),
      isTrue,
    );
  });
}
