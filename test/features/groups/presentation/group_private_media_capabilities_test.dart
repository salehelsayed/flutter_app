import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_policy.dart';
import 'package:flutter_app/features/groups/application/group_received_media_action_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

MediaAttachment _attachment({MediaOwnerLane? owner = MediaOwnerLane.group}) {
  return MediaAttachment(
    id: 'attachment-secret',
    messageId: 'message-private',
    mime: 'image/jpeg',
    size: 42,
    mediaType: 'image',
    localPath: '/tmp/SECRET-thumbnail.jpg',
    downloadStatus: 'done',
    createdAt: '2026-07-12T10:00:00.000Z',
    contentHash: _contentHash,
    encryptionKeyBase64: 'SECRET-key',
    encryptionNonce: 'SECRET-nonce',
    encryptionScheme: 'blob_aes_256_gcm_v1',
    ownerLane: owner,
    isBookmarked: true,
    lastPlaybackPositionMs: 12_345,
  );
}

GroupMessage _privateMessage({
  String id = 'message-private',
  GroupPrivateMediaPolicy policy = const GroupPrivateMediaPolicy.viewOnce(),
  int? consumedAt,
  int? expiredAt,
  bool cleanupPending = false,
}) {
  final timestamp = DateTime.utc(2026, 7, 12, 10);
  return GroupMessage(
    id: id,
    groupId: 'group-private',
    senderPeerId: 'peer-sender',
    senderUsername: 'SECRET sender',
    text: 'SECRET caption',
    timestamp: timestamp,
    createdAt: timestamp,
    isIncoming: true,
    privateMediaPolicy: policy,
    mediaReceivedAt: 100,
    mediaConsumedAt: consumedAt,
    mediaExpiredAt: expiredAt,
    mediaCleanupPending: cleanupPending,
  );
}

Widget _app({
  required List<GroupMessage> messages,
  required ValueChanged<String> onOpenPrivateMedia,
  bool privateMediaEnabled = true,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GroupConversationScreen(
      group: GroupModel(
        id: 'group-private',
        name: 'SECRET group',
        type: GroupType.chat,
        topicName: 'SECRET topic',
        createdAt: DateTime.utc(2026, 7, 12),
        createdBy: 'peer-owner',
        myRole: GroupRole.admin,
      ),
      messages: messages,
      ownPeerId: 'peer-self',
      onSend: (_) {},
      onBack: () {},
      canWrite: true,
      initialLoadDone: true,
      privateMediaEnabled: privateMediaEnabled,
      onOpenPrivateMedia: onOpenPrivateMedia,
      mediaMap: const <String, List<MediaAttachment>>{},
      reactions: const <String, List<MessageReaction>>{
        'message-private': <MessageReaction>[],
      },
      onMediaTap: (_, _) {},
      onMediaSave: (_, _) {},
      onMediaShare: (_, _) {},
      onMediaDeleteForMe: (_) {},
      onQuoteReply: (_) {},
      onReactionTap: (_, _) {},
      onReactionSelected: (_, _) {},
    ),
  );
}

