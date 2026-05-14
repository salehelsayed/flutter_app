import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
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

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    int maxTicks = 40,
  }) async {
    for (var tick = 0; tick < maxTicks; tick++) {
      if (await condition()) return;
      await pump();
    }
    fail('condition was not met within $maxTicks ticks');
  }

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
      'GE-001 A/B/C happy-path private chat smoke delivers every sender exactly once',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge001-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge001-happy-path';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge001-shared-private-chat-key';
        final createdAt = DateTime.utc(2026, 5, 10, 7, 31);
        final sendAt = DateTime.utc(2026, 5, 10, 7, 32);

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-001 Happy Path',
          createdAt: createdAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        final sends = [
          (
            user: alice,
            messageId: 'ge001-alice-message',
            text: 'GE001 from Alice',
          ),
          (user: bob, messageId: 'ge001-bob-message', text: 'GE001 from Bob'),
          (
            user: charlie,
            messageId: 'ge001-charlie-message',
            text: 'GE001 from Charlie',
          ),
        ];

        for (var index = 0; index < sends.length; index++) {
          final send = sends[index];
          final (result, message) = await send.user.sendGroupMessageViaBridge(
            groupId: groupId,
            text: send.text,
            messageId: send.messageId,
            timestamp: sendAt.add(Duration(seconds: index)),
          );

          expect(result.name, 'success', reason: send.messageId);
          expect(message, isNotNull, reason: send.messageId);
          expect(message!.id, send.messageId);
          expect(message.groupId, groupId);
          expect(message.senderPeerId, send.user.peerId);
          expect(message.senderUsername, send.user.username);
          expect(message.keyGeneration, keyEpoch);
          expect(message.text, send.text);
          expect(message.isIncoming, isFalse);
          expect(message.status, 'sent');
          expect(message.inboxStored, isTrue);
          expect(message.inboxRetryPayload, isNull);
          await pump();
        }

        expect(network.publishCallCount, 3);
        expect(network.totalDeliveries, 6);

        Future<void> expectParticipantTimeline(GroupTestUser user) async {
          final messages = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id.startsWith('ge001-')).toList();
          expect(
            messages,
            hasLength(3),
            reason: '${user.username} should have all GE-001 messages',
          );
          expect(messages.map((message) => message.id).toSet(), {
            for (final send in sends) send.messageId,
          });

          final outgoing = messages
              .where((message) => !message.isIncoming)
              .toList();
          final incoming = messages
              .where((message) => message.isIncoming)
              .toList();
          expect(outgoing, hasLength(1), reason: user.username);
          expect(incoming, hasLength(2), reason: user.username);
          expect(
            outgoing.single.senderPeerId,
            user.peerId,
            reason: user.username,
          );

          for (final send in sends.where(
            (send) => send.user.peerId != user.peerId,
          )) {
            final matching = incoming
                .where(
                  (message) =>
                      message.id == send.messageId &&
                      message.text == send.text &&
                      message.senderPeerId == send.user.peerId &&
                      message.senderUsername == send.user.username,
                )
                .toList();
            expect(
              matching,
              hasLength(1),
              reason:
                  '${user.username} should receive ${send.messageId} exactly once',
            );
          }

          expect(
            messages.where(
              (message) =>
                  message.status == 'failed' || message.status == 'pending',
            ),
            isEmpty,
            reason: '${user.username} should have no failed/pending rows',
          );
        }

        await expectParticipantTimeline(alice);
        await expectParticipantTimeline(bob);
        await expectParticipantTimeline(charlie);
      },
    );

    test('GE-002 A removes C and B receives all ten A messages', () async {
      final alice = GroupTestUser.create(
        peerId: 'ge002-alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'ge002-bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'ge002-charlie-peer',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-ge002-remove-c-b-continuity';
      const keyEpoch = 1;
      const sharedEncryptedKey = 'ge002-shared-private-chat-key';
      final createdAt = DateTime.utc(2026, 5, 10, 8);
      final removedAt = createdAt.add(const Duration(minutes: 1));
      final firstSendAt = removedAt.add(const Duration(seconds: 1));

      await alice.createGroup(
        groupId: groupId,
        name: 'GE-002 Removal Continuity',
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

      final group = (await alice.groupRepo.getGroup(groupId))!;
      final members = await alice.groupRepo.getMembers(groupId);

      Future<void> saveParticipantState(
        GroupTestUser user,
        GroupRole role,
      ) async {
        await user.groupRepo.saveGroup(group.copyWith(myRole: role));
        for (final member in members) {
          await user.groupRepo.saveMember(member);
        }
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      await Future.wait([
        saveParticipantState(alice, GroupRole.admin),
        saveParticipantState(bob, GroupRole.member),
        saveParticipantState(charlie, GroupRole.member),
      ]);

      alice.start();
      bob.start();
      charlie.start();

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );

      await waitUntil(() async {
        final bobCharlie = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobCharlie == null && charlieGroup == null;
      });

      expect(network.getSubscribers(groupId).toSet(), {
        alice.peerId,
        bob.peerId,
      });

      List<String> recipientPeerIdsForMessage(String messageId) {
        for (final raw in alice.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope =
              jsonDecode(payload['message'] as String) as Map<String, dynamic>;
          if (replayEnvelope['messageId'] != messageId) continue;
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }
        fail('missing group:inboxStore for $messageId');
      }

      final proofMessages = List.generate(10, (index) {
        final ordinal = (index + 1).toString().padLeft(2, '0');
        return (
          id: 'ge002-alice-post-removal-$ordinal',
          text: 'GE-002 Alice post-removal $ordinal',
          timestamp: firstSendAt.add(Duration(seconds: index)),
        );
      });

      for (final proof in proofMessages) {
        final (result, message) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: proof.text,
          messageId: proof.id,
          timestamp: proof.timestamp,
        );
        expect(result.name, 'success', reason: proof.id);
        expect(message, isNotNull, reason: proof.id);
        expect(message!.id, proof.id);
        expect(message.text, proof.text);
        expect(message.timestamp.toUtc(), proof.timestamp);
        expect(message.senderPeerId, alice.peerId);
        expect(message.senderUsername, alice.username);
        expect(message.keyGeneration, keyEpoch);
        expect(message.isIncoming, isFalse);
        expect(message.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final recipients = recipientPeerIdsForMessage(message.id);
        expect(recipients, <String>[bob.peerId], reason: proof.id);
        expect(recipients, isNot(contains(alice.peerId)));
        expect(recipients, isNot(contains(charlie.peerId)));
        await pump();
      }

      await waitUntil(() async {
        final bobIds = (await bob.loadGroupMessages(
          groupId,
        )).map((message) => message.id).toSet();
        return proofMessages.every((proof) => bobIds.contains(proof.id));
      });

      final bobMessages = await bob.loadGroupMessages(groupId);
      final bobProofMessages = bobMessages
          .where((message) => message.id.startsWith('ge002-alice-'))
          .toList(growable: false);
      expect(bobProofMessages, hasLength(10));
      for (final proof in proofMessages) {
        final matching = bobProofMessages
            .where(
              (message) =>
                  message.id == proof.id &&
                  message.text == proof.text &&
                  message.timestamp.toUtc().isAtSameMomentAs(proof.timestamp) &&
                  message.senderPeerId == alice.peerId &&
                  message.senderUsername == alice.username &&
                  message.keyGeneration == keyEpoch &&
                  message.isIncoming,
            )
            .toList(growable: false);
        expect(
          matching,
          hasLength(1),
          reason: 'Bob should receive ${proof.id} exactly once',
        );
      }

      final charlieMessages = await charlie.loadGroupMessages(groupId);
      final charliePostRemovalMessages = charlieMessages
          .where(
            (message) =>
                message.id.startsWith('ge002-alice-') ||
                proofMessages.any((proof) => proof.text == message.text),
          )
          .toList(growable: false);
      expect(charliePostRemovalMessages, isEmpty);
    });

    test('GE-003 A removes C and A receives all ten B messages', () async {
      final alice = GroupTestUser.create(
        peerId: 'ge003-alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'ge003-bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'ge003-charlie-peer',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-ge003-remove-c-a-continuity';
      const keyEpoch = 1;
      const sharedEncryptedKey = 'ge003-shared-private-chat-key';
      final createdAt = DateTime.utc(2026, 5, 10, 9);
      final removedAt = createdAt.add(const Duration(minutes: 1));
      final firstSendAt = removedAt.add(const Duration(seconds: 1));

      await alice.createGroup(
        groupId: groupId,
        name: 'GE-003 Remaining Pair Continuity',
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

      final group = (await alice.groupRepo.getGroup(groupId))!;
      final members = await alice.groupRepo.getMembers(groupId);

      Future<void> saveParticipantState(
        GroupTestUser user,
        GroupRole role,
      ) async {
        await user.groupRepo.saveGroup(group.copyWith(myRole: role));
        for (final member in members) {
          await user.groupRepo.saveMember(member);
        }
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      await Future.wait([
        saveParticipantState(alice, GroupRole.admin),
        saveParticipantState(bob, GroupRole.member),
        saveParticipantState(charlie, GroupRole.member),
      ]);

      alice.start();
      bob.start();
      charlie.start();

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );

      await waitUntil(() async {
        final bobCharlie = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobCharlie == null && charlieGroup == null;
      });

      expect(network.getSubscribers(groupId).toSet(), {
        alice.peerId,
        bob.peerId,
      });

      List<String> recipientPeerIdsForMessage(String messageId) {
        for (final raw in bob.bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:inboxStore') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          final replayEnvelope =
              jsonDecode(payload['message'] as String) as Map<String, dynamic>;
          if (replayEnvelope['messageId'] != messageId) continue;
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }
        fail('missing group:inboxStore for $messageId');
      }

      final proofMessages = List.generate(10, (index) {
        final ordinal = (index + 1).toString().padLeft(2, '0');
        return (
          id: 'ge003-bob-post-removal-$ordinal',
          text: 'GE-003 Bob post-removal $ordinal',
          timestamp: firstSendAt.add(Duration(seconds: index)),
        );
      });

      for (final proof in proofMessages) {
        final (result, message) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: proof.text,
          messageId: proof.id,
          timestamp: proof.timestamp,
        );
        expect(result.name, 'success', reason: proof.id);
        expect(message, isNotNull, reason: proof.id);
        expect(message!.id, proof.id);
        expect(message.text, proof.text);
        expect(message.timestamp.toUtc(), proof.timestamp);
        expect(message.senderPeerId, bob.peerId);
        expect(message.senderUsername, bob.username);
        expect(message.keyGeneration, keyEpoch);
        expect(message.isIncoming, isFalse);
        expect(message.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final recipients = recipientPeerIdsForMessage(message.id);
        expect(recipients, <String>[alice.peerId], reason: proof.id);
        expect(recipients, isNot(contains(bob.peerId)));
        expect(recipients, isNot(contains(charlie.peerId)));
        await pump();
      }

      await waitUntil(() async {
        final aliceIds = (await alice.loadGroupMessages(
          groupId,
        )).map((message) => message.id).toSet();
        return proofMessages.every((proof) => aliceIds.contains(proof.id));
      });

      final aliceMessages = await alice.loadGroupMessages(groupId);
      final aliceProofMessages = aliceMessages
          .where((message) => message.id.startsWith('ge003-bob-'))
          .toList(growable: false);
      expect(aliceProofMessages, hasLength(10));
      for (final proof in proofMessages) {
        final matching = aliceProofMessages
            .where(
              (message) =>
                  message.id == proof.id &&
                  message.text == proof.text &&
                  message.timestamp.toUtc().isAtSameMomentAs(proof.timestamp) &&
                  message.senderPeerId == bob.peerId &&
                  message.senderUsername == bob.username &&
                  message.keyGeneration == keyEpoch &&
                  message.isIncoming,
            )
            .toList(growable: false);
        expect(
          matching,
          hasLength(1),
          reason: 'Alice should receive ${proof.id} exactly once',
        );
      }

      final charlieMessages = await charlie.loadGroupMessages(groupId);
      final charliePostRemovalMessages = charlieMessages
          .where(
            (message) =>
                message.id.startsWith('ge003-bob-') ||
                proofMessages.any((proof) => proof.text == message.text),
          )
          .toList(growable: false);
      expect(charliePostRemovalMessages, isEmpty);
    });

    test('GE-004 A re-adds C and all three exchange messages', () async {
      final alice = GroupTestUser.create(
        peerId: 'ge004-alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'ge004-bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'ge004-charlie-peer',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-ge004-readd-all-send';
      const keyEpoch = 1;
      const sharedEncryptedKey = 'ge004-shared-private-chat-key';
      final createdAt = DateTime.utc(2026, 5, 10, 10);
      final removedAt = createdAt.add(const Duration(minutes: 1));
      final readdAt = removedAt.add(const Duration(minutes: 1));
      final firstSendAt = readdAt.add(const Duration(seconds: 1));

      await alice.createGroup(
        groupId: groupId,
        name: 'GE-004 Re-add Exchange',
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

      final group = (await alice.groupRepo.getGroup(groupId))!;
      final members = await alice.groupRepo.getMembers(groupId);

      Future<void> saveParticipantState(
        GroupTestUser user,
        GroupRole role,
      ) async {
        await user.groupRepo.saveGroup(group.copyWith(myRole: role));
        for (final member in members) {
          await user.groupRepo.saveMember(member);
        }
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      Future<void> saveParticipantKey(GroupTestUser user) {
        return user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: readdAt,
          ),
        );
      }

      await Future.wait([
        saveParticipantState(alice, GroupRole.admin),
        saveParticipantState(bob, GroupRole.member),
        saveParticipantState(charlie, GroupRole.member),
      ]);

      alice.start();
      bob.start();
      charlie.start();

      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );

      await waitUntil(() async {
        final bobCharlie = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return bobCharlie == null && charlieGroup == null;
      });
      expect(network.getSubscribers(groupId).toSet(), {
        alice.peerId,
        bob.peerId,
      });

      await alice.addMember(
        groupId: groupId,
        invitee: charlie,
        joinedAt: readdAt,
      );
      await Future.wait([
        saveParticipantKey(alice),
        saveParticipantKey(bob),
        saveParticipantKey(charlie),
      ]);
      await alice.broadcastMemberAdded(
        groupId: groupId,
        newMember: charlie,
        eventAt: readdAt,
      );

      await waitUntil(() async {
        final aliceCharlie = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final bobCharlie = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        final charlieGroup = await charlie.groupRepo.getGroup(groupId);
        return aliceCharlie != null &&
            bobCharlie != null &&
            charlieGroup != null;
      });
      expect(network.getSubscribers(groupId).toSet(), {
        alice.peerId,
        bob.peerId,
        charlie.peerId,
      });

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
        fail('missing group:inboxStore for $messageId');
      }

      final sends = [
        (
          user: alice,
          messageId: 'ge004-alice-post-readd',
          text: 'GE-004 Alice post-readd',
          expectedRecipients: {bob.peerId, charlie.peerId},
        ),
        (
          user: bob,
          messageId: 'ge004-bob-post-readd',
          text: 'GE-004 Bob post-readd',
          expectedRecipients: {alice.peerId, charlie.peerId},
        ),
        (
          user: charlie,
          messageId: 'ge004-charlie-post-readd',
          text: 'GE-004 Charlie post-readd',
          expectedRecipients: {alice.peerId, bob.peerId},
        ),
      ];

      for (var index = 0; index < sends.length; index++) {
        final send = sends[index];
        final (result, message) = await send.user.sendGroupMessageViaBridge(
          groupId: groupId,
          text: send.text,
          messageId: send.messageId,
          timestamp: firstSendAt.add(Duration(seconds: index)),
        );
        expect(result.name, 'success', reason: send.messageId);
        expect(message, isNotNull, reason: send.messageId);
        expect(message!.id, send.messageId);
        expect(message.text, send.text);
        expect(message.senderPeerId, send.user.peerId);
        expect(message.senderUsername, send.user.username);
        expect(message.keyGeneration, keyEpoch);
        expect(message.isIncoming, isFalse);
        expect(message.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final recipients = recipientPeerIdsForMessage(send.user, message.id);
        expect(recipients.toSet(), send.expectedRecipients);
        expect(recipients, hasLength(send.expectedRecipients.length));
        expect(recipients, isNot(contains(send.user.peerId)));
        await pump();
      }

      await waitUntil(() async {
        final expectedIds = sends.map((send) => send.messageId).toSet();
        final timelines = await Future.wait([
          alice.loadGroupMessages(groupId),
          bob.loadGroupMessages(groupId),
          charlie.loadGroupMessages(groupId),
        ]);
        return timelines.every((messages) {
          final ids = messages.map((message) => message.id).toSet();
          return expectedIds.difference(ids).isEmpty;
        });
      });

      Future<void> expectParticipantTimeline(GroupTestUser user) async {
        final messages = (await user.loadGroupMessages(
          groupId,
        )).where((message) => message.id.startsWith('ge004-')).toList();
        expect(messages, hasLength(3), reason: user.username);
        expect(messages.map((message) => message.id).toSet(), {
          for (final send in sends) send.messageId,
        });

        final outgoing = messages
            .where((message) => !message.isIncoming)
            .toList();
        final incoming = messages
            .where((message) => message.isIncoming)
            .toList();
        expect(outgoing, hasLength(1), reason: user.username);
        expect(incoming, hasLength(2), reason: user.username);
        expect(outgoing.single.senderPeerId, user.peerId);

        for (final send in sends) {
          final matching = messages
              .where(
                (message) =>
                    message.id == send.messageId &&
                    message.text == send.text &&
                    message.senderPeerId == send.user.peerId &&
                    message.senderUsername == send.user.username &&
                    message.keyGeneration == keyEpoch &&
                    message.isIncoming == (send.user.peerId != user.peerId),
              )
              .toList(growable: false);
          expect(
            matching,
            hasLength(1),
            reason:
                '${user.username} should persist ${send.messageId} exactly once',
          );
        }

        expect(
          messages.where(
            (message) =>
                message.status == 'failed' || message.status == 'pending',
          ),
          isEmpty,
          reason: '${user.username} should have no failed/pending rows',
        );
      }

      await expectParticipantTimeline(alice);
      await expectParticipantTimeline(bob);
      await expectParticipantTimeline(charlie);
    });

    test('GE-005 remove/re-add loop preserves entitlement windows', () async {
      final alice = GroupTestUser.create(
        peerId: 'ge005-alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'ge005-bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'ge005-charlie-peer',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-ge005-remove-readd-loop';
      const keyEpoch = 1;
      const sharedEncryptedKey = 'ge005-shared-private-chat-key';
      const cycleCount = 20;
      final createdAt = DateTime.utc(2026, 5, 10, 11);

      await alice.createGroup(
        groupId: groupId,
        name: 'GE-005 Remove Re-add Loop',
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

      final group = (await alice.groupRepo.getGroup(groupId))!;
      final members = await alice.groupRepo.getMembers(groupId);

      Future<void> saveParticipantState(
        GroupTestUser user,
        GroupRole role,
      ) async {
        await user.groupRepo.saveGroup(group.copyWith(myRole: role));
        for (final member in members) {
          await user.groupRepo.saveMember(member);
        }
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
            createdAt: createdAt,
          ),
        );
      }

      Future<void> saveParticipantKey(GroupTestUser user, DateTime createdAt) {
        return user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: keyEpoch,
            encryptedKey: sharedEncryptedKey,
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
        fail('missing group:inboxStore for $messageId');
      }

      Future<List<dynamic>> loadGe005Messages(GroupTestUser user) async {
        return (await user.msgRepo.getMessagesPage(
          groupId,
          limit: 200,
        )).where((message) => message.id.startsWith('ge005-')).toList();
      }

      await Future.wait([
        saveParticipantState(alice, GroupRole.admin),
        saveParticipantState(bob, GroupRole.member),
        saveParticipantState(charlie, GroupRole.member),
      ]);

      alice.start();
      bob.start();
      charlie.start();

      final removedWindowIds = <String>[];
      final readdWindowIds = <String>[];

      for (var cycle = 1; cycle <= cycleCount; cycle++) {
        final cycleStart = createdAt.add(Duration(minutes: cycle));
        final removedAt = cycleStart;
        final removedMessageAt = removedAt.add(const Duration(seconds: 1));
        final readdAt = removedAt.add(const Duration(seconds: 2));
        final readdMessageAt = readdAt.add(const Duration(seconds: 1));
        final removedMessageId =
            'ge005-cycle-${cycle.toString().padLeft(2, '0')}-removed';
        final readdMessageId =
            'ge005-cycle-${cycle.toString().padLeft(2, '0')}-readd';
        removedWindowIds.add(removedMessageId);
        readdWindowIds.add(readdMessageId);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );

        await waitUntil(() async {
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return bobCharlie == null && charlieGroup == null;
        });
        expect(
          network.getSubscribers(groupId).toSet(),
          {alice.peerId, bob.peerId},
          reason: 'cycle $cycle removal subscribers',
        );

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-005 removed-window cycle $cycle',
              messageId: removedMessageId,
              timestamp: removedMessageAt,
            );
        expect(removedResult.name, 'success', reason: removedMessageId);
        expect(removedMessage, isNotNull, reason: removedMessageId);
        expect(removedMessage!.status, 'sent');
        expect(removedMessage.inboxStored, isTrue);
        expect(removedMessage.inboxRetryPayload, isNull);
        expect(removedMessage.keyGeneration, keyEpoch);
        expect(
          recipientPeerIdsForMessage(alice, removedMessageId).toSet(),
          {bob.peerId},
          reason: '$removedMessageId durable recipients',
        );
        await waitUntil(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == removedMessageId);
        });
        final bobRemovedMatches = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == removedMessageId).toList();
        expect(
          bobRemovedMatches,
          hasLength(1),
          reason: '$removedMessageId Bob exact-once receipt',
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await Future.wait([
          saveParticipantKey(alice, readdAt),
          saveParticipantKey(bob, readdAt),
          saveParticipantKey(charlie, readdAt),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );

        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie != null &&
              bobCharlie != null &&
              charlieGroup != null;
        });
        expect(
          network.getSubscribers(groupId).toSet(),
          {alice.peerId, bob.peerId, charlie.peerId},
          reason: 'cycle $cycle re-add subscribers',
        );

        final (readdResult, readdMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GE-005 readd-window cycle $cycle',
          messageId: readdMessageId,
          timestamp: readdMessageAt,
        );
        expect(readdResult.name, 'success', reason: readdMessageId);
        expect(readdMessage, isNotNull, reason: readdMessageId);
        expect(readdMessage!.status, 'sent');
        expect(readdMessage.inboxStored, isTrue);
        expect(readdMessage.inboxRetryPayload, isNull);
        expect(readdMessage.keyGeneration, keyEpoch);
        expect(
          recipientPeerIdsForMessage(bob, readdMessageId).toSet(),
          {alice.peerId, charlie.peerId},
          reason: '$readdMessageId durable recipients',
        );
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          return aliceMessages.any((message) => message.id == readdMessageId) &&
              charlieMessages.any((message) => message.id == readdMessageId);
        });
        final aliceReaddMatches = (await alice.loadGroupMessages(
          groupId,
        )).where((message) => message.id == readdMessageId).toList();
        final charlieReaddMatches = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.id == readdMessageId).toList();
        expect(
          aliceReaddMatches,
          hasLength(1),
          reason: '$readdMessageId Alice exact-once receipt',
        );
        expect(
          charlieReaddMatches,
          hasLength(1),
          reason: '$readdMessageId Charlie exact-once receipt',
        );

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages
              .where((message) => removedWindowIds.contains(message.id))
              .toList(),
          isEmpty,
          reason: 'cycle $cycle removed-window leakage',
        );
      }

      Future<void> expectMessageSet({
        required GroupTestUser user,
        required Set<String> expectedIds,
        required int outgoingCount,
        required int incomingCount,
      }) async {
        final messages = await loadGe005Messages(user);
        expect(messages, hasLength(expectedIds.length), reason: user.username);
        expect(
          messages.map((message) => message.id).toSet(),
          expectedIds,
          reason: user.username,
        );
        expect(
          messages.where((message) => !message.isIncoming).toList(),
          hasLength(outgoingCount),
          reason: '${user.username} outgoing',
        );
        expect(
          messages.where((message) => message.isIncoming).toList(),
          hasLength(incomingCount),
          reason: '${user.username} incoming',
        );
        expect(
          messages.where(
            (message) =>
                message.status == 'failed' || message.status == 'pending',
          ),
          isEmpty,
          reason: '${user.username} should have no failed/pending rows',
        );
        for (final id in expectedIds) {
          expect(
            messages.where((message) => message.id == id).toList(),
            hasLength(1),
            reason: '${user.username} should persist $id exactly once',
          );
        }
      }

      await expectMessageSet(
        user: alice,
        expectedIds: {...removedWindowIds, ...readdWindowIds},
        outgoingCount: cycleCount,
        incomingCount: cycleCount,
      );
      await expectMessageSet(
        user: bob,
        expectedIds: {...removedWindowIds, ...readdWindowIds},
        outgoingCount: cycleCount,
        incomingCount: cycleCount,
      );
      final finalCharlieMessages = await loadGe005Messages(charlie);
      expect(
        finalCharlieMessages
            .where((message) => removedWindowIds.contains(message.id))
            .toList(),
        isEmpty,
        reason: 'Charlie should never retain removed-window traffic',
      );
      expect(
        finalCharlieMessages.where(
          (message) =>
              message.status == 'failed' || message.status == 'pending',
        ),
        isEmpty,
        reason: 'Charlie should have no failed/pending rows',
      );
    });

    test(
      'GE-006 remove/re-add while C offline catches up post-readd only',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge006-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge006-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge006-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge006-offline-remove-readd';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge006-shared-private-chat-key';
        const removedMessageId = 'ge006-removed-window';
        const alicePostReaddId = 'ge006-alice-post-readd';
        const bobPostReaddId = 'ge006-bob-post-readd';
        const charliePostCatchUpId = 'ge006-charlie-post-catchup';
        final createdAt = DateTime.utc(2026, 5, 10, 12);
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-006 Offline Remove Re-add',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        Map<String, dynamic> relayRecordForMessage({
          required GroupTestUser sender,
          required String messageId,
        }) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          expect(
            (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>(),
            contains(charlie.peerId),
            reason: '$messageId must be durable for offline Charlie',
          );
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<dynamic>> loadGe006Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          )).where((message) => message.id.startsWith('ge006-')).toList();
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        charlie.unsubscribeFromGroup(groupId);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
        });

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobCharlie == null;
        });

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-006 removed-window message',
              messageId: removedMessageId,
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedResult.name, 'success');
        expect(removedMessage, isNotNull);
        expect(removedMessage!.status, 'sent');
        expect(
          recipientPeerIdsForMessage(alice, removedMessageId).toSet(),
          {bob.peerId},
          reason: 'removed-window durable recipients',
        );
        await waitUntil(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == removedMessageId);
        });
        expect(
          (await loadGe006Messages(
            charlie,
          )).where((message) => message.id == removedMessageId).toList(),
          isEmpty,
          reason: 'Charlie is offline and removed during removed-window send',
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        charlie.unsubscribeFromGroup(groupId);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await waitUntil(() async {
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobCharlie != null;
        });
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
        });

        final (alicePostResult, alicePostMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-006 Alice post-readd while Charlie offline',
              messageId: alicePostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 1)),
            );
        expect(alicePostResult.name, 'success');
        expect(alicePostMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, alicePostReaddId).toSet(), {
          bob.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == alicePostReaddId);
        });

        final (bobPostResult, bobPostMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-006 Bob post-readd while Charlie offline',
              messageId: bobPostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 2)),
            );
        expect(bobPostResult.name, 'success');
        expect(bobPostMessage, isNotNull);
        expect(recipientPeerIdsForMessage(bob, bobPostReaddId).toSet(), {
          alice.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          return aliceMessages.any((message) => message.id == bobPostReaddId);
        });

        expect(
          (await loadGe006Messages(charlie))
              .where(
                (message) =>
                    message.id == alicePostReaddId ||
                    message.id == bobPostReaddId,
              )
              .toList(),
          isEmpty,
          reason: 'Charlie has not drained durable replay yet',
        );

        charlie.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            relayRecordForMessage(sender: alice, messageId: alicePostReaddId),
            relayRecordForMessage(sender: bob, messageId: bobPostReaddId),
          ],
          'cursor': '',
        };
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );

        final charlieAfterDrain = await loadGe006Messages(charlie);
        expect(
          charlieAfterDrain
              .where((message) => message.id == removedMessageId)
              .toList(),
          isEmpty,
          reason: 'Charlie must not render removed-window traffic after re-add',
        );
        expect(
          charlieAfterDrain.map((message) => message.id).toSet(),
          {alicePostReaddId, bobPostReaddId},
          reason: 'Charlie should catch up exactly post-readd messages',
        );

        charlie.subscribeToGroup(groupId);
        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-006 Charlie after offline catch-up',
              messageId: charliePostCatchUpId,
              timestamp: readdAt.add(const Duration(seconds: 3)),
            );
        expect(charlieResult.name, 'success');
        expect(charlieMessage, isNotNull);
        expect(
          recipientPeerIdsForMessage(charlie, charliePostCatchUpId).toSet(),
          {alice.peerId, bob.peerId},
        );
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final bobMessages = await bob.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.id == charliePostCatchUpId,
              ) &&
              bobMessages.any((message) => message.id == charliePostCatchUpId);
        });

        Future<void> expectExact(GroupTestUser user, Set<String> ids) async {
          final messages = await loadGe006Messages(user);
          expect(messages.map((message) => message.id).toSet(), ids);
          for (final id in ids) {
            expect(
              messages.where((message) => message.id == id).toList(),
              hasLength(1),
              reason: '${user.username} should persist $id exactly once',
            );
          }
        }

        await expectExact(alice, {
          removedMessageId,
          alicePostReaddId,
          bobPostReaddId,
          charliePostCatchUpId,
        });
        await expectExact(bob, {
          removedMessageId,
          alicePostReaddId,
          bobPostReaddId,
          charliePostCatchUpId,
        });
        await expectExact(charlie, {
          alicePostReaddId,
          bobPostReaddId,
          charliePostCatchUpId,
        });

        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
        }
      },
    );

    test(
      'GE-014 re-added Charlie recovers persisted invite key after restart before topic join',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge014-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge014-bob-peer',
          username: 'Bob',
          network: network,
        );
        var charlie = GroupTestUser.create(
          peerId: 'ge014-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge014-readd-restart-before-topic-join';
        const initialKeyEpoch = 1;
        const removedKeyEpoch = 2;
        const readdKeyEpoch = 3;
        const initialEncryptedKey = 'ge014-initial-key';
        const removedEncryptedKey = 'ge014-removed-window-key';
        const readdEncryptedKey = 'ge014-readd-persisted-key';
        const removedMessageId = 'ge014-removed-window';
        const alicePostReaddId = 'ge014-alice-post-readd';
        const bobPostReaddId = 'ge014-bob-post-readd';
        const charliePostRestartId = 'ge014-charlie-post-restart';
        final createdAt = DateTime.utc(2026, 5, 10, 12);
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-014 Restart Re-add',
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

        final initialGroup = (await alice.groupRepo.getGroup(groupId))!;
        final initialMembers = await alice.groupRepo.getMembers(groupId);

        Future<void> saveInitialState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(initialGroup.copyWith(myRole: role));
          for (final member in initialMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: initialKeyEpoch,
              encryptedKey: initialEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        Map<String, dynamic> relayRecordForMessage({
          required GroupTestUser sender,
          required String messageId,
        }) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          expect(
            (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>(),
            contains(charlie.peerId),
            reason: '$messageId must be durable for restarted Charlie',
          );
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<GroupMessage>> loadGe014Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          )).where((message) => message.id.startsWith('ge014-')).toList();
        }

        Future<void> persistReaddInviteAndKey(
          GroupTestUser user,
          GroupRole role,
          List<GroupMember> remainingMembers,
          GroupMember readdedCharlie,
        ) async {
          final group = (await alice.groupRepo.getGroup(groupId))!;
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in remainingMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveMember(readdedCharlie);
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: readdKeyEpoch,
              encryptedKey: readdEncryptedKey,
              createdAt: readdAt,
            ),
          );
        }

        await Future.wait([
          saveInitialState(alice, GroupRole.admin),
          saveInitialState(bob, GroupRole.member),
          saveInitialState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          return bobCharlie == null;
        });
        await Future.wait([
          alice.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: removedKeyEpoch,
              encryptedKey: removedEncryptedKey,
              createdAt: removedAt,
            ),
          ),
          bob.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: removedKeyEpoch,
              encryptedKey: removedEncryptedKey,
              createdAt: removedAt,
            ),
          ),
        ]);

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-014 removed-window message',
              messageId: removedMessageId,
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedResult.name, 'success');
        expect(removedMessage, isNotNull);
        expect(removedMessage!.keyGeneration, removedKeyEpoch);
        expect(
          recipientPeerIdsForMessage(alice, removedMessageId).toSet(),
          {bob.peerId},
          reason: 'removed-window durable recipients exclude Charlie',
        );
        await waitUntil(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == removedMessageId);
        });
        expect(
          (await loadGe014Messages(
            charlie,
          )).where((message) => message.id == removedMessageId),
          isEmpty,
          reason: 'Charlie must not persist removed-window plaintext',
        );

        final remainingMembers = await alice.groupRepo.getMembers(groupId);
        final readdedCharlie = GroupMember(
          groupId: groupId,
          peerId: charlie.peerId,
          username: charlie.username,
          role: MemberRole.writer,
          permissions: GroupMemberPermissions.empty,
          publicKey: charlie.publicKey,
          mlKemPublicKey: 'mlkem-${charlie.peerId}',
          devices: [charlie.deviceIdentity],
          joinedAt: readdAt,
        );
        await Future.wait([
          persistReaddInviteAndKey(
            alice,
            GroupRole.admin,
            remainingMembers,
            readdedCharlie,
          ),
          persistReaddInviteAndKey(
            bob,
            GroupRole.member,
            remainingMembers,
            readdedCharlie,
          ),
          persistReaddInviteAndKey(
            charlie,
            GroupRole.member,
            remainingMembers,
            readdedCharlie,
          ),
        ]);
        charlie.unsubscribeFromGroup(groupId);

        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))?.keyGeneration,
          readdKeyEpoch,
          reason: 'Charlie persisted the re-add key before restart',
        );
        expect(
          network.getSubscribers(groupId).toSet(),
          {alice.peerId, bob.peerId},
          reason: 'Charlie has persisted invite/key but has not joined topic',
        );

        charlie = charlie.restartWithPersistedState();
        charlie.start();
        expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))?.keyGeneration,
          readdKeyEpoch,
          reason: 'Charlie recovered persisted re-add key after restart',
        );
        expect(
          network.getSubscribers(groupId).toSet(),
          {alice.peerId, bob.peerId},
          reason: 'restart occurs before Charlie topic join',
        );

        final (alicePostResult, alicePostMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-014 Alice post-readd while Charlie restarted',
              messageId: alicePostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 1)),
            );
        expect(alicePostResult.name, 'success');
        expect(alicePostMessage, isNotNull);
        expect(alicePostMessage!.keyGeneration, readdKeyEpoch);
        expect(recipientPeerIdsForMessage(alice, alicePostReaddId).toSet(), {
          bob.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final bobMessages = await bob.loadGroupMessages(groupId);
          return bobMessages.any((message) => message.id == alicePostReaddId);
        });

        final (bobPostResult, bobPostMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-014 Bob post-readd while Charlie restarted',
              messageId: bobPostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 2)),
            );
        expect(bobPostResult.name, 'success');
        expect(bobPostMessage, isNotNull);
        expect(bobPostMessage!.keyGeneration, readdKeyEpoch);
        expect(recipientPeerIdsForMessage(bob, bobPostReaddId).toSet(), {
          alice.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          return aliceMessages.any((message) => message.id == bobPostReaddId);
        });

        expect(
          (await loadGe014Messages(charlie))
              .where(
                (message) =>
                    message.id == alicePostReaddId ||
                    message.id == bobPostReaddId,
              )
              .toList(),
          isEmpty,
          reason: 'Charlie has not joined topic or drained replay yet',
        );

        charlie.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            relayRecordForMessage(sender: alice, messageId: alicePostReaddId),
            relayRecordForMessage(sender: bob, messageId: bobPostReaddId),
          ],
          'cursor': '',
        };
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );

        final charlieAfterDrain = await loadGe014Messages(charlie);
        expect(
          charlieAfterDrain
              .where((message) => message.id == removedMessageId)
              .toList(),
          isEmpty,
          reason: 'Charlie must not recover removed-window plaintext',
        );
        expect(
          charlieAfterDrain.map((message) => message.id).toSet(),
          {alicePostReaddId, bobPostReaddId},
          reason: 'Charlie retrieves exactly post-readd messages after restart',
        );

        charlie.subscribeToGroup(groupId);
        final (charlieResult, charlieMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-014 Charlie after restart recovery',
              messageId: charliePostRestartId,
              timestamp: readdAt.add(const Duration(seconds: 3)),
            );
        expect(charlieResult.name, 'success');
        expect(charlieMessage, isNotNull);
        expect(charlieMessage!.keyGeneration, readdKeyEpoch);
        expect(
          recipientPeerIdsForMessage(charlie, charliePostRestartId).toSet(),
          {alice.peerId, bob.peerId},
        );
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final bobMessages = await bob.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.id == charliePostRestartId,
              ) &&
              bobMessages.any((message) => message.id == charliePostRestartId);
        });

        Future<void> expectExact(GroupTestUser user, Set<String> ids) async {
          final messages = await loadGe014Messages(user);
          expect(messages.map((message) => message.id).toSet(), ids);
          for (final id in ids) {
            expect(
              messages.where((message) => message.id == id).toList(),
              hasLength(1),
              reason: '${user.username} should persist $id exactly once',
            );
          }
        }

        await expectExact(alice, {
          removedMessageId,
          alicePostReaddId,
          bobPostReaddId,
          charliePostRestartId,
        });
        await expectExact(bob, {
          removedMessageId,
          alicePostReaddId,
          bobPostReaddId,
          charliePostRestartId,
        });
        await expectExact(charlie, {
          alicePostReaddId,
          bobPostReaddId,
          charliePostRestartId,
        });

        for (final user in [alice, bob, charlie]) {
          expect(
            (await user.groupRepo.getLatestKey(groupId))?.keyGeneration,
            3,
          );
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
        }
      },
    );

    test(
      'GE-015 admin restart during add/remove repairs fanout honestly',
      () async {
        var alice = GroupTestUser.create(
          peerId: 'ge015-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge015-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge015-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final inviteStatusRepo =
            _InMemoryGroupInviteDeliveryAttemptRepository();
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge015-admin-restart-during-mutation';
        const initialKeyEpoch = 1;
        const removedKeyEpoch = 2;
        const readdKeyEpoch = 3;
        const initialEncryptedKey = 'ge015-initial-key';
        const removedEncryptedKey = 'ge015-removed-key';
        const readdEncryptedKey = 'ge015-readd-key';
        const aliceRemovedWindowId = 'ge015-alice-removed-window';
        const bobAfterRepairId = 'ge015-bob-after-remove-repair';
        const charlieAfterRepairId = 'ge015-charlie-after-add-repair';
        final createdAt = DateTime.utc(2026, 5, 13, 12);
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-015 Admin Restart',
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

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
          DateTime created,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: created,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        Set<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          return ((latestInboxPayloadForMessage(
                        sender,
                        messageId,
                      )['recipientPeerIds']
                      as List<dynamic>? ??
                  const <dynamic>[]))
              .cast<String>()
              .toSet();
        }

        Future<List<GroupMessage>> loadGe015Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          )).where((message) => message.id.startsWith('ge015-')).toList();
        }

        Future<void> expectMembers(
          GroupTestUser user,
          Set<String> expectedPeerIds,
        ) async {
          expect(
            (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet(),
            expectedPeerIds,
            reason: '${user.username} membership',
          );
        }

        await Future.wait([
          saveKey(alice, initialKeyEpoch, initialEncryptedKey, createdAt),
          saveKey(bob, initialKeyEpoch, initialEncryptedKey, createdAt),
          saveKey(charlie, initialKeyEpoch, initialEncryptedKey, createdAt),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          return await bob.groupRepo.getMember(groupId, charlie.peerId) == null;
        });

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': removedEncryptedKey,
          'keyEpoch': removedKeyEpoch,
        };
        final interruptedRemoveTargets = <String>[];
        final interruptedRemoveRepair = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            interruptedRemoveTargets.add(peerId);
            return false;
          },
          distributionAttemptCount: 1,
          distributionRetryDelay: Duration.zero,
          perRecipientTimeout: const Duration(milliseconds: 10),
          distributionTimeout: const Duration(milliseconds: 50),
        );
        expect(interruptedRemoveRepair, isNull);
        expect(interruptedRemoveTargets.toSet(), {bob.peerId});
        expect(
          alice.bridge.commandLog.where((cmd) => cmd == 'group:updateKey'),
          isEmpty,
          reason: 'failed fanout must not promote Alice to a fake sent epoch',
        );
        expect(
          (await alice.groupRepo.getLatestKey(groupId))?.keyGeneration,
          initialKeyEpoch,
          reason: 'interrupted remove fanout remains visibly unrepaired',
        );

        alice = alice.restartWithPersistedState();
        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': removedEncryptedKey,
          'keyEpoch': removedKeyEpoch,
        };
        alice.start();
        alice.subscribeToGroup(groupId);

        final repairedRemoveTargets = <String>[];
        final repairedRemoveKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            repairedRemoveTargets.add(peerId);
            return true;
          },
          distributionAttemptCount: 1,
          distributionRetryDelay: Duration.zero,
        );
        expect(repairedRemoveKey, isNotNull);
        expect(repairedRemoveKey!.keyGeneration, removedKeyEpoch);
        expect(repairedRemoveTargets.toSet(), {bob.peerId});
        expect(repairedRemoveTargets, isNot(contains(charlie.peerId)));
        await saveKey(bob, removedKeyEpoch, removedEncryptedKey, removedAt);

        final (removedWindowResult, removedWindowMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-015 removed-window after admin repair',
              messageId: aliceRemovedWindowId,
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedWindowResult.name, 'success');
        expect(removedWindowMessage, isNotNull);
        expect(removedWindowMessage!.keyGeneration, removedKeyEpoch);
        expect(recipientPeerIdsForMessage(alice, aliceRemovedWindowId), {
          bob.peerId,
        });

        final (bobAfterRepairResult, bobAfterRepairMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-015 Bob after remove repair',
              messageId: bobAfterRepairId,
              timestamp: removedAt.add(const Duration(seconds: 2)),
            );
        expect(bobAfterRepairResult.name, 'success');
        expect(bobAfterRepairMessage, isNotNull);
        expect(bobAfterRepairMessage!.keyGeneration, removedKeyEpoch);
        expect(recipientPeerIdsForMessage(bob, bobAfterRepairId), {
          alice.peerId,
        });
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final bobMessages = await bob.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.id == bobAfterRepairId,
              ) &&
              bobMessages.any((message) => message.id == aliceRemovedWindowId);
        });
        expect(
          (await loadGe015Messages(
            charlie,
          )).where((message) => message.id == aliceRemovedWindowId),
          isEmpty,
          reason: 'removed Charlie must not receive post-removal plaintext',
        );
        await expectMembers(alice, {alice.peerId, bob.peerId});
        await expectMembers(bob, {alice.peerId, bob.peerId});

        final remainingMembers = await alice.groupRepo.getMembers(groupId);
        final readdedCharlie = GroupMember(
          groupId: groupId,
          peerId: charlie.peerId,
          username: charlie.username,
          role: MemberRole.writer,
          permissions: GroupMemberPermissions.empty,
          publicKey: charlie.publicKey,
          mlKemPublicKey: 'mlkem-${charlie.peerId}',
          devices: [charlie.deviceIdentity],
          joinedAt: readdAt,
        );
        await Future.wait([
          alice.groupRepo.saveMember(readdedCharlie),
          bob.groupRepo.saveMember(readdedCharlie),
        ]);
        await recordPendingGroupInviteFanoutAttempts(
          inviteDeliveryAttemptRepo: inviteStatusRepo,
          groupId: groupId,
          members: [readdedCharlie],
          now: readdAt,
        );

        alice = alice.restartWithPersistedState();
        alice.start();
        alice.subscribeToGroup(groupId);

        final pendingInvite = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: charlie.peerId,
        );
        expect(pendingInvite, isNotNull);
        expect(pendingInvite!.status, GroupInviteDeliveryStatus.needsResend);
        expect(
          pendingInvite.lastError,
          'invite_fanout_pending_after_membership_update',
          reason: 'admin restart retains honest invite fanout status',
        );

        await recordGroupInviteDeliveryBatch(
          inviteDeliveryAttemptRepo: inviteStatusRepo,
          groupId: groupId,
          attempts: [
            GroupInviteAttempt(
              peerId: charlie.peerId,
              username: charlie.username,
              result: SendGroupInviteResult.success,
            ),
          ],
          now: readdAt.add(const Duration(seconds: 1)),
        );
        final repairedInvite = await inviteStatusRepo.getAttempt(
          groupId: groupId,
          peerId: charlie.peerId,
        );
        expect(repairedInvite?.status, GroupInviteDeliveryStatus.sent);

        final group = (await alice.groupRepo.getGroup(groupId))!;
        await charlie.groupRepo.saveGroup(
          group.copyWith(myRole: GroupRole.member),
        );
        for (final member in [...remainingMembers, readdedCharlie]) {
          await charlie.groupRepo.saveMember(member);
        }
        await Future.wait([
          saveKey(alice, readdKeyEpoch, readdEncryptedKey, readdAt),
          saveKey(bob, readdKeyEpoch, readdEncryptedKey, readdAt),
          saveKey(charlie, readdKeyEpoch, readdEncryptedKey, readdAt),
        ]);
        charlie.subscribeToGroup(groupId);

        final (
          charlieAfterRepairResult,
          charlieAfterRepairMessage,
        ) = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GE-015 Charlie after repaired invite fanout',
          messageId: charlieAfterRepairId,
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        expect(charlieAfterRepairResult.name, 'success');
        expect(charlieAfterRepairMessage, isNotNull);
        expect(charlieAfterRepairMessage!.keyGeneration, readdKeyEpoch);
        expect(recipientPeerIdsForMessage(charlie, charlieAfterRepairId), {
          alice.peerId,
          bob.peerId,
        });
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final bobMessages = await bob.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.id == charlieAfterRepairId,
              ) &&
              bobMessages.any((message) => message.id == charlieAfterRepairId);
        });

        await expectMembers(alice, {alice.peerId, bob.peerId, charlie.peerId});
        await expectMembers(bob, {alice.peerId, bob.peerId, charlie.peerId});
        await expectMembers(charlie, {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
      },
    );

    test(
      'GE-007 remove/re-add while B offline observer catches up entitled messages',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge007-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge007-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge007-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge007-offline-observer';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge007-shared-private-chat-key';
        const removedMessageId = 'ge007-removed-window';
        const alicePostReaddId = 'ge007-alice-post-readd';
        const charliePostReaddId = 'ge007-charlie-post-readd';
        const bobPostCatchUpId = 'ge007-bob-post-catchup';
        final createdAt = DateTime.utc(2026, 5, 10, 13);
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-007 Offline Observer Re-add',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        Map<String, dynamic> relayRecordForMessage({
          required GroupTestUser sender,
          required String messageId,
        }) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          expect(
            (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>(),
            contains(bob.peerId),
            reason: '$messageId must be durable for offline Bob',
          );
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<GroupMessage>> loadGe007Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          )).where((message) => message.id.startsWith('ge007-')).toList();
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        bob.unsubscribeFromGroup(groupId);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          charlie.peerId,
        });

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie == null && charlieGroup == null;
        });

        final (removedResult, removedMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-007 removed-window for offline Bob',
              messageId: removedMessageId,
              timestamp: removedAt.add(const Duration(seconds: 1)),
            );
        expect(removedResult.name, anyOf('success', 'successNoPeers'));
        expect(removedMessage, isNotNull);
        expect(
          recipientPeerIdsForMessage(alice, removedMessageId).toSet(),
          {bob.peerId},
          reason: 'removed-window durable recipients',
        );
        expect(
          (await loadGe007Messages(
            bob,
          )).where((message) => message.id == removedMessageId).toList(),
          isEmpty,
          reason: 'Bob is offline until replay drain',
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie != null && charlieGroup != null;
        });
        final readdKey = await alice.groupRepo.getLatestKey(groupId);
        expect(readdKey, isNotNull);
        await charlie.groupRepo.saveKey(readdKey!);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          charlie.peerId,
        });

        final (alicePostResult, alicePostMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-007 Alice post-readd while Bob offline',
              messageId: alicePostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 1)),
            );
        expect(alicePostResult.name, 'success');
        expect(alicePostMessage, isNotNull);
        expect(recipientPeerIdsForMessage(alice, alicePostReaddId).toSet(), {
          bob.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          return charlieMessages.any(
            (message) => message.id == alicePostReaddId,
          );
        });

        final (charliePostResult, charliePostMessage) = await charlie
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-007 Charlie post-readd while Bob offline',
              messageId: charliePostReaddId,
              timestamp: readdAt.add(const Duration(seconds: 2)),
            );
        expect(charliePostResult.name, 'success');
        expect(charliePostMessage, isNotNull);
        expect(
          recipientPeerIdsForMessage(charlie, charliePostReaddId).toSet(),
          {alice.peerId, bob.peerId},
        );
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          return aliceMessages.any(
            (message) => message.id == charliePostReaddId,
          );
        });

        expect(
          (await loadGe007Messages(bob))
              .where(
                (message) =>
                    message.id == removedMessageId ||
                    message.id == alicePostReaddId ||
                    message.id == charliePostReaddId,
              )
              .toList(),
          isEmpty,
          reason: 'Bob has not drained durable replay yet',
        );

        bob.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            relayRecordForMessage(sender: alice, messageId: removedMessageId),
            relayRecordForMessage(sender: alice, messageId: alicePostReaddId),
            relayRecordForMessage(
              sender: charlie,
              messageId: charliePostReaddId,
            ),
          ],
          'cursor': '',
        };
        await drainGroupOfflineInboxForGroup(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          groupMessageListener: bob.groupMessageListener,
          selfPeerId: bob.peerId,
        );

        final bobAfterDrain = await loadGe007Messages(bob);
        expect(
          bobAfterDrain.map((message) => message.id).toSet(),
          {removedMessageId, alicePostReaddId, charliePostReaddId},
          reason: 'Bob should catch up every entitled offline message',
        );

        bob.subscribeToGroup(groupId);
        final (bobResult, bobMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GE-007 Bob after observer catch-up',
          messageId: bobPostCatchUpId,
          timestamp: readdAt.add(const Duration(seconds: 3)),
        );
        expect(bobResult.name, 'success');
        expect(bobMessage, isNotNull);
        expect(recipientPeerIdsForMessage(bob, bobPostCatchUpId).toSet(), {
          alice.peerId,
          charlie.peerId,
        });
        await waitUntil(() async {
          final aliceMessages = await alice.loadGroupMessages(groupId);
          final charlieMessages = await charlie.loadGroupMessages(groupId);
          return aliceMessages.any(
                (message) => message.id == bobPostCatchUpId,
              ) &&
              charlieMessages.any((message) => message.id == bobPostCatchUpId);
        });

        Future<void> expectExact(GroupTestUser user, Set<String> ids) async {
          final messages = await loadGe007Messages(user);
          expect(messages.map((message) => message.id).toSet(), ids);
          for (final id in ids) {
            expect(
              messages.where((message) => message.id == id).toList(),
              hasLength(1),
              reason: '${user.username} should persist $id exactly once',
            );
          }
        }

        await expectExact(alice, {
          removedMessageId,
          alicePostReaddId,
          charliePostReaddId,
          bobPostCatchUpId,
        });
        await expectExact(bob, {
          removedMessageId,
          alicePostReaddId,
          charliePostReaddId,
          bobPostCatchUpId,
        });
        await expectExact(charlie, {
          alicePostReaddId,
          charliePostReaddId,
          bobPostCatchUpId,
        });

        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
        }
      },
    );

    test(
      'GE-008 simultaneous send storm during remove/re-add keeps entitlement windows exact',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge008-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge008-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge008-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge008-send-storm-remove-readd';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge008-shared-private-chat-key';
        const stormCount = 4;
        final createdAt = DateTime.utc(2026, 5, 10, 14);
        final preStormAt = createdAt.add(const Duration(seconds: 10));
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));
        final preIds = <String>{};
        final removedIds = <String>{};
        final postIds = <String>{};
        final staleAttemptIds = <String>{};

        network.duplicateOnDeliver = true;

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-008 Send Storm Remove Re-add',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        Future<List<GroupMessage>> loadGe008Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 200,
          )).where((message) => message.id.startsWith('ge008-')).toList();
        }

        Future<void> sendStormMessage({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required DateTime timestamp,
          required Set<String> durableRecipients,
        }) async {
          final (result, message) = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(result.name, 'success', reason: messageId);
          expect(message, isNotNull, reason: messageId);
          expect(
            recipientPeerIdsForMessage(sender, messageId).toSet(),
            durableRecipients,
            reason: 'durable recipients for $messageId',
          );
        }

        Future<void> expectCharlieStaleSendRejected({
          required String messageId,
          required DateTime timestamp,
        }) async {
          final priorSentCount = charlie.bridge.sentMessages.length;
          final (result, message) = await charlie.sendGroupMessageViaBridge(
            groupId: groupId,
            text: 'GE-008 Charlie stale removed-window $messageId',
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(
            result.name,
            anyOf('groupNotFound', 'unauthorized'),
            reason: messageId,
          );
          expect(message, isNull, reason: messageId);
          expect(
            charlie.bridge.sentMessages
                .skip(priorSentCount)
                .where((raw) => raw.contains(messageId)),
            isEmpty,
            reason: 'stale removed Charlie send must not publish',
          );
        }

        Future<void> waitForIds(
          GroupTestUser user,
          Set<String> expectedIds,
        ) async {
          await waitUntil(() async {
            final actualIds = (await loadGe008Messages(
              user,
            )).map((message) => message.id).toSet();
            return expectedIds.difference(actualIds).isEmpty;
          }, maxTicks: 80);
        }

        Future<void> expectExactIds(
          GroupTestUser user,
          Set<String> expectedIds,
        ) async {
          final messages = await loadGe008Messages(user);
          expect(
            messages.map((message) => message.id).toSet(),
            expectedIds,
            reason: user.username,
          );
          for (final id in expectedIds) {
            expect(
              messages.where((message) => message.id == id).toList(),
              hasLength(1),
              reason: '${user.username} should persist $id exactly once',
            );
          }
          expect(
            messages.where(
              (message) =>
                  staleAttemptIds.contains(message.id) ||
                  (user.peerId == charlie.peerId &&
                      removedIds.contains(message.id)),
            ),
            isEmpty,
            reason: '${user.username} should not render removed-window leaks',
          );
          expect(
            messages.where(
              (message) =>
                  message.status == 'failed' || message.status == 'pending',
            ),
            isEmpty,
            reason:
                '${user.username} should have no failed/pending GE-008 rows',
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        for (var index = 0; index < stormCount; index++) {
          final suffix = index.toString().padLeft(2, '0');
          final aliceId = 'ge008-pre-alice-$suffix';
          final bobId = 'ge008-pre-bob-$suffix';
          final charlieId = 'ge008-pre-charlie-$suffix';
          preIds.addAll([aliceId, bobId, charlieId]);
          await Future.wait([
            sendStormMessage(
              sender: alice,
              messageId: aliceId,
              text: 'GE-008 pre-removal Alice $suffix',
              timestamp: preStormAt.add(Duration(milliseconds: index * 10)),
              durableRecipients: {bob.peerId, charlie.peerId},
            ),
            sendStormMessage(
              sender: bob,
              messageId: bobId,
              text: 'GE-008 pre-removal Bob $suffix',
              timestamp: preStormAt.add(Duration(milliseconds: index * 10 + 1)),
              durableRecipients: {alice.peerId, charlie.peerId},
            ),
            sendStormMessage(
              sender: charlie,
              messageId: charlieId,
              text: 'GE-008 pre-removal Charlie $suffix',
              timestamp: preStormAt.add(Duration(milliseconds: index * 10 + 2)),
              durableRecipients: {alice.peerId, bob.peerId},
            ),
          ]);
        }

        await Future.wait([
          waitForIds(alice, preIds),
          waitForIds(bob, preIds),
          waitForIds(charlie, preIds),
        ]);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie == null &&
              bobCharlie == null &&
              charlieGroup == null &&
              !network.isSubscribed(groupId, charlie.peerId);
        });

        for (var index = 0; index < stormCount; index++) {
          final suffix = index.toString().padLeft(2, '0');
          final aliceId = 'ge008-removed-alice-$suffix';
          final bobId = 'ge008-removed-bob-$suffix';
          final staleId = 'ge008-removed-charlie-stale-$suffix';
          removedIds.addAll([aliceId, bobId]);
          staleAttemptIds.add(staleId);
          await Future.wait([
            sendStormMessage(
              sender: alice,
              messageId: aliceId,
              text: 'GE-008 removed-window Alice $suffix',
              timestamp: removedAt.add(Duration(milliseconds: index * 10)),
              durableRecipients: {bob.peerId},
            ),
            sendStormMessage(
              sender: bob,
              messageId: bobId,
              text: 'GE-008 removed-window Bob $suffix',
              timestamp: removedAt.add(Duration(milliseconds: index * 10 + 1)),
              durableRecipients: {alice.peerId},
            ),
            expectCharlieStaleSendRejected(
              messageId: staleId,
              timestamp: removedAt.add(Duration(milliseconds: index * 10 + 2)),
            ),
          ]);
        }

        await Future.wait([
          waitForIds(alice, removedIds),
          waitForIds(bob, removedIds),
        ]);

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie != null &&
              bobCharlie != null &&
              charlieGroup != null &&
              network.isSubscribed(groupId, charlie.peerId);
        });
        final readdKey = await alice.groupRepo.getLatestKey(groupId);
        expect(readdKey, isNotNull);
        await charlie.groupRepo.saveKey(readdKey!);

        for (var index = 0; index < stormCount; index++) {
          final suffix = index.toString().padLeft(2, '0');
          final aliceId = 'ge008-post-alice-$suffix';
          final bobId = 'ge008-post-bob-$suffix';
          final charlieId = 'ge008-post-charlie-$suffix';
          postIds.addAll([aliceId, bobId, charlieId]);
          await Future.wait([
            sendStormMessage(
              sender: alice,
              messageId: aliceId,
              text: 'GE-008 post-readd Alice $suffix',
              timestamp: readdAt.add(Duration(milliseconds: index * 10)),
              durableRecipients: {bob.peerId, charlie.peerId},
            ),
            sendStormMessage(
              sender: bob,
              messageId: bobId,
              text: 'GE-008 post-readd Bob $suffix',
              timestamp: readdAt.add(Duration(milliseconds: index * 10 + 1)),
              durableRecipients: {alice.peerId, charlie.peerId},
            ),
            sendStormMessage(
              sender: charlie,
              messageId: charlieId,
              text: 'GE-008 post-readd Charlie $suffix',
              timestamp: readdAt.add(Duration(milliseconds: index * 10 + 2)),
              durableRecipients: {alice.peerId, bob.peerId},
            ),
          ]);
        }

        await Future.wait([
          waitForIds(alice, postIds),
          waitForIds(bob, postIds),
          waitForIds(charlie, postIds),
        ]);

        final expectedStableMemberIds = {...preIds, ...removedIds, ...postIds};
        await expectExactIds(alice, expectedStableMemberIds);
        await expectExactIds(bob, expectedStableMemberIds);
        await expectExactIds(charlie, {...preIds, ...postIds});

        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
        }
      },
    );

    test(
      'GE-009 network partition heals after membership mutation and replay converges',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge009-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge009-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge009-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge009-partition-heal-after-mutation';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge009-shared-private-chat-key';
        const alicePreId = 'ge009-pre-alice';
        const bobPreId = 'ge009-pre-bob';
        const charliePreId = 'ge009-pre-charlie';
        const alicePostReaddId = 'ge009-post-readd-alice';
        const bobPostReaddId = 'ge009-post-readd-bob';
        const charlieHealedId = 'ge009-healed-charlie';
        final createdAt = DateTime.utc(2026, 5, 10, 15);
        final partitionedAt = createdAt.add(const Duration(minutes: 1));
        final removedAt = partitionedAt.add(const Duration(seconds: 10));
        final readdAt = removedAt.add(const Duration(minutes: 1));
        final healedAt = readdAt.add(const Duration(minutes: 1));
        final preIds = {alicePreId, bobPreId, charliePreId};
        final replayIds = {alicePostReaddId, bobPostReaddId};
        final finalIds = {...preIds, ...replayIds, charlieHealedId};

        await alice.createGroup(
          groupId: groupId,
          name: 'GE-009 Partition Heal After Mutation',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        Map<String, dynamic> latestInboxPayloadForMessage(
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
          fail('missing group:inboxStore for $messageId');
        }

        List<String> recipientPeerIdsForMessage(
          GroupTestUser sender,
          String messageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          return (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
              .cast<String>();
        }

        Map<String, dynamic> relayRecordForMessage({
          required GroupTestUser sender,
          required String messageId,
        }) {
          final payload = latestInboxPayloadForMessage(sender, messageId);
          expect(
            (payload['recipientPeerIds'] as List<dynamic>? ?? const [])
                .cast<String>(),
            contains(charlie.peerId),
            reason: '$messageId must be durable for partitioned Charlie',
          );
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<GroupMessage>> loadGe009Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 100,
          )).where((message) => message.id.startsWith('ge009-')).toList();
        }

        Future<void> sendProofMessage({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required DateTime timestamp,
          required Set<String> durableRecipients,
        }) async {
          final (result, message) = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(result.name, 'success', reason: messageId);
          expect(message, isNotNull, reason: messageId);
          expect(
            recipientPeerIdsForMessage(sender, messageId).toSet(),
            durableRecipients,
            reason: 'durable recipients for $messageId',
          );
        }

        Future<void> waitForIds(
          GroupTestUser user,
          Set<String> expectedIds,
        ) async {
          await waitUntil(() async {
            final actualIds = (await loadGe009Messages(
              user,
            )).map((message) => message.id).toSet();
            return expectedIds.difference(actualIds).isEmpty;
          }, maxTicks: 80);
        }

        Future<void> expectExactConverged(
          GroupTestUser user,
          Set<String> expectedIds,
        ) async {
          final messages = await loadGe009Messages(user);
          expect(
            messages.map((message) => message.id).toSet(),
            expectedIds,
            reason: user.username,
          );
          for (final id in expectedIds) {
            expect(
              messages.where((message) => message.id == id).toList(),
              hasLength(1),
              reason: '${user.username} should persist $id exactly once',
            );
          }
          expect(
            messages.where(
              (message) =>
                  message.status == 'failed' || message.status == 'pending',
            ),
            isEmpty,
            reason:
                '${user.username} should have no failed/pending GE-009 rows',
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        await sendProofMessage(
          sender: alice,
          messageId: alicePreId,
          text: 'GE-009 pre-partition Alice',
          timestamp: createdAt.add(const Duration(seconds: 10)),
          durableRecipients: {bob.peerId, charlie.peerId},
        );
        await sendProofMessage(
          sender: bob,
          messageId: bobPreId,
          text: 'GE-009 pre-partition Bob',
          timestamp: createdAt.add(const Duration(seconds: 11)),
          durableRecipients: {alice.peerId, charlie.peerId},
        );
        await sendProofMessage(
          sender: charlie,
          messageId: charliePreId,
          text: 'GE-009 pre-partition Charlie',
          timestamp: createdAt.add(const Duration(seconds: 12)),
          durableRecipients: {alice.peerId, bob.peerId},
        );
        await Future.wait([
          waitForIds(alice, preIds),
          waitForIds(bob, preIds),
          waitForIds(charlie, preIds),
        ]);

        charlie.unsubscribeFromGroup(groupId);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
        });

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie == null &&
              bobCharlie == null &&
              charlieGroup != null &&
              !network.isSubscribed(groupId, charlie.peerId);
        });

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        charlie.unsubscribeFromGroup(groupId);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await waitUntil(() async {
          final aliceCharlie = await alice.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final bobCharlie = await bob.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieGroup = await charlie.groupRepo.getGroup(groupId);
          return aliceCharlie != null &&
              bobCharlie != null &&
              charlieGroup != null &&
              !network.isSubscribed(groupId, charlie.peerId);
        });
        final latestKey = await alice.groupRepo.getLatestKey(groupId);
        expect(latestKey, isNotNull);
        await charlie.groupRepo.saveKey(latestKey!);

        await sendProofMessage(
          sender: alice,
          messageId: alicePostReaddId,
          text: 'GE-009 Alice post-readd while Charlie partitioned',
          timestamp: readdAt.add(const Duration(seconds: 1)),
          durableRecipients: {bob.peerId, charlie.peerId},
        );
        await waitForIds(alice, {...preIds, alicePostReaddId});
        await waitForIds(bob, {...preIds, alicePostReaddId});

        await sendProofMessage(
          sender: bob,
          messageId: bobPostReaddId,
          text: 'GE-009 Bob post-readd while Charlie partitioned',
          timestamp: readdAt.add(const Duration(seconds: 2)),
          durableRecipients: {alice.peerId, charlie.peerId},
        );
        await waitForIds(alice, {...preIds, ...replayIds});
        await waitForIds(bob, {...preIds, ...replayIds});
        expect(
          (await loadGe009Messages(
            charlie,
          )).where((message) => replayIds.contains(message.id)).toList(),
          isEmpty,
          reason: 'Charlie must not receive partition-window messages live',
        );

        charlie.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            relayRecordForMessage(sender: alice, messageId: alicePostReaddId),
            relayRecordForMessage(sender: bob, messageId: bobPostReaddId),
          ],
          'cursor': '',
        };
        charlie.subscribeToGroup(groupId);
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );
        await waitForIds(charlie, {...preIds, ...replayIds});

        await sendProofMessage(
          sender: charlie,
          messageId: charlieHealedId,
          text: 'GE-009 Charlie after partition heal',
          timestamp: healedAt,
          durableRecipients: {alice.peerId, bob.peerId},
        );
        await Future.wait([
          waitForIds(alice, finalIds),
          waitForIds(bob, finalIds),
          waitForIds(charlie, finalIds),
        ]);

        await Future.wait([
          expectExactConverged(alice, finalIds),
          expectExactConverged(bob, finalIds),
          expectExactConverged(charlie, finalIds),
        ]);

        final epochs = <int>{};
        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull);
          expect(key!.keyGeneration, greaterThanOrEqualTo(1));
          epochs.add(key.keyGeneration);
        }
        expect(epochs, hasLength(1));
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });
      },
    );

    test(
      'GE-010 zero live topic peers use durable inbox fallback and receivers recover',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge010-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge010-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge010-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge010-zero-live-topic-peers';
        const messageId = 'ge010-zero-live-fallback-alice';
        const messageText = 'GE-010 zero live topic peers';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge010-shared-private-chat-key';
        final createdAt = DateTime.utc(2026, 5, 10, 16);
        await alice.createGroup(
          groupId: groupId,
          name: 'GE-010 Zero Live Topic Peers',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
        });

        Map<String, dynamic> latestInboxPayloadForMessage(
          GroupTestUser sender,
          String targetMessageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] == targetMessageId) {
              return payload;
            }
          }
          fail('missing group:inboxStore for $targetMessageId');
        }

        Map<String, dynamic> relayRecordForMessage(
          GroupTestUser sender,
          String targetMessageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, targetMessageId);
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<GroupMessage>> loadGe010Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 50,
          )).where((message) => message.id.startsWith('ge010-')).toList();
        }

        Future<void> expectGe010Message(
          GroupTestUser user, {
          required bool incoming,
        }) async {
          final messages = await loadGe010Messages(user);
          expect(
            messages.where((message) => message.id == messageId).toList(),
            hasLength(1),
            reason: '${user.username} should persist GE-010 exactly once',
          );
          final message = messages.singleWhere(
            (message) => message.id == messageId,
          );
          expect(message.text, messageText);
          expect(message.senderPeerId, alice.peerId);
          expect(message.isIncoming, incoming);
          expect(message.status, incoming ? 'delivered' : 'sent');
        }

        bob.unsubscribeFromGroup(groupId);
        charlie.unsubscribeFromGroup(groupId);
        expect(network.getSubscribers(groupId).toSet(), {alice.peerId});

        network.resetCounters();
        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: messageText,
          messageId: messageId,
          timestamp: createdAt.add(const Duration(minutes: 1)),
          publishTopicPeersOverride: 0,
        );

        expect(result.name, 'successNoPeers');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.status, 'sent');
        expect(sentMessage.inboxStored, isTrue);
        expect(sentMessage.inboxRetryPayload, isNull);
        expect(network.publishCallCount, 0);
        expect(network.totalDeliveries, 0);

        final inboxPayload = latestInboxPayloadForMessage(alice, messageId);
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          unorderedEquals(<String>[bob.peerId, charlie.peerId]),
        );
        final relayRecord = relayRecordForMessage(alice, messageId);

        bob.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [relayRecord],
          'cursor': '',
        };
        charlie.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [relayRecord],
          'cursor': '',
        };

        bob.subscribeToGroup(groupId);
        charlie.subscribeToGroup(groupId);
        await drainGroupOfflineInboxForGroup(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          groupMessageListener: bob.groupMessageListener,
          selfPeerId: bob.peerId,
        );
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );

        await expectGe010Message(alice, incoming: false);
        await expectGe010Message(bob, incoming: true);
        await expectGe010Message(charlie, incoming: true);

        final epochs = <int>{};
        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull);
          epochs.add(key!.keyGeneration);
        }
        expect(epochs, hasLength(1));
      },
    );

    test(
      'GE-011 partial live topic peers use live plus inbox fallback and dedupe',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge011-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ge011-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ge011-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ge011-partial-live-topic-peers';
        const messageId = 'ge011-partial-live-fallback-alice';
        const messageText = 'GE-011 partial live topic peers';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge011-shared-private-chat-key';
        final createdAt = DateTime.utc(2026, 5, 10, 17);
        await alice.createGroup(
          groupId: groupId,
          name: 'GE-011 Partial Live Topic Peers',
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

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bob, GroupRole.member),
          saveParticipantState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();
        charlie.unsubscribeFromGroup(groupId);
        expect(network.getSubscribers(groupId).toSet(), {
          alice.peerId,
          bob.peerId,
        });

        Map<String, dynamic> latestInboxPayloadForMessage(
          GroupTestUser sender,
          String targetMessageId,
        ) {
          for (final raw in sender.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final replayEnvelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (replayEnvelope['messageId'] == targetMessageId) {
              return payload;
            }
          }
          fail('missing group:inboxStore for $targetMessageId');
        }

        Map<String, dynamic> relayRecordForMessage(
          GroupTestUser sender,
          String targetMessageId,
        ) {
          final payload = latestInboxPayloadForMessage(sender, targetMessageId);
          return {
            'from': sender.peerId,
            'message': payload['message'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
        }

        Future<List<GroupMessage>> loadGe011Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 50,
          )).where((message) => message.id.startsWith('ge011-')).toList();
        }

        Future<void> expectGe011Message(
          GroupTestUser user, {
          required bool incoming,
        }) async {
          final messages = await loadGe011Messages(user);
          expect(
            messages.where((message) => message.id == messageId).toList(),
            hasLength(1),
            reason: '${user.username} should persist GE-011 exactly once',
          );
          final message = messages.singleWhere(
            (message) => message.id == messageId,
          );
          expect(message.text, messageText);
          expect(message.senderPeerId, alice.peerId);
          expect(message.isIncoming, incoming);
          expect(message.status, incoming ? 'delivered' : 'sent');
        }

        network.resetCounters();
        final (result, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: messageText,
          messageId: messageId,
          timestamp: createdAt.add(const Duration(minutes: 1)),
          publishTopicPeersOverride: 1,
        );
        await pump();

        expect(result.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.status, 'sent');
        expect(sentMessage.inboxStored, isTrue);
        expect(sentMessage.inboxRetryPayload, isNull);
        expect(network.publishCallCount, 1);
        expect(network.totalDeliveries, 1);
        await expectGe011Message(alice, incoming: false);
        await expectGe011Message(bob, incoming: true);
        expect(await loadGe011Messages(charlie), isEmpty);

        final inboxPayload = latestInboxPayloadForMessage(alice, messageId);
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          unorderedEquals(<String>[bob.peerId, charlie.peerId]),
        );
        final relayRecord = relayRecordForMessage(alice, messageId);

        bob.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [relayRecord],
          'cursor': '',
        };
        charlie.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [relayRecord],
          'cursor': '',
        };

        await drainGroupOfflineInboxForGroup(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          groupId: groupId,
          groupMessageListener: bob.groupMessageListener,
          selfPeerId: bob.peerId,
        );
        await expectGe011Message(bob, incoming: true);

        charlie.subscribeToGroup(groupId);
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
        );
        await expectGe011Message(charlie, incoming: true);

        final epochs = <int>{};
        for (final user in [alice, bob, charlie]) {
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberIds, {alice.peerId, bob.peerId, charlie.peerId});
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull);
          epochs.add(key!.keyGeneration);
        }
        expect(epochs, hasLength(1));
      },
    );

    test(
      'GE-012 same-user Bob devices exchange without sibling rejection',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge012-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bobPrimary = GroupTestUser.create(
          peerId: 'ge012-bob-peer',
          deviceId: 'ge012-bob-device-1',
          username: 'Bob',
          network: network,
        );
        final bobSibling = GroupTestUser.create(
          peerId: 'ge012-bob-peer',
          deviceId: 'ge012-bob-device-2',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bobPrimary.dispose();
          bobSibling.dispose();
        });

        const groupId = 'group-ge012-same-user-bob-devices';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge012-shared-private-chat-key';
        const aliceMessageId = 'ge012-alice-to-bob-devices';
        const bobPrimaryMessageId = 'ge012-bob-primary-to-group';
        const bobSiblingMessageId = 'ge012-bob-sibling-to-group';
        final createdAt = DateTime.utc(2026, 5, 10, 18);
        await alice.createGroup(
          groupId: groupId,
          name: 'GE-012 Same User Devices',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bobPrimary,
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        );

        final group = (await alice.groupRepo.getGroup(groupId))!;
        final members = await alice.groupRepo.getMembers(groupId);
        final bobMember = members.singleWhere(
          (member) => member.peerId == bobPrimary.peerId,
        );
        expect(
          bobMember.devices.map((device) => device.deviceId).toSet(),
          {bobPrimary.deviceId, bobSibling.deviceId},
          reason: 'Bob must be one logical member with both active devices',
        );

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in members) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin),
          saveParticipantState(bobPrimary, GroupRole.member),
          saveParticipantState(bobSibling, GroupRole.member),
        ]);

        alice.start();
        bobPrimary.start();
        bobSibling.start();
        bobSibling.subscribeToGroup(groupId);
        expect(network.isSubscribed(groupId, alice.deviceId), isTrue);
        expect(network.isSubscribed(groupId, bobPrimary.deviceId), isTrue);
        expect(network.isSubscribed(groupId, bobSibling.deviceId), isTrue);

        Map<String, dynamic> publishPayloadFor(
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

        List<String> durableRecipientsFor(
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
              return (payload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>();
            }
          }
          fail('missing group:inboxStore for $messageId');
        }

        Future<List<GroupMessage>> loadGe012Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 50,
          )).where((message) => message.id.startsWith('ge012-')).toList();
        }

        Future<void> expectGe012Message(
          GroupTestUser user, {
          required String messageId,
          required String text,
          required String senderPeerId,
          required String transportPeerId,
          required bool incoming,
          required String status,
        }) async {
          final messages = await loadGe012Messages(user);
          expect(
            messages.where((message) => message.id == messageId).toList(),
            hasLength(1),
            reason: '${user.deviceId} should persist $messageId exactly once',
          );
          final message = messages.singleWhere(
            (message) => message.id == messageId,
          );
          expect(message.text, text);
          expect(message.senderPeerId, senderPeerId);
          expect(message.transportPeerId, transportPeerId);
          expect(message.isIncoming, incoming);
          expect(message.status, status);
        }

        network.resetCounters();
        final (aliceResult, aliceSent) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'GE-012 Alice to Bob devices',
          messageId: aliceMessageId,
          timestamp: createdAt.add(const Duration(minutes: 1)),
        );
        await pump();
        expect(aliceResult.name, 'success');
        expect(aliceSent?.status, 'sent');

        final (bobPrimaryResult, bobPrimarySent) = await bobPrimary
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-012 Bob primary to group',
              messageId: bobPrimaryMessageId,
              timestamp: createdAt.add(const Duration(minutes: 2)),
            );
        await pump();
        expect(bobPrimaryResult.name, 'success');
        expect(bobPrimarySent?.status, 'sent');

        final (bobSiblingResult, bobSiblingSent) = await bobSibling
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-012 Bob sibling to group',
              messageId: bobSiblingMessageId,
              timestamp: createdAt.add(const Duration(minutes: 3)),
            );
        await pump();
        expect(bobSiblingResult.name, 'success');
        expect(bobSiblingSent?.status, 'sent');
        expect(network.publishCallCount, 3);
        expect(network.totalDeliveries, 6);

        expect(
          durableRecipientsFor(alice, aliceMessageId),
          [bobPrimary.peerId],
          reason: 'Durable custody should target logical Bob once',
        );
        expect(durableRecipientsFor(bobPrimary, bobPrimaryMessageId), [
          alice.peerId,
        ]);
        expect(durableRecipientsFor(bobSibling, bobSiblingMessageId), [
          alice.peerId,
        ]);

        expect(
          publishPayloadFor(bobPrimary, bobPrimaryMessageId)['senderDeviceId'],
          bobPrimary.deviceId,
        );
        expect(
          publishPayloadFor(bobSibling, bobSiblingMessageId)['senderDeviceId'],
          bobSibling.deviceId,
        );

        await expectGe012Message(
          alice,
          messageId: aliceMessageId,
          text: 'GE-012 Alice to Bob devices',
          senderPeerId: alice.peerId,
          transportPeerId: alice.deviceId,
          incoming: false,
          status: 'sent',
        );
        await expectGe012Message(
          alice,
          messageId: bobPrimaryMessageId,
          text: 'GE-012 Bob primary to group',
          senderPeerId: bobPrimary.peerId,
          transportPeerId: bobPrimary.deviceId,
          incoming: true,
          status: 'delivered',
        );
        await expectGe012Message(
          alice,
          messageId: bobSiblingMessageId,
          text: 'GE-012 Bob sibling to group',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: true,
          status: 'delivered',
        );

        for (final bobDevice in [bobPrimary, bobSibling]) {
          await expectGe012Message(
            bobDevice,
            messageId: aliceMessageId,
            text: 'GE-012 Alice to Bob devices',
            senderPeerId: alice.peerId,
            transportPeerId: alice.deviceId,
            incoming: true,
            status: 'delivered',
          );
        }
        await expectGe012Message(
          bobPrimary,
          messageId: bobPrimaryMessageId,
          text: 'GE-012 Bob primary to group',
          senderPeerId: bobPrimary.peerId,
          transportPeerId: bobPrimary.deviceId,
          incoming: false,
          status: 'sent',
        );
        await expectGe012Message(
          bobPrimary,
          messageId: bobSiblingMessageId,
          text: 'GE-012 Bob sibling to group',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: false,
          status: 'sent',
        );
        await expectGe012Message(
          bobSibling,
          messageId: bobPrimaryMessageId,
          text: 'GE-012 Bob primary to group',
          senderPeerId: bobPrimary.peerId,
          transportPeerId: bobPrimary.deviceId,
          incoming: false,
          status: 'sent',
        );
        await expectGe012Message(
          bobSibling,
          messageId: bobSiblingMessageId,
          text: 'GE-012 Bob sibling to group',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: false,
          status: 'sent',
        );

        for (final user in [alice, bobPrimary, bobSibling]) {
          expect(await loadGe012Messages(user), hasLength(3));
          final memberIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toList();
          expect(memberIds.where((peerId) => peerId == bobPrimary.peerId), [
            bobPrimary.peerId,
          ]);
          final localBobMember = await user.groupRepo.getMember(
            groupId,
            bobPrimary.peerId,
          );
          expect(localBobMember, isNotNull);
          expect(
            localBobMember!.devices.map((device) => device.deviceId).toSet(),
            {bobPrimary.deviceId, bobSibling.deviceId},
          );
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key?.keyGeneration, keyEpoch);
        }
      },
    );

    test(
      'GE-013 revoked Bob sibling device cannot send while B1 remains functional',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ge013-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bobPrimary = GroupTestUser.create(
          peerId: 'ge013-bob-peer',
          deviceId: 'ge013-bob-device-1',
          username: 'Bob',
          network: network,
        );
        final bobSibling = GroupTestUser.create(
          peerId: 'ge013-bob-peer',
          deviceId: 'ge013-bob-device-2',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bobPrimary.dispose();
          bobSibling.dispose();
        });

        const groupId = 'group-ge013-revoked-bob-sibling-device';
        const keyEpoch = 1;
        const sharedEncryptedKey = 'ge013-shared-private-chat-key';
        const siblingBeforeRevokeId = 'ge013-b2-before-revoke';
        const siblingAfterRevokeId = 'ge013-b2-after-revoke';
        const primaryAfterRevokeId = 'ge013-b1-after-revoke';
        const aliceAfterRevokeId = 'ge013-alice-after-revoke';
        final createdAt = DateTime.utc(2026, 5, 10, 19);
        await alice.createGroup(
          groupId: groupId,
          name: 'GE-013 Device Revocation',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bobPrimary,
          joinedAt: createdAt.add(const Duration(seconds: 1)),
        );

        final group = (await alice.groupRepo.getGroup(groupId))!;
        var members = await alice.groupRepo.getMembers(groupId);
        final bobMember = members.singleWhere(
          (member) => member.peerId == bobPrimary.peerId,
        );
        expect(
          bobMember.activeDevices.map((device) => device.deviceId).toSet(),
          {bobPrimary.deviceId, bobSibling.deviceId},
          reason: 'Bob starts as one member with B1 and B2 active',
        );

        Future<void> saveParticipantState(
          GroupTestUser user,
          GroupRole role,
          List<GroupMember> memberRows,
        ) async {
          await user.groupRepo.saveGroup(group.copyWith(myRole: role));
          for (final member in memberRows) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: sharedEncryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveParticipantState(alice, GroupRole.admin, members),
          saveParticipantState(bobPrimary, GroupRole.member, members),
          saveParticipantState(bobSibling, GroupRole.member, members),
        ]);

        alice.start();
        bobPrimary.start();
        bobSibling.start();
        bobSibling.subscribeToGroup(groupId);
        expect(network.isSubscribed(groupId, alice.deviceId), isTrue);
        expect(network.isSubscribed(groupId, bobPrimary.deviceId), isTrue);
        expect(network.isSubscribed(groupId, bobSibling.deviceId), isTrue);

        List<String> durableRecipientsFor(
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
              return (payload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>();
            }
          }
          fail('missing group:inboxStore for $messageId');
        }

        int bridgeCommandCount(GroupTestUser user, String command) {
          return user.bridge.sentMessages.where((raw) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            return parsed['cmd'] == command;
          }).length;
        }

        Future<List<GroupMessage>> loadGe013Messages(GroupTestUser user) async {
          return (await user.msgRepo.getMessagesPage(
            groupId,
            limit: 50,
          )).where((message) => message.id.startsWith('ge013-')).toList();
        }

        Future<void> expectGe013Message(
          GroupTestUser user, {
          required String messageId,
          required String text,
          required String senderPeerId,
          required String transportPeerId,
          required bool incoming,
          required String status,
        }) async {
          final messages = await loadGe013Messages(user);
          expect(
            messages.where((message) => message.id == messageId).toList(),
            hasLength(1),
            reason: '${user.deviceId} should persist $messageId exactly once',
          );
          final message = messages.singleWhere(
            (message) => message.id == messageId,
          );
          expect(message.text, text);
          expect(message.senderPeerId, senderPeerId);
          expect(message.transportPeerId, transportPeerId);
          expect(message.isIncoming, incoming);
          expect(message.status, status);
        }

        Future<void> expectNoGe013Message(
          GroupTestUser user,
          String messageId,
        ) async {
          final messages = await loadGe013Messages(user);
          expect(
            messages.where((message) => message.id == messageId),
            isEmpty,
            reason: '${user.deviceId} must not persist $messageId',
          );
        }

        network.resetCounters();
        final (siblingBeforeResult, siblingBeforeSent) = await bobSibling
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-013 B2 before revoke',
              messageId: siblingBeforeRevokeId,
              timestamp: createdAt.add(const Duration(minutes: 1)),
            );
        await pump();
        expect(siblingBeforeResult.name, 'success');
        expect(siblingBeforeSent?.status, 'sent');
        expect(network.publishCallCount, 1);
        expect(network.totalDeliveries, 2);
        expect(durableRecipientsFor(bobSibling, siblingBeforeRevokeId), [
          alice.peerId,
        ]);

        await expectGe013Message(
          alice,
          messageId: siblingBeforeRevokeId,
          text: 'GE-013 B2 before revoke',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: true,
          status: 'delivered',
        );
        await expectGe013Message(
          bobPrimary,
          messageId: siblingBeforeRevokeId,
          text: 'GE-013 B2 before revoke',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: false,
          status: 'sent',
        );
        await expectGe013Message(
          bobSibling,
          messageId: siblingBeforeRevokeId,
          text: 'GE-013 B2 before revoke',
          senderPeerId: bobSibling.peerId,
          transportPeerId: bobSibling.deviceId,
          incoming: false,
          status: 'sent',
        );

        final revokedAt = createdAt.add(const Duration(minutes: 2));
        final revokedBobMember = bobMember.copyWith(
          devices: [
            for (final device in bobMember.devices)
              device.deviceId == bobSibling.deviceId
                  ? device.copyWith(
                      status: GroupMemberDeviceStatus.revoked,
                      revokedAt: revokedAt,
                    )
                  : device,
          ],
        );
        expect(
          revokedBobMember.activeDevices.map((device) => device.deviceId),
          [bobPrimary.deviceId],
        );
        members = [
          for (final member in members)
            member.peerId == bobPrimary.peerId ? revokedBobMember : member,
        ];
        await Future.wait([
          saveParticipantState(alice, GroupRole.admin, members),
          saveParticipantState(bobPrimary, GroupRole.member, members),
          saveParticipantState(bobSibling, GroupRole.member, members),
        ]);

        for (final user in [alice, bobPrimary, bobSibling]) {
          final localBob = await user.groupRepo.getMember(
            groupId,
            bobPrimary.peerId,
          );
          expect(localBob, isNotNull);
          expect(localBob!.activeDevices.map((device) => device.deviceId), [
            bobPrimary.deviceId,
          ]);
          final localB2 = localBob.devices.singleWhere(
            (device) => device.deviceId == bobSibling.deviceId,
          );
          expect(localB2.status, GroupMemberDeviceStatus.revoked);
          expect(localB2.revokedAt, revokedAt);
        }

        final b2PublishCountBeforeRevokeAttempt = bridgeCommandCount(
          bobSibling,
          'group:publish',
        );
        final b2InboxCountBeforeRevokeAttempt = bridgeCommandCount(
          bobSibling,
          'group:inboxStore',
        );
        final (siblingAfterResult, siblingAfterSent) = await bobSibling
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-013 B2 after revoke should fail',
              messageId: siblingAfterRevokeId,
              timestamp: createdAt.add(const Duration(minutes: 3)),
            );
        await pump();
        expect(siblingAfterResult.name, 'unauthorized');
        expect(siblingAfterSent, isNull);
        expect(
          bridgeCommandCount(bobSibling, 'group:publish'),
          b2PublishCountBeforeRevokeAttempt,
        );
        expect(
          bridgeCommandCount(bobSibling, 'group:inboxStore'),
          b2InboxCountBeforeRevokeAttempt,
        );
        expect(network.publishCallCount, 1);
        for (final user in [alice, bobPrimary, bobSibling]) {
          await expectNoGe013Message(user, siblingAfterRevokeId);
        }

        final (primaryAfterResult, primaryAfterSent) = await bobPrimary
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-013 B1 after B2 revoke',
              messageId: primaryAfterRevokeId,
              timestamp: createdAt.add(const Duration(minutes: 4)),
            );
        await pump();
        expect(primaryAfterResult.name, 'success');
        expect(primaryAfterSent?.status, 'sent');
        expect(durableRecipientsFor(bobPrimary, primaryAfterRevokeId), [
          alice.peerId,
        ]);
        await expectGe013Message(
          alice,
          messageId: primaryAfterRevokeId,
          text: 'GE-013 B1 after B2 revoke',
          senderPeerId: bobPrimary.peerId,
          transportPeerId: bobPrimary.deviceId,
          incoming: true,
          status: 'delivered',
        );
        await expectGe013Message(
          bobPrimary,
          messageId: primaryAfterRevokeId,
          text: 'GE-013 B1 after B2 revoke',
          senderPeerId: bobPrimary.peerId,
          transportPeerId: bobPrimary.deviceId,
          incoming: false,
          status: 'sent',
        );

        final (aliceAfterResult, aliceAfterSent) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: 'GE-013 Alice after B2 revoke',
              messageId: aliceAfterRevokeId,
              timestamp: createdAt.add(const Duration(minutes: 5)),
            );
        await pump();
        expect(aliceAfterResult.name, 'success');
        expect(aliceAfterSent?.status, 'sent');
        expect(durableRecipientsFor(alice, aliceAfterRevokeId), [
          bobPrimary.peerId,
        ]);
        await expectGe013Message(
          bobPrimary,
          messageId: aliceAfterRevokeId,
          text: 'GE-013 Alice after B2 revoke',
          senderPeerId: alice.peerId,
          transportPeerId: alice.deviceId,
          incoming: true,
          status: 'delivered',
        );
        await expectGe013Message(
          alice,
          messageId: aliceAfterRevokeId,
          text: 'GE-013 Alice after B2 revoke',
          senderPeerId: alice.peerId,
          transportPeerId: alice.deviceId,
          incoming: false,
          status: 'sent',
        );

        expect(await loadGe013Messages(alice), hasLength(3));
        expect(await loadGe013Messages(bobPrimary), hasLength(3));
        expect(network.publishCallCount, 3);
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

    test(
      'GE-017 seeded random membership operations preserve invariants',
      () async {
        const seeds = [17017, 17018, 17019];
        for (final seed in seeds) {
          await _runGe017Seed(seed, network, pump, waitUntil);
        }
      },
    );

    test(
      'GE-019 seeded random key rotations preserve access windows',
      () async {
        const seeds = [19019, 19020, 19021];
        for (final seed in seeds) {
          await _runGe019Seed(seed, network, pump, waitUntil);
        }
      },
    );

    test(
      'GE-020 long soak private group with churn preserves convergence',
      () async {
        const seeds = [20020, 20021, 20022];
        for (final seed in seeds) {
          await _runGe020Seed(seed, network, pump, waitUntil);
        }
      },
    );

    test(
      'GE-021 large group with one flaky member preserves stable delivery',
      () async {
        await _runGe021LargeGroupFlakyMember(network, pump, waitUntil);
      },
    );

    test(
      'GE-023 media attachments in private group through remove/re-add respect entitlement',
      () async {
        await _runGe023MediaReaddEntitlement(network, pump, waitUntil);
      },
    );

    test(
      'GE-024 quoted replies across membership boundary preserve entitlement fallback',
      () async {
        await _runGe024QuotedRepliesAcrossBoundary(network, pump, waitUntil);
      },
    );

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

