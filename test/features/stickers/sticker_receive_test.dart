import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_preview_text.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_media_preview_label.dart';
import 'package:flutter_app/l10n/app_localizations_ar.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../shared/fixtures/media_repository_real_db_fixture.dart';

const _bodyKey = ValueKey('letter-body');

Map<String, dynamic> _incomingWire({String id = 'att-1', Object? sticker}) => {
  'id': id,
  'mime': 'image/webp',
  'size': 70000,
  'mediaType': 'image',
  'width': 512,
  'height': 512,
  'sticker': ?sticker,
};

Future<void> _pumpCard(WidgetTester tester, List<MediaAttachment> media) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: LetterCard(
          senderPeerId: 'peer-a',
          senderName: 'Alice',
          text: '',
          time: '10:00',
          isIncoming: true,
          media: media,
          bubbleLayout: true,
          decoratedBodyKey: _bodyKey,
        ),
      ),
    ),
  );
}

void _expectRendersAsSticker(WidgetTester tester, String label) {
  expect(find.bySemanticsLabel(label), findsOneWidget);
  expect(find.byType(MediaGrid), findsNothing);
  final body = tester.widget<Container>(find.byKey(_bodyKey));
  expect(body.decoration, isNull, reason: 'a sticker draws no bubble');
  expect(
    tester.getSize(find.bySemanticsLabel(label)).width,
    kStickerMessageWidth,
  );
}

void main() {
  late MediaRepositoryRealDbFixture fixture;

  setUp(() async => fixture = await MediaRepositoryRealDbFixture.create());
  tearDown(() => fixture.dispose());

  Future<List<MediaAttachment>> roundTrip(
    MediaAttachment incoming,
    MediaOwnerLane owner,
  ) async {
    await fixture.repo.saveAttachment(incoming, owner: owner);
    return fixture.repo.getAttachmentsForMessage(
      incoming.messageId,
      owner: owner,
    );
  }

  testWidgets('an incoming 1:1 sticker renders as a sticker after a reload '
      'from the database', (tester) async {
    final incoming = MediaAttachment.fromJson(
      _incomingWire(sticker: {'id': 'orbit_crew.planet.angry'}),
    ).copyWith(messageId: 'msg-1');

    await _pumpCard(tester, [incoming]);
    _expectRendersAsSticker(tester, 'Planet sticker');

    final reloaded = (await tester.runAsync(
      () => roundTrip(incoming, MediaOwnerLane.direct),
    ))!;
    expect(reloaded.single.stickerId, 'orbit_crew.planet.angry');
    await _pumpCard(tester, reloaded);
    _expectRendersAsSticker(tester, 'Planet sticker');
  });

  testWidgets('an incoming group sticker renders as a sticker after a reload '
      'from the database', (tester) async {
    final incoming = GroupMediaMimePolicy.sanitizeWireAttachment(
      _incomingWire(sticker: {'id': 'big_mood.de.ja', 'extra': true}),
      messageId: 'group-msg-1',
    );

    final reloaded = (await tester.runAsync(
      () => roundTrip(incoming, MediaOwnerLane.group),
    ))!;
    expect(reloaded.single.stickerId, 'big_mood.de.ja');
    await _pumpCard(tester, reloaded);
    _expectRendersAsSticker(tester, 'German sticker');
  });

  testWidgets('an unknown sticker id still renders as a sticker', (
    tester,
  ) async {
    final incoming = MediaAttachment.fromJson(
      _incomingWire(sticker: {'id': 'future_pack.cats.wave'}),
    ).copyWith(messageId: 'msg-2');

    await _pumpCard(tester, [incoming]);
    _expectRendersAsSticker(tester, 'Sticker');
  });

  testWidgets('a photo without the sticker key renders as a normal photo', (
    tester,
  ) async {
    final incoming = MediaAttachment.fromJson(
      _incomingWire(),
    ).copyWith(messageId: 'msg-3');

    await _pumpCard(tester, [incoming]);
    expect(find.byType(MediaGrid), findsOneWidget);
    expect(find.bySemanticsLabel('Sticker'), findsNothing);
    final body = tester.widget<Container>(find.byKey(_bodyKey));
    expect(body.decoration, isNotNull);
  });

  test('a protected group media commitment with a sticker key is refused, '
      'as builds 127 to 129 refuse it', () {
    final manifest = ProtectedGroupMediaManifest(
      groupId: 'group-1',
      messageId: 'msg-strict',
      attachments: [
        ProtectedGroupMediaAttachmentCommitment(
          attachmentId: 'att-strict',
          custodyBlobId: 'blob-strict',
          ciphertextSha256: 'a' * 64,
          ciphertextSize: 70016,
          mime: 'image/webp',
          mediaType: 'image',
          width: 512,
          height: 512,
          encryptionKeyBase64: 'key',
          encryptionNonce: 'nonce',
          targets: [
            GroupMediaBlobTargetCommitment(
              recipientPeerId: 'peer-b',
              expiresAtMs: 2000000000000,
            ),
          ],
        ),
      ],
    );
    final plain = manifest.toJson();
    expect(
      ProtectedGroupMediaManifest.fromJson(plain).attachments.single.mime,
      'image/webp',
    );
    final withSticker = <String, Object?>{
      ...plain,
      'attachments': [
        <String, Object?>{
          ...(plain['attachments']! as List).single as Map<String, Object?>,
          'sticker': {'id': 'orbit_crew.tux.approved'},
        },
      ],
    };

    expect(
      () => ProtectedGroupMediaManifest.fromJson(withSticker),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'non-canonical group-media fields',
        ),
      ),
    );
  });

  test('the chat list preview and the reply quote say Sticker', () {
    final sticker = MediaAttachment.fromJson(
      _incomingWire(sticker: {'id': 'orbit_crew.planet.angry'}),
    );
    final photo = MediaAttachment.fromJson(_incomingWire());

    expect(
      orbitMediaPreviewLabel(
        l10n: AppLocalizationsEn(),
        media: MediaPreviewDescriptor.fromAttachments([sticker]),
      ),
      'Sticker',
    );
    expect(
      orbitMediaPreviewLabel(
        l10n: AppLocalizationsAr(),
        media: MediaPreviewDescriptor.fromAttachments([sticker]),
      ),
      'ملصق',
    );
    expect(
      orbitMediaPreviewLabel(
        l10n: AppLocalizationsEn(),
        media: MediaPreviewDescriptor.fromAttachments([photo]),
      ),
      'Photo',
    );
    expect(
      mediaPreviewText([
        sticker,
      ], stickerLabel: AppLocalizationsAr().sticker_preview),
      'ملصق',
    );
    expect(mediaPreviewText([photo]), 'Photo');
  });
}
