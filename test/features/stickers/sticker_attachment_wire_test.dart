import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _wire({Object? sticker, bool withSticker = true}) => {
  'id': 'att-1',
  'mime': 'image/webp',
  'size': 1234,
  'mediaType': 'image',
  'width': 512,
  'height': 512,
  if (withSticker) 'sticker': sticker,
};

void main() {
  group('MediaAttachment sticker key', () {
    test('reads sticker.id and ignores unknown keys inside sticker', () {
      final attachment = MediaAttachment.fromJson(
        _wire(sticker: {'id': 'orbit_crew.planet.angry', 'pack': 'x'}),
      );

      expect(attachment.stickerId, 'orbit_crew.planet.angry');
    });

    test('ignores a sticker value of any other shape', () {
      for (final shape in <Object?>[
        'orbit_crew.planet.angry',
        {'id': 7},
        {'custom': true},
        null,
        ['orbit_crew.planet.angry'],
      ]) {
        expect(
          MediaAttachment.fromJson(_wire(sticker: shape)).stickerId,
          isNull,
          reason: '$shape',
        );
      }
      expect(
        MediaAttachment.fromJson(_wire(withSticker: false)).stickerId,
        isNull,
      );
    });

    test('writes sticker at the top level of the attachment object', () {
      final json = MediaAttachment.fromJson(
        _wire(sticker: {'id': 'big_mood.en.yes'}),
      ).toJson();

      expect(json, {
        'id': 'att-1',
        'mime': 'image/webp',
        'size': 1234,
        'mediaType': 'image',
        'width': 512,
        'height': 512,
        'sticker': {'id': 'big_mood.en.yes'},
      });
      expect(
        MediaAttachment.fromJson(_wire(withSticker: false)).toJson(),
        isNot(contains('sticker')),
      );
    });

    test('the sticker id survives a database row round trip', () {
      final row = MediaAttachment.fromJson(
        _wire(sticker: {'id': 'big_mood.de.ja'}),
      ).copyWith(messageId: 'm-1').toMap();

      expect(row['sticker_id'], 'big_mood.de.ja');
      expect(MediaAttachment.fromMap(row).stickerId, 'big_mood.de.ja');
      expect(
        MediaAttachment.fromJson(_wire(withSticker: false)).toMap(),
        isNot(contains('sticker_id')),
      );
    });
  });
}
