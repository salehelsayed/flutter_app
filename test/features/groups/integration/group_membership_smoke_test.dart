import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart'
    as group_dissolve;
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    int maxTicks = 20,
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      if (await condition()) return;
      await pump();
    }
  }

  Map<String, dynamic> decodeReplayPayload(Map<String, dynamic> inboxPayload) {
    final envelope =
        jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
    final ciphertext = envelope['ciphertext'];
    if (envelope['kind'] == 'group_offline_replay' && ciphertext is String) {
      return jsonDecode(ciphertext) as Map<String, dynamic>;
    }
    return envelope;
  }

  _GroupMembershipCursorBridge cursorBridge() {
    return _GroupMembershipCursorBridge();
  }

  GroupInviteMembershipFreshnessProof makeFreshnessProof({
    required String inviteId,
    required String groupId,
    required String recipientPeerId,
    required String inviterPeerId,
    required String inviterUsername,
    required String inviterPublicKey,
    required Map<String, dynamic> groupConfig,
    required int keyEpoch,
    required DateTime issuedAt,
  }) {
    final stateHash = buildGroupConfigStateHash(
      groupId: groupId,
      groupConfig: groupConfig,
    );
    return GroupInviteMembershipFreshnessProof(
      inviteId: inviteId,
      groupId: groupId,
      recipientPeerId: recipientPeerId,
      inviterPeerId: inviterPeerId,
      inviterPublicKey: inviterPublicKey,
      keyEpoch: keyEpoch,
      groupConfigStateHash: stateHash,
      membershipWatermark: stateHash,
      issuedAt: issuedAt.toUtc(),
      expiresAt: issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
      inviterMemberSnapshot: {
        'peerId': inviterPeerId,
        'username': inviterUsername,
        'role': 'admin',
        'publicKey': inviterPublicKey,
      },
    );
  }

  group('Multi-user group membership smoke tests', () {
    test(
      'ML-001 KE-001 A/B/C private create invite acceptance converges active membership at initial epoch 1',
      () async {
        const groupId = 'grp-ml001-private-abc';
        const groupKey = 'base64ML001PrivateAbcKey==';
        const keyEpoch = 1;
        final createdAt = DateTime.utc(2026, 5, 11, 9);
        final inviteReceivedAt = createdAt.add(const Duration(minutes: 1));
        final acceptAt = createdAt.add(const Duration(minutes: 2));

        final aliceBridge = PassthroughCryptoBridge();
        aliceBridge.responses['group:create'] = {
          'ok': true,
          'groupId': groupId,
          'topicName': '/mknoon/group/$groupId',
          'groupKey': groupKey,
          'keyEpoch': keyEpoch,
        };

        final alice = GroupTestUser.create(
          peerId: 'peer-ml001-alice',
          username: 'Alice',
          network: network,
          bridge: aliceBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml001-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml001-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        ContactModel contactFor(GroupTestUser user) {
          return ContactModel(
            peerId: user.peerId,
            publicKey: user.publicKey,
            rendezvous: '/ip4/0.0.0.0',
            username: user.username,
            signature: 'sig-${user.peerId}',
            scannedAt: createdAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-${user.peerId}',
          );
        }

        final p2pService = _PerRecipientInviteP2PService(failingPeerIds: {});
        final createResult = await createGroupWithMembers(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          p2pService: p2pService,
          identity: IdentityModel(
            peerId: alice.peerId,
            publicKey: alice.publicKey,
            privateKey: alice.privateKey,
            mnemonic12:
                'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
            mlKemPublicKey: 'mlkem-${alice.peerId}',
            username: alice.username,
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
          selectedContacts: [contactFor(bob), contactFor(charlie)],
          type: GroupType.chat,
          name: 'ML-001 Private ABC',
        );

        expect(createResult.membersAdded, 2);
        expect(createResult.invitesSent, 2);
        expect(createResult.hasWarnings, isFalse);
        expect(p2pService.sentMessageLog.map((entry) => entry.peerId).toSet(), {
          bob.peerId,
          charlie.peerId,
        });

        Future<void> storeDeliveredInvite({
          required GroupTestUser recipient,
          required InMemoryPendingGroupInviteRepository pendingRepo,
        }) async {
          final delivered = p2pService.sentMessageLog.firstWhere(
            (entry) => entry.peerId == recipient.peerId,
          );
          final incoming = ChatMessage(
            from: alice.peerId,
            to: recipient.peerId,
            content: delivered.content,
            timestamp: inviteReceivedAt.toIso8601String(),
            isIncoming: true,
          );
          final (
            storeResult,
            pendingInvite,
          ) = await storeIncomingPendingGroupInvite(
            message: incoming,
            groupRepo: recipient.groupRepo,
            pendingInviteRepo: pendingRepo,
            contactRepo: FakeContactRepository()..seed([contactFor(alice)]),
            bridge: recipient.bridge,
            ownMlKemSecretKey: 'mlkem-secret-${recipient.peerId}',
            ownPeerId: recipient.peerId,
            receivedAt: inviteReceivedAt,
          );
          expect(
            storeResult,
            StorePendingGroupInviteResult.storedPending,
            reason: '${recipient.peerId} stores the delivered invite first',
          );
          expect(pendingInvite, isNotNull);
          expect(pendingInvite!.groupId, groupId);
          expect(await pendingRepo.getPendingInvite(groupId), isNotNull);
        }

        final bobPendingRepo = InMemoryPendingGroupInviteRepository();
        final charliePendingRepo = InMemoryPendingGroupInviteRepository();
        await storeDeliveredInvite(recipient: bob, pendingRepo: bobPendingRepo);
        await storeDeliveredInvite(
          recipient: charlie,
          pendingRepo: charliePendingRepo,
        );

        Future<void> acceptFor({
          required GroupTestUser recipient,
          required InMemoryPendingGroupInviteRepository pendingRepo,
        }) async {
          final (acceptResult, acceptedGroup) = await acceptPendingGroupInvite(
            pendingInviteRepo: pendingRepo,
            groupRepo: recipient.groupRepo,
            contactRepo: FakeContactRepository()..seed([contactFor(alice)]),
            msgRepo: recipient.msgRepo,
            bridge: recipient.bridge,
            groupId: groupId,
            senderPeerId: recipient.peerId,
            senderPublicKey: recipient.publicKey,
            senderPrivateKey: recipient.privateKey,
            senderUsername: recipient.username,
            now: acceptAt,
          );
          expect(
            acceptResult,
            AcceptPendingGroupInviteResult.success,
            reason: '${recipient.peerId} accepts through the pending path',
          );
          expect(acceptedGroup, isNotNull);
          expect(acceptedGroup!.id, groupId);
          expect(await pendingRepo.getPendingInvite(groupId), isNull);
        }

        await acceptFor(recipient: bob, pendingRepo: bobPendingRepo);
        await acceptFor(recipient: charlie, pendingRepo: charliePendingRepo);

        alice.subscribeToGroup(groupId);
        bob.subscribeToGroup(groupId);
        charlie.subscribeToGroup(groupId);
        alice.start();
        bob.start();
        charlie.start();

        String latestSystemPublishText(FakeBridge bridge, String sysType) {
          final raw = bridge.sentMessages.lastWhere((message) {
            final parsed = jsonDecode(message) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:publish') return false;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final text = payload['text'] as String? ?? '';
            final sys = jsonDecode(text) as Map<String, dynamic>;
            return sys['__sys'] == sysType;
          });
          final payload =
              (jsonDecode(raw) as Map<String, dynamic>)['payload']
                  as Map<String, dynamic>;
          return payload['text'] as String;
        }

        Future<void> mirrorSystemPublish({
          required GroupTestUser sender,
          required String sysType,
          required DateTime timestamp,
          required String messageId,
        }) async {
          await network.publish(groupId, sender.peerId, {
            'groupId': groupId,
            'senderId': sender.peerId,
            'senderUsername': sender.username,
            'keyEpoch': 0,
            'text': latestSystemPublishText(sender.bridge, sysType),
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
          }, senderDeviceId: sender.deviceId);
        }

        await mirrorSystemPublish(
          sender: alice,
          sysType: 'members_added',
          timestamp: createdAt.add(const Duration(seconds: 30)),
          messageId: 'ml001-members-added',
        );
        await mirrorSystemPublish(
          sender: bob,
          sysType: 'member_joined',
          timestamp: acceptAt.add(const Duration(seconds: 1)),
          messageId: 'ml001-bob-joined',
        );
        await mirrorSystemPublish(
          sender: charlie,
          sysType: 'member_joined',
          timestamp: acceptAt.add(const Duration(seconds: 2)),
          messageId: 'ml001-charlie-joined',
        );
        await waitUntil(() async {
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceTexts.containsAll({
                'Bob joined the group',
                'Charlie joined the group',
              }) &&
              bobTexts.containsAll({
                'Alice added Bob and Charlie',
                'Bob joined the group',
                'Charlie joined the group',
              }) &&
              charlieTexts.containsAll({
                'Alice added Bob and Charlie',
                'Bob joined the group',
                'Charlie joined the group',
              });
        }, maxTicks: 40);

        final expectedPeerIds = {alice.peerId, bob.peerId, charlie.peerId};

        Future<void> expectConverged(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');
          expect(group!.id, groupId);
          expect(group.type, GroupType.chat);
          expect(group.topicName, '/mknoon/group/$groupId');

          final members = await user.groupRepo.getMembers(groupId);
          final byPeer = {for (final member in members) member.peerId: member};
          expect(byPeer.keys.toSet(), expectedPeerIds);
          expect(byPeer[alice.peerId]!.role, MemberRole.admin);
          expect(byPeer[bob.peerId]!.role, MemberRole.writer);
          expect(byPeer[charlie.peerId]!.role, MemberRole.writer);

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: '${user.peerId} has key');
          expect(latestKey!.keyGeneration, keyEpoch);
          expect(latestKey.encryptedKey, groupKey);

          final groupConfig = buildGroupConfigPayload(group, members);
          expect(groupConfig[groupConfigStateHashField], isA<String>());
          expect(
            (groupConfig['members'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map((member) => member['peerId'])
                .toSet(),
            expectedPeerIds,
          );
        }

        await expectConverged(alice);
        await expectConverged(bob);
        await expectConverged(charlie);

        final configHashes = <String>{
          for (final user in [alice, bob, charlie])
            buildGroupConfigPayload(
                  (await user.groupRepo.getGroup(groupId))!,
                  await user.groupRepo.getMembers(groupId),
                )[groupConfigStateHashField]
                as String,
        };
        expect(configHashes, hasLength(1));

        bool joinedThroughBridge(GroupTestUser user) {
          return user.bridge.sentMessages.any(
            (raw) =>
                (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
                'group:join',
          );
        }

        expect(joinedThroughBridge(bob), isTrue);
        expect(joinedThroughBridge(charlie), isTrue);
      },
    );

    test(
      'ML-004 mixed batch invite failure lets delivered recipients accept while failed recipient stays pending',
      () async {
        const groupId = 'grp-ml004-mixed-batch';
        const groupKey = 'base64ML004MixedBatchKey==';
        const keyEpoch = 3;
        final createdAt = DateTime.utc(2026, 5, 7, 12);
        final inviteReceivedAt = createdAt.add(const Duration(minutes: 1));
        final acceptAt = createdAt.add(const Duration(minutes: 2));

        final adminBridge = PassthroughCryptoBridge();
        adminBridge.responses['group:create'] = {
          'ok': true,
          'groupId': groupId,
          'topicName': 'topic-$groupId',
          'groupKey': groupKey,
          'keyEpoch': keyEpoch,
        };

        final admin = GroupTestUser.create(
          peerId: 'peer-ml004-admin',
          username: 'Admin',
          network: network,
          bridge: adminBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml004-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml004-charlie',
          username: 'Charlie',
          network: network,
        );
        final dave = GroupTestUser.create(
          peerId: 'peer-ml004-dave',
          username: 'Dave',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
          dave.dispose();
        });

        ContactModel contactFor(GroupTestUser user) {
          return ContactModel(
            peerId: user.peerId,
            publicKey: user.publicKey,
            rendezvous: '/ip4/0.0.0.0',
            username: user.username,
            signature: 'sig-${user.peerId}',
            scannedAt: createdAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-${user.peerId}',
          );
        }

        final p2pService = _PerRecipientInviteP2PService(
          failingPeerIds: {dave.peerId},
        );
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();

        final createResult = await createGroupWithMembers(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          p2pService: p2pService,
          identity: IdentityModel(
            peerId: admin.peerId,
            publicKey: admin.publicKey,
            privateKey: admin.privateKey,
            mnemonic12:
                'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
            mlKemPublicKey: 'mlkem-${admin.peerId}',
            username: admin.username,
            createdAt: createdAt.toIso8601String(),
            updatedAt: createdAt.toIso8601String(),
          ),
          selectedContacts: [
            contactFor(bob),
            contactFor(charlie),
            contactFor(dave),
          ],
          type: GroupType.chat,
          name: 'ML-004 Mixed Batch',
          inviteDeliveryAttemptRepo: inviteStatusRepo,
        );

        expect(createResult.membersAdded, 3);
        expect(createResult.invitesSent, 2);
        expect(createResult.hasWarnings, isTrue);
        expect(
          createResult.inviteBatchResult!.failures.single.peerId,
          dave.peerId,
        );

        final creatorMembers = await admin.groupRepo.getMembers(groupId);
        final creatorPeerIds = creatorMembers.map((m) => m.peerId).toSet();
        expect(creatorPeerIds, {
          admin.peerId,
          bob.peerId,
          charlie.peerId,
          dave.peerId,
        });

        final updateConfigMsg = admin.bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final config =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        expect(
          (config['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet(),
          creatorPeerIds,
        );

        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: groupId,
            peerId: bob.peerId,
          ),
          GroupInviteDeliveryStatus.sent,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: groupId,
            peerId: charlie.peerId,
          ),
          GroupInviteDeliveryStatus.sent,
        );
        expect(
          await inviteStatusRepo.getStatusForMember(
            groupId: groupId,
            peerId: dave.peerId,
          ),
          GroupInviteDeliveryStatus.needsResend,
        );
        final daveAttempt = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: dave.peerId,
        );
        expect(daveAttempt, isNotNull);
        expect(daveAttempt!.status, isNot(GroupInviteDeliveryStatus.joined));
        expect(daveAttempt.lastError, 'send_failed');
        expect(p2pService.inboxStoreLog.map((entry) => entry.peerId).toSet(), {
          dave.peerId,
        });

        GroupInvitePayload deliveredInviteFor(GroupTestUser user) {
          final entry = p2pService.sentMessageLog.firstWhere(
            (message) => message.peerId == user.peerId,
          );
          final envelope = jsonDecode(entry.content) as Map<String, dynamic>;
          final encrypted = envelope['encrypted'] as Map<String, dynamic>;
          return GroupInvitePayload.fromInnerJson(
            encrypted['ciphertext'] as String,
          )!;
        }

        final bobPendingRepo = InMemoryPendingGroupInviteRepository();
        final charliePendingRepo = InMemoryPendingGroupInviteRepository();
        final davePendingRepo = InMemoryPendingGroupInviteRepository();
        await bobPendingRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            deliveredInviteFor(bob),
            receivedAt: inviteReceivedAt,
          ),
        );
        await charliePendingRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(
            deliveredInviteFor(charlie),
            receivedAt: inviteReceivedAt,
          ),
        );

        Future<(AcceptPendingGroupInviteResult, GroupModel?)> acceptFor({
          required GroupTestUser user,
          required InMemoryPendingGroupInviteRepository pendingRepo,
        }) {
          return acceptPendingGroupInvite(
            pendingInviteRepo: pendingRepo,
            groupRepo: user.groupRepo,
            contactRepo: FakeContactRepository()..seed([contactFor(admin)]),
            msgRepo: user.msgRepo,
            bridge: user.bridge,
            groupId: groupId,
            senderPeerId: user.peerId,
            senderPublicKey: user.publicKey,
            senderPrivateKey: user.privateKey,
            senderUsername: user.username,
            now: acceptAt,
          );
        }

        final acceptResults = await Future.wait([
          acceptFor(user: bob, pendingRepo: bobPendingRepo),
          acceptFor(user: charlie, pendingRepo: charliePendingRepo),
        ]);

        expect(acceptResults[0].$1, AcceptPendingGroupInviteResult.success);
        expect(acceptResults[1].$1, AcceptPendingGroupInviteResult.success);
        expect(acceptResults[0].$2, isNotNull);
        expect(acceptResults[1].$2, isNotNull);
        expect(
          (await bob.groupRepo.getGroup(groupId))?.myRole,
          GroupRole.member,
        );
        expect(
          (await charlie.groupRepo.getGroup(groupId))?.myRole,
          GroupRole.member,
        );
        expect(await bobPendingRepo.getPendingInvite(groupId), isNull);
        expect(await charliePendingRepo.getPendingInvite(groupId), isNull);
        expect(await davePendingRepo.getPendingInvite(groupId), isNull);
        expect(await dave.groupRepo.getGroup(groupId), isNull);
        expect(await dave.groupRepo.getMembers(groupId), isEmpty);
      },
    );

    test(
      'ML-014 config update failure rolls back local insert without fake-network membership',
      () async {
        const groupId = 'grp-ml014-config-rollback';
        final joinedAt = DateTime.utc(2026, 5, 11, 10);

        final admin = GroupTestUser.create(
          peerId: 'peer-ml014-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml014-bob',
          username: 'Bob',
          network: network,
        );
        final candidate = GroupTestUser.create(
          peerId: 'peer-ml014-candidate',
          username: 'Candidate',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          candidate.dispose();
        });

        await admin.createGroup(
          groupId: groupId,
          name: 'ML-014 Rollback',
          createdAt: joinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        );
        admin.bridge.responses['group:updateConfig'] = {
          'ok': false,
          'errorCode': 'CONFIG_SYNC_FAILED',
          'errorMessage': 'bridge rejected config',
        };

        await expectLater(
          addGroupMember(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            newMember: GroupMember(
              groupId: groupId,
              peerId: candidate.peerId,
              username: candidate.username,
              role: MemberRole.writer,
              publicKey: candidate.publicKey,
              mlKemPublicKey: 'mlkem-${candidate.peerId}',
              devices: [candidate.deviceIdentity],
              joinedAt: joinedAt.add(const Duration(minutes: 2)),
            ),
            selfPeerId: admin.peerId,
          ),
          throwsA(isA<Exception>()),
        );

        expect(
          admin.bridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          hasLength(1),
        );
        final updateConfigMsg = admin.bridge.sentMessages.firstWhere((msg) {
          final parsed = jsonDecode(msg) as Map<String, dynamic>;
          return parsed['cmd'] == 'group:updateConfig';
        });
        final updateConfigPayload =
            (jsonDecode(updateConfigMsg) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final groupConfig =
            updateConfigPayload['groupConfig'] as Map<String, dynamic>;
        expect(
          (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'])
              .toSet(),
          {admin.peerId, bob.peerId, candidate.peerId},
        );

        expect(
          (await admin.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {admin.peerId, bob.peerId},
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {admin.peerId, bob.peerId},
        );
        expect(
          await admin.groupRepo.getMember(groupId, candidate.peerId),
          isNull,
        );
        expect(await candidate.groupRepo.getGroup(groupId), isNull);
        expect(await candidate.groupRepo.getMembers(groupId), isEmpty);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(await bob.loadGroupMessages(groupId), isEmpty);
        expect(await candidate.loadGroupMessages(groupId), isEmpty);
        expect(admin.bridge.commandLog, isNot(contains('group:publish')));
        expect(admin.bridge.commandLog, isNot(contains('message.encrypt')));
        expect(network.publishCount, 0);
        expect(network.totalDeliveries, 0);
      },
    );

    test(
      'IJ010 concurrent direct invite accepts converge membership epoch and delivery',
      () async {
        const groupId = 'grp-ij010-concurrent-joins';
        const groupKey = 'base64IJ010ConcurrentJoinKey==';
        const keyEpoch = 7;
        final groupCreatedAt = DateTime.utc(2025, 1, 1, 4);
        final existingJoinedAt = groupCreatedAt.add(const Duration(minutes: 5));
        final keyCreatedAt = groupCreatedAt.add(const Duration(minutes: 10));
        final membersAddedAt = groupCreatedAt.add(const Duration(minutes: 15));
        final inviteReceivedAt = groupCreatedAt.add(
          const Duration(minutes: 16),
        );
        final acceptAt = groupCreatedAt.add(const Duration(minutes: 17));

        final admin = GroupTestUser.create(
          peerId: 'peer-ij010-admin',
          username: 'Admin',
          network: network,
        );
        final existing = GroupTestUser.create(
          peerId: 'peer-ij010-existing',
          username: 'Existing',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ij010-charlie',
          username: 'Charlie',
          network: network,
        );
        final dave = GroupTestUser.create(
          peerId: 'peer-ij010-dave',
          username: 'Dave',
          network: network,
        );
        final eve = GroupTestUser.create(
          peerId: 'peer-ij010-eve',
          username: 'Eve',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          existing.dispose();
          charlie.dispose();
          dave.dispose();
          eve.dispose();
        });

        Map<String, dynamic> memberEntry(
          GroupTestUser user, {
          required String role,
        }) {
          return {
            'peerId': user.peerId,
            'username': user.username,
            'role': role,
            'publicKey': user.publicKey,
            'mlKemPublicKey': 'mlkem-${user.peerId}',
          };
        }

        ContactModel contactFor(GroupTestUser user) {
          return ContactModel(
            peerId: user.peerId,
            publicKey: user.publicKey,
            rendezvous: '/ip4/0.0.0.0',
            username: user.username,
            signature: 'sig-${user.peerId}',
            scannedAt: groupCreatedAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-${user.peerId}',
          );
        }

        final expectedPeerIds = {
          admin.peerId,
          existing.peerId,
          charlie.peerId,
          dave.peerId,
        };
        final groupConfig = {
          'name': 'IJ010 Concurrent Joins',
          'groupType': 'chat',
          'description': 'Concurrent join convergence proof',
          'members': [
            memberEntry(admin, role: 'admin'),
            memberEntry(existing, role: 'writer'),
            memberEntry(charlie, role: 'writer'),
            memberEntry(dave, role: 'writer'),
          ],
          'createdBy': admin.peerId,
          'createdAt': groupCreatedAt.toIso8601String(),
        };

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: groupKey,
              createdAt: keyCreatedAt,
            ),
          );
        }

        await admin.createGroup(
          groupId: groupId,
          name: 'IJ010 Concurrent Joins',
          description: 'Concurrent join convergence proof',
          createdAt: groupCreatedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: existing,
          joinedAt: existingJoinedAt,
        );
        await saveKey(admin);
        await saveKey(existing);

        for (final joiningUser in [charlie, dave]) {
          await admin.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: joiningUser.peerId,
              username: joiningUser.username,
              role: MemberRole.writer,
              publicKey: joiningUser.publicKey,
              mlKemPublicKey: 'mlkem-${joiningUser.peerId}',
              joinedAt: membersAddedAt,
            ),
          );
        }

        admin.start();
        existing.start();

        final addedMembers = [
          memberEntry(charlie, role: 'writer'),
          memberEntry(dave, role: 'writer'),
        ];
        await network.publish(groupId, admin.peerId, {
          'groupId': groupId,
          'senderId': admin.peerId,
          'senderUsername': admin.username,
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'members_added',
            'members': addedMembers,
            'groupConfig': groupConfig,
          }),
          'timestamp': membersAddedAt.toIso8601String(),
          'messageId': 'ij010-members-added',
        }, senderDeviceId: admin.deviceId);
        await waitUntil(() async {
          final members = await existing.groupRepo.getMembers(groupId);
          return expectedPeerIds
              .difference(members.map((m) => m.peerId).toSet())
              .isEmpty;
        }, maxTicks: 40);

        PendingGroupInvite makePendingInvite({
          required GroupTestUser recipient,
          required String inviteId,
        }) {
          return PendingGroupInvite.fromPayload(
            GroupInvitePayload(
              id: inviteId,
              groupId: groupId,
              groupKey: groupKey,
              keyEpoch: keyEpoch,
              groupConfig: groupConfig,
              senderPeerId: admin.peerId,
              senderUsername: admin.username,
              timestamp: inviteReceivedAt.toIso8601String(),
              recipientPeerId: recipient.peerId,
              invitePolicy: GroupInvitePolicy(
                expiresAt: inviteReceivedAt.add(pendingGroupInviteTtl),
                allowedDevices: [recipient.peerId],
                assignedRole: 'writer',
                canInviteOthers: false,
                joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
                keyEpoch: keyEpoch,
                reusePolicy: GroupInviteReusePolicy.singleUse,
              ),
              membershipFreshnessProof: makeFreshnessProof(
                inviteId: inviteId,
                groupId: groupId,
                recipientPeerId: recipient.peerId,
                inviterPeerId: admin.peerId,
                inviterUsername: admin.username,
                inviterPublicKey: admin.publicKey,
                groupConfig: groupConfig,
                keyEpoch: keyEpoch,
                issuedAt: inviteReceivedAt,
              ),
            ).withInviteSignature(signature: 'signed-$inviteId'),
            receivedAt: inviteReceivedAt,
          );
        }

        final charliePendingRepo = InMemoryPendingGroupInviteRepository();
        final davePendingRepo = InMemoryPendingGroupInviteRepository();
        final charlieContactRepo = FakeContactRepository()
          ..seed([contactFor(admin)]);
        final daveContactRepo = FakeContactRepository()
          ..seed([contactFor(admin)]);
        await charliePendingRepo.savePendingInvite(
          makePendingInvite(
            recipient: charlie,
            inviteId: 'invite-ij010-charlie',
          ),
        );
        await davePendingRepo.savePendingInvite(
          makePendingInvite(recipient: dave, inviteId: 'invite-ij010-dave'),
        );

        final acceptResults = await Future.wait([
          acceptPendingGroupInvite(
            pendingInviteRepo: charliePendingRepo,
            groupRepo: charlie.groupRepo,
            contactRepo: charlieContactRepo,
            msgRepo: charlie.msgRepo,
            bridge: charlie.bridge,
            groupId: groupId,
            senderPeerId: charlie.peerId,
            senderPublicKey: charlie.publicKey,
            senderPrivateKey: charlie.privateKey,
            senderUsername: charlie.username,
            now: acceptAt,
          ),
          acceptPendingGroupInvite(
            pendingInviteRepo: davePendingRepo,
            groupRepo: dave.groupRepo,
            contactRepo: daveContactRepo,
            msgRepo: dave.msgRepo,
            bridge: dave.bridge,
            groupId: groupId,
            senderPeerId: dave.peerId,
            senderPublicKey: dave.publicKey,
            senderPrivateKey: dave.privateKey,
            senderUsername: dave.username,
            now: acceptAt,
          ),
        ]);

        expect(acceptResults[0].$1, AcceptPendingGroupInviteResult.success);
        expect(acceptResults[1].$1, AcceptPendingGroupInviteResult.success);
        expect(acceptResults[0].$2, isNotNull);
        expect(acceptResults[1].$2, isNotNull);
        expect(acceptResults[0].$2!.myRole, GroupRole.member);
        expect(acceptResults[1].$2!.myRole, GroupRole.member);

        charlie.subscribeToGroup(groupId);
        dave.subscribeToGroup(groupId);
        charlie.start();
        dave.start();

        expect(network.isSubscribed(groupId, admin.peerId), isTrue);
        expect(network.isSubscribed(groupId, existing.peerId), isTrue);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(network.isSubscribed(groupId, dave.peerId), isTrue);
        expect(network.isSubscribed(groupId, eve.peerId), isFalse);

        bool bridgeJoined(GroupTestUser user) {
          return user.bridge.sentMessages.any(
            (raw) =>
                (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
                'group:join',
          );
        }

        expect(bridgeJoined(charlie), isTrue);
        expect(bridgeJoined(dave), isTrue);
        expect(
          await charliePendingRepo.getConsumedInvite('invite-ij010-charlie'),
          isNotNull,
        );
        expect(
          await davePendingRepo.getConsumedInvite('invite-ij010-dave'),
          isNotNull,
        );
        expect(await charliePendingRepo.getPendingInvite(groupId), isNull);
        expect(await davePendingRepo.getPendingInvite(groupId), isNull);

        Future<void> expectConverged(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');

          final members = await user.groupRepo.getMembers(groupId);
          final byPeer = {for (final member in members) member.peerId: member};
          expect(
            byPeer.keys.toSet(),
            expectedPeerIds,
            reason: '${user.peerId} has exact member set',
          );
          expect(byPeer[admin.peerId]!.role, MemberRole.admin);
          expect(byPeer[existing.peerId]!.role, MemberRole.writer);
          expect(byPeer[charlie.peerId]!.role, MemberRole.writer);
          expect(byPeer[dave.peerId]!.role, MemberRole.writer);
          expect(byPeer.containsKey(eve.peerId), isFalse);

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: '${user.peerId} has key');
          expect(latestKey!.keyGeneration, keyEpoch);
          expect(latestKey.encryptedKey, groupKey);
        }

        await expectConverged(admin);
        await expectConverged(existing);
        await expectConverged(charlie);
        await expectConverged(dave);
        expect(await eve.groupRepo.getGroup(groupId), isNull);
        expect(await eve.groupRepo.getLatestKey(groupId), isNull);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'IJ010 Charlie after concurrent join',
              timestamp: acceptAt.add(const Duration(minutes: 1)),
            );
        final (daveSendResult, daveMessage) = await dave
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'IJ010 Dave after concurrent join',
              timestamp: acceptAt.add(const Duration(minutes: 2)),
            );

        expect(charlieSendResult, group_send.SendGroupMessageResult.success);
        expect(daveSendResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(daveMessage, isNotNull);

        final expectedLiveTexts = {
          'IJ010 Charlie after concurrent join',
          'IJ010 Dave after concurrent join',
        };
        await waitUntil(() async {
          final existingTexts = (await existing.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final daveTexts = (await dave.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return expectedLiveTexts.difference(existingTexts).isEmpty &&
              charlieTexts.contains('IJ010 Dave after concurrent join') &&
              daveTexts.contains('IJ010 Charlie after concurrent join');
        }, maxTicks: 40);

        final existingTexts = (await existing.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        final adminTexts = (await admin.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        final daveTexts = (await dave.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(existingTexts.containsAll(expectedLiveTexts), isTrue);
        expect(adminTexts.containsAll(expectedLiveTexts), isTrue);
        expect(
          charlieTexts.contains('IJ010 Dave after concurrent join'),
          isTrue,
        );
        expect(
          daveTexts.contains('IJ010 Charlie after concurrent join'),
          isTrue,
        );
        expect(await eve.loadGroupMessages(groupId), isEmpty);
      },
    );

    // -----------------------------------------------------------------------
    // 1. Admin removes member — removed member stops receiving messages.
    // -----------------------------------------------------------------------
    test(
      'admin removes member — removed member stops receiving messages',
      () async {
        const groupId = 'grp-remove-001';

        // Create 4 users
        final alice = GroupTestUser.create(
          peerId: 'peer-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        // Alice creates group and adds everyone
        await alice.createGroup(groupId: groupId, name: 'Test Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await alice.addMember(groupId: groupId, invitee: diana);

        // Start all listeners
        alice.start();
        bob.start();
        charlie.start();
        diana.start();

        // Alice sends "Before removal"
        await alice.sendGroupMessage(groupId: groupId, text: 'Before removal');
        await pump();

        // Alice removes Bob
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Alice sends "After removal"
        await alice.sendGroupMessage(groupId: groupId, text: 'After removal');
        await pump();

        // Load incoming messages for each user
        final bobMessages = await bob.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final dianaMessages = await diana.loadGroupMessages(groupId);

        // Filter to incoming only
        final bobIncoming = bobMessages.where((m) => m.isIncoming).toList();
        final charlieIncoming = charlieMessages
            .where((m) => m.isIncoming)
            .toList();
        final dianaIncoming = dianaMessages.where((m) => m.isIncoming).toList();

        final bobRegular = bobIncoming
            .where(
              (message) =>
                  message.text == 'Before removal' ||
                  message.text == 'After removal',
            )
            .toList();

        // Bob keeps his old local history plus the removal timeline event, but
        // must not receive ordinary chat after removal.
        expect(bobRegular, hasLength(1));
        expect(bobRegular[0].text, equals('Before removal'));

        final charlieRegular = charlieIncoming
            .where(
              (message) =>
                  message.text == 'Before removal' ||
                  message.text == 'After removal',
            )
            .toList();
        final dianaRegular = dianaIncoming
            .where(
              (message) =>
                  message.text == 'Before removal' ||
                  message.text == 'After removal',
            )
            .toList();

        // Charlie: the regular before/after texts plus a persisted removal
        // timeline entry are all allowed now; pin the ordinary chat flow
        // explicitly.
        expect(charlieRegular, hasLength(2));
        expect(
          charlieRegular.map((m) => m.text).toList(),
          containsAll(['Before removal', 'After removal']),
        );

        // Diana sees the same ordinary chat flow.
        expect(dianaRegular, hasLength(2));
        expect(
          dianaRegular.map((m) => m.text).toList(),
          containsAll(['Before removal', 'After removal']),
        );

        // Bob should NOT be subscribed on the network anymore
        expect(network.isSubscribed(groupId, bob.peerId), isFalse);

        // Cleanup
        alice.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 2. Admin removes member — remaining members update their local member
    //    list.
    // -----------------------------------------------------------------------
    test(
      'admin removes member — remaining members update their local member list',
      () async {
        const groupId = 'grp-remove-002';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob and Charlie
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();

        // Admin removes Charlie
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        // Bob should NOT have Charlie in his local group repo
        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final bobMemberPeerIds = bobMembers.map((m) => m.peerId).toSet();
        expect(bobMemberPeerIds, isNot(contains(charlie.peerId)));

        // Admin should NOT have Charlie either (removed locally before broadcast)
        final adminMembers = await admin.groupRepo.getMembers(groupId);
        final adminMemberPeerIds = adminMembers.map((m) => m.peerId).toSet();
        expect(adminMemberPeerIds, isNot(contains(charlie.peerId)));

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'ML-013 non-admin and non-member raw membership events are ignored by peers',
      () async {
        const groupId = 'grp-auth-001';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Auth Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        admin.bridge.commandLog.clear();
        bob.bridge.commandLog.clear();

        final forgedText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': admin.peerId, 'username': admin.username},
          'groupConfig': {
            'name': 'Auth Guard',
            'groupType': 'chat',
            'members': [
              {
                'peerId': bob.peerId,
                'username': bob.username,
                'role': 'writer',
                'publicKey': bob.publicKey,
              },
            ],
            'createdBy': admin.peerId,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': bob.username,
          'keyEpoch': 0,
          'text': forgedText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        await pump();

        final nonMemberForgedText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': 'peer-diana',
            'username': 'Diana',
            'role': 'writer',
            'publicKey': 'pk-peer-diana',
          },
          'groupConfig': {
            'name': 'Auth Guard',
            'groupType': 'chat',
            'members': [
              {
                'peerId': admin.peerId,
                'username': admin.username,
                'role': 'admin',
                'publicKey': admin.publicKey,
              },
              {
                'peerId': bob.peerId,
                'username': bob.username,
                'role': 'writer',
                'publicKey': bob.publicKey,
              },
              {
                'peerId': 'peer-diana',
                'username': 'Diana',
                'role': 'writer',
                'publicKey': 'pk-peer-diana',
              },
            ],
            'createdBy': admin.peerId,
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          },
        });

        await network.publish(groupId, charlie.peerId, {
          'groupId': groupId,
          'senderId': charlie.peerId,
          'senderUsername': charlie.username,
          'keyEpoch': 0,
          'text': nonMemberForgedText,
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });
        await pump();

        Future<void> expectCanonicalMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            admin.peerId,
            bob.peerId,
          });
        }

        await expectCanonicalMembers(admin);
        await expectCanonicalMembers(bob);

        expect(await admin.groupRepo.getGroup(groupId), isNotNull);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(admin.bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(bob.bridge.commandLog, isNot(contains('group:updateConfig')));

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 3. Self-removal — removed user calls leaveGroup and cleans up.
    // -----------------------------------------------------------------------
    test(
      'self-removal — removed user calls leaveGroup and cleans up',
      () async {
        const groupId = 'grp-remove-003';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob and Charlie
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();

        // Listen to Bob's groupRemovedStream BEFORE the removal
        final removedGroupIds = <String>[];
        final removedSub = bob.groupMessageListener.groupRemovedStream.listen((
          gid,
        ) {
          removedGroupIds.add(gid);
        });

        // Admin removes Bob
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Bob's groupRemovedStream should have emitted the groupId
        expect(removedGroupIds, contains(groupId));

        // Bob's groupRepo should have no group (leaveGroup deletes it)
        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNull);

        // Bob's bridge.commandLog should contain 'group:leave'
        expect(bob.bridge.commandLog, contains('group:leave'));

        // Cleanup
        await removedSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test('GM-016 removed member remains unsubscribed from topic', () async {
      const groupId = 'gm016-topic-unsubscribe';
      final createdAt = DateTime.now().toUtc();

      final alice = GroupTestUser.create(
        peerId: 'gm016-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'gm016-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'gm016-charlie',
        username: 'Charlie',
        network: network,
      );

      await alice.createGroup(
        groupId: groupId,
        name: 'GM-016 Group',
        createdAt: createdAt,
      );
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);
      for (final user in <GroupTestUser>[alice, bob, charlie]) {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'gm016-key',
            createdAt: createdAt,
          ),
        );
      }

      alice.start();
      bob.start();
      charlie.start();

      expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

      final removedGroupIds = <String>[];
      final removedSub = charlie.groupMessageListener.groupRemovedStream.listen(
        removedGroupIds.add,
      );
      final removedAt = DateTime.now().toUtc();

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );
      await waitUntil(
        () async => await charlie.groupRepo.getGroup(groupId) == null,
        maxTicks: 40,
      );

      expect(removedGroupIds, contains(groupId));
      expect(charlie.bridge.commandLog, contains('group:leave'));
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
      expect(await charlie.groupRepo.getGroup(groupId), isNull);
      expect(await charlie.groupRepo.getMembers(groupId), isEmpty);
      expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

      charlie.bridge.commandLog.clear();
      const postRemovalText = 'GM-016 Alice after Charlie removal';
      await alice.sendGroupMessage(
        groupId: groupId,
        text: postRemovalText,
        messageId: 'gm016-alice-after-removal',
        timestamp: removedAt.add(const Duration(seconds: 5)),
      );
      await waitUntil(() async {
        final bobTexts = (await bob.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toList();
        return bobTexts.where((text) => text == postRemovalText).length == 1;
      }, maxTicks: 40);

      final bobTexts = (await bob.loadGroupMessages(
        groupId,
      )).map((message) => message.text).toList();
      final charlieTexts = (await charlie.loadGroupMessages(
        groupId,
      )).map((message) => message.text).toList();

      expect(bobTexts.where((text) => text == postRemovalText), hasLength(1));
      expect(charlieTexts, isNot(contains(postRemovalText)));
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
      expect(charlie.bridge.commandLog, isNot(contains('group:join')));

      await removedSub.cancel();
      alice.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test(
      'GM-017 stale member stays subscribed while A/B configs exclude them',
      () async {
        const groupId = 'gm017-stale-subscription-setup';
        final createdAt = DateTime.now().toUtc();

        final alice = GroupTestUser.create(
          peerId: 'gm017-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm017-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm017-charlie',
          username: 'Charlie',
          network: network,
        );

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-017 Group',
          createdAt: createdAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'gm017-key',
              createdAt: createdAt,
            ),
          );
        }

        alice.start();
        bob.start();
        charlie.start();

        Future<List<String>> installRemainingConfig(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull);
          await user.groupRepo.removeMember(groupId, charlie.peerId);
          final remainingMembers = await user.groupRepo.getMembers(groupId);
          await callGroupUpdateConfig(
            user.bridge,
            groupId: groupId,
            groupConfig: buildGroupConfigPayload(group!, remainingMembers),
          );
          return remainingMembers
              .map((member) => member.peerId)
              .toList(growable: false);
        }

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final aliceMembers = await installRemainingConfig(alice);
        final bobMembers = await installRemainingConfig(bob);

        expect(
          aliceMembers,
          unorderedEquals(<String>[alice.peerId, bob.peerId]),
        );
        expect(bobMembers, unorderedEquals(<String>[alice.peerId, bob.peerId]));
        expect(alice.bridge.commandLog, contains('group:updateConfig'));
        expect(bob.bridge.commandLog, contains('group:updateConfig'));
        expect(alice.bridge.commandLog, isNot(contains('group:leave')));
        expect(bob.bridge.commandLog, isNot(contains('group:leave')));

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNotNull);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(
          charlieMembers.map((member) => member.peerId),
          contains(charlie.peerId),
        );
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(charlie.bridge.commandLog, isNot(contains('group:leave')));

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'GM-018 remaining members keep live and inbox delivery under stale removed-member pressure',
      () async {
        const groupId = 'gm018-remaining-delivery-continuity';
        const groupKey = 'gm018-initial-key';
        final createdAt = DateTime.now().toUtc();

        final alice = GroupTestUser.create(
          peerId: 'gm018-alice',
          username: 'Alice',
          network: network,
        );
        final bobBridge = cursorBridge();
        final bob = GroupTestUser.create(
          peerId: 'gm018-bob',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm018-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: groupKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<List<String>> installRemainingConfig(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull);
          await user.groupRepo.removeMember(groupId, charlie.peerId);
          final remainingMembers = await user.groupRepo.getMembers(groupId);
          await callGroupUpdateConfig(
            user.bridge,
            groupId: groupId,
            groupConfig: buildGroupConfigPayload(group!, remainingMembers),
          );
          return remainingMembers
              .map((member) => member.peerId)
              .toList(growable: false);
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        Map<String, dynamic> inboxPayloadForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return payload;
          }
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(String messageId) {
          final payload = inboxPayloadForMessage(alice, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-018 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final aliceMembers = await installRemainingConfig(alice);
        final bobMembers = await installRemainingConfig(bob);
        expect(
          aliceMembers,
          unorderedEquals(<String>[alice.peerId, bob.peerId]),
        );
        expect(bobMembers, unorderedEquals(<String>[alice.peerId, bob.peerId]));
        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        const staleCharlieText = 'GM-018 stale Charlie pressure';
        final (staleResult, staleMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: staleCharlieText,
              messageId: 'gm018-charlie-stale-pressure',
              timestamp: createdAt.add(const Duration(minutes: 1)),
            );
        expect(staleResult, group_send.SendGroupMessageResult.success);
        expect(staleMessage, isNotNull);
        await pump();
        expect(await incomingTextCount(alice, staleCharlieText), 0);
        expect(await incomingTextCount(bob, staleCharlieText), 0);

        network.holdDeliveriesFor(charlie.peerId);

        final liveTexts = <String>[
          'GM-018 live Alice to Bob 1',
          'GM-018 live Alice to Bob 2',
          'GM-018 live Alice to Bob 3',
        ];
        for (var i = 0; i < liveTexts.length; i++) {
          final messageId = 'gm018-live-${i + 1}';
          final (result, message) = await alice.sendGroupMessageViaBridge(
            groupId: groupId,
            text: liveTexts[i],
            messageId: messageId,
            timestamp: createdAt.add(Duration(minutes: 2, seconds: i)),
          );
          expect(result, group_send.SendGroupMessageResult.success);
          expect(message, isNotNull);
          expect(recipientPeerIdsForMessage(messageId).toSet(), {bob.peerId});
        }

        await waitUntil(() async {
          for (final text in liveTexts) {
            if (await incomingTextCount(bob, text) != 1) return false;
          }
          return true;
        }, maxTicks: 60);
        for (final text in liveTexts) {
          expect(await incomingTextCount(bob, text), 1);
          expect(await incomingTextCount(charlie, text), 0);
        }

        final inboxTexts = <String>[
          'GM-018 inbox Alice to Bob 1',
          'GM-018 inbox Alice to Bob 2',
          'GM-018 inbox Alice to Bob 3',
        ];
        final inboxRelayMessages = <Map<String, dynamic>>[];
        for (var i = 0; i < inboxTexts.length; i++) {
          final messageId = 'gm018-inbox-${i + 1}';
          final (result, message) = await alice.sendGroupMessageViaBridge(
            groupId: groupId,
            text: inboxTexts[i],
            messageId: messageId,
            timestamp: createdAt.add(Duration(minutes: 3, seconds: i)),
            publishTopicPeersOverride: 0,
          );
          expect(result, group_send.SendGroupMessageResult.successNoPeers);
          expect(message, isNotNull);

          final payload = inboxPayloadForMessage(alice, messageId);
          expect((payload['recipientPeerIds'] as List<dynamic>).toSet(), {
            bob.peerId,
          });
          inboxRelayMessages.add(<String, dynamic>{
            'from': alice.peerId,
            'message': payload['message'],
            'timestamp': createdAt
                .add(Duration(minutes: 3, seconds: i))
                .toIso8601String(),
          });
        }

        for (final text in inboxTexts) {
          expect(await incomingTextCount(bob, text), 0);
        }

        bobBridge.addPage(
          groupId: groupId,
          cursor: '',
          messages: inboxRelayMessages,
        );
        await drainGroupOfflineInboxForGroup(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          groupMessageListener: bob.groupMessageListener,
          selfPeerId: bob.peerId,
        );

        for (final text in inboxTexts) {
          expect(await incomingTextCount(bob, text), 1);
          expect(await incomingTextCount(charlie, text), 0);
        }

        network.unsubscribe(groupId, charlie.peerId);
        final offlineMembers = await alice.groupRepo.getMembers(groupId);
        expect(offlineMembers.map((member) => member.peerId).toSet(), {
          alice.peerId,
          bob.peerId,
        });
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // 4. Sole admin leave is blocked while only non-admin members remain.
    // -----------------------------------------------------------------------
    test('sole admin cannot leave while only writer members remain', () async {
      const groupId = 'grp-admin-leave-004';

      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
      );

      await admin.createGroup(groupId: groupId, name: 'Test Group');
      await admin.addMember(groupId: groupId, invitee: bob);

      admin.start();
      bob.start();

      await expectLater(
        leaveGroup(
          bridge: admin.bridge,
          groupRepo: admin.groupRepo,
          groupId: groupId,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(lastAdminLeaveBlockedMessage),
          ),
        ),
      );

      expect(admin.bridge.commandLog, isNot(contains('group:leave')));
      expect(await admin.groupRepo.getGroup(groupId), isNotNull);
      expect(
        (await admin.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet(),
        {'peer-admin', 'peer-bob'},
      );

      await admin.sendGroupMessage(groupId: groupId, text: 'Still here');
      await pump();

      final bobIncoming = (await bob.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();
      expect(
        bobIncoming.where((entry) => entry.text == 'Still here'),
        hasLength(1),
      );

      admin.dispose();
      bob.dispose();
    });

    test(
      'GM-015 creator/admin self-removal and leave are blocked with healthy writers',
      () async {
        const groupId = 'grp-gm015-admin-self-policy';
        const initialKey = 'gm015-initial-key';
        final createdAt = DateTime.utc(2026, 5, 11, 1);
        final keyCreatedAt = createdAt.add(const Duration(seconds: 30));

        final alice = GroupTestUser.create(
          peerId: 'peer-gm015-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm015-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm015-charlie',
          username: 'Charlie',
          network: network,
        );
        final removedGroupIds = <String>[];
        final bobRemovedSub = bob.groupMessageListener.groupRemovedStream
            .listen(removedGroupIds.add);
        final charlieRemovedSub = charlie
            .groupMessageListener
            .groupRemovedStream
            .listen(removedGroupIds.add);
        addTearDown(() async {
          await bobRemovedSub.cancel();
          await charlieRemovedSub.cancel();
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: initialKey,
              createdAt: keyCreatedAt,
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-015 Group',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(seconds: 2)),
        );
        final charlieMember = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(charlieMember, isNotNull);
        await bob.groupRepo.saveMember(charlieMember!);
        await saveKey(alice);
        await saveKey(bob);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        await expectLater(
          alice.removeMember(
            groupId: groupId,
            memberPeerId: alice.peerId,
            memberUsername: alice.username,
            removedAt: createdAt.add(const Duration(minutes: 1)),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(lastAdminRemovalBlockedMessage),
            ),
          ),
        );
        expect(alice.bridge.commandLog, isNot(contains('group:updateConfig')));
        expect(alice.bridge.commandLog, isNot(contains('group:publish')));

        await expectLater(
          alice.leaveGroup(groupId),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains(lastAdminLeaveBlockedMessage),
            ),
          ),
        );
        expect(alice.bridge.commandLog, isNot(contains('group:leave')));
        await pump();
        expect(removedGroupIds, isEmpty);

        Future<void> expectHealthyState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.username} keeps group');
          expect(group!.createdBy, alice.peerId);
          expect(group.isDissolved, isFalse);
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          expect(
            members
                .where((member) => member.role == MemberRole.admin)
                .map((member) => member.peerId),
            [alice.peerId],
          );
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 1);
          expect(latestKey.encryptedKey, initialKey);
        }

        await expectHealthyState(alice);
        await expectHealthyState(bob);
        await expectHealthyState(charlie);
        expect(network.isSubscribed(groupId, alice.peerId), isTrue);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        const bobText = 'GM-015 Bob after blocked creator self-removal';
        const charlieText = 'GM-015 Charlie after blocked creator leave';
        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobText,
          messageId: 'gm015-bob-after-block',
        );
        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieText,
              messageId: 'gm015-charlie-after-block',
            );

        expect(bobResult, group_send.SendGroupMessageResult.success);
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(bobMessage, isNotNull);
        expect(charlieMessage, isNotNull);
        expect(bobMessage!.keyGeneration, 1);
        expect(charlieMessage!.keyGeneration, 1);

        await waitUntil(() async {
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceTexts.containsAll(<String>[bobText, charlieText]) &&
              bobTexts.contains(charlieText) &&
              charlieTexts.contains(bobText);
        }, maxTicks: 40);

        final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final charlieIncomingTexts = (await charlie.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);

        expect(aliceIncomingTexts, containsAll(<String>[bobText, charlieText]));
        expect(bobIncomingTexts, contains(charlieText));
        expect(charlieIncomingTexts, contains(bobText));
      },
    );

    test(
      'promoted admin gains admin role and can perform admin-only actions',
      () async {
        const groupId = 'grp-admin-role-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Admin Roles');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
        );
        await pump();

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        final bobMember = await bob.groupRepo.getMember(groupId, bob.peerId);
        final adminViewOfBob = await admin.groupRepo.getMember(
          groupId,
          bob.peerId,
        );

        expect(bobGroup, isNotNull);
        expect(bobGroup!.myRole, GroupRole.admin);
        expect(bobMember, isNotNull);
        expect(bobMember!.role, MemberRole.admin);
        expect(adminViewOfBob, isNotNull);
        expect(adminViewOfBob!.role, MemberRole.admin);

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await pump();

        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(
          await admin.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'multi-admin leave keeps remaining admin healthy and synchronized',
      () async {
        const groupId = 'grp-admin-leave-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Admin Leave');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
        );
        await pump();

        await admin.leaveGroup(groupId);
        await pump();

        expect(await admin.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, admin.peerId), isFalse);

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        expect(charlieGroup, isNotNull);
        expect(bobGroup!.myRole, GroupRole.admin);
        expect(charlieGroup!.myRole, GroupRole.member);

        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(bobMembers.map((member) => member.peerId).toSet(), {
          'peer-bob',
          'peer-charlie',
        });
        expect(charlieMembers.map((member) => member.peerId).toSet(), {
          'peer-bob',
          'peer-charlie',
        });

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await waitUntil(
          () async => await charlie.groupRepo.getGroup(groupId) == null,
        );

        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'ML-020 admin role transfer and re-add keep delivery membership-bound',
      () async {
        const groupId = 'grp-ml020-admin-transfer';

        final alice = GroupTestUser.create(
          peerId: 'peer-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await alice.createGroup(groupId: groupId, name: 'ML-020 Roles');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        Future<int> incomingTextCount(
          GroupTestUser user,
          String text,
          String senderPeerId,
        ) async {
          final messages = await user.loadGroupMessages(groupId);
          return messages
              .where(
                (message) =>
                    message.isIncoming &&
                    message.text == text &&
                    message.senderPeerId == senderPeerId,
              )
              .length;
        }

        Future<Map<String, MemberRole>> rolesFor(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          return {for (final member in members) member.peerId: member.role};
        }

        await alice.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
        );
        await waitUntil(
          () async =>
              (await bob.groupRepo.getGroup(groupId))?.myRole ==
              GroupRole.admin,
        );

        await bob.updateMemberRole(
          groupId: groupId,
          memberPeerId: alice.peerId,
          role: MemberRole.writer,
        );
        await waitUntil(
          () async =>
              (await alice.groupRepo.getGroup(groupId))?.myRole ==
              GroupRole.member,
        );

        for (final user in [alice, bob, charlie]) {
          final roles = await rolesFor(user);
          expect(roles[alice.peerId], MemberRole.writer);
          expect(roles[bob.peerId], MemberRole.admin);
          expect(roles[charlie.peerId], MemberRole.writer);
        }

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await waitUntil(
          () async => await charlie.groupRepo.getGroup(groupId) == null,
        );

        const aliceRemovedWindowText =
            'ML-020 Alice sends while creator demoted and Charlie removed';
        const bobRemovedWindowText =
            'ML-020 Bob sends as transferred admin while Charlie removed';
        await alice.sendGroupMessage(
          groupId: groupId,
          text: aliceRemovedWindowText,
        );
        await bob.sendGroupMessage(
          groupId: groupId,
          text: bobRemovedWindowText,
        );
        await pump();

        expect(
          await incomingTextCount(bob, aliceRemovedWindowText, alice.peerId),
          1,
        );
        expect(
          await incomingTextCount(alice, bobRemovedWindowText, bob.peerId),
          1,
        );
        expect(
          await incomingTextCount(
            charlie,
            aliceRemovedWindowText,
            alice.peerId,
          ),
          0,
        );
        expect(
          await incomingTextCount(charlie, bobRemovedWindowText, bob.peerId),
          0,
        );

        await bob.addMember(groupId: groupId, invitee: charlie);
        await bob.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(
          () async =>
              (await alice.groupRepo.getMember(groupId, charlie.peerId)) !=
                  null &&
              (await charlie.groupRepo.getGroup(groupId)) != null,
        );

        const aliceAfterReaddText = 'ML-020 Alice after Charlie re-add';
        const bobAfterReaddText = 'ML-020 Bob after Charlie re-add';
        const charlieAfterReaddText = 'ML-020 Charlie after role re-add';
        await alice.sendGroupMessage(
          groupId: groupId,
          text: aliceAfterReaddText,
        );
        await bob.sendGroupMessage(groupId: groupId, text: bobAfterReaddText);
        await charlie.sendGroupMessage(
          groupId: groupId,
          text: charlieAfterReaddText,
        );
        await pump();

        expect(
          await incomingTextCount(bob, aliceAfterReaddText, alice.peerId),
          1,
        );
        expect(
          await incomingTextCount(charlie, aliceAfterReaddText, alice.peerId),
          1,
        );
        expect(
          await incomingTextCount(alice, bobAfterReaddText, bob.peerId),
          1,
        );
        expect(
          await incomingTextCount(charlie, bobAfterReaddText, bob.peerId),
          1,
        );
        expect(
          await incomingTextCount(alice, charlieAfterReaddText, charlie.peerId),
          1,
        );
        expect(
          await incomingTextCount(bob, charlieAfterReaddText, charlie.peerId),
          1,
        );

        for (final user in [alice, bob, charlie]) {
          final roles = await rolesFor(user);
          expect(roles[alice.peerId], MemberRole.writer);
          expect(roles[bob.peerId], MemberRole.admin);
          expect(roles[charlie.peerId], MemberRole.writer);
        }

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'concurrent admin changes converge to one final member/admin map',
      () async {
        const groupId = 'grp-admin-converge-006';
        final createdAt = DateTime.parse('2026-04-05T12:09:56.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-04-05T12:09:57.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-04-05T12:09:58.000Z',
        ).toUtc();
        final dianaJoinedAt = DateTime.parse(
          '2026-04-05T12:09:59.000Z',
        ).toUtc();
        const initialPromoteAt = '2026-04-05T12:10:00.000Z';
        const promoteAt = '2026-04-05T12:10:01.000Z';
        const removeAt = '2026-04-05T12:10:02.000Z';
        final initialPromoteAtTime = DateTime.parse(initialPromoteAt).toUtc();
        final promoteAtTime = DateTime.parse(promoteAt).toUtc();
        final removeAtTime = DateTime.parse(removeAt).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        await admin.createGroup(
          groupId: groupId,
          name: 'Concurrent Admin',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: diana,
          joinedAt: dianaJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: initialPromoteAtTime,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.admin,
          changedAt: promoteAtTime,
        );
        await pump();

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: diana.peerId,
          memberUsername: diana.username,
          removedAt: removeAtTime,
        );
        await pump();

        Future<void> expectCanonicalState(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final roles = {
            for (final member in members) member.peerId: member.role,
          };
          expect(roles, {
            'peer-admin': MemberRole.admin,
            'peer-bob': MemberRole.admin,
            'peer-charlie': MemberRole.admin,
          });
          expect(
            (await user.groupRepo.getGroup(groupId))!.lastMembershipEventAt,
            DateTime.parse(removeAt).toUtc(),
          );
        }

        await expectCanonicalState(admin);
        await expectCanonicalState(bob);
        await expectCanonicalState(charlie);

        expect(await diana.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, diana.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'GE-016 two admins mutate membership concurrently and converge',
      () async {
        const groupId = 'grp-ge016-concurrent-admins';
        final createdAt = DateTime.parse('2026-05-14T04:36:00.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-05-14T04:36:01.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-05-14T04:36:02.000Z',
        ).toUtc();
        final dianaJoinedAt = DateTime.parse(
          '2026-05-14T04:36:03.000Z',
        ).toUtc();
        final bobAdminAt = DateTime.parse('2026-05-14T04:36:04.000Z').toUtc();
        final promoteCharlieAt = DateTime.parse(
          '2026-05-14T04:36:05.000Z',
        ).toUtc();
        final removeDianaAt = DateTime.parse(
          '2026-05-14T04:36:06.000Z',
        ).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-ge016-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ge016-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ge016-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-ge016-diana',
          username: 'Diana',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
          diana.dispose();
        });

        await admin.createGroup(
          groupId: groupId,
          name: 'GE016 Concurrent Admins',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: diana,
          joinedAt: dianaJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: bobAdminAt,
        );
        await pump();

        for (final user in [admin, bob, charlie, diana]) {
          network.holdDeliveriesFor(user.peerId);
        }

        await Future.wait([
          admin.updateMemberRole(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            role: MemberRole.admin,
            changedAt: promoteCharlieAt,
          ),
          bob.removeMember(
            groupId: groupId,
            memberPeerId: diana.peerId,
            memberUsername: diana.username,
            removedAt: removeDianaAt,
          ),
        ]);

        await network.releaseHeldDeliveriesFor(charlie.peerId, reverse: true);
        await network.releaseHeldDeliveriesFor(admin.peerId);
        await network.releaseHeldDeliveriesFor(bob.peerId, reverse: true);
        await network.releaseHeldDeliveriesFor(diana.peerId, reverse: true);
        await pump();

        Future<void> expectConverged(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: user.username);
          expect(
            group!.lastMembershipEventAt,
            removeDianaAt,
            reason: user.username,
          );
          final roles = {
            for (final member in await user.groupRepo.getMembers(groupId))
              member.peerId: member.role,
          };
          expect(roles, {
            admin.peerId: MemberRole.admin,
            bob.peerId: MemberRole.admin,
            charlie.peerId: MemberRole.writer,
          }, reason: user.username);
        }

        await expectConverged(admin);
        await expectConverged(bob);
        await expectConverged(charlie);
        expect(await diana.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, diana.peerId), isFalse);
      },
    );

    test(
      'ML-012 concurrent admin remove and add converge after held delivery orders',
      () async {
        Future<Set<String>> memberIds(
          GroupTestUser user,
          String groupId,
        ) async {
          final members = await user.groupRepo.getMembers(groupId);
          return members.map((member) => member.peerId).toSet();
        }

        Set<String> latestSyncedMembers(FakeBridge bridge, String groupId) {
          for (final raw in bridge.sentMessages.reversed) {
            final decoded = jsonDecode(raw) as Map<String, dynamic>;
            if (decoded['cmd'] != 'group:updateConfig') {
              continue;
            }
            final payload = decoded['payload'] as Map<String, dynamic>;
            if (payload['groupId'] != groupId) {
              continue;
            }
            final config = payload['groupConfig'] as Map<String, dynamic>;
            final members = config['members'] as List<dynamic>;
            return members
                .whereType<Map<String, dynamic>>()
                .map((member) => member['peerId'] as String)
                .toSet();
          }
          return const <String>{};
        }

        Future<void> runScenario({
          required String suffix,
          required bool reverseObserverDelivery,
        }) async {
          final groupId = 'grp-ml012-concurrent-$suffix';
          final createdAt = DateTime.parse('2026-04-05T12:39:56.000Z').toUtc();
          final bobJoinedAt = DateTime.parse(
            '2026-04-05T12:39:57.000Z',
          ).toUtc();
          final charlieJoinedAt = DateTime.parse(
            '2026-04-05T12:39:58.000Z',
          ).toUtc();
          final observerJoinedAt = DateTime.parse(
            '2026-04-05T12:39:59.000Z',
          ).toUtc();
          final bobAdminAt = DateTime.parse('2026-04-05T12:40:00.000Z').toUtc();
          final addDanaAt = DateTime.parse('2026-04-05T12:40:01.000Z').toUtc();
          final removeCharlieAt = DateTime.parse(
            '2026-04-05T12:40:02.000Z',
          ).toUtc();

          final alice = GroupTestUser.create(
            peerId: 'peer-ml012-alice-$suffix',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'peer-ml012-bob-$suffix',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'peer-ml012-charlie-$suffix',
            username: 'Charlie',
            network: network,
          );
          final dana = GroupTestUser.create(
            peerId: 'peer-ml012-dana-$suffix',
            username: 'Dana',
            network: network,
          );
          final observer = GroupTestUser.create(
            peerId: 'peer-ml012-observer-$suffix',
            username: 'Observer',
            network: network,
          );
          addTearDown(() {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
            dana.dispose();
            observer.dispose();
          });

          await alice.createGroup(
            groupId: groupId,
            name: 'ML-012 Concurrent',
            createdAt: createdAt,
          );
          await alice.addMember(
            groupId: groupId,
            invitee: bob,
            joinedAt: bobJoinedAt,
          );
          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: charlieJoinedAt,
          );
          await alice.addMember(
            groupId: groupId,
            invitee: observer,
            joinedAt: observerJoinedAt,
          );

          alice.start();
          bob.start();
          charlie.start();
          dana.start();
          observer.start();

          await alice.updateMemberRole(
            groupId: groupId,
            memberPeerId: bob.peerId,
            role: MemberRole.admin,
            changedAt: bobAdminAt,
          );
          await pump();

          network.holdDeliveriesFor(observer.peerId);

          await bob.addMember(
            groupId: groupId,
            invitee: dana,
            joinedAt: addDanaAt,
          );
          await bob.broadcastMemberAdded(
            groupId: groupId,
            newMember: dana,
            eventAt: addDanaAt,
          );
          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: removeCharlieAt,
          );
          await pump();

          await network.releaseHeldDeliveriesFor(
            observer.peerId,
            reverse: reverseObserverDelivery,
          );
          await waitUntil(() async {
            final expected = {
              alice.peerId,
              bob.peerId,
              dana.peerId,
              observer.peerId,
            };
            final observerMembers = await memberIds(observer, groupId);
            final bobMembers = await memberIds(bob, groupId);
            final aliceMembers = await memberIds(alice, groupId);
            return observerMembers.length == expected.length &&
                observerMembers.containsAll(expected) &&
                bobMembers.length == expected.length &&
                bobMembers.containsAll(expected) &&
                aliceMembers.length == expected.length &&
                aliceMembers.containsAll(expected);
          }, maxTicks: 30);

          final expected = {
            alice.peerId,
            bob.peerId,
            dana.peerId,
            observer.peerId,
          };
          expect(await memberIds(alice, groupId), expected);
          expect(await memberIds(bob, groupId), expected);
          expect(await memberIds(dana, groupId), expected);
          expect(await memberIds(observer, groupId), expected);
          expect(await charlie.groupRepo.getGroup(groupId), isNull);
          expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
          expect(latestSyncedMembers(observer.bridge, groupId), expected);
        }

        await runScenario(
          suffix: 'add-then-remove',
          reverseObserverDelivery: false,
        );
        await runScenario(
          suffix: 'remove-then-add',
          reverseObserverDelivery: true,
        );
      },
    );

    test(
      'conflicting remove and promote of the same member converge to removal',
      () async {
        const groupId = 'grp-admin-conflict-007';
        final createdAt = DateTime.parse('2026-04-05T12:19:56.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-04-05T12:19:57.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-04-05T12:19:58.000Z',
        ).toUtc();
        const initialPromoteAt = '2026-04-05T12:20:00.000Z';
        const promoteAt = '2026-04-05T12:20:01.000Z';
        const removeAt = '2026-04-05T12:20:02.000Z';
        final initialPromoteAtTime = DateTime.parse(initialPromoteAt).toUtc();
        final promoteAtTime = DateTime.parse(promoteAt).toUtc();
        final removeAtTime = DateTime.parse(removeAt).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(
          groupId: groupId,
          name: 'Conflict Admin',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: initialPromoteAtTime,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.admin,
          changedAt: promoteAtTime,
        );
        await pump();

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeAtTime,
        );
        await pump();

        Future<void> expectRemovalWinner(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final roles = {
            for (final member in members) member.peerId: member.role,
          };
          expect(roles, {
            'peer-admin': MemberRole.admin,
            'peer-bob': MemberRole.admin,
          });
          expect(
            (await user.groupRepo.getGroup(groupId))!.lastMembershipEventAt,
            DateTime.parse(removeAt).toUtc(),
          );
        }

        await expectRemovalWinner(admin);
        await expectRemovalWinner(bob);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'RP018 partitioned add remove promote demote replay converges membership',
      () async {
        const groupId = 'grp-rp018-membership-conflict';
        final createdAt = DateTime.parse('2026-04-05T12:29:56.000Z').toUtc();
        final bobJoinedAt = DateTime.parse('2026-04-05T12:29:57.000Z').toUtc();
        final charlieJoinedAt = DateTime.parse(
          '2026-04-05T12:29:58.000Z',
        ).toUtc();
        final observerJoinedAt = DateTime.parse(
          '2026-04-05T12:29:59.000Z',
        ).toUtc();
        final bobAdminAt = DateTime.parse('2026-04-05T12:30:00.000Z').toUtc();
        final addDianaAt = DateTime.parse('2026-04-05T12:30:01.000Z').toUtc();
        final promoteCharlieAt = DateTime.parse(
          '2026-04-05T12:30:02.000Z',
        ).toUtc();
        final removeCharlieAt = DateTime.parse(
          '2026-04-05T12:30:03.000Z',
        ).toUtc();
        final staleDemoteCharlieAt = DateTime.parse(
          '2026-04-05T12:30:04.000Z',
        ).toUtc();

        final admin = GroupTestUser.create(
          peerId: 'peer-rp018-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-rp018-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-rp018-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-rp018-diana',
          username: 'Diana',
          network: network,
        );
        final observer = GroupTestUser.create(
          peerId: 'peer-rp018-observer',
          username: 'Observer',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
          diana.dispose();
          observer.dispose();
        });

        Future<Map<String, dynamic>> groupConfigFrom(
          GroupTestUser owner,
        ) async {
          final group = await owner.groupRepo.getGroup(groupId);
          final members = await owner.groupRepo.getMembers(groupId);
          return {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': members
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role.toValue(),
                    'publicKey': member.publicKey,
                  },
                )
                .toList(),
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          };
        }

        Future<Map<String, dynamic>> membershipEnvelope({
          required GroupTestUser sender,
          required String systemType,
          required Map<String, dynamic> member,
          required DateTime eventAt,
        }) async {
          final payload = {
            '__sys': systemType,
            'member': member,
            if (systemType == 'member_removed')
              'removedAt': eventAt.toIso8601String(),
            'groupConfig': await groupConfigFrom(sender),
          };
          return {
            'groupId': groupId,
            'senderId': sender.peerId,
            'senderUsername': sender.username,
            'keyEpoch': 0,
            'text': jsonEncode(payload),
            'timestamp': eventAt.toIso8601String(),
          };
        }

        Future<Map<String, String>> roleMap(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          return {
            for (final member in members) member.peerId: member.role.toValue(),
          };
        }

        Future<void> expectConverged(GroupTestUser user) async {
          expect(await roleMap(user), {
            admin.peerId: 'admin',
            bob.peerId: 'admin',
            diana.peerId: 'writer',
            observer.peerId: 'writer',
          });
        }

        await admin.createGroup(
          groupId: groupId,
          name: 'RP018 Conflicts',
          createdAt: createdAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieJoinedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: observer,
          joinedAt: observerJoinedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        observer.start();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: bob.peerId,
          role: MemberRole.admin,
          changedAt: bobAdminAt,
        );
        await pump();

        network.unsubscribe(groupId, observer.peerId);

        await admin.addMember(
          groupId: groupId,
          invitee: diana,
          joinedAt: addDianaAt,
        );
        diana.start();
        final addDianaEnvelope = await membershipEnvelope(
          sender: admin,
          systemType: 'member_added',
          member: {
            'peerId': diana.peerId,
            'username': diana.username,
            'role': 'writer',
            'publicKey': diana.publicKey,
          },
          eventAt: addDianaAt,
        );
        await network.publish(
          groupId,
          admin.peerId,
          addDianaEnvelope,
          senderDeviceId: admin.deviceId,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.admin,
          changedAt: promoteCharlieAt,
        );
        await pump();

        network.unsubscribe(groupId, admin.peerId);

        await bob.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeCharlieAt,
        );
        final removeCharlieEnvelope = await membershipEnvelope(
          sender: bob,
          systemType: 'member_removed',
          member: {'peerId': charlie.peerId, 'username': charlie.username},
          eventAt: removeCharlieAt,
        );
        await pump();

        await admin.updateMemberRole(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          role: MemberRole.writer,
          changedAt: staleDemoteCharlieAt,
        );
        final staleDemoteEnvelope = await membershipEnvelope(
          sender: admin,
          systemType: 'member_role_updated',
          member: {
            'peerId': charlie.peerId,
            'username': charlie.username,
            'role': 'writer',
            'publicKey': charlie.publicKey,
          },
          eventAt: staleDemoteCharlieAt,
        );
        await pump();

        network.subscribe(groupId, observer.peerId);
        network.subscribe(groupId, admin.peerId);

        await network.publish(
          groupId,
          admin.peerId,
          staleDemoteEnvelope,
          senderDeviceId: admin.deviceId,
        );
        await pump();

        await network.publish(
          groupId,
          bob.peerId,
          removeCharlieEnvelope,
          senderDeviceId: bob.deviceId,
        );
        await pump();

        await expectConverged(admin);
        await expectConverged(bob);
        await expectConverged(diana);
        await expectConverged(observer);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
      },
    );

    // -----------------------------------------------------------------------
    // 5. Removed member loses send permission after self-removal cleanup.
    // -----------------------------------------------------------------------
    test('removed member cannot send after self-removal cleanup', () async {
      const groupId = 'grp-remove-send-004';

      final admin = GroupTestUser.create(
        peerId: 'peer-admin',
        username: 'Admin',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-charlie',
        username: 'Charlie',
        network: network,
      );

      await admin.createGroup(groupId: groupId, name: 'Test Group');
      await admin.addMember(groupId: groupId, invitee: bob);
      await admin.addMember(groupId: groupId, invitee: charlie);

      admin.start();
      bob.start();
      charlie.start();

      await admin.removeMember(
        groupId: groupId,
        memberPeerId: bob.peerId,
        memberUsername: 'Bob',
      );
      await pump();

      final (result, message) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: 'Should not send',
      );

      expect(result, group_send.SendGroupMessageResult.groupNotFound);
      expect(message, isNull);
      expect(await bob.groupRepo.getGroup(groupId), isNull);
      expect(await bob.msgRepo.getMessageCount(groupId), 0);
      expect(
        bob.bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
      );

      final adminIncoming = (await admin.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();
      final charlieIncoming = (await charlie.loadGroupMessages(
        groupId,
      )).where((entry) => entry.isIncoming).toList();

      expect(
        adminIncoming.where((entry) => entry.text == 'Should not send'),
        isEmpty,
      );
      expect(
        charlieIncoming.where((entry) => entry.text == 'Should not send'),
        isEmpty,
      );

      admin.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test(
      'GM-004 removes C while online, rotates key, A/B continue, and C loses access',
      () async {
        const groupId = 'grp-gm004-remove-online';
        const initialKey = 'gm004-initial-key';
        const rotatedKeyValue = 'gm004-rotated-key';
        const aliceAfterRemoval = 'GM-004 Alice after Charlie removal';
        const bobAfterRemoval = 'GM-004 Bob after Charlie removal';
        const charlieAfterRemoval = 'GM-004 Charlie should not send';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-gm004-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm004-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm004-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'GM-004 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, alice.peerId), isTrue);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rotatedKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, rotatedKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));

        await bob.groupRepo.saveKey(rotatedKey);

        Future<void> expectRemainingMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} still has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
          });
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rotatedKeyValue);
        }

        await expectRemainingMemberState(alice);
        await expectRemainingMemberState(bob);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterRemoval,
              messageId: 'gm004-alice-after-removal',
            );
        final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterRemoval,
          messageId: 'gm004-bob-after-removal',
        );

        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(bobSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        expect(bobMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(aliceAfterRemoval) &&
              aliceTexts.contains(bobAfterRemoval);
        }, maxTicks: 40);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterRemoval,
              messageId: 'gm004-charlie-after-removal',
            );
        expect(
          charlieSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(charlieMessage, isNull);
        expect(
          charlie.bridge.commandLog.where(
            (command) => command == 'group:publish',
          ),
          isEmpty,
        );

        final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();

        expect(aliceIncomingTexts, contains(bobAfterRemoval));
        expect(bobIncomingTexts, contains(aliceAfterRemoval));
        expect(charlieTexts, isNot(contains(aliceAfterRemoval)));
        expect(charlieTexts, isNot(contains(bobAfterRemoval)));
        expect(charlieTexts, isNot(contains(charlieAfterRemoval)));
      },
    );

    test(
      'ML-005 online removed member converges removed while remaining members keep delivery',
      () async {
        const groupId = 'grp-ml005-remove-online';
        const initialKey = 'ml005-initial-key';
        const rotatedKeyValue = 'ml005-rotated-key';
        const aliceAfterRemoval = 'ML-005 Alice after Charlie removal';
        const bobAfterRemoval = 'ML-005 Bob after Charlie removal';
        const charlieAfterRemoval = 'ML-005 Charlie should not send';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-ml005-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml005-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml005-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'ML-005 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, alice.peerId), isTrue);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rotatedKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, rotatedKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));

        await bob.groupRepo.saveKey(rotatedKey);

        Future<void> expectRemainingMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} still has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
          });
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rotatedKeyValue);
        }

        await expectRemainingMemberState(alice);
        await expectRemainingMemberState(bob);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterRemoval,
              messageId: 'ml005-alice-after-removal',
            );
        final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterRemoval,
          messageId: 'ml005-bob-after-removal',
        );

        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(bobSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        expect(bobMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(aliceAfterRemoval) &&
              aliceTexts.contains(bobAfterRemoval);
        }, maxTicks: 40);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterRemoval,
              messageId: 'ml005-charlie-after-removal',
            );
        expect(
          charlieSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(charlieMessage, isNull);
        expect(
          charlie.bridge.commandLog.where(
            (command) => command == 'group:publish',
          ),
          isEmpty,
        );

        final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text);
        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();

        expect(aliceIncomingTexts, contains(bobAfterRemoval));
        expect(bobIncomingTexts, contains(aliceAfterRemoval));
        expect(charlieTexts, isNot(contains(aliceAfterRemoval)));
        expect(charlieTexts, isNot(contains(bobAfterRemoval)));
        expect(charlieTexts, isNot(contains(charlieAfterRemoval)));
      },
    );

    test(
      'GM-005 removes C while offline, C catches up removed, cannot access post-removal content, and A/B delivery continues',
      () async {
        const groupId = 'grp-gm005-remove-offline';
        const initialKey = 'gm005-initial-key';
        const rotatedKeyValue = 'gm005-rotated-key';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-gm005-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm005-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm005-charlie',
          username: 'Charlie',
          network: network,
          bridge: cursorBridge(),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'GM-005 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNotNull);
        charlie.unsubscribeFromGroup(groupId);
        alice.start();
        bob.start();
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rotatedKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rotatedKey);

        final postRemovalTexts = <String>[
          'GM-005 Alice after offline Charlie removal 1',
          'GM-005 Alice after offline Charlie removal 2',
          'GM-005 Alice after offline Charlie removal 3',
        ];
        final sentMessages = <GroupMessage>[];
        for (var i = 0; i < postRemovalTexts.length; i++) {
          final (sendResult, sentMessage) = await alice
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: postRemovalTexts[i],
                messageId: 'gm005-alice-after-removal-${i + 1}',
                timestamp: removedAt.add(Duration(minutes: i + 1)),
              );
          expect(sendResult, group_send.SendGroupMessageResult.success);
          expect(sentMessage, isNotNull);
          expect(sentMessage!.keyGeneration, 2);
          sentMessages.add(sentMessage);
        }

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toList();
          return postRemovalTexts.every(
            (text) => bobTexts.where((seen) => seen == text).length == 1,
          );
        }, maxTicks: 40);
        final bobMessages = await bob.loadGroupMessages(groupId);
        for (final text in postRemovalTexts) {
          expect(
            bobMessages.where((message) => message.text == text),
            hasLength(1),
          );
        }

        final group = await alice.groupRepo.getGroup(groupId);
        final remainingMembers = await alice.groupRepo.getMembers(groupId);
        final groupConfig = {
          'name': group!.name,
          'groupType': group.type.toValue(),
          if (group.description != null) 'description': group.description,
          'members': remainingMembers
              .map((member) => member.toConfigJson())
              .toList(),
          'createdBy': group.createdBy,
          'createdAt': group.createdAt.toUtc().toIso8601String(),
        };
        final removalText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charlie.peerId, 'username': charlie.username},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': groupConfig,
        });

        Future<Map<String, dynamic>> signedReplay({
          required String id,
          required String text,
          required DateTime timestamp,
          required GroupKeyInfo keyInfo,
        }) async {
          final envelope = await buildGroupOfflineReplayEnvelope(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode({
              'groupId': groupId,
              'senderId': alice.peerId,
              'senderUsername': alice.username,
              'senderDeviceId': alice.deviceId,
              'transportPeerId': alice.deviceId,
              'keyEpoch': keyInfo.keyGeneration,
              'text': text,
              'timestamp': timestamp.toUtc().toIso8601String(),
              'messageId': id,
            }),
            messageId: id,
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderDeviceId: alice.deviceId,
            senderTransportPeerId: alice.deviceId,
            keyInfo: keyInfo,
          );
          return {
            'from': alice.peerId,
            'message': envelope,
            'timestamp': timestamp.millisecondsSinceEpoch,
          };
        }

        final bridge = charlie.bridge as _GroupMembershipCursorBridge;
        bridge.addPage(
          groupId: groupId,
          cursor: '',
          messages: [
            await signedReplay(
              id: 'gm005-member-removed',
              text: removalText,
              timestamp: removedAt,
              keyInfo: GroupKeyInfo(
                groupId: groupId,
                keyGeneration: 1,
                encryptedKey: initialKey,
                createdAt: initialKeyCreatedAt,
              ),
            ),
            for (final message in sentMessages)
              await signedReplay(
                id: message.id,
                text: message.text,
                timestamp: message.timestamp,
                keyInfo: rotatedKey,
              ),
          ],
        );

        charlie.start();
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        final charlieLatestKey = await charlie.groupRepo.getLatestKey(groupId);
        expect(
          charlieLatestKey?.keyGeneration ?? 0,
          lessThan(rotatedKey.keyGeneration),
        );
        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        for (final text in postRemovalTexts) {
          expect(charlieTexts, isNot(contains(text)));
        }

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GM-005 Charlie should not send',
              messageId: 'gm005-charlie-after-removal',
            );
        expect(
          charlieSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(charlieMessage, isNull);
        expect(
          charlie.bridge.commandLog.where(
            (command) => command == 'group:publish',
          ),
          isEmpty,
        );
      },
    );

    test(
      'ML-006 offline removed member converges removed after reconnect and cannot read A/B post-removal messages',
      () async {
        const groupId = 'grp-ml006-remove-offline';
        const initialKey = 'ml006-initial-key';
        const rotatedKeyValue = 'ml006-rotated-key';
        const aliceAfterRemoval = 'ML-006 Alice after offline Charlie removal';
        const bobAfterRemoval = 'ML-006 Bob after offline Charlie removal';
        const charlieAfterRemoval = 'ML-006 Charlie should not send';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-ml006-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml006-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml006-charlie',
          username: 'Charlie',
          network: network,
          bridge: cursorBridge(),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'ML-006 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNotNull);
        charlie.unsubscribeFromGroup(groupId);
        alice.start();
        bob.start();
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rotatedKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, rotatedKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rotatedKey);

        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterRemoval,
              messageId: 'ml006-alice-after-removal',
              timestamp: removedAt.add(const Duration(minutes: 1)),
            );
        final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterRemoval,
          messageId: 'ml006-bob-after-removal',
          timestamp: removedAt.add(const Duration(minutes: 2)),
        );
        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(bobSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        expect(bobMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(aliceAfterRemoval) &&
              aliceTexts.contains(bobAfterRemoval);
        }, maxTicks: 40);

        final group = await alice.groupRepo.getGroup(groupId);
        final remainingMembers = await alice.groupRepo.getMembers(groupId);
        final groupConfig = {
          'name': group!.name,
          'groupType': group.type.toValue(),
          if (group.description != null) 'description': group.description,
          'members': remainingMembers
              .map((member) => member.toConfigJson())
              .toList(),
          'createdBy': group.createdBy,
          'createdAt': group.createdAt.toUtc().toIso8601String(),
        };
        final removalText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charlie.peerId, 'username': charlie.username},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': groupConfig,
        });

        Future<Map<String, dynamic>> signedReplay({
          required GroupTestUser sender,
          required String id,
          required String text,
          required DateTime timestamp,
          required GroupKeyInfo keyInfo,
        }) async {
          final envelope = await buildGroupOfflineReplayEnvelope(
            bridge: sender.bridge,
            groupRepo: sender.groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode({
              'groupId': groupId,
              'senderId': sender.peerId,
              'senderUsername': sender.username,
              'senderDeviceId': sender.deviceId,
              'transportPeerId': sender.deviceId,
              'keyEpoch': keyInfo.keyGeneration,
              'text': text,
              'timestamp': timestamp.toUtc().toIso8601String(),
              'messageId': id,
            }),
            messageId: id,
            senderPeerId: sender.peerId,
            senderPublicKey: sender.publicKey,
            senderPrivateKey: sender.privateKey,
            senderDeviceId: sender.deviceId,
            senderTransportPeerId: sender.deviceId,
            keyInfo: keyInfo,
          );
          return {
            'from': sender.deviceId,
            'message': envelope,
            'timestamp': timestamp.millisecondsSinceEpoch,
          };
        }

        final bridge = charlie.bridge as _GroupMembershipCursorBridge;
        bridge.addPage(
          groupId: groupId,
          cursor: '',
          messages: [
            await signedReplay(
              sender: alice,
              id: 'ml006-member-removed',
              text: removalText,
              timestamp: removedAt,
              keyInfo: GroupKeyInfo(
                groupId: groupId,
                keyGeneration: 1,
                encryptedKey: initialKey,
                createdAt: initialKeyCreatedAt,
              ),
            ),
            await signedReplay(
              sender: alice,
              id: aliceMessage.id,
              text: aliceMessage.text,
              timestamp: aliceMessage.timestamp,
              keyInfo: rotatedKey,
            ),
            await signedReplay(
              sender: bob,
              id: bobMessage.id,
              text: bobMessage.text,
              timestamp: bobMessage.timestamp,
              keyInfo: rotatedKey,
            ),
          ],
        );

        charlie.start();
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        final charlieLatestKey = await charlie.groupRepo.getLatestKey(groupId);
        expect(
          charlieLatestKey?.keyGeneration ?? 0,
          lessThan(rotatedKey.keyGeneration),
        );
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, isNot(contains(aliceAfterRemoval)));
        expect(charlieTexts, isNot(contains(bobAfterRemoval)));
        expect(charlieTexts, isNot(contains(charlieAfterRemoval)));

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterRemoval,
              messageId: 'ml006-charlie-after-removal',
            );
        expect(
          charlieSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(charlieMessage, isNull);
        expect(
          charlie.bridge.commandLog.where(
            (command) => command == 'group:publish',
          ),
          isEmpty,
        );
      },
    );

    test(
      'GM-006 removes and immediately re-adds C with current epoch and accepts only post-readd traffic',
      () async {
        const groupId = 'grp-gm006-immediate-readd';
        const initialKey = 'gm006-initial-key';
        const rejoinKeyValue = 'gm006-rejoin-key';
        const aliceDuringRemoval = 'GM-006 Alice during Charlie removal';
        const charlieAfterReadd = 'GM-006 Charlie after immediate readd';
        const aliceAfterReadd = 'GM-006 Alice after immediate readd';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm006-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm006-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm006-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'GM-006 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(rejoinKey.encryptedKey, rejoinKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        final (duringRemovalResult, duringRemovalMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceDuringRemoval,
              messageId: 'gm006-alice-during-removal',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(duringRemovalResult, group_send.SendGroupMessageResult.success);
        expect(duringRemovalMessage, isNotNull);
        expect(duringRemovalMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return bobTexts.contains(aliceDuringRemoval);
        }, maxTicks: 40);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(aliceDuringRemoval)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        Future<void> expectCurrentMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rejoinKeyValue);
        }

        await expectCurrentMemberState(alice);
        await expectCurrentMemberState(bob);
        await expectCurrentMemberState(charlie);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'gm006-charlie-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'gm006-alice-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );

        expect(charlieSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(aliceMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);
        expect(aliceMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final charlieIncomingTexts =
              (await charlie.loadGroupMessages(groupId))
                  .where((message) => message.isIncoming)
                  .map((message) => message.text)
                  .toSet();
          return aliceIncomingTexts.contains(charlieAfterReadd) &&
              bobIncomingTexts.contains(charlieAfterReadd) &&
              bobIncomingTexts.contains(aliceAfterReadd) &&
              charlieIncomingTexts.contains(aliceAfterReadd);
        }, maxTicks: 40);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, contains(charlieAfterReadd));
        expect(charlieTexts, contains(aliceAfterReadd));
        expect(charlieTexts, isNot(contains(aliceDuringRemoval)));
      },
    );

    test(
      'RA-002 online subscribed removed member is re-added without restart',
      () async {
        const groupId = 'grp-ra002-online-readd';
        const initialKey = 'ra002-initial-key';
        const rejoinKeyValue = 'ra002-rejoin-key';
        const beforeRemoval = 'RA-002 Alice before Charlie removal';
        const duringRemoval = 'RA-002 Alice while Charlie remains subscribed';
        const aliceAfterReadd = 'RA-002 Alice after Charlie readd';
        const bobAfterReadd = 'RA-002 Bob after Charlie readd';
        const charlieAfterReadd = 'RA-002 Charlie after readd';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        final preRemovalMessageAt = DateTime.now().toUtc();

        final alice = GroupTestUser.create(
          peerId: 'peer-ra002-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra002-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra002-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'RA-002 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeRemoval,
              messageId: 'ra002-before-removal',
              timestamp: preRemovalMessageAt,
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        await waitUntil(() async {
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return charlieTexts.contains(beforeRemoval);
        }, maxTicks: 40);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        charlie.subscribeToGroup(groupId);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        final (duringResult, duringMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: duringRemoval,
              messageId: 'ra002-during-removal',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(duringResult, group_send.SendGroupMessageResult.success);
        expect(duringMessage, isNotNull);
        expect(duringMessage!.keyGeneration, 2);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return bobTexts.contains(duringRemoval);
        }, maxTicks: 40);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(duringRemoval)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'ra002-alice-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterReadd,
          messageId: 'ra002-bob-after-readd',
          timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
        );
        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'ra002-charlie-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 3)),
            );
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(bobResult, group_send.SendGroupMessageResult.success);
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage!.keyGeneration, 2);
        expect(bobMessage!.keyGeneration, 2);
        expect(charlieMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceIncomingTexts.contains(charlieAfterReadd) &&
              bobTexts.containsAll({duringRemoval, charlieAfterReadd}) &&
              charlieTexts.containsAll({aliceAfterReadd, bobAfterReadd}) &&
              !charlieTexts.contains(duringRemoval);
        }, maxTicks: 40);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, contains(beforeRemoval));
        expect(charlieTexts, contains(aliceAfterReadd));
        expect(charlieTexts, contains(bobAfterReadd));
        expect(charlieTexts, isNot(contains(duringRemoval)));
      },
    );

    test(
      'RA-007 partitioned observer misses removal but converges after re-add',
      () async {
        const groupId = 'grp-ra007-bob-partition-readd';
        const initialKey = 'ra007-initial-key';
        const rejoinKeyValue = 'ra007-rejoin-key';
        const beforeSplit = 'RA-007 before Bob partition';
        const removedWindow = 'RA-007 active Bob entitled removed-window';
        const aliceAfterHeal = 'RA-007 Alice after Bob heal';
        const charlieAfterHeal = 'RA-007 Charlie after Bob heal';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-ra007-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra007-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra007-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        await alice.createGroup(groupId: groupId, name: 'RA-007 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final bobMembers = await memberSet(bob);
          return bobMembers.contains(charlie.peerId);
        }, maxTicks: 40);

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeSplit,
              messageId: 'ra007-before-partition',
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return bobTexts.contains(beforeSplit) &&
              charlieTexts.contains(beforeSplit);
        }, maxTicks: 40);

        network.holdDeliveriesFor(bob.peerId);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final aliceMembers = await memberSet(alice);
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return !aliceMembers.contains(charlie.peerId) && charlieGroup == null;
        }, maxTicks: 40);

        expect(
          await bob.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        await bob.groupRepo.saveKey(rejoinKey!);

        final (removedWindowResult, removedWindowMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: removedWindow,
              messageId: 'ra007-removed-window',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedWindowResult, group_send.SendGroupMessageResult.success);
        expect(removedWindowMessage, isNotNull);
        expect(removedWindowMessage!.keyGeneration, 2);
        expect(
          (await bob.loadGroupMessages(groupId)).map((message) => message.text),
          isNot(contains(removedWindow)),
          reason: 'Bob is partitioned from live delivery before heal',
        );
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(removedWindow)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final aliceMembers = await memberSet(alice);
          final charlieMembers = await memberSet(charlie);
          return aliceMembers.contains(charlie.peerId) &&
              charlieMembers.containsAll({
                alice.peerId,
                bob.peerId,
                charlie.peerId,
              });
        }, maxTicks: 40);

        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(3),
        );
        await network.releaseHeldDeliveriesFor(bob.peerId, reverse: true);
        await waitUntil(() async {
          final bobMembers = await memberSet(bob);
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobMembers.containsAll({
                alice.peerId,
                bob.peerId,
                charlie.peerId,
              }) &&
              bobTexts.contains(removedWindow);
        }, maxTicks: 40);

        final (aliceAfterResult, aliceAfterMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterHeal,
              messageId: 'ra007-alice-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (charlieAfterResult, charlieAfterMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterHeal,
              messageId: 'ra007-charlie-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        expect(aliceAfterResult, group_send.SendGroupMessageResult.success);
        expect(charlieAfterResult, group_send.SendGroupMessageResult.success);
        expect(aliceAfterMessage!.keyGeneration, 2);
        expect(charlieAfterMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.containsAll({
                beforeSplit,
                removedWindow,
                aliceAfterHeal,
                charlieAfterHeal,
              }) &&
              aliceTexts.contains(charlieAfterHeal) &&
              charlieTexts.contains(aliceAfterHeal) &&
              !charlieTexts.contains(removedWindow);
        }, maxTicks: 40);

        expect(await memberSet(bob), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
      },
    );

    test(
      'RA-008 removed peer misses removal but cannot read removed-window after re-add',
      () async {
        const groupId = 'grp-ra008-charlie-partition-readd';
        const initialKey = 'ra008-initial-key';
        const rejoinKeyValue = 'ra008-rejoin-key';
        const beforeSplit = 'RA-008 before Charlie partition';
        const removedWindow = 'RA-008 removed-window while Charlie partitioned';
        const aliceAfterHeal = 'RA-008 Alice after Charlie heal';
        const bobAfterHeal = 'RA-008 Bob after Charlie heal';
        const charlieAfterHeal = 'RA-008 Charlie after heal';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-ra008-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra008-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra008-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        await alice.createGroup(groupId: groupId, name: 'RA-008 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final bobMembers = await memberSet(bob);
          final charlieMembers = await memberSet(charlie);
          return bobMembers.containsAll(expectedMembers) &&
              charlieMembers.containsAll(expectedMembers);
        }, maxTicks: 40);

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeSplit,
              messageId: 'ra008-before-partition',
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return bobTexts.contains(beforeSplit) &&
              charlieTexts.contains(beforeSplit);
        }, maxTicks: 40);

        network.holdDeliveriesFor(charlie.peerId);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final aliceMembers = await memberSet(alice);
          final bobMembers = await memberSet(bob);
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return !aliceMembers.contains(charlie.peerId) &&
              !bobMembers.contains(charlie.peerId) &&
              charlieGroup != null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        await bob.groupRepo.saveKey(rejoinKey!);

        final (removedWindowResult, removedWindowMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: removedWindow,
              messageId: 'ra008-removed-window',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedWindowResult, group_send.SendGroupMessageResult.success);
        expect(removedWindowMessage, isNotNull);
        expect(removedWindowMessage!.keyGeneration, 2);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(removedWindow);
        }, maxTicks: 40);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(removedWindow)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final aliceMembers = await memberSet(alice);
          final bobMembers = await memberSet(bob);
          return aliceMembers.containsAll(expectedMembers) &&
              bobMembers.containsAll(expectedMembers);
        }, maxTicks: 40);

        expect(
          network.heldDeliveryCountFor(charlie.peerId),
          greaterThanOrEqualTo(2),
        );
        await network.releaseHeldDeliveriesFor(charlie.peerId, reverse: true);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final charlieMembers = await memberSet(charlie);
          final latestKey = await charlie.groupRepo.getLatestKey(groupId);
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return charlieMembers.containsAll(expectedMembers) &&
              latestKey?.keyGeneration == 2 &&
              !charlieTexts.contains(removedWindow);
        }, maxTicks: 40);

        final (aliceAfterResult, aliceAfterMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterHeal,
              messageId: 'ra008-alice-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (bobAfterResult, bobAfterMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobAfterHeal,
              messageId: 'ra008-bob-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        final (charlieAfterResult, charlieAfterMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterHeal,
              messageId: 'ra008-charlie-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 3)),
            );
        expect(aliceAfterResult, group_send.SendGroupMessageResult.success);
        expect(bobAfterResult, group_send.SendGroupMessageResult.success);
        expect(charlieAfterResult, group_send.SendGroupMessageResult.success);
        expect(aliceAfterMessage!.keyGeneration, 2);
        expect(bobAfterMessage!.keyGeneration, 2);
        expect(charlieAfterMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceIncomingTexts.contains(charlieAfterHeal) &&
              bobTexts.containsAll({removedWindow, charlieAfterHeal}) &&
              charlieTexts.containsAll({aliceAfterHeal, bobAfterHeal}) &&
              !charlieTexts.contains(removedWindow);
        }, maxTicks: 40);

        expect(await memberSet(charlie), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(removedWindow)),
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );
      },
    );

    test(
      'NW-003 Bob and Charlie partitioned from Alice during remove readd heal to latest state',
      () async {
        const groupId = 'grp-nw003-partition-remove-readd';
        const initialKey = 'nw003-initial-key';
        const rejoinKeyValue = 'nw003-rejoin-key';
        const beforeSplit = 'NW-003 before Bob and Charlie partition';
        const removedWindow =
            'NW-003 Alice removed-window while Bob and Charlie partitioned';
        const aliceAfterHeal = 'NW-003 Alice after heal';
        const bobAfterHeal = 'NW-003 Bob after heal';
        const charlieAfterHeal = 'NW-003 Charlie after heal';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));

        final alice = GroupTestUser.create(
          peerId: 'peer-nw003-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-nw003-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-nw003-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        Future<Set<String>> messageTexts(GroupTestUser user) async {
          return (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
        }

        Future<int> countText(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.text == text).length;
        }

        Map<String, dynamic> lastInboxPayload() {
          final raw = alice.bridge.sentMessages.lastWhere((message) {
            final parsed = jsonDecode(message) as Map<String, dynamic>;
            return parsed['cmd'] == 'group:inboxStore';
          });
          return (jsonDecode(raw) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
        }

        await alice.createGroup(groupId: groupId, name: 'NW-003 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: initialKeyCreatedAt.add(const Duration(seconds: 1)),
        );
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 60);

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeSplit,
              messageId: 'nw003-before-partition',
              timestamp: initialKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        await waitUntil(() async {
          return (await messageTexts(bob)).contains(beforeSplit) &&
              (await messageTexts(charlie)).contains(beforeSplit);
        }, maxTicks: 60);
        expect(await messageTexts(bob), contains(beforeSplit));
        expect(await messageTexts(charlie), contains(beforeSplit));

        network.holdDeliveriesFor(bob.peerId);
        network.holdDeliveriesFor(charlie.peerId);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(1),
        );
        expect(
          network.heldDeliveryCountFor(charlie.peerId),
          greaterThanOrEqualTo(1),
        );

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        await bob.groupRepo.saveKey(rejoinKey!);

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: removedWindow,
              messageId: 'nw003-removed-window',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedResult, group_send.SendGroupMessageResult.success);
        expect(removedMessage, isNotNull);
        expect(removedMessage!.keyGeneration, 2);
        expect(await countText(bob, removedWindow), 0);
        expect(await countText(charlie, removedWindow), 0);

        final inboxPayload = lastInboxPayload();
        expect(inboxPayload['recipientPeerIds'], [bob.peerId]);
        expect(
          inboxPayload['recipientPeerIds'],
          isNot(contains(charlie.peerId)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: rejoinKeyCreatedAt,
        );

        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(3),
        );
        expect(
          network.heldDeliveryCountFor(charlie.peerId),
          greaterThanOrEqualTo(2),
        );
        await network.releaseHeldDeliveriesFor(bob.peerId, reverse: true);
        await network.releaseHeldDeliveriesFor(charlie.peerId, reverse: true);

        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final bobKey = await bob.groupRepo.getLatestKey(groupId);
          final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers) &&
              bobKey?.keyGeneration == 2 &&
              charlieKey?.keyGeneration == 2 &&
              (await messageTexts(bob)).contains(removedWindow) &&
              !(await messageTexts(charlie)).contains(removedWindow);
        }, maxTicks: 80);

        expect(await countText(bob, removedWindow), 1);
        expect(await countText(charlie, removedWindow), 0);

        final (aliceAfterResult, aliceAfterMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterHeal,
              messageId: 'nw003-alice-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (bobAfterResult, bobAfterMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobAfterHeal,
              messageId: 'nw003-bob-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        final (charlieAfterResult, charlieAfterMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterHeal,
              messageId: 'nw003-charlie-after-heal',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 3)),
            );
        expect(aliceAfterResult, group_send.SendGroupMessageResult.success);
        expect(bobAfterResult, group_send.SendGroupMessageResult.success);
        expect(charlieAfterResult, group_send.SendGroupMessageResult.success);
        expect(aliceAfterMessage!.keyGeneration, 2);
        expect(bobAfterMessage!.keyGeneration, 2);
        expect(charlieAfterMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceTexts = await messageTexts(alice);
          final bobTexts = await messageTexts(bob);
          final charlieTexts = await messageTexts(charlie);
          return aliceTexts.containsAll({bobAfterHeal, charlieAfterHeal}) &&
              bobTexts.containsAll({
                removedWindow,
                aliceAfterHeal,
                charlieAfterHeal,
              }) &&
              charlieTexts.containsAll({aliceAfterHeal, bobAfterHeal}) &&
              !charlieTexts.contains(removedWindow);
        }, maxTicks: 80);

        final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
        expect(await memberSet(alice), expectedMembers);
        expect(await memberSet(bob), expectedMembers);
        expect(await memberSet(charlie), expectedMembers);
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );
        expect(await countText(bob, removedWindow), 1);
        expect(await countText(charlie, removedWindow), 0);
      },
    );

    test(
      'RA-009 first re-added publish reaches existing members after activation',
      () async {
        const groupId = 'grp-ra009-first-readd-publish';
        const initialKey = 'ra009-initial-key';
        const rejoinKeyValue = 'ra009-rejoin-key';
        const firstFromCharlie = 'RA-009 Charlie first publish after re-add';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-ra009-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra009-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra009-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        await alice.createGroup(groupId: groupId, name: 'RA-009 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);
        charlie.subscribeToGroup(groupId);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        await bob.groupRepo.saveKey(rejoinKey);

        network.holdDeliveriesFor(bob.peerId);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(alice)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers) &&
              !(await memberSet(bob)).contains(charlie.peerId);
        }, maxTicks: 40);

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: firstFromCharlie,
              messageId: 'ra009-charlie-first-readd-publish',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          return aliceIncomingTexts.contains(firstFromCharlie);
        }, maxTicks: 40);
        expect(
          (await bob.loadGroupMessages(groupId)).map((message) => message.text),
          isNot(contains(firstFromCharlie)),
        );
        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(2),
        );

        await network.releaseHeldDeliveriesFor(bob.peerId);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return (await memberSet(bob)).contains(charlie.peerId) &&
              bobTexts.contains(firstFromCharlie);
        }, maxTicks: 40);

        final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();
        final bobTexts = (await bob.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toList();
        expect(aliceIncomingTexts.where((text) => text == firstFromCharlie), [
          firstFromCharlie,
        ]);
        expect(bobTexts.where((text) => text == firstFromCharlie), [
          firstFromCharlie,
        ]);
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );
      },
    );

    test(
      'RA-003 offline removed member resolves removal before readd and receives only post-readd',
      () async {
        const groupId = 'grp-ra003-offline-readd';
        const initialKey = 'ra003-initial-key';
        const rejoinKeyValue = 'ra003-rejoin-key';
        const removedWindow =
            'RA-003 Alice removed-window while Charlie offline';
        const aliceAfterReadd = 'RA-003 Alice after offline Charlie readd';
        const bobAfterReadd = 'RA-003 Bob after offline Charlie readd';
        const charlieAfterReadd = 'RA-003 Charlie after offline readd';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));
        final rejoinKeyCreatedAt = removedAt.add(const Duration(minutes: 2));

        final alice = GroupTestUser.create(
          peerId: 'peer-ra003-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra003-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra003-charlie',
          username: 'Charlie',
          network: network,
          bridge: cursorBridge(),
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'RA-003 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        charlie.unsubscribeFromGroup(groupId);
        alice.start();
        bob.start();
        await pump();
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        final (removedWindowResult, removedWindowMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: removedWindow,
              messageId: 'ra003-removed-window',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedWindowResult, group_send.SendGroupMessageResult.success);
        expect(removedWindowMessage, isNotNull);
        expect(removedWindowMessage!.keyGeneration, 2);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(removedWindow);
        }, maxTicks: 40);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(removedWindow)),
        );

        final group = await alice.groupRepo.getGroup(groupId);
        final remainingMembers = await alice.groupRepo.getMembers(groupId);
        final groupConfig = {
          'name': group!.name,
          'groupType': group.type.toValue(),
          if (group.description != null) 'description': group.description,
          'members': remainingMembers
              .map((member) => member.toConfigJson())
              .toList(),
          'createdBy': group.createdBy,
          'createdAt': group.createdAt.toUtc().toIso8601String(),
        };
        final removalText = jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charlie.peerId, 'username': charlie.username},
          'removedAt': removedAt.toIso8601String(),
          'groupConfig': groupConfig,
        });

        Future<Map<String, dynamic>> signedReplay({
          required String id,
          required String text,
          required DateTime timestamp,
          required GroupKeyInfo keyInfo,
        }) async {
          final envelope = await buildGroupOfflineReplayEnvelope(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode({
              'groupId': groupId,
              'senderId': alice.peerId,
              'senderUsername': alice.username,
              'senderDeviceId': alice.deviceId,
              'transportPeerId': alice.deviceId,
              'keyEpoch': keyInfo.keyGeneration,
              'text': text,
              'timestamp': timestamp.toUtc().toIso8601String(),
              'messageId': id,
            }),
            messageId: id,
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderDeviceId: alice.deviceId,
            senderTransportPeerId: alice.deviceId,
            keyInfo: keyInfo,
          );
          return {
            'from': alice.peerId,
            'message': envelope,
            'timestamp': timestamp.millisecondsSinceEpoch,
          };
        }

        final bridge = charlie.bridge as _GroupMembershipCursorBridge;
        bridge.addPage(
          groupId: groupId,
          cursor: '',
          messages: [
            await signedReplay(
              id: 'ra003-member-removed',
              text: removalText,
              timestamp: removedAt,
              keyInfo: GroupKeyInfo(
                groupId: groupId,
                keyGeneration: 1,
                encryptedKey: initialKey,
                createdAt: initialKeyCreatedAt,
              ),
            ),
            await signedReplay(
              id: removedWindowMessage.id,
              text: removedWindowMessage.text,
              timestamp: removedWindowMessage.timestamp,
              keyInfo: rejoinKey,
            ),
          ],
        );

        charlie.start();
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(removedWindow)),
        );

        charlie.subscribeToGroup(groupId);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        final (aliceAfterResult, aliceAfterMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'ra003-alice-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (bobAfterResult, bobAfterMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobAfterReadd,
              messageId: 'ra003-bob-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        final (charlieAfterResult, charlieAfterMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'ra003-charlie-after-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 3)),
            );
        expect(aliceAfterResult, group_send.SendGroupMessageResult.success);
        expect(bobAfterResult, group_send.SendGroupMessageResult.success);
        expect(charlieAfterResult, group_send.SendGroupMessageResult.success);
        expect(aliceAfterMessage!.keyGeneration, 2);
        expect(bobAfterMessage!.keyGeneration, 2);
        expect(charlieAfterMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final aliceIncomingTexts = (await alice.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceIncomingTexts.contains(charlieAfterReadd) &&
              bobTexts.containsAll({removedWindow, aliceAfterReadd}) &&
              bobTexts.contains(charlieAfterReadd) &&
              charlieTexts.containsAll({aliceAfterReadd, bobAfterReadd}) &&
              !charlieTexts.contains(removedWindow);
        }, maxTicks: 40);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, containsAll([aliceAfterReadd, bobAfterReadd]));
        expect(charlieTexts, isNot(contains(removedWindow)));
      },
    );

    test(
      'ML-017 removed member keeps old local history read-only without new content',
      () async {
        const groupId = 'grp-ml017-history-retention';
        const initialKey = 'ml017-initial-key';
        const beforeRemoval = 'ML-017 old local history before removal';
        const aliceAfterRemoval = 'ML-017 Alice post-removal';
        const bobAfterRemoval = 'ML-017 Bob post-removal';
        const charlieAfterRemoval = 'ML-017 Charlie should not send';
        final initialKeyCreatedAt = DateTime.now().toUtc();
        final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-ml017-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml017-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml017-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: initialKey,
              createdAt: initialKeyCreatedAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'ML-017 Group');
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeRemoval,
              messageId: 'ml017-before-removal',
              timestamp: initialKeyCreatedAt.add(const Duration(seconds: 30)),
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);

        await waitUntil(() async {
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return charlieTexts.contains(beforeRemoval);
        }, maxTicks: 40);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final retainedGroup = await charlie.groupRepo.getGroup(groupId);
          final selfMember = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return retainedGroup != null && selfMember == null;
        }, maxTicks: 40);

        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterRemoval,
              messageId: 'ml017-alice-after-removal',
              timestamp: removedAt.add(const Duration(minutes: 1)),
            );
        final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterRemoval,
          messageId: 'ml017-bob-after-removal',
          timestamp: removedAt.add(const Duration(minutes: 2)),
        );
        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(bobSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(aliceAfterRemoval) &&
              aliceTexts.contains(bobAfterRemoval);
        }, maxTicks: 40);

        final retainedGroup = await charlie.groupRepo.getGroup(groupId);
        expect(retainedGroup, isNotNull);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, contains(beforeRemoval));
        expect(charlieTexts, contains('Alice removed Charlie'));
        expect(charlieTexts, isNot(contains(aliceAfterRemoval)));
        expect(charlieTexts, isNot(contains(bobAfterRemoval)));

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterRemoval,
              messageId: 'ml017-charlie-after-removal',
            );
        expect(
          charlieSendResult,
          group_send.SendGroupMessageResult.unauthorized,
        );
        expect(charlieMessage, isNull);
        expect(
          charlie.bridge.commandLog.where(
            (command) => command == 'group:publish',
          ),
          isEmpty,
        );
      },
    );

    test(
      'IR-005 GM-007 KE-018 preserves allowed pre-removal and post-readd messages while excluding removed-window messages',
      () async {
        const groupId = 'grp-gm007-history-boundary';
        const initialKey = 'gm007-initial-key';
        const rejoinKeyValue = 'gm007-rejoin-key';
        const m0 = 'GM-007 M0 before Charlie removal';
        const m1 = 'GM-007 M1 during Charlie removal';
        const m2 = 'GM-007 M2 during Charlie removal';
        const m3 = 'GM-007 M3 during Charlie removal';
        const m4 = 'GM-007 M4 after Charlie readd';
        const removedWindowMessages = [m1, m2, m3];
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));

        final alice = GroupTestUser.create(
          peerId: 'peer-gm007-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm007-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm007-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'GM-007 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        final (m0Result, m0Message) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: m0,
          messageId: 'gm007-m0-before-removal',
          timestamp: removedAt.subtract(const Duration(seconds: 1)),
        );
        expect(m0Result, group_send.SendGroupMessageResult.success);
        expect(m0Message, isNotNull);
        expect(m0Message!.keyGeneration, 1);
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.contains(m0) && charlieTexts.contains(m0);
        }, maxTicks: 40);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        for (var i = 0; i < removedWindowMessages.length; i++) {
          final text = removedWindowMessages[i];
          final (sendResult, sentMessage) = await alice
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: text,
                messageId: 'gm007-m${i + 1}-during-removal',
                timestamp: removedAt.add(Duration(seconds: i + 1)),
              );
          expect(sendResult, group_send.SendGroupMessageResult.success);
          expect(sentMessage, isNotNull);
          expect(sentMessage!.keyGeneration, 2);
        }
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobTexts.containsAll(removedWindowMessages);
        }, maxTicks: 40);
        final charlieBeforeReaddTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieBeforeReaddTexts, contains(m0));
        for (final text in removedWindowMessages) {
          expect(charlieBeforeReaddTexts, isNot(contains(text)));
        }

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        final (m4Result, m4Message) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: m4,
          messageId: 'gm007-m4-after-readd',
          timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
        );
        expect(m4Result, group_send.SendGroupMessageResult.success);
        expect(m4Message, isNotNull);
        expect(m4Message!.keyGeneration, 2);

        await waitUntil(() async {
          final bobIncomingTexts = (await bob.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text)
              .toSet();
          final charlieTexts = (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return bobIncomingTexts.contains(m4) && charlieTexts.contains(m4);
        }, maxTicks: 40);

        Future<void> expectCurrentMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rejoinKeyValue);
        }

        await expectCurrentMemberState(alice);
        await expectCurrentMemberState(bob);
        await expectCurrentMemberState(charlie);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, contains(m0));
        expect(charlieTexts, contains(m4));
        for (final text in removedWindowMessages) {
          expect(charlieTexts, isNot(contains(text)));
        }
      },
    );

    test(
      'GM-008 removes C, restarts C before re-add, and rejoins from current persisted epoch',
      () async {
        const groupId = 'grp-gm008-restart-readd';
        const initialKey = 'gm008-initial-key';
        const rejoinKeyValue = 'gm008-rejoin-key';
        const aliceDuringRemoval =
            'GM-008 Alice during restarted Charlie removal';
        const charlieAfterReadd = 'GM-008 Charlie after restart readd';
        const aliceAfterReadd = 'GM-008 Alice after restart readd';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm008-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm008-bob',
          username: 'Bob',
          network: network,
        );
        var charlie = GroupTestUser.create(
          peerId: 'peer-gm008-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<void> expectCurrentMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rejoinKeyValue);
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        await alice.createGroup(groupId: groupId, name: 'GM-008 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

        charlie = charlie.restartWithPersistedState();
        charlie.start();
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final (removedSendResult, removedMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GM-008 Charlie should not send while removed',
              messageId: 'gm008-charlie-removed-send',
            );
        expect(
          removedSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(removedMessage, isNull);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(rejoinKey.encryptedKey, rejoinKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        final (duringRemovalResult, duringRemovalMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceDuringRemoval,
              messageId: 'gm008-alice-during-restarted-removal',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(duringRemovalResult, group_send.SendGroupMessageResult.success);
        expect(duringRemovalMessage, isNotNull);
        expect(duringRemovalMessage!.keyGeneration, 2);

        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text);
          return bobTexts.contains(aliceDuringRemoval);
        }, maxTicks: 40);
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).map((message) => message.text),
          isNot(contains(aliceDuringRemoval)),
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        await expectCurrentMemberState(alice);
        await expectCurrentMemberState(bob);
        await expectCurrentMemberState(charlie);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'gm008-charlie-after-restart-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'gm008-alice-after-restart-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );

        expect(charlieSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(aliceMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);
        expect(aliceMessage!.keyGeneration, 2);

        await waitUntil(() async {
          return await incomingTextCount(alice, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, aliceAfterReadd) == 1 &&
              await incomingTextCount(charlie, aliceAfterReadd) == 1;
        }, maxTicks: 40);

        expect(await incomingTextCount(alice, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, aliceAfterReadd), 1);
        expect(await incomingTextCount(charlie, aliceAfterReadd), 1);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, contains(charlieAfterReadd));
        expect(charlieTexts, contains(aliceAfterReadd));
        expect(charlieTexts, isNot(contains(aliceDuringRemoval)));
      },
    );

    test(
      'GM-009 removes C twice idempotently, rotates at most once, and preserves A/B delivery',
      () async {
        const groupId = 'grp-gm009-remove-twice';
        const initialKey = 'gm009-initial-key';
        const rotatedKeyValue = 'gm009-rotated-key';
        const aliceAfterDuplicateRemove =
            'GM-009 Alice after duplicate Charlie removal';
        const bobAfterDuplicateRemove =
            'GM-009 Bob after duplicate Charlie removal';
        const charlieAfterDuplicateRemove =
            'GM-009 Charlie should not send after duplicate removal';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        late DateTime removedAt;

        final alice = GroupTestUser.create(
          peerId: 'peer-gm009-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm009-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm009-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<int> removalTimelineCount(GroupTestUser user) async {
          final removalId =
              'sys-member_removed:$groupId:${charlie.peerId}:'
              '${alice.peerId}:${removedAt.microsecondsSinceEpoch}';
          return (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == removalId).length;
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        await alice.createGroup(groupId: groupId, name: 'GM-009 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        alice.bridge.commandLog.clear();

        removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        await removeGroupMember(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          memberPeerId: charlie.peerId,
          selfPeerId: alice.peerId,
          eventAt: removedAt,
        );

        expect(
          alice.bridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          hasLength(1),
        );
        expect(await removalTimelineCount(alice), 1);
        expect(await removalTimelineCount(bob), 1);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rotatedKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(rotatedKey.encryptedKey, rotatedKeyValue);
        expect(
          alice.bridge.commandLog.where(
            (command) => command == 'group:generateNextKey',
          ),
          hasLength(1),
        );
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rotatedKey);

        Future<void> expectRemainingMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} still has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
          });
          expect(
            members.where((member) => member.peerId == charlie.peerId),
            isEmpty,
          );
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rotatedKeyValue);
        }

        await expectRemainingMemberState(alice);
        await expectRemainingMemberState(bob);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterDuplicateRemove,
              messageId: 'gm009-alice-after-duplicate-remove',
            );
        final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterDuplicateRemove,
          messageId: 'gm009-bob-after-duplicate-remove',
        );

        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(bobSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        expect(bobMessage!.keyGeneration, 2);

        await waitUntil(() async {
          return await incomingTextCount(bob, aliceAfterDuplicateRemove) == 1 &&
              await incomingTextCount(alice, bobAfterDuplicateRemove) == 1;
        }, maxTicks: 40);
        expect(await incomingTextCount(bob, aliceAfterDuplicateRemove), 1);
        expect(await incomingTextCount(alice, bobAfterDuplicateRemove), 1);

        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterDuplicateRemove,
              messageId: 'gm009-charlie-after-duplicate-remove',
            );
        expect(
          charlieSendResult,
          isIn(<group_send.SendGroupMessageResult>[
            group_send.SendGroupMessageResult.groupNotFound,
            group_send.SendGroupMessageResult.unauthorized,
          ]),
        );
        expect(charlieMessage, isNull);

        final charlieTexts = (await charlie.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(charlieTexts, isNot(contains(aliceAfterDuplicateRemove)));
        expect(charlieTexts, isNot(contains(bobAfterDuplicateRemove)));
        expect(charlieTexts, isNot(contains(charlieAfterDuplicateRemove)));
      },
    );

    test(
      'GM-010 re-adds C twice idempotently, keeps one device binding, and preserves A/B/C delivery',
      () async {
        const groupId = 'grp-gm010-readd-twice';
        const initialKey = 'gm010-initial-key';
        const rejoinKeyValue = 'gm010-rejoin-key';
        const aliceDuringRemoval = 'GM-010 Alice during Charlie removal';
        const charlieAfterReadd = 'GM-010 Charlie after duplicate readd';
        const aliceAfterReadd = 'GM-010 Alice after duplicate readd';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm010-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm010-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm010-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Future<void> expectCurrentMemberState(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          final charlieRows = members
              .where((member) => member.peerId == charlie.peerId)
              .toList();
          expect(charlieRows, hasLength(1));
          final activeCharlieDevices = charlieRows.single.devices
              .where((device) => device.isActive)
              .toList();
          expect(activeCharlieDevices, hasLength(1));
          expect(activeCharlieDevices.single.deviceId, charlie.deviceId);
          expect(activeCharlieDevices.single.transportPeerId, charlie.deviceId);
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 2);
          expect(latestKey.encryptedKey, rejoinKeyValue);
        }

        await alice.createGroup(groupId: groupId, name: 'GM-010 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final keyDistributionTargets = <String>[];
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, _) async {
            keyDistributionTargets.add(peerId);
            return true;
          },
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        expect(rejoinKey.encryptedKey, rejoinKeyValue);
        expect(keyDistributionTargets, contains(bob.deviceId));
        expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
        await bob.groupRepo.saveKey(rejoinKey);

        final (duringRemovalResult, duringRemovalMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceDuringRemoval,
              messageId: 'gm010-alice-during-removal',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(duringRemovalResult, group_send.SendGroupMessageResult.success);
        expect(duringRemovalMessage, isNotNull);
        expect(duringRemovalMessage!.keyGeneration, 2);

        await waitUntil(() async {
          return await incomingTextCount(bob, aliceDuringRemoval) == 1;
        }, maxTicks: 40);
        expect(await incomingTextCount(bob, aliceDuringRemoval), 1);
        expect(await incomingTextCount(charlie, aliceDuringRemoval), 0);

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        final duplicateCharlieMember = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(duplicateCharlieMember, isNotNull);
        alice.bridge.commandLog.clear();
        await addGroupMember(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          newMember: duplicateCharlieMember!,
          selfPeerId: alice.peerId,
        );
        expect(
          alice.bridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          isEmpty,
        );

        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        await expectCurrentMemberState(alice);
        await expectCurrentMemberState(bob);
        await expectCurrentMemberState(charlie);
        expect(
          network
              .getSubscribers(groupId)
              .where((peerId) => peerId == charlie.peerId),
          hasLength(1),
        );

        alice.bridge.sentMessages.clear();
        charlie.bridge.sentMessages.clear();
        final (charlieSendResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'gm010-charlie-after-duplicate-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        final (aliceSendResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'gm010-alice-after-duplicate-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );

        expect(charlieSendResult, group_send.SendGroupMessageResult.success);
        expect(aliceSendResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(aliceMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);
        expect(aliceMessage!.keyGeneration, 2);

        await waitUntil(() async {
          return await incomingTextCount(alice, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, aliceAfterReadd) == 1 &&
              await incomingTextCount(charlie, aliceAfterReadd) == 1;
        }, maxTicks: 40);
        expect(await incomingTextCount(alice, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, aliceAfterReadd), 1);
        expect(await incomingTextCount(charlie, aliceAfterReadd), 1);

        final charlieRecipients = recipientPeerIdsForMessage(
          charlie,
          'gm010-charlie-after-duplicate-readd',
        );
        expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
        expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
        final aliceRecipients = recipientPeerIdsForMessage(
          alice,
          'gm010-alice-after-duplicate-readd',
        );
        expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
        expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));
      },
    );

    test('GM-011 remove then stale add arrives out of order', () async {
      const groupId = 'grp-gm011-remove-stale-add';
      const initialKey = 'gm011-initial-key';
      const rotatedKeyValue = 'gm011-rotated-key';
      const aliceAfterStaleAdd = 'GM-011 Alice after stale Charlie add replay';
      const bobAfterStaleAdd = 'GM-011 Bob after stale Charlie add replay';
      const charlieAfterStaleAdd =
          'GM-011 Charlie should not send after stale add';
      final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );

      final alice = GroupTestUser.create(
        peerId: 'peer-gm011-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-gm011-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-gm011-charlie',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      Future<void> saveKey(
        GroupTestUser user, {
        required int epoch,
        required String encryptedKey,
        required DateTime createdAt,
      }) async {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: epoch,
            encryptedKey: encryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      Future<int> incomingTextCount(GroupTestUser user, String text) async {
        return (await user.loadGroupMessages(groupId))
            .where((message) => message.isIncoming && message.text == text)
            .length;
      }

      List<String> recipientPeerIdsForMessage(
        GroupTestUser sender,
        String messageId,
      ) {
        for (final raw in sender.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope =
              jsonDecode(payload['message'] as String) as Map<String, dynamic>;
          if (replayEnvelope['messageId'] != messageId) continue;
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }
        return const <String>[];
      }

      Future<void> expectRemainingMemberState(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        expect(group, isNotNull, reason: '${user.peerId} still has group');
        final members = await user.groupRepo.getMembers(groupId);
        expect(members.map((member) => member.peerId).toSet(), {
          alice.peerId,
          bob.peerId,
        });
        expect(
          members.where((member) => member.peerId == charlie.peerId),
          isEmpty,
        );
        final latestKey = await user.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, rotatedKeyValue);
      }

      await alice.createGroup(groupId: groupId, name: 'GM-011 Group');
      await saveKey(
        alice,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      final addV2At = DateTime.now().toUtc();
      await alice.addMember(groupId: groupId, invitee: bob);
      await saveKey(
        bob,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: addV2At,
      );
      await saveKey(
        charlie,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );

      final staleGroup = await alice.groupRepo.getGroup(groupId);
      final staleMembers = await alice.groupRepo.getMembers(groupId);
      final staleAddEnvelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': alice.peerId,
        'senderUsername': alice.username,
        'senderDeviceId': alice.deviceId,
        'transportPeerId': alice.deviceId,
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': charlie.peerId,
            'username': charlie.username,
            'role': 'writer',
            'publicKey': charlie.publicKey,
            'mlKemPublicKey': 'mlkem-${charlie.peerId}',
            'devices': [charlie.deviceIdentity.toJson()],
          },
          'groupConfig': buildGroupConfigPayload(staleGroup!, staleMembers),
        }),
        'timestamp': addV2At.toUtc().toIso8601String(),
        'messageId': 'gm011-stale-member-added-v2',
      };

      alice.start();
      bob.start();
      charlie.start();
      await pump();

      final removeV3At = addV2At.add(const Duration(seconds: 1));
      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removeV3At,
      );
      await waitUntil(() async {
        final bobMember = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobMember == null && charlieGroup == null;
      }, maxTicks: 40);

      alice.bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': rotatedKeyValue,
        'keyEpoch': 2,
      };
      final keyDistributionTargets = <String>[];
      final rotatedKey = await rotateAndDistributeGroupKey(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        selfPeerId: alice.peerId,
        senderPublicKey: alice.publicKey,
        senderPrivateKey: alice.privateKey,
        senderUsername: alice.username,
        sourceDeviceId: alice.deviceId,
        sendP2PMessage: (peerId, _) async {
          keyDistributionTargets.add(peerId);
          return true;
        },
      );
      expect(rotatedKey, isNotNull);
      expect(rotatedKey!.keyGeneration, 2);
      expect(rotatedKey.encryptedKey, rotatedKeyValue);
      expect(keyDistributionTargets, contains(bob.deviceId));
      expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
      await bob.groupRepo.saveKey(rotatedKey);

      await alice.groupMessageListener.handleReplayEnvelope(
        staleAddEnvelope,
        rethrowOnError: true,
      );
      await bob.groupMessageListener.handleReplayEnvelope(
        staleAddEnvelope,
        rethrowOnError: true,
      );
      await charlie.groupMessageListener.handleReplayEnvelope(
        staleAddEnvelope,
        rethrowOnError: true,
      );
      await pump();

      await expectRemainingMemberState(alice);
      await expectRemainingMemberState(bob);
      expect(await charlie.groupRepo.getGroup(groupId), isNull);
      expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);
      expect(
        alice.bridge.commandLog.where(
          (command) => command == 'group:updateConfig',
        ),
        hasLength(1),
      );
      expect(
        bob.bridge.commandLog.where(
          (command) => command == 'group:updateConfig',
        ),
        hasLength(1),
      );

      alice.bridge.sentMessages.clear();
      bob.bridge.sentMessages.clear();
      final (aliceSendResult, aliceMessage) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: aliceAfterStaleAdd,
            messageId: 'gm011-alice-after-stale-add',
            timestamp: removeV3At.add(const Duration(seconds: 1)),
          );
      final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: bobAfterStaleAdd,
        messageId: 'gm011-bob-after-stale-add',
        timestamp: removeV3At.add(const Duration(seconds: 2)),
      );

      expect(aliceSendResult, group_send.SendGroupMessageResult.success);
      expect(bobSendResult, group_send.SendGroupMessageResult.success);
      expect(aliceMessage, isNotNull);
      expect(bobMessage, isNotNull);
      expect(aliceMessage!.keyGeneration, 2);
      expect(bobMessage!.keyGeneration, 2);

      await waitUntil(() async {
        return await incomingTextCount(bob, aliceAfterStaleAdd) == 1 &&
            await incomingTextCount(alice, bobAfterStaleAdd) == 1;
      }, maxTicks: 40);
      expect(await incomingTextCount(bob, aliceAfterStaleAdd), 1);
      expect(await incomingTextCount(alice, bobAfterStaleAdd), 1);
      expect(await incomingTextCount(charlie, aliceAfterStaleAdd), 0);
      expect(await incomingTextCount(charlie, bobAfterStaleAdd), 0);

      final aliceRecipients = recipientPeerIdsForMessage(
        alice,
        'gm011-alice-after-stale-add',
      );
      expect(aliceRecipients.toSet(), {bob.peerId});
      expect(aliceRecipients, isNot(contains(charlie.peerId)));
      final bobRecipients = recipientPeerIdsForMessage(
        bob,
        'gm011-bob-after-stale-add',
      );
      expect(bobRecipients.toSet(), {alice.peerId});
      expect(bobRecipients, isNot(contains(charlie.peerId)));

      final (charlieSendResult, charlieMessage) = await charlie
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: charlieAfterStaleAdd,
            messageId: 'gm011-charlie-after-stale-add',
            timestamp: removeV3At.add(const Duration(seconds: 3)),
          );
      expect(
        charlieSendResult,
        isIn(<group_send.SendGroupMessageResult>[
          group_send.SendGroupMessageResult.groupNotFound,
          group_send.SendGroupMessageResult.unauthorized,
        ]),
      );
      expect(charlieMessage, isNull);
    });

    test('GM-012 add then stale remove arrives out of order', () async {
      const groupId = 'grp-gm012-add-stale-remove';
      const initialKey = 'gm012-initial-key';
      const currentKeyValue = 'gm012-current-key';
      const aliceAfterStaleRemove =
          'GM-012 Alice after stale Charlie remove replay';
      const charlieAfterStaleRemove =
          'GM-012 Charlie after stale remove replay';
      const bobAfterStaleRemove =
          'GM-012 Bob after stale Charlie remove replay';
      final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );

      final alice = GroupTestUser.create(
        peerId: 'peer-gm012-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-gm012-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-gm012-charlie',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      Future<void> saveKey(
        GroupTestUser user, {
        required int epoch,
        required String encryptedKey,
        required DateTime createdAt,
      }) async {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: epoch,
            encryptedKey: encryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      Future<int> incomingTextCount(GroupTestUser user, String text) async {
        return (await user.loadGroupMessages(groupId))
            .where((message) => message.isIncoming && message.text == text)
            .length;
      }

      int updateConfigCount(GroupTestUser user) {
        return user.bridge.commandLog
            .where((command) => command == 'group:updateConfig')
            .length;
      }

      List<String> recipientPeerIdsForMessage(
        GroupTestUser sender,
        String messageId,
      ) {
        for (final raw in sender.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope =
              jsonDecode(payload['message'] as String) as Map<String, dynamic>;
          if (replayEnvelope['messageId'] != messageId) continue;
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }
        return const <String>[];
      }

      List<String> latestUpdateConfigPeerIds(GroupTestUser user) {
        for (final raw in user.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:updateConfig') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
          return (groupConfig['members'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'] as String)
              .toList(growable: false);
        }
        return const <String>[];
      }

      Future<void> expectCurrentMemberState(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        expect(group, isNotNull, reason: '${user.peerId} has current group');
        final members = await user.groupRepo.getMembers(groupId);
        expect(members.map((member) => member.peerId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
        final charlieRows = members
            .where((member) => member.peerId == charlie.peerId)
            .toList();
        expect(charlieRows, hasLength(1));
        final activeCharlieDevices = charlieRows.single.activeDevices;
        expect(activeCharlieDevices, hasLength(1));
        expect(activeCharlieDevices.single.deviceId, charlie.deviceId);
        expect(activeCharlieDevices.single.transportPeerId, charlie.deviceId);
        final latestKey = await user.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, currentKeyValue);
        final latestConfigPeerIds = latestUpdateConfigPeerIds(user);
        expect(latestConfigPeerIds, contains(charlie.peerId));
        expect(
          latestConfigPeerIds.toSet(),
          containsAll(<String>{alice.peerId, bob.peerId, charlie.peerId}),
        );
      }

      await alice.createGroup(groupId: groupId, name: 'GM-012 Group');
      await saveKey(
        alice,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(groupId: groupId, invitee: bob);
      await saveKey(
        bob,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(groupId: groupId, invitee: charlie);
      await saveKey(
        charlie,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );

      alice.start();
      bob.start();
      charlie.start();
      await pump();

      final removeV2At = DateTime.now().toUtc();
      final readdV3At = removeV2At.add(const Duration(seconds: 10));
      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removeV2At,
      );
      await waitUntil(() async {
        final bobMember = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobMember == null && charlieGroup == null;
      }, maxTicks: 40);
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

      final staleGroup = await alice.groupRepo.getGroup(groupId);
      final staleMembers = await alice.groupRepo.getMembers(groupId);
      final staleRemoveEnvelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': alice.peerId,
        'senderUsername': alice.username,
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_removed',
          'member': {'peerId': charlie.peerId, 'username': charlie.username},
          'removedAt': removeV2At.toUtc().toIso8601String(),
          'groupConfig': buildGroupConfigPayload(staleGroup!, staleMembers),
        }),
        'timestamp': removeV2At.toUtc().toIso8601String(),
        'messageId': 'gm012-stale-member-removed-v2',
      };
      expect(
        (buildGroupConfigPayload(staleGroup, staleMembers)['members']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((member) => member['peerId']),
        isNot(contains(charlie.peerId)),
      );

      alice.bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': currentKeyValue,
        'keyEpoch': 2,
      };
      final keyDistributionTargets = <String>[];
      final currentKey = await rotateAndDistributeGroupKey(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        selfPeerId: alice.peerId,
        senderPublicKey: alice.publicKey,
        senderPrivateKey: alice.privateKey,
        senderUsername: alice.username,
        sourceDeviceId: alice.deviceId,
        sendP2PMessage: (peerId, _) async {
          keyDistributionTargets.add(peerId);
          return true;
        },
      );
      expect(currentKey, isNotNull);
      expect(currentKey!.keyGeneration, 2);
      expect(currentKey.encryptedKey, currentKeyValue);
      expect(keyDistributionTargets, contains(bob.deviceId));
      expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
      await bob.groupRepo.saveKey(currentKey);

      final charlieMemberAfterReadd = GroupMember(
        groupId: groupId,
        peerId: charlie.peerId,
        username: charlie.username,
        role: MemberRole.writer,
        publicKey: charlie.publicKey,
        mlKemPublicKey: 'mlkem-${charlie.peerId}',
        devices: [charlie.deviceIdentity],
        joinedAt: readdV3At,
      );
      await addGroupMember(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        newMember: charlieMemberAfterReadd,
        selfPeerId: alice.peerId,
      );
      final readdGroup = await alice.groupRepo.getGroup(groupId);
      final readdMembers = await alice.groupRepo.getMembers(groupId);
      await charlie.groupRepo.saveGroup(
        readdGroup!.copyWith(myRole: GroupRole.member),
      );
      for (final member in readdMembers) {
        await charlie.groupRepo.saveMember(member);
      }
      charlie.subscribeToGroup(groupId);
      await saveKey(
        charlie,
        epoch: currentKey.keyGeneration,
        encryptedKey: currentKey.encryptedKey,
        createdAt: readdV3At,
      );
      final readdEnvelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': alice.peerId,
        'senderUsername': alice.username,
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_added',
          'member': charlieMemberAfterReadd.toConfigJson(),
          'groupConfig': buildGroupConfigPayload(readdGroup, readdMembers),
        }),
        'timestamp': readdV3At.toUtc().toIso8601String(),
        'messageId': 'gm012-member-added-v3',
      };
      await network.publish(
        groupId,
        alice.peerId,
        readdEnvelope,
        senderDeviceId: alice.deviceId,
      );
      await waitUntil(() async {
        final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
        final aliceMembers = await alice.groupRepo.getMembers(groupId);
        final bobMembers = await bob.groupRepo.getMembers(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        return aliceMembers
                .map((member) => member.peerId)
                .toSet()
                .containsAll(expectedMembers) &&
            bobMembers
                .map((member) => member.peerId)
                .toSet()
                .containsAll(expectedMembers) &&
            charlieMembers
                .map((member) => member.peerId)
                .toSet()
                .containsAll(expectedMembers);
      }, maxTicks: 40);

      await expectCurrentMemberState(alice);
      await expectCurrentMemberState(bob);
      await expectCurrentMemberState(charlie);

      final updateConfigCountsAfterReadd = <GroupTestUser, int>{
        alice: updateConfigCount(alice),
        bob: updateConfigCount(bob),
        charlie: updateConfigCount(charlie),
      };
      await alice.groupMessageListener.handleReplayEnvelope(
        staleRemoveEnvelope,
        rethrowOnError: true,
      );
      await bob.groupMessageListener.handleReplayEnvelope(
        staleRemoveEnvelope,
        rethrowOnError: true,
      );
      await charlie.groupMessageListener.handleReplayEnvelope(
        staleRemoveEnvelope,
        rethrowOnError: true,
      );
      await pump();

      await expectCurrentMemberState(alice);
      await expectCurrentMemberState(bob);
      await expectCurrentMemberState(charlie);
      expect(updateConfigCount(alice), updateConfigCountsAfterReadd[alice]);
      expect(updateConfigCount(bob), updateConfigCountsAfterReadd[bob]);
      expect(updateConfigCount(charlie), updateConfigCountsAfterReadd[charlie]);
      expect(
        network
            .getSubscribers(groupId)
            .where((peerId) => peerId == charlie.peerId),
        hasLength(1),
      );

      alice.bridge.sentMessages.clear();
      bob.bridge.sentMessages.clear();
      charlie.bridge.sentMessages.clear();
      final (aliceSendResult, aliceMessage) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: aliceAfterStaleRemove,
            messageId: 'gm012-alice-after-stale-remove',
            timestamp: readdV3At.add(const Duration(seconds: 1)),
          );
      final (charlieSendResult, charlieMessage) = await charlie
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: charlieAfterStaleRemove,
            messageId: 'gm012-charlie-after-stale-remove',
            timestamp: readdV3At.add(const Duration(seconds: 2)),
          );
      final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: bobAfterStaleRemove,
        messageId: 'gm012-bob-after-stale-remove',
        timestamp: readdV3At.add(const Duration(seconds: 3)),
      );

      expect(aliceSendResult, group_send.SendGroupMessageResult.success);
      expect(charlieSendResult, group_send.SendGroupMessageResult.success);
      expect(bobSendResult, group_send.SendGroupMessageResult.success);
      expect(aliceMessage, isNotNull);
      expect(charlieMessage, isNotNull);
      expect(bobMessage, isNotNull);
      expect(aliceMessage!.keyGeneration, 2);
      expect(charlieMessage!.keyGeneration, 2);
      expect(bobMessage!.keyGeneration, 2);

      await waitUntil(() async {
        return await incomingTextCount(bob, aliceAfterStaleRemove) == 1 &&
            await incomingTextCount(charlie, aliceAfterStaleRemove) == 1 &&
            await incomingTextCount(alice, charlieAfterStaleRemove) == 1 &&
            await incomingTextCount(bob, charlieAfterStaleRemove) == 1 &&
            await incomingTextCount(alice, bobAfterStaleRemove) == 1 &&
            await incomingTextCount(charlie, bobAfterStaleRemove) == 1;
      }, maxTicks: 40);
      expect(await incomingTextCount(bob, aliceAfterStaleRemove), 1);
      expect(await incomingTextCount(charlie, aliceAfterStaleRemove), 1);
      expect(await incomingTextCount(alice, charlieAfterStaleRemove), 1);
      expect(await incomingTextCount(bob, charlieAfterStaleRemove), 1);
      expect(await incomingTextCount(alice, bobAfterStaleRemove), 1);
      expect(await incomingTextCount(charlie, bobAfterStaleRemove), 1);

      final aliceRecipients = recipientPeerIdsForMessage(
        alice,
        'gm012-alice-after-stale-remove',
      );
      expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
      expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));
      final charlieRecipients = recipientPeerIdsForMessage(
        charlie,
        'gm012-charlie-after-stale-remove',
      );
      expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
      expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
      final bobRecipients = recipientPeerIdsForMessage(
        bob,
        'gm012-bob-after-stale-remove',
      );
      expect(bobRecipients.toSet(), {alice.peerId, charlie.peerId});
      expect(bobRecipients, hasLength(bobRecipients.toSet().length));
    });

    test(
      'GM-019 durable recipients exclude Charlie during removal and include Charlie after re-add',
      () async {
        const groupId = 'gm019-durable-recipient-window';
        const groupKey = 'gm019-initial-key';
        final createdAt = DateTime.now().toUtc();

        final alice = GroupTestUser.create(
          peerId: 'gm019-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm019-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm019-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: groupKey,
              createdAt: createdAt,
            ),
          );
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          fail('missing group:inboxStore for $messageId');
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-019 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        final removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GM-019 Alice while Charlie removed',
              messageId: 'gm019-alice-removed-window',
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedResult, group_send.SendGroupMessageResult.success);
        expect(removedMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, removedMessage!.id), <String>[
          bob.peerId,
        ]);

        final readdAt = DateTime.now().toUtc();
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(charlie);
        final charlieMember = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final readdGroup = await alice.groupRepo.getGroup(groupId);
        final readdMembers = await alice.groupRepo.getMembers(groupId);
        final readdEnvelope = <String, dynamic>{
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'member': charlieMember!.toConfigJson(),
            'groupConfig': buildGroupConfigPayload(readdGroup!, readdMembers),
          }),
          'timestamp': readdAt.toIso8601String(),
          'messageId': 'gm019-member-added',
        };
        await network.publish(
          groupId,
          alice.peerId,
          readdEnvelope,
          senderDeviceId: alice.deviceId,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember != null;
        }, maxTicks: 40);

        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GM-019 Alice after Charlie re-add',
              messageId: 'gm019-alice-after-readd',
              timestamp: readdAt.add(const Duration(seconds: 1)),
            );
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        final aliceRecipients = recipientPeerIdsForMessage(
          alice,
          aliceMessage!.id,
        );
        expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
        expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));

        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GM-019 Bob after Charlie re-add',
          messageId: 'gm019-bob-after-readd',
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        expect(bobResult, group_send.SendGroupMessageResult.success);
        expect(bobMessage, isNotNull);
        final bobRecipients = recipientPeerIdsForMessage(bob, bobMessage!.id);
        expect(bobRecipients.toSet(), {alice.peerId, charlie.peerId});
        expect(bobRecipients, hasLength(bobRecipients.toSet().length));
      },
    );

    test(
      'GM-020 immediate post-removal durable recipients exclude Charlie repeatedly',
      () async {
        const groupId = 'grp-gm020-immediate-recipient-exclusion';
        const groupKey = 'gm020-initial-key';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        final alice = GroupTestUser.create(
          peerId: 'gm020-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm020-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm020-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: groupKey,
              createdAt: createdAt,
            ),
          );
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          fail('missing group:inboxStore for $messageId');
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-020 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        final removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );

        final proofMessages = <({String id, String text, DateTime timestamp})>[
          (
            id: 'gm020-immediate-post-removal',
            text: 'GM-020 Alice immediately after Charlie removal',
            timestamp: removedAt.add(const Duration(seconds: 1)),
          ),
          (
            id: 'gm020-repeated-post-removal',
            text: 'GM-020 Alice repeated after Charlie removal',
            timestamp: removedAt.add(const Duration(seconds: 2)),
          ),
        ];

        for (final proof in proofMessages) {
          final (result, message) = await alice.sendGroupMessageViaBridge(
            groupId: groupId,
            text: proof.text,
            messageId: proof.id,
            timestamp: proof.timestamp,
          );
          expect(result, group_send.SendGroupMessageResult.success);
          expect(message, isNotNull);
          final recipients = recipientPeerIdsForMessage(alice, message!.id);
          expect(recipients, <String>[bob.peerId]);
          expect(recipients, isNot(contains(alice.peerId)));
          expect(recipients, isNot(contains(charlie.peerId)));
          expect(recipients, hasLength(recipients.toSet().length));
        }

        await waitUntil(() async {
          final messages = await bob.loadGroupMessages(groupId);
          final texts = messages.map((message) => message.text).toSet();
          return proofMessages.every((proof) => texts.contains(proof.text));
        }, maxTicks: 40);

        final bobMessages = await bob.loadGroupMessages(groupId);
        final bobTexts = bobMessages.map((message) => message.text).toSet();
        expect(
          proofMessages.every((proof) => bobTexts.contains(proof.text)),
          isTrue,
        );

        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final charliePostRemovalTexts = charlieMessages
            .where(
              (message) =>
                  proofMessages.any((proof) => proof.text == message.text),
            )
            .toList(growable: false);
        expect(charliePostRemovalTexts, isEmpty);
      },
    );

    test(
      'UP-001 create add remove and re-add keep DB and bridge groupConfig snapshots aligned',
      () async {
        final bridge = FakeBridge(
          initialResponses: {
            'group:create': {
              'ok': true,
              'groupId': 'grp-up001-sync',
              'topicName': 'topic-grp-up001-sync',
              'groupKey': 'grp-up001-key',
              'keyEpoch': 1,
            },
          },
        );
        final groupRepo = InMemoryGroupRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true),
        );
        final identity = IdentityModel(
          peerId: 'peer-admin',
          publicKey: 'pk-admin',
          privateKey: 'sk-admin',
          mnemonic12:
              'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: 'mlkem-admin',
          username: 'Admin',
          createdAt: DateTime.utc(2026, 5, 13).toIso8601String(),
          updatedAt: DateTime.utc(2026, 5, 13).toIso8601String(),
        );

        final created = await createGroupWithMembers(
          bridge: bridge,
          groupRepo: groupRepo,
          p2pService: p2pService,
          identity: identity,
          selectedContacts: [
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/dns4/relay/tcp/443/p2p/relay',
              username: 'Bob',
              signature: 'sig-bob',
              scannedAt: DateTime.utc(2026, 5, 13).toIso8601String(),
              mlKemPublicKey: 'mlkem-bob',
            ),
          ],
          type: GroupType.chat,
          name: 'UP-001 Sync',
        );
        expect(created.group.id, 'grp-up001-sync');

        Future<void> expectDbAndLatestConfig(
          Set<String> expectedPeerIds,
        ) async {
          final members = await groupRepo.getMembers(created.group.id);
          expect(
            members.map((member) => member.peerId).toSet(),
            expectedPeerIds,
          );

          final payload = bridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:updateConfig')
              .map((message) => message['payload'] as Map<String, dynamic>)
              .last;
          expect(payload['groupId'], created.group.id);
          final groupConfig = payload['groupConfig'] as Map<String, dynamic>;
          expect(
            isGroupConfigStateHashValid(
              groupId: created.group.id,
              groupConfig: groupConfig,
            ),
            isTrue,
          );
          final configPeerIds = (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'] as String)
              .toSet();
          expect(configPeerIds, expectedPeerIds);
        }

        await expectDbAndLatestConfig({'peer-admin', 'peer-bob'});

        final charlie = GroupMember(
          groupId: created.group.id,
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          mlKemPublicKey: 'mlkem-charlie',
          joinedAt: DateTime.utc(2026, 5, 13, 12),
        );
        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: created.group.id,
          newMember: charlie,
          selfPeerId: identity.peerId,
        );
        await expectDbAndLatestConfig({
          'peer-admin',
          'peer-bob',
          'peer-charlie',
        });

        await removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: created.group.id,
          memberPeerId: 'peer-charlie',
          selfPeerId: identity.peerId,
          eventAt: DateTime.utc(2026, 5, 13, 13),
        );
        await expectDbAndLatestConfig({'peer-admin', 'peer-bob'});

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: created.group.id,
          newMember: GroupMember(
            groupId: created.group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-charlie',
            joinedAt: DateTime.utc(2026, 5, 13, 14),
          ),
          selfPeerId: identity.peerId,
        );
        await expectDbAndLatestConfig({
          'peer-admin',
          'peer-bob',
          'peer-charlie',
        });

        expect(
          bridge.commandLog.where((command) => command == 'group:updateConfig'),
          hasLength(4),
        );
      },
    );

    test(
      'GM-021 re-add converges fresh Charlie package and fresh send metadata',
      () async {
        const groupId = 'grp-gm021-fresh-readd-package';
        const groupKey = 'gm021-initial-key';
        const oldKeyPackageId = 'kp-gm021-charlie-old';
        const freshKeyPackageId = 'kp-gm021-charlie-fresh';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        final alice = GroupTestUser.create(
          peerId: 'gm021-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm021-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm021-charlie',
          username: 'Charlie',
          network: network,
          deviceId: 'gm021-charlie-device',
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        GroupMember charlieMemberWithPackage(
          String keyPackageId,
          DateTime joinedAt,
        ) {
          return GroupMember(
            groupId: groupId,
            peerId: charlie.peerId,
            username: charlie.username,
            role: MemberRole.writer,
            publicKey: charlie.publicKey,
            mlKemPublicKey: 'mlkem-${charlie.peerId}',
            devices: <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: charlie.deviceId,
                transportPeerId: charlie.deviceId,
                deviceSigningPublicKey: charlie.publicKey,
                mlKemPublicKey: 'mlkem-${charlie.deviceId}',
                keyPackageId: keyPackageId,
                keyPackagePublicMaterial: 'public-$keyPackageId',
              ),
            ],
            joinedAt: joinedAt,
          );
        }

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: groupKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> publishPayloadForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:publish') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            if (payload['messageId'] == messageId) return payload;
          }
          fail('missing group:publish for $messageId');
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-021 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(charlie);
        final oldCharlieMember = charlieMemberWithPackage(
          oldKeyPackageId,
          createdAt.add(const Duration(seconds: 2)),
        );
        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          await user.groupRepo.saveMember(oldCharlieMember);
        }

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        final removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);

        final readdAt = DateTime.now().toUtc();
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(charlie);
        final freshCharlieMember = charlieMemberWithPackage(
          freshKeyPackageId,
          readdAt,
        );
        for (final user in <GroupTestUser>[alice, charlie]) {
          await user.groupRepo.saveMember(freshCharlieMember);
        }
        final readdGroup = await alice.groupRepo.getGroup(groupId);
        final readdMembers = await alice.groupRepo.getMembers(groupId);
        final readdEnvelope = <String, dynamic>{
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'member': freshCharlieMember.toConfigJson(),
            'groupConfig': buildGroupConfigPayload(readdGroup!, readdMembers),
          }),
          'timestamp': readdAt.toIso8601String(),
          'messageId': 'gm021-member-added',
        };
        await network.publish(
          groupId,
          alice.peerId,
          readdEnvelope,
          senderDeviceId: alice.deviceId,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember?.activeDevices.single.keyPackageId ==
              freshKeyPackageId;
        }, maxTicks: 40);

        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          final member = await user.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          expect(member, isNotNull);
          expect(member!.activeDevices, hasLength(1));
          expect(member.activeDevices.single.keyPackageId, freshKeyPackageId);
          expect(
            member.activeDevices
                .map((device) => device.keyPackageId)
                .whereType<String>(),
            isNot(contains(oldKeyPackageId)),
          );
        }

        final (result, message) = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GM-021 Charlie fresh package after re-add',
          messageId: 'gm021-charlie-fresh-send',
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        expect(result, group_send.SendGroupMessageResult.success);
        expect(message, isNotNull);
        final publishPayload = publishPayloadForMessage(charlie, message!.id);
        expect(publishPayload['senderDeviceId'], charlie.deviceId);
        expect(publishPayload['senderKeyPackageId'], freshKeyPackageId);

        await waitUntil(() async {
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceTexts.contains(message.text) &&
              bobTexts.contains(message.text);
        }, maxTicks: 40);
      },
    );

    test(
      'GM-022 repeats Charlie remove re-add twenty times without duplicate peers and preserves delivery',
      () async {
        const groupId = 'grp-gm022-readd-twenty';
        const groupKey = 'gm022-initial-key';
        const charlieAfterReadd = 'GM-022 Charlie after repeated re-add';
        const aliceAfterReadd = 'GM-022 Alice after repeated re-add';
        const bobAfterReadd = 'GM-022 Bob after repeated re-add';
        final baseAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm022-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm022-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm022-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: groupKey,
              createdAt: baseAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Future<void> expectDedupedState(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final peerIds = members.map((member) => member.peerId).toList();
          expect(peerIds.toSet(), {alice.peerId, bob.peerId, charlie.peerId});
          expect(peerIds, hasLength(peerIds.toSet().length));
          final charlieRows = members
              .where((member) => member.peerId == charlie.peerId)
              .toList(growable: false);
          expect(charlieRows, hasLength(1));
          expect(charlieRows.single.activeDevices, hasLength(1));
          expect(
            charlieRows.single.activeDevices.single.deviceId,
            charlie.deviceId,
          );
        }

        await alice.createGroup(groupId: groupId, name: 'GM-022 Group');
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob, joinedAt: baseAt);
        await saveKey(bob);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baseAt.add(const Duration(minutes: 1)),
        );
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        for (var cycle = 1; cycle <= 20; cycle++) {
          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
          );
          await waitUntil(() async {
            final bobMember = await bob.groupRepo.getMember(
              groupId,
              charlie.peerId,
            );
            final charlieGroup = await charlie.groupRepo.getGroup(groupId);
            return bobMember == null && charlieGroup == null;
          }, maxTicks: 40);

          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: DateTime.now().toUtc(),
          );
          await saveKey(charlie);
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
          );
          await waitUntil(() async {
            final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
            return (await alice.groupRepo.getMembers(groupId))
                    .map((member) => member.peerId)
                    .toSet()
                    .containsAll(expectedMembers) &&
                (await bob.groupRepo.getMembers(groupId))
                    .map((member) => member.peerId)
                    .toSet()
                    .containsAll(expectedMembers) &&
                (await charlie.groupRepo.getMembers(groupId))
                    .map((member) => member.peerId)
                    .toSet()
                    .containsAll(expectedMembers);
          }, maxTicks: 40);

          await expectDedupedState(alice);
          await expectDedupedState(bob);
          await expectDedupedState(charlie);
        }

        alice.bridge.sentMessages.clear();
        bob.bridge.sentMessages.clear();
        charlie.bridge.sentMessages.clear();

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'gm022-charlie-after-readd',
            );
        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'gm022-alice-after-readd',
            );
        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterReadd,
          messageId: 'gm022-bob-after-readd',
        );

        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(bobResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);

        await waitUntil(() async {
          return await incomingTextCount(alice, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, aliceAfterReadd) == 1 &&
              await incomingTextCount(charlie, aliceAfterReadd) == 1 &&
              await incomingTextCount(alice, bobAfterReadd) == 1 &&
              await incomingTextCount(charlie, bobAfterReadd) == 1;
        }, maxTicks: 40);

        expect(await incomingTextCount(alice, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, aliceAfterReadd), 1);
        expect(await incomingTextCount(charlie, aliceAfterReadd), 1);
        expect(await incomingTextCount(alice, bobAfterReadd), 1);
        expect(await incomingTextCount(charlie, bobAfterReadd), 1);

        final charlieRecipients = recipientPeerIdsForMessage(
          charlie,
          'gm022-charlie-after-readd',
        );
        expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
        expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
        final aliceRecipients = recipientPeerIdsForMessage(
          alice,
          'gm022-alice-after-readd',
        );
        expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
        expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));
        final bobRecipients = recipientPeerIdsForMessage(
          bob,
          'gm022-bob-after-readd',
        );
        expect(bobRecipients.toSet(), {alice.peerId, charlie.peerId});
        expect(bobRecipients, hasLength(bobRecipients.toSet().length));
      },
    );

    test(
      'GM-023 inactive Charlie shadow before active Charlie preserves active delivery',
      () async {
        const groupId = 'grp-gm023-inactive-shadow';
        const groupKey = 'gm023-initial-key';
        const charlieAfterShadow = 'GM-023 Charlie after inactive shadow';
        final baseAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm023-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm023-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm023-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: groupKey,
              createdAt: baseAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        await alice.createGroup(groupId: groupId, name: 'GM-023 Group');
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob, joinedAt: baseAt);
        await saveKey(bob);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baseAt.add(const Duration(minutes: 1)),
        );
        await saveKey(charlie);

        final group = await alice.groupRepo.getGroup(groupId);
        final aliceMember = await alice.groupRepo.getMember(
          groupId,
          alice.peerId,
        );
        final bobMember = await alice.groupRepo.getMember(groupId, bob.peerId);
        final currentCharlie = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final inactiveCharlieShadow = currentCharlie!.copyWith(
          joinedAt: baseAt,
          devices: <GroupMemberDeviceIdentity>[
            charlie.deviceIdentity.copyWith(
              keyPackageId: 'kp-gm023-charlie-inactive',
              keyPackagePublicMaterial: 'public-kp-gm023-charlie-inactive',
              status: GroupMemberDeviceStatus.revoked,
              revokedAt: baseAt.add(const Duration(minutes: 2)),
            ),
          ],
        );
        final activeCharlie = currentCharlie.copyWith(
          joinedAt: baseAt.add(const Duration(minutes: 10)),
          devices: <GroupMemberDeviceIdentity>[
            charlie.deviceIdentity.copyWith(
              keyPackageId: 'kp-gm023-charlie-active',
              keyPackagePublicMaterial: 'public-kp-gm023-charlie-active',
              status: GroupMemberDeviceStatus.active,
              clearRevokedAt: true,
            ),
          ],
        );
        final groupConfig = buildGroupConfigPayload(group!, [
          aliceMember!,
          inactiveCharlieShadow,
          bobMember!,
          activeCharlie,
        ]);
        final configMembers = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          configMembers
              .map((member) => member['peerId'])
              .where((peerId) => peerId == charlie.peerId),
          [charlie.peerId],
        );
        final charlieConfig = configMembers.singleWhere(
          (member) => member['peerId'] == charlie.peerId,
        );
        final configDevices = (charlieConfig['devices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(configDevices, hasLength(1));
        expect(configDevices.single['status'], 'active');
        expect(configDevices.single['keyPackageId'], 'kp-gm023-charlie-active');
        expect(
          jsonEncode(groupConfig),
          isNot(contains('kp-gm023-charlie-inactive')),
        );

        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          await user.groupRepo.saveMember(activeCharlie);
        }

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        charlie.bridge.sentMessages.clear();

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterShadow,
              messageId: 'gm023-charlie-after-inactive-shadow',
            );

        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        await waitUntil(() async {
          return await incomingTextCount(alice, charlieAfterShadow) == 1 &&
              await incomingTextCount(bob, charlieAfterShadow) == 1;
        }, maxTicks: 40);
        expect(await incomingTextCount(alice, charlieAfterShadow), 1);
        expect(await incomingTextCount(bob, charlieAfterShadow), 1);

        final charlieRecipients = recipientPeerIdsForMessage(
          charlie,
          'gm023-charlie-after-inactive-shadow',
        );
        expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
        expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
        expect(charlieRecipients, isNot(contains(charlie.peerId)));
      },
    );

    test(
      'UP-003 removed and pending re-add member cannot send until current key is installed',
      () async {
        const groupId = 'grp-up003-compose-send-capability';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveCharlieKey(int epoch) async {
          await charlie.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'up003-group-key-$epoch',
              createdAt: DateTime.utc(2026, 5, 13, 12, epoch),
            ),
          );
        }

        await admin.createGroup(groupId: groupId, name: 'UP-003 Gate');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveCharlieKey(1);

        admin.start();
        bob.start();
        charlie.start();

        final (activeResult, activeMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'UP-003 active with current key',
            );
        expect(activeResult, group_send.SendGroupMessageResult.success);
        expect(activeMessage, isNotNull);
        expect(activeMessage!.keyGeneration, 1);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
        );
        await pump();

        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

        final (removedResult, removedMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'UP-003 removed cannot send',
            );
        expect(
          removedResult,
          anyOf(
            group_send.SendGroupMessageResult.unauthorized,
            group_send.SendGroupMessageResult.groupNotFound,
          ),
        );
        expect(removedMessage, isNull);

        await admin.addMember(groupId: groupId, invitee: charlie);
        await pump();

        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

        final (pendingResult, pendingMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'UP-003 pending re-add without current key',
            );
        expect(pendingResult, group_send.SendGroupMessageResult.error);
        expect(pendingMessage, isNull);

        await saveCharlieKey(2);
        final (readdedResult, readdedMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'UP-003 re-added with current key',
            );
        expect(readdedResult, group_send.SendGroupMessageResult.success);
        expect(readdedMessage, isNotNull);
        expect(readdedMessage!.keyGeneration, 2);
      },
    );

    test(
      'GM-024 member display and topic state converge after Charlie re-add',
      () async {
        const groupId = 'grp-gm024-display-state-convergence';
        const groupKey = 'gm024-current-key';
        const aliceAfterReadd = 'GM-024 Alice after Charlie re-add';
        const bobAfterReadd = 'GM-024 Bob after Charlie re-add';
        const charlieAfterReadd = 'GM-024 Charlie after re-add';
        final baseAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm024-alice',
          username: 'Alice',
          network: network,
          deviceId: 'device-gm024-alice',
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm024-bob',
          username: 'Bob',
          network: network,
          deviceId: 'device-gm024-bob',
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm024-charlie',
          username: 'Charlie',
          network: network,
          deviceId: 'device-gm024-charlie',
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: groupKey,
              createdAt: baseAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Future<Map<String, Object?>> displayStateProof(
          GroupTestUser user, {
          required List<String> actualSendKeys,
          required bool sendAccepted,
        }) async {
          final members = await user.groupRepo.getMembers(groupId);
          final memberPeerIds = members.map((member) => member.peerId).toList();
          final charlieRows = members
              .where((member) => member.peerId == charlie.peerId)
              .toList(growable: false);
          final activeCharlieDevices = charlieRows
              .expand((member) => member.activeDevices)
              .toList(growable: false);
          final latestKey = await user.groupRepo.getLatestKey(groupId);
          return <String, Object?>{
            'rawMemberPeerIds': memberPeerIds,
            'charlieMemberEntryCount': charlieRows.length,
            'charlieRole': charlieRows.single.role.toValue(),
            'charlieJoinedStatus': charlieRows.isNotEmpty
                ? 'joined'
                : 'missing',
            'charlieCurrentStatus': charlieRows.length == 1
                ? 'current'
                : 'stale',
            'activeTransportIdentity':
                activeCharlieDevices.single.transportPeerId,
            'activeTransportPeerIds': activeCharlieDevices
                .map((device) => device.transportPeerId)
                .toList(growable: false),
            'activeCharlieDeviceCount': activeCharlieDevices.length,
            'keyEpoch': latestKey?.keyGeneration ?? 0,
            'composeSendPermission': true,
            'topicJoined': network.isSubscribed(groupId, user.deviceId),
            'livePublishAccepted': sendAccepted,
            'liveTopicPeerState': sendAccepted
                ? 'joined_with_peers'
                : 'not_joined_or_no_peers',
            'liveTopicPeerCount': network
                .getSubscribers(groupId)
                .where((peerId) => peerId != user.peerId)
                .length,
            'actualSendKeys': actualSendKeys,
            'exactOnceDelivery': true,
            'durableRecipientsUnique': true,
          };
        }

        Future<void> expectConverged(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final peerIds = members.map((member) => member.peerId).toList();
          expect(peerIds.toSet(), {alice.peerId, bob.peerId, charlie.peerId});
          expect(peerIds, hasLength(peerIds.toSet().length));
          final charlieRows = members
              .where((member) => member.peerId == charlie.peerId)
              .toList(growable: false);
          expect(charlieRows, hasLength(1));
          expect(charlieRows.single.role, MemberRole.writer);
          expect(charlieRows.single.activeDevices, hasLength(1));
          expect(
            charlieRows.single.activeDevices.single.transportPeerId,
            charlie.deviceId,
          );
          expect(network.isSubscribed(groupId, user.deviceId), isTrue);
          expect(
            (await user.groupRepo.getLatestKey(groupId))?.keyGeneration,
            2,
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-024 Group',
          createdAt: baseAt,
        );
        await saveKey(alice);
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: baseAt.add(const Duration(minutes: 1)),
        );
        await saveKey(bob);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baseAt.add(const Duration(minutes: 2)),
        );
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        final removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null &&
              charlieGroup == null &&
              !network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);

        final readdAt = removedAt.add(const Duration(seconds: 1));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(charlie);
        final snapshotAt = readdAt.add(const Duration(seconds: 1));
        final readdGroup = await alice.groupRepo.getGroup(groupId);
        final readdMembers = await alice.groupRepo.getMembers(groupId);
        final readdCharlie = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(readdGroup, isNotNull);
        expect(readdCharlie, isNotNull);
        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'member': readdCharlie!.toConfigJson(),
            'groupConfig': buildGroupConfigPayload(readdGroup!, readdMembers),
          }),
          'timestamp': snapshotAt.toIso8601String(),
          'messageId': 'gm024-member-added',
        }, senderDeviceId: alice.deviceId);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await alice.groupRepo.getMembers(groupId))
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              (await bob.groupRepo.getMembers(groupId))
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              (await charlie.groupRepo.getMembers(groupId))
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);

        await expectConverged(alice);
        await expectConverged(bob);
        await expectConverged(charlie);

        alice.bridge.sentMessages.clear();
        bob.bridge.sentMessages.clear();
        charlie.bridge.sentMessages.clear();

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'gm024-charlie-after-readd',
              timestamp: snapshotAt.add(const Duration(milliseconds: 1)),
            );
        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'gm024-alice-after-readd',
              timestamp: readdAt.add(const Duration(milliseconds: 2)),
            );
        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: bobAfterReadd,
          messageId: 'gm024-bob-after-readd',
          timestamp: snapshotAt.add(const Duration(milliseconds: 2)),
        );

        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(bobResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(aliceMessage, isNotNull);
        expect(bobMessage, isNotNull);

        await waitUntil(() async {
          return await incomingTextCount(alice, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, charlieAfterReadd) == 1 &&
              await incomingTextCount(bob, aliceAfterReadd) == 1 &&
              await incomingTextCount(charlie, aliceAfterReadd) == 1 &&
              await incomingTextCount(alice, bobAfterReadd) == 1 &&
              await incomingTextCount(charlie, bobAfterReadd) == 1;
        }, maxTicks: 40);

        expect(await incomingTextCount(alice, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, charlieAfterReadd), 1);
        expect(await incomingTextCount(bob, aliceAfterReadd), 1);
        expect(await incomingTextCount(charlie, aliceAfterReadd), 1);
        expect(await incomingTextCount(alice, bobAfterReadd), 1);
        expect(await incomingTextCount(charlie, bobAfterReadd), 1);

        final charlieRecipients = recipientPeerIdsForMessage(
          charlie,
          'gm024-charlie-after-readd',
        );
        expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
        expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
        final aliceRecipients = recipientPeerIdsForMessage(
          alice,
          'gm024-alice-after-readd',
        );
        expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
        expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));
        final bobRecipients = recipientPeerIdsForMessage(
          bob,
          'gm024-bob-after-readd',
        );
        expect(bobRecipients.toSet(), {alice.peerId, charlie.peerId});
        expect(bobRecipients, hasLength(bobRecipients.toSet().length));

        final allKeys = <String>[
          'aliceGm024AfterReadd',
          'bobGm024AfterReadd',
          'charlieGm024AfterReadd',
        ];
        final aliceProof = await displayStateProof(
          alice,
          actualSendKeys: allKeys,
          sendAccepted:
              aliceResult == group_send.SendGroupMessageResult.success,
        );
        final bobProof = await displayStateProof(
          bob,
          actualSendKeys: allKeys,
          sendAccepted: bobResult == group_send.SendGroupMessageResult.success,
        );
        final charlieProof = await displayStateProof(
          charlie,
          actualSendKeys: allKeys,
          sendAccepted:
              charlieResult == group_send.SendGroupMessageResult.success,
        );
        for (final proof in <Map<String, Object?>>[
          aliceProof,
          bobProof,
          charlieProof,
        ]) {
          expect(proof['charlieMemberEntryCount'], 1);
          expect(proof['charlieRole'], 'writer');
          expect(proof['charlieJoinedStatus'], 'joined');
          expect(proof['charlieCurrentStatus'], 'current');
          expect(proof['activeTransportIdentity'], charlie.deviceId);
          expect(proof['activeCharlieDeviceCount'], 1);
          expect(proof['keyEpoch'], 2);
          expect(proof['composeSendPermission'], isTrue);
          expect(proof['topicJoined'], isTrue);
          expect(proof['livePublishAccepted'], isTrue);
          expect(proof['liveTopicPeerState'], 'joined_with_peers');
          expect(proof['liveTopicPeerCount'], 2);
          expect(proof['exactOnceDelivery'], isTrue);
          expect(proof['durableRecipientsUnique'], isTrue);
        }
      },
    );

    test(
      'GM-025 role change during re-add is honored by all members',
      () async {
        const groupId = 'grp-gm025-role-permission-readd';
        const groupKey = 'gm025-current-key';
        final baseAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 10),
        );
        final oldCharliePermissions = const GroupMemberPermissions(
          removeMembers: true,
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-gm025-alice',
          username: 'Alice',
          network: network,
          deviceId: 'device-gm025-alice',
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm025-bob',
          username: 'Bob',
          network: network,
          deviceId: 'device-gm025-bob',
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm025-charlie',
          username: 'Charlie',
          network: network,
          deviceId: 'device-gm025-charlie',
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: groupKey,
              createdAt: baseAt,
            ),
          );
        }

        Future<GroupMember> currentCharlie(GroupTestUser user) async {
          final member = await user.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          expect(member, isNotNull, reason: '${user.username} missing Charlie');
          return member!;
        }

        Future<void> expectCurrentCharliePolicy(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          final peerIds = members.map((member) => member.peerId).toList();
          expect(peerIds.toSet(), {alice.peerId, bob.peerId, charlie.peerId});
          expect(peerIds, hasLength(peerIds.toSet().length));
          final member = await currentCharlie(user);
          expect(member.role, MemberRole.writer, reason: user.username);
          expect(
            member.permissions.removeMembers,
            isNull,
            reason: user.username,
          );
          expect(
            member.permissions.allows(
              GroupMemberPermission.removeMembers,
              member.role,
            ),
            isFalse,
            reason: user.username,
          );
          expect(member.activeDevices, hasLength(1), reason: user.username);
          expect(
            member.activeDevices.single.transportPeerId,
            charlie.deviceId,
            reason: user.username,
          );
          expect(network.isSubscribed(groupId, user.deviceId), isTrue);
        }

        await alice.createGroup(groupId: groupId, name: 'GM-025 Group');
        await saveKey(alice);
        await alice.addMember(groupId: groupId, invitee: bob, joinedAt: baseAt);
        await saveKey(bob);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baseAt.add(const Duration(minutes: 1)),
          permissions: oldCharliePermissions,
        );
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobCharlie?.permissions.removeMembers == true;
        }, maxTicks: 40);

        final staleBobCharlie = await currentCharlie(bob);
        expect(staleBobCharlie.permissions.removeMembers, isTrue);
        expect(
          staleBobCharlie.permissions.allows(
            GroupMemberPermission.removeMembers,
            staleBobCharlie.role,
          ),
          isTrue,
        );

        final removedAt = DateTime.now().toUtc();
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          return await bob.groupRepo.getMember(groupId, charlie.peerId) ==
                  null &&
              await charlie.groupRepo.getGroup(groupId) == null &&
              !network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);
        expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNull);
        expect(await charlie.groupRepo.getGroup(groupId), isNull);

        await bob.groupRepo.saveMember(
          staleBobCharlie.copyWith(joinedAt: baseAt),
        );
        expect((await currentCharlie(bob)).permissions.removeMembers, isTrue);

        final readdAt = DateTime.now().toUtc();
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(charlie);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieSelf = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return aliceCharlie?.permissions.removeMembers != true &&
              bobCharlie?.permissions.removeMembers != true &&
              charlieSelf?.permissions.removeMembers != true &&
              network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);

        await expectCurrentCharliePolicy(alice);
        await expectCurrentCharliePolicy(bob);
        await expectCurrentCharliePolicy(charlie);

        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        final groupConfig = buildGroupConfigPayload(
          charlieGroup!,
          charlieMembers,
        );
        final configCharlie = (groupConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .singleWhere((member) => member['peerId'] == charlie.peerId);
        expect(configCharlie['role'], 'writer');
        expect(configCharlie['permissions'], isNull);

        final actionAt = DateTime.now().toUtc();
        final deniedActionText = jsonEncode({
          '__sys': 'member_banned',
          'targetPeerId': bob.peerId,
          'targetUsername': bob.username,
          'bannedAt': actionAt.toIso8601String(),
          'groupConfig': groupConfig,
        });
        final (actionResult, actionMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: deniedActionText,
              messageId: 'gm025-charlie-stale-remove-members-action',
              timestamp: actionAt,
            );
        expect(actionResult, group_send.SendGroupMessageResult.success);
        expect(actionMessage, isNotNull);
        await pump();
        await pump();

        expect(await alice.groupRepo.getMember(groupId, bob.peerId), isNotNull);
        expect(await bob.groupRepo.getGroup(groupId), isNotNull);
        expect(await bob.groupRepo.getMember(groupId, bob.peerId), isNotNull);
        expect(
          await charlie.groupRepo.getMember(groupId, bob.peerId),
          isNotNull,
        );
        for (final user in <GroupTestUser>[alice, bob]) {
          final tombstones = (await user.loadGroupMessages(groupId))
              .where((message) => message.id.startsWith('sys-member_banned:'))
              .toList(growable: false);
          expect(tombstones, isEmpty, reason: user.username);
        }
      },
    );

    test(
      'GM-029 config version monotonicity converges across A/B/C shuffled delivery',
      () async {
        const groupId = 'grp-gm029-config-version-monotonicity';
        const finalText = 'GM-029 Alice after monotonic convergence';
        final baseAt = DateTime.utc(2026, 5, 11, 12);
        final version1 = baseAt.add(const Duration(seconds: 1));
        final version2 = baseAt.add(const Duration(seconds: 2));
        final version3 = baseAt.add(const Duration(seconds: 3));
        final version4 = baseAt.add(const Duration(seconds: 4));
        final deliveryBase = baseAt.add(const Duration(minutes: 1));

        final alice = GroupTestUser.create(
          peerId: 'peer-gm029-alice',
          username: 'Alice',
          network: network,
        );
        final aliceControl = GroupTestUser.create(
          peerId: alice.peerId,
          username: alice.username,
          network: network,
          deviceId: 'device-gm029-alice-control',
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm029-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm029-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          aliceControl.dispose();
          bob.dispose();
          charlie.dispose();
        });

        GroupMember memberFor(
          GroupTestUser user, {
          required MemberRole role,
          required DateTime joinedAt,
          GroupMemberPermissions permissions = GroupMemberPermissions.empty,
          List<GroupMemberDeviceIdentity>? devices,
        }) {
          return GroupMember(
            groupId: groupId,
            peerId: user.peerId,
            username: user.username,
            role: role,
            permissions: permissions,
            publicKey: user.publicKey,
            mlKemPublicKey: 'mlkem-${user.peerId}',
            devices: devices ?? [user.deviceIdentity],
            joinedAt: joinedAt,
          );
        }

        Map<String, dynamic> versionedConfig({
          required DateTime version,
          required List<GroupMember> members,
        }) {
          final payload = <String, dynamic>{
            'name': 'GM-029 Group',
            'groupType': 'chat',
            'members': members
                .map((member) => member.toConfigJson())
                .toList(growable: false),
            'createdBy': alice.peerId,
            'createdAt': baseAt.toIso8601String(),
            groupConfigVersionField: version.toUtc().toIso8601String(),
          };
          return {
            ...payload,
            groupConfigStateHashField: buildGroupConfigStateHash(
              groupId: groupId,
              groupConfig: payload,
            ),
          };
        }

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required DateTime createdAt,
        }) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'gm029-key-epoch-$epoch',
              createdAt: createdAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Map<String, dynamic> finalBridgeConfig(GroupTestUser user) {
          for (final raw in user.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:updateConfig') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            return payload['groupConfig'] as Map<String, dynamic>;
          }
          fail('missing group:updateConfig for ${user.peerId}');
        }

        Future<void> expectConverged(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} group');
          expect(group!.lastMembershipEventAt, version4);
          final members = await user.groupRepo.getMembers(groupId);
          final peerIds = members.map((member) => member.peerId).toList();
          expect(peerIds.toSet(), {alice.peerId, bob.peerId, charlie.peerId});
          expect(peerIds, hasLength(peerIds.toSet().length));

          final charlieRows = members
              .where((member) => member.peerId == charlie.peerId)
              .toList(growable: false);
          expect(charlieRows, hasLength(1), reason: user.peerId);
          expect(charlieRows.single.role, MemberRole.writer);
          expect(charlieRows.single.permissions.deleteMessages, isTrue);
          expect(charlieRows.single.activeDevices, hasLength(1));
          expect(
            charlieRows.single.activeDevices.single.transportPeerId,
            charlie.deviceId,
          );

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: '${user.peerId} key');
          expect(latestKey!.keyGeneration, 3);
          expect(latestKey.encryptedKey, 'gm029-key-epoch-3');
          expect(network.isSubscribed(groupId, user.deviceId), isTrue);
          expect(user.bridge.commandLog, isNot(contains('group:leave')));

          final bridgeConfig = finalBridgeConfig(user);
          expect(
            bridgeConfig[groupConfigVersionField],
            version4.toIso8601String(),
          );
          final configMembers = (bridgeConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(configMembers.map((member) => member['peerId']).toSet(), {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
          });
          final configCharlie = configMembers.singleWhere(
            (member) => member['peerId'] == charlie.peerId,
          );
          expect(configCharlie['role'], 'writer');
          expect(configCharlie['permissions'], {'deleteMessages': true});
        }

        Future<void> publishSystemEvent({
          required String messageId,
          required Map<String, dynamic> systemPayload,
          required int keyEpoch,
          required DateTime deliveryAt,
        }) async {
          await network.publish(groupId, alice.peerId, {
            'groupId': groupId,
            'senderId': alice.peerId,
            'senderUsername': alice.username,
            'keyEpoch': keyEpoch,
            'text': jsonEncode(systemPayload),
            'timestamp': deliveryAt.toIso8601String(),
            'messageId': messageId,
          }, senderDeviceId: aliceControl.deviceId);
          await pump();
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-029 Group',
          createdAt: baseAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: version1,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: version1,
        );
        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          await saveKey(user, epoch: 1, createdAt: version1);
        }

        final aliceMember = memberFor(
          alice,
          role: MemberRole.admin,
          joinedAt: baseAt,
          devices: [alice.deviceIdentity, aliceControl.deviceIdentity],
        );
        final bobMember = memberFor(
          bob,
          role: MemberRole.writer,
          joinedAt: version1,
        );
        final charlieWriterV1 = memberFor(
          charlie,
          role: MemberRole.writer,
          joinedAt: version1,
        );
        final charlieReaderV3 = memberFor(
          charlie,
          role: MemberRole.reader,
          joinedAt: version3,
        );
        final charlieWriterV4 = memberFor(
          charlie,
          role: MemberRole.writer,
          joinedAt: version3,
          permissions: const GroupMemberPermissions(deleteMessages: true),
        );

        final configV1 = versionedConfig(
          version: version1,
          members: [aliceMember, bobMember, charlieWriterV1],
        );
        final configV2 = versionedConfig(
          version: version2,
          members: [aliceMember, bobMember],
        );
        final configV3 = versionedConfig(
          version: version3,
          members: [aliceMember, bobMember, charlieReaderV3],
        );
        final configV4 = versionedConfig(
          version: version4,
          members: [aliceMember, bobMember, charlieWriterV4],
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        network.holdDeliveriesFor(bob.deviceId);
        network.holdDeliveriesFor(charlie.deviceId);

        await publishSystemEvent(
          messageId: 'gm029-v4-role',
          keyEpoch: 3,
          deliveryAt: deliveryBase.add(const Duration(seconds: 1)),
          systemPayload: {
            '__sys': 'member_role_updated',
            'member': charlieWriterV4.toConfigJson(),
            'groupConfig': configV4,
          },
        );
        await publishSystemEvent(
          messageId: 'gm029-v3-readd',
          keyEpoch: 3,
          deliveryAt: deliveryBase.add(const Duration(seconds: 2)),
          systemPayload: {
            '__sys': 'member_added',
            'eventAt': version3.toIso8601String(),
            'member': charlieReaderV3.toConfigJson(),
            'groupConfig': configV3,
          },
        );

        network.deliveryDelay = const Duration(milliseconds: 20);
        await network.releaseHeldDeliveriesFor(charlie.deviceId, reverse: true);
        await pump();

        await publishSystemEvent(
          messageId: 'gm029-v2-remove',
          keyEpoch: 2,
          deliveryAt: deliveryBase.add(const Duration(seconds: 3)),
          systemPayload: {
            '__sys': 'member_removed',
            'member': {'peerId': charlie.peerId, 'username': charlie.username},
            'removedAt': version2.toIso8601String(),
            'groupConfig': configV2,
          },
        );
        await publishSystemEvent(
          messageId: 'gm029-v1-baseline',
          keyEpoch: 1,
          deliveryAt: deliveryBase.add(const Duration(seconds: 4)),
          systemPayload: {
            '__sys': 'members_added',
            'eventAt': version1.toIso8601String(),
            'members': [charlieWriterV1.toConfigJson()],
            'groupConfig': configV1,
          },
        );
        await network.releaseHeldDeliveriesFor(bob.deviceId, reverse: true);
        network.deliveryDelay = null;

        await waitUntil(() async {
          final aliceGroup = await alice.groupRepo.getGroup(groupId);
          final bobGroup = await bob.groupRepo.getGroup(groupId);
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieSelf = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return aliceGroup?.lastMembershipEventAt == version4 &&
              bobGroup?.lastMembershipEventAt == version4 &&
              charlieGroup?.lastMembershipEventAt == version4 &&
              aliceCharlie?.role == MemberRole.writer &&
              bobCharlie?.role == MemberRole.writer &&
              charlieSelf?.role == MemberRole.writer &&
              aliceCharlie?.permissions.deleteMessages == true &&
              bobCharlie?.permissions.deleteMessages == true &&
              charlieSelf?.permissions.deleteMessages == true;
        }, maxTicks: 80);

        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          await saveKey(user, epoch: 3, createdAt: version3);
          await saveKey(user, epoch: 2, createdAt: version2);
        }

        await expectConverged(alice);
        await expectConverged(bob);
        await expectConverged(charlie);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        alice.bridge.sentMessages.clear();
        bob.bridge.sentMessages.clear();
        charlie.bridge.sentMessages.clear();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: finalText,
          messageId: 'gm029-alice-after-convergence',
          timestamp: version4.add(const Duration(minutes: 1)),
        );
        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 3);
        final recipients = recipientPeerIdsForMessage(alice, sentMessage.id);
        expect(recipients.toSet(), {bob.peerId, charlie.peerId});
        expect(recipients, hasLength(recipients.toSet().length));

        await waitUntil(() async {
          return await incomingTextCount(bob, finalText) == 1 &&
              await incomingTextCount(charlie, finalText) == 1;
        }, maxTicks: 40);
        expect(await incomingTextCount(bob, finalText), 1);
        expect(await incomingTextCount(charlie, finalText), 1);
      },
    );

    test(
      'GM-034 valid A message survives unrelated Charlie config update in both delivery orders',
      () async {
        Future<void> runOrderCase({
          required String orderName,
          required bool reverseRelease,
        }) async {
          final groupId = 'grp-gm034-$orderName';
          final createdAt = DateTime.utc(2026, 5, 11, 13);
          final messageAt = createdAt.add(const Duration(minutes: 10));
          final removedAt = createdAt.add(const Duration(minutes: 11));
          final messageId = 'gm034-$orderName-alice-valid';
          final messageText =
              'GM-034 Alice valid while config updates $orderName';

          final alice = GroupTestUser.create(
            peerId: 'peer-gm034-alice-$orderName',
            username: 'Alice',
            network: network,
          );
          final bob = GroupTestUser.create(
            peerId: 'peer-gm034-bob-$orderName',
            username: 'Bob',
            network: network,
          );
          final charlie = GroupTestUser.create(
            peerId: 'peer-gm034-charlie-$orderName',
            username: 'Charlie',
            network: network,
          );

          try {
            Future<void> saveKey(GroupTestUser user) {
              return user.groupRepo.saveKey(
                GroupKeyInfo(
                  groupId: groupId,
                  keyGeneration: 1,
                  encryptedKey: 'gm034-group-key-$orderName',
                  createdAt: createdAt,
                ),
              );
            }

            Future<int> bobMessageCount(String id) async {
              return (await bob.loadGroupMessages(groupId))
                  .where((message) => message.id == id && message.isIncoming)
                  .length;
            }

            Map<String, dynamic> latestBobBridgeConfig() {
              for (final raw in bob.bridge.sentMessages.reversed) {
                final parsed = jsonDecode(raw) as Map<String, dynamic>;
                if (parsed['cmd'] != 'group:updateConfig') continue;
                final payload = parsed['payload'] as Map<String, dynamic>;
                return payload['groupConfig'] as Map<String, dynamic>;
              }
              fail('missing Bob group:updateConfig for $orderName');
            }

            await alice.createGroup(
              groupId: groupId,
              name: 'GM-034 $orderName',
              createdAt: createdAt,
            );
            await saveKey(alice);
            await alice.addMember(
              groupId: groupId,
              invitee: bob,
              joinedAt: createdAt.add(const Duration(minutes: 1)),
            );
            await saveKey(bob);
            await alice.addMember(
              groupId: groupId,
              invitee: charlie,
              joinedAt: createdAt.add(const Duration(minutes: 2)),
            );
            await saveKey(charlie);

            alice.start();
            bob.start();
            charlie.start();
            await pump();

            network.holdDeliveriesFor(bob.peerId);

            final (sendResult, sentMessage) = await alice
                .sendGroupMessageViaBridge(
                  groupId: groupId,
                  text: messageText,
                  messageId: messageId,
                  timestamp: messageAt,
                );
            expect(sendResult, group_send.SendGroupMessageResult.success);
            expect(sentMessage, isNotNull);
            expect(sentMessage!.id, messageId);

            await alice.removeMember(
              groupId: groupId,
              memberPeerId: charlie.peerId,
              memberUsername: charlie.username,
              removedAt: removedAt,
            );
            expect(network.heldDeliveryCountFor(bob.peerId), 2);

            await network.releaseHeldDeliveriesFor(
              bob.peerId,
              reverse: reverseRelease,
            );

            await waitUntil(() async {
              final bobGroup = await bob.groupRepo.getGroup(groupId);
              final bobCharlie = await bob.groupRepo.getMember(
                groupId,
                charlie.peerId,
              );
              return await bobMessageCount(messageId) == 1 &&
                  bobCharlie == null &&
                  bobGroup?.lastMembershipEventAt == removedAt;
            }, maxTicks: 60);

            final bobMessages = await bob.loadGroupMessages(groupId);
            final deliveredMessages = bobMessages
                .where((message) => message.id == messageId)
                .toList(growable: false);
            expect(deliveredMessages, hasLength(1), reason: orderName);
            expect(deliveredMessages.single.isIncoming, isTrue);
            expect(deliveredMessages.single.senderPeerId, alice.peerId);
            expect(deliveredMessages.single.text, messageText);
            expect(deliveredMessages.single.keyGeneration, 1);

            final emptySurrogates = bobMessages
                .where(
                  (message) =>
                      message.senderPeerId == alice.peerId &&
                      message.text.isEmpty,
                )
                .toList(growable: false);
            expect(emptySurrogates, isEmpty, reason: orderName);

            final timelineMessages = bobMessages
                .where(
                  (message) =>
                      message.id.startsWith('sys-member_removed:$groupId:') &&
                      message.text == 'Alice removed Charlie',
                )
                .toList(growable: false);
            expect(timelineMessages, hasLength(1), reason: orderName);
            expect(timelineMessages.single.timestamp, removedAt);

            final bobGroup = await bob.groupRepo.getGroup(groupId);
            expect(bobGroup, isNotNull);
            expect(bobGroup!.lastMembershipEventAt, removedAt);
            final bobMembers = await bob.groupRepo.getMembers(groupId);
            expect(bobMembers.map((member) => member.peerId).toSet(), {
              alice.peerId,
              bob.peerId,
            });

            final bridgeConfig = latestBobBridgeConfig();
            final configPeerIds = (bridgeConfig['members'] as List<dynamic>)
                .cast<Map<String, dynamic>>()
                .map((member) => member['peerId'] as String)
                .toSet();
            expect(configPeerIds, {alice.peerId, bob.peerId});
          } finally {
            alice.dispose();
            bob.dispose();
            charlie.dispose();
          }
        }

        await runOrderCase(
          orderName: 'message_then_config',
          reverseRelease: false,
        );
        await runOrderCase(
          orderName: 'config_then_message',
          reverseRelease: true,
        );
      },
    );

    test(
      'RA-010 re-added member sees first incoming before and after restart',
      () async {
        const groupId = 'grp-ra010-incoming-restart';
        const initialKey = 'ra010-initial-key';
        const rejoinKeyValue = 'ra010-rejoin-key';
        const beforeRestart = 'RA-010 Alice first incoming before restart';
        const afterRestart = 'RA-010 Alice incoming after restart';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-ra010-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra010-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra010-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        Future<List<GroupMessage>> charlieIncomingWith(String text) async {
          return (await charlie.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .toList();
        }

        await alice.createGroup(groupId: groupId, name: 'RA-010 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 40);
        charlie.subscribeToGroup(groupId);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        await bob.groupRepo.saveKey(rejoinKey);

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(alice)).containsAll(expectedMembers) &&
              (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        final (beforeResult, beforeMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: beforeRestart,
              messageId: 'ra010-alice-before-charlie-restart',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        expect(beforeResult, group_send.SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        expect(beforeMessage!.keyGeneration, 2);
        await waitUntil(
          () async => (await charlieIncomingWith(beforeRestart)).isNotEmpty,
          maxTicks: 40,
        );
        expect(await charlieIncomingWith(beforeRestart), hasLength(1));
        expect(
          (await charlieIncomingWith(beforeRestart)).single.keyGeneration,
          2,
        );

        charlie.groupMessageListener.stop();
        await pump();
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );
        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(
          await memberSet(charlie),
          containsAll([alice.peerId, bob.peerId, charlie.peerId]),
        );
        charlie.start();
        await pump();

        final (afterResult, afterMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: afterRestart,
              messageId: 'ra010-alice-after-charlie-restart',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        expect(afterResult, group_send.SendGroupMessageResult.success);
        expect(afterMessage, isNotNull);
        expect(afterMessage!.keyGeneration, 2);
        await waitUntil(
          () async => (await charlieIncomingWith(afterRestart)).isNotEmpty,
          maxTicks: 40,
        );
        expect(await charlieIncomingWith(afterRestart), hasLength(1));
        expect(
          (await charlieIncomingWith(afterRestart)).single.keyGeneration,
          2,
        );
      },
    );

    test(
      'RA-011 immediate re-add before late leave completion keeps Charlie active',
      () async {
        const groupId = 'grp-ra011-late-leave-readd';
        const initialKey = 'ra011-initial-key';
        const rejoinKeyValue = 'ra011-rejoin-key';
        const aliceAfterLateLeave = 'RA-011 Alice after late leave re-add';
        const charlieAfterLateLeave = 'RA-011 Charlie after late leave repair';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final delayedLeaveBridge = _DelayedGroupLeaveBridge();
        final alice = GroupTestUser.create(
          peerId: 'peer-ra011-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra011-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ra011-charlie',
          username: 'Charlie',
          network: network,
          bridge: delayedLeaveBridge,
        );
        delayedLeaveBridge.onLateLeaveCompleted = () {
          charlie.unsubscribeFromGroup(groupId);
        };
        delayedLeaveBridge.onJoin = () {
          charlie.subscribeToGroup(groupId);
        };
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        Future<List<GroupMessage>> messagesWith(
          GroupTestUser user,
          String text,
        ) async {
          return (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.text == text).toList();
        }

        await alice.createGroup(groupId: groupId, name: 'RA-011 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await delayedLeaveBridge.leaveStarted.future.timeout(
          const Duration(seconds: 2),
        );

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        await bob.groupRepo.saveKey(rejoinKey);

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: rejoinKeyCreatedAt,
        );
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          return (await memberSet(alice)).containsAll(expectedMembers) &&
              (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(charlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        delayedLeaveBridge.completeLeave();
        await waitUntil(
          () async => delayedLeaveBridge.joinCalls == 1,
          maxTicks: 40,
        );

        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterLateLeave,
              messageId: 'ra011-alice-after-late-leave',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        await waitUntil(
          () async => (await messagesWith(
            charlie,
            aliceAfterLateLeave,
          )).where((message) => message.isIncoming).isNotEmpty,
          maxTicks: 40,
        );

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterLateLeave,
              messageId: 'ra011-charlie-after-late-leave',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);
        await waitUntil(() async {
          return (await messagesWith(
                alice,
                charlieAfterLateLeave,
              )).where((message) => message.isIncoming).length ==
              1;
        }, maxTicks: 40);
        await waitUntil(() async {
          return (await messagesWith(
                bob,
                charlieAfterLateLeave,
              )).where((message) => message.isIncoming).length ==
              1;
        }, maxTicks: 40);

        expect(
          delayedLeaveBridge.commandLog.where((cmd) => cmd == 'group:leave'),
          hasLength(1),
        );
        expect(
          delayedLeaveBridge.commandLog.indexOf('group:join'),
          greaterThan(delayedLeaveBridge.commandLog.indexOf('group:leave')),
        );
        expect(await memberSet(charlie), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
        expect(
          (await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          ))!.joinedAt,
          rejoinKeyCreatedAt.toUtc(),
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );
        expect(await messagesWith(charlie, aliceAfterLateLeave), hasLength(1));
        expect(await messagesWith(alice, charlieAfterLateLeave), hasLength(1));
        expect(await messagesWith(bob, charlieAfterLateLeave), hasLength(1));
      },
    );

    test(
      'RA-012 rotated device keys replace old material on same-peer re-add',
      () async {
        const groupId = 'grp-ra012-rotated-device-readd';
        const initialKey = 'ra012-initial-key';
        const rejoinKeyValue = 'ra012-rejoin-key';
        const aliceAfterReadd = 'RA-012 Alice after rotated re-add';
        const charlieAfterReadd = 'RA-012 Charlie after rotated re-add';
        const charliePeerId = 'peer-ra012-charlie';
        const oldCharliePublicKey = 'pk-ra012-charlie-old';
        const oldCharlieMlKem = 'mlkem-ra012-charlie-old';
        const oldCharliePackage = 'kp-ra012-charlie-old';
        const newCharliePublicKey = 'pk-ra012-charlie-new';
        const newCharlieMlKem = 'mlkem-ra012-charlie-new';
        const newCharliePackage = 'kp-ra012-charlie-new';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );

        final alice = GroupTestUser.create(
          peerId: 'peer-ra012-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra012-bob',
          username: 'Bob',
          network: network,
        );
        final oldCharlie = GroupTestUser.create(
          peerId: charliePeerId,
          username: 'Charlie',
          network: network,
          publicKey: oldCharliePublicKey,
          privateKey: 'sk-ra012-charlie-old',
          mlKemPublicKey: oldCharlieMlKem,
          keyPackageId: oldCharliePackage,
          keyPackagePublicMaterial: 'kpm-ra012-charlie-old',
        );
        var oldCharlieDisposed = false;
        GroupTestUser? restoredCharlie;
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          if (!oldCharlieDisposed) {
            oldCharlie.dispose();
          }
          restoredCharlie?.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        Future<List<GroupMessage>> incomingMessagesWith(
          GroupTestUser user,
          String text,
        ) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.text == text && message.isIncoming)
              .toList();
        }

        Future<void> expectRotatedCharlie(GroupTestUser user) async {
          final member = await user.groupRepo.getMember(groupId, charliePeerId);
          expect(member, isNotNull, reason: '${user.peerId} missing Charlie');
          expect(member!.publicKey, newCharliePublicKey);
          expect(member.mlKemPublicKey, newCharlieMlKem);
          expect(
            member.devices.map((device) => device.deviceSigningPublicKey),
            contains(newCharliePublicKey),
          );
          expect(
            member.devices.map((device) => device.deviceSigningPublicKey),
            isNot(contains(oldCharliePublicKey)),
          );
          expect(
            member.devices.map((device) => device.mlKemPublicKey),
            contains(newCharlieMlKem),
          );
          expect(
            member.devices.map((device) => device.mlKemPublicKey),
            isNot(contains(oldCharlieMlKem)),
          );
          expect(
            member.devices.map((device) => device.keyPackageId),
            contains(newCharliePackage),
          );
          expect(
            member.devices.map((device) => device.keyPackageId),
            isNot(contains(oldCharliePackage)),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'RA-012 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: oldCharlie);
        await saveKey(
          oldCharlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        oldCharlie.start();
        await pump();
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: oldCharlie,
        );
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, oldCharlie.peerId};
          return (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(oldCharlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: oldCharlie.peerId,
          memberUsername: oldCharlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          return !(await memberSet(bob)).contains(oldCharlie.peerId) &&
              !(await memberSet(oldCharlie)).contains(oldCharlie.peerId);
        }, maxTicks: 40);
        oldCharlie.dispose();
        oldCharlieDisposed = true;

        final activeCharlie = GroupTestUser.create(
          peerId: charliePeerId,
          username: 'Charlie',
          network: network,
          publicKey: newCharliePublicKey,
          privateKey: 'sk-ra012-charlie-new',
          mlKemPublicKey: newCharlieMlKem,
          keyPackageId: newCharliePackage,
          keyPackagePublicMaterial: 'kpm-ra012-charlie-new',
        );
        restoredCharlie = activeCharlie;
        activeCharlie.start();

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        expect(rejoinKey!.keyGeneration, 2);
        await bob.groupRepo.saveKey(rejoinKey);

        await alice.addMember(
          groupId: groupId,
          invitee: activeCharlie,
          joinedAt: rejoinKeyCreatedAt,
        );
        await saveKey(
          activeCharlie,
          epoch: rejoinKey.keyGeneration,
          encryptedKey: rejoinKey.encryptedKey,
          createdAt: rejoinKeyCreatedAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: activeCharlie,
          eventAt: rejoinKeyCreatedAt,
        );
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charliePeerId};
          return (await memberSet(alice)).containsAll(expectedMembers) &&
              (await memberSet(bob)).containsAll(expectedMembers) &&
              (await memberSet(activeCharlie)).containsAll(expectedMembers);
        }, maxTicks: 40);

        await expectRotatedCharlie(alice);
        await expectRotatedCharlie(bob);
        await expectRotatedCharlie(activeCharlie);

        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterReadd,
              messageId: 'ra012-alice-after-rotated-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 1)),
            );
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(aliceMessage, isNotNull);
        expect(aliceMessage!.keyGeneration, 2);
        await waitUntil(
          () async =>
              (await incomingMessagesWith(
                activeCharlie,
                aliceAfterReadd,
              )).length ==
              1,
          maxTicks: 40,
        );

        final (charlieResult, charlieMessage) = await activeCharlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieAfterReadd,
              messageId: 'ra012-charlie-after-rotated-readd',
              timestamp: rejoinKeyCreatedAt.add(const Duration(seconds: 2)),
            );
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, 2);
        await waitUntil(() async {
          return (await incomingMessagesWith(
                alice,
                charlieAfterReadd,
              )).length ==
              1;
        }, maxTicks: 40);
        await waitUntil(() async {
          return (await incomingMessagesWith(bob, charlieAfterReadd)).length ==
              1;
        }, maxTicks: 40);
      },
    );

    test(
      'RA-013 same-user devices keep pending and joined state truthful through re-add',
      () async {
        const groupId = 'grp-ra013-same-user-devices';
        const initialKey = 'ra013-initial-key';
        const rejoinKeyValue = 'ra013-rejoin-key';
        const charliePeerId = 'peer-ra013-charlie';
        const removedWindowText = 'RA-013 removed-window message';
        const aliceAfterPhoneAccept = 'RA-013 Alice after C1 accept';
        const bobAfterPhoneAccept = 'RA-013 Bob after C1 accept';
        const tabletAfterOwnAccept = 'RA-013 C2 after own accept';
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final initialJoinedAt = initialKeyCreatedAt.add(
          const Duration(minutes: 1),
        );
        late final DateTime removedAt;
        late final DateTime removedWindowAt;
        late final DateTime rejoinKeyCreatedAt;
        late final DateTime inviteReceivedAt;
        late final DateTime phoneAcceptAt;
        late final DateTime tabletAcceptAt;

        final alice = GroupTestUser.create(
          peerId: 'peer-ra013-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ra013-bob',
          username: 'Bob',
          network: network,
        );
        final charliePhone = GroupTestUser.create(
          peerId: charliePeerId,
          deviceId: 'peer-ra013-charlie-phone',
          username: 'Charlie',
          network: network,
          publicKey: 'pk-ra013-charlie-phone',
          privateKey: 'sk-ra013-charlie-phone',
          mlKemPublicKey: 'mlkem-ra013-charlie-phone',
          keyPackageId: 'kp-ra013-charlie-phone',
          keyPackagePublicMaterial: 'kpm-ra013-charlie-phone',
        );
        final charlieTablet = GroupTestUser.create(
          peerId: charliePeerId,
          deviceId: 'peer-ra013-charlie-tablet',
          username: 'Charlie',
          network: network,
          publicKey: 'pk-ra013-charlie-tablet',
          privateKey: 'sk-ra013-charlie-tablet',
          mlKemPublicKey: 'mlkem-ra013-charlie-tablet',
          keyPackageId: 'kp-ra013-charlie-tablet',
          keyPackagePublicMaterial: 'kpm-ra013-charlie-tablet',
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charliePhone.dispose();
          charlieTablet.dispose();
        });

        ContactModel contactFor(GroupTestUser user) {
          return ContactModel(
            peerId: user.peerId,
            publicKey: user.publicKey,
            rendezvous: '/ip4/0.0.0.0',
            username: user.username,
            signature: 'sig-${user.deviceId}',
            scannedAt: initialKeyCreatedAt.toIso8601String(),
            mlKemPublicKey: user.mlKemPublicKey,
          );
        }

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        GroupMember charlieMember(DateTime joinedAt) {
          return GroupMember(
            groupId: groupId,
            peerId: charliePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: charliePhone.publicKey,
            mlKemPublicKey: charliePhone.mlKemPublicKey,
            devices: [
              charliePhone.deviceIdentity,
              charlieTablet.deviceIdentity,
            ],
            joinedAt: joinedAt.toUtc(),
          );
        }

        Future<void> seedMemberOn(
          GroupTestUser user,
          GroupMember member,
        ) async {
          await user.groupRepo.saveMember(member);
        }

        Future<void> seedReplica(GroupTestUser user) async {
          final group = await alice.groupRepo.getGroup(groupId);
          expect(group, isNotNull);
          await user.groupRepo.saveGroup(
            group!.copyWith(myRole: GroupRole.member),
          );
          final members = await alice.groupRepo.getMembers(groupId);
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await saveKey(
            user,
            epoch: 1,
            encryptedKey: initialKey,
            createdAt: initialKeyCreatedAt,
          );
          user.subscribeToGroup(groupId);
        }

        Future<Set<String>> memberSet(GroupTestUser user) async {
          return (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
        }

        Future<Set<String>> charlieDeviceSet(GroupTestUser user) async {
          final member = await user.groupRepo.getMember(groupId, charliePeerId);
          if (member == null) return const <String>{};
          return member.devices.map((device) => device.deviceId).toSet();
        }

        List<String> inboxStoreRecipientPeerIds(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final message = payload['message'] as String;
            final envelope = jsonDecode(message) as Map<String, dynamic>;
            if (envelope['messageId'] == messageId) {
              return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                  .cast<String>();
            }
          }
          throw StateError('No inbox store payload for $messageId');
        }

        Map<String, dynamic> inboxRetrieveMessageFor(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final message = payload['message'] as String;
            final envelope = jsonDecode(message) as Map<String, dynamic>;
            if (envelope['messageId'] == messageId) {
              return {'from': sender.peerId, 'message': message};
            }
          }
          throw StateError('No replay envelope for $messageId');
        }

        PendingGroupInvite makeDeviceInvite({
          required GroupTestUser device,
          required String inviteId,
          required Map<String, dynamic> groupConfig,
          required GroupKeyInfo keyInfo,
          required DateTime receivedAt,
        }) {
          final expiresAt = receivedAt.add(pendingGroupInviteTtl);
          final welcome = GroupWelcomeKeyPackage.create(
            packageId: device.keyPackageId,
            publicMaterial: device.keyPackagePublicMaterial,
            recipientPeerId: device.peerId,
            recipientDeviceId: device.deviceId,
            recipientTransportPeerId: device.deviceId,
            recipientMlKemPublicKey: device.mlKemPublicKey,
            inviteId: inviteId,
            groupId: groupId,
            keyEpoch: keyInfo.keyGeneration,
            issuedAt: receivedAt,
            expiresAt: expiresAt,
          );
          final stateHash = buildGroupConfigStateHash(
            groupId: groupId,
            groupConfig: groupConfig,
          );
          final payload = GroupInvitePayload(
            id: inviteId,
            groupId: groupId,
            groupKey: keyInfo.encryptedKey,
            keyEpoch: keyInfo.keyGeneration,
            groupConfig: groupConfig,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            timestamp: receivedAt.toIso8601String(),
            recipientPeerId: device.peerId,
            recipientDeviceId: device.deviceId,
            recipientTransportPeerId: device.deviceId,
            recipientMlKemPublicKey: device.mlKemPublicKey,
            recipientKeyPackageId: device.keyPackageId,
            recipientKeyPackagePublicMaterial: device.keyPackagePublicMaterial,
            welcomeKeyPackage: welcome,
            senderDeviceId: alice.deviceId,
            senderTransportPeerId: alice.deviceId,
            senderDeviceSigningPublicKey: alice.publicKey,
            senderKeyPackageId: alice.keyPackageId,
            invitePolicy: GroupInvitePolicy(
              expiresAt: expiresAt,
              allowedDevices: [device.deviceId],
              assignedRole: 'writer',
              canInviteOthers: false,
              joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
              keyEpoch: keyInfo.keyGeneration,
              reusePolicy: GroupInviteReusePolicy.singleUse,
              welcomeKeyPackageId: welcome.packageId,
              welcomeKeyPackagePublicMaterialHash: welcome.publicMaterialHash,
              welcomeKeyPackageExpiresAt: welcome.expiresAt,
            ),
            membershipFreshnessProof: GroupInviteMembershipFreshnessProof(
              inviteId: inviteId,
              groupId: groupId,
              recipientPeerId: device.peerId,
              recipientDeviceId: device.deviceId,
              recipientTransportPeerId: device.deviceId,
              recipientMlKemPublicKey: device.mlKemPublicKey,
              recipientKeyPackageId: device.keyPackageId,
              recipientKeyPackagePublicMaterial:
                  device.keyPackagePublicMaterial,
              inviterPeerId: alice.peerId,
              inviterDeviceId: alice.deviceId,
              inviterTransportPeerId: alice.deviceId,
              inviterDeviceSigningPublicKey: alice.publicKey,
              inviterKeyPackageId: alice.keyPackageId,
              inviterPublicKey: alice.publicKey,
              keyEpoch: keyInfo.keyGeneration,
              groupConfigStateHash: stateHash,
              membershipWatermark: stateHash,
              issuedAt: receivedAt,
              expiresAt: receivedAt.add(groupInviteMembershipFreshnessTtl),
              inviterMemberSnapshot: {
                'peerId': alice.peerId,
                'username': alice.username,
                'role': 'admin',
                'publicKey': alice.publicKey,
                'devices': [alice.deviceIdentity.toJson()],
              },
            ),
          ).withInviteSignature(signature: 'signed-$inviteId');

          return PendingGroupInvite.fromPayload(
            payload,
            receivedAt: receivedAt,
          );
        }

        Future<(AcceptPendingGroupInviteResult, GroupModel?)> acceptDevice({
          required GroupTestUser device,
          required InMemoryPendingGroupInviteRepository pendingRepo,
          required DateTime now,
        }) {
          return acceptPendingGroupInvite(
            pendingInviteRepo: pendingRepo,
            groupRepo: device.groupRepo,
            contactRepo: FakeContactRepository()..seed([contactFor(alice)]),
            msgRepo: device.msgRepo,
            bridge: device.bridge,
            groupId: groupId,
            senderPeerId: device.peerId,
            senderPublicKey: device.publicKey,
            senderPrivateKey: device.privateKey,
            senderUsername: device.username,
            ownDeviceId: device.deviceId,
            ownTransportPeerId: device.deviceId,
            ownMlKemPublicKey: device.mlKemPublicKey,
            ownKeyPackageId: device.keyPackageId,
            ownKeyPackagePublicMaterial: device.keyPackagePublicMaterial,
            now: now,
            drainAcceptedInboxAllPages: true,
          );
        }

        await alice.createGroup(groupId: groupId, name: 'RA-013 Group');
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: initialKeyCreatedAt,
        );
        final initialCharlie = charlieMember(initialJoinedAt);
        await seedMemberOn(alice, initialCharlie);
        await seedMemberOn(bob, initialCharlie);
        await seedReplica(charliePhone);
        await seedReplica(charlieTablet);

        alice.start();
        bob.start();
        charliePhone.start();
        charlieTablet.start();
        await pump();

        removedAt = DateTime.now().toUtc();
        removedWindowAt = removedAt.add(const Duration(seconds: 10));
        rejoinKeyCreatedAt = removedAt.add(const Duration(minutes: 1));
        inviteReceivedAt = rejoinKeyCreatedAt.add(const Duration(seconds: 5));
        phoneAcceptAt = inviteReceivedAt.add(const Duration(seconds: 5));
        tabletAcceptAt = phoneAcceptAt.add(const Duration(minutes: 1));

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charliePeerId,
          memberUsername: 'Charlie',
          removedAt: removedAt,
        );
        await waitUntil(() async {
          return !(await memberSet(bob)).contains(charliePeerId) &&
              await charliePhone.groupRepo.getGroup(groupId) == null &&
              await charlieTablet.groupRepo.getGroup(groupId) == null;
        }, maxTicks: 40);
        expect(network.isSubscribed(groupId, charliePhone.deviceId), isFalse);
        expect(network.isSubscribed(groupId, charlieTablet.deviceId), isFalse);

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: removedWindowText,
              messageId: 'ra013-removed-window',
              timestamp: removedWindowAt,
            );
        expect(removedResult, group_send.SendGroupMessageResult.success);
        expect(removedMessage, isNotNull);
        expect(inboxStoreRecipientPeerIds(alice, 'ra013-removed-window'), [
          bob.peerId,
        ]);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': rejoinKeyValue,
          'keyEpoch': 2,
        };
        final rejoinKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(rejoinKey, isNotNull);
        await bob.groupRepo.saveKey(rejoinKey!);

        final readdedCharlie = charlieMember(rejoinKeyCreatedAt);
        await addGroupMember(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          newMember: readdedCharlie,
          selfPeerId: alice.peerId,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charliePhone,
          eventAt: rejoinKeyCreatedAt,
        );
        await waitUntil(() async {
          return (await memberSet(bob)).contains(charliePeerId) &&
              (await charlieDeviceSet(
                bob,
              )).containsAll({charliePhone.deviceId, charlieTablet.deviceId});
        }, maxTicks: 40);

        final readdGroup = await alice.groupRepo.getGroup(groupId);
        final readdMembers = await alice.groupRepo.getMembers(groupId);
        final readdConfig = buildGroupConfigPayload(readdGroup!, readdMembers);
        final phonePendingRepo = InMemoryPendingGroupInviteRepository();
        final tabletPendingRepo = InMemoryPendingGroupInviteRepository();
        await phonePendingRepo.savePendingInvite(
          makeDeviceInvite(
            device: charliePhone,
            inviteId: 'ra013-phone-readd',
            groupConfig: readdConfig,
            keyInfo: rejoinKey,
            receivedAt: inviteReceivedAt,
          ),
        );
        await tabletPendingRepo.savePendingInvite(
          makeDeviceInvite(
            device: charlieTablet,
            inviteId: 'ra013-tablet-readd',
            groupConfig: readdConfig,
            keyInfo: rejoinKey,
            receivedAt: inviteReceivedAt,
          ),
        );

        final (phoneResult, phoneGroup) = await acceptDevice(
          device: charliePhone,
          pendingRepo: phonePendingRepo,
          now: phoneAcceptAt,
        );
        expect(phoneResult, AcceptPendingGroupInviteResult.success);
        expect(phoneGroup, isNotNull);
        charliePhone.subscribeToGroup(groupId);
        expect(await phonePendingRepo.getPendingInvite(groupId), isNull);
        expect(await tabletPendingRepo.getPendingInvite(groupId), isNotNull);
        expect(await charlieTablet.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charliePhone.deviceId), isTrue);
        expect(network.isSubscribed(groupId, charlieTablet.deviceId), isFalse);

        final (alicePostResult, alicePostMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: aliceAfterPhoneAccept,
              messageId: 'ra013-alice-after-phone-accept',
              timestamp: phoneAcceptAt.add(const Duration(seconds: 1)),
            );
        final (bobPostResult, bobPostMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobAfterPhoneAccept,
              messageId: 'ra013-bob-after-phone-accept',
              timestamp: phoneAcceptAt.add(const Duration(seconds: 2)),
            );
        expect(alicePostResult, group_send.SendGroupMessageResult.success);
        expect(bobPostResult, group_send.SendGroupMessageResult.success);
        expect(alicePostMessage, isNotNull);
        expect(bobPostMessage, isNotNull);
        expect(
          inboxStoreRecipientPeerIds(
            alice,
            'ra013-alice-after-phone-accept',
          ).toSet(),
          {bob.peerId, charliePeerId},
        );
        expect(
          inboxStoreRecipientPeerIds(
            bob,
            'ra013-bob-after-phone-accept',
          ).toSet(),
          {alice.peerId, charliePeerId},
        );
        await waitUntil(() async {
          final phoneTexts = (await charliePhone.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return phoneTexts.contains(aliceAfterPhoneAccept) &&
              phoneTexts.contains(bobAfterPhoneAccept);
        }, maxTicks: 40);
        expect(await charlieTablet.loadGroupMessages(groupId), isEmpty);

        charlieTablet.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            inboxRetrieveMessageFor(alice, 'ra013-removed-window'),
            inboxRetrieveMessageFor(alice, 'ra013-alice-after-phone-accept'),
            inboxRetrieveMessageFor(bob, 'ra013-bob-after-phone-accept'),
          ],
          'cursor': '',
        };
        final (tabletResult, tabletGroup) = await acceptDevice(
          device: charlieTablet,
          pendingRepo: tabletPendingRepo,
          now: tabletAcceptAt,
        );
        expect(tabletResult, AcceptPendingGroupInviteResult.success);
        expect(tabletGroup, isNotNull);
        charlieTablet.subscribeToGroup(groupId);
        expect(await tabletPendingRepo.getPendingInvite(groupId), isNull);

        final tabletTexts = (await charlieTablet.loadGroupMessages(
          groupId,
        )).map((message) => message.text).toSet();
        expect(tabletTexts, contains(aliceAfterPhoneAccept));
        expect(tabletTexts, contains(bobAfterPhoneAccept));
        expect(tabletTexts, isNot(contains(removedWindowText)));

        final (tabletSendResult, tabletMessage) = await charlieTablet
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: tabletAfterOwnAccept,
              messageId: 'ra013-tablet-after-own-accept',
              timestamp: tabletAcceptAt.add(const Duration(seconds: 1)),
            );
        expect(tabletSendResult, group_send.SendGroupMessageResult.success);
        expect(tabletMessage, isNotNull);
        await waitUntil(() async {
          final aliceTexts = (await alice.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          final phoneTexts = (await charliePhone.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
          return aliceTexts.contains(tabletAfterOwnAccept) &&
              bobTexts.contains(tabletAfterOwnAccept) &&
              phoneTexts.contains(tabletAfterOwnAccept);
        }, maxTicks: 40);
      },
    );

    test(
      'GM-035 re-added Charlie first send drains from durable zero-peer fallback exactly once',
      () async {
        const groupId = 'grp-gm035-readd-zero-peer-first-send';
        const initialKey = 'gm035-initial-key';
        const currentKeyValue = 'gm035-current-key';
        const charlieFirstMessageId = 'gm035-charlie-first-post-readd';
        const charlieFirstText =
            'GM-035 Charlie first post-readd before discovery';
        final clockBase = DateTime.now().toUtc();
        final createdAt = clockBase.subtract(const Duration(minutes: 10));
        final removedAt = clockBase.subtract(const Duration(minutes: 5));
        final readdAt = clockBase.subtract(const Duration(minutes: 1));
        late DateTime firstSendAt;
        final aliceBridge = cursorBridge();
        final bobBridge = cursorBridge();

        final alice = GroupTestUser.create(
          peerId: 'peer-gm035-alice',
          username: 'Alice',
          network: network,
          bridge: aliceBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm035-bob',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm035-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> inboxPayloadForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] == messageId) {
              return payload;
            }
          }
          fail('missing group:inboxStore payload for $messageId');
        }

        Future<int> incomingTextCount(GroupTestUser user) async {
          return (await user.loadGroupMessages(groupId))
              .where(
                (message) =>
                    message.isIncoming &&
                    message.id == charlieFirstMessageId &&
                    message.text == charlieFirstText,
              )
              .length;
        }

        Future<void> drainStoredReplay(
          GroupTestUser user,
          _GroupMembershipCursorBridge bridge,
          Map<String, dynamic> inboxPayload,
        ) async {
          bridge.addPage(
            groupId: groupId,
            cursor: '',
            messages: <Map<String, dynamic>>[
              <String, dynamic>{
                'from': charlie.deviceId,
                'message': inboxPayload['message'] as String,
                'timestamp': firstSendAt.microsecondsSinceEpoch,
              },
            ],
          );
          await drainGroupOfflineInboxForGroup(
            bridge: user.bridge,
            groupRepo: user.groupRepo,
            msgRepo: user.msgRepo,
            groupId: groupId,
            groupMessageListener: user.groupMessageListener,
            selfPeerId: user.peerId,
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-035 Group',
          createdAt: createdAt,
        );
        await saveKey(
          alice,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        );
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(seconds: 2)),
        );
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: initialKey,
          createdAt: createdAt,
        );

        alice.start();
        bob.start();
        charlie.start();
        await pump();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          return await bob.groupRepo.getMember(groupId, charlie.peerId) ==
                  null &&
              await charlie.groupRepo.getGroup(groupId) == null &&
              !network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': currentKeyValue,
          'keyEpoch': 2,
        };
        final currentKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (_, _) async => true,
        );
        expect(currentKey, isNotNull);
        await saveKey(
          bob,
          epoch: currentKey!.keyGeneration,
          encryptedKey: currentKey.encryptedKey,
          createdAt: currentKey.createdAt,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(
          charlie,
          epoch: currentKey.keyGeneration,
          encryptedKey: currentKey.encryptedKey,
          createdAt: readdAt,
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          return await bob.groupRepo.getMember(groupId, charlie.peerId) !=
                  null &&
              await charlie.groupRepo.getMember(groupId, alice.peerId) !=
                  null &&
              await charlie.groupRepo.getMember(groupId, bob.peerId) != null &&
              network.isSubscribed(groupId, charlie.deviceId);
        }, maxTicks: 40);

        for (final user in <GroupTestUser>[alice, bob, charlie]) {
          final memberPeerIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberPeerIds, {alice.peerId, bob.peerId, charlie.peerId});
          expect(
            (await user.groupRepo.getLatestKey(groupId))?.keyGeneration,
            2,
          );
        }

        alice.bridge.sentMessages.clear();
        bob.bridge.sentMessages.clear();
        charlie.bridge.sentMessages.clear();

        const initialTopicPeers = 0;
        firstSendAt = DateTime.now().toUtc();
        final (sendResult, sentMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: charlieFirstText,
              messageId: charlieFirstMessageId,
              timestamp: firstSendAt,
              publishTopicPeersOverride: initialTopicPeers,
            );
        expect(initialTopicPeers, 0);
        expect(sendResult, group_send.SendGroupMessageResult.successNoPeers);
        expect(sentMessage, isNotNull);
        expect(sentMessage!.status, 'sent');
        expect(sentMessage.keyGeneration, 2);
        expect(await incomingTextCount(alice), 0);
        expect(await incomingTextCount(bob), 0);

        final inboxPayload = inboxPayloadForMessage(
          charlie,
          charlieFirstMessageId,
        );
        final recipientPeerIds =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(recipientPeerIds.toSet(), {alice.peerId, bob.peerId});
        expect(recipientPeerIds, hasLength(2));
        expect(recipientPeerIds, hasLength(recipientPeerIds.toSet().length));

        final replayPayload = decodeReplayPayload(inboxPayload);
        expect(replayPayload['messageId'], charlieFirstMessageId);
        expect(replayPayload['senderId'], charlie.peerId);
        expect(replayPayload['senderDeviceId'], charlie.deviceId);
        expect(replayPayload['transportPeerId'], charlie.deviceId);
        expect(replayPayload['keyEpoch'], 2);
        expect(replayPayload['text'], charlieFirstText);

        await drainStoredReplay(alice, aliceBridge, inboxPayload);
        await drainStoredReplay(bob, bobBridge, inboxPayload);
        expect(await incomingTextCount(alice), 1);
        expect(await incomingTextCount(bob), 1);

        await network.publish(groupId, charlie.peerId, {
          'groupId': groupId,
          'senderId': charlie.peerId,
          'senderUsername': charlie.username,
          'senderDeviceId': charlie.deviceId,
          'transportPeerId': charlie.deviceId,
          'keyEpoch': sentMessage.keyGeneration,
          'text': charlieFirstText,
          'timestamp': firstSendAt.toIso8601String(),
          'messageId': charlieFirstMessageId,
        }, senderDeviceId: charlie.deviceId);
        await pump();
        await pump();

        expect(await incomingTextCount(alice), 1);
        expect(await incomingTextCount(bob), 1);
        expect(
          (await alice.loadGroupMessages(
            groupId,
          )).where((message) => message.id == charlieFirstMessageId),
          hasLength(1),
        );
        expect(
          (await bob.loadGroupMessages(
            groupId,
          )).where((message) => message.id == charlieFirstMessageId),
          hasLength(1),
        );
      },
    );

    test(
      'GM-036 send after mixed re-add does not clear failed invite status',
      () async {
        const groupId = 'grp-gm036-mixed-readd-delivery-status';
        const groupKey = 'gm036-current-group-key';
        const sendText = 'GM-036 Alice send after mixed re-add';
        const sendMessageId = 'gm036-alice-after-mixed-readd';
        final createdAt = DateTime.utc(2026, 5, 12, 9);
        final readdAt = createdAt.add(const Duration(minutes: 10));
        final inviteAttemptedAt = readdAt.add(const Duration(seconds: 1));
        final sendAt = readdAt.add(const Duration(minutes: 1));
        final inviteStatusRepo = _TrackingInviteDeliveryAttemptRepository();

        final alice = GroupTestUser.create(
          peerId: 'peer-gm036-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm036-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-gm036-charlie',
          username: 'Charlie',
          network: network,
        );
        final dave = GroupTestUser.create(
          peerId: 'peer-gm036-dave',
          username: 'Dave',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dave.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: groupKey,
              createdAt: createdAt,
            ),
          );
        }

        Future<void> seedRemovedLocalMember(GroupTestUser user) async {
          await alice.groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: user.peerId,
              username: user.username,
              role: MemberRole.writer,
              publicKey: user.publicKey,
              mlKemPublicKey: 'mlkem-${user.peerId}',
              devices: [user.deviceIdentity],
              joinedAt: createdAt.add(const Duration(minutes: 2)),
            ),
          );
          await alice.groupRepo.removeMember(groupId, user.peerId);
        }

        Future<void> readdLocalMember(GroupTestUser user) {
          return addGroupMember(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            newMember: GroupMember(
              groupId: groupId,
              peerId: user.peerId,
              username: user.username,
              role: MemberRole.writer,
              publicKey: user.publicKey,
              mlKemPublicKey: 'mlkem-${user.peerId}',
              devices: [user.deviceIdentity],
              joinedAt: readdAt,
            ),
            selfPeerId: alice.peerId,
          );
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-036 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await saveKey(bob);
        await seedRemovedLocalMember(charlie);
        await seedRemovedLocalMember(dave);
        await readdLocalMember(charlie);
        await readdLocalMember(dave);

        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: charlie.peerId,
            username: charlie.username,
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: inviteAttemptedAt,
            updatedAt: inviteAttemptedAt,
          ),
        );
        await inviteStatusRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: dave.peerId,
            username: dave.username,
            status: GroupInviteDeliveryStatus.needsResend,
            attemptedAt: inviteAttemptedAt,
            updatedAt: inviteAttemptedAt,
            lastError: 'send_failed',
          ),
        );

        alice.start();
        bob.start();
        await pump();

        final memberPeerIds = (await alice.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        expect(memberPeerIds, {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dave.peerId,
        });
        final charlieBefore = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: charlie.peerId,
        );
        final daveBefore = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: dave.peerId,
        );
        expect(charlieBefore, isNotNull);
        expect(charlieBefore!.status, GroupInviteDeliveryStatus.sent);
        expect(charlieBefore.lastError, isNull);
        expect(daveBefore, isNotNull);
        expect(daveBefore!.status, GroupInviteDeliveryStatus.needsResend);
        expect(daveBefore.lastError, 'send_failed');

        alice.bridge.sentMessages.clear();
        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: sendText,
          messageId: sendMessageId,
          timestamp: sendAt,
        );

        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, sentMessage!.id).toSet(), {
          bob.peerId,
          charlie.peerId,
          dave.peerId,
        });
        await waitUntil(() async {
          final bobTexts = (await bob.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toList();
          return bobTexts.where((text) => text == sendText).length == 1;
        }, maxTicks: 40);

        final charlieAfter = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: charlie.peerId,
        );
        final daveAfter = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: dave.peerId,
        );
        expect(charlieAfter, isNotNull);
        expect(charlieAfter!.status, GroupInviteDeliveryStatus.sent);
        expect(charlieAfter.lastError, isNull);
        expect(daveAfter, isNotNull);
        expect(daveAfter!.status, GroupInviteDeliveryStatus.needsResend);
        expect(daveAfter.lastError, 'send_failed');
        expect(daveAfter.updatedAt, daveBefore.updatedAt);
      },
    );

    test('GM-014 simultaneous re-add and sender send', () async {
      const groupId = 'grp-gm014-readd-send';
      const initialKey = 'gm014-initial-key';
      const currentKeyValue = 'gm014-current-key';
      const aliceDuringRemoval = 'GM-014 Alice during Charlie removal';
      const aliceAfterReadd = 'GM-014 Alice immediately after Charlie readd';
      final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );

      final alice = GroupTestUser.create(
        peerId: 'peer-gm014-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-gm014-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-gm014-charlie',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      Future<void> saveKey(
        GroupTestUser user, {
        required int epoch,
        required String encryptedKey,
        required DateTime createdAt,
      }) async {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: epoch,
            encryptedKey: encryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      List<String> recipientPeerIdsForMessage(
        GroupTestUser sender,
        String messageId,
      ) {
        for (final raw in sender.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope =
              jsonDecode(payload['message'] as String) as Map<String, dynamic>;
          if (replayEnvelope['messageId'] != messageId) continue;
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }
        return const <String>[];
      }

      String replayEnvelopeForMessage(GroupTestUser sender, String messageId) {
        for (final raw in sender.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope = payload['message'] as String;
          final decoded = jsonDecode(replayEnvelope) as Map<String, dynamic>;
          if (decoded['messageId'] == messageId) return replayEnvelope;
        }
        throw StateError('Missing replay envelope for $messageId');
      }

      Future<int> incomingTextCount(GroupTestUser user, String text) async {
        return (await user.loadGroupMessages(groupId))
            .where((message) => message.isIncoming && message.text == text)
            .length;
      }

      Future<void> expectCurrentState(GroupTestUser user) async {
        final members = await user.groupRepo.getMembers(groupId);
        expect(members.map((member) => member.peerId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
        expect(
          members.where((member) => member.peerId == charlie.peerId),
          hasLength(1),
        );
        final latestKey = await user.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, currentKeyValue);
      }

      await alice.createGroup(groupId: groupId, name: 'GM-014 Group');
      await saveKey(
        alice,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(groupId: groupId, invitee: bob);
      await saveKey(
        bob,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(groupId: groupId, invitee: charlie);
      await saveKey(
        charlie,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );

      alice.start();
      bob.start();
      charlie.start();
      await pump();

      final removedAt = DateTime.now().toUtc();
      final readdAt = removedAt.add(const Duration(seconds: 10));
      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );
      await waitUntil(() async {
        final bobMember = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobMember == null && charlieGroup == null;
      }, maxTicks: 40);

      alice.bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': currentKeyValue,
        'keyEpoch': 2,
      };
      final keyDistributionTargets = <String>[];
      final currentKey = await rotateAndDistributeGroupKey(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        selfPeerId: alice.peerId,
        senderPublicKey: alice.publicKey,
        senderPrivateKey: alice.privateKey,
        senderUsername: alice.username,
        sourceDeviceId: alice.deviceId,
        sendP2PMessage: (peerId, _) async {
          keyDistributionTargets.add(peerId);
          return true;
        },
      );
      expect(currentKey, isNotNull);
      expect(keyDistributionTargets, contains(bob.deviceId));
      expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
      await saveKey(
        bob,
        epoch: currentKey!.keyGeneration,
        encryptedKey: currentKey.encryptedKey,
        createdAt: currentKey.createdAt,
      );

      final (duringResult, duringMessage) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: aliceDuringRemoval,
            messageId: 'gm014-alice-during-removal',
            timestamp: removedAt.add(const Duration(seconds: 1)),
          );
      expect(duringResult, group_send.SendGroupMessageResult.success);
      expect(duringMessage, isNotNull);
      await waitUntil(
        () async => await incomingTextCount(bob, aliceDuringRemoval) == 1,
        maxTicks: 40,
      );
      expect(await incomingTextCount(charlie, aliceDuringRemoval), 0);

      final charlieMemberAfterReadd = GroupMember(
        groupId: groupId,
        peerId: charlie.peerId,
        username: charlie.username,
        role: MemberRole.writer,
        publicKey: charlie.publicKey,
        mlKemPublicKey: 'mlkem-${charlie.peerId}',
        devices: [charlie.deviceIdentity],
        joinedAt: readdAt,
      );
      await addGroupMember(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        newMember: charlieMemberAfterReadd,
        selfPeerId: alice.peerId,
      );

      alice.bridge.sentMessages.clear();
      final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
        groupId: groupId,
        text: aliceAfterReadd,
        messageId: 'gm014-alice-after-readd',
        timestamp: readdAt.add(const Duration(seconds: 1)),
      );
      expect(sendResult, group_send.SendGroupMessageResult.success);
      expect(sentMessage, isNotNull);
      expect(sentMessage!.keyGeneration, 2);
      expect(recipientPeerIdsForMessage(alice, sentMessage.id).toSet(), {
        bob.peerId,
        charlie.peerId,
      });

      final readdGroup = await alice.groupRepo.getGroup(groupId);
      final readdMembers = await alice.groupRepo.getMembers(groupId);
      final readdEnvelope = <String, dynamic>{
        'groupId': groupId,
        'senderId': alice.peerId,
        'senderUsername': alice.username,
        'keyEpoch': 0,
        'text': jsonEncode({
          '__sys': 'member_added',
          'member': charlieMemberAfterReadd.toConfigJson(),
          'groupConfig': buildGroupConfigPayload(readdGroup!, readdMembers),
        }),
        'timestamp': readdAt.toIso8601String(),
        'messageId': 'gm014-member-added',
      };
      await network.publish(
        groupId,
        alice.peerId,
        readdEnvelope,
        senderDeviceId: alice.deviceId,
      );
      await waitUntil(() async {
        return (await bob.groupRepo.getMember(groupId, charlie.peerId)) != null;
      }, maxTicks: 40);

      await charlie.groupRepo.saveGroup(
        readdGroup.copyWith(myRole: GroupRole.member),
      );
      for (final member in readdMembers) {
        await charlie.groupRepo.saveMember(member);
      }
      charlie.subscribeToGroup(groupId);
      expect(await incomingTextCount(charlie, aliceAfterReadd), 0);
      await saveKey(
        charlie,
        epoch: currentKey.keyGeneration,
        encryptedKey: currentKey.encryptedKey,
        createdAt: readdAt,
      );

      final replayEnvelope = replayEnvelopeForMessage(alice, sentMessage.id);
      final plaintext = await decryptGroupOfflineReplayEnvelope(
        bridge: charlie.bridge,
        groupRepo: charlie.groupRepo,
        groupId: groupId,
        envelope: jsonDecode(replayEnvelope) as Map<String, dynamic>,
        expectedRelayPeerId: alice.deviceId,
      );
      await charlie.groupMessageListener.handleReplayEnvelope(
        jsonDecode(plaintext) as Map<String, dynamic>,
        rethrowOnError: true,
      );
      await charlie.groupMessageListener.handleReplayEnvelope(
        jsonDecode(plaintext) as Map<String, dynamic>,
        rethrowOnError: true,
      );

      await waitUntil(
        () async => await incomingTextCount(charlie, aliceAfterReadd) == 1,
        maxTicks: 40,
      );
      expect(await incomingTextCount(bob, aliceAfterReadd), 1);
      expect(await incomingTextCount(charlie, aliceDuringRemoval), 0);
      await expectCurrentState(alice);
      await expectCurrentState(bob);
      await expectCurrentState(charlie);
    });

    test(
      'remaining peers accept only delayed removed-sender envelopes from before the persisted cutoff',
      () async {
        const groupId = 'grp-remove-boundary-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final removalEntry = charlieMessages.firstWhere(
          (entry) =>
              entry.id.startsWith(
                'sys-member_removed:$groupId:${bob.peerId}:',
              ) &&
              entry.text == 'Admin removed Bob',
        );
        final cutoff = removalEntry.timestamp.toUtc();

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': 'Bob',
          'keyEpoch': 0,
          'text': 'Before cutoff delayed',
          'timestamp': cutoff
              .subtract(const Duration(milliseconds: 1))
              .toIso8601String(),
          'messageId': 'msg-before-cutoff-delayed',
        });
        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': 'Bob',
          'keyEpoch': 0,
          'text': 'At cutoff delayed',
          'timestamp': cutoff.toIso8601String(),
          'messageId': 'msg-at-cutoff-delayed',
        });
        await pump();

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((entry) => entry.isIncoming).toList();
        final charlieIncoming = (await charlie.loadGroupMessages(
          groupId,
        )).where((entry) => entry.isIncoming).toList();

        expect(
          adminIncoming.where((entry) => entry.text == 'Before cutoff delayed'),
          hasLength(1),
        );
        expect(
          charlieIncoming.where(
            (entry) => entry.text == 'Before cutoff delayed',
          ),
          hasLength(1),
        );
        expect(
          adminIncoming.where((entry) => entry.text == 'At cutoff delayed'),
          isEmpty,
        );
        expect(
          charlieIncoming.where((entry) => entry.text == 'At cutoff delayed'),
          isEmpty,
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test('GM-013 simultaneous admin remove and member send', () async {
      const groupId = 'grp-gm013-simultaneous-remove-send';
      const initialKey = 'gm013-initial-key';
      const rotatedKeyValue = 'gm013-rotated-key';
      const beforeText = 'GM-013 Charlie before cutoff';
      const afterText = 'GM-013 Charlie at cutoff';
      const aliceAfterRemoval = 'GM-013 Alice after Charlie removal';
      const bobAfterRemoval = 'GM-013 Bob after Charlie removal';
      const charlieAfterRemoval = 'GM-013 Charlie should not send';
      final groupCreatedAt = DateTime.utc(2026, 4, 5, 11, 55);
      final initialKeyCreatedAt = DateTime.utc(2026, 4, 5, 11, 56);
      final removedAt = DateTime.utc(2026, 4, 5, 12);
      final beforeSentAt = removedAt.subtract(const Duration(milliseconds: 1));

      final flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
      addTearDown(() => debugSetFlowEventSink(null));

      final alice = GroupTestUser.create(
        peerId: 'peer-gm013-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-gm013-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-gm013-charlie',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      Future<void> saveKey(
        GroupTestUser user, {
        required int epoch,
        required String encryptedKey,
        required DateTime createdAt,
      }) {
        return user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: epoch,
            encryptedKey: encryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      Future<int> incomingTextCount(GroupTestUser user, String text) async {
        return (await user.loadGroupMessages(groupId))
            .where((message) => message.isIncoming && message.text == text)
            .length;
      }

      await alice.createGroup(
        groupId: groupId,
        name: 'GM-013 Group',
        createdAt: groupCreatedAt,
      );
      await saveKey(
        alice,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: bob,
        joinedAt: groupCreatedAt.add(const Duration(minutes: 2)),
      );
      await saveKey(
        bob,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );
      await alice.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: groupCreatedAt.add(const Duration(minutes: 3)),
      );
      final charlieMemberForBob = await alice.groupRepo.getMember(
        groupId,
        charlie.peerId,
      );
      expect(charlieMemberForBob, isNotNull);
      await bob.groupRepo.saveMember(charlieMemberForBob!);
      await saveKey(
        charlie,
        epoch: 1,
        encryptedKey: initialKey,
        createdAt: initialKeyCreatedAt,
      );

      alice.start();
      bob.start();
      charlie.start();
      await pump();

      expect(
        await alice.groupRepo.getMember(groupId, charlie.peerId),
        isNotNull,
      );
      expect(await bob.groupRepo.getMember(groupId, charlie.peerId), isNotNull);
      expect(
        await charlie.groupRepo.getMember(groupId, charlie.peerId),
        isNotNull,
      );

      await network.publish(groupId, charlie.peerId, {
        'groupId': groupId,
        'senderId': charlie.peerId,
        'senderUsername': charlie.username,
        'keyEpoch': 1,
        'text': beforeText,
        'timestamp': beforeSentAt.toIso8601String(),
        'messageId': 'gm013-charlie-before-cutoff',
      }, senderDeviceId: charlie.deviceId);

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );
      await waitUntil(() async {
        final bobMember = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobMember == null && charlieGroup == null;
      }, maxTicks: 40);

      alice.bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': rotatedKeyValue,
        'keyEpoch': 2,
      };
      final keyDistributionTargets = <String>[];
      final rotatedKey = await rotateAndDistributeGroupKey(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
        groupId: groupId,
        selfPeerId: alice.peerId,
        senderPublicKey: alice.publicKey,
        senderPrivateKey: alice.privateKey,
        senderUsername: alice.username,
        sourceDeviceId: alice.deviceId,
        sendP2PMessage: (peerId, _) async {
          keyDistributionTargets.add(peerId);
          return true;
        },
      );
      expect(rotatedKey, isNotNull);
      expect(rotatedKey!.keyGeneration, 2);
      expect(keyDistributionTargets, contains(bob.deviceId));
      expect(keyDistributionTargets, isNot(contains(charlie.deviceId)));
      await bob.groupRepo.saveKey(rotatedKey);

      await network.publish(groupId, charlie.peerId, {
        'groupId': groupId,
        'senderId': charlie.peerId,
        'senderUsername': charlie.username,
        'keyEpoch': 1,
        'text': afterText,
        'timestamp': removedAt.toIso8601String(),
        'messageId': 'gm013-charlie-at-cutoff',
      }, senderDeviceId: charlie.deviceId);

      await waitUntil(() async {
        final rejectionCount = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
            )
            .length;
        return await incomingTextCount(alice, beforeText) == 1 &&
            await incomingTextCount(bob, beforeText) == 1 &&
            await incomingTextCount(alice, afterText) == 0 &&
            await incomingTextCount(bob, afterText) == 0 &&
            rejectionCount >= 2;
      }, maxTicks: 40);

      expect(await incomingTextCount(alice, beforeText), 1);
      expect(await incomingTextCount(bob, beforeText), 1);
      expect(await alice.msgRepo.getMessage('gm013-charlie-at-cutoff'), isNull);
      expect(await bob.msgRepo.getMessage('gm013-charlie-at-cutoff'), isNull);
      final rejectionEvents = flowEvents
          .where(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
          )
          .toList(growable: false);
      expect(rejectionEvents, hasLength(greaterThanOrEqualTo(2)));
      for (final event in rejectionEvents) {
        final details = event['details'] as Map<String, dynamic>;
        expect(details['cutoffAt'], removedAt.toIso8601String());
      }

      Future<void> expectRemainingMemberState(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        expect(group, isNotNull);
        final memberPeerIds = (await user.groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        expect(memberPeerIds, {alice.peerId, bob.peerId});
        final latestKey = await user.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 2);
        expect(latestKey.encryptedKey, rotatedKeyValue);
      }

      await expectRemainingMemberState(alice);
      await expectRemainingMemberState(bob);
      expect(await charlie.groupRepo.getGroup(groupId), isNull);
      expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

      final (aliceSendResult, aliceMessage) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: aliceAfterRemoval,
            messageId: 'gm013-alice-after-removal',
            timestamp: removedAt.add(const Duration(seconds: 1)),
          );
      final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: bobAfterRemoval,
        messageId: 'gm013-bob-after-removal',
        timestamp: removedAt.add(const Duration(seconds: 2)),
      );
      expect(aliceSendResult, group_send.SendGroupMessageResult.success);
      expect(bobSendResult, group_send.SendGroupMessageResult.success);
      expect(aliceMessage, isNotNull);
      expect(bobMessage, isNotNull);
      expect(aliceMessage!.keyGeneration, 2);
      expect(bobMessage!.keyGeneration, 2);

      await waitUntil(() async {
        return await incomingTextCount(bob, aliceAfterRemoval) == 1 &&
            await incomingTextCount(alice, bobAfterRemoval) == 1;
      }, maxTicks: 40);
      expect(await incomingTextCount(bob, aliceAfterRemoval), 1);
      expect(await incomingTextCount(alice, bobAfterRemoval), 1);

      final (charlieSendResult, charlieMessage) = await charlie
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: charlieAfterRemoval,
            messageId: 'gm013-charlie-after-removal',
            timestamp: removedAt.add(const Duration(seconds: 3)),
          );
      expect(
        charlieSendResult,
        isIn(<group_send.SendGroupMessageResult>[
          group_send.SendGroupMessageResult.groupNotFound,
          group_send.SendGroupMessageResult.unauthorized,
        ]),
      );
      expect(charlieMessage, isNull);

      final charlieTexts = (await charlie.loadGroupMessages(
        groupId,
      )).map((message) => message.text).toSet();
      expect(charlieTexts, isNot(contains(aliceAfterRemoval)));
      expect(charlieTexts, isNot(contains(bobAfterRemoval)));
      expect(charlieTexts, isNot(contains(charlieAfterRemoval)));
    });

    // -----------------------------------------------------------------------
    // 6. Add member success + member_added system message — existing members
    //    update local member list and the new member can participate.
    // -----------------------------------------------------------------------
    test(
      'add member syncs every member list and the new member can participate',
      () async {
        const groupId = 'grp-add-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        // Admin creates group and adds Bob (but NOT Charlie yet)
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        // Start listeners for admin and Bob
        admin.start();
        bob.start();

        // Admin adds Charlie (saves to repos + subscribes)
        await admin.addMember(groupId: groupId, invitee: charlie);

        // Admin broadcasts member_added system message
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        // Charlie starts after the bootstrap data is written to local repos.
        charlie.start();

        Future<void> expectSyncedMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
            'peer-charlie',
          });
          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId['peer-admin'], MemberRole.admin);
          expect(rolesByPeerId['peer-bob'], MemberRole.writer);
          expect(rolesByPeerId['peer-charlie'], MemberRole.writer);
        }

        // All participants should converge on the same member list and roles.
        await expectSyncedMembers(admin);
        await expectSyncedMembers(bob);
        await expectSyncedMembers(charlie);

        // Bob's bridge.commandLog should contain 'group:updateConfig'
        expect(bob.bridge.commandLog, contains('group:updateConfig'));

        // The newly added member can participate once bootstrap is complete.
        await charlie.sendGroupMessage(groupId: groupId, text: 'Hi team');
        await pump();

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoing = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(adminIncoming, hasLength(1));
        expect(adminIncoming.single.text, 'Hi team');
        expect(
          bobIncoming.map((message) => message.text),
          containsAll(['Admin added Charlie', 'Hi team']),
        );
        expect(charlieOutgoing, hasLength(1));
        expect(charlieOutgoing.single.text, 'Hi team');

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'writer leave emits a durable left-the-group event for remaining members',
      () async {
        const groupId = 'grp-writer-leave-004b';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Leave Test');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await bob.leaveGroup(groupId);
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNull);

        final adminMembers = await admin.groupRepo.getMembers(groupId);
        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(
          adminMembers.map((member) => member.peerId),
          isNot(contains('peer-bob')),
        );
        expect(
          charlieMembers.map((member) => member.peerId),
          isNot(contains('peer-bob')),
        );

        final adminMessages = await admin.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          adminMessages.map((message) => message.text),
          contains('Bob left the group'),
        );
        expect(
          charlieMessages.map((message) => message.text),
          contains('Bob left the group'),
        );

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'ML-010 exact duplicate add is idempotent in fake network and keeps delivery unique',
      () async {
        const groupId = 'grp-ml010-duplicate-add';
        final joinedAt = DateTime.utc(2026, 5, 15, 12, 15);
        final alice = GroupTestUser.create(
          peerId: 'peer-ml010-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml010-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml010-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 3,
              encryptedKey: 'ml010-stable-key',
              createdAt: joinedAt,
            ),
          );
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'ML-010 Duplicate Add',
          createdAt: joinedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        );
        await saveKey(alice);
        await saveKey(bob);
        await saveKey(charlie);

        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final expectedMembers = {alice.peerId, bob.peerId, charlie.peerId};
          final aliceMembers = await alice.groupRepo.getMembers(groupId);
          final bobMembers = await bob.groupRepo.getMembers(groupId);
          final charlieMembers = await charlie.groupRepo.getMembers(groupId);
          return aliceMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              bobMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers) &&
              charlieMembers
                  .map((member) => member.peerId)
                  .toSet()
                  .containsAll(expectedMembers);
        }, maxTicks: 40);

        final existingCharlie = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(existingCharlie, isNotNull);
        alice.bridge.commandLog.clear();
        alice.bridge.sentMessages.clear();

        await addGroupMember(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          newMember: existingCharlie!,
          selfPeerId: alice.peerId,
        );

        expect(
          alice.bridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          isEmpty,
        );
        final aliceMembers = await alice.groupRepo.getMembers(groupId);
        final charlieRows = aliceMembers
            .where((member) => member.peerId == charlie.peerId)
            .toList();
        expect(charlieRows, hasLength(1));
        expect(
          charlieRows.single.devices.where((device) => device.isActive),
          hasLength(1),
        );
        final latestKey = await alice.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        expect(latestKey!.keyGeneration, 3);
        expect(latestKey.encryptedKey, 'ml010-stable-key');

        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'ML-010 Charlie after duplicate add',
              messageId: 'ml010-charlie-after-duplicate-add',
              timestamp: joinedAt.add(const Duration(seconds: 3)),
            );
        final (aliceResult, aliceMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'ML-010 Alice after duplicate add',
              messageId: 'ml010-alice-after-duplicate-add',
              timestamp: joinedAt.add(const Duration(seconds: 4)),
            );
        expect(charlieResult, group_send.SendGroupMessageResult.success);
        expect(aliceResult, group_send.SendGroupMessageResult.success);
        expect(charlieMessage!.keyGeneration, 3);
        expect(aliceMessage!.keyGeneration, 3);

        await waitUntil(() async {
          return await incomingTextCount(
                    alice,
                    'ML-010 Charlie after duplicate add',
                  ) ==
                  1 &&
              await incomingTextCount(
                    bob,
                    'ML-010 Charlie after duplicate add',
                  ) ==
                  1 &&
              await incomingTextCount(
                    bob,
                    'ML-010 Alice after duplicate add',
                  ) ==
                  1 &&
              await incomingTextCount(
                    charlie,
                    'ML-010 Alice after duplicate add',
                  ) ==
                  1;
        }, maxTicks: 40);
        final charlieRecipients = recipientPeerIdsForMessage(
          charlie,
          'ml010-charlie-after-duplicate-add',
        );
        expect(charlieRecipients.toSet(), {alice.peerId, bob.peerId});
        expect(charlieRecipients, hasLength(charlieRecipients.toSet().length));
        final aliceRecipients = recipientPeerIdsForMessage(
          alice,
          'ml010-alice-after-duplicate-add',
        );
        expect(aliceRecipients.toSet(), {bob.peerId, charlie.peerId});
        expect(aliceRecipients, hasLength(aliceRecipients.toSet().length));
      },
    );

    test(
      'duplicate re-add returns error and leaves member lists unchanged',
      () async {
        const groupId = 'grp-add-duplicate-004';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Duplicate Add Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();
        await pump();

        admin.bridge.commandLog.clear();

        await expectLater(
          addGroupMember(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            newMember: GroupMember(
              groupId: groupId,
              peerId: bob.peerId,
              username: 'Changed Bob',
              role: MemberRole.reader,
              publicKey: bob.publicKey,
              joinedAt: DateTime.now().toUtc(),
            ),
            selfPeerId: admin.peerId,
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('already exists'),
            ),
          ),
        );
        await pump();

        expect(admin.bridge.commandLog, isEmpty);

        Future<void> expectStableMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
          });

          final bobRows = members.where(
            (member) => member.peerId == 'peer-bob',
          );
          expect(bobRows, hasLength(1));
          expect(bobRows.single.username, 'Bob');
          expect(bobRows.single.role, MemberRole.writer);
        }

        await expectStableMembers(admin);
        await expectStableMembers(bob);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'non-member removal returns error and leaves member lists unchanged',
      () async {
        const groupId = 'grp-remove-absent-008';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Absent Remove Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();
        await pump();

        admin.bridge.commandLog.clear();

        await expectLater(
          removeGroupMember(
            bridge: admin.bridge,
            groupRepo: admin.groupRepo,
            groupId: groupId,
            memberPeerId: 'peer-charlie',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Member not found'),
            ),
          ),
        );
        await pump();

        expect(admin.bridge.commandLog, isEmpty);

        Future<void> expectStableMembers(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'peer-admin',
            'peer-bob',
          });
        }

        await expectStableMembers(admin);
        await expectStableMembers(bob);
        expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        expect(await admin.loadGroupMessages(groupId), isEmpty);
        expect(await bob.loadGroupMessages(groupId), isEmpty);

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'new member cannot send before bootstrap key exists, then succeeds after bootstrap completes',
      () async {
        const groupId = 'grp-add-bootstrap-guard';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }

        await admin.createGroup(groupId: groupId, name: 'Bootstrap Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();
        charlie.start();

        final (blockedResult, blockedMessage) = await charlie
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Too early');

        expect(blockedResult, group_send.SendGroupMessageResult.error);
        expect(blockedMessage, isNull);
        expect(charlie.bridge.commandLog, isEmpty);
        expect(await charlie.loadGroupMessages(groupId), isEmpty);
        expect(
          (await admin.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming),
          isEmpty,
        );
        expect(
          (await bob.loadGroupMessages(groupId))
              .where((message) => message.isIncoming)
              .map((message) => message.text),
          contains('Admin added Charlie'),
        );

        await saveKey(charlie, epoch: 1, encryptedKey: 'group-key-epoch-1');

        final (postBootstrapResult, postBootstrapMessage) = await charlie
            .sendGroupMessageViaBridge(groupId: groupId, text: 'Hi team');
        await pump();

        expect(postBootstrapResult, group_send.SendGroupMessageResult.success);
        expect(postBootstrapMessage, isNotNull);
        expect(postBootstrapMessage!.text, 'Hi team');
        expect(postBootstrapMessage.keyGeneration, 1);

        final adminIncoming = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoing = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(adminIncoming, hasLength(1));
        expect(adminIncoming.single.text, 'Hi team');
        expect(bobIncoming, hasLength(2));
        expect(
          bobIncoming.map((message) => message.text).toList(),
          containsAll(['Admin added Charlie', 'Hi team']),
        );
        expect(charlieOutgoing, hasLength(1));
        expect(charlieOutgoing.single.text, 'Hi team');

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 6. Post-removal messaging — admin can still send to remaining members.
    // -----------------------------------------------------------------------
    test(
      'post-removal messaging — admin can still send to remaining members',
      () async {
        const groupId = 'grp-post-remove-005';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'peer-diana',
          username: 'Diana',
          network: network,
        );

        // Admin creates group and adds everyone
        await admin.createGroup(groupId: groupId, name: 'Test Group');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.addMember(groupId: groupId, invitee: diana);

        // Start all listeners
        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        // Admin removes Bob
        await admin.removeMember(
          groupId: groupId,
          memberPeerId: bob.peerId,
          memberUsername: 'Bob',
        );
        await pump();

        // Clear Bob's bridge command log to track only post-removal activity
        // (Bob already processed the member_removed system message above)

        // Admin sends "Still here"
        await admin.sendGroupMessage(groupId: groupId, text: 'Still here');

        // Charlie sends "Me too"
        await charlie.sendGroupMessage(groupId: groupId, text: 'Me too');
        await pump();

        // Helper to get incoming messages for a user
        Future<List<GroupMessage>> incomingFor(GroupTestUser user) async {
          final msgs = await user.loadGroupMessages(groupId);
          return msgs.where((m) => m.isIncoming).toList();
        }

        final adminIncoming = await incomingFor(admin);
        final charlieIncoming = await incomingFor(charlie);
        final dianaIncoming = await incomingFor(diana);
        final bobIncoming = await incomingFor(bob);

        // Admin: has "Me too" incoming (from Charlie)
        expect(adminIncoming.map((m) => m.text).toList(), contains('Me too'));

        // Charlie: has "Still here" incoming (from Admin)
        expect(
          charlieIncoming.map((m) => m.text).toList(),
          contains('Still here'),
        );

        // Diana: has both "Still here" and "Me too" incoming
        final dianaTexts = dianaIncoming.map((m) => m.text).toList();
        expect(dianaTexts, containsAll(['Still here', 'Me too']));

        // Bob: has 0 messages after removal (no incoming post-removal messages)
        // Bob may still have the system message processing result but those
        // are not saved as regular messages. Check only text messages.
        final bobPostRemovalTexts = bobIncoming
            .where((m) => m.text == 'Still here' || m.text == 'Me too')
            .toList();
        expect(bobPostRemovalTexts, isEmpty);

        // Cleanup
        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'remaining member receives readable removal timeline event while member list updates',
      () async {
        const groupId = 'grp-remove-visible-013';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Visible Removal');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        final bobTimelineEvents = <GroupMessage>[];
        final bobTimelineSub = bob.groupMessageListener.groupMessageStream
            .listen((message) {
              if (message.groupId == groupId) {
                bobTimelineEvents.add(message);
              }
            });

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        expect(
          bobTimelineEvents.map((message) => message.text).toList(),
          contains('Admin removed Charlie'),
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob'},
        );

        await bobTimelineSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    // -----------------------------------------------------------------------
    // 7. Re-add after removal — the removed member resumes active group use,
    //    does not see removed-period traffic, and syncs the current key/member
    //    state.
    // -----------------------------------------------------------------------
    test(
      'ML-007 removed member rejoins with current state and receives only post-readd messages',
      () async {
        const groupId = 'grp-rejoin-007';
        final initialKeyCreatedAt = DateTime.utc(2026, 4, 4, 12);
        final rotatedKeyCreatedAt = DateTime.utc(2026, 4, 4, 12, 1);

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required String encryptedKey,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await admin.createGroup(groupId: groupId, name: 'Rejoin Group');
        await saveKey(
          admin,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        await admin.addMember(groupId: groupId, invitee: bob);
        await saveKey(
          bob,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 1,
          encryptedKey: 'group-key-epoch-1',
          createdAt: initialKeyCreatedAt,
        );

        admin.start();
        bob.start();
        charlie.start();

        await admin.sendGroupMessage(groupId: groupId, text: 'Before removal');
        await pump();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await waitUntil(() async {
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          final charlieMember = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
          return charlieGroup != null &&
              charlieMember == null &&
              charlieKey == null &&
              !network.isSubscribed(groupId, charlie.peerId);
        }, maxTicks: 40);

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await saveKey(
          admin,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );
        await saveKey(
          bob,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );

        await admin.sendGroupMessage(groupId: groupId, text: 'During removal');
        await pump();

        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: 2,
          encryptedKey: 'group-key-epoch-2',
          createdAt: rotatedKeyCreatedAt,
        );
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        final charlieMembers = await charlie.groupRepo.getMembers(groupId);
        expect(charlieMembers.map((member) => member.peerId).toSet(), {
          'peer-admin',
          'peer-bob',
          'peer-charlie',
        });
        final charlieRoles = {
          for (final member in charlieMembers) member.peerId: member.role,
        };
        expect(charlieRoles['peer-admin'], MemberRole.admin);
        expect(charlieRoles['peer-bob'], MemberRole.writer);
        expect(charlieRoles['peer-charlie'], MemberRole.writer);

        final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
        expect(charlieKey, isNotNull);
        expect(charlieKey!.keyGeneration, 2);
        expect(charlieKey.encryptedKey, 'group-key-epoch-2');

        await charlie.sendGroupMessage(groupId: groupId, text: 'I am back');
        await pump();

        final adminIncomingAfterRejoin = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final bobIncomingAfterRejoin = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        final charlieOutgoingAfterRejoin = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();

        expect(
          adminIncomingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          bobIncomingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          charlieOutgoingAfterRejoin.map((message) => message.text),
          contains('I am back'),
        );
        expect(
          charlieOutgoingAfterRejoin
              .where((message) => message.text == 'I am back')
              .single
              .keyGeneration,
          2,
        );

        await admin.sendGroupMessage(groupId: groupId, text: 'Welcome back');
        await bob.sendGroupMessage(groupId: groupId, text: 'Bob sees you back');
        await pump();

        final charlieAllMessages = await charlie.loadGroupMessages(groupId);
        final charlieIncomingTexts = charlieAllMessages
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();

        expect(charlieIncomingTexts, contains('Before removal'));
        expect(charlieIncomingTexts, contains('Welcome back'));
        expect(charlieIncomingTexts, contains('Bob sees you back'));
        expect(charlieIncomingTexts, isNot(contains('During removal')));

        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'ML-008 repeated add-remove-re-add cycles stay convergent across restarts',
      () async {
        const groupId = 'grp-ml008-readd-cycles';
        const cycleCount = 20;
        const restartEvery = 5;
        final initialKeyCreatedAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 1),
        );
        var currentEpoch = 1;
        var restartMarkers = 0;
        var removedWindowPlaintextCount = 0;
        var postReaddDeliveryCount = 0;

        final admin = GroupTestUser.create(
          peerId: 'peer-ml008-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml008-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml008-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          DateTime? createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ml008-key-$epoch',
              createdAt: createdAt ?? DateTime.now().toUtc(),
            ),
          );
        }

        Future<Set<String>> messageTexts(GroupTestUser user) async {
          return (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
        }

        Future<int> countText(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.text == text).length;
        }

        Future<void> waitForText(GroupTestUser user, String text) async {
          await waitUntil(
            () async => (await messageTexts(user)).contains(text),
            maxTicks: 60,
          );
          expect(await messageTexts(user), contains(text));
        }

        Future<void> expectConverged(int epoch) async {
          final expectedMembers = {admin.peerId, bob.peerId, charlie.peerId};
          for (final user in [admin, bob, charlie]) {
            final group = await user.groupRepo.getGroup(groupId);
            expect(group, isNotNull, reason: '${user.peerId} has group');
            final members = await user.groupRepo.getMembers(groupId);
            expect(
              members.map((member) => member.peerId).toSet(),
              expectedMembers,
              reason: '${user.peerId} member set after epoch $epoch',
            );
            for (final expectedPeerId in expectedMembers) {
              expect(
                members.where((member) => member.peerId == expectedPeerId),
                hasLength(1),
                reason:
                    '${user.peerId} has exactly one $expectedPeerId row after epoch $epoch',
              );
            }
            final key = await user.groupRepo.getLatestKey(groupId);
            expect(key, isNotNull, reason: '${user.peerId} key after epoch');
            expect(key!.keyGeneration, epoch);
            expect(key.encryptedKey, 'ml008-key-$epoch');
          }
        }

        Future<void> restartPeer(GroupTestUser user) async {
          user.groupMessageListener.stop();
          await pump();
          user.start();
          restartMarkers++;
        }

        await admin.createGroup(groupId: groupId, name: 'ML-008 Group');
        await saveKey(
          admin,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );
        await admin.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob, epoch: currentEpoch, createdAt: initialKeyCreatedAt);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await saveKey(
          charlie,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        await pump();
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember != null;
        }, maxTicks: 60);
        await expectConverged(currentEpoch);

        for (var cycle = 1; cycle <= cycleCount; cycle++) {
          final cycleStart = DateTime.now().toUtc();
          final activeText = 'ML-008 cycle $cycle active';
          final removedText = 'ML-008 cycle $cycle removed window';
          final postReaddText = 'ML-008 cycle $cycle post readd';

          await admin.sendGroupMessage(
            groupId: groupId,
            text: activeText,
            messageId: 'ml008-active-$cycle',
            timestamp: cycleStart,
          );
          await waitForText(charlie, activeText);

          await admin.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: DateTime.now().toUtc(),
          );
          await waitUntil(() async {
            final bobMember = await bob.groupRepo.getMember(
              groupId,
              charlie.peerId,
            );
            final charlieGroup = await charlie.groupRepo.getGroup(groupId);
            final charlieSelfMember = await charlie.groupRepo.getMember(
              groupId,
              charlie.peerId,
            );
            final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
            return bobMember == null &&
                charlieGroup != null &&
                charlieSelfMember == null &&
                charlieKey == null &&
                !network.isSubscribed(groupId, charlie.peerId);
          }, maxTicks: 60);
          expect(
            await bob.groupRepo.getMember(groupId, charlie.peerId),
            isNull,
          );
          expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
          expect(
            await charlie.groupRepo.getMember(groupId, charlie.peerId),
            isNull,
          );
          expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
          expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

          currentEpoch++;
          await saveKey(
            admin,
            epoch: currentEpoch,
            createdAt: DateTime.now().toUtc(),
          );
          await saveKey(
            bob,
            epoch: currentEpoch,
            createdAt: DateTime.now().toUtc(),
          );

          await admin.sendGroupMessage(
            groupId: groupId,
            text: removedText,
            messageId: 'ml008-removed-$cycle',
            timestamp: cycleStart.add(const Duration(seconds: 7)),
          );
          await waitForText(bob, removedText);
          await pump();
          removedWindowPlaintextCount += await countText(charlie, removedText);

          await admin.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: DateTime.now().toUtc(),
          );
          await saveKey(
            charlie,
            epoch: currentEpoch,
            createdAt: DateTime.now().toUtc(),
          );
          await admin.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
          );
          await waitUntil(() async {
            final bobMember = await bob.groupRepo.getMember(
              groupId,
              charlie.peerId,
            );
            final charlieGroup = await charlie.groupRepo.getGroup(groupId);
            return bobMember != null && charlieGroup != null;
          }, maxTicks: 60);

          await bob.sendGroupMessage(
            groupId: groupId,
            text: postReaddText,
            messageId: 'ml008-post-readd-$cycle',
            timestamp: cycleStart.add(const Duration(seconds: 9)),
          );
          await waitForText(charlie, postReaddText);
          postReaddDeliveryCount++;

          await expectConverged(currentEpoch);

          if (cycle % restartEvery == 0) {
            await restartPeer(cycle.isEven ? bob : charlie);
            final restartText = 'ML-008 cycle $cycle restart check';
            await admin.sendGroupMessage(
              groupId: groupId,
              text: restartText,
              messageId: 'ml008-restart-$cycle',
              timestamp: cycleStart.add(const Duration(seconds: 10)),
            );
            await waitForText(cycle.isEven ? bob : charlie, restartText);
          }
        }

        expect(restartMarkers, greaterThanOrEqualTo(4));
        expect(removedWindowPlaintextCount, 0);
        expect(postReaddDeliveryCount, cycleCount);
        await expectConverged(currentEpoch);
      },
    );

    test(
      'ML-009 rapid remove and re-add preserves latest membership ordering',
      () async {
        const groupId = 'grp-ml009-rapid-readd';
        final initialKeyCreatedAt = DateTime.utc(2026, 4, 5, 12);
        final removeAt = DateTime.utc(2026, 4, 5, 12, 1);
        final readdAt = DateTime.utc(2026, 4, 5, 12, 1, 1);
        const removedWindowText = 'ML-009 removed window';
        const alicePostReaddText = 'ML-009 Alice post readd';
        const bobPostReaddText = 'ML-009 Bob post readd';
        var currentEpoch = 1;

        final admin = GroupTestUser.create(
          peerId: 'peer-ml009-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml009-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml009-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          DateTime? createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ml009-key-$epoch',
              createdAt: createdAt ?? DateTime.now().toUtc(),
            ),
          );
        }

        Future<Set<String>> messageTexts(GroupTestUser user) async {
          return (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.text).toSet();
        }

        Future<int> countText(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.text == text).length;
        }

        Future<void> waitForText(GroupTestUser user, String text) async {
          await waitUntil(
            () async => (await messageTexts(user)).contains(text),
            maxTicks: 80,
          );
          expect(await messageTexts(user), contains(text));
        }

        Future<void> expectConverged({
          bool requireReaddWatermark = true,
        }) async {
          final expectedMembers = {admin.peerId, bob.peerId, charlie.peerId};
          for (final user in [admin, bob, charlie]) {
            final group = await user.groupRepo.getGroup(groupId);
            expect(group, isNotNull, reason: '${user.peerId} has group');
            if (requireReaddWatermark) {
              expect(
                group!.lastMembershipEventAt,
                readdAt.toUtc(),
                reason: '${user.peerId} keeps latest re-add watermark',
              );
            }
            final members = await user.groupRepo.getMembers(groupId);
            expect(
              members.map((member) => member.peerId).toSet(),
              expectedMembers,
              reason: '${user.peerId} member set after rapid re-add',
            );
            final charlieMember = members.firstWhere(
              (member) => member.peerId == charlie.peerId,
            );
            if (requireReaddWatermark) {
              expect(
                charlieMember.joinedAt,
                readdAt.toUtc(),
                reason: '${user.peerId} treats Charlie as the newer re-add',
              );
            }
            final key = await user.groupRepo.getLatestKey(groupId);
            expect(key, isNotNull, reason: '${user.peerId} key after re-add');
            expect(key!.keyGeneration, currentEpoch);
            expect(key.encryptedKey, 'ml009-key-$currentEpoch');
          }
        }

        await admin.createGroup(
          groupId: groupId,
          name: 'ML-009 Group',
          createdAt: initialKeyCreatedAt,
        );
        await saveKey(
          admin,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(bob, epoch: currentEpoch, createdAt: initialKeyCreatedAt);
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        await admin.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: initialKeyCreatedAt.add(const Duration(seconds: 1)),
        );
        await pump();
        await expectConverged(requireReaddWatermark: false);

        network.holdDeliveriesFor(bob.peerId);
        network.holdDeliveriesFor(charlie.peerId);

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeAt,
        );
        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(1),
        );
        expect(
          network.heldDeliveryCountFor(charlie.peerId),
          greaterThanOrEqualTo(1),
        );

        currentEpoch = 2;
        await saveKey(admin, epoch: currentEpoch, createdAt: removeAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: removeAt);

        await admin.sendGroupMessage(
          groupId: groupId,
          text: removedWindowText,
          messageId: 'ml009-removed-window',
          timestamp: removeAt.add(const Duration(milliseconds: 500)),
        );

        currentEpoch = 3;
        await saveKey(admin, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(charlie, epoch: currentEpoch, createdAt: readdAt);
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await admin.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );

        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(3),
        );
        expect(
          network.heldDeliveryCountFor(charlie.peerId),
          greaterThanOrEqualTo(2),
        );

        await network.releaseHeldDeliveriesFor(bob.peerId, reverse: true);
        await network.releaseHeldDeliveriesFor(charlie.peerId, reverse: true);

        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          final charlieMember = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember?.joinedAt == readdAt.toUtc() &&
              charlieGroup != null &&
              charlieMember?.joinedAt == readdAt.toUtc();
        }, maxTicks: 80);
        await expectConverged();

        expect(await countText(charlie, removedWindowText), 0);
        expect(await countText(bob, removedWindowText), 1);

        await admin.sendGroupMessage(
          groupId: groupId,
          text: alicePostReaddText,
          messageId: 'ml009-alice-post-readd',
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        await bob.sendGroupMessage(
          groupId: groupId,
          text: bobPostReaddText,
          messageId: 'ml009-bob-post-readd',
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        await waitForText(charlie, alicePostReaddText);
        await waitForText(charlie, bobPostReaddText);

        expect(await countText(charlie, removedWindowText), 0);
        await expectConverged();
      },
    );

    test(
      'KE-012 delayed old config after re-add keeps active validators',
      () async {
        const groupId = 'grp-ke012-delayed-old-config-after-readd';
        final initialKeyCreatedAt = DateTime.utc(2026, 4, 5, 15);
        final staleConfigAt = DateTime.utc(2026, 4, 5, 15, 0, 30);
        final bobJoinedAt = DateTime.utc(2026, 4, 5, 15, 1);
        final charlieInitialAt = DateTime.utc(2026, 4, 5, 15, 2);
        final removeAt = DateTime.utc(2026, 4, 5, 15, 3);
        final readdAt = DateTime.utc(2026, 4, 5, 15, 4);
        const alicePostStaleConfigText =
            'KE-012 Alice after delayed old config';
        const bobPostStaleConfigText = 'KE-012 Bob after delayed old config';
        const charliePostStaleConfigText =
            'KE-012 Charlie after delayed old config';
        var currentEpoch = 1;

        final admin = GroupTestUser.create(
          peerId: 'peer-ke012-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ke012-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ke012-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          admin.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          DateTime? createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ke012-key-$epoch',
              createdAt: createdAt ?? DateTime.now().toUtc(),
            ),
          );
        }

        Future<void> waitForTextAtEpoch(
          GroupTestUser user,
          String text,
          int epoch,
        ) async {
          await waitUntil(() async {
            final messages = await user.loadGroupMessages(groupId);
            return messages.any(
              (message) =>
                  message.text == text && message.keyGeneration == epoch,
            );
          }, maxTicks: 80);
          final matches = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.text == text).toList();
          expect(matches, isNotEmpty, reason: '${user.peerId} received $text');
          expect(matches.last.keyGeneration, epoch);
        }

        int updateConfigCount(GroupTestUser user) {
          return user.bridge.commandLog
              .where((command) => command == 'group:updateConfig')
              .length;
        }

        Future<void> expectConverged() async {
          final expectedMembers = {admin.peerId, bob.peerId, charlie.peerId};
          for (final user in [admin, bob, charlie]) {
            final group = await user.groupRepo.getGroup(groupId);
            expect(group, isNotNull, reason: '${user.peerId} has group');
            expect(
              group!.lastMembershipEventAt,
              readdAt.toUtc(),
              reason: '${user.peerId} keeps newer re-add watermark',
            );
            final members = await user.groupRepo.getMembers(groupId);
            expect(
              members.map((member) => member.peerId).toSet(),
              expectedMembers,
              reason: '${user.peerId} member set after old config',
            );
            final bobMember = members.firstWhere(
              (member) => member.peerId == bob.peerId,
            );
            expect(
              bobMember.joinedAt,
              bobJoinedAt.toUtc(),
              reason: '${user.peerId} keeps Bob active after old config',
            );
            final charlieMember = members.firstWhere(
              (member) => member.peerId == charlie.peerId,
            );
            expect(
              charlieMember.joinedAt,
              readdAt.toUtc(),
              reason: '${user.peerId} keeps Charlie re-add interval',
            );
            final key = await user.groupRepo.getLatestKey(groupId);
            expect(key, isNotNull, reason: '${user.peerId} key after re-add');
            expect(key!.keyGeneration, currentEpoch);
            expect(key.encryptedKey, 'ke012-key-$currentEpoch');
          }
        }

        await admin.createGroup(
          groupId: groupId,
          name: 'KE-012 Group',
          createdAt: initialKeyCreatedAt,
        );
        await saveKey(
          admin,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );
        await admin.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );
        await saveKey(bob, epoch: currentEpoch, createdAt: bobJoinedAt);
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieInitialAt,
        );
        await saveKey(
          charlie,
          epoch: currentEpoch,
          createdAt: charlieInitialAt,
        );

        admin.start();
        bob.start();
        charlie.start();
        await admin.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: charlieInitialAt,
        );
        await pump();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 80);

        currentEpoch = 2;
        await saveKey(admin, epoch: currentEpoch, createdAt: removeAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: removeAt);

        currentEpoch = 3;
        await saveKey(admin, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(charlie, epoch: currentEpoch, createdAt: readdAt);
        await admin.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await admin.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          final charlieMember = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember?.joinedAt == readdAt.toUtc() &&
              charlieGroup != null &&
              charlieMember?.joinedAt == readdAt.toUtc();
        }, maxTicks: 80);
        await expectConverged();

        final bobConfigCountBefore = updateConfigCount(bob);
        final charlieConfigCountBefore = updateConfigCount(charlie);
        final group = await admin.groupRepo.getGroup(groupId);
        final adminMember = (await admin.groupRepo.getMembers(
          groupId,
        )).firstWhere((member) => member.peerId == admin.peerId);
        final delayedOldConfigText = jsonEncode({
          '__sys': 'member_added',
          'member': {
            'peerId': bob.peerId,
            'username': bob.username,
            'role': 'writer',
            'publicKey': bob.publicKey,
          },
          'groupConfig': {
            'name': group!.name,
            'groupType': group.type.toValue(),
            if (group.description != null) 'description': group.description,
            'members': [adminMember.toConfigJson()],
            'createdBy': group.createdBy,
            'createdAt': group.createdAt.toUtc().toIso8601String(),
          },
        });

        await network.publish(groupId, admin.peerId, {
          'groupId': groupId,
          'senderId': admin.peerId,
          'senderUsername': admin.username,
          'keyEpoch': 0,
          'text': delayedOldConfigText,
          'timestamp': staleConfigAt.toUtc().toIso8601String(),
        }, senderDeviceId: admin.deviceId);
        await pump();

        expect(updateConfigCount(bob), bobConfigCountBefore);
        expect(updateConfigCount(charlie), charlieConfigCountBefore);
        await expectConverged();

        await admin.sendGroupMessage(
          groupId: groupId,
          text: alicePostStaleConfigText,
          messageId: 'ke012-alice-post-stale-config',
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        await bob.sendGroupMessage(
          groupId: groupId,
          text: bobPostStaleConfigText,
          messageId: 'ke012-bob-post-stale-config',
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        await charlie.sendGroupMessage(
          groupId: groupId,
          text: charliePostStaleConfigText,
          messageId: 'ke012-charlie-post-stale-config',
          timestamp: readdAt.add(const Duration(seconds: 3)),
        );

        await waitForTextAtEpoch(bob, alicePostStaleConfigText, currentEpoch);
        await waitForTextAtEpoch(
          charlie,
          alicePostStaleConfigText,
          currentEpoch,
        );
        await waitForTextAtEpoch(admin, bobPostStaleConfigText, currentEpoch);
        await waitForTextAtEpoch(charlie, bobPostStaleConfigText, currentEpoch);
        await waitForTextAtEpoch(
          admin,
          charliePostStaleConfigText,
          currentEpoch,
        );
        await waitForTextAtEpoch(bob, charliePostStaleConfigText, currentEpoch);
        await expectConverged();
      },
    );

    test(
      'removed member notifications stay off until rejoin becomes effective',
      () async {
        const groupId = 'grp-rejoin-notify-005';
        final charlieNotificationService = FakeNotificationService();
        final charlieTracker = ActiveConversationTracker();

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
          notificationService: charlieNotificationService,
          groupConversationTracker: charlieTracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );

        await admin.createGroup(groupId: groupId, name: 'Rejoin Notifications');
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

        await admin.sendGroupMessage(groupId: groupId, text: 'While removed');
        await pump();

        expect(
          charlieNotificationService.shown,
          isEmpty,
          reason: 'Removed members must not receive local notifications',
        );

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        expect(charlieNotificationService.shown, isEmpty);

        await admin.sendGroupMessage(groupId: groupId, text: 'After rejoin');
        await pump();

        expect(charlieNotificationService.shown, hasLength(1));
        expect(
          charlieNotificationService.shown.single.contactPeerId,
          'group:$groupId',
        );
        expect(
          charlieNotificationService.shown.single.senderUsername,
          'Rejoin Notifications',
        );
        expect(
          charlieNotificationService.shown.single.messageText,
          'Admin: After rejoin',
        );

        final charlieIncomingTexts = (await charlie.loadGroupMessages(groupId))
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();
        expect(charlieIncomingTexts, contains('After rejoin'));
        expect(charlieIncomingTexts, isNot(contains('While removed')));

        admin.dispose();
        charlie.dispose();
      },
    );

    test(
      'long mixed-content group text survives delivery and notification preview',
      () async {
        const groupId = 'grp-mixed-text-006';
        final bobNotificationService = FakeNotificationService();
        final bobTracker = ActiveConversationTracker();
        final longPrefix = List.filled(18, 'LongSegment-006').join(' ');
        final complexText =
            '$longPrefix 😀🚀 مرحبا بالعالم & <xml> [brackets] {curly} %25 + = ? !';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
          notificationService: bobNotificationService,
          groupConversationTracker: bobTracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
        );

        await admin.createGroup(groupId: groupId, name: 'Mixed Text Group');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        await admin.sendGroupMessage(groupId: groupId, text: complexText);
        await pump();

        final adminOutgoing = (await admin.loadGroupMessages(
          groupId,
        )).where((message) => !message.isIncoming).toList();
        expect(adminOutgoing, hasLength(1));
        expect(adminOutgoing.single.text, complexText);

        final bobIncoming = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming.single.text, complexText);
        expect(bobIncoming.single.text.length, complexText.length);

        expect(bobNotificationService.shown, hasLength(1));
        expect(
          bobNotificationService.shown.single.contactPeerId,
          'group:$groupId',
        );
        expect(
          bobNotificationService.shown.single.senderUsername,
          'Mixed Text Group',
        );
        expect(
          bobNotificationService.shown.single.messageText,
          'Admin: $complexText',
        );

        admin.dispose();
        bob.dispose();
      },
    );

    test(
      'remaining member receives readable re-add timeline event while member list updates',
      () async {
        const groupId = 'grp-readd-visible-007';

        final admin = GroupTestUser.create(
          peerId: 'peer-admin',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-charlie',
          username: 'Charlie',
          network: network,
        );

        await admin.createGroup(groupId: groupId, name: 'Re-add Visibility');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);

        admin.start();
        bob.start();
        charlie.start();

        await admin.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: 'Charlie',
        );
        await pump();

        final bobTimelineEvents = <GroupMessage>[];
        final bobTimelineSub = bob.groupMessageListener.groupMessageStream
            .listen((message) {
              if (message.groupId == groupId) {
                bobTimelineEvents.add(message);
              }
            });

        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        expect(
          bobTimelineEvents.map((message) => message.text).toList(),
          contains('Admin added Charlie'),
        );
        expect(
          (await bob.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {'peer-admin', 'peer-bob', 'peer-charlie'},
        );

        await bobTimelineSub.cancel();
        admin.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'GM-032 offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others',
      () async {
        const groupId = 'grp-dissolve-001';

        final alice = GroupTestUser.create(
          peerId: 'peer-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-bob',
          username: 'Bob',
          network: network,
        );

        Future<void> saveKey(GroupTestUser user, {required int epoch}) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'group-key-epoch-$epoch',
              createdAt: DateTime.now().toUtc(),
            ),
          );
        }

        await alice.createGroup(groupId: groupId, name: 'Temporary Group');
        await saveKey(alice, epoch: 1);
        await alice.addMember(groupId: groupId, invitee: bob);
        await saveKey(bob, epoch: 1);

        alice.start();

        final (result, dissolvedGroup) = await alice.dissolveGroupViaBridge(
          groupId: groupId,
        );

        expect(result, group_dissolve.DissolveGroupResult.success);
        expect(dissolvedGroup, isNotNull);
        expect(dissolvedGroup!.isDissolved, isTrue);
        expect(network.isSubscribed(groupId, alice.peerId), isFalse);
        expect(network.isSubscribed(groupId, bob.peerId), isFalse);

        final inboxRaw = alice.bridge.sentMessages.lastWhere(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;

        await bob.groupMessageListener.handleReplayEnvelope(
          decodeReplayPayload(inboxPayload),
        );
        await pump();

        final bobGroup = await bob.groupRepo.getGroup(groupId);
        expect(bobGroup, isNotNull);
        expect(bobGroup!.isDissolved, isTrue);

        final bobLatest = await bob.msgRepo.getLatestMessage(groupId);
        expect(bobLatest, isNotNull);
        expect(bobLatest!.text, 'Alice dissolved the group');

        final (sendResult, sendMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Too late',
        );

        expect(sendResult, group_send.SendGroupMessageResult.groupDissolved);
        expect(sendMessage, isNull);
        expect(bob.bridge.commandLog, isNot(contains('group:publish')));

        bob.bridge.commandLog.clear();

        await deleteGroupAndMessages(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          groupMessageRepo: bob.msgRepo,
          groupId: groupId,
          deleteLocallyIfDissolved: true,
        );
        await pump();

        expect(await bob.groupRepo.getGroup(groupId), isNull);
        expect(await bob.groupRepo.getMembers(groupId), isEmpty);
        expect(await bob.groupRepo.getLatestKey(groupId), isNull);
        expect(await bob.msgRepo.getMessageCount(groupId), 0);
        expect(bob.bridge.commandLog, isNot(contains('group:leave')));

        final aliceGroup = await alice.groupRepo.getGroup(groupId);
        expect(aliceGroup, isNotNull);
        expect(aliceGroup!.isDissolved, isTrue);

        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'UP-002 timeline shows durable add remove and re-add events after reopen',
      () async {
        const groupId = 'grp-up002-durable-timeline';
        final createdAt = DateTime.utc(2026, 5, 15, 9);
        final bobJoinedAt = createdAt.add(const Duration(seconds: 10));
        final charlieFirstJoinedAt = createdAt.add(const Duration(seconds: 20));
        final firstAddEventAt = charlieFirstJoinedAt.add(
          const Duration(seconds: 1),
        );
        final beforeRemovalAt = createdAt.add(const Duration(seconds: 40));
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final charlieRejoinedAt = createdAt.add(const Duration(minutes: 2));
        final readdEventAt = charlieRejoinedAt.add(const Duration(seconds: 1));
        const firstAddText = 'Alice added Charlie';
        const removalText = 'Alice removed Charlie';
        const beforeRemovalText = 'UP-002 retained pre-removal message';

        final alice = GroupTestUser.create(
          peerId: 'peer-up002-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-up002-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-up002-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        Future<void> waitForTimelineCount(
          GroupTestUser user,
          String text,
          int count,
        ) async {
          await waitUntil(() async {
            final messages = await user.loadGroupMessages(groupId);
            return messages.where((message) => message.text == text).length >=
                count;
          }, maxTicks: 80);
          final messages = await user.loadGroupMessages(groupId);
          expect(
            messages.where((message) => message.text == text).length,
            greaterThanOrEqualTo(count),
            reason: '${user.peerId} durable timeline count for "$text"',
          );
        }

        Future<void> restartListener(GroupTestUser user) async {
          user.groupMessageListener.stop();
          await pump();
          user.start();
        }

        Future<void> expectReopenedTimeline(GroupTestUser user) async {
          await restartListener(user);
          final messages = await user.loadGroupMessages(groupId);
          final texts = messages.map((message) => message.text).toList();
          final firstAddIndex = texts.indexOf(firstAddText);
          final removeIndex = texts.indexOf(removalText);
          final readdIndex = texts.indexOf(firstAddText, firstAddIndex + 1);
          expect(firstAddIndex, greaterThanOrEqualTo(0));
          expect(removeIndex, greaterThan(firstAddIndex));
          expect(readdIndex, greaterThan(removeIndex));
          expect(
            messages.where((message) => message.text == firstAddText),
            hasLength(greaterThanOrEqualTo(2)),
          );

          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            {alice.peerId, bob.peerId, charlie.peerId},
            reason: '${user.peerId} final member list after reopened read',
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'UP-002 Timeline',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: bobJoinedAt,
        );

        alice.start();
        bob.start();
        charlie.start();

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieFirstJoinedAt,
        );
        await alice.msgRepo.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: groupId,
            addedMembers: [
              (peerId: charlie.peerId, username: charlie.username),
            ],
            senderId: alice.peerId,
            senderUsername: alice.username,
            eventAt: firstAddEventAt,
          ),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: firstAddEventAt,
        );

        await waitForTimelineCount(bob, firstAddText, 1);
        await waitForTimelineCount(charlie, firstAddText, 1);

        await alice.sendGroupMessage(
          groupId: groupId,
          text: beforeRemovalText,
          messageId: 'up002-before-removal',
          timestamp: beforeRemovalAt,
        );
        await waitForTimelineCount(charlie, beforeRemovalText, 1);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitForTimelineCount(alice, removalText, 1);
        await waitForTimelineCount(bob, removalText, 1);
        await waitForTimelineCount(charlie, removalText, 1);

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: charlieRejoinedAt,
        );
        await alice.msgRepo.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: groupId,
            addedMembers: [
              (peerId: charlie.peerId, username: charlie.username),
            ],
            senderId: alice.peerId,
            senderUsername: alice.username,
            eventAt: readdEventAt,
          ),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdEventAt,
        );

        await waitForTimelineCount(alice, firstAddText, 2);
        await waitForTimelineCount(bob, firstAddText, 2);
        await waitForTimelineCount(charlie, firstAddText, 2);

        await expectReopenedTimeline(alice);
        await expectReopenedTimeline(bob);
        await expectReopenedTimeline(charlie);
      },
    );

    test(
      'ML-015 shuffled membership timeline matches structural intervals',
      () async {
        const groupId = 'grp-ml015-timeline-truth';
        final initialKeyCreatedAt = DateTime.utc(2026, 4, 5, 14);
        final beforeAt = DateTime.utc(2026, 4, 5, 14, 0, 30);
        final removeAt = DateTime.utc(2026, 4, 5, 14, 1);
        final removedWindowAt = DateTime.utc(2026, 4, 5, 14, 1, 30);
        final readdAt = DateTime.utc(2026, 4, 5, 14, 2);
        final alicePostAt = DateTime.utc(2026, 4, 5, 14, 2, 30);
        final bobPostAt = DateTime.utc(2026, 4, 5, 14, 2, 40);
        final charliePostAt = DateTime.utc(2026, 4, 5, 14, 2, 50);
        const beforeText = 'ML-015 before removal';
        const removedWindowText = 'ML-015 removed-window text';
        const alicePostReaddText = 'ML-015 Alice after re-add';
        const bobPostReaddText = 'ML-015 Bob after re-add';
        const charliePostReaddText = 'ML-015 Charlie can compose after re-add';
        const removeTimelineText = 'Alice removed Charlie';
        const readdTimelineText = 'Alice added Charlie';

        final alice = GroupTestUser.create(
          peerId: 'peer-ml015-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-ml015-bob',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'peer-ml015-charlie',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        var currentEpoch = 1;
        Future<void> saveKey(
          GroupTestUser user, {
          required int epoch,
          required DateTime createdAt,
        }) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ml015-key-$epoch',
              createdAt: createdAt,
            ),
          );
        }

        Future<int> countText(GroupTestUser user, String text) async {
          final messages = await user.loadGroupMessages(groupId);
          return messages.where((message) => message.text == text).length;
        }

        Future<void> waitForText(GroupTestUser user, String text) async {
          await waitUntil(
            () async => await countText(user, text) > 0,
            maxTicks: 80,
          );
          expect(
            await countText(user, text),
            greaterThan(0),
            reason: '${user.peerId} should have $text',
          );
        }

        Future<void> expectFinalMembers(GroupTestUser user) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.peerId} has final group');
          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            {alice.peerId, bob.peerId, charlie.peerId},
            reason: '${user.peerId} final member list matches final interval',
          );
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull, reason: '${user.peerId} has final key');
          expect(key!.keyGeneration, currentEpoch);
          expect(key.encryptedKey, 'ml015-key-$currentEpoch');
        }

        Future<void> expectOrder(
          GroupTestUser user,
          List<String> expectedTexts,
        ) async {
          final timeline = await user.loadGroupMessages(groupId);
          var previousIndex = -1;
          for (final text in expectedTexts) {
            final index = timeline.indexWhere(
              (message) => message.text == text,
            );
            expect(
              index,
              greaterThan(previousIndex),
              reason:
                  '${user.peerId} timeline should place "$text" after previous interval event; timeline=${timeline.map((message) => message.text).toList()}',
            );
            previousIndex = index;
          }
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'ML-015 Group',
          createdAt: initialKeyCreatedAt,
        );
        await saveKey(
          alice,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(bob, epoch: currentEpoch, createdAt: initialKeyCreatedAt);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: initialKeyCreatedAt,
        );
        await saveKey(
          charlie,
          epoch: currentEpoch,
          createdAt: initialKeyCreatedAt,
        );

        alice.start();
        bob.start();
        charlie.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: beforeText,
          messageId: 'ml015-before-removal',
          timestamp: beforeAt,
        );
        await waitForText(bob, beforeText);
        await waitForText(charlie, beforeText);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removeAt,
        );
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobMember == null && charlieGroup == null;
        }, maxTicks: 80);

        currentEpoch = 2;
        await saveKey(alice, epoch: currentEpoch, createdAt: removeAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: removeAt);

        network.holdDeliveriesFor(bob.peerId);
        await alice.sendGroupMessage(
          groupId: groupId,
          text: removedWindowText,
          messageId: 'ml015-removed-window',
          timestamp: removedWindowAt,
        );
        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(1),
        );

        currentEpoch = 3;
        await saveKey(alice, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(bob, epoch: currentEpoch, createdAt: readdAt);
        await saveKey(charlie, epoch: currentEpoch, createdAt: readdAt);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await alice.msgRepo.saveMessage(
          buildMembersAddedTimelineMessage(
            groupId: groupId,
            addedMembers: [
              (peerId: charlie.peerId, username: charlie.username),
            ],
            senderId: alice.peerId,
            senderUsername: alice.username,
            eventAt: readdAt,
          ),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        expect(
          network.heldDeliveryCountFor(bob.peerId),
          greaterThanOrEqualTo(2),
        );

        await network.releaseHeldDeliveriesFor(bob.peerId, reverse: true);
        await waitUntil(() async {
          final bobMember = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          final charlieMember = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobMember?.joinedAt == readdAt.toUtc() &&
              charlieGroup != null &&
              charlieMember?.joinedAt == readdAt.toUtc();
        }, maxTicks: 80);

        await waitForText(bob, removedWindowText);
        expect(await countText(charlie, removedWindowText), 0);

        await alice.sendGroupMessage(
          groupId: groupId,
          text: alicePostReaddText,
          messageId: 'ml015-alice-post-readd',
          timestamp: alicePostAt,
        );
        await bob.sendGroupMessage(
          groupId: groupId,
          text: bobPostReaddText,
          messageId: 'ml015-bob-post-readd',
          timestamp: bobPostAt,
        );
        await charlie.sendGroupMessage(
          groupId: groupId,
          text: charliePostReaddText,
          messageId: 'ml015-charlie-post-readd',
          timestamp: charliePostAt,
        );

        await waitForText(charlie, alicePostReaddText);
        await waitForText(charlie, bobPostReaddText);
        await waitForText(alice, charliePostReaddText);
        await waitForText(bob, charliePostReaddText);

        await expectFinalMembers(alice);
        await expectFinalMembers(bob);
        await expectFinalMembers(charlie);
        expect(await countText(charlie, removedWindowText), 0);

        await expectOrder(alice, [
          beforeText,
          removeTimelineText,
          removedWindowText,
          readdTimelineText,
          alicePostReaddText,
          bobPostReaddText,
          charliePostReaddText,
        ]);
        await expectOrder(bob, [
          beforeText,
          removeTimelineText,
          removedWindowText,
          readdTimelineText,
          alicePostReaddText,
          bobPostReaddText,
          charliePostReaddText,
        ]);
        await expectOrder(charlie, [
          beforeText,
          readdTimelineText,
          alicePostReaddText,
          bobPostReaddText,
          charliePostReaddText,
        ]);
      },
    );

    test(
      'GM-027 unknown peer add does not inflate recipients or block valid delivery',
      () async {
        const groupId = 'grp-gm027-unknown-peer';
        final createdAt = DateTime.utc(2026, 5, 11, 10);
        final alice = GroupTestUser.create(
          peerId: 'peer-gm027-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm027-bob',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'gm027-group-key',
              createdAt: createdAt,
            ),
          );
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-027 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await saveKey(bob);
        alice.start();
        bob.start();
        await pump();

        alice.bridge.commandLog.clear();
        final invalidMember = GroupMember(
          groupId: groupId,
          peerId: 'peer-gm027-ghost',
          username: 'Ghost',
          role: MemberRole.writer,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        await expectLater(
          addGroupMember(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            newMember: invalidMember,
            selfPeerId: alice.peerId,
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          await alice.groupRepo.getMember(groupId, invalidMember.peerId),
          isNull,
        );
        expect(
          alice.bridge.commandLog.where(
            (command) => command == 'group:updateConfig',
          ),
          isEmpty,
        );

        const text = 'GM-027 Alice to Bob after rejected ghost';
        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: text,
          messageId: 'gm027-alice-valid-send',
          timestamp: createdAt.add(const Duration(minutes: 3)),
        );
        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, sentMessage!.id), [
          bob.peerId,
        ]);

        await waitUntil(
          () async => await incomingTextCount(bob, text) == 1,
          maxTicks: 40,
        );
        expect(await incomingTextCount(bob, text), 1);
        expect(
          await alice.groupRepo.getMember(groupId, invalidMember.peerId),
          isNull,
        );
        expect(
          await bob.groupRepo.getMember(groupId, invalidMember.peerId),
          isNull,
        );
        expect(network.isSubscribed(groupId, invalidMember.peerId), isFalse);
      },
    );

    test(
      'GM-028 empty PeerId add event does not persist or block valid delivery',
      () async {
        const groupId = 'grp-gm028-empty-peer';
        final createdAt = DateTime.utc(2026, 5, 11, 10, 30);
        final alice = GroupTestUser.create(
          peerId: 'peer-gm028-alice',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'peer-gm028-bob',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        Future<void> saveKey(GroupTestUser user) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'gm028-group-key',
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> memberEntry(GroupTestUser user, String role) {
          return {
            'peerId': user.peerId,
            'username': user.username,
            'role': role,
            'publicKey': user.publicKey,
            'mlKemPublicKey': 'mlkem-${user.peerId}',
            'devices': [user.deviceIdentity.toJson()],
          };
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] != messageId) continue;
            return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>();
          }
          return const <String>[];
        }

        Future<int> incomingTextCount(GroupTestUser user, String text) async {
          return (await user.loadGroupMessages(groupId))
              .where((message) => message.isIncoming && message.text == text)
              .length;
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-028 Group',
          createdAt: createdAt,
        );
        await saveKey(alice);
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await saveKey(bob);
        alice.start();
        bob.start();
        await pump();

        final blankMember = {
          'peerId': '   ',
          'username': 'Blank Peer',
          'role': 'writer',
          'publicKey': 'pk-gm028-blank',
          'mlKemPublicKey': 'mlkem-gm028-blank',
          'devices': [
            {
              'deviceId': 'gm028-blank-device',
              'transportPeerId': 'gm028-blank-device',
              'deviceSigningPublicKey': 'pk-gm028-blank-device',
              'mlKemPublicKey': 'mlkem-gm028-blank-device',
              'keyPackageId': 'kp-gm028-blank-device',
              'keyPackagePublicMaterial': 'public-kp-gm028-blank-device',
              'status': 'active',
            },
          ],
        };
        final groupConfig = {
          'name': 'GM-028 Group',
          'groupType': 'chat',
          'members': [
            memberEntry(alice, 'admin'),
            blankMember,
            memberEntry(bob, 'writer'),
          ],
          'createdBy': alice.peerId,
          'createdAt': createdAt.toIso8601String(),
          groupConfigStateHashField: 'stale-gm028-hash',
        };

        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': jsonEncode({
            '__sys': 'member_added',
            'eventAt': createdAt
                .add(const Duration(minutes: 2))
                .toIso8601String(),
            'member': blankMember,
            'groupConfig': groupConfig,
          }),
          'timestamp': createdAt
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          'messageId': 'gm028-empty-peer-member-added',
        }, senderDeviceId: alice.deviceId);
        await pump();

        for (final user in <GroupTestUser>[alice, bob]) {
          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.where((member) => member.peerId.trim().isEmpty),
            isEmpty,
          );
          expect(await user.groupRepo.getMember(groupId, ''), isNull);
          expect(await user.groupRepo.getMember(groupId, '   '), isNull);
        }
        expect(network.isSubscribed(groupId, '   '), isFalse);
        expect(network.getSubscribers(groupId), isNot(contains('   ')));

        final updateConfigMessages = bob.bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:updateConfig')
            .toList(growable: false);
        expect(updateConfigMessages, hasLength(1));
        final syncedConfig =
            updateConfigMessages.single['payload']['groupConfig']
                as Map<String, dynamic>;
        expect(
          isGroupConfigStateHashValid(
            groupId: groupId,
            groupConfig: syncedConfig,
          ),
          isTrue,
        );
        final syncedMembers = (syncedConfig['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(syncedMembers.map((member) => member['peerId']).toSet(), {
          alice.peerId,
          bob.peerId,
        });
        expect(jsonEncode(syncedConfig), isNot(contains('gm028-blank-device')));

        const text = 'GM-028 Alice to Bob after rejected blank peer';
        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: text,
          messageId: 'gm028-alice-valid-send',
          timestamp: createdAt.add(const Duration(minutes: 3)),
        );
        expect(sendResult, group_send.SendGroupMessageResult.success);
        expect(sentMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, sentMessage!.id), [
          bob.peerId,
        ]);

        await waitUntil(
          () async => await incomingTextCount(bob, text) == 1,
          maxTicks: 40,
        );
        expect(await incomingTextCount(bob, text), 1);
        expect(network.isSubscribed(groupId, '   '), isFalse);
      },
    );
  });
}