Future<void> _runGe017Seed(
  int seed,
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  final random = Random(seed);
  const operationCount = 30;
  final groupId = 'group-ge017-$seed';
  final baseTime = DateTime.utc(
    2026,
    5,
    13,
    17,
    17,
  ).add(Duration(minutes: seed - 17017));
  var step = 0;
  var currentEpoch = 1;
  var cleanedUp = false;
  final active = <String>{'A', 'B', 'C'};
  final online = <String>{'A', 'B', 'C'};
  final operationLog = <String>[];
  final expectations = <String, ({String sender, Set<String> recipients})>{};

  final users = <String, GroupTestUser>{
    'A': GroupTestUser.create(
      peerId: 'ge017-$seed-alice-peer',
      username: 'Alice',
      network: network,
    ),
    'B': GroupTestUser.create(
      peerId: 'ge017-$seed-bob-peer',
      username: 'Bob',
      network: network,
    ),
    'C': GroupTestUser.create(
      peerId: 'ge017-$seed-charlie-peer',
      username: 'Charlie',
      network: network,
    ),
    'D': GroupTestUser.create(
      peerId: 'ge017-$seed-dana-peer',
      username: 'Dana',
      network: network,
    ),
  };

  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    for (final user in users.values.toSet()) {
      user.dispose();
    }
  }

  addTearDown(cleanup);

  DateTime nextTime() => baseTime.add(Duration(seconds: step++));

  String stateContext(String op) {
    final sortedActive = active.toList()..sort();
    final sortedOnline = online.toList()..sort();
    return 'seed=$seed step=$step op=$op active=$sortedActive '
        'online=$sortedOnline log=${operationLog.join(' | ')}';
  }

  GroupTestUser user(String label) => users[label]!;

  Future<void> saveKeyFor(String label) {
    return user(label).groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: currentEpoch,
        encryptedKey: 'ge017-$seed-key-$currentEpoch',
        createdAt: nextTime(),
      ),
    );
  }

  Future<void> saveKeyForActive() async {
    for (final label in active) {
      await saveKeyFor(label);
    }
  }

  Future<void> mirrorAliceStateToActiveUsers() async {
    final group = (await user('A').groupRepo.getGroup(groupId))!;
    final members = await user('A').groupRepo.getMembers(groupId);
    for (final label in active) {
      await user(label).groupRepo.saveGroup(
        group.copyWith(
          myRole: label == 'A' ? GroupRole.admin : GroupRole.member,
        ),
      );
      for (final member in members) {
        await user(label).groupRepo.saveMember(member);
      }
    }
  }

  Set<String> activePeerIds() =>
      active.map((label) => user(label).peerId).toSet();

  Future<int> messageCount(String label, String messageId) async {
    return (await user(label).loadGroupMessages(
      groupId,
    )).where((message) => message.id == messageId).length;
  }

  Future<List<GroupMessage>> messagesFor(String label) {
    return user(label).loadGroupMessages(groupId);
  }

  Future<void> expectMemberUniqueness(String label, String op) async {
    final members = await user(label).groupRepo.getMembers(groupId);
    final peerIds = members.map((member) => member.peerId).toList();
    expect(
      peerIds.toSet(),
      hasLength(peerIds.length),
      reason: '${stateContext(op)} duplicate active member rows for $label',
    );

    for (final member in members) {
      final deviceIds = member.devices
          .map((device) => device.deviceId)
          .toList();
      expect(
        deviceIds.toSet(),
        hasLength(deviceIds.length),
        reason:
            '${stateContext(op)} duplicate active devices for '
            '$label/${member.peerId}',
      );
    }
  }

  Future<void> expectConvergedState(String label, String op) async {
    await expectMemberUniqueness(label, op);
    if (!active.contains(label) || !online.contains(label)) {
      return;
    }

    final group = await user(label).groupRepo.getGroup(groupId);
    expect(group, isNotNull, reason: stateContext(op));
    final members = await user(label).groupRepo.getMembers(groupId);
    expect(
      members.map((member) => member.peerId).toSet(),
      activePeerIds(),
      reason: '${stateContext(op)} member set mismatch for $label',
    );
    final latestKey = await user(label).groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull, reason: stateContext(op));
    expect(
      latestKey!.keyGeneration,
      currentEpoch,
      reason: '${stateContext(op)} key epoch mismatch for $label',
    );
  }

  Future<void> expectMessageInvariants(
    String op, {
    bool finalRecovery = false,
  }) async {
    for (final entry in expectations.entries) {
      final messageId = entry.key;
      final sender = entry.value.sender;
      final recipients = entry.value.recipients;
      for (final label in users.keys) {
        final count = await messageCount(label, messageId);
        expect(
          count,
          lessThanOrEqualTo(1),
          reason: '${stateContext(op)} duplicate $messageId for $label',
        );
        if (label == sender) {
          expect(
            count,
            1,
            reason: '${stateContext(op)} sender missing $messageId',
          );
        } else if (recipients.contains(label)) {
          if (finalRecovery || online.contains(label)) {
            expect(
              count,
              1,
              reason:
                  '${stateContext(op)} entitled recipient $label missing '
                  '$messageId',
            );
          }
        } else {
          expect(
            count,
            0,
            reason: '${stateContext(op)} non-entitled $label has $messageId',
          );
        }
      }
    }
  }

  Future<void> expectInvariants(String op) async {
    for (final label in users.keys) {
      await expectMemberUniqueness(label, op);
    }
    for (final label in active.where(online.contains)) {
      await expectConvergedState(label, op);
    }
    await expectMessageInvariants(op);
  }

  Future<void> recoverOnline(String label, String op) async {
    if (!active.contains(label)) return;
    online.add(label);
    user(label).subscribeToGroup(groupId);
    await network.releaseHeldDeliveriesFor(
      user(label).peerId,
      reverse: random.nextBool(),
    );
    await pump();
    await waitUntil(() async {
      for (final entry in expectations.entries) {
        if (entry.value.recipients.contains(label) &&
            await messageCount(label, entry.key) != 1) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
    await expectConvergedState(label, op);
  }

  Future<void> sendFrom(String label, String op) async {
    final messageId = 'ge017-$seed-msg-${expectations.length}';
    final recipients = active.where((entry) => entry != label).toSet();
    final beforePublish = network.publishCallCount;
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: 'GE-017 seed $seed message ${expectations.length}',
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['success', 'successNoPeers']),
      reason: stateContext(op),
    );
    expect(sent, isNotNull, reason: stateContext(op));
    expect(await messageCount(label, messageId), 1, reason: stateContext(op));
    expectations[messageId] = (sender: label, recipients: recipients);

    if (online.length > 1) {
      expect(
        network.publishCallCount,
        greaterThan(beforePublish),
        reason: '${stateContext(op)} active send did not publish',
      );
    }

    await waitUntil(() async {
      for (final recipient in recipients.where(online.contains)) {
        if (await messageCount(recipient, messageId) != 1) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
  }

  Future<void> inactiveSend(String label, String op) async {
    final messageId = 'ge017-$seed-inactive-${operationLog.length}';
    final beforePublish = network.publishCallCount;
    final beforeMessages = await messagesFor(label);
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: 'GE-017 inactive send must fail',
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['groupNotFound', 'groupDissolved', 'unauthorized', 'error']),
      reason: stateContext(op),
    );
    expect(sent, isNull, reason: stateContext(op));
    expect(network.publishCallCount, beforePublish, reason: stateContext(op));
    expect(await messageCount(label, messageId), 0, reason: stateContext(op));
    final afterMessages = await messagesFor(label);
    expect(
      afterMessages.map((message) => message.id).toSet(),
      beforeMessages.map((message) => message.id).toSet(),
      reason: '${stateContext(op)} inactive send mutated local messages',
    );
  }

  Future<void> addOrReadd(String label, String op) async {
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user(label), joinedAt: nextTime());
    active.add(label);
    online.add(label);
    await saveKeyFor(label);
    await user('A').broadcastMemberAdded(
      groupId: groupId,
      newMember: user(label),
      eventAt: nextTime(),
    );
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active.where(online.contains)) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        if (members.map((member) => member.peerId).toSet().length !=
            active.length) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
    await saveKeyForActive();
  }

  Future<void> removeActive(String label, String op) async {
    if (!online.contains(label)) {
      await recoverOnline(label, '$op:pre-remove-online');
    }
    await user('A').removeMember(
      groupId: groupId,
      memberPeerId: user(label).peerId,
      memberUsername: user(label).username,
      removedAt: nextTime(),
    );
    active.remove(label);
    online.remove(label);
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active.where(online.contains)) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        if (members.any((member) => member.peerId == user(label).peerId)) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
  }

  Future<void> rotateKey(String op) async {
    currentEpoch++;
    user('A').bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'ge017-$seed-key-$currentEpoch',
      'keyEpoch': currentEpoch,
    };
    final targets = <String>[];
    final rotatedKey = await rotateAndDistributeGroupKey(
      bridge: user('A').bridge,
      groupRepo: user('A').groupRepo,
      groupId: groupId,
      selfPeerId: user('A').peerId,
      senderPublicKey: user('A').publicKey,
      senderPrivateKey: user('A').privateKey,
      senderUsername: user('A').username,
      sourceDeviceId: user('A').deviceId,
      sendP2PMessage: (peerId, _) async {
        targets.add(peerId);
        return true;
      },
    );
    expect(rotatedKey, isNotNull, reason: stateContext(op));
    expect(rotatedKey!.keyGeneration, currentEpoch, reason: stateContext(op));
    for (final label in active) {
      await user(label).groupRepo.saveKey(rotatedKey);
    }
    expect(
      targets.toSet(),
      active
          .where((label) => label != 'A')
          .map((label) => user(label).deviceId)
          .toSet(),
      reason: stateContext(op),
    );
  }

  Future<void> restartActive(String label, String op) async {
    if (!online.contains(label)) {
      await recoverOnline(label, '$op:pre-restart-online');
    }
    users[label] = user(label).restartWithPersistedState();
    user(label).start();
    if (active.contains(label)) {
      user(label).subscribeToGroup(groupId);
      online.add(label);
    }
    await pump();
    await expectConvergedState(label, op);
  }

  Future<void> runOperation(String op) async {
    operationLog.add('$step:$op');
    switch (op) {
      case 'send':
        await sendFrom(active.elementAt(random.nextInt(active.length)), op);
        break;
      case 'offline':
        final candidates = active
            .where((label) => label != 'A' && online.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        final label = candidates[random.nextInt(candidates.length)];
        online.remove(label);
        network.holdDeliveriesFor(user(label).peerId);
        break;
      case 'online':
        final candidates = active
            .where((label) => !online.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await recoverOnline(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'remove':
        final candidates = active.where((label) => label != 'A').toList();
        if (candidates.isEmpty) return;
        await removeActive(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'readd':
        final candidates = users.keys
            .where((label) => label != 'A' && !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await addOrReadd(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'inactiveSend':
        final candidates = users.keys
            .where((label) => !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await inactiveSend(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'rotate':
        await rotateKey(op);
        break;
      case 'restart':
        await restartActive(
          active.elementAt(random.nextInt(active.length)),
          op,
        );
        break;
      case 'duplicateSend':
        network.duplicateOnDeliver = true;
        try {
          await sendFrom(active.elementAt(random.nextInt(active.length)), op);
        } finally {
          network.duplicateOnDeliver = false;
        }
        break;
      default:
        throw StateError('unknown GE-017 operation $op');
    }
    await pump();
    await expectInvariants(op);
  }

  try {
    await user('A').createGroup(
      groupId: groupId,
      name: 'GE-017 Seed $seed',
      createdAt: nextTime(),
    );
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('B'), joinedAt: nextTime());
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('C'), joinedAt: nextTime());
    await mirrorAliceStateToActiveUsers();
    await saveKeyForActive();
    for (final label in users.keys) {
      user(label).start();
    }
    await expectInvariants('initial');

    final guaranteed = [
      'send',
      'offline',
      'send',
      'online',
      'rotate',
      'remove',
      'inactiveSend',
      'readd',
      'duplicateSend',
      'restart',
    ];
    const randomOps = [
      'send',
      'offline',
      'online',
      'remove',
      'readd',
      'inactiveSend',
      'rotate',
      'restart',
      'duplicateSend',
    ];
    final operations = <String>[
      ...guaranteed,
      for (var index = guaranteed.length; index < operationCount; index++)
        randomOps[random.nextInt(randomOps.length)],
    ];

    for (final op in operations) {
      await runOperation(op);
    }

    for (final label in active.toList()) {
      if (!online.contains(label)) {
        await recoverOnline(label, 'final-recovery');
      }
    }
    await pump();
    await expectMessageInvariants('final-recovery', finalRecovery: true);
    for (final label in active) {
      await expectConvergedState(label, 'final-recovery');
    }
  } finally {
    await cleanup();
  }
}

Future<void> _runGe019Seed(
  int seed,
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  final random = Random(seed);
  const operationCount = 36;
  final groupId = 'group-ge019-$seed';
  final baseTime = DateTime.utc(
    2026,
    5,
    13,
    19,
    19,
  ).add(Duration(minutes: seed - 19019));
  var step = 0;
  var currentEpoch = 1;
  var cleanedUp = false;
  final active = <String>{'A', 'B', 'C'};
  final operationLog = <String>[];
  final expectations =
      <
        String,
        ({String sender, Set<String> recipients, int epoch, String text})
      >{};

  final users = <String, GroupTestUser>{
    'A': GroupTestUser.create(
      peerId: 'ge019-$seed-alice-peer',
      username: 'Alice',
      network: network,
    ),
    'B': GroupTestUser.create(
      peerId: 'ge019-$seed-bob-peer',
      username: 'Bob',
      network: network,
    ),
    'C': GroupTestUser.create(
      peerId: 'ge019-$seed-charlie-peer',
      username: 'Charlie',
      network: network,
    ),
    'D': GroupTestUser.create(
      peerId: 'ge019-$seed-dana-peer',
      username: 'Dana',
      network: network,
    ),
  };

  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    for (final user in users.values.toSet()) {
      user.dispose();
    }
  }

  addTearDown(cleanup);

  DateTime nextTime() => baseTime.add(Duration(seconds: step++));

  GroupTestUser user(String label) => users[label]!;

  Set<String> activePeerIds() =>
      active.map((label) => user(label).peerId).toSet();

  String stateContext(String op) {
    final sortedActive = active.toList()..sort();
    return 'seed=$seed step=$step op=$op epoch=$currentEpoch '
        'active=$sortedActive log=${operationLog.join(' | ')}';
  }

  Future<void> saveKeyFor(String label) {
    return user(label).groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: currentEpoch,
        encryptedKey: 'ge019-$seed-key-$currentEpoch',
        createdAt: nextTime(),
      ),
    );
  }

  Future<void> saveKeyForActive() async {
    for (final label in active) {
      await saveKeyFor(label);
    }
  }

  Future<void> mirrorAliceStateToActiveUsers() async {
    final group = (await user('A').groupRepo.getGroup(groupId))!;
    final members = await user('A').groupRepo.getMembers(groupId);
    for (final label in active) {
      await user(label).groupRepo.saveGroup(
        group.copyWith(
          myRole: label == 'A' ? GroupRole.admin : GroupRole.member,
        ),
      );
      for (final member in members) {
        await user(label).groupRepo.saveMember(member);
      }
    }
  }

  Future<List<GroupMessage>> messagesFor(String label) {
    return user(label).loadGroupMessages(groupId);
  }

  Future<List<GroupMessage>> messagesForId(
    String label,
    String messageId,
  ) async {
    return (await messagesFor(
      label,
    )).where((message) => message.id == messageId).toList();
  }

  Future<void> expectMemberUniqueness(String label, String op) async {
    final members = await user(label).groupRepo.getMembers(groupId);
    final peerIds = members.map((member) => member.peerId).toList();
    expect(
      peerIds.toSet(),
      hasLength(peerIds.length),
      reason: '${stateContext(op)} duplicate active member rows for $label',
    );

    for (final member in members) {
      final deviceIds = member.devices
          .map((device) => device.deviceId)
          .toList();
      expect(
        deviceIds.toSet(),
        hasLength(deviceIds.length),
        reason:
            '${stateContext(op)} duplicate active devices for '
            '$label/${member.peerId}',
      );
    }
  }

  Future<void> expectConvergedState(String label, String op) async {
    await expectMemberUniqueness(label, op);
    if (!active.contains(label)) {
      return;
    }

    final group = await user(label).groupRepo.getGroup(groupId);
    expect(group, isNotNull, reason: stateContext(op));
    final members = await user(label).groupRepo.getMembers(groupId);
    expect(
      members.map((member) => member.peerId).toSet(),
      activePeerIds(),
      reason: '${stateContext(op)} member set mismatch for $label',
    );

    final latestKey = await user(label).groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull, reason: stateContext(op));
    expect(
      latestKey!.keyGeneration,
      currentEpoch,
      reason: '${stateContext(op)} key epoch mismatch for $label',
    );
    final currentKey = await user(
      label,
    ).groupRepo.getKeyByGeneration(groupId, currentEpoch);
    expect(
      currentKey,
      isNotNull,
      reason: '${stateContext(op)} missing current key for $label',
    );
  }

  Future<void> expectAccessWindows(String op) async {
    for (final label in users.keys) {
      await expectMemberUniqueness(label, op);
    }
    for (final label in active) {
      await expectConvergedState(label, op);
    }

    for (final entry in expectations.entries) {
      final messageId = entry.key;
      final sender = entry.value.sender;
      final recipients = entry.value.recipients;
      final expectedEpoch = entry.value.epoch;
      final expectedText = entry.value.text;

      for (final label in users.keys) {
        final matches = await messagesForId(label, messageId);
        expect(
          matches,
          hasLength(lessThanOrEqualTo(1)),
          reason: '${stateContext(op)} duplicate $messageId for $label',
        );

        final isAuthorized = label == sender || recipients.contains(label);
        if (!isAuthorized) {
          expect(
            matches,
            isEmpty,
            reason:
                '${stateContext(op)} non-authorized $label rendered '
                '$messageId',
          );
          continue;
        }

        expect(
          matches,
          hasLength(1),
          reason: '${stateContext(op)} authorized $label missing $messageId',
        );
        final message = matches.single;
        expect(
          message.text,
          expectedText,
          reason: '${stateContext(op)} text mismatch for $label/$messageId',
        );
        expect(
          message.keyGeneration,
          expectedEpoch,
          reason: '${stateContext(op)} epoch mismatch for $label/$messageId',
        );
        expect(
          message.isIncoming,
          label != sender,
          reason:
              '${stateContext(op)} direction mismatch for $label/$messageId',
        );
      }
    }
  }

  Future<void> sendFrom(String label, String op) async {
    final messageIndex = expectations.length;
    final messageId = 'ge019-$seed-msg-$messageIndex';
    final text = 'GE-019 seed $seed epoch $currentEpoch message $messageIndex';
    final recipients = active.where((entry) => entry != label).toSet();
    final beforePublish = network.publishCallCount;
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: text,
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['success', 'successNoPeers']),
      reason: stateContext(op),
    );
    expect(sent, isNotNull, reason: stateContext(op));
    expect(sent!.keyGeneration, currentEpoch, reason: stateContext(op));
    expectations[messageId] = (
      sender: label,
      recipients: recipients,
      epoch: currentEpoch,
      text: text,
    );

    if (recipients.isNotEmpty) {
      expect(
        network.publishCallCount,
        greaterThan(beforePublish),
        reason: '${stateContext(op)} active send did not publish',
      );
    }

    await waitUntil(() async {
      for (final recipient in recipients) {
        if ((await messagesForId(recipient, messageId)).length != 1) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
  }

  Future<void> inactiveSend(String label, String op) async {
    final messageId = 'ge019-$seed-inactive-${operationLog.length}';
    final beforePublish = network.publishCallCount;
    final beforeMessages = await messagesFor(label);
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: 'GE-019 inactive send must fail',
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['groupNotFound', 'groupDissolved', 'unauthorized', 'error']),
      reason: stateContext(op),
    );
    expect(sent, isNull, reason: stateContext(op));
    expect(network.publishCallCount, beforePublish, reason: stateContext(op));
    expect(
      await messagesForId(label, messageId),
      isEmpty,
      reason: stateContext(op),
    );
    final afterMessages = await messagesFor(label);
    expect(
      afterMessages.map((message) => message.id).toSet(),
      beforeMessages.map((message) => message.id).toSet(),
      reason: '${stateContext(op)} inactive send mutated local messages',
    );
  }

  Future<void> addOrReadd(String label, String op) async {
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user(label), joinedAt: nextTime());
    active.add(label);
    await saveKeyFor(label);
    await user('A').broadcastMemberAdded(
      groupId: groupId,
      newMember: user(label),
      eventAt: nextTime(),
    );
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        if (members
            .map((member) => member.peerId)
            .toSet()
            .difference(activePeerIds())
            .isNotEmpty) {
          return false;
        }
        if (members.map((member) => member.peerId).toSet().length !=
            active.length) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
    await saveKeyForActive();
  }

  Future<void> removeActive(String label, String op) async {
    await user('A').removeMember(
      groupId: groupId,
      memberPeerId: user(label).peerId,
      memberUsername: user(label).username,
      removedAt: nextTime(),
    );
    active.remove(label);
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        final memberPeerIds = members.map((member) => member.peerId).toSet();
        if (memberPeerIds.length != active.length ||
            memberPeerIds.difference(activePeerIds()).isNotEmpty) {
          return false;
        }
      }
      return true;
    }, maxTicks: 40);
  }

  Future<void> rotateKey(String op) async {
    currentEpoch++;
    user('A').bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'ge019-$seed-key-$currentEpoch',
      'keyEpoch': currentEpoch,
    };
    final targets = <String>[];
    final rotatedKey = await rotateAndDistributeGroupKey(
      bridge: user('A').bridge,
      groupRepo: user('A').groupRepo,
      groupId: groupId,
      selfPeerId: user('A').peerId,
      senderPublicKey: user('A').publicKey,
      senderPrivateKey: user('A').privateKey,
      senderUsername: user('A').username,
      sourceDeviceId: user('A').deviceId,
      sendP2PMessage: (peerId, _) async {
        targets.add(peerId);
        return true;
      },
    );
    expect(rotatedKey, isNotNull, reason: stateContext(op));
    expect(rotatedKey!.keyGeneration, currentEpoch, reason: stateContext(op));
    for (final label in active) {
      await user(label).groupRepo.saveKey(rotatedKey);
    }
    expect(
      targets.toSet(),
      active
          .where((label) => label != 'A')
          .map((label) => user(label).deviceId)
          .toSet(),
      reason: stateContext(op),
    );
  }

  Future<void> runOperation(String op) async {
    operationLog.add('$step:$op');
    switch (op) {
      case 'send':
        await sendFrom(active.elementAt(random.nextInt(active.length)), op);
        break;
      case 'rotate':
        await rotateKey(op);
        break;
      case 'remove':
        final candidates = active.where((label) => label != 'A').toList();
        if (candidates.isEmpty) return;
        await removeActive(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'readd':
        final candidates = users.keys
            .where((label) => label != 'A' && !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await addOrReadd(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'inactiveSend':
        final candidates = users.keys
            .where((label) => !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await inactiveSend(candidates[random.nextInt(candidates.length)], op);
        break;
      default:
        throw StateError('unknown GE-019 operation $op');
    }
    await pump();
    await expectAccessWindows(op);
  }

  try {
    await user('A').createGroup(
      groupId: groupId,
      name: 'GE-019 Seed $seed',
      createdAt: nextTime(),
    );
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('B'), joinedAt: nextTime());
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('C'), joinedAt: nextTime());
    await mirrorAliceStateToActiveUsers();
    await saveKeyForActive();
    for (final label in users.keys) {
      user(label).start();
    }
    await expectAccessWindows('initial');

    final guaranteed = [
      'send',
      'rotate',
      'send',
      'remove',
      'send',
      'rotate',
      'inactiveSend',
      'readd',
      'send',
      'rotate',
      'remove',
      'send',
      'readd',
      'send',
    ];
    const randomOps = ['send', 'rotate', 'remove', 'readd', 'inactiveSend'];
    final operations = <String>[
      ...guaranteed,
      for (var index = guaranteed.length; index < operationCount; index++)
        randomOps[random.nextInt(randomOps.length)],
    ];

    for (final op in operations) {
      await runOperation(op);
    }

    await expectAccessWindows('final');
  } finally {
    await cleanup();
  }
}

Future<void> _runGe020Seed(
  int seed,
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  final random = Random(seed);
  const operationCount = 44;
  final groupId = 'group-ge020-$seed';
  final baseTime = DateTime.utc(
    2026,
    5,
    13,
    20,
    20,
  ).add(Duration(minutes: seed - 20020));
  var step = 0;
  var currentEpoch = 1;
  var cleanedUp = false;
  final active = <String>{'A', 'B', 'C'};
  final online = <String>{'A', 'B', 'C'};
  final operationLog = <String>[];
  final expectations =
      <
        String,
        ({String sender, Set<String> recipients, int epoch, String text})
      >{};

  final users = <String, GroupTestUser>{
    'A': GroupTestUser.create(
      peerId: 'ge020-$seed-alice-peer',
      username: 'Alice',
      network: network,
    ),
    'B': GroupTestUser.create(
      peerId: 'ge020-$seed-bob-peer',
      username: 'Bob',
      network: network,
    ),
    'C': GroupTestUser.create(
      peerId: 'ge020-$seed-charlie-peer',
      username: 'Charlie',
      network: network,
    ),
    'D': GroupTestUser.create(
      peerId: 'ge020-$seed-dana-peer',
      username: 'Dana',
      network: network,
    ),
  };

  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    for (final user in users.values.toSet()) {
      user.dispose();
    }
  }

  addTearDown(cleanup);

  DateTime nextTime() => baseTime.add(Duration(seconds: step++));

  GroupTestUser user(String label) => users[label]!;

  Set<String> activePeerIds() =>
      active.map((label) => user(label).peerId).toSet();

  String stateContext(String op) {
    final sortedActive = active.toList()..sort();
    final sortedOnline = online.toList()..sort();
    return 'seed=$seed step=$step op=$op epoch=$currentEpoch '
        'active=$sortedActive online=$sortedOnline '
        'log=${operationLog.join(' | ')}';
  }

  Future<void> saveKeyFor(String label) {
    return user(label).groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: currentEpoch,
        encryptedKey: 'ge020-$seed-key-$currentEpoch',
        createdAt: nextTime(),
      ),
    );
  }

  Future<void> saveKeyForActive() async {
    for (final label in active) {
      await saveKeyFor(label);
    }
  }

  Future<void> mirrorAliceStateToActiveUsers() async {
    final group = (await user('A').groupRepo.getGroup(groupId))!;
    final members = await user('A').groupRepo.getMembers(groupId);
    for (final label in active) {
      await user(label).groupRepo.saveGroup(
        group.copyWith(
          myRole: label == 'A' ? GroupRole.admin : GroupRole.member,
        ),
      );
      for (final member in members) {
        await user(label).groupRepo.saveMember(member);
      }
    }
  }

  Future<List<GroupMessage>> messagesFor(String label) {
    return user(label).loadGroupMessages(groupId);
  }

  Future<List<GroupMessage>> messagesForId(
    String label,
    String messageId,
  ) async {
    return (await messagesFor(
      label,
    )).where((message) => message.id == messageId).toList();
  }

  Future<void> expectMemberUniqueness(String label, String op) async {
    final members = await user(label).groupRepo.getMembers(groupId);
    final peerIds = members.map((member) => member.peerId).toList();
    expect(
      peerIds.toSet(),
      hasLength(peerIds.length),
      reason: '${stateContext(op)} duplicate member rows for $label',
    );

    for (final member in members) {
      final deviceIds = member.devices
          .map((device) => device.deviceId)
          .toList();
      expect(
        deviceIds.toSet(),
        hasLength(deviceIds.length),
        reason:
            '${stateContext(op)} duplicate active devices for '
            '$label/${member.peerId}',
      );
    }
  }

  Future<void> expectConvergedState(String label, String op) async {
    await expectMemberUniqueness(label, op);
    if (!active.contains(label) || !online.contains(label)) {
      return;
    }

    final group = await user(label).groupRepo.getGroup(groupId);
    expect(group, isNotNull, reason: stateContext(op));
    final members = await user(label).groupRepo.getMembers(groupId);
    expect(
      members.map((member) => member.peerId).toSet(),
      activePeerIds(),
      reason: '${stateContext(op)} member set mismatch for $label',
    );

    final latestKey = await user(label).groupRepo.getLatestKey(groupId);
    expect(latestKey, isNotNull, reason: stateContext(op));
    expect(
      latestKey!.keyGeneration,
      currentEpoch,
      reason: '${stateContext(op)} key epoch mismatch for $label',
    );
  }

  Future<void> expectHeldQueues(String op, {bool finalRecovery = false}) async {
    for (final label in users.keys) {
      final held = network.heldDeliveryCountFor(user(label).peerId);
      if (finalRecovery || online.contains(label) || !active.contains(label)) {
        expect(
          held,
          0,
          reason: '${stateContext(op)} stranded held deliveries for $label',
        );
      }
    }
  }

  Future<void> expectMessageInvariants(
    String op, {
    bool finalRecovery = false,
  }) async {
    for (final entry in expectations.entries) {
      final messageId = entry.key;
      final sender = entry.value.sender;
      final recipients = entry.value.recipients;
      final expectedEpoch = entry.value.epoch;
      final expectedText = entry.value.text;

      for (final label in users.keys) {
        final matches = await messagesForId(label, messageId);
        expect(
          matches,
          hasLength(lessThanOrEqualTo(1)),
          reason: '${stateContext(op)} duplicate $messageId for $label',
        );

        final entitled = label == sender || recipients.contains(label);
        if (!entitled) {
          expect(
            matches,
            isEmpty,
            reason:
                '${stateContext(op)} out-of-window plaintext $messageId '
                'rendered for $label',
          );
          continue;
        }

        if (label == sender || finalRecovery || online.contains(label)) {
          expect(
            matches,
            hasLength(1),
            reason: '${stateContext(op)} entitled $label missing $messageId',
          );
          final message = matches.single;
          expect(message.text, expectedText, reason: stateContext(op));
          expect(
            message.keyGeneration,
            expectedEpoch,
            reason: stateContext(op),
          );
          expect(message.isIncoming, label != sender, reason: stateContext(op));
        }
      }
    }
  }

  Future<void> expectInvariants(String op, {bool finalRecovery = false}) async {
    for (final label in users.keys) {
      await expectMemberUniqueness(label, op);
    }
    for (final label in active.where(online.contains)) {
      await expectConvergedState(label, op);
    }
    await expectMessageInvariants(op, finalRecovery: finalRecovery);
    await expectHeldQueues(op, finalRecovery: finalRecovery);
  }

  Future<void> recoverOnline(String label, String op) async {
    if (!active.contains(label)) return;
    online.add(label);
    user(label).subscribeToGroup(groupId);
    await network.releaseHeldDeliveriesFor(
      user(label).peerId,
      reverse: random.nextBool(),
    );
    await pump();
    await waitUntil(() async {
      for (final entry in expectations.entries) {
        if (entry.value.recipients.contains(label) &&
            await messagesForId(label, entry.key).then((m) => m.length) != 1) {
          return false;
        }
      }
      return network.heldDeliveryCountFor(user(label).peerId) == 0;
    }, maxTicks: 50);
    await expectConvergedState(label, op);
  }

  Future<void> sendFrom(String label, String op) async {
    final messageIndex = expectations.length;
    final messageId = 'ge020-$seed-msg-$messageIndex';
    final text = 'GE-020 seed $seed epoch $currentEpoch message $messageIndex';
    final recipients = active.where((entry) => entry != label).toSet();
    final beforePublish = network.publishCallCount;
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: text,
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['success', 'successNoPeers']),
      reason: stateContext(op),
    );
    expect(sent, isNotNull, reason: stateContext(op));
    expect(sent!.keyGeneration, currentEpoch, reason: stateContext(op));
    expectations[messageId] = (
      sender: label,
      recipients: recipients,
      epoch: currentEpoch,
      text: text,
    );
    if (recipients.isNotEmpty) {
      expect(
        network.publishCallCount,
        greaterThan(beforePublish),
        reason: '${stateContext(op)} active send did not publish',
      );
    }

    await waitUntil(() async {
      for (final recipient in recipients.where(online.contains)) {
        if ((await messagesForId(recipient, messageId)).length != 1) {
          return false;
        }
      }
      return true;
    }, maxTicks: 50);
  }

  Future<void> inactiveSend(String label, String op) async {
    final messageId = 'ge020-$seed-inactive-${operationLog.length}';
    final beforePublish = network.publishCallCount;
    final beforeMessages = await messagesFor(label);
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: 'GE-020 inactive send must not publish',
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['groupNotFound', 'groupDissolved', 'unauthorized', 'error']),
      reason: stateContext(op),
    );
    expect(sent, isNull, reason: stateContext(op));
    expect(network.publishCallCount, beforePublish, reason: stateContext(op));
    expect(
      await messagesForId(label, messageId),
      isEmpty,
      reason: stateContext(op),
    );
    final afterMessages = await messagesFor(label);
    expect(
      afterMessages.map((message) => message.id).toSet(),
      beforeMessages.map((message) => message.id).toSet(),
      reason: '${stateContext(op)} inactive send mutated local messages',
    );
  }

  Future<void> addOrReadd(String label, String op) async {
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user(label), joinedAt: nextTime());
    active.add(label);
    online.add(label);
    await saveKeyFor(label);
    await user('A').broadcastMemberAdded(
      groupId: groupId,
      newMember: user(label),
      eventAt: nextTime(),
    );
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active.where(online.contains)) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        final memberPeerIds = members.map((member) => member.peerId).toSet();
        if (memberPeerIds.length != active.length ||
            memberPeerIds.difference(activePeerIds()).isNotEmpty) {
          return false;
        }
      }
      return true;
    }, maxTicks: 50);
    await saveKeyForActive();
  }

  Future<void> removeActive(String label, String op) async {
    if (!online.contains(label)) {
      await recoverOnline(label, '$op:pre-remove-recovery');
    }
    await user('A').removeMember(
      groupId: groupId,
      memberPeerId: user(label).peerId,
      memberUsername: user(label).username,
      removedAt: nextTime(),
    );
    active.remove(label);
    online.remove(label);
    await network.releaseHeldDeliveriesFor(user(label).peerId);
    await pump();
    await waitUntil(() async {
      for (final activeLabel in active.where(online.contains)) {
        final members = await user(activeLabel).groupRepo.getMembers(groupId);
        if (members.any((member) => member.peerId == user(label).peerId)) {
          return false;
        }
      }
      return true;
    }, maxTicks: 50);
  }

  Future<void> rotateKey(String op) async {
    currentEpoch++;
    user('A').bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'ge020-$seed-key-$currentEpoch',
      'keyEpoch': currentEpoch,
    };
    final targets = <String>[];
    final rotatedKey = await rotateAndDistributeGroupKey(
      bridge: user('A').bridge,
      groupRepo: user('A').groupRepo,
      groupId: groupId,
      selfPeerId: user('A').peerId,
      senderPublicKey: user('A').publicKey,
      senderPrivateKey: user('A').privateKey,
      senderUsername: user('A').username,
      sourceDeviceId: user('A').deviceId,
      sendP2PMessage: (peerId, _) async {
        targets.add(peerId);
        return true;
      },
    );
    expect(rotatedKey, isNotNull, reason: stateContext(op));
    expect(rotatedKey!.keyGeneration, currentEpoch, reason: stateContext(op));
    for (final label in active) {
      await user(label).groupRepo.saveKey(rotatedKey);
    }
    expect(
      targets.toSet(),
      active
          .where((label) => label != 'A')
          .map((label) => user(label).deviceId)
          .toSet(),
      reason: stateContext(op),
    );
  }

  Future<void> relayRefresh(String label, String op) async {
    if (!active.contains(label)) return;
    if (!online.contains(label)) {
      await recoverOnline(label, '$op:pre-refresh-recovery');
    }
    user(label).unsubscribeFromGroup(groupId);
    await rejoinGroupTopics(
      bridge: user(label).bridge,
      groupRepo: user(label).groupRepo,
    );
    user(label).subscribeToGroup(groupId);
    await pump();
    expect(
      network.isSubscribed(groupId, user(label).peerId),
      isTrue,
      reason: '${stateContext(op)} relay refresh did not rejoin $label',
    );
  }

  Future<void> restartActive(String label, String op) async {
    if (!online.contains(label)) {
      await recoverOnline(label, '$op:pre-restart-recovery');
    }
    users[label] = user(label).restartWithPersistedState();
    user(label).start();
    if (active.contains(label)) {
      user(label).subscribeToGroup(groupId);
      online.add(label);
    }
    await pump();
    await expectConvergedState(label, op);
  }

  Future<void> runOperation(String op) async {
    operationLog.add('$step:$op');
    switch (op) {
      case 'send':
        await sendFrom(active.elementAt(random.nextInt(active.length)), op);
        break;
      case 'offline':
        final candidates = active
            .where((label) => label != 'A' && online.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        final label = candidates[random.nextInt(candidates.length)];
        online.remove(label);
        network.holdDeliveriesFor(user(label).peerId);
        break;
      case 'online':
        final candidates = active
            .where((label) => !online.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await recoverOnline(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'relayRefresh':
        await relayRefresh(active.elementAt(random.nextInt(active.length)), op);
        break;
      case 'remove':
        final candidates = active.where((label) => label != 'A').toList();
        if (candidates.isEmpty) return;
        await removeActive(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'readd':
        final candidates = users.keys
            .where((label) => label != 'A' && !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await addOrReadd(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'inactiveSend':
        final candidates = users.keys
            .where((label) => !active.contains(label))
            .toList();
        if (candidates.isEmpty) return;
        await inactiveSend(candidates[random.nextInt(candidates.length)], op);
        break;
      case 'rotate':
        await rotateKey(op);
        break;
      case 'restart':
        await restartActive(
          active.elementAt(random.nextInt(active.length)),
          op,
        );
        break;
      case 'duplicateSend':
        network.duplicateOnDeliver = true;
        try {
          await sendFrom(active.elementAt(random.nextInt(active.length)), op);
        } finally {
          network.duplicateOnDeliver = false;
        }
        break;
      default:
        throw StateError('unknown GE-020 operation $op');
    }
    await pump();
    await expectInvariants(op);
  }

  try {
    await user('A').createGroup(
      groupId: groupId,
      name: 'GE-020 Seed $seed',
      createdAt: nextTime(),
    );
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('B'), joinedAt: nextTime());
    await user(
      'A',
    ).addMember(groupId: groupId, invitee: user('C'), joinedAt: nextTime());
    await mirrorAliceStateToActiveUsers();
    await saveKeyForActive();
    for (final label in users.keys) {
      user(label).start();
    }
    await expectInvariants('initial');

    final guaranteed = [
      'send',
      'offline',
      'send',
      'online',
      'relayRefresh',
      'rotate',
      'remove',
      'inactiveSend',
      'readd',
      'duplicateSend',
      'restart',
      'send',
    ];
    const randomOps = [
      'send',
      'offline',
      'online',
      'relayRefresh',
      'remove',
      'readd',
      'inactiveSend',
      'rotate',
      'restart',
      'duplicateSend',
    ];
    final operations = <String>[
      ...guaranteed,
      for (var index = guaranteed.length; index < operationCount; index++)
        randomOps[random.nextInt(randomOps.length)],
    ];

    for (final op in operations) {
      await runOperation(op);
    }

    for (final label in active.toList()) {
      if (!online.contains(label)) {
        await recoverOnline(label, 'final-recovery');
      }
    }
    await pump();
    await expectInvariants('final-recovery', finalRecovery: true);
    for (final label in active) {
      await expectConvergedState(label, 'final-recovery');
      expect(
        network.heldDeliveryCountFor(user(label).peerId),
        0,
        reason: stateContext('final-recovery'),
      );
    }
  } finally {
    await cleanup();
  }
}

Future<void> _runGe021LargeGroupFlakyMember(
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  const groupId = 'group-ge021-large-flaky';
  const keyEpoch = 1;
  const flakyLabel = 'K';
  const labels = <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
  ];
  const stableLabels = <String>[
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
  ];
  const usernames = <String, String>{
    'A': 'Alice',
    'B': 'Bob',
    'C': 'Charlie',
    'D': 'Dana',
    'E': 'Erin',
    'F': 'Frank',
    'G': 'Grace',
    'H': 'Heidi',
    'I': 'Ivan',
    'J': 'Judy',
    'K': 'Kira',
  };
  final baseTime = DateTime.utc(2026, 5, 13, 21, 21);
  var step = 0;
  var cleanedUp = false;
  final expectedMessages = <String, ({String sender, String text})>{};

  DateTime nextTime() => baseTime.add(Duration(seconds: step++));

  final users = <String, GroupTestUser>{
    for (final label in labels)
      label: GroupTestUser.create(
        peerId: 'ge021-${label.toLowerCase()}-peer',
        username: usernames[label]!,
        network: network,
      ),
  };

  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    for (final user in users.values) {
      user.dispose();
    }
  }

  addTearDown(cleanup);

  GroupTestUser user(String label) => users[label]!;

  String stateContext(String op) {
    return 'GE-021 op=$op step=$step expected=${expectedMessages.keys.toList()}';
  }

  Future<void> saveKeyFor(String label) {
    return user(label).groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: keyEpoch,
        encryptedKey: 'ge021-shared-key',
        createdAt: nextTime(),
      ),
    );
  }

  Future<void> saveKeyForAll() async {
    for (final label in labels) {
      await saveKeyFor(label);
    }
  }

  Future<void> mirrorAliceStateToAll() async {
    final sourceGroup = (await user('A').groupRepo.getGroup(groupId))!;
    final sourceMembers = await user('A').groupRepo.getMembers(groupId);
    for (final label in labels) {
      await user(label).groupRepo.saveGroup(
        sourceGroup.copyWith(
          myRole: label == 'A' ? GroupRole.admin : GroupRole.member,
        ),
      );
      for (final member in sourceMembers) {
        await user(label).groupRepo.saveMember(member);
      }
    }
  }

  Future<int> messageCount(String label, String messageId) async {
    return (await user(label).loadGroupMessages(
      groupId,
    )).where((message) => message.id == messageId).length;
  }

  Future<void> expectStableMembers(
    Set<String> expectedPeerIds,
    String op,
  ) async {
    await waitUntil(() async {
      for (final label in stableLabels) {
        final memberPeerIds = (await user(
          label,
        ).groupRepo.getMembers(groupId)).map((member) => member.peerId).toSet();
        if (memberPeerIds.length != expectedPeerIds.length ||
            memberPeerIds.difference(expectedPeerIds).isNotEmpty) {
          return false;
        }
      }
      return true;
    }, maxTicks: 60);
    for (final label in stableLabels) {
      final memberPeerIds = (await user(
        label,
      ).groupRepo.getMembers(groupId)).map((member) => member.peerId).toList();
      expect(
        memberPeerIds.toSet(),
        hasLength(memberPeerIds.length),
        reason: '${stateContext(op)} duplicate member rows for $label',
      );
    }
  }

  Future<void> expectStableDelivery(String op) async {
    await waitUntil(() async {
      for (final entry in expectedMessages.entries) {
        for (final label in stableLabels) {
          if (label == entry.value.sender) continue;
          if (await messageCount(label, entry.key) != 1) {
            return false;
          }
        }
      }
      return true;
    }, maxTicks: 80);

    for (final entry in expectedMessages.entries) {
      for (final label in stableLabels) {
        final count = await messageCount(label, entry.key);
        expect(
          count,
          lessThanOrEqualTo(1),
          reason: '${stateContext(op)} duplicate ${entry.key} for $label',
        );
        if (label == entry.value.sender) {
          expect(
            count,
            1,
            reason:
                '${stateContext(op)} stable sender $label missing ${entry.key}',
          );
        } else {
          expect(
            count,
            1,
            reason:
                '${stateContext(op)} stable recipient $label missing '
                '${entry.key}',
          );
        }
      }
    }
  }

  Future<void> sendFrom(String label, String key) async {
    final messageId = 'ge021-$key';
    final text = 'GE-021 $key from $label';
    final beforePublish = network.publishCallCount;
    final (result, sent) = await user(label).sendGroupMessageViaBridge(
      groupId: groupId,
      text: text,
      messageId: messageId,
      timestamp: nextTime(),
    );
    expect(
      result.name,
      isIn(['success', 'successNoPeers']),
      reason: stateContext(key),
    );
    expect(sent, isNotNull, reason: stateContext(key));
    expect(
      network.publishCallCount,
      greaterThan(beforePublish),
      reason: '${stateContext(key)} send did not publish',
    );
    expectedMessages[messageId] = (sender: label, text: text);
    await expectStableDelivery(key);
  }

  try {
    await user('A').createGroup(
      groupId: groupId,
      name: 'GE-021 Large Private Group',
      createdAt: nextTime(),
    );
    for (final label in labels.where((label) => label != 'A')) {
      await user(
        'A',
      ).addMember(groupId: groupId, invitee: user(label), joinedAt: nextTime());
    }
    await mirrorAliceStateToAll();
    await saveKeyForAll();
    for (final label in labels) {
      user(label).start();
    }

    final allPeerIds = labels.map((label) => user(label).peerId).toSet();
    final stablePeerIds = stableLabels
        .map((label) => user(label).peerId)
        .toSet();
    expect(allPeerIds, hasLength(11), reason: 'GE-021 requires 10+ members');
    await expectStableMembers(allPeerIds, 'initial-large-roster');

    await sendFrom('A', 'alice-initial');
    await sendFrom('B', 'bob-initial');
    await sendFrom('D', 'dana-initial');

    network.holdDeliveriesFor(user(flakyLabel).peerId);
    await sendFrom('C', 'charlie-while-flaky-held');
    await sendFrom('E', 'erin-while-flaky-held');
    expect(
      network.heldDeliveryCountFor(user(flakyLabel).peerId),
      greaterThan(0),
      reason:
          'flaky member should have delayed work while stable peers proceed',
    );
    await network.releaseHeldDeliveriesFor(
      user(flakyLabel).peerId,
      reverse: true,
    );
    await pump();
    expect(network.heldDeliveryCountFor(user(flakyLabel).peerId), 0);

    await user('A').removeMember(
      groupId: groupId,
      memberPeerId: user(flakyLabel).peerId,
      memberUsername: user(flakyLabel).username,
      removedAt: nextTime(),
    );
    await pump();
    await expectStableMembers(stablePeerIds, 'flaky-removed');
    await sendFrom('F', 'frank-after-flaky-removed');

    await user('A').addMember(
      groupId: groupId,
      invitee: user(flakyLabel),
      joinedAt: nextTime(),
    );
    await saveKeyFor(flakyLabel);
    await user('A').broadcastMemberAdded(
      groupId: groupId,
      newMember: user(flakyLabel),
      eventAt: nextTime(),
    );
    await pump();
    await expectStableMembers(allPeerIds, 'flaky-readded');
    await saveKeyForAll();
    await sendFrom(flakyLabel, 'flaky-after-readd');

    user(flakyLabel).unsubscribeFromGroup(groupId);
    network.holdDeliveriesFor(user(flakyLabel).peerId);
    await sendFrom('G', 'grace-while-flaky-offline-again');
    await sendFrom('H', 'heidi-while-flaky-offline-again');
    user(flakyLabel).subscribeToGroup(groupId);
    await network.releaseHeldDeliveriesFor(user(flakyLabel).peerId);
    await pump();
    await sendFrom('I', 'ivan-after-flaky-online');

    await expectStableDelivery('final-stable-delivery');
    await expectStableMembers(allPeerIds, 'final-large-roster');
    for (final label in stableLabels) {
      expect(
        network.isSubscribed(groupId, user(label).peerId),
        isTrue,
        reason: '${stateContext('final')} stable member $label lost topic',
      );
    }
  } finally {
    await cleanup();
  }
}

