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