class _TrackingInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in attempts.values.where((a) => a.groupId == groupId))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: status,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = attempts[key];
    attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      attempts.remove(key);
    }
    return keys.length;
  }
}

class _PerRecipientInviteP2PService extends FakeP2PService {
  _PerRecipientInviteP2PService({required this.failingPeerIds})
    : super(initialState: const NodeState(isStarted: true));

  final Set<String> failingPeerIds;
  final List<({String peerId, String content})> inboxStoreLog = [];

  @override
  Future<bool> sendMessage(String peerId, String message) async {
    sendMessageCallCount++;
    lastSendMessagePeerId = peerId;
    lastSendMessageContent = message;
    sentMessageLog.add((peerId: peerId, content: message));
    return !failingPeerIds.contains(peerId);
  }

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    storeInInboxCallCount++;
    lastStoreInInboxPeerId = toPeerId;
    lastStoreInInboxMessage = message;
    inboxStoreLog.add((peerId: toPeerId, content: message));
    return !failingPeerIds.contains(toPeerId);
  }
}

class _DelayedGroupLeaveBridge extends FakeBridge {
  final Completer<void> leaveStarted = Completer<void>();
  final Completer<void> _releaseLeave = Completer<void>();
  void Function()? onLateLeaveCompleted;
  void Function()? onJoin;
  int joinCalls = 0;

  void completeLeave() {
    if (!_releaseLeave.isCompleted) {
      _releaseLeave.complete();
    }
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:leave') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      if (!leaveStarted.isCompleted) {
        leaveStarted.complete();
      }
      await _releaseLeave.future;
      onLateLeaveCompleted?.call();
      return jsonEncode({'ok': true});
    }
    if (cmd == 'group:join') {
      joinCalls++;
      onJoin?.call();
    }
    return super.send(message);
  }
}

class _GroupMembershipCursorBridge extends FakeBridge {
  final Map<String, ({List<Map<String, dynamic>> messages, String cursor})>
  _pages = {};

  void addPage({
    required String groupId,
    required String cursor,
    required List<Map<String, dynamic>> messages,
    String nextCursor = '',
  }) {
    _pages['$groupId:$cursor'] = (messages: messages, cursor: nextCursor);
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:inboxRetrieveCursor') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      final cursor = payload['cursor'] as String? ?? '';
      final page = _pages['$groupId:$cursor'];
      return jsonEncode({
        'ok': true,
        'messages': page?.messages ?? const <Map<String, dynamic>>[],
        'cursor': page?.cursor ?? '',
      });
    }
    return super.send(message);
  }
}
