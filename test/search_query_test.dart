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

  test('format-only and language filters compile to valid media queries', () {
    final formatOnly = service.buildQuery(
      const SearchState(formats: {FileFormat.png}),
    );
    final clientOnly = service.buildQuery(
      const SearchState(attributionRequired: true),
    );
    final captionLanguageOnly = service.buildQuery(
      const SearchState(languageCode: 'fr'),
    );

    expect(formatOnly.srsearch, 'prefix:file:');
    expect(clientOnly.srsearch, 'prefix:file:');
    expect(captionLanguageOnly.srsearch, 'hascaption:fr');
  });

  test('scopes text search to the selected caption language', () {
    final singleWord = service.buildQuery(
      const SearchState(queryText: 'DNA', languageCode: 'fr'),
    );
    final multipleWords = service.buildQuery(
      const SearchState(queryText: 'historic building', languageCode: 'fr'),
    );
    final phrase = service.buildQuery(
      const SearchState(queryText: '"tour Eiffel"', languageCode: 'fr'),
    );
    final titleOnly = service.buildQuery(
      const SearchState(
        queryText: 'DNA',
        languageCode: 'fr',
        titleOnly: true,
      ),
    );

    expect(singleWord.srsearch, 'incaption:DNA@fr');
    expect(
      multipleWords.srsearch,
      'incaption:historic@fr incaption:building@fr',
    );
    expect(phrase.srsearch, 'incaption:"tour Eiffel@fr"');
    expect(titleOnly.srsearch, 'intitle:"DNA" hascaption:fr');
  });

  test('accepts comma-separated caption languages', () {
    final built = service.buildQuery(const SearchState(
      queryText: 'cat',
      languageCode: 'fr, EN, fr',
    ));

    expect(built.srsearch, 'incaption:cat@fr,en');
    expect(
      built.chips.map((chip) => chip.label),
      contains('Caption language: fr,en'),
    );
  });

  test('combines multiple quality types with OR semantics', () {
    final built = service.buildQuery(const SearchState(
      qualityFilters: {
        QualityFilter.qualityImage,
        QualityFilter.featuredPicture,
      },
      allImages: false,
    ));

    expect(
      built.srsearch,
      contains(
        '(hastemplate:"Quality image" OR incategory:"Featured pictures on Wikimedia Commons")',
      ),
    );
    expect(
      built.chips.map((chip) => chip.id),
      containsAll(<String>[
        'quality:qualityImage',
        'quality:featuredPicture',
      ]),
    );
  });

  test('expands a tier-and-above quality selection', () {
    final built = service.buildQuery(const SearchState(
      qualityFilters: {QualityFilter.valuedImage},
      qualityMatchMode: QualityMatchMode.andAbove,
      allImages: false,
    ));

    expect(built.srsearch, contains('hastemplate:"Valued image"'));
    expect(built.srsearch, contains('hastemplate:"Quality image"'));
    expect(built.srsearch,
        contains('incategory:"Featured pictures on Wikimedia Commons"'));
    expect(
      built.chips.map((chip) => chip.label),
      contains('Valued media and above'),
    );
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
      originalDate: DateFilter(from: '1960-01-01', to: '1971-01-01'),
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
      'incaption:historic@fr',
      'incaption:building@fr',
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
      'originalFrom',
      'originalTo',
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
    expect(
      built.chips.map((chip) => chip.label),
      contains('Caption language: fr'),
    );
  });

  test('near-title is used when coordinate search is absent', () {
    final query = service
        .buildQuery(const SearchState(
          nearTitle: NearTitleFilter(title: 'Eiffel Tower', radiusKm: 7),
        ))
        .srsearch;

    expect(query, contains('neartitle:"7km,Eiffel Tower"'));
  });

  test('preserves fractional geolocation radii in queries and chips', () {
    final nearCoord = service.buildQuery(const SearchState(
      nearCoord: NearCoordFilter(
        lat: 48.8583701,
        lng: 2.2944813,
        radiusKm: 0.5,
      ),
    ));
    final nearTitle = service.buildQuery(const SearchState(
      nearTitle: NearTitleFilter(title: 'Eiffel Tower', radiusKm: 0.5),
    ));

    expect(
      nearCoord.srsearch,
      contains('nearcoord:500m,48.8583701,2.2944813'),
    );
    expect(
      nearCoord.chips.map((chip) => chip.label),
      contains('Near 48.858, 2.294 (0.5km)'),
    );
    expect(nearTitle.srsearch, contains('neartitle:"500m,Eiffel Tower"'));
    expect(
      nearTitle.chips.map((chip) => chip.label),
      contains('Near "Eiffel Tower" (0.5km)'),
    );
  });

  test('shared Ogg and WebM containers are searchable in both media tabs', () {
    final audio = service.buildQuery(
      const SearchState(tab: MediaTabType.audio),
      overrideFormat: FileFormat.webm,
    );
    final video = service.buildQuery(
      const SearchState(tab: MediaTabType.video),
      overrideFormat: FileFormat.ogg,
    );

    expect(audio.srsearch, contains('filetype:audio'));
    expect(audio.srsearch, contains('filemime:webm'));
    expect(video.srsearch, contains('filetype:video'));
    expect(video.srsearch, contains('filemime:ogg'));
  });

  test('3D tab compiles to the Commons 3D file type and STL MIME', () {
    final query = service
        .buildQuery(
          const SearchState(tab: MediaTabType.threeD),
          overrideFormat: FileFormat.stl,
        )
        .srsearch;

    expect(query, contains('filetype:3D'));
    expect(query, contains('filemime:"application/sla"'));
  });

  test('supports the expanded Commons license presets', () {
    final query = service
        .buildQuery(const SearchState(
          queryText: 'open media',
          licensePresets: {
            LicensePreset.ccBy1,
            LicensePreset.ccBySa3,
            LicensePreset.gfdl13,
            LicensePreset.freeArt13,
          },
        ))
        .srsearch;

    expect(query, contains('haswbstatement:P275=Q30942811'));
    expect(query, contains('haswbstatement:P275=Q14946043'));
    expect(query, contains('haswbstatement:P275=Q26921691'));
    expect(query, contains('haswbstatement:P275=Q124150926'));
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