Future<void> _runGe023MediaReaddEntitlement(
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  const groupId = 'ge023-media-readd-group';
  const validContentHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  var tick = 0;
  DateTime nextTime() =>
      DateTime.utc(2026, 5, 13, 22, 23).add(Duration(seconds: tick++));

  final alice = GroupTestUser.create(
    peerId: 'ge023-alice-peer',
    username: 'Alice',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'ge023-bob-peer',
    username: 'Bob',
    network: network,
  );
  final charlie = GroupTestUser.create(
    peerId: 'ge023-charlie-peer',
    username: 'Charlie',
    network: network,
  );
  final users = <GroupTestUser>[alice, bob, charlie];

  Future<void> saveMediaKeyFor(GroupTestUser user) async {
    await user.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'ge023-media-test-key',
        createdAt: DateTime.utc(2026, 5, 13, 22, 22),
      ),
    );
  }

  MediaAttachment mediaAttachment({
    required String id,
    required String messageId,
    required DateTime createdAt,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 2048,
      mediaType: 'image',
      width: 1200,
      height: 800,
      localPath: '/tmp/$id.jpg',
      downloadStatus: 'done',
      createdAt: createdAt.toIso8601String(),
      contentHash: validContentHash,
      encryptionKeyBase64: 'Z2UwMjMtbWVkaWEta2V5LTAwMDAwMDAwMDA=',
      encryptionNonce: 'Z2UwMjMtbm9uY2UtMDAwMDAwMDAwMDA=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
  }

  Future<void> sendMedia({
    required GroupTestUser sender,
    required String messageId,
    required String text,
    required String attachmentId,
  }) async {
    final sentAt = nextTime();
    final (result, sent) = await sender.sendGroupMessageViaBridge(
      groupId: groupId,
      text: text,
      messageId: messageId,
      timestamp: sentAt,
      mediaAttachments: <MediaAttachment>[
        mediaAttachment(
          id: attachmentId,
          messageId: messageId,
          createdAt: sentAt,
        ),
      ],
    );
    expect(result.name, isIn(['success', 'successNoPeers']));
    expect(sent?.id, messageId);
  }

  Future<void> expectMediaVisible({
    required GroupTestUser user,
    required String messageId,
    required String attachmentId,
    required bool isIncoming,
    required bool localContentAvailable,
  }) async {
    await waitUntil(() async {
      final messages = await user.loadGroupMessages(groupId);
      final matchingMessages = messages
          .where((message) => message.id == messageId)
          .toList();
      if (matchingMessages.length != 1) return false;
      final attachments = await user.mediaAttachmentRepo
          .getAttachmentsForMessage(messageId);
      return attachments.length == 1 && attachments.single.id == attachmentId;
    }, maxTicks: 80);

    final messages = await user.loadGroupMessages(groupId);
    final message = messages.singleWhere((message) => message.id == messageId);
    final attachments = await user.mediaAttachmentRepo.getAttachmentsForMessage(
      messageId,
    );
    final attachment = attachments.single;
    expect(message.isIncoming, isIncoming);
    expect(attachment.id, attachmentId);
    expect(attachment.mime, 'image/jpeg');
    expect(attachment.mediaType, 'image');
    expect(attachment.size, 2048);
    expect(attachment.width, 1200);
    expect(attachment.height, 800);
    expect(attachment.contentHash, validContentHash);
    expect(attachment.hasEncryptionMetadata, isTrue);
    if (localContentAvailable) {
      expect(attachment.downloadStatus, 'done');
      expect(attachment.localPath, isNotNull);
    }
  }

  Future<void> expectMediaAbsent({
    required GroupTestUser user,
    required String messageId,
  }) async {
    await pump();
    final messages = await user.loadGroupMessages(groupId);
    expect(
      messages.where((message) => message.id == messageId),
      isEmpty,
      reason: '${user.username} must not receive removed-window media',
    );
    expect(
      await user.mediaAttachmentRepo.getAttachmentsForMessage(messageId),
      isEmpty,
      reason: '${user.username} must not persist removed-window media',
    );
  }

  try {
    await alice.createGroup(
      groupId: groupId,
      name: 'GE-023 Media Entitlement',
      createdAt: nextTime(),
    );
    await alice.addMember(groupId: groupId, invitee: bob, joinedAt: nextTime());

    alice.start();
    bob.start();
    charlie.start();

    await alice.addMember(
      groupId: groupId,
      invitee: charlie,
      joinedAt: nextTime(),
    );
    await alice.broadcastMemberAdded(
      groupId: groupId,
      newMember: charlie,
      eventAt: nextTime(),
    );
    final latestKey = await alice.groupRepo.getLatestKey(groupId);
    if (latestKey != null) {
      await charlie.groupRepo.saveKey(latestKey);
    }
    for (final user in users) {
      await saveMediaKeyFor(user);
    }
    await pump();

    await sendMedia(
      sender: alice,
      messageId: 'ge023-before-removal',
      text: 'GE-023 media before removal',
      attachmentId: 'ge023-media-before',
    );
    await expectMediaVisible(
      user: alice,
      messageId: 'ge023-before-removal',
      attachmentId: 'ge023-media-before',
      isIncoming: false,
      localContentAvailable: true,
    );
    await expectMediaVisible(
      user: bob,
      messageId: 'ge023-before-removal',
      attachmentId: 'ge023-media-before',
      isIncoming: true,
      localContentAvailable: false,
    );
    await expectMediaVisible(
      user: charlie,
      messageId: 'ge023-before-removal',
      attachmentId: 'ge023-media-before',
      isIncoming: true,
      localContentAvailable: false,
    );

    await alice.removeMember(
      groupId: groupId,
      memberPeerId: charlie.peerId,
      memberUsername: charlie.username,
      removedAt: nextTime(),
    );
    await pump();

    await sendMedia(
      sender: alice,
      messageId: 'ge023-removed-window',
      text: 'GE-023 media while Charlie removed',
      attachmentId: 'ge023-media-removed-window',
    );
    await expectMediaVisible(
      user: alice,
      messageId: 'ge023-removed-window',
      attachmentId: 'ge023-media-removed-window',
      isIncoming: false,
      localContentAvailable: true,
    );
    await expectMediaVisible(
      user: bob,
      messageId: 'ge023-removed-window',
      attachmentId: 'ge023-media-removed-window',
      isIncoming: true,
      localContentAvailable: false,
    );
    await expectMediaAbsent(user: charlie, messageId: 'ge023-removed-window');

    await alice.addMember(
      groupId: groupId,
      invitee: charlie,
      joinedAt: nextTime(),
    );
    await alice.broadcastMemberAdded(
      groupId: groupId,
      newMember: charlie,
      eventAt: nextTime(),
    );
    final readdKey = await alice.groupRepo.getLatestKey(groupId);
    if (readdKey != null) {
      await charlie.groupRepo.saveKey(readdKey);
    }
    await saveMediaKeyFor(charlie);
    await pump();

    await sendMedia(
      sender: charlie,
      messageId: 'ge023-after-readd',
      text: 'GE-023 media after Charlie re-add',
      attachmentId: 'ge023-media-after-readd',
    );
    await expectMediaVisible(
      user: charlie,
      messageId: 'ge023-after-readd',
      attachmentId: 'ge023-media-after-readd',
      isIncoming: false,
      localContentAvailable: true,
    );
    await expectMediaVisible(
      user: alice,
      messageId: 'ge023-after-readd',
      attachmentId: 'ge023-media-after-readd',
      isIncoming: true,
      localContentAvailable: false,
    );
    await expectMediaVisible(
      user: bob,
      messageId: 'ge023-after-readd',
      attachmentId: 'ge023-media-after-readd',
      isIncoming: true,
      localContentAvailable: false,
    );

    await expectMediaAbsent(user: charlie, messageId: 'ge023-removed-window');
  } finally {
    for (final user in users) {
      user.dispose();
    }
  }
}

