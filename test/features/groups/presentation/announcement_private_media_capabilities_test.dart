import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _attachment() => MediaAttachment(
  id: 'announcement-private-attachment',
  messageId: 'announcement-private-message',
  mime: 'image/jpeg',
  size: 42,
  mediaType: 'image',
  localPath: '/tmp/SECRET-announcement-thumbnail.jpg',
  downloadStatus: 'done',
  createdAt: '2026-07-12T10:00:00.000Z',
  contentHash: _contentHash,
  encryptionKeyBase64: 'SECRET-key',
  encryptionNonce: 'SECRET-nonce',
  encryptionScheme: 'blob_aes_256_gcm_v1',
  ownerLane: MediaOwnerLane.group,
  isBookmarked: true,
  lastPlaybackPositionMs: 12345,
);

GroupModel _announcement({GroupRole role = GroupRole.member}) => GroupModel(
  id: 'announcement-private',
  name: 'SECRET announcement',
  type: GroupType.announcement,
  topicName: 'SECRET topic',
  createdAt: DateTime.utc(2026, 7, 12),
  createdBy: 'announcement-admin',
  myRole: role,
);

GroupMessage _message({
  GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.viewOnce(),
  int? consumedAt,
  int? expiredAt,
}) => GroupMessage(
  id: 'announcement-private-message',
  groupId: 'announcement-private',
  senderPeerId: 'announcement-admin',
  senderUsername: 'SECRET admin',
  text: 'SECRET announcement caption',
  timestamp: DateTime.utc(2026, 7, 12, 10),
  createdAt: DateTime.utc(2026, 7, 12, 10),
  isIncoming: true,
  privateMediaPolicy: policy,
  mediaReceivedAt: 100,
  mediaConsumedAt: consumedAt,
  mediaExpiredAt: expiredAt,
);

void main() {
  test(
    'APL-04 announcement actions and Forward fail closed for every private policy',
    () {
      final attachment = _attachment();
      for (final policy in <GroupPrivateMediaPolicy>[
        const GroupPrivateMediaPolicy.protected(),
        const GroupPrivateMediaPolicy.viewOnce(),
        GroupPrivateMediaPolicy.disappearing(3600),
        const GroupPrivateMediaPolicy.unsupported(sourceVersion: 9),
      ]) {
        expect(
          GroupReceivedMediaActionPolicy.capabilitiesFor(
            groupType: GroupType.announcement,
            isIncoming: true,
            attachment: attachment,
            canWrite: true,
            mediaPolicy: policy,
          ),
          isEmpty,
          reason: '$policy',
        );
        expect(
          GroupMediaForwardPolicy.canOfferForward(
            groupType: GroupType.announcement,
            isIncoming: true,
            attachment: attachment,
            mediaPolicy: policy,
          ),
          isFalse,
          reason: '$policy',
        );
      }
    },
  );

  testWidgets(
    'APL-04 reader sees one generic open path without compose thumbnail reactions or egress',
    (tester) async {
      final opens = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationScreen(
            group: _announcement(),
            messages: <GroupMessage>[_message()],
            ownPeerId: 'announcement-reader',
            onSend: (_) {},
            onBack: () {},
            canWrite: false,
            initialLoadDone: true,
            privateMediaEnabled: true,
            onOpenPrivateMedia: opens.add,
            mediaMap: <String, List<MediaAttachment>>{
              'announcement-private-message': <MediaAttachment>[_attachment()],
            },
            onMediaTap: (_, _) {},
            onMediaSave: (_, _) {},
            onMediaShare: (_, _) {},
            onMediaInfo: (_, _) async {},
            onMediaDeleteForMe: (_) {},
            onQuoteReply: (_) {},
            onReactionTap: (_, _) {},
            onReactionSelected: (_, _) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('New private media'), findsOneWidget);
      expect(find.text('SECRET announcement caption'), findsNothing);
      expect(
        find.textContaining('SECRET-announcement-thumbnail'),
        findsNothing,
      );
      expect(find.byType(MediaGridCell), findsNothing);
      expect(
        find.byKey(const ValueKey('group-private-media-selector')),
        findsNothing,
      );
      final open = find.byKey(
        const ValueKey('group-private-open-announcement-private-message'),
      );
      expect(open, findsOneWidget);
      await tester.tap(open);
      await tester.pump();
      expect(opens, <String>['announcement-private-message']);
    },
  );

  testWidgets(
    'APL-10 ordinary announcement media remains visible and read only',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationScreen(
            group: _announcement(),
            messages: <GroupMessage>[
              _message(policy: const GroupPrivateMediaPolicy.ordinary()),
            ],
            ownPeerId: 'announcement-reader',
            onSend: (_) {},
            onBack: () {},
            canWrite: false,
            initialLoadDone: true,
            mediaMap: <String, List<MediaAttachment>>{
              'announcement-private-message': <MediaAttachment>[_attachment()],
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('SECRET announcement caption'), findsOneWidget);
      expect(find.byType(MediaGridCell), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('group-private-open-announcement-private-message'),
        ),
        findsNothing,
      );
    },
  );
}
