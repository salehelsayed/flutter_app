import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_sender_display_name.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/record_group_invite_delivery_attempts.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_key_repair.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_key_repair_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';
import '../../../shared/fakes/in_memory_pending_group_invite_repository.dart';

class _SmokeInMemoryGroupPendingKeyRepairRepository
    implements GroupPendingKeyRepairRepository {
  final Map<String, GroupPendingKeyRepair> repairs = {};

  @override
  Future<GroupPendingKeyRepairUpsertResult> upsertPendingRepair(
    GroupPendingKeyRepair repair,
  ) async {
    final existing = repairs[repair.id];
    if (existing == null) {
      repairs[repair.id] = repair;
      return GroupPendingKeyRepairUpsertResult(repair: repair, created: true);
    }
    final merged = existing.copyWith(
      senderPeerId: repair.senderPeerId,
      transportPeerId: repair.transportPeerId,
      replayEnvelopeJson:
          existing.replayEnvelopeJson ?? repair.replayEnvelopeJson,
      lastError: repair.lastError,
      updatedAt: repair.updatedAt,
    );
    repairs[repair.id] = merged;
    return GroupPendingKeyRepairUpsertResult(repair: merged, created: false);
  }

  @override
  Future<GroupPendingKeyRepair?> getRepair(String id) async => repairs[id];

  @override
  Future<List<GroupPendingKeyRepair>> getPendingRepairsForGroupEpoch({
    required String groupId,
    required int keyEpoch,
    int limit = 50,
  }) async {
    final pending =
        repairs.values
            .where(
              (repair) =>
                  repair.groupId == groupId &&
                  repair.keyEpoch == keyEpoch &&
                  repair.status == groupPendingKeyRepairStatusPendingKey,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending.take(limit).toList(growable: false);
  }

  @override
  Future<void> recordAttempt(String id, {required String? lastError}) async {
    final existing = repairs[id];
    if (existing == null) return;
    repairs[id] = existing.copyWith(
      attempts: existing.attempts + 1,
      lastError: lastError,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> finalizeRepaired(String id) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusRepaired,
      updatedAt: now,
      finalizedAt: now,
    );
  }

  @override
  Future<void> finalizeUndecryptable(
    String id, {
    required String lastError,
  }) async {
    final existing = repairs[id];
    if (existing == null || existing.finalizedAt != null) return;
    final now = DateTime.now().toUtc();
    repairs[id] = existing.copyWith(
      status: groupPendingKeyRepairStatusUndecryptable,
      lastError: lastError,
      updatedAt: now,
      finalizedAt: now,
    );
  }
}

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

    test('DE-006 full live fanout remains sent not delivered', () async {
      final alice = GroupTestUser.create(
        peerId: 'de006-alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'de006-bob-peer',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'de006-charlie-peer',
        username: 'Charlie',
        network: network,
      );
      addTearDown(() {
        alice.dispose();
        bob.dispose();
        charlie.dispose();
      });

      const groupId = 'group-de006-full-fanout';
      const messageId = 'de006-full-live-fanout';
      const text = 'DE-006 full fanout proof';
      await alice.createGroup(groupId: groupId, name: 'DE-006 Full Fanout');
      await alice.addMember(groupId: groupId, invitee: bob);
      await alice.addMember(groupId: groupId, invitee: charlie);

      Future<void> saveKey(GroupTestUser user) async {
        await user.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'de006-key',
            createdAt: DateTime.utc(2026, 5, 11, 8),
          ),
        );
      }

      await Future.wait([saveKey(alice), saveKey(bob), saveKey(charlie)]);

      alice.start();
      bob.start();
      charlie.start();

      final (result, sent) = await alice.sendGroupMessageViaBridge(
        groupId: groupId,
        text: text,
        messageId: messageId,
      );
      expect(result.name, 'success');
      expect(sent, isNotNull);
      expect(sent!.status, 'sent');
      expect(sent.status, isNot('delivered'));

      await pump();
      final bobMessages = await bob.loadGroupMessages(groupId);
      final charlieMessages = await charlie.loadGroupMessages(groupId);
      expect(
        bobMessages.where((message) => message.text == text),
        hasLength(1),
      );
      expect(
        charlieMessages.where((message) => message.text == text),
        hasLength(1),
      );

      final saved = await alice.msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.status, isNot('delivered'));
      expect(
        await alice.msgRepo.getReceiptsForMessage(
          groupId,
          messageId,
          receiptType: groupMessageReceiptTypeDelivered,
        ),
        isEmpty,
      );
      expect(
        await alice.msgRepo.getReceiptsForMessage(
          groupId,
          messageId,
          receiptType: groupMessageReceiptTypeRead,
        ),
        isEmpty,
      );
    });

    test(
      'UP-013 route-unmounted recipient persists incoming message for reopen',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'up013-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'up013-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-up013-route-away';
        await alice.createGroup(groupId: groupId, name: 'UP-013 Route Away');
        await alice.addMember(groupId: groupId, invitee: bob);

        // Bob's app-level listener stays running while no conversation route is
        // mounted, which is the production shape for a user on another route.
        alice.start();
        bob.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'UP-013 message while Bob route is unmounted',
          messageId: 'up013-route-away-smoke',
          timestamp: DateTime.utc(2026, 5, 14, 0, 13),
        );
        await pump();

        final persisted = await bob.msgRepo.getMessage(
          'up013-route-away-smoke',
        );
        expect(persisted, isNotNull);
        expect(persisted!.isIncoming, isTrue);
        expect(persisted.text, 'UP-013 message while Bob route is unmounted');

        final reopenedMessages = await bob.loadGroupMessages(groupId);
        expect(
          reopenedMessages
              .where((message) => message.id == 'up013-route-away-smoke')
              .toList(),
          hasLength(1),
        );
      },
    );

    test(
      'SV-001 never-member fake-network publish is rejected by all recipients',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'sv001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv001-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'sv001-dana-never-member',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-sv001-never-member';
        await alice.createGroup(groupId: groupId, name: 'SV-001 Private ABC');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        await network.publish(groupId, dana.peerId, {
          'groupId': groupId,
          'senderId': dana.peerId,
          'senderUsername': dana.username,
          'keyEpoch': 1,
          'text': 'SV-001 forged never-member message',
          'timestamp': DateTime.utc(2026, 5, 14, 1, 1).toIso8601String(),
          'messageId': 'sv001-forged-never-member',
          'transportPeerId': dana.deviceId,
        }, senderDeviceId: dana.deviceId);
        await pump();

        for (final recipient in [alice, bob, charlie]) {
          expect(
            await recipient.msgRepo.getMessage('sv001-forged-never-member'),
            isNull,
            reason: '${recipient.username} must not persist Dana injection',
          );
          expect(
            (await recipient.loadGroupMessages(
              groupId,
            )).where((message) => message.senderPeerId == dana.peerId).toList(),
            isEmpty,
            reason: '${recipient.username} must not render Dana injection',
          );
        }
        expect(
          network.deliveryRecords
              .where(
                (record) =>
                    record['messageId'] == 'sv001-forged-never-member' &&
                    record['senderPeerId'] == dana.peerId,
              )
              .toList(),
          hasLength(3),
        );
      },
    );

    test(
      'SV-011 valid-key nonmember fake-network publish is rejected by all recipients',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'sv011-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv011-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv011-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'sv011-dana-key-holder',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-sv011-valid-key-nonmember';
        const messageId = 'sv011-valid-key-nonmember-injection';
        final createdAt = DateTime.utc(2026, 5, 14, 4, 5);
        final group = await alice.createGroup(
          groupId: groupId,
          name: 'SV-011 Private ABC',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 2)),
        );
        await pump();

        Future<void> saveCurrentKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'sv011-current-shared-key',
              createdAt: createdAt.add(const Duration(minutes: 1)),
            ),
          );
        }

        await Future.wait([
          saveCurrentKey(alice),
          saveCurrentKey(bob),
          saveCurrentKey(charlie),
        ]);
        await dana.groupRepo.saveGroup(
          group.copyWith(myRole: GroupRole.member),
        );
        await saveCurrentKey(dana);
        dana.subscribeToGroup(groupId);
        expect((await dana.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);

        for (final recipient in [alice, bob, charlie]) {
          final members = await recipient.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            isNot(contains(dana.peerId)),
            reason: '${recipient.username} active config excludes Dana',
          );
        }

        await network.publish(groupId, dana.peerId, {
          'groupId': groupId,
          'senderId': dana.peerId,
          'senderUsername': dana.username,
          'keyEpoch': 1,
          'text': 'SV-011 Dana has key but is not a member',
          'timestamp': createdAt
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          'messageId': messageId,
          'transportPeerId': dana.deviceId,
        }, senderDeviceId: dana.deviceId);
        await pump();

        for (final recipient in [alice, bob, charlie]) {
          expect(
            await recipient.msgRepo.getMessage(messageId),
            isNull,
            reason:
                '${recipient.username} must not persist valid-key nonmember traffic',
          );
          expect(
            (await recipient.loadGroupMessages(groupId))
                .where(
                  (message) =>
                      message.id == messageId ||
                      message.senderPeerId == dana.peerId,
                )
                .toList(),
            isEmpty,
            reason:
                '${recipient.username} must not render valid-key nonmember traffic',
          );
        }
        expect(
          flowEvents
              .where(
                (event) =>
                    event['event'] ==
                        'GROUP_HANDLE_INCOMING_MSG_UNKNOWN_SENDER_REJECTED' &&
                    (event['details'] as Map<String, dynamic>)['keyEpoch'] == 1,
              )
              .length,
          greaterThanOrEqualTo(3),
        );
        expect(
          network.deliveryRecords
              .where(
                (record) =>
                    record['messageId'] == messageId &&
                    record['senderPeerId'] == dana.peerId,
              )
              .toList(),
          hasLength(3),
        );
      },
    );

    test(
      'SV-004 forged sender identity is rejected by all fake-network recipients',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'sv004-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv004-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv004-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'sv004-dana-attacker',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-sv004-forged-sender';
        const forgedMessageId = 'sv004-forged-bob-from-dana-device';
        await alice.createGroup(groupId: groupId, name: 'SV-004 Private ABC');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': bob.username,
          'keyEpoch': 1,
          'text': 'SV-004 forged Bob message from Dana device',
          'timestamp': DateTime.utc(2026, 5, 14, 4, 34).toIso8601String(),
          'messageId': forgedMessageId,
          'senderDeviceId': dana.deviceId,
          'transportPeerId': dana.deviceId,
        }, senderDeviceId: dana.deviceId);
        await pump();

        for (final recipient in [alice, bob, charlie]) {
          expect(
            await recipient.msgRepo.getMessage(forgedMessageId),
            isNull,
            reason: '${recipient.username} must not persist forged Bob traffic',
          );
          expect(
            (await recipient.loadGroupMessages(groupId))
                .where(
                  (message) =>
                      message.id == forgedMessageId ||
                      message.text ==
                          'SV-004 forged Bob message from Dana device',
                )
                .toList(),
            isEmpty,
            reason: '${recipient.username} must not render forged Bob traffic',
          );
        }
        expect(
          flowEvents
              .where(
                (event) =>
                    event['event'] ==
                    'GROUP_HANDLE_INCOMING_MSG_UNBOUND_DEVICE_REJECTED',
              )
              .length,
          greaterThanOrEqualTo(3),
        );
        expect(
          network.deliveryRecords
              .where(
                (record) =>
                    record['messageId'] == forgedMessageId &&
                    record['senderPeerId'] == bob.peerId &&
                    record['senderDeviceId'] == dana.deviceId,
              )
              .toList(),
          hasLength(3),
        );
      },
    );

    test(
      'SV-002 removed old-key publish reaches listeners without timeline unread or reaction mutation',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final aliceReactions = FakeReactionRepository();
        final bobReactions = FakeReactionRepository();
        final alice = GroupTestUser.create(
          peerId: 'sv002-alice-peer',
          username: 'Alice',
          network: network,
          reactionRepo: aliceReactions,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv002-bob-peer',
          username: 'Bob',
          network: network,
          reactionRepo: bobReactions,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv002-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-sv002-removed-old-key';
        const targetId = 'sv002-target-before-removal';
        const staleMessageId = 'sv002-charlie-old-key-message';
        const staleReactionId = 'sv002-charlie-old-key-reaction';
        const staleText = 'SV-002 Charlie removed old-key publish';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
          DateTime createdAt,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'SV-002 Removed Old Key',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await Future.wait([
          saveKey(alice, 1, 'sv002-old-key', createdAt),
          saveKey(bob, 1, 'sv002-old-key', createdAt),
          saveKey(charlie, 1, 'sv002-old-key', createdAt),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'SV-002 target before removal',
          messageId: targetId,
          timestamp: createdAt.add(const Duration(minutes: 1)),
        );
        await pump();
        expect(await bob.msgRepo.getMessage(targetId), isNotNull);
        expect(await charlie.msgRepo.getMessage(targetId), isNotNull);

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await pump();
        await Future.wait([
          saveKey(
            alice,
            2,
            'sv002-current-key',
            createdAt.add(const Duration(minutes: 3)),
          ),
          saveKey(
            bob,
            2,
            'sv002-current-key',
            createdAt.add(const Duration(minutes: 3)),
          ),
        ]);

        final aliceUnreadBefore = await alice.msgRepo.getUnreadCount(groupId);
        final bobUnreadBefore = await bob.msgRepo.getUnreadCount(groupId);

        await network.publish(groupId, charlie.peerId, <String, dynamic>{
          'groupId': groupId,
          'senderId': charlie.peerId,
          'senderUsername': charlie.username,
          'keyEpoch': 1,
          'text': staleText,
          'timestamp': createdAt
              .add(const Duration(minutes: 4))
              .toIso8601String(),
          'messageId': staleMessageId,
          'transportPeerId': charlie.deviceId,
        }, senderDeviceId: charlie.deviceId);
        await network.publishReaction(
          groupId,
          charlie.peerId,
          <String, dynamic>{
            'groupId': groupId,
            'senderId': charlie.peerId,
            'transportPeerId': charlie.deviceId,
            'reaction': jsonEncode({
              'id': staleReactionId,
              'messageId': targetId,
              'emoji': '🔥',
              'action': 'add',
              'senderPeerId': charlie.peerId,
              'timestamp': createdAt
                  .add(const Duration(minutes: 4, seconds: 1))
                  .toIso8601String(),
            }),
          },
          senderDeviceId: charlie.deviceId,
        );
        await pump();

        for (final user in [alice, bob]) {
          expect(
            await user.msgRepo.getMessage(staleMessageId),
            isNull,
            reason: '${user.username} must not persist Charlie old-key publish',
          );
          expect(
            (await user.loadGroupMessages(
              groupId,
            )).where((message) => message.text == staleText).toList(),
            isEmpty,
            reason: '${user.username} must not render Charlie old-key publish',
          );
        }
        expect(await alice.msgRepo.getUnreadCount(groupId), aliceUnreadBefore);
        expect(await bob.msgRepo.getUnreadCount(groupId), bobUnreadBefore);
        expect(await aliceReactions.getReactionsForMessage(targetId), isEmpty);
        expect(await bobReactions.getReactionsForMessage(targetId), isEmpty);
        expect(
          network.deliveryRecords
              .where(
                (record) =>
                    record['messageId'] == staleMessageId &&
                    record['senderPeerId'] == charlie.peerId,
              )
              .toList(),
          hasLength(2),
        );
        expect(network.totalReactionDeliveries, 2);
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_REMOVED_AFTER_CUTOFF',
          ),
          isNotEmpty,
        );
      },
    );

    test(
      'SV-003 pending re-add publish is blocked until current config and key',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'sv003-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv003-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv003-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-sv003-pending-readd-current';
        const pendingMessageId = 'sv003-charlie-pending-readd';
        const currentMessageId = 'sv003-charlie-current-readd';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'SV-003 Pending Readd',
          createdAt: createdAt,
        );
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);
        await Future.wait([
          saveKey(alice, 1, 'sv003-old-key'),
          saveKey(bob, 1, 'sv003-old-key'),
          saveKey(charlie, 1, 'sv003-old-key'),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await pump();

        final readdAt = createdAt.add(const Duration(minutes: 4));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await charlie.groupRepo.removeAllKeys(groupId);

        final pendingSend = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'SV-003 Charlie pending re-add before current key',
          messageId: pendingMessageId,
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        expect(pendingSend.$1.name, isNot('success'));
        expect(pendingSend.$1.name, isNot('successNoPeers'));
        expect(pendingSend.$2, isNull);
        expect(await charlie.msgRepo.getMessage(pendingMessageId), isNull);
        expect(charlie.bridge.commandLog, isEmpty);
        await pump();

        for (final recipient in [alice, bob]) {
          final pendingVisible = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == pendingMessageId);
          expect(pendingVisible, isEmpty);
        }

        await Future.wait([
          saveKey(alice, 2, 'sv003-current-key'),
          saveKey(bob, 2, 'sv003-current-key'),
          saveKey(charlie, 2, 'sv003-current-key'),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        final readdedCharlieMember = await alice.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        expect(readdedCharlieMember, isNotNull);
        await bob.groupRepo.saveMember(readdedCharlieMember!);
        await pump();

        final currentSend = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'SV-003 Charlie current re-add publish',
          messageId: currentMessageId,
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        expect(currentSend.$1.name, anyOf('success', 'successNoPeers'));
        expect(currentSend.$2, isNotNull);
        expect(currentSend.$2!.keyGeneration, 2);
        await pump();

        for (final recipient in [alice, bob]) {
          final currentVisible = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == currentMessageId).toList();
          expect(currentVisible, hasLength(1));
          expect(currentVisible.single.keyGeneration, 2);
          expect(
            currentVisible.single.text,
            'SV-003 Charlie current re-add publish',
          );
        }
      },
    );

    test(
      'NW-001 full-mesh online A/B/C delivery works without relay fallback',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);

        final alice = GroupTestUser.create(
          peerId: 'nw001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'nw001-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'nw001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-nw001-full-mesh-online';
        const keyEpoch = 1;
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 15),
        );
        final expectedPeerIds = {alice.peerId, bob.peerId, charlie.peerId};

        await alice.createGroup(
          groupId: groupId,
          name: 'NW-001 Full Mesh',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt,
        );

        final finalGroup = (await alice.groupRepo.getGroup(groupId))!;
        final finalMembers = await alice.groupRepo.getMembers(groupId);
        Future<void> saveFinalMembership(GroupTestUser user) async {
          await user.groupRepo.saveGroup(
            finalGroup.copyWith(myRole: GroupRole.member),
          );
          for (final member in finalMembers) {
            await user.groupRepo.saveMember(member);
          }
        }

        Future<void> saveSharedKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: 'nw001-shared-full-mesh-key',
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveFinalMembership(bob),
          saveFinalMembership(charlie),
          saveSharedKey(alice),
          saveSharedKey(bob),
          saveSharedKey(charlie),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        expect(network.getSubscribers(groupId).toSet(), expectedPeerIds);

        final sends = [
          (
            sender: alice,
            messageId: 'nw001-alice-full-mesh',
            text: 'NW-001 Alice full-mesh live message',
            sentAt: createdAt.add(const Duration(minutes: 1)),
          ),
          (
            sender: bob,
            messageId: 'nw001-bob-full-mesh',
            text: 'NW-001 Bob full-mesh live message',
            sentAt: createdAt.add(const Duration(minutes: 2)),
          ),
          (
            sender: charlie,
            messageId: 'nw001-charlie-full-mesh',
            text: 'NW-001 Charlie full-mesh live message',
            sentAt: createdAt.add(const Duration(minutes: 3)),
          ),
        ];
        final users = [alice, bob, charlie];
        final topicPeerCountsBySender = <String, int>{};

        for (final send in sends) {
          flowEvents.clear();
          final (result, sentMessage) = await send.sender
              .sendGroupMessageViaBridge(
                groupId: groupId,
                text: send.text,
                messageId: send.messageId,
                timestamp: send.sentAt,
              );
          expect(result.name, 'success', reason: send.sender.username);
          expect(sentMessage, isNotNull, reason: send.sender.username);
          expect(sentMessage!.id, send.messageId);
          expect(sentMessage.isIncoming, isFalse);
          expect(sentMessage.status, 'sent');
          expect(sentMessage.keyGeneration, keyEpoch);

          final diagnostics = flowEvents
              .where(
                (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
              )
              .toList();
          expect(
            diagnostics,
            isNotEmpty,
            reason: '${send.sender.username} should emit send diagnostics',
          );
          final details = diagnostics.last['details'] as Map<String, dynamic>;
          expect(details['topicPeers'], 2, reason: send.sender.username);
          expect(details['expectedRecipientCount'], 2);
          expect(details['liveFanoutState'], 'full_peers');
          expect(details['inboxPending'], isFalse);
          expect(details['recipientReceiptClaimed'], isFalse);
          topicPeerCountsBySender[send.sender.peerId] =
              details['topicPeers'] as int;

          await pump();
        }

        expect(topicPeerCountsBySender, {
          alice.peerId: 2,
          bob.peerId: 2,
          charlie.peerId: 2,
        });

        for (final user in users) {
          final visibleMessages = (await user.loadGroupMessages(
            groupId,
          )).where((message) => !message.id.startsWith('sys-')).toList();
          expect(
            visibleMessages,
            hasLength(3),
            reason: '${user.username} should see three row-owned messages',
          );
        }

        for (final send in sends) {
          for (final user in users) {
            final matching = (await user.loadGroupMessages(
              groupId,
            )).where((message) => message.id == send.messageId).toList();
            expect(
              matching,
              hasLength(1),
              reason:
                  '${user.username} should persist ${send.messageId} exactly once',
            );
            final message = matching.single;
            expect(message.text, send.text, reason: user.username);
            expect(message.senderPeerId, send.sender.peerId);
            expect(message.senderUsername, send.sender.username);
            expect(message.keyGeneration, keyEpoch);
            expect(
              message.timestamp.toUtc(),
              send.sentAt,
              reason: user.username,
            );
            expect(
              message.isIncoming,
              user.peerId != send.sender.peerId,
              reason: '${user.username} incoming state for ${send.messageId}',
            );
          }
        }
      },
    );

    test(
      'NW-002 relay-only or circuit-routed peer receives group messages',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);

        final alice = GroupTestUser.create(
          peerId: 'nw002-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'nw002-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'nw002-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-nw002-relay-only-delivery';
        const keyEpoch = 1;
        final createdAt = DateTime.utc(2026, 5, 13, 10);
        final expectedPeerIds = {alice.peerId, bob.peerId, charlie.peerId};
        final users = [alice, bob, charlie];

        network.setRouteMode(bob.peerId, FakeGroupRouteMode.relayOnly);
        network.setRouteMode(charlie.peerId, FakeGroupRouteMode.circuitRouted);
        expect(network.routeModeFor(bob.peerId), FakeGroupRouteMode.relayOnly);
        expect(
          network.routeModeFor(charlie.peerId),
          FakeGroupRouteMode.circuitRouted,
        );

        await alice.createGroup(
          groupId: groupId,
          name: 'NW-002 Relay Delivery',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt,
        );

        final finalGroup = (await alice.groupRepo.getGroup(groupId))!;
        final finalMembers = await alice.groupRepo.getMembers(groupId);
        Future<void> saveFinalMembership(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(finalGroup.copyWith(myRole: role));
          for (final member in finalMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: 'nw002-shared-relay-route-key',
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([
          saveFinalMembership(alice, GroupRole.admin),
          saveFinalMembership(bob, GroupRole.member),
          saveFinalMembership(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        expect(network.getSubscribers(groupId).toSet(), expectedPeerIds);

        Future<Set<String>> memberIds(GroupTestUser user) async =>
            (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();
        final membersBefore = <String, Set<String>>{
          for (final user in users) user.peerId: await memberIds(user),
        };
        for (final members in membersBefore.values) {
          expect(members, expectedPeerIds);
        }

        Future<Map<String, dynamic>> expectLastSendSuccess(
          String senderPeerId,
        ) async {
          final diagnostics = flowEvents
              .where(
                (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
              )
              .toList();
          expect(
            diagnostics,
            isNotEmpty,
            reason: '$senderPeerId should emit send diagnostics',
          );
          final details = Map<String, dynamic>.from(
            diagnostics.last['details'] as Map,
          );
          expect(details['topicPeers'], 2, reason: senderPeerId);
          expect(details['expectedRecipientCount'], 2);
          expect(details['liveFanoutState'], 'full_peers');
          expect(details['inboxPending'], isFalse);
          return details;
        }

        flowEvents.clear();
        final (aliceResult, aliceSent) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'NW-002 Alice to relay-only Bob',
          messageId: 'nw002-alice-to-routed-peer',
          timestamp: createdAt.add(const Duration(minutes: 1)),
        );
        expect(aliceResult.name, 'success');
        expect(aliceSent, isNotNull);
        await expectLastSendSuccess(alice.peerId);
        await pump();

        flowEvents.clear();
        final (bobResult, bobSent) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'NW-002 Bob relay-only publish back',
          messageId: 'nw002-bob-relay-publish-back',
          timestamp: createdAt.add(const Duration(minutes: 2)),
        );
        expect(bobResult.name, 'success');
        expect(bobSent, isNotNull);
        await expectLastSendSuccess(bob.peerId);
        await pump();

        Map<String, dynamic> deliveryRecord({
          required String messageId,
          required String receiverPeerId,
        }) {
          return network.deliveryRecords.singleWhere(
            (record) =>
                record['messageId'] == messageId &&
                record['receiverPeerId'] == receiverPeerId,
          );
        }

        expect(
          deliveryRecord(
            messageId: 'nw002-alice-to-routed-peer',
            receiverPeerId: bob.peerId,
          ),
          containsPair('receiverRouteMode', FakeGroupRouteMode.relayOnly.name),
        );
        expect(
          deliveryRecord(
            messageId: 'nw002-alice-to-routed-peer',
            receiverPeerId: bob.peerId,
          ),
          containsPair('deliveryRouteKind', 'relay_only'),
        );
        expect(
          deliveryRecord(
            messageId: 'nw002-alice-to-routed-peer',
            receiverPeerId: charlie.peerId,
          ),
          containsPair(
            'receiverRouteMode',
            FakeGroupRouteMode.circuitRouted.name,
          ),
        );
        expect(
          deliveryRecord(
            messageId: 'nw002-bob-relay-publish-back',
            receiverPeerId: alice.peerId,
          ),
          containsPair('senderRouteMode', FakeGroupRouteMode.relayOnly.name),
        );
        expect(
          deliveryRecord(
            messageId: 'nw002-bob-relay-publish-back',
            receiverPeerId: charlie.peerId,
          ),
          containsPair('deliveryRouteKind', 'relay_only'),
        );

        Future<void> expectMessageOnce(
          GroupTestUser user,
          String messageId,
          String text,
          String senderPeerId,
          bool isIncoming,
        ) async {
          final matching = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matching,
            hasLength(1),
            reason: '${user.username} should persist $messageId exactly once',
          );
          expect(matching.single.text, text);
          expect(matching.single.senderPeerId, senderPeerId);
          expect(matching.single.isIncoming, isIncoming);
          expect(matching.single.keyGeneration, keyEpoch);
        }

        await expectMessageOnce(
          alice,
          'nw002-alice-to-routed-peer',
          'NW-002 Alice to relay-only Bob',
          alice.peerId,
          false,
        );
        await expectMessageOnce(
          bob,
          'nw002-alice-to-routed-peer',
          'NW-002 Alice to relay-only Bob',
          alice.peerId,
          true,
        );
        await expectMessageOnce(
          charlie,
          'nw002-alice-to-routed-peer',
          'NW-002 Alice to relay-only Bob',
          alice.peerId,
          true,
        );
        await expectMessageOnce(
          alice,
          'nw002-bob-relay-publish-back',
          'NW-002 Bob relay-only publish back',
          bob.peerId,
          true,
        );
        await expectMessageOnce(
          bob,
          'nw002-bob-relay-publish-back',
          'NW-002 Bob relay-only publish back',
          bob.peerId,
          false,
        );
        await expectMessageOnce(
          charlie,
          'nw002-bob-relay-publish-back',
          'NW-002 Bob relay-only publish back',
          bob.peerId,
          true,
        );

        for (final user in users) {
          expect(await memberIds(user), membersBefore[user.peerId]);
        }
      },
    );

    test(
      'GM-001 DE-001 creates private A/B/C group with shared epoch and exact fanout tuple',
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
        final sentAt = DateTime.utc(2026, 5, 10, 12);
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
          timestamp: sentAt,
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.id, messageId);
        expect(sentMessage.groupId, groupId);
        expect(sentMessage.senderPeerId, alice.peerId);
        expect(sentMessage.senderUsername, alice.username);
        expect(sentMessage.keyGeneration, keyEpoch);
        expect(sentMessage.timestamp.toUtc(), sentAt);
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
          expect(
            received.timestamp.toUtc(),
            sentAt,
            reason: recipient.username,
          );
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
        expect(aliceMatching.single.timestamp.toUtc(), sentAt);
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

    test(
      'PL-003 empty text without media creates no local or remote ghost row',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'pl003-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'pl003-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-pl003-empty-no-media';
        const messageId = 'pl003-empty-no-media';
        await alice.createGroup(groupId: groupId, name: 'PL-003 Empty');
        await alice.addMember(groupId: groupId, invitee: bob);
        for (final user in [alice, bob]) {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'pl003-k1',
              createdAt: DateTime.utc(2026, 5, 13, 20, 45),
            ),
          );
        }

        alice.start();
        bob.start();

        final (result, message) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: ' \n\t ',
          messageId: messageId,
        );
        await pump();

        expect(result.name, 'error');
        expect(message, isNull);
        expect(await alice.msgRepo.getMessage(messageId), isNull);
        expect(await bob.msgRepo.getMessage(messageId), isNull);
        expect(
          (await alice.loadGroupMessages(
            groupId,
          )).where((row) => row.id == messageId),
          isEmpty,
        );
        expect(
          (await bob.loadGroupMessages(
            groupId,
          )).where((row) => row.id == messageId),
          isEmpty,
        );
        expect(network.publishCount, 0);
        expect(alice.bridge.sentMessages, isEmpty);
        expect(alice.bridge.commandLog, isEmpty);
      },
    );

    test(
      'PL-008 media upload progress storm does not drop fake-network group messages',
      () async {
        final progressEvents = <Map<String, dynamic>>[];
        final progressSub = mediaUploadProgressStream.listen(
          progressEvents.add,
        );
        addTearDown(progressSub.cancel);

        final alice = GroupTestUser.create(
          peerId: 'pl008-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'pl008-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'pl008-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-pl008-progress-storm';
        await alice.createGroup(groupId: groupId, name: 'PL-008 Progress');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'pl008-key',
              createdAt: DateTime.utc(2026, 5, 13, 21),
            ),
          );
        }

        await Future.wait([saveKey(alice), saveKey(bob), saveKey(charlie)]);

        alice.start();
        bob.start();
        charlie.start();

        var progressSequence = 0;
        void emitProgressBurst(String phase) {
          for (var i = 0; i < 6; i++) {
            progressSequence++;
            emitMediaUploadProgressEvent({
              'id': 'pl008-upload',
              'sentBytes': progressSequence * 1024,
              'totalBytes': 36 * 1024,
              'phase': phase,
            });
          }
        }

        Future<void> sendDuringProgress({
          required GroupTestUser sender,
          required String messageId,
          required String text,
        }) async {
          emitProgressBurst('before-$messageId');
          final (result, sent) = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
          );
          expect(result.name, 'success');
          expect(sent, isNotNull);
          emitProgressBurst('after-$messageId');
        }

        const messageTexts = [
          'PL-008 Alice message 1',
          'PL-008 Bob message',
          'PL-008 Alice message 2',
        ];

        await sendDuringProgress(
          sender: alice,
          messageId: 'pl008-alice-1',
          text: messageTexts[0],
        );
        await sendDuringProgress(
          sender: bob,
          messageId: 'pl008-bob-1',
          text: messageTexts[1],
        );
        await sendDuringProgress(
          sender: alice,
          messageId: 'pl008-alice-2',
          text: messageTexts[2],
        );

        Future<List<GroupMessage>> waitForAllMessages(
          GroupTestUser user,
        ) async {
          final deadline = DateTime.now().add(const Duration(seconds: 3));
          while (DateTime.now().isBefore(deadline)) {
            final messages = await user.loadGroupMessages(groupId);
            final hasAll = messageTexts.every(
              (text) =>
                  messages.where((message) => message.text == text).length == 1,
            );
            if (hasAll) return messages;
            await pump();
          }
          fail('Expected all PL-008 messages for ${user.username}');
        }

        final aliceMessages = await waitForAllMessages(alice);
        final bobMessages = await waitForAllMessages(bob);
        final charlieMessages = await waitForAllMessages(charlie);

        for (final text in messageTexts) {
          expect(
            aliceMessages.where((message) => message.text == text),
            hasLength(1),
            reason: 'Alice should retain exactly one copy of $text',
          );
          expect(
            bobMessages.where((message) => message.text == text),
            hasLength(1),
            reason: 'Bob should retain exactly one copy of $text',
          );
          expect(
            charlieMessages.where((message) => message.text == text),
            hasLength(1),
            reason: 'Charlie should receive exactly one copy of $text',
          );
        }

        expect(progressEvents, hasLength(36));
        expect(progressEvents.last['id'], 'pl008-upload');
        expect(progressEvents.last['sentBytes'], 36 * 1024);
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
          final charlieSelf = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
          return bobCharlie == null &&
              (charlieGroup == null ||
                  (charlieSelf == null && charlieKey == null));
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
          retentionNowUtc: readdAt.add(const Duration(days: 1)),
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
          retentionNowUtc: readdAt.add(const Duration(days: 1)),
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
          _bridgeCommandIndex(
            alice.bridge,
            'group:updateKey',
            keyEpoch: removedKeyEpoch,
          ),
          -1,
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
          retentionNowUtc: readdAt.add(const Duration(days: 1)),
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
      'SV-006 fake-network replay duplicate and removed-interval delivery stay deduped',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'sv006-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv006-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv006-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-sv006-replay';
        const duplicateMessageId = 'sv006-duplicate-live';
        const removedReplayMessageId = 'sv006-removed-window-replay';
        const currentMessageId = 'sv006-current-after-readd';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );
        final removedAt = createdAt.add(const Duration(minutes: 3));
        final readdAt = createdAt.add(const Duration(minutes: 5));

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'SV-006 Replay',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await Future.wait([
          saveKey(alice, 1, 'sv006-key-1'),
          saveKey(bob, 1, 'sv006-key-1'),
          saveKey(charlie, 1, 'sv006-key-1'),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        network.resetCounters();
        network.duplicateOnDeliver = true;
        final duplicateSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'SV-006 duplicate live delivery',
          messageId: duplicateMessageId,
          timestamp: createdAt.add(const Duration(minutes: 2, seconds: 10)),
        );
        expect(duplicateSend.$1.name, 'success');
        expect(duplicateSend.$2, isNotNull);
        expect(duplicateSend.$2!.keyGeneration, 1);
        await pump();
        network.duplicateOnDeliver = false;

        expect(network.totalDeliveries, 4);
        expect(
          network.deliveryRecords.where(
            (record) => record['messageId'] == duplicateMessageId,
          ),
          hasLength(2),
        );
        for (final recipient in [bob, charlie]) {
          final matches = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == duplicateMessageId).toList();
          expect(matches, hasLength(1), reason: recipient.username);
          expect(matches.single.text, 'SV-006 duplicate live delivery');
          expect(matches.single.keyGeneration, 1);
        }

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await pump();
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );

        await Future.wait([
          saveKey(alice, 2, 'sv006-key-2'),
          saveKey(bob, 2, 'sv006-key-2'),
        ]);
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await saveKey(charlie, 2, 'sv006-key-2');
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await pump();
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );

        final removedReplay = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'SV-006 removed-window replay',
          messageId: removedReplayMessageId,
          timestamp: removedAt.add(const Duration(seconds: 30)),
        );
        expect(removedReplay.$1.name, 'success');
        expect(removedReplay.$2, isNotNull);
        expect(removedReplay.$2!.keyGeneration, 2);
        await pump();

        final charlieRemovedReplay = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.id == removedReplayMessageId);
        expect(charlieRemovedReplay, isEmpty);
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                    'GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED' ||
                event['event'] ==
                    'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
          ),
          isNotEmpty,
        );

        final currentSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'SV-006 current after readd',
          messageId: currentMessageId,
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        expect(currentSend.$1.name, 'success');
        expect(currentSend.$2, isNotNull);
        expect(currentSend.$2!.keyGeneration, 2);
        await pump();

        final currentForCharlie = (await charlie.loadGroupMessages(
          groupId,
        )).where((message) => message.id == currentMessageId).toList();
        expect(currentForCharlie, hasLength(1));
        expect(currentForCharlie.single.text, 'SV-006 current after readd');
      },
    );

    test(
      'SV-007 fake-network topic mismatch is rejected from both groups',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'sv007-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv007-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
        });

        const topicGroupId = 'group-sv007-topic-a';
        const payloadGroupId = 'group-sv007-payload-b';
        const mismatchMessageId = 'sv007-topic-mismatch';
        const validTopicMessageId = 'sv007-valid-topic-a';
        const validPayloadMessageId = 'sv007-valid-payload-b';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );

        Future<void> saveKey(
          GroupTestUser user,
          String groupId,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: encryptedKey,
              createdAt: createdAt,
            ),
          );
        }

        await alice.createGroup(
          groupId: topicGroupId,
          name: 'SV-007 Topic Group',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: topicGroupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.createGroup(
          groupId: payloadGroupId,
          name: 'SV-007 Payload Group',
          createdAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.addMember(
          groupId: payloadGroupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await Future.wait([
          saveKey(alice, topicGroupId, 'sv007-topic-key'),
          saveKey(bob, topicGroupId, 'sv007-topic-key'),
          saveKey(alice, payloadGroupId, 'sv007-payload-key'),
          saveKey(bob, payloadGroupId, 'sv007-payload-key'),
        ]);

        alice.start();
        bob.start();
        network.resetCounters();

        await network.publish(topicGroupId, alice.peerId, {
          'groupId': payloadGroupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'keyEpoch': 1,
          'text': 'SV-007 wrong topic payload',
          'timestamp': createdAt
              .add(const Duration(minutes: 4))
              .toIso8601String(),
          'messageId': mismatchMessageId,
        }, senderDeviceId: alice.deviceId);
        await pump();

        expect(
          network.deliveryRecords
              .where((record) => record['messageId'] == mismatchMessageId)
              .single['payloadGroupId'],
          payloadGroupId,
        );
        expect(await bob.msgRepo.getMessage(mismatchMessageId), isNull);
        expect(
          (await bob.loadGroupMessages(
            topicGroupId,
          )).where((message) => message.id == mismatchMessageId),
          isEmpty,
        );
        expect(
          (await bob.loadGroupMessages(
            payloadGroupId,
          )).where((message) => message.id == mismatchMessageId),
          isEmpty,
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_MESSAGE_LISTENER_TOPIC_GROUP_MISMATCH_REJECTED',
          ),
          isNotEmpty,
        );

        final validTopicSend = await alice.sendGroupMessageViaBridge(
          groupId: topicGroupId,
          text: 'SV-007 valid topic group',
          messageId: validTopicMessageId,
          timestamp: createdAt.add(const Duration(minutes: 5)),
        );
        expect(validTopicSend.$1.name, 'success');
        final validPayloadSend = await alice.sendGroupMessageViaBridge(
          groupId: payloadGroupId,
          text: 'SV-007 valid payload group',
          messageId: validPayloadMessageId,
          timestamp: createdAt.add(const Duration(minutes: 6)),
        );
        expect(validPayloadSend.$1.name, 'success');
        await pump();

        final topicVisible = (await bob.loadGroupMessages(
          topicGroupId,
        )).where((message) => message.id == validTopicMessageId).toList();
        final payloadVisible = (await bob.loadGroupMessages(
          payloadGroupId,
        )).where((message) => message.id == validPayloadMessageId).toList();
        expect(topicVisible, hasLength(1));
        expect(topicVisible.single.text, 'SV-007 valid topic group');
        expect(payloadVisible, hasLength(1));
        expect(payloadVisible.single.text, 'SV-007 valid payload group');
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
          final charlieSelf = await charlie.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final charlieKey = await charlie.groupRepo.getLatestKey(groupId);
          return aliceCharlie == null &&
              bobCharlie == null &&
              charlieGroup != null &&
              charlieSelf == null &&
              charlieKey == null &&
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
          retentionNowUtc: readdAt.add(const Duration(days: 1)),
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
          retentionNowUtc: createdAt.add(const Duration(days: 1)),
        );
        await drainGroupOfflineInboxForGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          msgRepo: charlie.msgRepo,
          groupId: groupId,
          groupMessageListener: charlie.groupMessageListener,
          selfPeerId: charlie.peerId,
          retentionNowUtc: createdAt.add(const Duration(days: 1)),
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
          retentionNowUtc: createdAt.add(const Duration(days: 1)),
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
          retentionNowUtc: createdAt.add(const Duration(days: 1)),
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
      'KE-017 fake network higher epoch live delivery requests repair and keeps message',
      () async {
        const expectedReason = 'received_message_epoch_missing_local_key';
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final bobRepairRequests = <GroupKeyRepairRequest>[];
        final alice = GroupTestUser.create(
          peerId: 'ke017-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke017-bob-peer',
          username: 'Bob',
          network: network,
          requestGroupKeyRepair: bobRepairRequests.add,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-ke017-received-epoch-repair';
        await alice.createGroup(groupId: groupId, name: 'KE-017');
        await alice.addMember(groupId: groupId, invitee: bob);

        Future<void> saveKey(GroupTestUser user, int epoch) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: 'ke017-key-$epoch',
              createdAt: DateTime.utc(2026, 5, 11, 12, epoch),
            ),
          );
        }

        await Future.wait([saveKey(alice, 1), saveKey(bob, 1)]);
        await saveKey(alice, 2);
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 2);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);

        alice.start();
        bob.start();

        final higher = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-017 higher epoch over fake network',
          messageId: 'ke017h1',
          timestamp: DateTime.utc(2026, 5, 11, 12, 2),
        );
        expect(higher.$1.name, 'success');
        expect(higher.$2, isNotNull);
        expect(higher.$2!.keyGeneration, 2);
        await pump();

        final higherMatches = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == 'ke017h1').toList();
        expect(higherMatches, hasLength(1));
        expect(higherMatches.single.isIncoming, isTrue);
        expect(higherMatches.single.status, 'delivered');
        expect(higherMatches.single.keyGeneration, 2);
        expect(
          higherMatches.single.text,
          'KE-017 higher epoch over fake network',
        );
        expect(bobRepairRequests, hasLength(1));
        expect(bobRepairRequests.single.groupId, groupId);
        expect(bobRepairRequests.single.keyEpoch, 2);
        expect(bobRepairRequests.single.reason, expectedReason);
        expect(bobRepairRequests.single.messageId, 'ke017h1');

        await saveKey(bob, 2);
        final sameEpoch = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-017 same epoch follow-up',
          messageId: 'ke017h2',
          timestamp: DateTime.utc(2026, 5, 11, 12, 3),
        );
        expect(sameEpoch.$1.name, 'success');
        expect(sameEpoch.$2, isNotNull);
        expect(sameEpoch.$2!.keyGeneration, 2);
        await pump();

        final bobMessages = await bob.loadGroupMessages(groupId);
        expect(
          bobMessages.where((message) => message.id == 'ke017h1'),
          hasLength(1),
        );
        expect(
          bobMessages.where((message) => message.id == 'ke017h2'),
          hasLength(1),
        );
        expect(bobRepairRequests, hasLength(1));

        final diagnostics = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL',
            )
            .toList();
        expect(diagnostics, hasLength(1));
        final details = diagnostics.single['details'] as Map<String, dynamic>;
        expect(details['groupId'], groupId.substring(0, 8));
        expect(details['messageId'], 'ke017h1');
        expect(details['incomingKeyEpoch'], 2);
        expect(details['localKeyEpoch'], 1);
        expect(details['reason'], expectedReason);
      },
    );

    test(
      'KE-022 failed key update exposes diagnostics and recovery placeholder over fake network',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final keyUpdateRepairRequests = <GroupKeyRepairRequest>[];
        final receiveRepairRequests = <GroupKeyRepairRequest>[];
        final bobPendingRepairs =
            _SmokeInMemoryGroupPendingKeyRepairRepository();
        final bobDiagnostics =
            StreamController<Map<String, dynamic>>.broadcast();
        final bobLiveEvents =
            StreamController<Map<String, dynamic>>.broadcast();
        addTearDown(() async {
          network.deliveryFails = false;
          await bobDiagnostics.close();
          await bobLiveEvents.close();
        });
        final alice = GroupTestUser.create(
          peerId: 'ke022-alice-peer',
          username: 'Alice',
          network: network,
          bridge: _CommittedEpochGenerateBridge(
            initialCommittedEpoch: 1,
            keyPrefix: 'ke022-key',
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'ke022-bob-peer',
          username: 'Bob',
          network: network,
        );
        final bobDiagnosticListener = GroupMessageListener(
          groupRepo: bob.groupRepo,
          msgRepo: bob.msgRepo,
          bridge: bob.bridge,
          getSelfPeerId: () async => bob.peerId,
          mediaAttachmentRepo: bob.mediaAttachmentRepo,
          groupDiagnosticEvents: bobDiagnostics.stream,
          pendingKeyRepairRepo: bobPendingRepairs,
          requestGroupKeyRepair: receiveRepairRequests.add,
        );
        addTearDown(() {
          bobDiagnosticListener.dispose();
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-ke022-update-failure-recovery';
        const epochOneKey = 'ke022-key-1';
        const messageId = 'ke022-degraded-message';
        final createdAt = DateTime.utc(2026, 5, 12, 8);
        await alice.createGroup(
          groupId: groupId,
          name: 'KE-022',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt,
        );
        await Future.wait([
          alice.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: epochOneKey,
              createdAt: createdAt,
            ),
          ),
          bob.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: epochOneKey,
              createdAt: createdAt,
            ),
          ),
        ]);

        String? capturedBobKeyUpdate;
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            if (peerId == bob.deviceId) {
              capturedBobKeyUpdate = message;
            }
            return true;
          },
        );
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(capturedBobKeyUpdate, isNotNull);

        bob.bridge.responses['group:updateKey'] = {
          'ok': false,
          'errorCode': 'UPDATE_KEY_FAILED',
          'errorMessage': 'forced KE-022 update failure',
        };
        final keyUpdateController = StreamController<ChatMessage>.broadcast();
        final keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdateController.stream,
          groupRepo: bob.groupRepo,
          bridge: bob.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${bob.deviceId}',
          getOwnPeerId: () async => bob.peerId,
          getOwnDeviceId: () async => bob.deviceId,
          requestGroupKeyRepair: keyUpdateRepairRequests.add,
        );
        addTearDown(() async {
          keyUpdateListener.dispose();
          await keyUpdateController.close();
        });
        keyUpdateListener.start();
        keyUpdateController.add(
          ChatMessage(
            from: alice.deviceId,
            to: bob.deviceId,
            content: capturedBobKeyUpdate!,
            timestamp: DateTime.utc(2026, 5, 12, 8, 1).toIso8601String(),
            isIncoming: true,
            confirmNonce: 'ke022-direct-key-update',
          ),
        );
        await pump();

        final bobLatest = await bob.groupRepo.getLatestKey(groupId);
        expect(bobLatest, isNotNull);
        expect(bobLatest!.keyGeneration, 1);
        expect(await bob.groupRepo.getKeyByGeneration(groupId, 2), isNull);
        expect(keyUpdateRepairRequests, hasLength(1));
        expect(keyUpdateRepairRequests.single.groupId, groupId);
        expect(keyUpdateRepairRequests.single.keyEpoch, 2);
        expect(
          keyUpdateRepairRequests.single.reason,
          groupKeyRepairReasonKeyUpdateApplyFailed,
        );

        bobDiagnosticListener.start(bobLiveEvents.stream);
        network.deliveryFails = true;
        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-022 message requiring epoch 2',
          messageId: messageId,
          timestamp: DateTime.utc(2026, 5, 12, 8, 2),
        );
        network.deliveryFails = false;
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);

        bobDiagnostics.add({
          'event': 'group:decryption_failed',
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderDeviceId': alice.deviceId,
          'keyEpoch': 2,
          'localKeyEpoch': 1,
          'messageId': messageId,
          'error': 'forced KE-022 receive failure after key update failure',
        });
        await pump();

        final repairId = liveGroupPendingKeyRepairId(
          groupId: groupId,
          senderPeerId: alice.peerId,
          keyEpoch: 2,
          localKeyEpoch: 1,
        );
        final repair = await bobPendingRepairs.getRepair(repairId);
        expect(repair, isNotNull);
        expect(repair!.status, groupPendingKeyRepairStatusPendingKey);
        expect(repair.keyEpoch, 2);
        expect(
          repair.lastError,
          'forced KE-022 receive failure after key update failure',
        );
        expect(receiveRepairRequests, hasLength(1));
        expect(receiveRepairRequests.single.groupId, groupId);
        expect(receiveRepairRequests.single.keyEpoch, 2);
        expect(
          receiveRepairRequests.single.reason,
          groupKeyRepairReasonLiveDiagnostic,
        );

        final bobMessages = await bob.loadGroupMessages(groupId);
        final placeholders = bobMessages
            .where((message) => message.id == repairId)
            .toList();
        expect(placeholders, hasLength(1));
        expect(placeholders.single.text, groupPendingKeyRepairPlaceholderText);
        expect(
          placeholders.single.status,
          groupPendingKeyRepairStatusPendingKey,
        );

        expect(
          flowEvents.where(
            (event) =>
                event['event'] == 'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED',
          ),
          hasLength(1),
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_KEY_UPDATE_LISTENER_RECOVERY_REQUESTED',
          ),
          hasLength(1),
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_LIVE_DECRYPTION_REPAIR_PLACEHOLDER_SAVED',
          ),
          hasLength(1),
        );
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
      'ML-002 online add D receives immediate live A and B messages after join/key handoff',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ml002-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ml002-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ml002-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'ml002-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-ml002-online-add-live-delivery';
        const keyEpoch = 5;
        const sharedEncryptedKey = 'ml002-shared-current-key';
        const aliceMessageId = 'ml002-a-post-join';
        const bobMessageId = 'ml002-b-post-join';
        const alicePlaintext = 'ML-002 live post-join message from A';
        const bobPlaintext = 'ML-002 live post-join message from B';
        final baselineAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final addDAt = baselineAt.add(const Duration(minutes: 1));
        final aliceSentAt = baselineAt.add(const Duration(minutes: 2));
        final bobSentAt = baselineAt.add(const Duration(minutes: 3));
        final baselinePeerIds = {alice.peerId, bob.peerId, charlie.peerId};
        final postJoinPeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dana.peerId,
        };

        await alice.createGroup(
          groupId: groupId,
          name: 'ML-002 Online Add',
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
          baselinePeerIds,
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
        dana.start();

        expect(network.getSubscribers(groupId).toSet(), baselinePeerIds);
        expect(await dana.groupRepo.getGroup(groupId), isNull);
        expect(await dana.groupRepo.getMember(groupId, dana.peerId), isNull);
        expect(network.isSubscribed(groupId, dana.peerId), isFalse);

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

        expect(network.getSubscribers(groupId).toSet(), postJoinPeerIds);

        Future<void> expectConvergedMemberState(
          GroupTestUser user,
          GroupRole expectedGroupRole,
        ) async {
          final group = await user.groupRepo.getGroup(groupId);
          expect(group, isNotNull, reason: '${user.username} has group');
          expect(group!.id, groupId, reason: user.username);
          expect(
            group.topicName,
            baselineGroup.topicName,
            reason: user.username,
          );
          expect(group.myRole, expectedGroupRole, reason: user.username);

          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            postJoinPeerIds,
            reason: '${user.username} should see D active after join',
          );

          final rolesByPeerId = {
            for (final member in members) member.peerId: member.role,
          };
          expect(rolesByPeerId[alice.peerId], MemberRole.admin);
          expect(rolesByPeerId[bob.peerId], MemberRole.writer);
          expect(rolesByPeerId[charlie.peerId], MemberRole.writer);
          expect(rolesByPeerId[dana.peerId], MemberRole.writer);

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

        final configHashes = <String>{
          for (final user in [alice, bob, charlie, dana])
            buildGroupConfigPayload(
                  (await user.groupRepo.getGroup(groupId))!,
                  await user.groupRepo.getMembers(groupId),
                  configVersionOverride: addDAt,
                )[groupConfigStateHashField]
                as String,
        };
        expect(configHashes, hasLength(1));

        final (aliceSendResult, aliceSentMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: alicePlaintext,
              messageId: aliceMessageId,
              timestamp: aliceSentAt,
            );
        expect(aliceSendResult.name, 'success');
        expect(aliceSentMessage, isNotNull);
        expect(aliceSentMessage!.keyGeneration, keyEpoch);

        final (bobSendResult, bobSentMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobPlaintext,
              messageId: bobMessageId,
              timestamp: bobSentAt,
            );
        expect(bobSendResult.name, 'success');
        expect(bobSentMessage, isNotNull);
        expect(bobSentMessage!.keyGeneration, keyEpoch);

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
            reason: '${user.username} should persist $messageId exactly once',
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
          dana,
          messageId: aliceMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: alicePlaintext,
          isIncoming: true,
        );
        await expectMessageTuple(
          dana,
          messageId: bobMessageId,
          senderPeerId: bob.peerId,
          senderUsername: bob.username,
          text: bobPlaintext,
          isIncoming: true,
        );

        await expectMessageTuple(
          alice,
          messageId: aliceMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: alicePlaintext,
          isIncoming: false,
        );
        await expectMessageTuple(
          bob,
          messageId: bobMessageId,
          senderPeerId: bob.peerId,
          senderUsername: bob.username,
          text: bobPlaintext,
          isIncoming: false,
        );
      },
    );

    test(
      'ML-016 non-friend invited Dana receives A and B messages with stable sender labels',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ml016-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ml016-bob-peer',
          username: 'Bob',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'ml016-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          dana.dispose();
        });

        const groupId = 'group-ml016-non-friend-delivery';
        const keyEpoch = 7;
        const aliceMessageId = 'ml016-alice-to-dana';
        const bobMessageId = 'ml016-bob-to-dana';
        const aliceText = 'ML-016 Alice visible to non-friend Dana';
        const bobText = 'ML-016 Bob visible to non-friend Dana';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        );

        await alice.createGroup(
          groupId: groupId,
          name: 'ML-016 Non-Friend Delivery',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );

        for (final user in [alice, bob, dana]) {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: 'ml016-shared-key',
              createdAt: createdAt,
            ),
          );
        }

        alice.start();
        bob.start();
        dana.start();

        await network.publish(groupId, alice.peerId, {
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': '',
          'keyEpoch': keyEpoch,
          'text': aliceText,
          'timestamp': createdAt
              .add(const Duration(minutes: 2))
              .toIso8601String(),
          'messageId': aliceMessageId,
        }, senderDeviceId: alice.deviceId);
        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': '   ',
          'keyEpoch': keyEpoch,
          'text': bobText,
          'timestamp': createdAt
              .add(const Duration(minutes: 3))
              .toIso8601String(),
          'messageId': bobMessageId,
        }, senderDeviceId: bob.deviceId);
        await pump();

        Future<GroupMessage> expectDanaMessage({
          required String messageId,
          required String senderPeerId,
          required String expectedLabel,
          required String text,
        }) async {
          final matching = (await dana.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matching, hasLength(1));
          final message = matching.single;
          expect(message.isIncoming, isTrue);
          expect(message.senderPeerId, senderPeerId);
          expect(message.senderUsername, expectedLabel);
          expect(message.senderUsername!.trim(), isNotEmpty);
          expect(message.senderUsername, isNot('Unknown'));
          expect(message.text, text);
          expect(message.keyGeneration, keyEpoch);
          return message;
        }

        await expectDanaMessage(
          messageId: aliceMessageId,
          senderPeerId: alice.peerId,
          expectedLabel: alice.username,
          text: aliceText,
        );
        await expectDanaMessage(
          messageId: bobMessageId,
          senderPeerId: bob.peerId,
          expectedLabel: bob.username,
          text: bobText,
        );
      },
    );

    test(
      'UP-009 re-added sender identity uses current member label when wire name is stale',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'up009-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'up009-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'up009-charlie-peer',
          username: 'Old Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-up009-readd-sender-identity';
        const text = 'UP-009 Charlie after re-add remains visible';
        const readdedUsername = 'Readded Charlie';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final removedAt = createdAt.add(const Duration(minutes: 1));
        final readdedAt = createdAt.add(const Duration(minutes: 2));
        final sentAt = createdAt.add(const Duration(minutes: 3));

        await alice.createGroup(
          groupId: groupId,
          name: 'UP-009 Sender Identity',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt,
        );

        for (final user in [alice, bob, charlie]) {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'up009-shared-key',
              createdAt: createdAt,
            ),
          );
        }

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
        await pump();

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdedAt,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdedAt,
        );
        await pump();

        for (final user in [alice, bob]) {
          final member = await user.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          expect(member, isNotNull, reason: user.username);
          await user.groupRepo.saveMember(
            member!.copyWith(username: readdedUsername, joinedAt: readdedAt),
          );
        }

        final sent = await charlie.sendGroupMessage(
          groupId: groupId,
          text: text,
          messageId: 'up009-charlie-after-readd',
          timestamp: sentAt,
        );
        expect(sent, isNotNull);
        await pump();

        Future<void> expectRenderedLabel(GroupTestUser user) async {
          final messages = await user.loadGroupMessages(groupId);
          final matching = messages
              .where((message) => message.id == 'up009-charlie-after-readd')
              .toList();
          expect(matching, hasLength(1), reason: user.username);
          final message = matching.single;
          expect(message.text, text, reason: user.username);
          expect(message.senderPeerId, charlie.peerId, reason: user.username);
          expect(
            message.senderUsername,
            readdedUsername,
            reason: user.username,
          );
          final member = await user.groupRepo.getMember(
            groupId,
            charlie.peerId,
          );
          final rendered = resolveGroupSenderDisplayName(
            senderPeerId: message.senderPeerId,
            wireSenderUsername: message.senderUsername,
            member: member,
            preferMemberName: true,
          );
          expect(rendered, readdedUsername, reason: user.username);
          expect(rendered, isNot('Member up009-ch'), reason: user.username);
        }

        await expectRenderedLabel(alice);
        await expectRenderedLabel(bob);
      },
    );

    test(
      'ML-003 offline D accepts pending invite, drains A/B post-add replay, and receives live after drain',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ml003-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ml003-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ml003-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'ml003-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-ml003-offline-add';
        const keyEpoch = 5;
        const sharedEncryptedKey = 'ml003-shared-current-key';
        const preAddMessageId = 'ml003-a-pre-add';
        const alicePostAddMessageId = 'ml003-a-post-add';
        const bobPostAddMessageId = 'ml003-b-post-add';
        const liveAfterDrainMessageId = 'ml003-a-live-after-drain';
        const preAddPlaintext = 'ML-003 pre-add control from A';
        const alicePostAddPlaintext = 'ML-003 post-add replay from A';
        const bobPostAddPlaintext = 'ML-003 post-add replay from B';
        const liveAfterDrainPlaintext = 'ML-003 live after drain from A';
        final baselineAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final addDAt = baselineAt.add(const Duration(minutes: 1));
        final preAddSentAt = baselineAt.add(const Duration(seconds: 30));
        final alicePostAddSentAt = addDAt.add(const Duration(minutes: 1));
        final bobPostAddSentAt = addDAt.add(const Duration(minutes: 2));
        final liveAfterDrainSentAt = addDAt.add(const Duration(minutes: 3));
        final baselinePeerIds = {alice.peerId, bob.peerId, charlie.peerId};
        final postAddPeerIds = {
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dana.peerId,
        };

        await alice.createGroup(
          groupId: groupId,
          name: 'ML-003 Offline Add',
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
          baselinePeerIds,
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

        expect(network.getSubscribers(groupId).toSet(), baselinePeerIds);
        expect(await dana.groupRepo.getGroup(groupId), isNull);
        expect(await dana.groupRepo.getMember(groupId, dana.peerId), isNull);
        expect(network.isSubscribed(groupId, dana.peerId), isFalse);

        Map<String, dynamic> inboxStoreFor(
          GroupTestUser user,
          String messageId,
        ) {
          for (final raw in user.bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:inboxStore') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            final envelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (envelope['messageId'] == messageId) {
              return payload;
            }
          }
          throw StateError('Missing inbox store payload for $messageId');
        }

        Map<String, dynamic> relayEnvelopeFor(
          GroupTestUser user,
          String messageId,
          DateTime timestamp,
        ) {
          final payload = inboxStoreFor(user, messageId);
          return {
            'from': user.peerId,
            'message': payload['message'],
            'timestamp': timestamp.toIso8601String(),
          };
        }

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
            reason: '${user.username} should persist $messageId exactly once',
          );
          final message = matching.single;
          expect(message.isIncoming, isIncoming, reason: user.username);
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

        final (preAddResult, preAddMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: preAddPlaintext,
              messageId: preAddMessageId,
              timestamp: preAddSentAt,
            );
        expect(preAddResult.name, 'success');
        expect(preAddMessage, isNotNull);
        final preAddInbox = inboxStoreFor(alice, preAddMessageId);
        expect(preAddInbox['recipientPeerIds'], isNot(contains(dana.peerId)));

        final danaMember = GroupMember(
          groupId: groupId,
          peerId: dana.peerId,
          username: dana.username,
          role: MemberRole.writer,
          publicKey: dana.publicKey,
          mlKemPublicKey: 'mlkem-${dana.peerId}',
          devices: [dana.deviceIdentity],
          joinedAt: addDAt,
        );
        await addGroupMember(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          newMember: danaMember,
          selfPeerId: alice.peerId,
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: dana,
          eventAt: addDAt,
        );
        await pump();

        expect(network.getSubscribers(groupId).toSet(), baselinePeerIds);
        expect(await dana.groupRepo.getGroup(groupId), isNull);
        expect(await dana.groupRepo.getMember(groupId, dana.peerId), isNull);
        expect(network.isSubscribed(groupId, dana.peerId), isFalse);

        Future<void> expectPostAddMemberState(GroupTestUser user) async {
          final members = await user.groupRepo.getMembers(groupId);
          expect(
            members.map((member) => member.peerId).toSet(),
            postAddPeerIds,
            reason: '${user.username} should know D before post-add send',
          );
        }

        await expectPostAddMemberState(alice);
        await expectPostAddMemberState(bob);
        await expectPostAddMemberState(charlie);

        final (alicePostAddResult, alicePostAddMessage) = await alice
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: alicePostAddPlaintext,
              messageId: alicePostAddMessageId,
              timestamp: alicePostAddSentAt,
            );
        expect(alicePostAddResult.name, 'success');
        expect(alicePostAddMessage, isNotNull);

        final (bobPostAddResult, bobPostAddMessage) = await bob
            .sendGroupMessageViaBridge(
              groupId: groupId,
              text: bobPostAddPlaintext,
              messageId: bobPostAddMessageId,
              timestamp: bobPostAddSentAt,
            );
        expect(bobPostAddResult.name, 'success');
        expect(bobPostAddMessage, isNotNull);
        expect(
          inboxStoreFor(alice, alicePostAddMessageId)['recipientPeerIds'],
          contains(dana.peerId),
        );
        expect(
          inboxStoreFor(bob, bobPostAddMessageId)['recipientPeerIds'],
          contains(dana.peerId),
        );

        final pendingInviteRepo = InMemoryPendingGroupInviteRepository();
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: alice.peerId,
              publicKey: alice.publicKey,
              rendezvous: '/ip4/0.0.0.0',
              username: alice.username,
              signature: 'sig',
              scannedAt: baselineAt.toIso8601String(),
              mlKemPublicKey: 'mlkem-${alice.peerId}',
            ),
          ]);
        final acceptedGroup = (await alice.groupRepo.getGroup(groupId))!;
        final acceptedMembers = await alice.groupRepo.getMembers(groupId);
        final acceptedConfig = buildGroupConfigPayload(
          acceptedGroup,
          acceptedMembers,
        );
        final stateHash = buildGroupConfigStateHash(
          groupId: groupId,
          groupConfig: acceptedConfig,
        );
        final invitePayload = GroupInvitePayload(
          id: 'ml003-invite',
          groupId: groupId,
          groupKey: sharedEncryptedKey,
          keyEpoch: keyEpoch,
          groupConfig: acceptedConfig,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          timestamp: addDAt.toIso8601String(),
          recipientPeerId: dana.peerId,
          recipientDeviceId: dana.deviceId,
          recipientTransportPeerId: dana.deviceId,
          recipientMlKemPublicKey: 'mlkem-${dana.deviceId}',
          invitePolicy: GroupInvitePolicy(
            expiresAt: addDAt.add(const Duration(days: 1)),
            allowedDevices: [dana.deviceId],
            assignedRole: 'writer',
            canInviteOthers: false,
            joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
            keyEpoch: keyEpoch,
            reusePolicy: GroupInviteReusePolicy.singleUse,
          ),
          membershipFreshnessProof: GroupInviteMembershipFreshnessProof(
            inviteId: 'ml003-invite',
            groupId: groupId,
            recipientPeerId: dana.peerId,
            recipientDeviceId: dana.deviceId,
            recipientTransportPeerId: dana.deviceId,
            recipientMlKemPublicKey: 'mlkem-${dana.deviceId}',
            inviterPeerId: alice.peerId,
            inviterPublicKey: alice.publicKey,
            keyEpoch: keyEpoch,
            groupConfigStateHash: stateHash,
            membershipWatermark: stateHash,
            issuedAt: addDAt,
            expiresAt: addDAt.add(const Duration(days: 1)),
            inviterMemberSnapshot: {
              'peerId': alice.peerId,
              'username': alice.username,
              'role': 'admin',
              'publicKey': alice.publicKey,
              'mlKemPublicKey': 'mlkem-${alice.peerId}',
            },
          ),
        ).withInviteSignature(signature: 'ml003-signed-invite');
        await pendingInviteRepo.savePendingInvite(
          PendingGroupInvite.fromPayload(invitePayload, receivedAt: addDAt),
        );
        expect(await pendingInviteRepo.getPendingInvite(groupId), isNotNull);

        dana.bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': [
            relayEnvelopeFor(alice, preAddMessageId, preAddSentAt),
            relayEnvelopeFor(alice, alicePostAddMessageId, alicePostAddSentAt),
            relayEnvelopeFor(bob, bobPostAddMessageId, bobPostAddSentAt),
            relayEnvelopeFor(alice, alicePostAddMessageId, alicePostAddSentAt),
            relayEnvelopeFor(bob, bobPostAddMessageId, bobPostAddSentAt),
          ],
          'cursor': '',
        };

        dana.start();
        final (acceptResult, group) = await acceptPendingGroupInvite(
          pendingInviteRepo: pendingInviteRepo,
          groupRepo: dana.groupRepo,
          contactRepo: contactRepo,
          msgRepo: dana.msgRepo,
          bridge: dana.bridge,
          groupId: groupId,
          groupMessageListener: dana.groupMessageListener,
          senderPeerId: dana.peerId,
          senderPublicKey: dana.publicKey,
          senderPrivateKey: dana.privateKey,
          senderUsername: dana.username,
          ownDeviceId: dana.deviceId,
          ownTransportPeerId: dana.deviceId,
          ownMlKemPublicKey: 'mlkem-${dana.deviceId}',
          drainAcceptedInboxAllPages: true,
          acceptedInboxPageSize: 2,
        );
        expect(acceptResult, AcceptPendingGroupInviteResult.success);
        expect(group, isNotNull);
        expect(await pendingInviteRepo.getPendingInvite(groupId), isNull);
        dana.subscribeToGroup(groupId);
        await pump();

        await expectNoMessage(dana, preAddMessageId);
        await expectMessageTuple(
          dana,
          messageId: alicePostAddMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: alicePostAddPlaintext,
          isIncoming: true,
        );
        await expectMessageTuple(
          dana,
          messageId: bobPostAddMessageId,
          senderPeerId: bob.peerId,
          senderUsername: bob.username,
          text: bobPostAddPlaintext,
          isIncoming: true,
        );

        final (liveResult, liveMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: liveAfterDrainPlaintext,
          messageId: liveAfterDrainMessageId,
          timestamp: liveAfterDrainSentAt,
        );
        expect(liveResult.name, 'success');
        expect(liveMessage, isNotNull);
        await pump();

        await expectMessageTuple(
          dana,
          messageId: liveAfterDrainMessageId,
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          text: liveAfterDrainPlaintext,
          isIncoming: true,
        );
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
      'SV-010 duplicate message id from different sender preserves trusted row',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'sv010-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'sv010-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'sv010-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-sv010-duplicate-id-conflict';
        const sharedMessageId = 'sv010-shared-message-id';
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        await alice.createGroup(groupId: groupId, name: 'SV-010 Guard');
        await alice.addMember(groupId: groupId, invitee: bob);
        alice.start();
        bob.start();
        charlie.start();
        await alice.addMember(groupId: groupId, invitee: charlie);
        await alice.broadcastMemberAdded(groupId: groupId, newMember: charlie);
        await pump();

        await alice.sendGroupMessage(
          groupId: groupId,
          text: 'Trusted Alice row',
          messageId: sharedMessageId,
        );
        await pump();

        Future<void> expectTrustedRow(GroupTestUser user) async {
          final message = await user.msgRepo.getMessage(sharedMessageId);
          expect(
            message,
            isNotNull,
            reason: '${user.username} has trusted row',
          );
          expect(message!.senderPeerId, alice.peerId);
          expect(message.text, 'Trusted Alice row');
          final matches = (await user.loadGroupMessages(
            groupId,
          )).where((m) => m.id == sharedMessageId).toList();
          expect(matches, hasLength(1), reason: '${user.username} row count');
        }

        await expectTrustedRow(alice);
        await expectTrustedRow(bob);
        await expectTrustedRow(charlie);

        await network.publish(groupId, bob.peerId, {
          'groupId': groupId,
          'senderId': bob.peerId,
          'senderUsername': bob.username,
          'keyEpoch': 0,
          'text': 'Bob poison row',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'messageId': sharedMessageId,
          'quotedMessageId': 'bob-quote-poison',
        }, senderDeviceId: bob.deviceId);
        await pump();

        await expectTrustedRow(alice);
        await expectTrustedRow(bob);
        await expectTrustedRow(charlie);

        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_DUPLICATE_ID_CONFLICT_REJECTED',
          ),
          isNotEmpty,
        );
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
      'RA-015 already-joined re-add refresh sends latest config and keeps delivery converged',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'ra015-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ra015-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ra015-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ra015-already-joined-readd-refresh';
        const epochOneKey = 'ra015-smoke-key-1';
        const epochTwoKey = 'ra015-smoke-key-2';
        const epochThreeKey = 'ra015-smoke-key-3';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'RA-015 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await pump();
        await Future.wait([
          saveKey(alice, 2, epochTwoKey),
          saveKey(bob, 2, epochTwoKey),
        ]);

        final readdAt = createdAt.add(const Duration(minutes: 4));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await Future.wait([
          saveKey(alice, 3, epochThreeKey),
          saveKey(bob, 3, epochThreeKey),
          saveKey(charlie, 3, epochThreeKey),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await pump();

        charlie.bridge.responses['group:join'] = {
          'ok': true,
          'note': 'ALREADY_JOINED',
        };
        final rejoinResult = await rejoinGroupTopics(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          reason: RejoinReason.inPlaceRecovery,
        );
        expect(rejoinResult.joinedGroupCount, 1);
        expect(rejoinResult.errorCount, 0);

        final joinCommands = charlie.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(1));
        final payload = joinCommands.single['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], groupId);
        expect(payload['groupKey'], epochThreeKey);
        expect(payload['keyEpoch'], 3);
        final config = payload['groupConfig'] as Map<String, dynamic>;
        final members = config['members'] as List<dynamic>;
        expect(members, hasLength(3));
        expect(
          members,
          contains(
            allOf(
              isA<Map<String, dynamic>>(),
              containsPair('peerId', charlie.peerId),
              containsPair('publicKey', charlie.publicKey),
              containsPair('role', 'writer'),
            ),
          ),
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] == 'GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE' &&
                (event['details'] as Map<String, dynamic>)['note'] ==
                    'ALREADY_JOINED',
          ),
          isNotEmpty,
        );

        final aliceSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-015 Alice after already-joined refresh',
          messageId: 'ra015-alice-after-refresh',
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        final bobSend = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-015 Bob after already-joined refresh',
          messageId: 'ra015-bob-after-refresh',
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        final charlieSend = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-015 Charlie after already-joined refresh',
          messageId: 'ra015-charlie-after-refresh',
          timestamp: readdAt.add(const Duration(seconds: 3)),
        );
        expect(aliceSend.$1.name, 'success');
        expect(bobSend.$1.name, 'success');
        expect(charlieSend.$1.name, 'success');
        await pump();

        final aliceMessages = await alice.loadGroupMessages(groupId);
        final bobMessages = await bob.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          aliceMessages.where((m) => m.id == 'ra015-charlie-after-refresh'),
          hasLength(1),
        );
        expect(
          bobMessages.where((m) => m.id == 'ra015-charlie-after-refresh'),
          hasLength(1),
        );
        expect(
          charlieMessages.where((m) => m.id == 'ra015-alice-after-refresh'),
          hasLength(1),
        );
        expect(
          charlieMessages.where((m) => m.id == 'ra015-bob-after-refresh'),
          hasLength(1),
        );
        for (final message in [
          ...aliceMessages.where((m) => m.id == 'ra015-charlie-after-refresh'),
          ...bobMessages.where((m) => m.id == 'ra015-charlie-after-refresh'),
          ...charlieMessages.where(
            (m) =>
                m.id == 'ra015-alice-after-refresh' ||
                m.id == 'ra015-bob-after-refresh',
          ),
        ]) {
          expect(message.keyGeneration, 3);
        }
      },
    );

    test(
      'RA-016 removed-interval replay after re-add is rejected while current delivery converges',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'ra016-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ra016-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ra016-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ra016-removed-interval-replay';
        const epochOneKey = 'ra016-smoke-key-1';
        const epochTwoKey = 'ra016-smoke-key-2';
        const epochThreeKey = 'ra016-smoke-key-3';
        const retainedPreRemovalId = 'ra016-charlie-retained-pre-removal';
        const removedWindowId = 'ra016-delayed-removed-window-replay';
        const removedWindowText = 'RA-016 removed-window replay plaintext';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 30),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'RA-016 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        final retainedSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-016 retained pre-removal message',
          messageId: retainedPreRemovalId,
          timestamp: createdAt.add(const Duration(minutes: 2, seconds: 30)),
        );
        expect(retainedSend.$1.name, 'success');
        await pump();
        expect(
          (await charlie.loadGroupMessages(
            groupId,
          )).where((message) => message.id == retainedPreRemovalId),
          hasLength(1),
        );

        final removedAt = createdAt.add(const Duration(minutes: 3));
        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: removedAt,
        );
        await pump();
        expect(
          await charlie.msgRepo.getLatestSystemEventTimestampForTarget(
            groupId,
            eventType: 'member_removed',
            targetId: charlie.peerId,
          ),
          removedAt,
        );

        await Future.wait([
          saveKey(alice, 2, epochTwoKey),
          saveKey(bob, 2, epochTwoKey),
          saveKey(charlie, 2, epochTwoKey),
        ]);

        final readdAt = createdAt.add(const Duration(minutes: 5));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await Future.wait([
          saveKey(alice, 3, epochThreeKey),
          saveKey(bob, 3, epochThreeKey),
          saveKey(charlie, 3, epochThreeKey),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await pump();

        await charlie.groupMessageListener.handleReplayEnvelope({
          'groupId': groupId,
          'senderId': alice.peerId,
          'senderUsername': alice.username,
          'transportPeerId': alice.deviceId,
          'senderDeviceId': alice.deviceId,
          'keyEpoch': 2,
          'text': removedWindowText,
          'timestamp': removedAt
              .add(const Duration(seconds: 30))
              .toIso8601String(),
          'messageId': removedWindowId,
        }, rethrowOnError: true);

        final charlieAfterReplay = await charlie.loadGroupMessages(groupId);
        expect(
          charlieAfterReplay.where((message) => message.id == removedWindowId),
          isEmpty,
        );
        expect(
          charlieAfterReplay.where(
            (message) => message.text == removedWindowText,
          ),
          isEmpty,
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                    'GROUP_HANDLE_INCOMING_MSG_LOCAL_REMOVED_INTERVAL_REPLAY_REJECTED' ||
                event['event'] ==
                    'GROUP_HANDLE_INCOMING_MSG_SELF_REMOVED_WINDOW_AFTER_REJOIN',
          ),
          isNotEmpty,
        );

        final aliceSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-016 Alice after removed-interval replay',
          messageId: 'ra016-alice-after-replay',
          timestamp: readdAt.add(const Duration(seconds: 1)),
        );
        final bobSend = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-016 Bob after removed-interval replay',
          messageId: 'ra016-bob-after-replay',
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        final charlieSend = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'RA-016 Charlie after removed-interval replay',
          messageId: 'ra016-charlie-after-replay',
          timestamp: readdAt.add(const Duration(seconds: 3)),
        );
        expect(aliceSend.$1.name, 'success');
        expect(bobSend.$1.name, 'success');
        expect(charlieSend.$1.name, 'success');
        await pump();

        final aliceMessages = await alice.loadGroupMessages(groupId);
        final bobMessages = await bob.loadGroupMessages(groupId);
        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          aliceMessages.where((m) => m.id == 'ra016-charlie-after-replay'),
          hasLength(1),
        );
        expect(
          bobMessages.where((m) => m.id == 'ra016-charlie-after-replay'),
          hasLength(1),
        );
        expect(
          charlieMessages.where((m) => m.id == 'ra016-alice-after-replay'),
          hasLength(1),
        );
        expect(
          charlieMessages.where((m) => m.id == 'ra016-bob-after-replay'),
          hasLength(1),
        );
        expect(charlieMessages.where((m) => m.id == removedWindowId), isEmpty);
      },
    );

    test(
      'RA-017 active members keep receiving through repeated Charlie churn',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ra017-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ra017-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ra017-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'ra017-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-ra017-active-member-churn';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 40),
        );
        final allUsers = <GroupTestUser>[alice, bob, charlie, dana];

        Future<void> saveKeyFor(
          Iterable<GroupTestUser> users,
          int epoch,
        ) async {
          for (final user in users) {
            await user.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: epoch,
                encryptedKey: 'ra017-smoke-key-$epoch',
                createdAt: createdAt.add(Duration(minutes: epoch)),
              ),
            );
          }
        }

        Future<void> copyAliceStateTo(
          Iterable<GroupTestUser> users, {
          required int epoch,
        }) async {
          final group = await alice.groupRepo.getGroup(groupId);
          final members = await alice.groupRepo.getMembers(groupId);
          expect(group, isNotNull);
          for (final user in users) {
            await user.groupRepo.saveGroup(
              group!.copyWith(
                myRole: user.peerId == alice.peerId
                    ? GroupRole.admin
                    : GroupRole.member,
              ),
            );
            for (final member in members) {
              await user.groupRepo.saveMember(member);
            }
          }
          await saveKeyFor(users, epoch);
        }

        Future<void> expectIncomingOnce({
          required GroupTestUser recipient,
          required String messageId,
          required String text,
          required GroupTestUser sender,
          required int epoch,
        }) async {
          final matches = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matches,
            hasLength(1),
            reason:
                '${recipient.username} should receive $messageId exactly once',
          );
          final message = matches.single;
          expect(message.isIncoming, isTrue, reason: recipient.username);
          expect(message.text, text, reason: recipient.username);
          expect(
            message.senderPeerId,
            sender.peerId,
            reason: recipient.username,
          );
          expect(message.keyGeneration, epoch, reason: recipient.username);
        }

        Future<void> expectOutgoingOnce({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required int epoch,
        }) async {
          final matches = (await sender.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matches, hasLength(1), reason: sender.username);
          expect(matches.single.isIncoming, isFalse, reason: sender.username);
          expect(matches.single.text, text, reason: sender.username);
          expect(matches.single.keyGeneration, epoch, reason: sender.username);
        }

        Future<void> expectAbsent({
          required GroupTestUser user,
          required Iterable<String> messageIds,
        }) async {
          final ids = (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.id).toSet();
          for (final messageId in messageIds) {
            expect(
              ids,
              isNot(contains(messageId)),
              reason: '${user.username} must not persist $messageId',
            );
          }
        }

        Future<void> sendAndExpect({
          required int cycle,
          required String phase,
          required GroupTestUser sender,
          required List<GroupTestUser> recipients,
          required int epoch,
        }) async {
          final messageId = 'ra017-c$cycle-$phase-${sender.peerId}';
          final text = 'RA-017 cycle $cycle $phase from ${sender.username}';
          final send = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: createdAt.add(
              Duration(minutes: cycle * 10 + (phase == 'removed' ? 1 : 6)),
            ),
          );
          expect(send.$1.name, 'success');
          expect(send.$2, isNotNull);
          expect(send.$2!.keyGeneration, epoch);
          await pump();

          await expectOutgoingOnce(
            sender: sender,
            messageId: messageId,
            text: text,
            epoch: epoch,
          );
          for (final recipient in recipients) {
            await expectIncomingOnce(
              recipient: recipient,
              messageId: messageId,
              text: text,
              sender: sender,
              epoch: epoch,
            );
          }
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'RA-017 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await copyAliceStateTo(allUsers, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        var epoch = 1;
        for (var cycle = 1; cycle <= 3; cycle++) {
          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: createdAt.add(Duration(minutes: cycle * 10)),
          );
          await pump();
          epoch++;
          await saveKeyFor([alice, bob, dana], epoch);

          final removedWindowMessageIds = <String>[];
          for (final sender in [alice, bob, dana]) {
            final recipients = <GroupTestUser>[
              if (sender != alice) alice,
              if (sender != bob) bob,
              if (sender != dana) dana,
            ];
            final messageId = 'ra017-c$cycle-removed-${sender.peerId}';
            removedWindowMessageIds.add(messageId);
            await sendAndExpect(
              cycle: cycle,
              phase: 'removed',
              sender: sender,
              recipients: recipients,
              epoch: epoch,
            );
          }
          await expectAbsent(
            user: charlie,
            messageIds: removedWindowMessageIds,
          );

          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: createdAt.add(Duration(minutes: cycle * 10 + 5)),
          );
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
            eventAt: createdAt.add(Duration(minutes: cycle * 10 + 5)),
          );
          await pump();
          epoch++;
          await copyAliceStateTo(allUsers, epoch: epoch);

          for (final sender in [alice, bob, dana]) {
            final recipients = <GroupTestUser>[
              if (sender != alice) alice,
              if (sender != bob) bob,
              if (sender != charlie) charlie,
              if (sender != dana) dana,
            ];
            await sendAndExpect(
              cycle: cycle,
              phase: 'readd',
              sender: sender,
              recipients: recipients,
              epoch: epoch,
            );
          }

          for (final user in allUsers) {
            final members = await user.groupRepo.getMembers(groupId);
            expect(
              members.map((member) => member.peerId).toSet(),
              {alice.peerId, bob.peerId, charlie.peerId, dana.peerId},
              reason: '${user.username} final member set after cycle $cycle',
            );
            final key = await user.groupRepo.getLatestKey(groupId);
            expect(key, isNotNull, reason: user.username);
            expect(key!.keyGeneration, epoch, reason: user.username);
          }
        }
      },
    );

    test(
      'RA-018 alternating C and D churn keeps rotating sender visibility deterministic',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ra018-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ra018-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ra018-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'ra018-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-ra018-alternating-churn';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 50),
        );
        final allUsers = <GroupTestUser>[alice, bob, charlie, dana];
        final expectedVisibleIdsByPeerId = <String, Set<String>>{
          for (final user in allUsers) user.peerId: <String>{},
        };
        final allRa018MessageIds = <String>{};

        Future<void> saveKeyFor(
          Iterable<GroupTestUser> users,
          int epoch,
        ) async {
          for (final user in users) {
            await user.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: epoch,
                encryptedKey: 'ra018-smoke-key-$epoch',
                createdAt: createdAt.add(Duration(minutes: epoch)),
              ),
            );
          }
        }

        Future<void> copyAliceStateTo(
          Iterable<GroupTestUser> users, {
          required int epoch,
        }) async {
          final group = await alice.groupRepo.getGroup(groupId);
          final members = await alice.groupRepo.getMembers(groupId);
          expect(group, isNotNull);
          for (final user in users) {
            await user.groupRepo.saveGroup(
              group!.copyWith(
                myRole: user.peerId == alice.peerId
                    ? GroupRole.admin
                    : GroupRole.member,
              ),
            );
            for (final member in members) {
              await user.groupRepo.saveMember(member);
            }
          }
          await saveKeyFor(users, epoch);
        }

        Future<void> expectIncomingOnce({
          required GroupTestUser recipient,
          required String messageId,
          required String text,
          required GroupTestUser sender,
          required int epoch,
        }) async {
          final matches = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matches,
            hasLength(1),
            reason:
                '${recipient.username} should receive $messageId exactly once',
          );
          final message = matches.single;
          expect(message.isIncoming, isTrue, reason: recipient.username);
          expect(message.text, text, reason: recipient.username);
          expect(
            message.senderPeerId,
            sender.peerId,
            reason: recipient.username,
          );
          expect(message.keyGeneration, epoch, reason: recipient.username);
        }

        Future<void> expectOutgoingOnce({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required int epoch,
        }) async {
          final matches = (await sender.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matches, hasLength(1), reason: sender.username);
          expect(matches.single.isIncoming, isFalse, reason: sender.username);
          expect(matches.single.text, text, reason: sender.username);
          expect(matches.single.keyGeneration, epoch, reason: sender.username);
        }

        Future<void> expectAbsent({
          required GroupTestUser user,
          required String messageId,
        }) async {
          final ids = (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.id).toSet();
          expect(
            ids,
            isNot(contains(messageId)),
            reason: '${user.username} must not persist inactive $messageId',
          );
        }

        Future<void> sendAndExpect({
          required int cycle,
          required String operation,
          required GroupTestUser sender,
          required List<GroupTestUser> recipients,
          required List<GroupTestUser> inactiveUsers,
          required int epoch,
        }) async {
          final messageId = 'ra018-c$cycle-$operation-${sender.peerId}';
          final text = 'RA-018 cycle $cycle $operation from ${sender.username}';
          allRa018MessageIds.add(messageId);
          expectedVisibleIdsByPeerId[sender.peerId]!.add(messageId);
          for (final recipient in recipients) {
            expectedVisibleIdsByPeerId[recipient.peerId]!.add(messageId);
          }
          final operationMinuteOffset = switch (operation) {
            'charlie-removed' => 1,
            'charlie-readded' => 3,
            'dana-removed' => 5,
            'dana-readded' => 7,
            _ => allRa018MessageIds.length,
          };

          final send = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: createdAt.add(
              Duration(minutes: cycle * 10 + operationMinuteOffset),
            ),
          );
          expect(send.$1.name, 'success');
          expect(send.$2, isNotNull);
          expect(send.$2!.keyGeneration, epoch);
          await pump();
          await waitUntil(() async {
            for (final recipient in recipients) {
              final received = (await recipient.loadGroupMessages(
                groupId,
              )).where((message) => message.id == messageId).length;
              if (received != 1) {
                return false;
              }
            }
            return true;
          });

          await expectOutgoingOnce(
            sender: sender,
            messageId: messageId,
            text: text,
            epoch: epoch,
          );
          for (final recipient in recipients) {
            await expectIncomingOnce(
              recipient: recipient,
              messageId: messageId,
              text: text,
              sender: sender,
              epoch: epoch,
            );
          }
          for (final inactive in inactiveUsers) {
            await expectAbsent(user: inactive, messageId: messageId);
          }
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'RA-018 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await copyAliceStateTo(allUsers, epoch: 1);

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        var epoch = 1;
        for (var cycle = 1; cycle <= 3; cycle++) {
          await alice.removeMember(
            groupId: groupId,
            memberPeerId: charlie.peerId,
            memberUsername: charlie.username,
            removedAt: createdAt.add(Duration(minutes: cycle * 10)),
          );
          await pump();
          epoch++;
          await saveKeyFor([alice, bob, dana], epoch);
          await sendAndExpect(
            cycle: cycle,
            operation: 'charlie-removed',
            sender: alice,
            recipients: [bob, dana],
            inactiveUsers: [charlie],
            epoch: epoch,
          );

          await alice.addMember(
            groupId: groupId,
            invitee: charlie,
            joinedAt: createdAt.add(Duration(minutes: cycle * 10 + 2)),
          );
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: charlie,
            eventAt: createdAt.add(Duration(minutes: cycle * 10 + 2)),
          );
          await pump();
          epoch++;
          await copyAliceStateTo(allUsers, epoch: epoch);
          await sendAndExpect(
            cycle: cycle,
            operation: 'charlie-readded',
            sender: bob,
            recipients: [alice, charlie, dana],
            inactiveUsers: const [],
            epoch: epoch,
          );

          await alice.removeMember(
            groupId: groupId,
            memberPeerId: dana.peerId,
            memberUsername: dana.username,
            removedAt: createdAt.add(Duration(minutes: cycle * 10 + 4)),
          );
          await pump();
          epoch++;
          await saveKeyFor([alice, bob, charlie], epoch);
          await sendAndExpect(
            cycle: cycle,
            operation: 'dana-removed',
            sender: charlie,
            recipients: [alice, bob],
            inactiveUsers: [dana],
            epoch: epoch,
          );

          await alice.addMember(
            groupId: groupId,
            invitee: dana,
            joinedAt: createdAt.add(Duration(minutes: cycle * 10 + 6)),
          );
          await alice.broadcastMemberAdded(
            groupId: groupId,
            newMember: dana,
            eventAt: createdAt.add(Duration(minutes: cycle * 10 + 6)),
          );
          await pump();
          epoch++;
          await copyAliceStateTo(allUsers, epoch: epoch);
          await sendAndExpect(
            cycle: cycle,
            operation: 'dana-readded',
            sender: dana,
            recipients: [alice, bob, charlie],
            inactiveUsers: const [],
            epoch: epoch,
          );
        }

        for (final user in allUsers) {
          final memberPeerIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberPeerIds, {
            alice.peerId,
            bob.peerId,
            charlie.peerId,
            dana.peerId,
          }, reason: '${user.username} final RA-018 member set');
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull, reason: user.username);
          expect(key!.keyGeneration, epoch, reason: user.username);

          final messages = await user.loadGroupMessages(groupId);
          final visibleRa018Ids = messages
              .where((message) => allRa018MessageIds.contains(message.id))
              .map((message) => message.id)
              .toList(growable: false);
          expect(
            visibleRa018Ids.toSet(),
            expectedVisibleIdsByPeerId[user.peerId],
            reason: '${user.username} RA-018 active-interval visibility',
          );
          for (final messageId in visibleRa018Ids.toSet()) {
            expect(
              visibleRa018Ids.where((id) => id == messageId),
              hasLength(1),
              reason: '${user.username} duplicate RA-018 $messageId',
            );
          }
        }
        expect(epoch, 13);
      },
    );

    test(
      'ST-001 model-based membership oracle matches delivered and replayed recipient sets',
      () async {
        const seed = 1001;
        final random = Random(seed);
        final alice = GroupTestUser.create(
          peerId: 'st001-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'st001-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'st001-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'st001-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-st001-recipient-oracle';
        final createdAt = DateTime.utc(2026, 5, 14, 8, 20);
        final allUsers = <GroupTestUser>[alice, bob, charlie, dana];
        final usersByPeerId = {for (final user in allUsers) user.peerId: user};
        final roleByPeerId = {
          alice.peerId: 'alice',
          bob.peerId: 'bob',
          charlie.peerId: 'charlie',
          dana.peerId: 'dana',
        };
        final activePeerIds = <String>{
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dana.peerId,
        };
        final expectedVisibleIdsByPeerId = <String, Set<String>>{
          for (final user in allUsers) user.peerId: <String>{},
        };
        final oracleRows = <Map<String, Object?>>[];
        var logicalStep = 0;
        var epoch = 1;

        Future<void> saveKeyFor(
          Iterable<GroupTestUser> users,
          int keyEpoch,
        ) async {
          for (final user in users) {
            await user.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: keyEpoch,
                encryptedKey: 'st001-oracle-key-$keyEpoch',
                createdAt: createdAt.add(Duration(minutes: keyEpoch)),
              ),
            );
          }
        }

        Future<void> copyAliceStateTo(
          Iterable<GroupTestUser> users, {
          required int keyEpoch,
        }) async {
          final group = await alice.groupRepo.getGroup(groupId);
          final members = await alice.groupRepo.getMembers(groupId);
          expect(group, isNotNull);
          for (final user in users) {
            await user.groupRepo.saveGroup(
              group!.copyWith(
                myRole: user.peerId == alice.peerId
                    ? GroupRole.admin
                    : GroupRole.member,
              ),
            );
            for (final member in members) {
              await user.groupRepo.saveMember(member);
            }
          }
          await saveKeyFor(users, keyEpoch);
        }

        GroupTestUser randomActiveSender({GroupTestUser? not}) {
          final candidates = allUsers
              .where(
                (user) => activePeerIds.contains(user.peerId) && user != not,
              )
              .toList(growable: false);
          expect(candidates, isNotEmpty);
          return candidates[random.nextInt(candidates.length)];
        }

        Future<void> expectOutgoingOnce({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required int keyEpoch,
        }) async {
          final matches = (await sender.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matches, hasLength(1), reason: sender.username);
          expect(matches.single.isIncoming, isFalse, reason: sender.username);
          expect(matches.single.text, text, reason: sender.username);
          expect(
            matches.single.keyGeneration,
            keyEpoch,
            reason: sender.username,
          );
        }

        Future<void> expectIncomingOnce({
          required GroupTestUser recipient,
          required String messageId,
          required String text,
          required GroupTestUser sender,
          required int keyEpoch,
        }) async {
          final matches = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matches,
            hasLength(1),
            reason:
                '${recipient.username} should match ST-001 oracle for $messageId',
          );
          final message = matches.single;
          expect(message.isIncoming, isTrue, reason: recipient.username);
          expect(message.text, text, reason: recipient.username);
          expect(
            message.senderPeerId,
            sender.peerId,
            reason: recipient.username,
          );
          expect(message.keyGeneration, keyEpoch, reason: recipient.username);
        }

        Future<void> expectAbsent({
          required GroupTestUser user,
          required String messageId,
        }) async {
          final ids = (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.id).toSet();
          expect(
            ids,
            isNot(contains(messageId)),
            reason: '${user.username} must not persist non-oracle $messageId',
          );
        }

        Future<void> sendAndCheckOracle({
          required String operation,
          required GroupTestUser sender,
          String deliveryMode = 'normal',
          GroupTestUser? target,
        }) async {
          expect(activePeerIds, contains(sender.peerId));
          logicalStep++;
          final timestamp = createdAt.add(Duration(minutes: logicalStep));
          final messageId = 'st001-$logicalStep-$operation-${sender.peerId}';
          final text = 'ST-001 seed $seed $operation from ${sender.username}';
          final recipientPeerIds = activePeerIds
              .where((peerId) => peerId != sender.peerId)
              .toSet();
          final recipients = recipientPeerIds
              .map((peerId) => usersByPeerId[peerId]!)
              .toList(growable: false);
          final inactiveUsers = allUsers
              .where((user) => !activePeerIds.contains(user.peerId))
              .toList(growable: false);

          expectedVisibleIdsByPeerId[sender.peerId]!.add(messageId);
          for (final peerId in recipientPeerIds) {
            expectedVisibleIdsByPeerId[peerId]!.add(messageId);
          }
          oracleRows.add(<String, Object?>{
            'messageId': messageId,
            'operation': operation,
            'sender': roleByPeerId[sender.peerId],
            'activeRoles': activePeerIds
                .map((peerId) => roleByPeerId[peerId]!)
                .toList(growable: false),
            'recipientRoles': recipientPeerIds
                .map((peerId) => roleByPeerId[peerId]!)
                .toList(growable: false),
            'keyEpoch': epoch,
            'deliveryMode': deliveryMode,
          });

          if (deliveryMode == 'restartReplay') {
            expect(target, isNotNull);
            target!.unsubscribeFromGroup(groupId);
          } else if (deliveryMode == 'heldReplay') {
            expect(target, isNotNull);
            network.holdDeliveriesFor(target!.deviceId);
          } else if (deliveryMode == 'duplicate') {
            network.duplicateOnDeliver = true;
          }

          final send = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(send.$1.name, 'success');
          expect(send.$2, isNotNull);
          expect(send.$2!.keyGeneration, epoch);
          await pump();

          if (deliveryMode == 'restartReplay') {
            await expectAbsent(user: target!, messageId: messageId);
            target.subscribeToGroup(groupId);
            network.duplicateOnDeliver = true;
            await network.publish(groupId, sender.peerId, <String, dynamic>{
              'groupId': groupId,
              'senderId': sender.peerId,
              'senderUsername': sender.username,
              'keyEpoch': epoch,
              'text': text,
              'timestamp': timestamp.toIso8601String(),
              'messageId': messageId,
            }, senderDeviceId: sender.deviceId);
          } else if (deliveryMode == 'heldReplay') {
            await expectAbsent(user: target!, messageId: messageId);
            await network.releaseHeldDeliveriesFor(
              target.deviceId,
              reverse: random.nextBool(),
            );
          }

          network.duplicateOnDeliver = false;
          await pump();

          await expectOutgoingOnce(
            sender: sender,
            messageId: messageId,
            text: text,
            keyEpoch: epoch,
          );
          for (final recipient in recipients) {
            await expectIncomingOnce(
              recipient: recipient,
              messageId: messageId,
              text: text,
              sender: sender,
              keyEpoch: epoch,
            );
          }
          for (final inactiveUser in inactiveUsers) {
            await expectAbsent(user: inactiveUser, messageId: messageId);
          }
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'ST-001 Recipient Oracle',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await copyAliceStateTo(allUsers, keyEpoch: epoch);

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        await sendAndCheckOracle(
          operation: 'initial-all-active',
          sender: randomActiveSender(),
          deliveryMode: 'duplicate',
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 10)),
        );
        activePeerIds.remove(charlie.peerId);
        await pump();
        epoch++;
        await saveKeyFor([alice, bob, dana], epoch);
        await sendAndCheckOracle(
          operation: 'charlie-removed-bob-restart-replay',
          sender: randomActiveSender(not: bob),
          deliveryMode: 'restartReplay',
          target: bob,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 15)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 15)),
        );
        activePeerIds.add(charlie.peerId);
        await pump();
        epoch++;
        await copyAliceStateTo(allUsers, keyEpoch: epoch);
        await sendAndCheckOracle(
          operation: 'charlie-readded-duplicate',
          sender: randomActiveSender(),
          deliveryMode: 'duplicate',
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: dana.peerId,
          memberUsername: dana.username,
          removedAt: createdAt.add(const Duration(minutes: 20)),
        );
        activePeerIds.remove(dana.peerId);
        await pump();
        epoch++;
        await saveKeyFor([alice, bob, charlie], epoch);
        await sendAndCheckOracle(
          operation: 'dana-removed-held-alice',
          sender: randomActiveSender(not: alice),
          deliveryMode: 'heldReplay',
          target: alice,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 25)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: dana,
          eventAt: createdAt.add(const Duration(minutes: 25)),
        );
        activePeerIds.add(dana.peerId);
        await pump();
        epoch++;
        await copyAliceStateTo(allUsers, keyEpoch: epoch);
        await sendAndCheckOracle(
          operation: 'dana-readded-charlie-restart-replay',
          sender: randomActiveSender(not: charlie),
          deliveryMode: 'restartReplay',
          target: charlie,
        );

        for (final user in allUsers) {
          final memberPeerIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberPeerIds, activePeerIds, reason: user.username);
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull, reason: user.username);
          expect(key!.keyGeneration, epoch, reason: user.username);

          final visibleIds = (await user.loadGroupMessages(groupId))
              .where(
                (message) =>
                    oracleRows.any((row) => row['messageId'] == message.id),
              )
              .map((message) => message.id)
              .toList(growable: false);
          expect(
            visibleIds.toSet(),
            expectedVisibleIdsByPeerId[user.peerId],
            reason: '${user.username} final ST-001 recipient oracle',
          );
          for (final messageId in visibleIds.toSet()) {
            expect(
              visibleIds.where((id) => id == messageId),
              hasLength(1),
              reason: '${user.username} duplicate ST-001 $messageId',
            );
          }
        }

        expect(oracleRows, hasLength(5));
        expect(
          oracleRows.map((row) => row['deliveryMode']).toSet().containsAll({
            'duplicate',
            'restartReplay',
            'heldReplay',
          }),
          isTrue,
        );
        expect(epoch, 5);
      },
    );

    test(
      'NW-014 deterministic network chaos run maintains model invariants',
      () async {
        const seed = 14014;
        final random = Random(seed);
        final alice = GroupTestUser.create(
          peerId: 'nw014-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'nw014-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'nw014-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final dana = GroupTestUser.create(
          peerId: 'nw014-dana-peer',
          username: 'Dana',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
          dana.dispose();
        });

        const groupId = 'group-nw014-chaos-model';
        final createdAt = DateTime.utc(2026, 5, 13, 21, 40);
        final allUsers = <GroupTestUser>[alice, bob, charlie, dana];
        final usersByPeerId = {for (final user in allUsers) user.peerId: user};
        final activePeerIds = <String>{
          alice.peerId,
          bob.peerId,
          charlie.peerId,
          dana.peerId,
        };
        final expectedVisibleIdsByPeerId = <String, Set<String>>{
          for (final user in allUsers) user.peerId: <String>{},
        };
        final allNw014MessageIds = <String>{};
        var logicalStep = 0;
        var epoch = 1;

        Future<void> saveKeyFor(
          Iterable<GroupTestUser> users,
          int keyEpoch,
        ) async {
          for (final user in users) {
            await user.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: keyEpoch,
                encryptedKey: 'nw014-chaos-key-$keyEpoch',
                createdAt: createdAt.add(Duration(minutes: keyEpoch)),
              ),
            );
          }
        }

        Future<void> copyAliceStateTo(
          Iterable<GroupTestUser> users, {
          required int keyEpoch,
        }) async {
          final group = await alice.groupRepo.getGroup(groupId);
          final members = await alice.groupRepo.getMembers(groupId);
          expect(group, isNotNull);
          for (final user in users) {
            await user.groupRepo.saveGroup(
              group!.copyWith(
                myRole: user.peerId == alice.peerId
                    ? GroupRole.admin
                    : GroupRole.member,
              ),
            );
            for (final member in members) {
              await user.groupRepo.saveMember(member);
            }
          }
          await saveKeyFor(users, keyEpoch);
        }

        Future<void> expectIncomingOnce({
          required GroupTestUser recipient,
          required String messageId,
          required String text,
          required GroupTestUser sender,
          required int keyEpoch,
        }) async {
          final matches = (await recipient.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(
            matches,
            hasLength(1),
            reason:
                '${recipient.username} should eventually persist $messageId once',
          );
          final message = matches.single;
          expect(message.isIncoming, isTrue, reason: recipient.username);
          expect(message.text, text, reason: recipient.username);
          expect(
            message.senderPeerId,
            sender.peerId,
            reason: recipient.username,
          );
          expect(message.keyGeneration, keyEpoch, reason: recipient.username);
        }

        Future<void> expectOutgoingOnce({
          required GroupTestUser sender,
          required String messageId,
          required String text,
          required int keyEpoch,
        }) async {
          final matches = (await sender.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matches, hasLength(1), reason: sender.username);
          expect(matches.single.isIncoming, isFalse, reason: sender.username);
          expect(matches.single.text, text, reason: sender.username);
          expect(
            matches.single.keyGeneration,
            keyEpoch,
            reason: sender.username,
          );
        }

        Future<void> expectAbsent({
          required GroupTestUser user,
          required String messageId,
        }) async {
          final ids = (await user.loadGroupMessages(
            groupId,
          )).map((message) => message.id).toSet();
          expect(
            ids,
            isNot(contains(messageId)),
            reason: '${user.username} must not persist inactive $messageId',
          );
        }

        Future<void> sendAndConverge({
          required String step,
          required GroupTestUser sender,
          required String chaosMode,
          GroupTestUser? target,
        }) async {
          logicalStep++;
          final timestamp = createdAt.add(Duration(minutes: logicalStep));
          final messageId = 'nw014-$step-${sender.peerId}';
          final text = 'NW-014 seed $seed $step from ${sender.username}';
          final recipients = activePeerIds
              .where((peerId) => peerId != sender.peerId)
              .map((peerId) => usersByPeerId[peerId]!)
              .toList(growable: false);
          final inactiveUsers = allUsers
              .where((user) => !activePeerIds.contains(user.peerId))
              .toList(growable: false);

          allNw014MessageIds.add(messageId);
          expectedVisibleIdsByPeerId[sender.peerId]!.add(messageId);
          for (final recipient in recipients) {
            expectedVisibleIdsByPeerId[recipient.peerId]!.add(messageId);
          }

          if (chaosMode == 'held') {
            network.holdDeliveriesFor(target!.deviceId);
          } else if (chaosMode == 'reconnectReplay') {
            target!.unsubscribeFromGroup(groupId);
          } else if (chaosMode == 'duplicate') {
            network.duplicateOnDeliver = true;
          } else if (chaosMode == 'delay') {
            network.deliveryDelay = Duration(
              milliseconds: 1 + random.nextInt(3),
            );
          }

          final send = await sender.sendGroupMessageViaBridge(
            groupId: groupId,
            text: text,
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(send.$1.name, 'success');
          expect(send.$2, isNotNull);
          expect(send.$2!.keyGeneration, epoch);
          await pump();

          if (chaosMode == 'held') {
            await expectAbsent(user: target!, messageId: messageId);
            await network.releaseHeldDeliveriesFor(
              target.deviceId,
              reverse: random.nextBool(),
            );
          } else if (chaosMode == 'reconnectReplay') {
            await expectAbsent(user: target!, messageId: messageId);
            target.subscribeToGroup(groupId);
            network.duplicateOnDeliver = true;
            await network.publish(groupId, sender.peerId, <String, dynamic>{
              'groupId': groupId,
              'senderId': sender.peerId,
              'senderUsername': sender.username,
              'keyEpoch': epoch,
              'text': text,
              'timestamp': timestamp.toIso8601String(),
              'messageId': messageId,
            }, senderDeviceId: sender.deviceId);
          }
          network.deliveryDelay = null;
          network.duplicateOnDeliver = false;
          await pump();

          await expectOutgoingOnce(
            sender: sender,
            messageId: messageId,
            text: text,
            keyEpoch: epoch,
          );
          for (final recipient in recipients) {
            await expectIncomingOnce(
              recipient: recipient,
              messageId: messageId,
              text: text,
              sender: sender,
              keyEpoch: epoch,
            );
          }
          for (final inactive in inactiveUsers) {
            await expectAbsent(user: inactive, messageId: messageId);
          }
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'NW-014 Chaos Model',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await copyAliceStateTo(allUsers, keyEpoch: epoch);

        alice.start();
        bob.start();
        charlie.start();
        dana.start();

        await sendAndConverge(
          step: 'baseline-delay',
          sender: alice,
          chaosMode: 'delay',
        );
        await sendAndConverge(
          step: 'held-charlie-duplicate',
          sender: bob,
          chaosMode: 'held',
          target: charlie,
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 10)),
        );
        activePeerIds.remove(charlie.peerId);
        await pump();
        epoch++;
        await saveKeyFor([alice, bob, dana], epoch);
        await sendAndConverge(
          step: 'charlie-removed-drop-bob-replay',
          sender: dana,
          chaosMode: 'reconnectReplay',
          target: bob,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 15)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 15)),
        );
        activePeerIds.add(charlie.peerId);
        await pump();
        epoch++;
        await copyAliceStateTo(allUsers, keyEpoch: epoch);
        await sendAndConverge(
          step: 'charlie-readded-duplicate',
          sender: charlie,
          chaosMode: 'duplicate',
        );

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: dana.peerId,
          memberUsername: dana.username,
          removedAt: createdAt.add(const Duration(minutes: 20)),
        );
        activePeerIds.remove(dana.peerId);
        await pump();
        epoch++;
        await saveKeyFor([alice, bob, charlie], epoch);
        await sendAndConverge(
          step: 'dana-removed-held-alice',
          sender: bob,
          chaosMode: 'held',
          target: alice,
        );

        await alice.addMember(
          groupId: groupId,
          invitee: dana,
          joinedAt: createdAt.add(const Duration(minutes: 25)),
        );
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: dana,
          eventAt: createdAt.add(const Duration(minutes: 25)),
        );
        activePeerIds.add(dana.peerId);
        await pump();
        epoch++;
        await copyAliceStateTo(allUsers, keyEpoch: epoch);
        await sendAndConverge(
          step: 'dana-readded-drop-dana-replay',
          sender: alice,
          chaosMode: 'reconnectReplay',
          target: dana,
        );

        for (final user in allUsers) {
          final memberPeerIds = (await user.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet();
          expect(memberPeerIds, activePeerIds, reason: user.username);
          final key = await user.groupRepo.getLatestKey(groupId);
          expect(key, isNotNull, reason: user.username);
          expect(key!.keyGeneration, epoch, reason: user.username);

          final visibleIds = (await user.loadGroupMessages(groupId))
              .where((message) => allNw014MessageIds.contains(message.id))
              .map((message) => message.id)
              .toList(growable: false);
          expect(
            visibleIds.toSet(),
            expectedVisibleIdsByPeerId[user.peerId],
            reason: '${user.username} final NW-014 visibility model',
          );
          for (final messageId in visibleIds.toSet()) {
            expect(
              visibleIds.where((id) => id == messageId),
              hasLength(1),
              reason: '${user.username} duplicate NW-014 $messageId',
            );
          }
        }

        expect(epoch, 5);
        expect(allNw014MessageIds, hasLength(6));
        expect(
          network.deliveryRecords
              .where(
                (record) => allNw014MessageIds.contains(record['messageId']),
              )
              .isNotEmpty,
          isTrue,
        );
      },
    );

    test(
      'KE-010 key-before-config does not authorize pre-config plaintext',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final alice = GroupTestUser.create(
          peerId: 'ke010-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke010-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ke010-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ke010-key-before-config';
        const epochTwoKey = 'ke010-smoke-key-2';
        const preConfigMessageId = 'ke010-pre-config-message';
        const postConfigMessageId = 'ke010-post-config-message';
        final createdAt = DateTime.utc(2026, 5, 12, 11, 50);

        await alice.createGroup(
          groupId: groupId,
          name: 'KE-010 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await charlie.groupRepo.removeMember(groupId, charlie.peerId);
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
          reason: 'Charlie has the key before the active self config arrives',
        );

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 2,
              encryptedKey: epochTwoKey,
              createdAt: createdAt.add(const Duration(minutes: 3)),
            ),
          );
        }

        await Future.wait([saveKey(alice), saveKey(bob), saveKey(charlie)]);
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          2,
        );

        alice.start();
        charlie.start();

        final preConfigSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-010 pre-config message must not persist',
          messageId: preConfigMessageId,
          timestamp: createdAt.add(const Duration(minutes: 4)),
        );
        expect(preConfigSend.$1.name, 'success');
        expect(preConfigSend.$2, isNotNull);
        expect(preConfigSend.$2!.keyGeneration, 2);
        await pump();

        final preConfigMessages = await charlie.loadGroupMessages(groupId);
        expect(
          preConfigMessages.where(
            (message) => message.id == preConfigMessageId,
          ),
          isEmpty,
        );
        expect(
          flowEvents.any(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING',
          ),
          isTrue,
        );

        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: createdAt.add(const Duration(minutes: 5)),
        );
        await pump();
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
          reason: 'The delayed config activates Charlie after the key',
        );

        final postConfigSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-010 post-config message may persist',
          messageId: postConfigMessageId,
          timestamp: createdAt.add(const Duration(minutes: 6)),
        );
        expect(postConfigSend.$1.name, 'success');
        expect(postConfigSend.$2, isNotNull);
        expect(postConfigSend.$2!.keyGeneration, 2);
        await pump();

        final postConfigMessages = await charlie.loadGroupMessages(groupId);
        expect(
          postConfigMessages.where(
            (message) => message.id == preConfigMessageId,
          ),
          isEmpty,
        );
        final delivered = postConfigMessages
            .where((message) => message.id == postConfigMessageId)
            .toList();
        expect(delivered, hasLength(1));
        expect(delivered.single.text, 'KE-010 post-config message may persist');
        expect(delivered.single.keyGeneration, 2);
      },
    );

    test(
      'RA-006 KE-011 delayed old key after re-add does not downgrade Charlie',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'ke011-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke011-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ke011-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final keyUpdates = StreamController<ChatMessage>.broadcast();
        GroupKeyUpdateListener? keyUpdateListener;
        addTearDown(() async {
          debugSetFlowEventSink(null);
          keyUpdateListener?.dispose();
          await keyUpdates.close();
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ke011-delayed-old-key-after-readd';
        const epochOneKey = 'ke011-smoke-key-1';
        const epochTwoKey = 'ke011-smoke-key-2';
        const epochThreeKey = 'ke011-smoke-key-3';
        const staleOldKey = 'ke011-delayed-old-key-1';
        const alicePostStaleId = 'ke011-alice-post-stale';
        const bobPostStaleId = 'ke011-bob-post-stale';
        final createdAt = DateTime.utc(2026, 5, 12, 12, 11);

        await alice.createGroup(
          groupId: groupId,
          name: 'KE-011 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await pump();
        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNull,
        );

        await Future.wait([
          saveKey(alice, 2, epochTwoKey),
          saveKey(bob, 2, epochTwoKey),
        ]);

        final readdAt = createdAt.add(const Duration(minutes: 4));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await Future.wait([
          saveKey(alice, 3, epochThreeKey),
          saveKey(bob, 3, epochThreeKey),
          saveKey(charlie, 3, epochThreeKey),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await pump();

        expect(
          await charlie.groupRepo.getMember(groupId, charlie.peerId),
          isNotNull,
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          3,
        );

        keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdates.stream,
          groupRepo: charlie.groupRepo,
          bridge: charlie.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${charlie.deviceId}',
          getOwnPeerId: () async => charlie.peerId,
          getOwnDeviceId: () async => charlie.deviceId,
        );
        keyUpdateListener.start();

        charlie.bridge.commandLog.clear();
        keyUpdates.add(
          ChatMessage(
            from: alice.deviceId,
            to: charlie.deviceId,
            content: _directKeyUpdateEnvelope(
              groupId: groupId,
              source: alice,
              recipient: charlie,
              keyGeneration: 1,
              encryptedKey: staleOldKey,
              sourceEventId: 'ke011-delayed-old-key-after-readd',
              eventAt: createdAt.add(const Duration(minutes: 5)),
            ),
            timestamp: createdAt
                .add(const Duration(minutes: 5))
                .toIso8601String(),
            isIncoming: true,
            confirmNonce: 'ke011-delayed-old-key-after-readd',
          ),
        );
        await pump();

        final latestAfterStale = await charlie.groupRepo.getLatestKey(groupId);
        expect(latestAfterStale, isNotNull);
        expect(latestAfterStale!.keyGeneration, 3);
        expect(latestAfterStale.encryptedKey, epochThreeKey);
        final historical = await charlie.groupRepo.getKeyByGeneration(
          groupId,
          1,
        );
        expect(historical, isNotNull);
        expect(historical!.encryptedKey, staleOldKey);
        expect(
          charlie.bridge.commandLog.where((c) => c == 'group:updateKey'),
          isEmpty,
        );
        expect(
          flowEvents.any(
            (event) =>
                event['event'] ==
                'GROUP_KEY_UPDATE_LISTENER_HISTORICAL_KEY_SAVED',
          ),
          isTrue,
        );

        final aliceSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-011 Alice after delayed old key',
          messageId: alicePostStaleId,
          timestamp: createdAt.add(const Duration(minutes: 6)),
        );
        expect(aliceSend.$1.name, 'success');
        expect(aliceSend.$2, isNotNull);
        expect(aliceSend.$2!.keyGeneration, 3);

        final bobSend = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-011 Bob after delayed old key',
          messageId: bobPostStaleId,
          timestamp: createdAt.add(const Duration(minutes: 7)),
        );
        expect(bobSend.$1.name, 'success');
        expect(bobSend.$2, isNotNull);
        expect(bobSend.$2!.keyGeneration, 3);
        await pump();

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        final delivered = {
          for (final message in charlieMessages)
            if (message.id == alicePostStaleId || message.id == bobPostStaleId)
              message.id: message,
        };
        expect(delivered.keys.toSet(), {alicePostStaleId, bobPostStaleId});
        expect(delivered[alicePostStaleId]!.keyGeneration, 3);
        expect(delivered[bobPostStaleId]!.keyGeneration, 3);
      },
    );

    test(
      'RA-014 old-key publish after re-add is rejected and current publish still delivers',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        final alice = GroupTestUser.create(
          peerId: 'ra014-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ra014-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ra014-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          debugSetFlowEventSink(null);
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ra014-old-key-publish-after-readd';
        const staleText = 'RA-014 Charlie stale old-key publish';
        const staleMessageId = 'ra014-charlie-stale-old-key';
        const currentText = 'RA-014 Charlie current publish after stale reject';
        const currentMessageId = 'ra014-charlie-current-after-stale';
        const epochOneKey = 'ra014-smoke-key-1';
        const epochTwoKey = 'ra014-smoke-key-2';
        const epochThreeKey = 'ra014-smoke-key-3';
        final createdAt = DateTime.now().toUtc().subtract(
          const Duration(minutes: 20),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int epoch,
          String encryptedKey,
        ) {
          return user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: encryptedKey,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await alice.createGroup(
          groupId: groupId,
          name: 'RA-014 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );
        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await pump();

        await Future.wait([
          saveKey(alice, 2, epochTwoKey),
          saveKey(bob, 2, epochTwoKey),
        ]);

        final readdAt = createdAt.add(const Duration(minutes: 4));
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: readdAt,
        );
        await Future.wait([
          saveKey(alice, 3, epochThreeKey),
          saveKey(bob, 3, epochThreeKey),
          saveKey(charlie, 3, epochThreeKey),
        ]);
        await alice.broadcastMemberAdded(
          groupId: groupId,
          newMember: charlie,
          eventAt: readdAt,
        );
        await pump();

        await network.publish(groupId, charlie.peerId, <String, dynamic>{
          'groupId': groupId,
          'senderId': charlie.peerId,
          'senderUsername': charlie.username,
          'keyEpoch': 1,
          'text': staleText,
          'timestamp': readdAt
              .add(const Duration(seconds: 1))
              .toIso8601String(),
          'messageId': staleMessageId,
        }, senderDeviceId: charlie.deviceId);
        await pump();

        Future<List<GroupMessage>> messagesFor(GroupTestUser user) =>
            user.loadGroupMessages(groupId);
        expect(
          (await messagesFor(
            alice,
          )).where((message) => message.id == staleMessageId),
          isEmpty,
        );
        expect(
          (await messagesFor(
            bob,
          )).where((message) => message.id == staleMessageId),
          isEmpty,
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_HANDLE_INCOMING_MSG_STALE_EPOCH_AFTER_READD_REJECTED',
          ),
          isNotEmpty,
        );

        final currentSend = await charlie.sendGroupMessageViaBridge(
          groupId: groupId,
          text: currentText,
          messageId: currentMessageId,
          timestamp: readdAt.add(const Duration(seconds: 2)),
        );
        expect(currentSend.$1.name, 'success');
        expect(currentSend.$2, isNotNull);
        expect(currentSend.$2!.keyGeneration, 3);
        await pump();

        for (final user in [alice, bob]) {
          final delivered = (await messagesFor(
            user,
          )).where((message) => message.id == currentMessageId).toList();
          expect(delivered, hasLength(1));
          expect(delivered.single.text, currentText);
          expect(delivered.single.keyGeneration, 3);
        }
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
      'NW-015 manual peer dial and disconnect commands preserve group topic state',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'nw015-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'nw015-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'nw015-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-nw015-manual-peer-commands';
        const keyEpoch = 3;
        final createdAt = DateTime.utc(2026, 5, 13, 22, 5);
        final users = [alice, bob, charlie];
        final expectedPeerIds = {alice.peerId, bob.peerId, charlie.peerId};

        await alice.createGroup(
          groupId: groupId,
          name: 'NW-015 Manual Peer Commands',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        final finalGroup = (await alice.groupRepo.getGroup(groupId))!;
        final finalMembers = await alice.groupRepo.getMembers(groupId);
        Future<void> saveConvergedState(
          GroupTestUser user,
          GroupRole role,
        ) async {
          await user.groupRepo.saveGroup(finalGroup.copyWith(myRole: role));
          for (final member in finalMembers) {
            await user.groupRepo.saveMember(member);
          }
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: keyEpoch,
              encryptedKey: 'nw015-stable-key',
              createdAt: createdAt.add(const Duration(minutes: keyEpoch)),
            ),
          );
        }

        await Future.wait([
          saveConvergedState(alice, GroupRole.admin),
          saveConvergedState(bob, GroupRole.member),
          saveConvergedState(charlie, GroupRole.member),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        Future<Set<String>> memberIds(GroupTestUser user) async =>
            (await user.groupRepo.getMembers(
              groupId,
            )).map((member) => member.peerId).toSet();

        Future<void> expectStableGroupState(String label) async {
          expect(
            network.getSubscribers(groupId).toSet(),
            expectedPeerIds,
            reason: '$label topic subscribers',
          );
          for (final user in users) {
            expect(await memberIds(user), expectedPeerIds, reason: label);
            final group = await user.groupRepo.getGroup(groupId);
            expect(group, isNotNull, reason: '${user.username} $label');
            expect(group!.topicName, finalGroup.topicName);
            final key = await user.groupRepo.getLatestKey(groupId);
            expect(key, isNotNull, reason: '${user.username} $label');
            expect(key!.keyGeneration, keyEpoch, reason: user.username);
          }
        }

        await expectStableGroupState('before manual commands');

        alice.bridge.responses['peer:dial'] = {'ok': true, 'connected': true};
        alice.bridge.responses['peer:disconnect'] = {
          'ok': true,
          'disconnected': true,
        };
        final commandStart = alice.bridge.commandLog.length;

        final bobDial = await callP2PPeerDial(
          alice.bridge,
          peerId: bob.peerId,
          addresses: const ['/ip4/127.0.0.1/tcp/4015'],
          timeoutMs: 250,
        );
        expect(bobDial['ok'], isTrue);
        expect(bobDial['connected'], isTrue);
        final bobDisconnect = await callP2PPeerDisconnect(
          alice.bridge,
          peerId: bob.peerId,
        );
        expect(bobDisconnect['ok'], isTrue);
        expect(bobDisconnect['disconnected'], isTrue);

        final charlieDial = await callP2PPeerDial(
          alice.bridge,
          peerId: charlie.peerId,
          addresses: const ['/ip4/127.0.0.1/tcp/4016'],
          timeoutMs: 250,
        );
        expect(charlieDial['ok'], isTrue);
        final charlieDisconnect = await callP2PPeerDisconnect(
          alice.bridge,
          peerId: charlie.peerId,
        );
        expect(charlieDisconnect['ok'], isTrue);

        expect(alice.bridge.commandLog.skip(commandStart).toList(), [
          'peer:dial',
          'peer:disconnect',
          'peer:dial',
          'peer:disconnect',
        ]);
        await expectStableGroupState('after manual commands');

        final aliceSend = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'NW-015 after manual Bob/Charlie peer commands',
          messageId: 'nw015-after-manual-commands',
          timestamp: createdAt.add(const Duration(minutes: 10)),
        );
        expect(aliceSend.$1.name, 'success');
        expect(aliceSend.$2, isNotNull);
        expect(aliceSend.$2!.keyGeneration, keyEpoch);
        await pump();

        final bobSend = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'NW-015 Bob sends after Alice manual disconnect',
          messageId: 'nw015-bob-after-manual-disconnect',
          timestamp: createdAt.add(const Duration(minutes: 11)),
        );
        expect(bobSend.$1.name, 'success');
        expect(bobSend.$2, isNotNull);
        expect(bobSend.$2!.keyGeneration, keyEpoch);
        await pump();

        Future<void> expectMessageOnce({
          required GroupTestUser user,
          required String messageId,
          required String text,
          required String senderPeerId,
          required bool incoming,
        }) async {
          final matches = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == messageId).toList();
          expect(matches, hasLength(1), reason: '${user.username} $messageId');
          expect(matches.single.text, text);
          expect(matches.single.senderPeerId, senderPeerId);
          expect(matches.single.isIncoming, incoming);
          expect(matches.single.keyGeneration, keyEpoch);
        }

        await expectMessageOnce(
          user: alice,
          messageId: 'nw015-after-manual-commands',
          text: 'NW-015 after manual Bob/Charlie peer commands',
          senderPeerId: alice.peerId,
          incoming: false,
        );
        await expectMessageOnce(
          user: bob,
          messageId: 'nw015-after-manual-commands',
          text: 'NW-015 after manual Bob/Charlie peer commands',
          senderPeerId: alice.peerId,
          incoming: true,
        );
        await expectMessageOnce(
          user: charlie,
          messageId: 'nw015-after-manual-commands',
          text: 'NW-015 after manual Bob/Charlie peer commands',
          senderPeerId: alice.peerId,
          incoming: true,
        );
        await expectMessageOnce(
          user: alice,
          messageId: 'nw015-bob-after-manual-disconnect',
          text: 'NW-015 Bob sends after Alice manual disconnect',
          senderPeerId: bob.peerId,
          incoming: true,
        );
        await expectMessageOnce(
          user: bob,
          messageId: 'nw015-bob-after-manual-disconnect',
          text: 'NW-015 Bob sends after Alice manual disconnect',
          senderPeerId: bob.peerId,
          incoming: false,
        );
        await expectMessageOnce(
          user: charlie,
          messageId: 'nw015-bob-after-manual-disconnect',
          text: 'NW-015 Bob sends after Alice manual disconnect',
          senderPeerId: bob.peerId,
          incoming: true,
        );
        await expectStableGroupState('after post-command sends');
      },
    );

    test(
      'IR-006 KE-021 removed member is not targeted by future fake-network key or inbox payloads',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke021-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke021-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ke021-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ke021-fake-network';
        const epochOneKey = 'ke021-smoke-key-1';
        const epochTwoKey = 'ke021-smoke-key-2';
        const messageId = 'ke021-post-removal-message';
        const messageText = 'KE-021 post-removal fake-network message';
        const declinedPeerId = 'ke021-declined-peer';
        const expiredPeerId = 'ke021-expired-peer';
        const neverJoinedPeerId = 'ke021-never-joined-peer';
        final createdAt = DateTime.utc(2026, 5, 11, 8, 27);

        await alice.createGroup(
          groupId: groupId,
          name: 'KE-021 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        Future<void> saveKey(GroupTestUser user, int epoch, String key) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: key,
              createdAt: createdAt.add(Duration(minutes: epoch)),
            ),
          );
        }

        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.start();
        bob.start();

        await alice.removeMember(
          groupId: groupId,
          memberPeerId: charlie.peerId,
          memberUsername: charlie.username,
          removedAt: createdAt.add(const Duration(minutes: 3)),
        );
        await pump();

        expect(network.isSubscribed(groupId, bob.deviceId), isTrue);
        expect(network.isSubscribed(groupId, charlie.deviceId), isFalse);
        expect(
          (await alice.groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          {alice.peerId, bob.peerId},
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          1,
        );

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': epochTwoKey,
          'keyEpoch': 2,
        };
        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke021-key-rotated',
          'topicPeers': 1,
        };

        final capturedKeyUpdates = <String, Map<String, dynamic>>{};
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (transportPeerId, message) async {
            capturedKeyUpdates[transportPeerId] = _decodeDirectKeyUpdatePayload(
              message,
            );
            return true;
          },
        );

        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(capturedKeyUpdates.keys, unorderedEquals([bob.deviceId]));
        expect(capturedKeyUpdates.keys, isNot(contains(charlie.deviceId)));
        expect(
          capturedKeyUpdates.values
              .map((payload) => payload['recipientPeerId'])
              .toSet(),
          {bob.peerId},
        );
        expect(
          capturedKeyUpdates.values
              .map((payload) => payload['recipientDeviceId'])
              .toSet(),
          {bob.deviceId},
        );
        expect(
          capturedKeyUpdates.values
              .map((payload) => payload['recipientTransportPeerId'])
              .toSet(),
          {bob.deviceId},
        );
        await saveKey(bob, rotatedKey.keyGeneration, rotatedKey.encryptedKey);

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: messageText,
          messageId: messageId,
          timestamp: createdAt.add(const Duration(minutes: 4)),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);

        final inboxRaw = alice.bridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        final inboxPayload =
            (jsonDecode(inboxRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final inboxRecipients =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(inboxRecipients, [bob.peerId]);
        expect(inboxRecipients, isNot(contains(alice.peerId)));
        expect(inboxRecipients, isNot(contains(charlie.peerId)));
        expect(inboxRecipients, isNot(contains(declinedPeerId)));
        expect(inboxRecipients, isNot(contains(expiredPeerId)));
        expect(inboxRecipients, isNot(contains(neverJoinedPeerId)));
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['keyEpoch'], 2);
        expect(replayEnvelope['recipientSetHash'], isA<String>());

        await pump();

        final bobDelivered = (await bob.loadGroupMessages(
          groupId,
        )).where((message) => message.id == messageId).toList();
        expect(bobDelivered, hasLength(1));
        expect(bobDelivered.single.isIncoming, isTrue);
        expect(bobDelivered.single.keyGeneration, 2);
        expect(bobDelivered.single.text, messageText);

        final charlieMessages = await charlie.loadGroupMessages(groupId);
        expect(
          charlieMessages.where((message) => message.id == messageId),
          isEmpty,
        );
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          1,
        );
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
      'KE-015 partial key distribution failure blocks sender promotion and preserves fake-network delivery',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke015-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke015-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ke015-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ke015-partial-distribution';
        const epochOneKey = 'ke015-shared-key-1';
        const epochTwoKey = 'ke015-generated-key-2';
        const postFailureMessageId = 'ke015-post-failure-message';
        const postFailureText = 'KE-015 previous epoch after partial failure';
        final createdAt = DateTime.utc(2026, 5, 12, 13, 15);

        await alice.createGroup(
          groupId: groupId,
          name: 'KE-015 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        Future<void> saveKey(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: epochOneKey,
              createdAt: createdAt,
            ),
          );
        }

        await Future.wait([saveKey(alice), saveKey(bob), saveKey(charlie)]);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': epochTwoKey,
          'keyEpoch': 2,
        };
        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke015-key-rotated',
          'topicPeers': 2,
        };

        final keyUpdateAttempts = <String, Map<String, dynamic>>{};
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          distributionAttemptCount: 1,
          sendP2PMessage: (transportPeerId, message) async {
            keyUpdateAttempts[transportPeerId] = _decodeDirectKeyUpdatePayload(
              message,
            );
            return transportPeerId == bob.deviceId;
          },
        );

        expect(rotatedKey, isNull);
        expect(keyUpdateAttempts.keys.toSet(), {
          bob.deviceId,
          charlie.deviceId,
        });
        expect(keyUpdateAttempts[bob.deviceId]!['keyGeneration'], 2);
        expect(keyUpdateAttempts[charlie.deviceId]!['keyGeneration'], 2);
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);
        expect(await alice.groupRepo.getKeyByGeneration(groupId, 2), isNull);
        expect(
          alice.bridge.sentMessages.any((raw) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            final payload = parsed['payload'];
            return parsed['cmd'] == 'group:updateKey' &&
                payload is Map<String, dynamic> &&
                payload['keyEpoch'] == 2;
          }),
          isFalse,
        );
        expect(alice.bridge.commandLog, isNot(contains('group:publish')));

        alice.start();
        bob.start();
        charlie.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: postFailureText,
          messageId: postFailureMessageId,
          timestamp: createdAt.add(const Duration(minutes: 3)),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 1);
        await pump();

        Future<void> expectDeliveredPreviousEpoch(GroupTestUser user) async {
          final delivered = (await user.loadGroupMessages(
            groupId,
          )).where((message) => message.id == postFailureMessageId).toList();
          expect(delivered, hasLength(1), reason: user.username);
          expect(delivered.single.isIncoming, isTrue);
          expect(delivered.single.keyGeneration, 1);
          expect(delivered.single.text, postFailureText);
        }

        await expectDeliveredPreviousEpoch(bob);
        await expectDeliveredPreviousEpoch(charlie);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);
        expect(
          (await charlie.groupRepo.getLatestKey(groupId))!.keyGeneration,
          1,
        );
      },
    );

    test(
      'KE-020 concurrent rotations commit unique epochs before fake-network send',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke020-alice-peer',
          username: 'Alice',
          network: network,
          bridge: _CommittedEpochGenerateBridge(initialCommittedEpoch: 1),
        );
        final bob = GroupTestUser.create(
          peerId: 'ke020-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'ke020-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-ke020-concurrent-rotations';
        const epochOneKey = 'ke020-shared-key-1';
        await alice.createGroup(groupId: groupId, name: 'KE-020');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        Future<void> saveKey(GroupTestUser user, int epoch, String key) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: epoch,
              encryptedKey: key,
              createdAt: DateTime.utc(2026, 5, 11, 14, epoch),
            ),
          );
        }

        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        final firstSendStarted = Completer<void>();
        final secondRotationDistributedBeforeRelease = Completer<void>();
        final releaseFirstSend = Completer<bool>();
        final capturedPayloads = <Map<String, dynamic>>[];
        String? firstBlockedKey;

        Future<bool> captureAndGateSend(String peerId, String message) {
          final payload = _decodeDirectKeyUpdatePayload(message);
          capturedPayloads.add(payload);
          final encryptedKey = payload['encryptedKey'] as String;
          firstBlockedKey ??= encryptedKey;
          if (!firstSendStarted.isCompleted) {
            firstSendStarted.complete();
            return releaseFirstSend.future;
          }
          if (encryptedKey != firstBlockedKey &&
              !releaseFirstSend.isCompleted &&
              !secondRotationDistributedBeforeRelease.isCompleted) {
            secondRotationDistributedBeforeRelease.complete();
          }
          return Future.value(true);
        }

        final firstRotation = rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: captureAndGateSend,
        );

        await firstSendStarted.future.timeout(const Duration(seconds: 1));

        final secondRotation = rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: captureAndGateSend,
        );

        try {
          await secondRotationDistributedBeforeRelease.future.timeout(
            const Duration(milliseconds: 100),
          );
        } on TimeoutException {
          // Green behavior keeps the second rotation queued until epoch 2 has
          // been fully committed by the first rotation.
        }

        releaseFirstSend.complete(true);
        final results = await Future.wait([
          firstRotation,
          secondRotation,
        ]).timeout(const Duration(seconds: 2));

        expect(results, everyElement(isNotNull));
        expect(results.map((key) => key!.keyGeneration).toList(), [2, 3]);
        _expectNoSameEpochDifferentKeys(capturedPayloads);
        expect(
          capturedPayloads
              .map((payload) => payload['keyGeneration'] as int)
              .toSet(),
          {2, 3},
        );

        final finalKey = results.last!;
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 3);
        await Future.wait([
          saveKey(bob, finalKey.keyGeneration, finalKey.encryptedKey),
          saveKey(charlie, finalKey.keyGeneration, finalKey.encryptedKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-020 post-rotation epoch',
          messageId: 'ke020-post-rotation-message',
          timestamp: DateTime.utc(2026, 5, 11, 14, 3),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 3);
        await pump();

        Future<void> expectReceivedFinalEpoch(GroupTestUser user) async {
          final delivered = (await user.loadGroupMessages(groupId))
              .where((message) => message.id == 'ke020-post-rotation-message')
              .toList();
          expect(delivered, hasLength(1));
          expect(delivered.single.isIncoming, isTrue);
          expect(delivered.single.keyGeneration, 3);
          expect(delivered.single.text, 'KE-020 post-rotation epoch');
        }

        await expectReceivedFinalEpoch(bob);
        await expectReceivedFinalEpoch(charlie);
      },
    );

    test(
      'NW-013 stop-start retry reuses pending rotation key and preserves fake-network delivery',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'nw013-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'nw013-bob-peer',
          username: 'Bob',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'nw013-charlie-peer',
          username: 'Charlie',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        });

        const groupId = 'group-nw013-rotation-restart';
        const epochOneKey = 'nw013-shared-key-1';
        const firstGeneratedKey = 'nw013-generated-key-a';
        const secondGeneratedKey = 'nw013-generated-key-b';
        final createdAt = DateTime.utc(2026, 5, 13, 8, 13);

        await alice.createGroup(
          groupId: groupId,
          name: 'NW-013 Fake Network',
          createdAt: createdAt,
        );
        await alice.addMember(
          groupId: groupId,
          invitee: bob,
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        );
        await alice.addMember(
          groupId: groupId,
          invitee: charlie,
          joinedAt: createdAt.add(const Duration(minutes: 2)),
        );

        Future<void> saveKey(
          GroupTestUser user,
          int generation,
          String key,
        ) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: generation,
              encryptedKey: key,
              createdAt: createdAt.add(Duration(minutes: generation)),
            ),
          );
        }

        await Future.wait([
          saveKey(alice, 1, epochOneKey),
          saveKey(bob, 1, epochOneKey),
          saveKey(charlie, 1, epochOneKey),
        ]);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': firstGeneratedKey,
          'keyEpoch': 2,
        };
        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw013-key-rotated',
          'topicPeers': 2,
        };

        final capturedPayloads = <Map<String, dynamic>>[];
        final firstAttempt = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          distributionAttemptCount: 1,
          sendP2PMessage: (transportPeerId, message) async {
            capturedPayloads.add(_decodeDirectKeyUpdatePayload(message));
            return transportPeerId == bob.deviceId;
          },
        );

        expect(firstAttempt, isNull);
        expect((await alice.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);
        expect(await alice.groupRepo.getKeyByGeneration(groupId, 2), isNull);
        final pendingDraft = await alice.groupRepo.getPendingKeyRotation(
          groupId,
        );
        expect(pendingDraft, isNotNull);
        expect(pendingDraft!.keyGeneration, 2);
        expect(pendingDraft.encryptedKey, firstGeneratedKey);

        alice.bridge.commandLog.clear();
        alice.bridge.sentMessages.clear();
        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': secondGeneratedKey,
          'keyEpoch': 2,
        };

        final retry = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (transportPeerId, message) async {
            capturedPayloads.add(_decodeDirectKeyUpdatePayload(message));
            return true;
          },
        );

        expect(retry, isNotNull);
        expect(retry!.keyGeneration, 2);
        expect(retry.encryptedKey, firstGeneratedKey);
        expect(
          alice.bridge.commandLog,
          isNot(contains('group:generateNextKey')),
        );
        _expectNoSameEpochDifferentKeys(capturedPayloads);
        expect(await alice.groupRepo.getPendingKeyRotation(groupId), isNull);

        await Future.wait([
          saveKey(bob, retry.keyGeneration, retry.encryptedKey),
          saveKey(charlie, retry.keyGeneration, retry.encryptedKey),
        ]);

        alice.start();
        bob.start();
        charlie.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'NW-013 post-retry epoch',
          messageId: 'nw013-post-retry-message',
          timestamp: createdAt.add(const Duration(minutes: 4)),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 2);
        await pump();

        Future<void> expectDelivered(GroupTestUser recipient) async {
          final delivered = (await recipient.loadGroupMessages(groupId))
              .where((message) => message.id == 'nw013-post-retry-message')
              .toList();
          expect(delivered, hasLength(1), reason: recipient.username);
          expect(delivered.single.isIncoming, isTrue);
          expect(delivered.single.keyGeneration, 2);
          expect(delivered.single.text, 'NW-013 post-retry epoch');
        }

        await expectDelivered(bob);
        await expectDelivered(charlie);
      },
    );

    test(
      'KE-019 tampered key update is rejected and preserved key still sends over fake network',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke019-alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'ke019-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-ke019-fake-network';
        const epochOneKey = 'ke019-shared-key-1';
        const epochTwoKey = 'ke019-generated-key-2';

        await alice.createGroup(groupId: groupId, name: 'KE-019');
        await alice.addMember(groupId: groupId, invitee: bob);

        Future<void> saveEpochOne(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: epochOneKey,
              createdAt: DateTime.utc(2026, 5, 11, 13),
            ),
          );
        }

        await Future.wait([saveEpochOne(alice), saveEpochOne(bob)]);

        alice.bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': epochTwoKey,
          'keyEpoch': 2,
        };
        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke019-key-rotated',
          'topicPeers': 1,
        };

        String? capturedBobKeyUpdate;
        final rotatedKey = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            if (peerId == bob.deviceId) {
              capturedBobKeyUpdate = message;
            }
            return true;
          },
        );
        expect(rotatedKey, isNotNull);
        expect(rotatedKey!.keyGeneration, 2);
        expect(capturedBobKeyUpdate, isNotNull);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 1);

        final capturedEnvelope =
            jsonDecode(capturedBobKeyUpdate!) as Map<String, dynamic>;
        final encrypted = capturedEnvelope['encrypted'] as Map<String, dynamic>;
        final plaintext =
            jsonDecode(encrypted['ciphertext'] as String)
                as Map<String, dynamic>;
        plaintext['encryptedKey'] = 'ke019-tampered-direct-key-2';
        encrypted['ciphertext'] = jsonEncode(plaintext);
        final tamperedEnvelope = jsonEncode(capturedEnvelope);

        final keyUpdateController = StreamController<ChatMessage>.broadcast();
        final keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdateController.stream,
          groupRepo: bob.groupRepo,
          bridge: bob.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${bob.deviceId}',
          getOwnPeerId: () async => bob.peerId,
          getOwnDeviceId: () async => bob.deviceId,
        );
        addTearDown(() async {
          keyUpdateListener.dispose();
          await keyUpdateController.close();
        });
        keyUpdateListener.start();

        bob.bridge.commandLog.clear();
        keyUpdateController.add(
          ChatMessage(
            from: alice.deviceId,
            to: bob.deviceId,
            content: tamperedEnvelope,
            timestamp: DateTime.utc(2026, 5, 11, 13, 1).toIso8601String(),
            isIncoming: true,
            confirmNonce: 'ke019-tampered-direct-key-update',
          ),
        );
        await pump();

        final bobLatest = await bob.groupRepo.getLatestKey(groupId);
        expect(bobLatest, isNotNull);
        expect(bobLatest!.keyGeneration, 1);
        expect(bobLatest.encryptedKey, epochOneKey);
        expect(bob.bridge.commandLog, contains('message.decrypt'));
        expect(bob.bridge.commandLog, isNot(contains('payload.verify')));
        expect(bob.bridge.commandLog, isNot(contains('group:updateKey')));
        expect(await bob.groupRepo.getKeyByGeneration(groupId, 2), isNull);

        alice.start();
        bob.start();

        final (sendResult, sentMessage) = await bob.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-019 preserved epoch over fake network',
          messageId: 'ke019-preserved-epoch-message',
          timestamp: DateTime.utc(2026, 5, 11, 13, 2),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 1);
        await pump();

        final aliceMessages = await alice.loadGroupMessages(groupId);
        final delivered = aliceMessages
            .where((message) => message.id == 'ke019-preserved-epoch-message')
            .toList();
        expect(delivered, hasLength(1));
        expect(delivered.single.isIncoming, isTrue);
        expect(delivered.single.keyGeneration, 1);
        expect(
          delivered.single.text,
          'KE-019 preserved epoch over fake network',
        );
      },
    );

    test(
      'KE-003 stale lower key update cannot downgrade fake-network delivery',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke003-alice-peer',
          username: 'Alice',
          network: network,
          bridge: _CommittedEpochGenerateBridge(
            initialCommittedEpoch: 3,
            keyPrefix: 'ke003-key',
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'ke003-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
        });

        const groupId = 'group-ke003-stale-lower-key-update';
        const epochThreeKey = 'ke003-shared-key-3';
        await alice.createGroup(groupId: groupId, name: 'KE-003');
        await alice.addMember(groupId: groupId, invitee: bob);

        Future<void> saveEpochThree(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 3,
              encryptedKey: epochThreeKey,
              createdAt: DateTime.utc(2026, 5, 12, 6),
            ),
          );
        }

        await Future.wait([saveEpochThree(alice), saveEpochThree(bob)]);

        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke003-key-rotated',
          'topicPeers': 1,
        };
        final capturedBobUpdates = <int, String>{};

        Future<GroupKeyInfo?> rotateAndCapture() {
          return rotateAndDistributeGroupKey(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            selfPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderUsername: alice.username,
            sourceDeviceId: alice.deviceId,
            sendP2PMessage: (peerId, message) async {
              if (peerId == bob.deviceId) {
                final payload = _decodeDirectKeyUpdatePayload(message);
                capturedBobUpdates[payload['keyGeneration'] as int] = message;
              }
              return true;
            },
          );
        }

        final epochFour = await rotateAndCapture();
        final epochFive = await rotateAndCapture();
        expect(epochFour, isNotNull);
        expect(epochFour!.keyGeneration, 4);
        expect(epochFive, isNotNull);
        expect(epochFive!.keyGeneration, 5);
        expect(capturedBobUpdates.keys.toSet(), {4, 5});
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 3);

        final keyUpdateController = StreamController<ChatMessage>.broadcast();
        final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
        final keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdateController.stream,
          groupRepo: bob.groupRepo,
          bridge: bob.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${bob.deviceId}',
          getOwnPeerId: () async => bob.peerId,
          getOwnDeviceId: () async => bob.deviceId,
          retryPendingGroupKeyRepairs: (request) async {
            repairCalls.add(request);
          },
        );
        addTearDown(() async {
          keyUpdateListener.dispose();
          await keyUpdateController.close();
        });
        keyUpdateListener.start();

        void deliverKeyUpdate(int epoch, int minute) {
          keyUpdateController.add(
            ChatMessage(
              from: alice.deviceId,
              to: bob.deviceId,
              content: capturedBobUpdates[epoch]!,
              timestamp: DateTime.utc(2026, 5, 12, 6, minute).toIso8601String(),
              isIncoming: true,
              confirmNonce: 'ke003-key-update-$epoch',
            ),
          );
        }

        bob.bridge.commandLog.clear();
        deliverKeyUpdate(5, 1);
        await pump();
        final bobEpochFive = await bob.groupRepo.getLatestKey(groupId);
        expect(bobEpochFive, isNotNull);
        expect(bobEpochFive!.keyGeneration, 5);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);

        deliverKeyUpdate(4, 2);
        await pump();
        final bobAfterStale = await bob.groupRepo.getLatestKey(groupId);
        expect(bobAfterStale, isNotNull);
        expect(bobAfterStale!.keyGeneration, 5);
        expect(bobAfterStale.encryptedKey, bobEpochFive.encryptedKey);
        expect(await bob.groupRepo.getKeyByGeneration(groupId, 4), isNotNull);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);

        alice.start();
        bob.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-003 epoch 5 after stale update',
          messageId: 'ke003-epoch5-after-stale',
          timestamp: DateTime.utc(2026, 5, 12, 6, 3),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 5);

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final delivered = bobMessages
            .where((message) => message.id == 'ke003-epoch5-after-stale')
            .toList();
        expect(delivered, hasLength(1));
        expect(delivered.single.isIncoming, isTrue);
        expect(delivered.single.keyGeneration, 5);
        expect(delivered.single.text, 'KE-003 epoch 5 after stale update');
      },
    );

    test(
      'KE-004 same-epoch same-key update is idempotent and delivery remains readable',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke004-alice-peer',
          username: 'Alice',
          network: network,
          bridge: _CommittedEpochGenerateBridge(
            initialCommittedEpoch: 4,
            keyPrefix: 'ke004-key',
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'ke004-bob-peer',
          username: 'Bob',
          network: network,
        );
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          debugSetFlowEventSink(null);
        });

        const groupId = 'group-ke004-same-epoch-same-key-idempotent';
        const epochFourKey = 'ke004-shared-key-4';
        await alice.createGroup(groupId: groupId, name: 'KE-004');
        await alice.addMember(groupId: groupId, invitee: bob);

        Future<void> saveEpochFour(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 4,
              encryptedKey: epochFourKey,
              createdAt: DateTime.utc(2026, 5, 15, 8),
            ),
          );
        }

        await Future.wait([saveEpochFour(alice), saveEpochFour(bob)]);

        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke004-key-rotated',
          'topicPeers': 1,
        };

        String? capturedBobEpochFive;
        final epochFive = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            if (peerId == bob.deviceId) {
              capturedBobEpochFive = message;
            }
            return true;
          },
        );
        expect(epochFive, isNotNull);
        expect(epochFive!.keyGeneration, 5);
        expect(capturedBobEpochFive, isNotNull);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 4);

        final keyUpdateController = StreamController<ChatMessage>.broadcast();
        final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
        final keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdateController.stream,
          groupRepo: bob.groupRepo,
          bridge: bob.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${bob.deviceId}',
          getOwnPeerId: () async => bob.peerId,
          getOwnDeviceId: () async => bob.deviceId,
          retryPendingGroupKeyRepairs: (request) async {
            repairCalls.add(request);
          },
        );
        addTearDown(() async {
          keyUpdateListener.dispose();
          await keyUpdateController.close();
        });
        keyUpdateListener.start();

        void deliver(String nonce, int minute) {
          keyUpdateController.add(
            ChatMessage(
              from: alice.deviceId,
              to: bob.deviceId,
              content: capturedBobEpochFive!,
              timestamp: DateTime.utc(2026, 5, 15, 8, minute).toIso8601String(),
              isIncoming: true,
              confirmNonce: nonce,
            ),
          );
        }

        bob.bridge.commandLog.clear();
        deliver('ke004-key-update-first', 1);
        await pump();
        final bobEpochFive = await bob.groupRepo.getLatestKey(groupId);
        expect(bobEpochFive, isNotNull);
        expect(bobEpochFive!.keyGeneration, 5);
        expect(bobEpochFive.encryptedKey, epochFive.encryptedKey);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);

        deliver('ke004-key-update-duplicate', 2);
        await pump();
        await pump();
        final bobAfterDuplicate = await bob.groupRepo.getLatestKey(groupId);
        expect(bobAfterDuplicate, isNotNull);
        expect(bobAfterDuplicate!.keyGeneration, 5);
        expect(bobAfterDuplicate.encryptedKey, bobEpochFive.encryptedKey);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                'GROUP_KEY_UPDATE_LISTENER_DUPLICATE_GENERATION',
          ),
          hasLength(1),
        );
        expect(
          flowEvents.where(
            (event) =>
                event['event'] ==
                    'GROUP_KEY_UPDATE_LISTENER_SAME_EPOCH_CONFLICT' ||
                event['event'] ==
                    'GROUP_KEY_UPDATE_LISTENER_UPDATE_KEY_FAILED' ||
                event['event'] == 'GROUP_KEY_UPDATE_LISTENER_HANDLE_ERROR',
          ),
          isEmpty,
        );

        alice.start();
        bob.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-004 epoch 5 after duplicate key update',
          messageId: 'ke004-epoch5-after-duplicate',
          timestamp: DateTime.now().toUtc().add(const Duration(seconds: 1)),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 5);

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final delivered = bobMessages
            .where((message) => message.id == 'ke004-epoch5-after-duplicate')
            .toList();
        expect(delivered, hasLength(1));
        expect(delivered.single.isIncoming, isTrue);
        expect(delivered.single.keyGeneration, 5);
        expect(
          delivered.single.text,
          'KE-004 epoch 5 after duplicate key update',
        );
      },
    );

    test(
      'KE-005 same-epoch different key conflict keeps first key over fake network',
      () async {
        final alice = GroupTestUser.create(
          peerId: 'ke005-alice-peer',
          username: 'Alice',
          network: network,
          bridge: _CommittedEpochGenerateBridge(
            initialCommittedEpoch: 4,
            keyPrefix: 'ke005-key',
          ),
        );
        final bob = GroupTestUser.create(
          peerId: 'ke005-bob-peer',
          username: 'Bob',
          network: network,
        );
        addTearDown(() {
          alice.dispose();
          bob.dispose();
          debugSetFlowEventSink(null);
        });

        const groupId = 'group-ke005-same-epoch-key-conflict';
        const epochFourKey = 'ke005-shared-key-4';
        await alice.createGroup(groupId: groupId, name: 'KE-005');
        await alice.addMember(groupId: groupId, invitee: bob);

        Future<void> saveEpochFour(GroupTestUser user) async {
          await user.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 4,
              encryptedKey: epochFourKey,
              createdAt: DateTime.utc(2026, 5, 12, 7),
            ),
          );
        }

        await Future.wait([saveEpochFour(alice), saveEpochFour(bob)]);

        alice.bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ke005-key-rotated',
          'topicPeers': 1,
        };

        String? capturedBobEpochFive;
        final epochFive = await rotateAndDistributeGroupKey(
          bridge: alice.bridge,
          groupRepo: alice.groupRepo,
          groupId: groupId,
          selfPeerId: alice.peerId,
          senderPublicKey: alice.publicKey,
          senderPrivateKey: alice.privateKey,
          senderUsername: alice.username,
          sourceDeviceId: alice.deviceId,
          sendP2PMessage: (peerId, message) async {
            if (peerId == bob.deviceId) {
              capturedBobEpochFive = message;
            }
            return true;
          },
        );
        expect(epochFive, isNotNull);
        expect(epochFive!.keyGeneration, 5);
        expect(capturedBobEpochFive, isNotNull);
        expect((await bob.groupRepo.getLatestKey(groupId))!.keyGeneration, 4);

        final conflictEnvelope = _sameEpochConflictEnvelope(
          capturedBobEpochFive!,
          encryptedKey: 'ke005-conflicting-key-5',
          sourceEventId: 'ke005-conflicting-same-epoch-update',
        );
        final conflictEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink((payload) {
          if (payload['event'] ==
              'GROUP_KEY_UPDATE_LISTENER_SAME_EPOCH_CONFLICT') {
            conflictEvents.add(payload);
          }
        });

        final keyUpdateController = StreamController<ChatMessage>.broadcast();
        final repairCalls = <GroupPendingKeyRepairRetryRequest>[];
        final keyUpdateListener = GroupKeyUpdateListener(
          groupKeyUpdateStream: keyUpdateController.stream,
          groupRepo: bob.groupRepo,
          bridge: bob.bridge,
          getOwnMlKemSecretKey: () async => 'mlkem-secret-${bob.deviceId}',
          getOwnPeerId: () async => bob.peerId,
          getOwnDeviceId: () async => bob.deviceId,
          retryPendingGroupKeyRepairs: (request) async {
            repairCalls.add(request);
          },
        );
        addTearDown(() async {
          keyUpdateListener.dispose();
          await keyUpdateController.close();
        });
        keyUpdateListener.start();

        void deliver(String content, String nonce, int minute) {
          keyUpdateController.add(
            ChatMessage(
              from: alice.deviceId,
              to: bob.deviceId,
              content: content,
              timestamp: DateTime.utc(2026, 5, 12, 7, minute).toIso8601String(),
              isIncoming: true,
              confirmNonce: nonce,
            ),
          );
        }

        bob.bridge.commandLog.clear();
        deliver(capturedBobEpochFive!, 'ke005-key-update-k1', 1);
        await pump();
        final bobEpochFive = await bob.groupRepo.getLatestKey(groupId);
        expect(bobEpochFive, isNotNull);
        expect(bobEpochFive!.keyGeneration, 5);
        expect(bobEpochFive.encryptedKey, epochFive.encryptedKey);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);

        deliver(conflictEnvelope, 'ke005-key-update-k2', 2);
        await pump();
        await pump();
        final bobAfterConflict = await bob.groupRepo.getLatestKey(groupId);
        expect(bobAfterConflict, isNotNull);
        expect(bobAfterConflict!.keyGeneration, 5);
        expect(bobAfterConflict.encryptedKey, bobEpochFive.encryptedKey);
        expect(
          bob.bridge.commandLog.where((c) => c == 'group:updateKey'),
          hasLength(1),
        );
        expect(repairCalls.map((request) => request.keyEpoch).toList(), [5]);
        expect(conflictEvents, isNotEmpty);

        alice.start();
        bob.start();

        final (sendResult, sentMessage) = await alice.sendGroupMessageViaBridge(
          groupId: groupId,
          text: 'KE-005 epoch 5 after same-epoch conflict',
          messageId: 'ke005-epoch5-after-conflict',
          timestamp: DateTime.utc(2026, 5, 12, 7, 3),
        );
        expect(sendResult.name, 'success');
        expect(sentMessage, isNotNull);
        expect(sentMessage!.keyGeneration, 5);

        await pump();
        final bobMessages = await bob.loadGroupMessages(groupId);
        final delivered = bobMessages
            .where((message) => message.id == 'ke005-epoch5-after-conflict')
            .toList();
        expect(delivered, hasLength(1));
        expect(delivered.single.isIncoming, isTrue);
        expect(delivered.single.keyGeneration, 5);
        expect(
          delivered.single.text,
          'KE-005 epoch 5 after same-epoch conflict',
        );
      },
    );

    test(
      'DE-002 rapid 100 same-sender messages stay ordered for both recipients',
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

        const groupId = 'group-de002-same-sender-ordering';
        await alice.createGroup(groupId: groupId, name: 'DE-002 Ordering');
        await alice.addMember(groupId: groupId, invitee: bob);
        await alice.addMember(groupId: groupId, invitee: charlie);

        alice.start();
        bob.start();
        charlie.start();

        final expectedTexts = List<String>.generate(
          100,
          (index) =>
              'DE-002 rapid message ${(index + 1).toString().padLeft(3, '0')}',
        );
        final expectedIds = List<String>.generate(
          100,
          (index) => 'de002-a-${(index + 1).toString().padLeft(3, '0')}',
        );
        final baseTimestamp = DateTime.utc(2026, 5, 10, 13);
        for (var index = 0; index < expectedTexts.length; index += 1) {
          await alice.sendGroupMessage(
            groupId: groupId,
            text: expectedTexts[index],
            messageId: expectedIds[index],
            timestamp: baseTimestamp.add(Duration(microseconds: index)),
          );
        }
        await pump();

        Future<void> expectOrderedIncoming(GroupTestUser user) async {
          final incoming =
              (await user.msgRepo.getMessagesPage(groupId, limit: 200))
                  .where(
                    (message) =>
                        message.isIncoming && message.text.startsWith('DE-002'),
                  )
                  .toList();

          expect(
            incoming.map((message) => message.text).toList(),
            expectedTexts,
            reason:
                '${user.username} should display all DE-002 messages in Alice send order',
          );
          expect(
            incoming.map((message) => message.id).toSet(),
            expectedIds.toSet(),
            reason: '${user.username} should persist each DE-002 message once',
          );
          expect(
            incoming.map((message) => message.timestamp).toList(),
            expectedTexts.indexed
                .map(
                  (entry) =>
                      baseTimestamp.add(Duration(microseconds: entry.$1)),
                )
                .toList(),
            reason:
                '${user.username} should preserve DE-002 sender timestamps for ordering',
          );
        }

        await expectOrderedIncoming(bob);
        await expectOrderedIncoming(charlie);

        final aliceOutgoing =
            (await alice.msgRepo.getMessagesPage(groupId, limit: 200))
                .where(
                  (message) =>
                      !message.isIncoming && message.text.startsWith('DE-002'),
                )
                .toList();
        expect(
          aliceOutgoing.map((message) => message.text).toList(),
          expectedTexts,
        );

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

Map<String, dynamic> _decodeDirectKeyUpdatePayload(String message) {
  final envelope = jsonDecode(message) as Map<String, dynamic>;
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  return jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
}

void _expectNoSameEpochDifferentKeys(
  List<Map<String, dynamic>> capturedPayloads,
) {
  final encryptedKeysByEpoch = <int, Set<String>>{};
  for (final payload in capturedPayloads) {
    final epoch = payload['keyGeneration'] as int;
    final encryptedKey = payload['encryptedKey'] as String;
    encryptedKeysByEpoch.putIfAbsent(epoch, () => <String>{}).add(encryptedKey);
  }

  for (final entry in encryptedKeysByEpoch.entries) {
    expect(
      entry.value,
      hasLength(1),
      reason:
          'epoch ${entry.key} must not be distributed with multiple key values',
    );
  }
}

int _bridgeCommandIndex(FakeBridge bridge, String command, {int? keyEpoch}) {
  for (var i = 0; i < bridge.sentMessages.length; i++) {
    final parsed = jsonDecode(bridge.sentMessages[i]) as Map<String, dynamic>;
    if (parsed['cmd'] != command) {
      continue;
    }
    if (keyEpoch == null) {
      return i;
    }
    final payload = parsed['payload'];
    if (payload is Map<String, dynamic> && payload['keyEpoch'] == keyEpoch) {
      return i;
    }
  }
  return -1;
}

String _sameEpochConflictEnvelope(
  String message, {
  required String encryptedKey,
  required String sourceEventId,
}) {
  final envelope = jsonDecode(message) as Map<String, dynamic>;
  final encrypted = envelope['encrypted'] as Map<String, dynamic>;
  final payload =
      jsonDecode(encrypted['ciphertext'] as String) as Map<String, dynamic>;
  payload['sourceEventId'] = sourceEventId;
  payload['encryptedKey'] = encryptedKey;
  payload['signedPayload'] = canonicalGroupKeyUpdateSignedPayload(
    groupId: payload['groupId'] as String,
    sourcePeerId: payload['sourcePeerId'] as String,
    sourceDeviceId: payload['sourceDeviceId'] as String?,
    sourceTransportPeerId: payload['sourceTransportPeerId'] as String?,
    recipientPeerId: payload['recipientPeerId'] as String?,
    recipientDeviceId: payload['recipientDeviceId'] as String?,
    recipientTransportPeerId: payload['recipientTransportPeerId'] as String?,
    recipientKeyPackageId: payload['recipientKeyPackageId'] as String?,
    keyGeneration: payload['keyGeneration'] as int,
    encryptedKey: encryptedKey,
  );
  payload['signature'] = 'ke005-conflict-signature';
  payload.remove('signedTransitionAudit');
  encrypted['ciphertext'] = jsonEncode(payload);
  return jsonEncode(envelope);
}

String _directKeyUpdateEnvelope({
  required String groupId,
  required GroupTestUser source,
  required GroupTestUser recipient,
  required int keyGeneration,
  required String encryptedKey,
  required String sourceEventId,
  required DateTime eventAt,
}) {
  final signedPayload = canonicalGroupKeyUpdateSignedPayload(
    groupId: groupId,
    sourcePeerId: source.peerId,
    sourceDeviceId: source.deviceId,
    sourceTransportPeerId: source.deviceId,
    recipientPeerId: recipient.peerId,
    recipientDeviceId: recipient.deviceId,
    recipientTransportPeerId: recipient.deviceId,
    recipientKeyPackageId: recipient.deviceIdentity.keyPackageId,
    keyGeneration: keyGeneration,
    encryptedKey: encryptedKey,
  );
  final innerJson = jsonEncode({
    'groupId': groupId,
    'sourceEventId': sourceEventId,
    'eventAt': eventAt.toUtc().toIso8601String(),
    'sourcePeerId': source.peerId,
    'sourceDeviceId': source.deviceId,
    'sourceTransportPeerId': source.deviceId,
    'recipientPeerId': recipient.peerId,
    'recipientDeviceId': recipient.deviceId,
    'recipientTransportPeerId': recipient.deviceId,
    'recipientKeyPackageId': recipient.deviceIdentity.keyPackageId,
    'keyGeneration': keyGeneration,
    'encryptedKey': encryptedKey,
    'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
    'signedPayload': signedPayload,
    'signature': 'signature-$sourceEventId',
  });
  return jsonEncode({
    'encrypted': {
      'kem': 'fake-kem',
      'ciphertext': innerJson,
      'nonce': 'fake-nonce',
    },
  });
}

class _CommittedEpochGenerateBridge extends PassthroughCryptoBridge {
  _CommittedEpochGenerateBridge({
    required int initialCommittedEpoch,
    String keyPrefix = 'ke020-key',
  }) : _committedEpoch = initialCommittedEpoch,
       _keyPrefix = keyPrefix;

  int _committedEpoch;
  final String _keyPrefix;
  int _generatedKeyCount = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:generateNextKey') {
      final nextEpoch = _committedEpoch + 1;
      _generatedKeyCount++;
      responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': '$_keyPrefix-$nextEpoch-$_generatedKeyCount',
        'keyEpoch': nextEpoch,
      };
      return super.send(message);
    }

    if (cmd == 'group:updateKey') {
      final response = await super.send(message);
      final responseMap = jsonDecode(response) as Map<String, dynamic>;
      if (responseMap['ok'] == true) {
        final payload = parsed['payload'] as Map<String, dynamic>;
        final epoch = payload['keyEpoch'] as int;
        if (epoch > _committedEpoch) {
          _committedEpoch = epoch;
        }
      }
      return response;
    }

    return super.send(message);
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
