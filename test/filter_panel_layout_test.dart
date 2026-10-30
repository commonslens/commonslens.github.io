import 'package:commonslens/advanced_filters_drawer.dart';
import 'package:commonslens/backend_providers.dart';
import 'package:commonslens/commons_backend.dart';
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

class _FakeBackend extends CommonsBackend {
  @override
  Future<MediaSearchResult> search(
    SearchState filters, {
    Map<String, dynamic>? continueToken,
  }) async {
    return const MediaSearchResult(
      items: [],
      hasMore: false,
      continueToken: null,
      queryUsed: '',
    );
  }
}

Widget _host({VoidCallback? onLocationSelected}) {
  return ProviderScope(
    overrides: [
      commonsBackendProvider.overrideWithValue(_FakeBackend()),
      commonsAutocompleteProvider.overrideWithValue(_FakeAutocomplete()),
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

void main() {
  testWidgets('docked filter bars fit and autocomplete options stay visible',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

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

    expect(
      find.descendant(
        of: find.byType(Chip),
        matching: find.text('Aurora borealis'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Minimize feature panel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Minimize filter groups'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Expand filter groups'), findsOneWidget);
    expect(find.byTooltip('Expand feature panel'), findsNothing);
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

    await tester.tap(find.byTooltip('Expand feature panel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('LICENSE'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Minimize feature panel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
