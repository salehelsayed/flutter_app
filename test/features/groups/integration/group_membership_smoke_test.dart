import 'dart:convert';

import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/accept_pending_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/dissolve_group_use_case.dart'
    as group_dissolve;
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/group_test_user.dart';
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

        // Bob: only 1 incoming message ("Before removal")
        expect(bobIncoming, hasLength(1));
        expect(bobIncoming[0].text, equals('Before removal'));

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
      'non-admin raw membership removal event is ignored by peers',
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

        await admin.createGroup(groupId: groupId, name: 'Auth Guard');
        await admin.addMember(groupId: groupId, invitee: bob);

        admin.start();
        bob.start();

        admin.bridge.commandLog.clear();

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

        admin.dispose();
        bob.dispose();
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
        final removedAt = DateTime.now().toUtc();
        final rejoinKeyCreatedAt = removedAt.add(const Duration(seconds: 10));

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
      'GM-007 preserves allowed pre-removal and post-readd messages while excluding removed-window messages',
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
      'removed member can be re-added with current state and resumes send/receive',
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
        await pump();

        expect(await charlie.groupRepo.getGroup(groupId), isNull);
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
        await pump();

        final charlieAllMessages = await charlie.loadGroupMessages(groupId);
        final charlieIncomingTexts = charlieAllMessages
            .where((message) => message.isIncoming)
            .map((message) => message.text)
            .toList();

        expect(charlieIncomingTexts, contains('Before removal'));
        expect(charlieIncomingTexts, contains('Welcome back'));
        expect(charlieIncomingTexts, isNot(contains('During removal')));

        admin.dispose();
        bob.dispose();
        charlie.dispose();
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
      'offline member converges to dissolved state through replay, cannot send afterwards, and can delete locally without affecting others',
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
  });
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