Future<void> _runGe024QuotedRepliesAcrossBoundary(
  FakeGroupPubSubNetwork network,
  Future<void> Function() pump,
  Future<void> Function(Future<bool> Function() condition, {int maxTicks})
  waitUntil,
) async {
  const groupId = 'ge024-quoted-boundary-group';
  var tick = 0;
  DateTime nextTime() =>
      DateTime.utc(2026, 5, 14, 0, 24).add(Duration(seconds: tick++));

  final alice = GroupTestUser.create(
    peerId: 'ge024-alice-peer',
    username: 'Alice',
    network: network,
  );
  final bob = GroupTestUser.create(
    peerId: 'ge024-bob-peer',
    username: 'Bob',
    network: network,
  );
  final charlie = GroupTestUser.create(
    peerId: 'ge024-charlie-peer',
    username: 'Charlie',
    network: network,
  );
  final users = <GroupTestUser>[alice, bob, charlie];

  Future<void> saveBoundaryKeyFor(GroupTestUser user) {
    return user.groupRepo.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'ge024-quoted-boundary-key',
        createdAt: DateTime.utc(2026, 5, 14, 0, 23),
      ),
    );
  }

  Future<GroupMessage> sendBridgeMessage({
    required GroupTestUser sender,
    required String messageId,
    required String text,
    String? quotedMessageId,
  }) async {
    final (result, message) = await sender.sendGroupMessageViaBridge(
      groupId: groupId,
      text: text,
      messageId: messageId,
      timestamp: nextTime(),
      quotedMessageId: quotedMessageId,
    );
    expect(result.name, isIn(['success', 'successNoPeers']));
    expect(message, isNotNull);
    expect(message!.quotedMessageId, quotedMessageId);
    return message;
  }

  Future<GroupMessage> expectMessage({
    required GroupTestUser user,
    required String messageId,
    String? quotedMessageId,
  }) async {
    await waitUntil(() async {
      final messages = await user.loadGroupMessages(groupId);
      return messages.where((message) => message.id == messageId).length == 1;
    }, maxTicks: 80);
    final messages = await user.loadGroupMessages(groupId);
    final message = messages.singleWhere((message) => message.id == messageId);
    expect(message.quotedMessageId, quotedMessageId);
    return message;
  }

  Future<void> expectAbsent({
    required GroupTestUser user,
    required String messageId,
  }) async {
    await pump();
    final messages = await user.loadGroupMessages(groupId);
    expect(
      messages.where((message) => message.id == messageId),
      isEmpty,
      reason: '${user.username} must not persist unavailable quote parent',
    );
  }

  try {
    await alice.createGroup(
      groupId: groupId,
      name: 'GE-024 Quoted Boundary',
      createdAt: nextTime(),
    );
    await alice.addMember(groupId: groupId, invitee: bob, joinedAt: nextTime());
    await alice.addMember(
      groupId: groupId,
      invitee: charlie,
      joinedAt: nextTime(),
    );

    alice.start();
    bob.start();
    charlie.start();
    for (final user in users) {
      await saveBoundaryKeyFor(user);
    }
    await pump();

    final beforeParent = await sendBridgeMessage(
      sender: alice,
      messageId: 'ge024-before-parent',
      text: 'GE-024 parent before Charlie removal',
    );
    await expectMessage(user: bob, messageId: beforeParent.id);
    await expectMessage(user: charlie, messageId: beforeParent.id);

    await alice.removeMember(
      groupId: groupId,
      memberPeerId: charlie.peerId,
      memberUsername: charlie.username,
      removedAt: nextTime(),
    );
    await pump();

    final removedParent = await sendBridgeMessage(
      sender: alice,
      messageId: 'ge024-removed-parent',
      text: 'GE-024 parent while Charlie removed',
    );
    await expectMessage(user: bob, messageId: removedParent.id);
    await expectAbsent(user: charlie, messageId: removedParent.id);

    await alice.addMember(
      groupId: groupId,
      invitee: charlie,
      joinedAt: nextTime(),
    );
    await alice.broadcastMemberAdded(
      groupId: groupId,
      newMember: charlie,
      eventAt: nextTime(),
    );
    final readdKey = await alice.groupRepo.getLatestKey(groupId);
    if (readdKey != null) {
      await charlie.groupRepo.saveKey(readdKey);
    }
    await saveBoundaryKeyFor(charlie);
    await pump();

    final availableReply = await sendBridgeMessage(
      sender: bob,
      messageId: 'ge024-reply-available',
      text: 'GE-024 reply to available parent',
      quotedMessageId: beforeParent.id,
    );
    final unavailableReply = await sendBridgeMessage(
      sender: bob,
      messageId: 'ge024-reply-unavailable',
      text: 'GE-024 reply to unavailable parent',
      quotedMessageId: removedParent.id,
    );

    await expectMessage(
      user: alice,
      messageId: availableReply.id,
      quotedMessageId: beforeParent.id,
    );
    await expectMessage(
      user: alice,
      messageId: unavailableReply.id,
      quotedMessageId: removedParent.id,
    );
    await expectMessage(
      user: charlie,
      messageId: availableReply.id,
      quotedMessageId: beforeParent.id,
    );
    await expectMessage(
      user: charlie,
      messageId: unavailableReply.id,
      quotedMessageId: removedParent.id,
    );
    await expectAbsent(user: charlie, messageId: removedParent.id);

    final charlieMessages = await charlie.loadGroupMessages(groupId);
    expect(
      charlieMessages.where((message) => message.id == beforeParent.id),
      hasLength(1),
      reason: 'Charlie should retain entitled quote parent from before removal',
    );
    expect(
      charlieMessages.where((message) => message.id == removedParent.id),
      isEmpty,
      reason:
          'Charlie should render the quote as unavailable without receiving '
          'the removed-window parent',
    );
  } finally {
    for (final user in users) {
      user.dispose();
    }
  }
}

