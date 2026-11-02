import 'dart:io';

import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final packsJson = File('assets/stickers/packs.json').readAsStringSync();

  group('StickerCatalog.parse', () {
    test('the bundled pack list has 133 stickers in 3 packs', () {
      final catalog = StickerCatalog.parse(packsJson, includeTestOnly: true);

      expect(catalog.packs.map((pack) => pack.id).toList(), [
        'orbit_crew',
        'big_mood',
        'nujoom',
      ]);
      expect(
        catalog.packs.expand((p) => p.groups).expand((g) => g.stickers).length,
        133,
      );
      expect(catalog.packs.last.status, StickerPackStatus.testOnly);
      expect(catalog.packs.first.status, StickerPackStatus.ship);
      expect(catalog.packs[1].groups.map((g) => g.id).toList(), [
        'en',
        'ar',
        'de',
      ]);
    });

    test('looks a sticker up by id, and returns null for an unknown id', () {
      final catalog = StickerCatalog.parse(packsJson, includeTestOnly: true);

      final entry = catalog.byId('orbit_crew.planet.angry');
      expect(entry?.assetPath, 'assets/stickers/orbit_crew/planet/angry.webp');
      expect(catalog.byId('orbit_crew.planet.nope'), isNull);
    });

    test('every Big Mood sticker except hug carries its printed words', () {
      final catalog = StickerCatalog.parse(packsJson, includeTestOnly: true);
      final bigMood = catalog.packs.singleWhere((p) => p.id == 'big_mood');

      expect(
        {
          for (final sticker in bigMood.groups.expand((g) => g.stickers))
            sticker.id: sticker.printedText,
        },
        {
          'big_mood.en.hi': 'hi.',
          'big_mood.en.hug': null,
          'big_mood.en.huh': 'Huh?',
          'big_mood.en.im_fine': "I'm fine.",
          'big_mood.en.lol': 'LOL',
          'big_mood.en.on_it': 'On it',
          'big_mood.en.thanks': 'Thanks!',
          'big_mood.en.yay': 'Yay!',
          'big_mood.ar.bird': 'يا زلمة!',
          'big_mood.ar.blob': 'اشطا',
          'big_mood.ar.cloud': 'معلش',
          'big_mood.ar.comet': 'مطفي عالآخر',
          'big_mood.ar.teacup': 'روق',
          'big_mood.de.alien': 'Nicht dein Ernst!',
          'big_mood.de.ghost': 'Vermiss dich.',
          'big_mood.de.potato': 'Was geht mich das an?',
          'big_mood.de.gecko': 'Erzähl!',
          'big_mood.de.cactus': 'War nicht so gemeint.',
          'big_mood.de.octopus': 'Eins nach dem anderen!',
          'big_mood.de.moon': 'Bin durch.',
          'big_mood.de.raccoon': "Ich war's nicht!",
        },
      );
      expect(
        catalog.packs
            .where((p) => p.id != 'big_mood')
            .expand((p) => p.groups)
            .expand((g) => g.stickers)
            .where((s) => s.printedText != null),
        isEmpty,
      );
    });

    test('test_only packs are hidden unless the define is set', () {
      final shipped = StickerCatalog.parse(packsJson, includeTestOnly: false);

      expect(shipped.packs.map((pack) => pack.id).toList(), [
        'orbit_crew',
        'big_mood',
      ]);
      expect(
        shipped.packs.expand((p) => p.groups).expand((g) => g.stickers).length,
        101,
      );
      expect(
        shipped.byId('nujoom.arab.${_firstNujoomName(packsJson)}'),
        isNull,
      );
    });

    test('orders packs, groups and stickers by their order field', () {
      const raw = '''
{"version":1,"packs":[
 {"id":"b","order":2,"status":"ship","groups":[
   {"id":"g","order":1,"stickers":[{"id":"b.g.x","order":1,"file":"x.webp"}]}]},
 {"id":"a","order":1,"status":"ship","groups":[
   {"id":"g2","order":2,"stickers":[{"id":"a.g2.z","order":1,"file":"z.webp"}]},
   {"id":"g1","order":1,"stickers":[
     {"id":"a.g1.y","order":2,"file":"y.webp"},
     {"id":"a.g1.w","order":1,"file":"w.webp"}]}]}]}
''';
      final catalog = StickerCatalog.parse(raw, includeTestOnly: false);

      expect(
        catalog.packs
            .expand((p) => p.groups)
            .expand((g) => g.stickers)
            .map((s) => s.id)
            .toList(),
        ['a.g1.w', 'a.g1.y', 'a.g2.z', 'b.g.x'],
      );
    });
  });
}

String _firstNujoomName(String packsJson) {
  final match = RegExp(r'"id": "nujoom\.arab\.([^"]+)"').firstMatch(packsJson);
  return match!.group(1)!;
}
