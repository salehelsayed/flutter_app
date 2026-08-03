import 'dart:ui';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_test/flutter_test.dart';

MediaAttachment _attachment(
  String mediaType, {
  MediaOwnerLane? owner = MediaOwnerLane.group,
  String mime = 'application/octet-stream',
}) => MediaAttachment(
  id: 'attachment-$mediaType-${owner?.name ?? 'unresolved'}-$mime',
  messageId: 'target-message',
  mime: mime,
  size: 1,
  mediaType: mediaType,
  downloadStatus: 'done',
  createdAt: '2026-08-02T00:00:00.000Z',
  ownerLane: owner,
);

void main() {
  group('group reaction notification semantic copy', () {
    test('maps only group-owned target media to a semantic noun', () {
      expect(
        groupReactionTargetKindForAttachments(const []),
        GroupReactionTargetKind.message,
      );
      expect(
        groupReactionTargetKindForAttachments([_attachment('image')]),
        GroupReactionTargetKind.photo,
      );
      expect(
        groupReactionTargetKindForAttachments([_attachment('video')]),
        GroupReactionTargetKind.video,
      );
      expect(
        groupReactionTargetKindForAttachments([_attachment('audio')]),
        GroupReactionTargetKind.voiceMessage,
      );
      expect(
        groupReactionTargetKindForAttachments([_attachment('file')]),
        GroupReactionTargetKind.file,
      );
      expect(
        groupReactionTargetKindForAttachments([_attachment('sticker')]),
        GroupReactionTargetKind.media,
      );
      expect(
        groupReactionTargetKindForAttachments([
          _attachment('image'),
          _attachment('video'),
        ]),
        GroupReactionTargetKind.media,
      );
    });

    test('ignores direct and unresolved rows even when ids collide', () {
      final kind = groupReactionTargetKindForAttachments([
        _attachment(
          'video',
          owner: MediaOwnerLane.direct,
          mime: 'secret/direct-video',
        ),
        _attachment('audio', owner: null, mime: 'secret/unresolved-audio'),
        _attachment('image', mime: 'image/jpeg'),
      ]);

      expect(kind, GroupReactionTargetKind.photo);
    });

    test(
      'never includes target text, reaction emoji, or attachment metadata',
      () {
        const targetText = 'TOP SECRET target text \u202e';
        const reactionEmoji = '👍';
        final body = localizedGroupReactionNotificationBody(
          actorName: 'Alice',
          targetAttachments: [
            _attachment(
              'video',
              owner: MediaOwnerLane.direct,
              mime: 'TOP SECRET direct mime',
            ),
            _attachment('audio', mime: 'audio/voice-secret'),
          ],
        );

        expect(body, 'Alice reacted to your voice message');
        expect(body, isNot(contains(targetText)));
        expect(body, isNot(contains(reactionEmoji)));
        expect(body, isNot(contains('TOP SECRET')));
        expect(body, isNot(contains('voice-secret')));
      },
    );

    test('uses someone copy when the canonical actor name is blank', () {
      expect(
        localizedGroupReactionNotificationBody(
          actorName: '  ',
          targetAttachments: [_attachment('image')],
        ),
        'Someone reacted to your photo',
      );
    });

    test('renders an already-derived recipient-owned target kind', () {
      expect(
        localizedGroupReactionNotificationBodyForTargetKind(
          actorName: 'Alice',
          targetKind: GroupReactionTargetKind.video,
        ),
        'Alice reacted to your video',
      );
    });

    test('localizes every semantic noun without a widget context', () {
      final inputs = <GroupReactionTargetKind, List<MediaAttachment>>{
        GroupReactionTargetKind.message: const [],
        GroupReactionTargetKind.photo: [_attachment('image')],
        GroupReactionTargetKind.video: [_attachment('video')],
        GroupReactionTargetKind.voiceMessage: [_attachment('audio')],
        GroupReactionTargetKind.file: [_attachment('file')],
        GroupReactionTargetKind.media: [
          _attachment('image'),
          _attachment('video'),
        ],
      };

      for (final entry in inputs.entries) {
        final german = localizedGroupReactionNotificationBody(
          actorName: 'Alice',
          targetAttachments: entry.value,
          locale: const Locale('de'),
        );
        final arabic = localizedGroupReactionNotificationBody(
          actorName: 'Alice',
          targetAttachments: entry.value,
          locale: const Locale('ar'),
        );
        expect(german, isNot(contains('reacted to your')));
        expect(arabic, isNot(contains('reacted to your')));
        expect(german, isNot(contains('👍')));
        expect(arabic, isNot(contains('👍')));
      }
    });
  });
}
