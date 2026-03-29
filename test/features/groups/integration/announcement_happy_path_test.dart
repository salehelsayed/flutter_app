import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/create_group_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_reaction_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

Widget _buildConversation({
  required GroupModel group,
  required List<GroupMessage> messages,
  required String ownPeerId,
  required bool canWrite,
  ValueChanged<String>? onRetryFailedMedia,
  ValueChanged<String>? onDeleteFailedMedia,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: GroupConversationScreen(
        group: group,
        messages: messages,
        ownPeerId: ownPeerId,
        onSend: (_) {},
        onBack: () {},
        canWrite: canWrite,
        initialLoadDone: true,
        onRetryFailedMedia: onRetryFailedMedia,
        onDeleteFailedMedia: onDeleteFailedMedia,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'announcement happy path: create, admin send, reader read-only receive, member react',
    (tester) async {
      final network = FakeGroupPubSubNetwork();
      final adminBridge = PassthroughCryptoBridge();
      final readerBridge = PassthroughCryptoBridge();

      const groupId = 'group-ann-happy';
      adminBridge.responses['group:create'] = {
        'ok': true,
        'groupId': groupId,
        'topicName': 'topic-$groupId',
        'groupKey': 'group-key-ann-happy',
        'keyEpoch': 0,
      };
      readerBridge.responses['group:publishReaction'] = {'ok': true};

      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
        bridge: adminBridge,
      );
      final reader = GroupTestUser.create(
        peerId: 'peer-reader',
        username: 'Reader',
        network: network,
        bridge: readerBridge,
      );
      addTearDown(() {
        admin.dispose();
        reader.dispose();
      });

      final created = await createGroup(
        bridge: admin.bridge,
        groupRepo: admin.groupRepo,
        name: 'Announcements',
        type: GroupType.announcement,
        creatorPeerId: admin.peerId,
        creatorPublicKey: admin.publicKey,
        creatorMlKemPublicKey: 'mlkem-${admin.peerId}',
      );

      expect(created.type, GroupType.announcement);
      expect(created.myRole, GroupRole.admin);

      network.subscribe(created.id, admin.peerId);
      await admin.addMember(groupId: created.id, invitee: reader);

      final readerGroup = await reader.groupRepo.getGroup(created.id);
      expect(readerGroup, isNotNull);
      expect(readerGroup!.type, GroupType.announcement);
      expect(readerGroup.myRole, GroupRole.member);

      admin.start();
      reader.start();

      final (sendResult, _) = await admin.sendGroupMessageViaBridge(
        groupId: created.id,
        text: 'Announcement one',
      );
      expect(sendResult, SendGroupMessageResult.success);

      await tester.pump(const Duration(milliseconds: 50));

      final readerMessages = await reader.loadGroupMessages(created.id);
      expect(readerMessages, hasLength(1));
      final received = readerMessages.single;
      expect(received.text, 'Announcement one');
      expect(received.isIncoming, isTrue);

      await tester.pumpWidget(
        _buildConversation(
          group: readerGroup,
          messages: readerMessages,
          ownPeerId: reader.peerId,
          canWrite: false,
        ),
      );

      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );
      expect(find.text('Write something...'), findsNothing);

      final failedAdminMedia = GroupMessage(
        id: 'failed-announcement-media',
        groupId: created.id,
        senderPeerId: admin.peerId,
        senderUsername: admin.username,
        text: '',
        timestamp: DateTime.now().toUtc(),
        status: 'failed',
        isIncoming: false,
        createdAt: DateTime.now().toUtc(),
        media: const [
          MediaAttachment(
            id: 'failed-announcement-attachment',
            messageId: 'failed-announcement-media',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: '/tmp/failed-announcement.jpg',
            downloadStatus: 'upload_failed',
            createdAt: '2026-03-29T10:00:00.000Z',
          ),
        ],
      );

      await tester.pumpWidget(
        _buildConversation(
          group: created,
          messages: [failedAdminMedia],
          ownPeerId: admin.peerId,
          canWrite: true,
          onRetryFailedMedia: (_) {},
          onDeleteFailedMedia: (_) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(
          const ValueKey('failed-media-retry-failed-announcement-media'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey('failed-media-delete-failed-announcement-media'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _buildConversation(
          group: readerGroup,
          messages: [failedAdminMedia],
          ownPeerId: reader.peerId,
          canWrite: false,
          onRetryFailedMedia: (_) {},
          onDeleteFailedMedia: (_) {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(
          const ValueKey('failed-media-retry-failed-announcement-media'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey('failed-media-delete-failed-announcement-media'),
        ),
        findsNothing,
      );

      final reactionRepo = FakeReactionRepository();
      final (reactionResult, reaction) = await sendGroupReaction(
        bridge: reader.bridge,
        groupRepo: reader.groupRepo,
        msgRepo: reader.msgRepo,
        reactionRepo: reactionRepo,
        groupId: created.id,
        messageId: received.id,
        emoji: '👍',
        senderPeerId: reader.peerId,
        senderPublicKey: reader.publicKey,
        senderPrivateKey: reader.privateKey,
      );

      expect(reactionResult, SendGroupReactionResult.success);
      expect(reaction, isNotNull);

      final storedReactions = await reactionRepo.getReactionsForMessage(
        received.id,
      );
      expect(storedReactions, hasLength(1));
      expect(storedReactions.single.emoji, '👍');
      expect(storedReactions.single.senderPeerId, reader.peerId);
    },
  );
}
