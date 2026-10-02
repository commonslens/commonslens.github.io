import 'package:commonslens/search_models.dart';
import 'package:commonslens/search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = SearchService();

  test('empty state compiles to no backend query', () {
    final built = service.buildQuery(const SearchState());

    expect(built.srsearch, isEmpty);
    expect(built.debugPreview, isEmpty);
    expect(built.chips.map((chip) => chip.id), contains('tab'));
  });

  test('compiles the complete filter surface into clauses and chips', () {
    final state = SearchState(
      queryText: 'historic building',
      tab: MediaTabType.images,
      formats: {FileFormat.jpg},
      categories: {'Architecture', 'Paris'},
      categoriesUnion: true,
      excludeCategories: {'Modern architecture'},
      titleOnly: true,
      localOnly: true,
      languageCode: 'fr',
      contentModel: 'wikitext',
      createdDate: DateFilter(from: '1900-01-01', to: '1950-01-01'),
      editedDate: DateFilter(from: '2020-01-01', to: '2025-01-01'),
      licensePresets: {LicensePreset.cc0},
      qualityFilter: QualityFilter.qualityImage,
      attributionRequired: true,
      minWidth: 800,
      minHeight: 600,
      maxWidth: 8000,
      maxHeight: 6000,
      minFileSizeBytes: 1024,
      maxFileSizeBytes: 10485760,
      colorDepthBits: 24,
      templates: {'Quality image'},
      excludeTemplates: {'Delete'},
      depictsInclude: {
        DepictsEntity(qid: 'Q146', label: 'cat'),
        DepictsEntity(qid: 'Q144', label: 'dog'),
      },
      depictsExclude: {
        DepictsEntity(qid: 'Q7377', label: 'mammal'),
      },
      depictsUnion: true,
      statementsInclude: {
        WikidataStatement(
          property: DepictsEntity(qid: 'P1071', label: 'location of creation'),
          value: DepictsEntity(qid: 'Q90', label: 'Paris'),
        ),
      },
      statementsExclude: {
        WikidataStatement(
          property: DepictsEntity(qid: 'P195', label: 'collection'),
          value: DepictsEntity(qid: 'Q160236', label: 'Louvre'),
        ),
      },
      excludeTerms: {'modern building'},
      morelikeTitles: {'Example.jpg'},
      insourceText: 'monument.*historique',
      insourceRegex: true,
      nearCoord: NearCoordFilter(lat: 48.8566, lng: 2.3522, radiusKm: 5),
    );

    final built = service.buildQuery(state, overrideFormat: FileFormat.jpg);
    final query = built.srsearch;
    final chipIds = built.chips.map((chip) => chip.id).toSet();

    for (final clause in [
      'local:',
      'intitle:"historic building"',
      'filetype:bitmap',
      'filemime:"image/jpeg"',
      'incategory:"Architecture" OR incategory:"Paris"',
      '-incategory:"Modern architecture"',
      'inlanguage:fr',
      'contentmodel:wikitext',
      'creationdate:>=1900-01-01',
      'creationdate:<1950-01-01',
      'lasteditdate:>=2020-01-01',
      'lasteditdate:<2025-01-01',
      'haswbstatement:P275=Q6938433',
      'hastemplate:"Quality image"',
      'filew:>800',
      'fileh:>600',
      'filew:<8000',
      'fileh:<6000',
      'filesize:>1024',
      'filesize:<10485760',
      'filebits:24',
      '-hastemplate:Delete',
      'haswbstatement:P180=Q144 OR haswbstatement:P180=Q146',
      '-haswbstatement:P180=Q7377',
      'haswbstatement:P1071=Q90',
      '-haswbstatement:P195=Q160236',
      'nearcoord:5km,48.8566,2.3522',
      '-"modern building"',
      'morelike:File:Example.jpg',
      'insource:/monument.*historique/',
    ]) {
      expect(query, contains(clause), reason: 'Missing query clause: $clause');
    }

    for (final chipId in [
      'localOnly',
      'titleOnly',
      'format:jpg',
      'category:Architecture',
      'excludeCategory:Modern architecture',
      'language',
      'contentModel',
      'createdFrom',
      'editedTo',
      'license:cc0',
      'quality',
      'attributionRequired',
      'minWidth',
      'maxFileSize',
      'colorDepth',
      'template:Quality image',
      'excludeTemplate:Delete',
      'depicts:Q146',
      'statement:P1071:Q90',
      'nearCoord',
      'exclude:modern building',
      'morelike',
      'insource',
    ]) {
      expect(chipIds, contains(chipId), reason: 'Missing chip: $chipId');
    }
  });

  test('near-title is used when coordinate search is absent', () {
    final query = service
        .buildQuery(const SearchState(
          nearTitle: NearTitleFilter(title: 'Eiffel Tower', radiusKm: 7),
        ))
        .srsearch;

    expect(query, contains('neartitle:"7km,Eiffel Tower"'));
  });

  test('set-backed clauses compile in a stable order', () {
    const first = SearchState(
      categories: {'Zulu', 'Alpha'},
      formats: {FileFormat.png, FileFormat.jpg},
      excludeTerms: {'zebra', 'apple'},
    );
    const second = SearchState(
      categories: {'Alpha', 'Zulu'},
      formats: {FileFormat.jpg, FileFormat.png},
      excludeTerms: {'apple', 'zebra'},
    );

    expect(service.buildQuery(first).srsearch,
        service.buildQuery(second).srsearch);
  });

  test('cache signatures cover every backend-only filter and set order', () {
    const first = SearchState(
      categories: {'Zulu', 'Alpha'},
      templates: {'Two', 'One'},
    );
    const reordered = SearchState(
      categories: {'Alpha', 'Zulu'},
      templates: {'One', 'Two'},
    );

    expect(
      service.buildQuerySignature(first),
      service.buildQuerySignature(reordered),
    );

    final baseline = service.buildQuerySignature(const SearchState());
    final states = [
      const SearchState(morelikeTitles: {'File:Example.jpg'}),
      const SearchState(insourceText: 'literal source'),
      const SearchState(insourceRegex: true),
      const SearchState(maxWidth: 4000),
      const SearchState(maxHeight: 3000),
      const SearchState(minFileSizeBytes: 1024),
      const SearchState(maxFileSizeBytes: 2048),
      const SearchState(colorDepthBits: 24),
      const SearchState(templates: {'Quality image'}),
      const SearchState(excludeTemplates: {'Delete'}),
    ];

    for (final state in states) {
      expect(service.buildQuerySignature(state), isNot(baseline));
    }
  });
}
