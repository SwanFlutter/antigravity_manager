// Keeps every language file in sync with the English source of truth.

import 'package:antigravity_manager/I18n/en.dart';
import 'package:antigravity_manager/I18n/fa.dart';
import 'package:antigravity_manager/I18n/ar.dart';
import 'package:antigravity_manager/I18n/de.dart';
import 'package:antigravity_manager/I18n/fr.dart';
import 'package:antigravity_manager/I18n/zh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final reference = English().keys;

  void expectSameKeys(Map<String, String> translation, String name) {
    expect(
      translation.keys.toSet(),
      reference.keys.toSet(),
      reason: '$name has a different set of keys than English',
    );

    for (final entry in translation.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: '$name has an empty value for "${entry.key}"',
      );
    }
  }

  test('Persian matches English', () => expectSameKeys(Farsi().keys, 'fa'));
  test('Arabic matches English', () => expectSameKeys(Arabic().keys, 'ar'));
  test('German matches English', () => expectSameKeys(German().keys, 'de'));
  test('French matches English', () => expectSameKeys(French().keys, 'fr'));
  test('Chinese matches English', () => expectSameKeys(Chinese().keys, 'zh'));

  test('placeholders survive translation', () {
    const tokens = ['{n}', '{t}', '{m}'];
    final maps = <String, Map<String, String>>{
      'fa': Farsi().keys,
      'ar': Arabic().keys,
      'de': German().keys,
      'fr': French().keys,
      'zh': Chinese().keys,
    };

    for (final entry in maps.entries) {
      for (final token in tokens) {
        final englishHas = reference.values.any((v) => v.contains(token));
        if (!englishHas) continue;
        final translatedHas =
            entry.value.values.any((v) => v.contains(token));
        expect(
          translatedHas,
          isTrue,
          reason: '${entry.key} dropped the $token placeholder',
        );
      }
    }
  });
}
