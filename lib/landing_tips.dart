import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';

/// One short, discoverable workflow hint shown on the landing page.
class LandingTip {
  const LandingTip({
    required this.id,
    required this.title,
    required this.message,
    required this.guideSection,
    required this.guideLabel,
  });

  factory LandingTip.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Landing tip field "$key" must be a string.');
      }
      return value;
    }

    return LandingTip(
      id: requiredString('id'),
      title: requiredString('title'),
      message: requiredString('message'),
      guideSection: requiredString('guideSection'),
      guideLabel: requiredString('guideLabel'),
    );
  }

  final String id;
  final String title;
  final String message;
  final String guideSection;
  final String guideLabel;
}

/// Loads the bundled tips once and chooses a fresh random entry per landing
/// page initialization.
class LandingTips {
  LandingTips._();

  static const assetPath = 'assets/tips.json';
  static Future<List<LandingTip>>? _loadFuture;

  static Future<List<LandingTip>> load() {
    return _loadFuture ??= _read();
  }

  static LandingTip pickRandom(
    List<LandingTip> tips, {
    Random? random,
  }) {
    if (tips.isEmpty) {
      throw StateError('Cannot choose a landing tip from an empty list.');
    }
    return tips[(random ?? Random()).nextInt(tips.length)];
  }

  static Future<List<LandingTip>> _read() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Landing tips must be a JSON list.');
    }

    return decoded
        .map<LandingTip>((entry) {
          if (entry is! Map) {
            throw const FormatException('Every landing tip must be an object.');
          }
          return LandingTip.fromJson(Map<String, dynamic>.from(entry));
        })
        .where((tip) => tip.id.isNotEmpty)
        .toList(growable: false);
  }
}
