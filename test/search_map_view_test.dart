@TestOn('browser')
library;

import 'package:commonslens/search_components.dart';
import 'package:commonslens/search_map_view.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _mappedItem = SearchItem(
  title: 'File:Mapped result.jpg',
  url: 'https://example.test/original.jpg',
  thumb: 'https://example.test/thumb.jpg',
  commonsUrl: 'https://commons.wikimedia.org/wiki/File:Mapped_result.jpg',
  snippet: '',
  mime: 'image/jpeg',
  isSvg: false,
  latitude: 48.8584,
  longitude: 2.2945,
);

Widget _host({
  required VoidCallback onShowResults,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 420,
            height: 700,
            child: MapResultsPreview(
              session: const SearchSession(
                items: [_mappedItem],
                hasSearched: true,
              ),
              searchState: const SearchState(),
              onLoadMore: () {},
              onShowResults: onShowResults,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('loaded map results open in a right-hand preview',
      (tester) async {
    var switchedToGrid = false;
    await tester.pumpWidget(
      _host(
        onShowResults: () => switchedToGrid = true,
      ),
    );
    await tester.pump();

    expect(find.byType(MediaCard), findsOneWidget);
    expect(find.text('1 RESULT'), findsOneWidget);
    expect(find.text('Switch to grid'), findsOneWidget);

    await tester.tap(find.text('Switch to grid'));
    await tester.pump();
    expect(switchedToGrid, isTrue);
    expect(tester.takeException(), isNull);
  });
}
