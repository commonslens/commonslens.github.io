import 'dart:math';

import 'package:commonslens/landing_tips.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a tip and preserves its guide destination', () {
    final tip = LandingTip.fromJson({
      'id': 'query-preview',
      'title': 'Tip title',
      'message': 'Tip message',
      'guideSection': 'advanced-filters',
      'guideLabel': 'Read more',
    });

    expect(tip.id, 'query-preview');
    expect(tip.guideSection, 'advanced-filters');
    expect(tip.guideLabel, 'Read more');
  });

  test('chooses an entry from the configured tip list', () {
    const tips = [
      LandingTip(
        id: 'one',
        title: 'One',
        message: 'One',
        guideSection: 'one',
        guideLabel: 'One',
      ),
      LandingTip(
        id: 'two',
        title: 'Two',
        message: 'Two',
        guideSection: 'two',
        guideLabel: 'Two',
      ),
    ];

    final picked = LandingTips.pickRandom(tips, random: Random(1));

    expect(tips, contains(picked));
  });

  test('rejects tips without required copy', () {
    expect(
      () => LandingTip.fromJson({'id': 'incomplete'}),
      throwsA(isA<FormatException>()),
    );
  });
}