class _InMemoryGroupInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> _attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    _attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return _attempts[_key(groupId, peerId)];
  }

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async {
    return _attempts.entries
        .where((entry) => entry.key.startsWith('$groupId::'))
        .map((entry) => entry.value)
        .toList(growable: false);
  }

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async {
    return _attempts[_key(groupId, peerId)]?.status ??
        GroupInviteDeliveryStatus.unknown;
  }

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async {
    return {
      for (final attempt in await getAttemptsForGroup(groupId))
        attempt.peerId: attempt.status,
    };
  }

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final existing = _attempts[_key(groupId, peerId)];
    _attempts[_key(groupId, peerId)] =
        existing?.copyWith(status: status, updatedAt: now) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          status: status,
          attemptedAt: now,
          updatedAt: now,
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
    final existing = _attempts[_key(groupId, peerId)];
    _attempts[_key(groupId, peerId)] =
        existing?.copyWith(
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          updatedAt: now,
          clearLastError: true,
        ) ??
        GroupInviteDeliveryAttempt(
          groupId: groupId,
          peerId: peerId,
          username: username,
          status: GroupInviteDeliveryStatus.joined,
          attemptedAt: now,
          updatedAt: now,
        );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async {
    return _attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;
  }

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = _attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      _attempts.remove(key);
    }
    return keys.length;
  }
}
