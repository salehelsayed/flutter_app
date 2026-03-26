import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

Widget _buildReaderConversation({
  required GroupModel group,
  required List<GroupMessage> messages,
  required String ownPeerId,
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
        canWrite: false,
        initialLoadDone: true,
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
        _buildReaderConversation(
          group: readerGroup,
          messages: readerMessages,
          ownPeerId: reader.peerId,
        ),
      );

      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );
      expect(find.text('Write something...'), findsNothing);

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
