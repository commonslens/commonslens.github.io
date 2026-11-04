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

  testWidgets('mobile showcase rows always place images before their copy',
      (tester) async {
    await tester.pumpWidget(_host(const Size(390, 844)));

    const featurePairs = [
      ('assets/features_media/glacier_point.jpg', 'DISCOVERY ENGINE'),
      ('assets/features_media/midtown_manhattan.jpg', 'FILTER SYSTEM'),
      ('assets/features_media/iss_aug2005.jpg', 'GEOGRAPHIC CONTEXT'),
      ('assets/features_media/monet_bridge.jpg', 'CONTEXT & RIGHTS'),
      ('assets/features_media/jaws_of_death.jpg', 'COLLECTIONS & EXPORT'),
    ];

    for (final (assetPath, moduleLabel) in featurePairs) {
      final image = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == assetPath,
      );
      final copy = find.text(moduleLabel);

      expect(image, findsOneWidget);
      expect(copy, findsOneWidget);
      expect(
        tester.getTopLeft(image).dy,
        lessThan(tester.getTopLeft(copy).dy),
      );
    }
  });
}
