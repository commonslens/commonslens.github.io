import 'package:commonslens_core/commonslens_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FixtureTransport implements WikimediaTransport {
  _FixtureTransport(this.handler);

  final Future<http.Response> Function(Uri uri) handler;
  final List<Uri> requests = [];
  final List<int> requestedMaxAttempts = [];

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
    WikimediaRequestCategory category = WikimediaRequestCategory.other,
  }) {
    requests.add(uri);
    requestedMaxAttempts.add(maxAttempts);
    return handler(uri);
  }
}

void main() {
  test('drains imageinfo continuations into one logical generator page',
      () async {
    final transport = _FixtureTransport((uri) async {
      if (uri.queryParameters.containsKey('iicontinue')) {
        expect(uri.queryParameters['iicontinue'], 'image-page-2');
        return http.Response('''
          {
            "continue": {"gsroffset": 50, "continue": "gsroffset||"},
            "query": {
              "pages": {
                "1": {
                  "title": "File:First.jpg"
                },
                "2": {
                  "title": "File:Second.jpg",
                  "imageinfo": [{
                    "url": "https://upload.wikimedia.org/second.jpg",
                    "mime": "image/jpeg"
                  }]
                }
              }
            }
          }
        ''', 200);
      }

      expect(uri.queryParameters['gsrlimit'], '50');
      expect(uri.queryParameters['iilimit'], '50');
      expect(uri.queryParameters['iiurlwidth'], '330');
      return http.Response('''
        {
          "continue": {
            "iicontinue": "image-page-2",
            "continue": "||info"
          },
          "query": {
            "searchinfo": {"totalhits": 2},
            "pages": {
              "1": {
                "title": "File:First.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/first.jpg",
                  "mime": "image/jpeg"
                }]
              },
              "2": {
                "title": "File:Second.jpg"
              }
            }
          }
        }
      ''', 200);
    });

    final result = await SearchService(transport: transport).fetchPage(
      const SearchState(queryText: 'two files'),
      continueParams: null,
      includeThumbWidth: true,
    );

    expect(result, isNotNull);
    expect(transport.requests, hasLength(2));
    expect(
        result!.items.map((item) => item.title), ['First.jpg', 'Second.jpg']);
    expect(result.continueParams?['gsroffset'], 50);
  });

  test('pipeline ETL profile requests 200-record logical pages', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['gsrlimit'], '200');
      expect(uri.queryParameters['iilimit'], '200');
      expect(uri.queryParameters['iiprop'], isNot(contains('extmetadata')));
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "title": "File:Pipeline.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/pipeline.jpg",
                  "mime": "image/jpeg"
                }]
              }
            }
          }
        }
      ''', 200);
    });

    final result = await SearchService(transport: transport).fetchPage(
      const SearchState(queryText: 'pipeline'),
      continueParams: null,
      requestProfile: SearchRequestProfile.pipelineEtl,
    );

    expect(result, isNotNull);
    expect(result!.items, hasLength(1));
  });

  test('rights-enabled pipeline profile requests Commons extmetadata',
      () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['iiprop'], contains('extmetadata'));
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "title": "File:Rights.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/rights.jpg",
                  "mime": "image/jpeg",
                  "extmetadata": {
                    "Artist": {"value": "Example artist"},
                    "AttributionRequired": {"value": "true"}
                  }
                }]
              }
            }
          }
        }
      ''', 200);
    });

    final result = await SearchService(transport: transport).fetchPage(
      const SearchState(queryText: 'rights'),
      continueParams: null,
      requestProfile: SearchRequestProfile.pipelinePreviewWithRights,
    );

    expect(result!.items.single.artistHtml, 'Example artist');
    expect(result.items.single.attributionRequired, 'true');
  });

  test('pipeline skips one failed 200-record page and continues', () async {
    var calls = 0;
    final transport = _FixtureTransport((uri) async {
      calls++;
      if (calls == 1) return http.Response('temporarily unavailable', 503);

      expect(uri.queryParameters['gsroffset'], '200');
      return http.Response('''
        {
          "query": {
            "pages": {
              "2": {
                "title": "File:AfterFailure.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/after-failure.jpg",
                  "mime": "image/jpeg"
                }]
              }
            }
          }
        }
      ''', 200);
    });
    final backend = CommonsBackend(
      service: SearchService(transport: transport),
    );
    const state = SearchState(queryText: 'pipeline');

    final skipped = await backend.search(
      state,
      requestProfile: SearchRequestProfile.pipelineEtl,
    );
    expect(skipped.ok, isTrue);
    expect(skipped.items, isEmpty);
    expect(skipped.hasMore, isTrue);
    expect(skipped.warning, contains('Skipped the 200-result pipeline batch'));
    expect(transport.requestedMaxAttempts.first, 4);

    final next = await backend.search(
      state,
      continueToken: skipped.continueToken,
      requestProfile: SearchRequestProfile.pipelineEtl,
    );
    expect(next.items.map((item) => item.title), ['AfterFailure.jpg']);
  });

  test('author pagination uses 50 for UI and 200 for pipeline ETL', () async {
    final transport = _FixtureTransport((uri) async {
      if (uri.queryParameters['list'] == 'allimages') {
        expect(
          uri.queryParameters['ailimit'],
          anyOf('50', '200'),
        );
        return http.Response('''
          {
            "query": {
              "allimages": [{
                "name": "Example.jpg",
                "canonicaltitle": "File:Example.jpg",
                "timestamp": "2026-01-01T00:00:00Z"
              }]
            }
          }
        ''', 200);
      }
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "title": "File:Example.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/example.jpg",
                  "mime": "image/jpeg"
                }]
              }
            }
          }
        }
      ''', 200);
    });

    await SearchService(transport: transport).fetchAuthorImages('Example');
    await SearchService(transport: transport).fetchAuthorImages(
      'Example',
      requestProfile: SearchRequestProfile.pipelineEtl,
    );

    final listRequests = transport.requests
        .where((uri) => uri.queryParameters['list'] == 'allimages')
        .toList();
    expect(listRequests.map((uri) => uri.queryParameters['ailimit']),
        ['50', '200']);
  });

  test('geosearch defaults to the 50-row UI/map batch', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['ggslimit'], '50');
      return http.Response('{"query":{"pages":{}}}', 200);
    });

    final result = await SearchService(transport: transport).geosearch(
      lat: 51.5,
      lng: -0.1,
    );

    expect(result, isNotNull);
    expect(result!.items, isEmpty);
  });

  test('filters original media dates from Commons metadata client-side',
      () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['generator'], 'search');
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "title": "File:Elizabeth 1965.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/elizabeth-1965.jpg",
                  "mime": "image/jpeg",
                  "extmetadata": {
                    "DateTimeOriginal": {"value": "1965:05:04 12:00:00"}
                  }
                }]
              },
              "2": {
                "title": "File:Elizabeth 1972.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/elizabeth-1972.jpg",
                  "mime": "image/jpeg",
                  "extmetadata": {
                    "DateTimeOriginal": {"value": "1972-01-01"}
                  }
                }]
              },
              "3": {
                "title": "File:Undated.jpg",
                "imageinfo": [{
                  "url": "https://upload.wikimedia.org/undated.jpg",
                  "mime": "image/jpeg",
                  "extmetadata": {}
                }]
              }
            }
          }
        }
      ''', 200);
    });
    final service = SearchService(transport: transport);

    final result = await service.fetchPage(
        const SearchState(
          queryText: 'queen elizabeth',
          originalDate: DateFilter(from: '1960-01-01', to: '1971-01-01'),
        ),
        continueParams: null);

    expect(result, isNotNull);
    expect(result!.items.map((item) => item.title), ['Elizabeth 1965.jpg']);
  });

  test('headless backend fetches and maps an item through injected transport',
      () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.host, 'commons.wikimedia.org');
      expect(uri.path, '/w/api.php');
      expect(uri.queryParameters['action'], 'query');
      expect(uri.queryParameters['titles'], 'File:Example.jpg');

      return http.Response('''
        {
          "query": {
            "pages": {
              "123": {
                "title": "File:Example.jpg",
                "fullurl": "https://commons.wikimedia.org/wiki/File:Example.jpg",
                "imageinfo": [
                  {
                    "url": "https://upload.wikimedia.org/example.jpg",
                    "thumburl": "https://upload.wikimedia.org/thumb/example.jpg",
                    "mime": "image/jpeg",
                    "width": 1200,
                    "height": 800,
                    "user": "Example user",
                    "extmetadata": {
                      "LicenseShortName": {"value": "CC BY 4.0"}
                    }
                  }
                ]
              }
            }
          }
        }
      ''', 200);
    });
    final backend = CommonsBackend(
      service: SearchService(transport: transport),
    );

    final item = await backend.fetchItem('Example.jpg');

    expect(transport.requests, hasLength(1));
    expect(item, isNotNull);
    expect(item!.title, 'Example.jpg');
    expect(item.width, 1200);
    expect(item.licenseShortName, 'CC BY 4.0');
    expect(item.pageId, 123);
  });

  test('batches Structured Data and preserves the raw MediaInfo entity',
      () async {
    final transport = _FixtureTransport((uri) async {
      if (uri.host == 'commons.wikimedia.org' &&
          uri.queryParameters['action'] == 'wbgetentities') {
        expect(uri.host, 'commons.wikimedia.org');
        expect(uri.queryParameters['ids'], 'M101|M102');
        return http.Response('''
          {
            "entities": {
              "M101": {
                "id": "M101",
                "labels": {"en": {"value": "A caption"}},
                "statements": {
                  "P180": [{
                    "mainsnak": {
                      "snaktype": "value",
                      "datavalue": {
                        "type": "wikibase-entityid",
                        "value": {"id": "Q42"}
                      }
                    },
                    "qualifiers": {"P580": [{"hash": "kept"}]}
                  }]
                }
              },
              "M102": {
                "id": "M102",
                "labels": {},
                "statements": {}
              }
            }
          }
        ''', 200);
      }
      if (uri.host == 'www.wikidata.org') {
        expect(uri.queryParameters['ids'], contains('P180'));
        expect(uri.queryParameters['ids'], contains('Q42'));
        return http.Response('''
          {
            "entities": {
              "P180": {"labels": {"en": {"value": "depicts"}}},
              "Q42": {"labels": {"en": {"value": "Douglas Adams"}}}
            }
          }
        ''', 200);
      }
      fail('Unexpected request: $uri');
    });
    final backend = CommonsBackend(
      service: SearchService(transport: transport),
    );

    final result = await backend.structuredDataBatch(
      ['A.jpg', 'B.jpg'],
      pageIds: {'A.jpg': 101, 'B.jpg': 102},
    );

    expect(result.keys, containsAll(['File:A.jpg', 'File:B.jpg']));
    expect(result['File:A.jpg']!.captions['en'], 'A caption');
    expect(
        result['File:A.jpg']!.statements.single.valueDisplay, 'Douglas Adams');
    expect(result['File:A.jpg']!.raw['statements'], isNotNull);
    expect(result['File:A.jpg']!.raw['statements']['P180'][0]['qualifiers'],
        isNotNull);
    expect(transport.requests, hasLength(2));
  });

  test('batches global usage and retains page metadata', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['prop'], 'globalusage');
      expect(uri.queryParameters['titles'], 'File:A.jpg|File:B.jpg');
      expect(uri.queryParameters['guprop'], 'url|pageid|namespace');
      return http.Response('''
        {
          "query": {
            "pages": {
              "1": {
                "title": "File:A.jpg",
                "globalusage": [{
                  "wiki": "enwiki",
                  "title": "Example",
                  "url": "https://en.wikipedia.org/wiki/Example",
                  "pageid": 44,
                  "ns": 0
                }]
              },
              "2": {"title": "File:B.jpg", "globalusage": []}
            }
          }
        }
      ''', 200);
    });
    final backend = CommonsBackend(
      service: SearchService(transport: transport),
    );

    final result = await backend.globalUsageBatch(['A.jpg', 'B.jpg']);

    expect(result['File:A.jpg']!.single.pageId, 44);
    expect(result['File:A.jpg']!.single.namespace, 0);
    expect(result['File:B.jpg'], isEmpty);
    expect(transport.requests, hasLength(1));
  });

  test('browse extensions use the same injected transport', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['list'], 'allcategories');
      expect(uri.queryParameters['acmin'], isNull);
      return http.Response('''
        {
          "continue": {"accontinue": "Museums"},
          "query": {
            "allcategories": [
              {"*": "Architecture", "size": 42}
            ]
          }
        }
      ''', 200);
    });
    final service = SearchService(transport: transport);

    final result = await service.browseCategories(prefix: 'Arch');

    expect(transport.requests, hasLength(1));
    expect(result.items, [(name: 'Architecture', size: 42)]);
    expect(result.nextCursor, 'Museums');
  });

  test('category tree follows immediate subcategories', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['generator'], 'categorymembers');
      expect(uri.queryParameters['gcmtitle'], 'Category:Topics');
      expect(uri.queryParameters['gcmtype'], 'subcat');
      expect(uri.queryParameters['formatversion'], '2');
      return http.Response('''
        {
          "continue": {"gcmcontinue": "next-child"},
          "query": {
            "pages": [
              {
                "title": "Category:Main topics",
                "categoryinfo": {"files": 12, "subcats": 3}
              }
            ]
          }
        }
      ''', 200);
    });
    final service = SearchService(transport: transport);

    final result = await service.browseCategoryChildren(category: 'Topics');

    expect(result.items, [
      (name: 'Main topics', files: 12, subcategories: 3),
    ]);
    expect(result.nextCursor, 'next-child');
  });

  test('template browse lists actual namespace-10 prefix matches', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['list'], 'allpages');
      expect(uri.queryParameters['apnamespace'], '10');
      expect(uri.queryParameters['apprefix'], 'institution:');
      return http.Response('''
        {
          "continue": {"apcontinue": "Institution:next"},
          "query": {"allpages": [
              {"title": "Template:Institution:art"},
            {"title": "Template:Institution source"},
            {"title": "Template:Institution/doc"}
          ]}
        }
      ''', 200);
    });
    final service = SearchService(transport: transport);

    final result = await service.browseTemplates(prefix: 'institution:');

    expect(result.items, ['Institution:art', 'Institution source']);
    expect(result.nextCursor, 'Institution:next');
  });

  test('deep category search stays on one server-side query', () async {
    final transport = _FixtureTransport((uri) async {
      final categoryQuery = uri.queryParameters['gsrsearch'] ?? '';
      expect(uri.queryParameters['generator'], 'search');
      expect(categoryQuery, contains('deepcat:"Topics"'));
      final title = 'File:Topic.jpg';
      return http.Response('''
        {"warnings":{"search":{"*":"Deep category search timed out"}},
         "query":{"pages":{"1":{"title":"$title","imageinfo":[
            {"url":"https://upload.wikimedia.org/$title","mime":"image/jpeg"}
         ]}}}}
      ''', 200);
    });

    final result = await SearchService(transport: transport).fetchPage(
      const SearchState(categories: {'Topics'}, deepCategoryMode: true),
      continueParams: null,
      includeThumbWidth: false,
    );

    expect(result, isNotNull);
    expect(result!.items, hasLength(1));
    expect(result.warning, contains('timed out'));
  });

  test('template autocomplete uses the same prefix contract', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['list'], 'allpages');
      expect(uri.queryParameters['apnamespace'], '10');
      expect(uri.queryParameters['apprefix'], 'institution:');
      expect(uri.queryParameters['aplimit'], '8');
      return http.Response('''
        {
          "query": {"allpages": [{"title": "Template:Institution:museum"}]}
        }
      ''', 200);
    });
    final service = SearchService(transport: transport);

    final result = await service.searchTemplates('institution:');

    expect(result, ['Institution:museum']);
  });

  test('Wikidata autocomplete surfaces an API error to its caller', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['action'], 'wbsearchentities');
      return http.Response(
        '{"error":{"code":"maxlag","info":"replica lag"}}',
        200,
      );
    });

    expect(
      SearchService(transport: transport).searchDepictsEntities('cat'),
      throwsA(isA<AutocompleteLookupException>()),
    );
  });
}
