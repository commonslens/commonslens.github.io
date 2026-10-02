@TestOn('browser')
library;

import 'package:commonslens/search_components.dart';
import 'package:commonslens/search_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

SearchItem _item(int index) => SearchItem(
      title: 'File:Result $index.ogg',
      url: 'https://example.test/$index.ogg',
      thumb: '',
      commonsUrl: 'https://commons.wikimedia.org/wiki/File:Result_$index.ogg',
      snippet: '',
      mime: 'audio/ogg',
      isSvg: false,
    );

Widget _host(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
      ),
    );

void main() {
  const delegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    childAspectRatio: 1,
  );

  testWidgets('renders only the configured item limit and loading tail',
      (tester) async {
    final items = List.generate(5, _item);

    await tester.pumpWidget(
      _host(
        MediaResultsGrid(
          items: items,
          itemLimit: 3,
          loadingMore: true,
          searchState: const SearchState(),
          gridDelegate: delegate,
        ),
      ),
    );

    expect(find.byType(MediaCard), findsNWidgets(3));
    expect(find.byKey(const ValueKey('media-results-loading')), findsOneWidget);
  });

  testWidgets('reports when scrolling near the end', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var nearEndCalls = 0;

    await tester.pumpWidget(
      _host(
        MediaResultsGrid(
          controller: controller,
          items: List.generate(30, _item),
          searchState: const SearchState(),
          gridDelegate: delegate,
          nearEndThreshold: 0,
          onNearEnd: () => nearEndCalls++,
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    expect(nearEndCalls, greaterThan(0));
  });
}
