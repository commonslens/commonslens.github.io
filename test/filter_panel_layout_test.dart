import 'package:commonslens/advanced_filters_drawer.dart';
import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
import 'package:commonslens/search_page.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAutocomplete extends CommonsAutocomplete {
  @override
  Future<List<DepictsEntity>> wikidataEntities(
    String text, {
    int limit = 8,
  }) async {
    return const [
      DepictsEntity(
        qid: 'Q2',
        label: 'Aurora borealis',
        description: 'Natural light display',
      ),
    ];
  }
}

class _FailingAutocomplete extends CommonsAutocomplete {
  @override
  Future<List<DepictsEntity>> wikidataEntities(
    String text, {
    int limit = 8,
  }) async {
    throw StateError('simulated autocomplete outage');
  }
}

class _FakeBackend extends CommonsBackend {
  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
    bool includeThumbnailUrls = true,
    SearchRequestProfile requestProfile = SearchRequestProfile.ui,
    int? pageSizeOverride,
  }) async {
    return const MediaSearchResult(
      items: [],
      hasMore: false,
      continueToken: null,
      queryUsed: '',
    );
  }
}

Widget _host({
  VoidCallback? onLocationSelected,
  CommonsAutocomplete? autocomplete,
}) {
  return ProviderScope(
    overrides: [
      commonsBackendProvider.overrideWithValue(_FakeBackend()),
      commonsAutocompleteProvider
          .overrideWithValue(autocomplete ?? _FakeAutocomplete()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 600,
            height: 800,
            child: FilterPanelContent(
              docked: true,
              onLocationSelected: onLocationSelected,
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _mobileHost() {
  return ProviderScope(
    overrides: [
      commonsBackendProvider.overrideWithValue(_FakeBackend()),
      commonsAutocompleteProvider.overrideWithValue(_FakeAutocomplete()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 800,
          child: FilterPanelContent(showCloseButton: true),
        ),
      ),
    ),
  );
}

Widget _mobileDrawerHost() {
  return ProviderScope(
    overrides: [
      commonsBackendProvider.overrideWithValue(_FakeBackend()),
      commonsAutocompleteProvider.overrideWithValue(_FakeAutocomplete()),
    ],
    child: MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 800),
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        child: Scaffold(
          drawer: const AdvancedFiltersDrawer(),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'mobile filter drawer selects image classification with a minimized panel',
      (tester) async {
    await tester.pumpWidget(_mobileHost());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand filter groups'), findsNothing);
    expect(find.byTooltip('Close filters'), findsOneWidget);
    expect(find.byTooltip('More Pages'), findsNothing);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('IMAGE CLASSIFICATION'), findsOneWidget);
    expect(find.byTooltip('Expand feature panel'), findsOneWidget);

    await tester.tap(find.text('IMAGE CLASSIFICATION'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Close filters'), findsOneWidget);
    expect(find.byTooltip('Minimize feature panel'), findsNothing);

    final depictsField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. Cat, Eiffel Tower...',
    );
    expect(depictsField, findsOneWidget);
    await tester.enterText(depictsField, 'aurora');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(find.text('Aurora borealis').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('autocomplete failures are visible in the filter field',
      (tester) async {
    await tester.pumpWidget(_host(autocomplete: _FailingAutocomplete()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('IMAGE CLASSIFICATION'));
    await tester.pumpAndSettle();

    final depictsField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. Cat, Eiffel Tower...',
    );
    await tester.enterText(depictsField, 'cat');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(
      find.text(
          'Suggestions unavailable. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('request logger is available from the primary sidebar',
      (tester) async {
    final logger = WikimediaRequestLogger.instance;
    logger.clear();
    logger.record(
      WikimediaRequestCategory.autocomplete,
      Uri.parse('https://www.wikidata.org/w/api.php?action=test'),
      '200',
    );

    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.byTooltip('Wikimedia request log'), findsOneWidget);
    await tester.tap(find.byTooltip('Wikimedia request log'));
    await tester.pumpAndSettle();

    expect(find.text('WIKIMEDIA REQUEST LOG'), findsOneWidget);
    expect(
      find.text('https://www.wikidata.org/w/api.php?action=test 200'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    logger.clear();
  });

  testWidgets('landing request logger remains hit-testable above its content',
      (tester) async {
    final logger = WikimediaRequestLogger.instance;
    logger.clear();
    logger.record(
      WikimediaRequestCategory.search,
      Uri.parse('https://commons.wikimedia.org/w/api.php?action=query'),
      '200',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commonsBackendProvider.overrideWithValue(_FakeBackend()),
          commonsAutocompleteProvider.overrideWithValue(_FakeAutocomplete()),
        ],
        child: const MaterialApp(home: SearchPage()),
      ),
    );
    await tester.pumpAndSettle();

    final loggerButton = find.byTooltip('Wikimedia request log');
    expect(loggerButton, findsOneWidget);
    expect(loggerButton.hitTestable(), findsOneWidget);
    await tester.tap(loggerButton);
    await tester.pumpAndSettle();

    expect(find.text('WIKIMEDIA REQUEST LOG'), findsOneWidget);
    expect(
      find.text('https://commons.wikimedia.org/w/api.php?action=query 200'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    logger.clear();
  });

  testWidgets('mobile Drawer keeps autocomplete options above the keyboard',
      (tester) async {
    await tester.pumpWidget(_mobileDrawerHost());
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('IMAGE CLASSIFICATION'));
    await tester.pumpAndSettle();

    final depictsField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. Cat, Eiffel Tower...',
    );
    await tester.enterText(depictsField, 'aurora');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text('Aurora borealis').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('docked filter bars fit and autocomplete options stay visible',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('MORE PAGES'), findsOneWidget);
    expect(find.text('Visual ETL pipelines'), findsOneWidget);
    expect(find.text('Bookmarks'), findsOneWidget);
    expect(find.text('QUALITY'), findsOneWidget);
    expect(find.byTooltip('Minimize filter groups'), findsOneWidget);
    expect(find.byTooltip('Expand feature panel'), findsOneWidget);
    expect(find.byTooltip('Minimize feature panel'), findsNothing);

    await tester.tap(find.text('IMAGE CLASSIFICATION'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Minimize feature panel'), findsOneWidget);

    final depictsField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == 'e.g. Cat, Eiffel Tower...',
    );
    expect(depictsField, findsOneWidget);

    await tester.enterText(depictsField, 'aurora');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    final suggestion = find.text('Aurora borealis').hitTestable();
    expect(suggestion, findsOneWidget);

    await tester.tap(suggestion);
    await tester.pumpAndSettle();

    expect(find.text('Aurora borealis'), findsOneWidget);

    await tester.tap(find.byTooltip('Minimize feature panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Minimize filter groups'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand filter groups'), findsOneWidget);
    expect(find.byTooltip('Bookmarks'), findsOneWidget);
    expect(find.byTooltip('Expand feature panel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Expand feature panel'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Minimize feature panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('location opens the map and preserves the secondary panel',
      (tester) async {
    var locationSelections = 0;
    await tester.pumpWidget(
      _host(onLocationSelected: () => locationSelections++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('LOCATION'));
    await tester.pumpAndSettle();

    expect(locationSelections, 1);
    expect(find.byTooltip('Minimize feature panel'), findsOneWidget);
    expect(find.textContaining('GEOLOCATION'), findsNothing);

    await tester.tap(find.byTooltip('Minimize feature panel'));
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Expand feature panel'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('LICENSE'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Minimize feature panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quality is a primary sidebar group with multi-select options',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('QUALITY'));
    await tester.pumpAndSettle();

    expect(find.text('QUALITY TYPES'), findsOneWidget);
    expect(find.text('All media'), findsOneWidget);
    expect(find.text('Quality media'), findsOneWidget);
    expect(find.text('Valued media'), findsOneWidget);
    expect(find.text('Featured media'), findsOneWidget);
  });

  testWidgets('license group presents multi-select reuse guidance',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('LICENSE'));
    await tester.pumpAndSettle();

    expect(find.text('LICENSE / RIGHTS'), findsOneWidget);
    expect(
      find.text(
        'Select one or more. Results match any selected license. A file may have more than one license. Open the file in the asset viewer to see all attribution info.',
      ),
      findsOneWidget,
    );
    expect(find.text('CC0'), findsOneWidget);
    expect(
      find.text('Copy, adapt and use commercially; no credit required by CC0.'),
      findsOneWidget,
    );

    await tester.tap(find.text('CC0'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