void main() {
  test(
    'GPL-09 exact owner-scoped action policies deny every private derivative',
    () {
      for (final policy in <GroupPrivateMediaPolicy>[
        const GroupPrivateMediaPolicy.protected(),
        const GroupPrivateMediaPolicy.viewOnce(),
        GroupPrivateMediaPolicy.disappearing(3600),
        const GroupPrivateMediaPolicy.unsupported(sourceVersion: 9),
      ]) {
        for (final owner in <MediaOwnerLane?>[
          MediaOwnerLane.group,
          MediaOwnerLane.direct,
          null,
        ]) {
          final attachment = _attachment(owner: owner);
          expect(
            GroupReceivedMediaActionPolicy.capabilitiesFor(
              groupType: GroupType.chat,
              isIncoming: true,
              attachment: attachment,
              canWrite: true,
              mediaPolicy: policy,
            ),
            isEmpty,
            reason:
                'private/unsupported policy must deny save, share, info, '
                'delete, and reply for owner=${owner?.dbValue ?? 'unresolved'}',
          );
          expect(
            GroupMediaForwardPolicy.canOfferForward(
              groupType: GroupType.chat,
              isIncoming: true,
              attachment: attachment,
              mediaPolicy: policy,
            ),
            isFalse,
            reason:
                'private/unsupported policy must deny forward for '
                'owner=${owner?.dbValue ?? 'unresolved'}',
          );
        }
      }

      final ordinaryGroup = _attachment();
      expect(
        GroupReceivedMediaActionPolicy.capabilitiesFor(
          groupType: GroupType.chat,
          isIncoming: true,
          attachment: ordinaryGroup,
          canWrite: true,
        ),
        containsAll(<GroupReceivedMediaAction>{
          GroupReceivedMediaAction.save,
          GroupReceivedMediaAction.share,
          GroupReceivedMediaAction.deleteForMe,
          GroupReceivedMediaAction.info,
          GroupReceivedMediaAction.reply,
        }),
        reason: 'the private restriction must not alter ordinary group media',
      );
      expect(
        GroupMediaForwardPolicy.canOfferForward(
          groupType: GroupType.chat,
          isIncoming: true,
          attachment: ordinaryGroup,
        ),
        isTrue,
      );

      for (final untrusted in <MediaOwnerLane?>[MediaOwnerLane.direct, null]) {
        expect(
          GroupReceivedMediaActionPolicy.capabilitiesFor(
            groupType: GroupType.chat,
            isIncoming: true,
            attachment: _attachment(owner: untrusted),
            canWrite: true,
          ),
          isEmpty,
        );
        expect(
          GroupMediaForwardPolicy.canOfferForward(
            groupType: GroupType.chat,
            isIncoming: true,
            attachment: _attachment(owner: untrusted),
          ),
          isFalse,
        );
      }
    },
  );

  testWidgets(
    'GPL-09 active private bubble exposes only the dedicated open path',
    (tester) async {
      final opens = <String>[];
      await tester.pumpWidget(
        _app(
          messages: <GroupMessage>[_privateMessage()],
          onOpenPrivateMedia: opens.add,
        ),
      );
      await tester.pump();

      final row = find.byKey(const ValueKey('grp-msg-message-private'));
      final open = find.byKey(
        const ValueKey('group-private-open-message-private'),
      );
      expect(row, findsOneWidget);
      expect(open, findsOneWidget);
      expect(find.text('New private media'), findsOneWidget);
      expect(find.textContaining('SECRET caption'), findsNothing);
      expect(find.textContaining('SECRET-thumbnail'), findsNothing);
      expect(find.byType(SwipeToQuoteBubble), findsNothing);

      final card = tester.widget<LetterCard>(
        find.descendant(of: row, matching: find.byType(LetterCard)),
      );
      expect(card.media, isEmpty, reason: 'no private thumbnail is built');
      expect(card.reactions, isEmpty);
      expect(card.onMediaTap, isNull);
      expect(card.onMediaLongPress, isNull);
      expect(card.onLongPress, isNull);
      expect(card.onReactionTap, isNull);

      await tester.tap(open);
      await tester.pump();
      expect(opens, <String>['message-private']);
    },
  );

  testWidgets(
    'GPL-09 consumed expired unsupported cleanup and disabled rows stay terminal',
    (tester) async {
      // Plan 260 replaces compact terminal text with full in-bubble visual
      // cards. Give the four-row matrix enough viewport to keep every lazy
      // ListView child mounted while asserting all terminal copies together.
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final opens = <String>[];
      final rows = <GroupMessage>[
        _privateMessage(id: 'consumed', consumedAt: 300),
        _privateMessage(
          id: 'expired',
          policy: GroupPrivateMediaPolicy.disappearing(3600),
          expiredAt: 400,
        ),
        _privateMessage(
          id: 'unsupported',
          policy: const GroupPrivateMediaPolicy.unsupported(sourceVersion: 7),
        ),
        _privateMessage(id: 'cleanup', cleanupPending: true),
      ];
      await tester.pumpWidget(
        _app(messages: rows, onOpenPrivateMedia: opens.add),
      );
      await tester.pump();

      final context = tester.element(find.byType(GroupConversationScreen));
      final l10n = AppLocalizations.of(context)!;
      expect(find.text(l10n.private_media_consumed), findsOneWidget);
      expect(find.text(l10n.private_media_expired), findsOneWidget);
      expect(find.text(l10n.private_media_unsupported), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-private-open-consumed')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('group-private-open-expired')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('group-private-open-unsupported')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('group-private-open-cleanup')),
        findsNothing,
      );
      expect(find.byType(SwipeToQuoteBubble), findsNothing);
      expect(opens, isEmpty);

      await tester.pumpWidget(
        _app(
          messages: <GroupMessage>[_privateMessage()],
          onOpenPrivateMedia: opens.add,
          privateMediaEnabled: false,
        ),
      );
      await tester.pump();
      expect(find.text(l10n.media_unavailable), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-private-open-message-private')),
        findsNothing,
      );
      expect(opens, isEmpty);
    },
  );
}
