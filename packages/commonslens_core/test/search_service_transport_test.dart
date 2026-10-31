import 'package:commonslens_core/commonslens_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _FixtureTransport implements WikimediaTransport {
  _FixtureTransport(this.handler);

  final Future<http.Response> Function(Uri uri) handler;
  final List<Uri> requests = [];

  @override
  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 20),
    int maxAttempts = 4,
    bool deduplicate = true,
    bool Function()? cancelled,
    bool Function(http.Response response)? acceptResponse,
  }) {
    requests.add(uri);
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
      expect(uri.queryParameters['iiurlwidth'], '320');
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
  });

  test('browse extensions use the same injected transport', () async {
    final transport = _FixtureTransport((uri) async {
      expect(uri.queryParameters['list'], 'allcategories');
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
}
