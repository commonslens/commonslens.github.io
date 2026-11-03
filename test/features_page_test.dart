import 'package:commonslens/features_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Size size) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: const FeaturesPage(),
    ),
  );
}

void main() {
  testWidgets('mobile features page hides pipeline entry points',
      (tester) async {
    await tester.pumpWidget(_host(const Size(390, 844)));

    expect(find.text('Build a pipeline'), findsNothing);
    expect(find.text('BUILD WORKFLOWS'), findsNothing);
    expect(find.text('Build a visual pipeline'), findsNothing);
  });

  testWidgets('wide features page keeps pipeline entry points', (tester) async {
    await tester.pumpWidget(_host(const Size(1200, 900)));

    expect(find.text('Build a pipeline'), findsOneWidget);
    expect(find.text('BUILD WORKFLOWS'), findsOneWidget);
    expect(find.text('Build a visual pipeline'), findsOneWidget);
  });
}
