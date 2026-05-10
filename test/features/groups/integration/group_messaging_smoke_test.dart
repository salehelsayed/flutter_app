import 'dart:convert';

import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  /// Helper to let async listeners process delivered messages.
  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Multi-user group messaging smoke tests', () {
    test(
      '3 users: basic fan-out — sender does not receive own message',
      () async {
        // -- arrange --
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-1';
        await alice.createGroup(groupId: groupId, name: 'Test Group');
        await alice.addMember(groupId: groupId, invitee: bob);

        // Existing members need the member_added system event to hydrate later
        // joins into their local member list before the row is fully proven.
        alice.start();
        bob.start();
        charlie.start();

        await alice.addMember(groupId: groupId, invitee: charlie);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        Future<void> expectHydratedGroupState(
          GroupTestUser user,
          GroupRole expectedRole,
        ) async {
          final hydratedGroup = await user.groupRepo.getGroup(groupId);
          expect(hydratedGroup, isNotNull);
          expect(hydratedGroup!.id, groupId);
          expect(hydratedGroup.name, 'Test Group');
          expect(hydratedGroup.myRole, expectedRole);
          expect(hydratedGroup.createdBy, 'alice-peer');

          final members = await user.groupRepo.getMembers(groupId);
          expect(members.map((member) => member.peerId).toSet(), {
            'alice-peer',
            'bob-peer',
            'charlie-peer',
          });

          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId['alice-peer'], MemberRole.admin);
          expect(rolesByPeerId['bob-peer'], MemberRole.writer);
          expect(rolesByPeerId['charlie-peer'], MemberRole.writer);
        }

        await expectHydratedGroupState(alice, GroupRole.admin);
        await expectHydratedGroupState(bob, GroupRole.member);
        await expectHydratedGroupState(charlie, GroupRole.member);

        // -- act --
        await alice.sendGroupMessage(groupId: groupId, text: 'Hello group!');
        await pump();

        // -- assert --
        final bobMessages = await bob.loadGroupMessages(groupId);
        final bobRegular = bobMessages
            .where((message) => message.text == 'Hello group!')
            .toList();
        expect(bobRegular, hasLength(1));
        expect(bobRegular.first.isIncoming, isTrue);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final charlieRegular = charlieMessages
            .where((message) => message.text == 'Hello group!')
            .toList();
        expect(charlieRegular, hasLength(1));
        expect(charlieRegular.first.isIncoming, isTrue);

        // Alice has 0 incoming (the network does not fan back to sender)
        final aliceIncoming = (await alice.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).toList();
        expect(aliceIncoming, isEmpty);

        // Alice has 1 total message (her own outgoing, saved locally by sendGroupMessage)
        final aliceAll = await alice.loadGroupMessages(groupId);
        expect(aliceAll, hasLength(1));
        expect(aliceAll.first.isIncoming, isFalse);

        // -- cleanup --
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'GM-001 creates private A/B/C group with shared epoch and exact fanout tuple',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'gm001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm001-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-gm001-baseline';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'gm001-shared-initial-key';
        const messageId = 'gm001-baseline-message';
        const plaintext = 'GM-001 baseline private message';
        final expectedMemberPeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        };

        await alice.createGroup(groupId: groupId, name: 'GM-001 Baseline');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        final baselineGroup = (await alice.groupRepo.getGroup(groupId))!;
        final baselineMembers = await alice.groupRepo.getMembers(groupId);

        Future<void> saveBaselineState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(baselineGroup.copyWith(myRole: role));
          for (final member in baselineMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: DateTime.utc(2026, 5, 10),
            ),
          );
        }

        await Future.wait([
          saveBaselineState(alice, GroupRole.admin),
          saveBaselineState(bob, GroupRole.member),
          saveBaselineState(charlie, GroupRole.member),
        ]);

        List<String> sortedDeviceIds(GroupMember member) {
          final deviceIds = member.devices
              .map((device) => device.deviceId)
              .toList();
          deviceIds.sort();
          return deviceIds;
        }

        Future<Map<String, Object?>> sharedConfigSnapshot(
          GroupTestUser user,
        ) async {
          final group = (await user.groupRepo.getGroup(groupId))!;
          final members = await user.groupRepo.getMembers(groupId);
          members.sort((a, b) => a.peerId.compareTo(b.peerId));
          return {
            'id': group.id,
            'name': group.name,
            'topicName': group.topicName,
            'type': group.type,
            'createdBy': group.createdBy,
            'members': members
                .map(
                  (member) => {
                    'peerId': member.peerId,
                    'username': member.username,
                    'role': member.role,
                    'publicKey': member.publicKey,
                    'mlKemPublicKey': member.mlKemPublicKey,
                    'devices': sortedDeviceIds(member),
                  },
                )
                .toList(),
          };
        }

        final expectedConfig = await sharedConfigSnapshot(alice);

        Future<void> expectBaselineParticipant(
          GroupTestUser user,
          GroupRole role,
        ) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: user.username);
          expect(group!.myRole, role, reason: user.username);
          expect(group.topicName, 'topic-$groupId', reason: user.username);
          expect(
            await sharedConfigSnapshot(user),
            expectedConfig,
            reason: '${user.username} should share the baseline group config',
          );

          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            expectedMemberPeerIds,
            reason: '${user.username} should have the A/B/C member set',
          );

          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId[alice.peerId], MemberRole.admin);
          expect(rolesByPeerId[bob.peerId], MemberRole.writer);
          expect(rolesByPeerId[charlie.peerId], MemberRole.writer);

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: user.username);
          expect(latestKey!.keyGeneration, keyEpoch, reason: user.username);
          expect(
            latestKey.encryptedKey,
            sharedEncryptedKey,
            reason: user.username,
          );
        }

        await expectBaselineParticipant(alice, GroupRole.admin);
        await expectBaselineParticipant(bob, GroupRole.member);
        await expectBaselineParticipant(charlie, GroupRole.member);

        alice.start();
        bob.start();
        charlie.start();

        expect(network.getSubscribers(groupId).toSet(), expectedMemberPeerIds);

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: plaintext,
          messageId: messageId,
          timestamp: DateTime.utc(2026, 5, 10, 12),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.id, messageId);
        expect(sentMessage.groupId, groupId);
        expect(sentMessage.senderPeerId, alice.peerId);
        expect(sentMessage.senderUsername, alice.username);
        expect(sentMessage.keyGeneration, keyEpoch);
        expect(sentMessage.text, plaintext);
        expect(sentMessage.isIncoming, isFalse);

        await pump();

        Future<void> expectIncomingTuple(GroupTestUser recipient) async {
          final matching = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matching,
            hasLength(1),
            reason: '${recipient.username} should persist the GM-001 row once',
          );

          final received = matching.single;
          expect(received.isIncoming, isTrue, reason: recipient.username);
          expect(received.groupId, groupId, reason: recipient.username);
          expect(received.id, messageId, reason: recipient.username);
          expect(
            received.senderPeerId,
            alice.peerId,
            reason: recipient.username,
          );
          expect(
            received.senderUsername,
            alice.username,
            reason: recipient.username,
          );
          expect(received.keyGeneration, keyEpoch, reason: recipient.username);
          expect(received.text, plaintext, reason: recipient.username);
        }

        await expectIncomingTuple(bob);
        await expectIncomingTuple(charlie);

        final aliceMatching = (await alice.loadGroupMessages(
          groupId,
        )).where((message) => message.id == messageId).toList();
        expect(aliceMatching, hasLength(1));
        expect(aliceMatching.single.isIncoming, isFalse);
        expect(aliceMatching.single.groupId, groupId);
        expect(aliceMatching.single.senderPeerId, alice.peerId);
        expect(aliceMatching.single.senderUsername, alice.username);
        expect(aliceMatching.single.keyGeneration, keyEpoch);
        expect(aliceMatching.single.text, plaintext);

        final aliceIncomingEcho = aliceMatching
            .where((message) => message.isIncoming)
            .toList();
        expect(aliceIncomingEcho, isEmpty);
      },
    );

    test(
      'GM-002 adds D while A/B/C are online and converges post-add delivery',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'gm002-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm002-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm002-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'gm002-diana-peer',
          username: 'Diana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          diana.dispose();
        });

        const groupId = 'group-gm002-add-d-online';
        const keyEpoch = 3;
        const sharedEncryptedKey = 'gm002-shared-current-key';
        const aliceMessageId = 'gm002-a-post-add';
        const dianaMessageId = 'gm002-d-post-add';
        const alicePlaintext = 'GM-002 post-add message from A';
        const dianaPlaintext = 'GM-002 post-add message from D';
        final baselineAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final addDAt = baselineAt.add(const Duration(minutes: 1));
        final aliceSentAt = baselineAt.add(const Duration(minutes: 2));
        final dianaSentAt = baselineAt.add(const Duration(minutes: 3));
        final expectedBaselinePeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        };
        final expectedPostAddPeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          diana.peerId,
        };

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-002 Add D',
          createdAt: baselineAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: baselineAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baselineAt,
        );

        final baselineGroup = (await alice.groupRepo.getGroup(groupId))!;
        final baselineMembers = await alice.groupRepo.getMembers(groupId);
        expect(
          baselineMembers.map((member) => member.peerId).toSet(),
          expectedBaselinePeerIds,
        );

        Future<void> saveBaselineState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(baselineGroup.copyWith(myRole: role));
          for (final member in baselineMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: baselineAt,
            ),
          );
        }

        await Future.wait([
          saveBaselineState(alice, GroupRole.admin),
          saveBaselineState(bob, GroupRole.member),
          saveBaselineState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        expect(
          network.getSubscribers(groupId).toSet(),
          expectedBaselinePeerIds,
        );
        expect(await diana.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, diana.peerId), isFalse);

        await alice.addMember(
          groupId: groupId,
          invitee: diana,
          joinedAt: addDAt,
        );
        await diana.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: baselineAt,
          ),
        );
        diana.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: diana);
        await pump();

        expect(network.getSubscribers(groupId).toSet(), expectedPostAddPeerIds);

        Future<void> expectConvergedMemberState(
          GroupTestUser user,
          GroupRole expectedGroupRole,
        ) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: user.username);
          expect(group!.myRole, expectedGroupRole, reason: user.username);

          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            expectedPostAddPeerIds,
            reason: '${user.username} should have A/B/C/D after D joins',
          );

          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId[alice.peerId], MemberRole.admin);
          expect(rolesByPeerId[bob.peerId], MemberRole.writer);
          expect(rolesByPeerId[charlie.peerId], MemberRole.writer);
          expect(rolesByPeerId[diana.peerId], MemberRole.writer);

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: user.username);
          expect(latestKey!.keyGeneration, keyEpoch, reason: user.username);
          expect(
            latestKey.encryptedKey,
            sharedEncryptedKey,
            reason: user.username,
          );
        }

        await expectConvergedMemberState(alice, GroupRole.admin);
        await expectConvergedMemberState(bob, GroupRole.member);
        await expectConvergedMemberState(charlie, GroupRole.member);
        await expectConvergedMemberState(diana, GroupRole.member);

        final (aliceSendResult, aliceSentMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: alicePlaintext,
              messageId: aliceMessageId,
              timestamp: aliceSentAt,
            );
        expect(aliceSendResult.name, 'success');
        expect(aliceSentMessage, isNotNull);

        await pump();

        final (dianaSendResult, dianaSentMessage) = await diana
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: dianaPlaintext,
              messageId: dianaMessageId,
              timestamp: dianaSentAt,
            );
        expect(dianaSendResult.name, 'success');
        expect(dianaSentMessage, isNotNull);

        await pump();

        Future<void> expectMessageTuple(
          GroupTestUser user, {
          required String messageId,
          required String senderPeerId,
          required String senderUsername,
          required String text,
          required bool isIncoming,
        }) async {
          final matching = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matching,
            hasLength(1),
            reason: '${user.username} should persist $messageId once',
          );

          final message = matching.single;
          expect(message.isIncoming, isIncoming, reason: user.username);
          expect(message.groupId, groupId, reason: user.username);
          expect(message.id, messageId, reason: user.username);
          expect(message.senderPeerId, senderPeerId, reason: user.username);
          expect(message.senderUsername, senderUsername, reason: user.username);
          expect(message.keyGeneration, keyEpoch, reason: user.username);
          expect(message.text, text, reason: user.username);
        }

        await expectMessageTuple(
          alice,
          messageId: aliceMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: alicePlaintext,
          isIncoming: false,
        );
        for (final recipient in [bob, charlie, diana]) {
          await expectMessageTuple(
            recipient,
            messageId: aliceMessageId,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            text: alicePlaintext,
            isIncoming: true,
          );
        }

        await expectMessageTuple(
          diana,
          messageId: dianaMessageId,
          senderPeerId: diana.peerId,
          senderUsername: diana.username,
          text: dianaPlaintext,
          isIncoming: false,
        );
        for (final recipient in [alice, bob, charlie]) {
          await expectMessageTuple(
            recipient,
            messageId: dianaMessageId,
            senderPeerId: diana.peerId,
            senderUsername: diana.username,
            text: dianaPlaintext,
            isIncoming: true,
          );
        }
      },
    );

    test(
      'GM-003 adds D while D is offline, catches up post-add only, and D can send',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'gm003-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'gm003-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm003-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'gm003-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-gm003-add-d-offline';
        const keyEpoch = 4;
        const sharedEncryptedKey = 'gm003-shared-current-key';
        const preAddMessageId = 'gm003-a-pre-add';
        const postAddMessageId = 'gm003-a-post-add';
        const danaMessageId = 'gm003-d-post-open';
        const preAddPlaintext = 'GM-003 pre-add message from A';
        const postAddPlaintext = 'GM-003 post-add message from A';
        const danaPlaintext = 'GM-003 message from D after opening';
        final baselineAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final addDAt = baselineAt.add(const Duration(minutes: 1));
        final preAddSentAt = baselineAt.add(const Duration(minutes: 2));
        final postAddSentAt = baselineAt.add(const Duration(minutes: 3));
        final danaSentAt = baselineAt.add(const Duration(minutes: 4));
        final expectedBaselinePeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        };
        final expectedPostAddPeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dana.peerId,
        };

        await alice.createGroup(
          groupId: groupId,
          name: 'GM-003 Add D Offline',
          createdAt: baselineAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: baselineAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: baselineAt,
        );

        final baselineGroup = (await alice.groupRepo.getGroup(groupId))!;
        final baselineMembers = await alice.groupRepo.getMembers(groupId);
        expect(
          baselineMembers.map((member) => member.peerId).toSet(),
          expectedBaselinePeerIds,
        );

        Future<void> saveKnownState(GroupTestUser user, GroupRole role) async {
          await user.groupRepo.saveGroup(baselineGroup.copyWith(myRole: role));
          for (final member in baselineMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: baselineAt,
            ),
          );
        }

        await Future.wait([
          saveKnownState(alice, GroupRole.admin),
          saveKnownState(bob, GroupRole.member),
          saveKnownState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        expect(
          network.getSubscribers(groupId).toSet(),
          expectedBaselinePeerIds,
        );
        expect(await dana.groupRepo.getGroup(groupId), isNull);
        expect(network.isSubscribed(groupId, dana.peerId), isFalse);

        final (preAddResult, preAddMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: preAddPlaintext,
              messageId: preAddMessageId,
              timestamp: preAddSentAt,
            );
        expect(preAddResult.name, 'success');
        expect(preAddMessage, isNotNull);
        await pump();

        network.holdDeliveriesFor(dana.peerId);
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: addDAt,
        );
        await dana.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: baselineAt,
          ),
        );
        await alice.broadcastMemberAdded(groupId: groupId, newMember: dana);
        await pump();

        expect(network.isSubscribed(groupId, dana.peerId), isTrue);
        expect(
          network.heldDeliveryCountFor(dana.peerId),
          greaterThanOrEqualTo(1),
        );

        final (postAddResult, postAddMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: postAddPlaintext,
              messageId: postAddMessageId,
              timestamp: postAddSentAt,
            );
        expect(postAddResult.name, 'success');
        expect(postAddMessage, isNotNull);
        await pump();
        expect(
          network.heldDeliveryCountFor(dana.peerId),
          greaterThanOrEqualTo(2),
        );

        Future<void> expectMessageTuple(
          GroupTestUser user, {
          required String messageId,
          required String senderPeerId,
          required String senderUsername,
          required String text,
          required bool isIncoming,
        }) async {
          final matching = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matching,
            hasLength(1),
            reason: '${user.username} should persist $messageId once',
          );

          final message = matching.single;
          expect(message.isIncoming, isIncoming, reason: user.username);
          expect(message.groupId, groupId, reason: user.username);
          expect(message.id, messageId, reason: user.username);
          expect(message.senderPeerId, senderPeerId, reason: user.username);
          expect(message.senderUsername, senderUsername, reason: user.username);
          expect(message.keyGeneration, keyEpoch, reason: user.username);
          expect(message.text, text, reason: user.username);
        }

        Future<void> expectNoMessage(
          GroupTestUser user,
          String messageId,
        ) async {
          final matching = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matching,
            isEmpty,
            reason: '${user.username} must not persist $messageId',
          );
        }

        await expectMessageTuple(
          alice,
          messageId: preAddMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: preAddPlaintext,
          isIncoming: false,
        );
        for (final recipient in [bob, charlie]) {
          await expectMessageTuple(
            recipient,
            messageId: preAddMessageId,
            senderPeerId: alice.peerId,
            senderUsername: alice.username,
            text: preAddPlaintext,
            isIncoming: true,
          );
        }
        await expectNoMessage(dana, preAddMessageId);
        await expectNoMessage(dana, postAddMessageId);

        dana.start();
        await network.releaseHeldDeliveriesFor(dana.peerId);
        await pump();

        Future<void> expectConvergedMemberState(
          GroupTestUser user,
          GroupRole expectedGroupRole,
        ) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: user.username);
          expect(group!.myRole, expectedGroupRole, reason: user.username);

          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            expectedPostAddPeerIds,
            reason: '${user.username} should have A/B/C/D after D opens',
          );

          final latestKey = await user.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull, reason: user.username);
          expect(latestKey!.keyGeneration, keyEpoch, reason: user.username);
          expect(
            latestKey.encryptedKey,
            sharedEncryptedKey,
            reason: user.username,
          );
        }

        await expectConvergedMemberState(alice, GroupRole.admin);
        await expectConvergedMemberState(bob, GroupRole.member);
        await expectConvergedMemberState(charlie, GroupRole.member);
        await expectConvergedMemberState(dana, GroupRole.member);

        await expectMessageTuple(
          dana,
          messageId: postAddMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: postAddPlaintext,
          isIncoming: true,
        );
        await expectNoMessage(dana, preAddMessageId);

        final (danaSendResult, danaSentMessage) = await dana
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: danaPlaintext,
              messageId: danaMessageId,
              timestamp: danaSentAt,
            );
        expect(danaSendResult.name, 'success');
        expect(danaSentMessage, isNotNull);
        await pump();

        await expectMessageTuple(
          dana,
          messageId: danaMessageId,
          senderPeerId: dana.peerId,
          senderUsername: dana.username,
          text: danaPlaintext,
          isIncoming: false,
        );
        for (final recipient in [alice, bob, charlie]) {
          await expectMessageTuple(
            recipient,
            messageId: danaMessageId,
            senderPeerId: dana.peerId,
            senderUsername: dana.username,
            text: danaPlaintext,
            isIncoming: true,
          );
        }
      },
    );

    test(
      '4 users: round-robin messaging — all receive from all others',
      () async {
        // -- arrange --
        final admin = GroupTestUser.create(
          peerId: 'admin-peer',
          username: 'Admin',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final diana = GroupTestUser.create(
          peerId: 'diana-peer',
          username: 'Diana',
          network: network,
        );

        const groupId = 'group-roundrobin';
        await admin.createGroup(groupId: groupId, name: 'Round Robin');
        await admin.addMember(groupId: groupId, invitee: bob);
        await admin.addMember(groupId: groupId, invitee: charlie);
        await admin.addMember(groupId: groupId, invitee: diana);

        admin.start();
        bob.start();
        charlie.start();
        diana.start();

        await admin.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await admin.broadcastMemberAdded(groupId: groupId, newMember: diana);
        await pump();

        // -- act: each user sends one message --
        await admin.sendGroupMessage(groupId: groupId, text: 'From Admin');
        await pump();
        await bob.sendGroupMessage(groupId: groupId, text: 'From Bob');
        await pump();
        await charlie.sendGroupMessage(groupId: groupId, text: 'From Charlie');
        await pump();
        await diana.sendGroupMessage(groupId: groupId, text: 'From Diana');
        await pump();

        // -- assert --
        // Each user should have 4 total messages: 1 outgoing + 3 incoming
        for (final user in [admin, bob, charlie, diana]) {
          final messages = (await user.loadGroupMessages(
            groupId,
          )).where((message) => !message.id.startsWith('sys-')).toList();
          expect(
            messages,
            hasLength(4),
            reason: '${user.username} should have 4 total messages',
          );

          final incoming = messages.where((m) => m.isIncoming).toList();
          final outgoing = messages.where((m) => !m.isIncoming).toList();
          expect(
            incoming,
            hasLength(3),
            reason: '${user.username} should have 3 incoming messages',
          );
          expect(
            outgoing,
            hasLength(1),
            reason: '${user.username} should have 1 outgoing message',
          );
        }

        Future<void> expectIncomingFromEveryOtherMember(
          GroupTestUser recipient,
          Map<String, String> expectedSenderPeerIdsByText,
          Map<String, String> expectedSenderUsernamesByText,
        ) async {
          final incoming = (await recipient.loadGroupMessages(
            groupId,
          )).where((m) => m.isIncoming && !m.id.startsWith('sys-')).toList();
          expect(
            incoming,
            hasLength(expectedSenderPeerIdsByText.length),
            reason:
                '${recipient.username} should receive each other member once',
          );
          expect(
            incoming.map((m) => m.text).toSet(),
            expectedSenderPeerIdsByText.keys.toSet(),
            reason: '${recipient.username} should receive the expected texts',
          );
          expect(
            incoming.map((m) => m.senderPeerId).toSet(),
            expectedSenderPeerIdsByText.values.toSet(),
            reason:
                '${recipient.username} should receive from the expected peers',
          );

          for (final expected in expectedSenderPeerIdsByText.entries) {
            final matchingMessages = incoming
                .where(
                  (m) =>
                      m.text == expected.key &&
                      m.senderPeerId == expected.value &&
                      m.senderUsername ==
                          expectedSenderUsernamesByText[expected.key],
                )
                .toList();
            expect(
              matchingMessages,
              hasLength(1),
              reason:
                  '${recipient.username} should receive "${expected.key}" '
                  'exactly once from ${expected.value}',
            );
          }
        }

        await expectIncomingFromEveryOtherMember(
          admin,
          {
            'From Bob': 'bob-peer',
            'From Charlie': 'charlie-peer',
            'From Diana': 'diana-peer',
          },
          {'From Bob': 'Bob', 'From Charlie': 'Charlie', 'From Diana': 'Diana'},
        );
        await expectIncomingFromEveryOtherMember(
          bob,
          {
            'From Admin': 'admin-peer',
            'From Charlie': 'charlie-peer',
            'From Diana': 'diana-peer',
          },
          {
            'From Admin': 'Admin',
            'From Charlie': 'Charlie',
            'From Diana': 'Diana',
          },
        );
        await expectIncomingFromEveryOtherMember(
          charlie,
          {
            'From Admin': 'admin-peer',
            'From Bob': 'bob-peer',
            'From Diana': 'diana-peer',
          },
          {'From Admin': 'Admin', 'From Bob': 'Bob', 'From Diana': 'Diana'},
        );
        await expectIncomingFromEveryOtherMember(
          diana,
          {
            'From Admin': 'admin-peer',
            'From Bob': 'bob-peer',
            'From Charlie': 'charlie-peer',
          },
          {'From Admin': 'Admin', 'From Bob': 'Bob', 'From Charlie': 'Charlie'},
        );

        // -- cleanup --
        admin.dispose();
        bob.dispose();
        charlie.dispose();
        diana.dispose();
      },
    );

    test(
      'MS002 live fake-network delivery stores and checks transport binding',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ms002-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ms002-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-ms002-live-binding';
        await alice.createGroup(groupId: groupId, name: 'MS002 Live');
        await alice.addMember(groupId: groupId, invitee: bob);
        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'MS002 bound live message',
          messageId: 'ms002-live-bound',
        );
        await pump();

        final stored = await bob.msgRepo.getMessage('ms002-live-bound');
        expect(stored, isNotNull);
        expect(stored!.senderPeerId, alice.peerId);
        expect(stored.transportPeerId, alice.peerId);

        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'transportPeerId': 'ms002-attacker-peer',
          'senderUsername': alice.username,
          'keyEpoch': 0,
          'text': 'MS002 spoofed live message',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': 'ms002-live-spoof',
        }, senderDeviceId: alice.deviceId);
        await pump();

        expect(await bob.msgRepo.getMessage('ms002-live-spoof'), isNull);
      },
    );

    test(
      'MS003 live skewed timestamps clamp far future and keep latest sane',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ms003-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ms003-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ms003-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ms003-live-skew';
        await alice.createGroup(groupId: groupId, name: 'MS003 Live');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        alice.start();
        bob.start();
        charlie.start();
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final beforeReceive = DateTime.now().toUtc();
        final past = beforeReceive.subtract(const Duration(minutes: 10));
        final current = beforeReceive;
        final nearFuture = beforeReceive.add(const Duration(minutes: 3));
        final farFuture = beforeReceive.add(const Duration(days: 2));

        Future<void> publishSkewed({
          required String id,
          required String text,
          required DateTime timestamp,
        }) {
          return network.publish(groupId, charlie.peerId, {
            'groupId': groupId,
            'senderId': charlie.peerId,
            'senderUsername': charlie.username,
            'keyEpoch': 0,
            'text': text,
            'timestamp': timestamp.toIso8601String(),
            'messageId': id,
          }, senderDeviceId: charlie.deviceId);
        }

        await publishSkewed(
          id: 'ms003-live-past',
          text: 'Past skew',
          timestamp: past,
        );
        await publishSkewed(
          id: 'ms003-live-far',
          text: 'Far future skew',
          timestamp: farFuture,
        );
        await publishSkewed(
          id: 'ms003-live-current',
          text: 'Current clock',
          timestamp: current,
        );
        await publishSkewed(
          id: 'ms003-live-near',
          text: 'Near future clock',
          timestamp: nearFuture,
        );
        await pump();

        Future<void> expectSkewSafe(GroupTestUser recipient) async {
          final messages = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id.startsWith('ms003-live-')).toList();
          expect(messages.map((message) => message.id), [
            'ms003-live-past',
            'ms003-live-current',
            'ms003-live-far',
            'ms003-live-near',
          ]);

          final clamped = messages.singleWhere(
            (message) => message.id == 'ms003-live-far',
          );
          expect(clamped.timestamp.isBefore(farFuture), isTrue);
          expect(clamped.timestamp.isBefore(nearFuture), isTrue);
          expect(
            (await recipient.msgRepo.getLatestMessage(groupId))!.id,
            'ms003-live-near',
          );
        }

        await expectSkewSafe(alice);
        await expectSkewSafe(bob);
      },
    );

    test(
      'simultaneous sends fan out to the third member without loss',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-simultaneous';
        await alice.createGroup(groupId: groupId, name: 'Simultaneous Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await Future.wait([
          alice.sendGroupMessage(groupId: groupId, text: 'From Alice'),
          bob.sendGroupMessage(groupId: groupId, text: 'From Bob'),
        ]);
        await pump();

        final charlieIncoming = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.isIncoming).toList();
        expect(charlieIncoming, hasLength(2));
        expect(charlieIncoming.map((message) => message.text).toSet(), {
          'From Alice',
          'From Bob',
        });
        expect(
          charlieIncoming.map((message) => message.id).toSet(),
          hasLength(2),
        );

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'MS004 concurrent A/B/C sends and quoted replies converge to deterministic order',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-ms004-concurrent';
        await alice.createGroup(groupId: groupId, name: 'MS-004');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        final concurrentAt = DateTime.utc(2026, 4, 29, 12);
        final sent = await Future.wait([
          alice.sendGroupMessage(
            groupId: groupId,
            text: 'Concurrent A',
            messageId: 'ms004-a',
            timestamp: concurrentAt,
          ),
          bob.sendGroupMessage(
            groupId: groupId,
            text: 'Concurrent B',
            messageId: 'ms004-b',
            timestamp: concurrentAt,
          ),
          charlie.sendGroupMessage(
            groupId: groupId,
            text: 'Concurrent C',
            messageId: 'ms004-c',
            timestamp: concurrentAt,
          ),
        ]);
        await pump();

        await Future.wait([
          bob.sendGroupMessage(
            groupId: groupId,
            text: 'Reply to A',
            quotedMessageId: sent[0]!.id,
            messageId: 'ms004-0-reply-b-to-a',
            timestamp: concurrentAt,
          ),
          charlie.sendGroupMessage(
            groupId: groupId,
            text: 'Reply to B',
            quotedMessageId: sent[1]!.id,
            messageId: 'ms004-0-reply-c-to-b',
            timestamp: concurrentAt,
          ),
        ]);
        await pump();

        Future<void> expectConverged(GroupTestUser user) async {
          final messages = (await user.loadGroupMessages(
            groupId,
          )).where((message) => !message.id.startsWith('sys-')).toList();
          expect(
            messages.map((message) => message.id).toList(),
            [
              'ms004-a',
              'ms004-b',
              'ms004-c',
              'ms004-0-reply-b-to-a',
              'ms004-0-reply-c-to-b',
            ],
            reason: '${user.username} should render the same stable order',
          );
          expect(
            messages
                .singleWhere((message) => message.id == 'ms004-0-reply-b-to-a')
                .quotedMessageId,
            'ms004-a',
          );
          expect(
            messages
                .singleWhere((message) => message.id == 'ms004-0-reply-c-to-b')
                .quotedMessageId,
            'ms004-b',
          );
        }

        await expectConverged(alice);
        await expectConverged(bob);
        await expectConverged(charlie);

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'MS018 rotation race preserves message epochs under out-of-order live delivery',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-ms018-rotation-race';
        await alice.createGroup(groupId: groupId, name: 'MS-018');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user, int epoch) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ms018-key-$epoch',
              createdAt: DateTime.utc(2026, 4, 29, 12, epoch),
            ),
          );
        }

        await Future.wait([
          saveKey(alice, 1),
          saveKey(bob, 1),
          saveKey(charlie, 1),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        network.holdDeliveriesFor(charlie.deviceId);

        final before = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'Before rotation commit',
          messageId: 'ms018-before',
          timestamp: DateTime.utc(2026, 4, 29, 12),
        );
        expect(before.$1.name, 'success');
        expect(before.$2!.keyGeneration, 1);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'ms018-key-2',
          'keyEpoch': 2,
        };
        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ms018-key-rotated',
          'topicPeers': 2,
        };
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
        );
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);

        final during = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'During remote rotation before local commit',
          messageId: 'ms018-during',
          timestamp: DateTime.utc(2026, 4, 29, 12, 0, 1),
        );
        expect(during.$1.name, 'success');
        expect(during.$2!.keyGeneration, 1);

        await Future.wait([saveKey(bob, 2), saveKey(charlie, 2)]);

        final after = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'After local rotation commit',
          messageId: 'ms018-after',
          timestamp: DateTime.utc(2026, 4, 29, 12, 0, 2),
        );
        expect(after.$1.name, 'success');
        expect(after.$2!.keyGeneration, 2);
        await pump();

        expect(network.heldDeliveryCountFor(charlie.deviceId), 3);

        Future<void> expectEpochs(
          GroupTestUser user, {
          required bool incoming,
        }) async {
          final messages = await user.loadGroupMessages(groupId);
          final byId = {
            for (final message in messages)
              if (message.id.startsWith('ms018-')) message.id: message,
          };

          expect(
            byId.keys.toSet(),
            {'ms018-before', 'ms018-during', 'ms018-after'},
            reason: '${user.username} should have exactly the MS018 messages',
          );
          expect(byId['ms018-before']!.keyGeneration, 1);
          expect(byId['ms018-during']!.keyGeneration, 1);
          expect(byId['ms018-after']!.keyGeneration, 2);
          expect(
            byId.values.map((message) => message.isIncoming).toSet(),
            {incoming},
            reason: '${user.username} incoming/outgoing state should be stable',
          );
        }

        await expectEpochs(bob, incoming: false);
        await expectEpochs(alice, incoming: true);

        await network.releaseHeldDeliveriesFor(charlie.deviceId, reverse: true);
        await pump();

        await expectEpochs(charlie, incoming: true);

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test(
      'same sender sequential messages stay ordered for both recipients',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );

        const groupId = 'group-same-sender-ordering';
        await alice.createGroup(groupId: groupId, name: 'Ordering Group');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await alice.sendGroupMessage(groupId: groupId, text: 'M1');
        await pump();

        // Keep timestamps distinct so the assertion matches the repo's
        // chronological ordering rule instead of same-millisecond luck.
        await Future<void>.delayed(const Duration(milliseconds: 2));

        await alice.sendGroupMessage(groupId: groupId, text: 'M2');
        await pump();

        Future<void> expectOrderedIncoming(GroupTestUser user) async {
          final incoming = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();

          expect(
            incoming.map((message) => message.text).toList(),
            ['M1', 'M2'],
            reason:
                '${user.username} should display same-sender messages in chronological order',
          );
        }

        await expectOrderedIncoming(bob);
        await expectOrderedIncoming(charlie);

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test('message to unknown group is ignored', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      // Alice creates a group but does NOT add Bob
      const groupId = 'group-private';
      await alice.createGroup(groupId: groupId, name: 'Private Group');

      alice.start();
      bob.start();

      // -- act: manually inject a message with this groupId into Bob's stream --
      // Bob has no group in his repo, so handleIncomingGroupMessage should
      // return null and nothing should be saved.
      // We simulate this by subscribing Bob on the network (so he receives
      // the envelope) but NOT giving him the group in his repo.
      network.subscribe(groupId, bob.peerId);

      await alice.sendGroupMessage(groupId: groupId, text: 'Secret message');
      await pump();

      // -- assert --
      // Bob's listener received the envelope, but handleIncomingGroupMessage
      // returned null because Bob's groupRepo has no matching group.
      final bobMessages = await bob.loadGroupMessages(groupId);
      expect(
        bobMessages,
        isEmpty,
        reason: 'Bob should ignore messages to groups he does not know',
      );

      // Alice still has her outgoing
      final aliceMessages = await alice.loadGroupMessages(groupId);
      expect(aliceMessages, hasLength(1));

      // -- cleanup --
      network.unsubscribe(groupId, bob.peerId);
      alice.dispose();
      bob.dispose();
    });

    test('late joiner receives messages only after joining', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'charlie-peer',
        username: 'Charlie',
        network: network,
      );

      const groupId = 'group-late';
      await alice.createGroup(groupId: groupId, name: 'Late Joiner Group');
      await alice.addMember(groupId: groupId, invitee: bob);

      alice.start();
      bob.start();
      charlie.start();

      // -- act: Alice sends BEFORE Charlie joins --
      await alice.sendGroupMessage(groupId: groupId, text: 'Before Charlie');
      await pump();

      // Now Alice adds Charlie
      await alice.addMember(groupId: groupId, invitee: charlie);

      // Alice sends AFTER Charlie joined
      await alice.sendGroupMessage(groupId: groupId, text: 'After Charlie');
      await pump();

      // -- assert --
      // Bob was a member the whole time — should have both incoming messages
      final bobMessages = (await bob.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(bobMessages, hasLength(2));
      expect(bobMessages.map((m) => m.text).toList(), [
        'Before Charlie',
        'After Charlie',
      ]);

      // Charlie joined late — should only have the message sent after joining
      final charlieMessages = (await charlie.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(charlieMessages, hasLength(1));
      expect(charlieMessages.first.text, 'After Charlie');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test('sender saves outgoing locally and others save incoming', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      const groupId = 'group-direction';
      await alice.createGroup(groupId: groupId, name: 'Direction Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      alice.start();
      bob.start();

      // -- act --
      await alice.sendGroupMessage(groupId: groupId, text: 'Test');
      await pump();

      // -- assert --
      // Alice's message is outgoing with status 'sent'
      final aliceMessages = await alice.loadGroupMessages(groupId);
      expect(aliceMessages, hasLength(1));
      expect(aliceMessages.first.isIncoming, isFalse);
      expect(aliceMessages.first.status, 'sent');
      expect(aliceMessages.first.text, 'Test');
      expect(aliceMessages.first.senderPeerId, 'alice-peer');

      // Bob's message is incoming with status 'delivered'
      final bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages, hasLength(1));
      expect(bobMessages.first.isIncoming, isTrue);
      expect(bobMessages.first.status, 'delivered');
      expect(bobMessages.first.text, 'Test');
      expect(bobMessages.first.senderPeerId, 'alice-peer');
      expect(bobMessages.first.senderUsername, 'Alice');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
    });

    test('quoted reply propagates to all recipients', () async {
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'charlie-peer',
        username: 'Charlie',
        network: network,
      );

      const groupId = 'group-quote';
      await alice.createGroup(groupId: groupId, name: 'Quote Group');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);

      alice.start();
      bob.start();
      charlie.start();

      final parent = await alice.sendGroupMessage(
        groupId: groupId,
        text: 'Original group message',
      );
      await pump();

      await bob.sendGroupMessage(
        groupId: groupId,
        text: 'Quoted reply',
        quotedMessageId: parent!.id,
      );
      await pump();

      final aliceMessages = await alice.loadGroupMessages(groupId);
      final aliceReplies = aliceMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(aliceReplies, hasLength(1));
      final aliceReply = aliceReplies.single;
      expect(aliceReply.isIncoming, isTrue);
      expect(aliceReply.quotedMessageId, parent.id);

      final charlieMessages = await charlie.loadGroupMessages(groupId);
      final charlieReplies = charlieMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(charlieReplies, hasLength(1));
      final charlieReply = charlieReplies.single;
      expect(charlieReply.isIncoming, isTrue);
      expect(charlieReply.quotedMessageId, parent.id);

      final bobMessages = await bob.loadGroupMessages(groupId);
      final bobReplies = bobMessages
          .where((message) => message.text == 'Quoted reply')
          .toList();
      expect(bobReplies, hasLength(1));
      final bobReply = bobReplies.single;
      expect(bobReply.isIncoming, isFalse);
      expect(bobReply.quotedMessageId, parent.id);

      alice.dispose();
      bob.dispose();
      charlie.dispose();
    });

    test('message is received after app restart with rejoin', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      const groupId = 'group-post-restart';
      await alice.createGroup(groupId: groupId, name: 'Post Restart');
      await alice.addMember(groupId: groupId, invitee: bob);

      // Store a key for Bob (simulates invite acceptance)
      await bob.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'test-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      alice.start();
      bob.start();

      // Pre-restart: send and verify
      await alice.sendGroupMessage(groupId: groupId, text: 'Before restart');
      await pump();
      expect(
        (await bob.loadGroupMessages(
          groupId,
        )).where((m) => m.isIncoming).length,
        1,
      );

      // -- simulate restart: unsubscribe Bob from network --
      network.unsubscribe(groupId, bob.peerId);

      // -- act: rejoin (calls bridge, re-subscribe on fake network) --
      await rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo);

      // Verify bridge got the correct join command
      final joinCmds = bob.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCmds, hasLength(1));

      final payload = joinCmds.first['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], groupId);
      expect(payload['groupKey'], 'test-key');

      // Verify config contains member publicKeys (critical for Go validator)
      final config = payload['groupConfig'] as Map<String, dynamic>;
      final members = config['members'] as List<dynamic>;
      for (final m in members) {
        expect(
          (m as Map)['publicKey'],
          isNotNull,
          reason: 'publicKey required for Go validator',
        );
      }

      // Re-subscribe on fake network (Go does this in production)
      network.subscribe(groupId, bob.peerId);

      // -- assert: Bob can receive messages after restart --
      await alice.sendGroupMessage(groupId: groupId, text: 'After restart');
      await pump();

      final bobIncoming = (await bob.loadGroupMessages(
        groupId,
      )).where((m) => m.isIncoming).toList();
      expect(bobIncoming, hasLength(2));
      expect(bobIncoming.map((m) => m.text).toSet(), {
        'Before restart',
        'After restart',
      });
      expect(await bob.msgRepo.getMessageCount(groupId), 2);
      expect(await bob.msgRepo.getUnreadCount(groupId), 2);

      final threadSummary = await bob.msgRepo.getGroupThreadSummary(groupId);
      expect(threadSummary.unreadCount, 2);
      expect(threadSummary.latestMessage?.text, 'After restart');

      // -- cleanup --
      alice.dispose();
      bob.dispose();
    });
  });
}
