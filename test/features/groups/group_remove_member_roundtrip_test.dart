import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    as group_send;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';

import '../../shared/fakes/fake_group_pubsub_network.dart';
import '../../shared/fakes/group_test_user.dart';

/// 124 Phase 8 — end-to-end coverage for the `group_remove_member` audit gap.
///
/// Group remove-member enforcement is the monolith-only SPOF: when an admin
/// removes a member there is no central authority that revokes the removed
/// member's access. Enforcement is split across (a) admin-side membership
/// mutation + key rotation, (b) recipient-side config/subscription state, and
/// (c) the send use-case's own membership gate. This round-trip locks all three
/// together with the real multi-user harness (GroupTestUser +
/// FakeGroupPubSubNetwork) so a regression in any layer is caught host-side:
///
///   1. An admin (Alice) removes a member (Charlie) — Charlie is excluded from
///      the live roster on every remaining device and unsubscribed from the
///      topic.
///   2. The admin rotates the group key to a new epoch and distributes it ONLY
///      to the remaining members (Bob), never to the removed member (Charlie).
///   3. Remaining members continue to message each other on the rotated epoch
///      and converge.
///   4. The removed member's post-removal publish is REJECTED by the send
///      use-case (unauthorized / groupNotFound) and never reaches the bridge,
///      and the removed member cannot observe the new-epoch traffic (it has no
///      rotated key and is no longer a recipient — i.e. cannot decrypt the new
///      epoch).
void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future<void>.delayed(const Duration(milliseconds: 50));

  Future<void> waitUntil(
    Future<bool> Function() condition, {
    int maxTicks = 40,
  }) async {
    for (var i = 0; i < maxTicks; i++) {
      if (await condition()) return;
      await pump();
    }
  }

  test(
    'admin remove-member rotates the key, excludes the removed member, and '
    'rejects the removed member post-removal publish',
    () async {
      const groupId = 'grp-remove-member-roundtrip';
      const initialKey = 'remove-roundtrip-initial-key';
      const rotatedKeyValue = 'remove-roundtrip-rotated-key';
      const aliceAfterRemoval = 'Alice after Charlie removal';
      const bobAfterRemoval = 'Bob after Charlie removal';
      const charlieAfterRemoval = 'Charlie should not be able to send';
      final initialKeyCreatedAt = DateTime.now().toUtc();
      final removedAt = initialKeyCreatedAt.add(const Duration(minutes: 1));

      final alice = GroupTestUser.create(
        peerId: 'peer-remove-alice',
        username: 'Alice',
        network: network,
      );
      final bob = GroupTestUser.create(
        peerId: 'peer-remove-bob',
        username: 'Bob',
        network: network,
      );
      final charlie = GroupTestUser.create(
        peerId: 'peer-remove-charlie',
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

      // Alice creates the group and onboards Bob + Charlie at epoch 1.
      await alice.createGroup(groupId: groupId, name: 'Remove Roundtrip Group');
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

      // Sanity: all three are live members at the same initial epoch.
      expect(network.isSubscribed(groupId, alice.peerId), isTrue);
      expect(network.isSubscribed(groupId, bob.peerId), isTrue);
      expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
      expect(
        await charlie.groupRepo.getMember(groupId, charlie.peerId),
        isNotNull,
      );

      // 1. Admin removes Charlie. The removal broadcasts member_removed and
      //    unsubscribes Charlie from the topic; remaining devices drop Charlie
      //    from the live roster.
      await alice.removeMember(
        groupId: groupId,
        memberPeerId: charlie.peerId,
        memberUsername: charlie.username,
        removedAt: removedAt,
      );
      await waitUntil(() async {
        final bobSeesCharlie = await bob.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        // Charlie's own device converges on self no longer being an active
        // member (the group row is retained read-only).
        final charlieSelf = await charlie.groupRepo.getMember(
          groupId,
          charlie.peerId,
        );
        return bobSeesCharlie == null && charlieSelf == null;
      });

      // 2. Admin rotates the group key to epoch 2 and distributes ONLY to the
      //    remaining member (Bob) — never to the removed member (Charlie).
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
      expect(
        keyDistributionTargets,
        isNot(contains(charlie.deviceId)),
        reason: 'removed member must NOT receive the rotated key',
      );
      expect(
        keyDistributionTargets,
        isNot(contains(charlie.peerId)),
        reason: 'removed member must NOT receive the rotated key',
      );

      // Bob adopts the rotated key (mirrors the key-update listener path).
      await bob.groupRepo.saveKey(rotatedKey);

      // Remaining members are on epoch 2; the removed member has no rotated key.
      Future<void> expectRotatedRemainingMember(GroupTestUser user) async {
        final group = await user.groupRepo.getGroup(groupId);
        expect(group, isNotNull, reason: '${user.peerId} still has the group');
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

      await expectRotatedRemainingMember(alice);
      await expectRotatedRemainingMember(bob);

      // Removed member: retained read-only shell, no active membership, no new
      // epoch key, unsubscribed from the topic — it cannot decrypt epoch 2.
      expect(await charlie.groupRepo.getGroup(groupId), isNotNull);
      expect(await charlie.groupRepo.getMember(groupId, charlie.peerId), isNull);
      expect(await charlie.groupRepo.getLatestKey(groupId), isNull);
      expect(network.isSubscribed(groupId, charlie.peerId), isFalse);

      // 3. Remaining members keep messaging on the rotated epoch and converge.
      final (aliceSendResult, aliceMessage) = await alice
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: aliceAfterRemoval,
            messageId: 'remove-roundtrip-alice-after',
          );
      final (bobSendResult, bobMessage) = await bob.sendGroupMessageViaBridge(
        groupId: groupId,
        text: bobAfterRemoval,
        messageId: 'remove-roundtrip-bob-after',
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
      });

      // 4. The removed member's post-removal publish is rejected by the send
      //    use-case and never reaches the bridge.
      final (charlieSendResult, charlieMessage) = await charlie
          .sendGroupMessageViaBridge(
            groupId: groupId,
            text: charlieAfterRemoval,
            messageId: 'remove-roundtrip-charlie-after',
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
        charlie.bridge.commandLog.where((command) => command == 'group:publish'),
        isEmpty,
        reason: 'rejected removed-member send must not publish',
      );

      // The remaining members see each other's rotated-epoch messages; the
      // removed member sees none of the post-removal epoch-2 traffic and its
      // own rejected send was never stored.
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
}
