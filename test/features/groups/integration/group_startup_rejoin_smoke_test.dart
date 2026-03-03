import 'dart:convert';

import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Startup rejoin smoke tests', () {
    test('rejoin topics then receive live messages after simulated restart',
        () async {
      // -- arrange: set up group normally --
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

      const groupId = 'group-restart';
      await alice.createGroup(groupId: groupId, name: 'Restart Test');
      await alice.addMember(groupId: groupId, invitee: bob);

      // Save a key for Bob's group (simulate invite acceptance stored key)
      await bob.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'test-key-base64',
        createdAt: DateTime.now().toUtc(),
      ));

      alice.start();
      bob.start();

      // Verify normal messaging works
      await alice.sendGroupMessage(groupId: groupId, text: 'Before restart');
      await pump();
      var bobMessages = await bob.loadGroupMessages(groupId);
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      // -- simulate app restart for Bob --
      // Unsubscribe Bob from the network (Go node is fresh)
      network.unsubscribe(groupId, bob.peerId);
      expect(network.isSubscribed(groupId, bob.peerId), isFalse);

      // Message sent while Bob is unsubscribed should NOT reach Bob
      await alice.sendGroupMessage(
          groupId: groupId, text: 'While Bob is offline');
      await pump();
      bobMessages = await bob.loadGroupMessages(groupId);
      // Bob still has only 1 incoming (from before restart)
      expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

      // -- act: rejoin topics (simulates startup rejoin) --
      // rejoinGroupTopics calls bridge but doesn't interact with the fake network.
      // We need to also re-subscribe Bob on the fake network to simulate the
      // Go node actually subscribing to the topic.
      await rejoinGroupTopics(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
      );

      // Verify the bridge received the join command with correct config
      final joinCommands = bob.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], groupId);
      expect(joinCommands.first['payload']['groupKey'], 'test-key-base64');
      expect(joinCommands.first['payload']['keyEpoch'], 1);

      // Re-subscribe on fake network (in production, Go does this internally)
      network.subscribe(groupId, bob.peerId);

      // -- assert: Bob can now receive live messages --
      await alice.sendGroupMessage(
          groupId: groupId, text: 'After Bob rejoined');
      await pump();
      bobMessages = await bob.loadGroupMessages(groupId);
      final incoming = bobMessages.where((m) => m.isIncoming).toList();
      expect(incoming, hasLength(2));
      expect(incoming.map((m) => m.text).toSet(),
          {'Before restart', 'After Bob rejoined'});

      // -- cleanup --
      alice.dispose();
      bob.dispose();
    });

    test('rejoin + drain handles groups with no offline messages', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );

      const groupId = 'group-empty';
      await alice.createGroup(groupId: groupId, name: 'Empty Group');
      await alice.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'key-base64',
        createdAt: DateTime.now().toUtc(),
      ));

      // -- act: rejoin with no messages --
      await rejoinGroupTopics(
        bridge: alice.bridge,
        groupRepo: alice.groupRepo,
      );

      // -- assert: join was called, no errors --
      final joinCommands = alice.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));

      final messages = await alice.loadGroupMessages(groupId);
      expect(messages, isEmpty);

      // -- cleanup --
      alice.dispose();
    });

    test('rejoin sends correct groupConfig with all member public keys',
        () async {
      // -- arrange: Bob has a group with multiple members --
      final bob = GroupTestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );

      const groupId = 'group-multikey';
      final now = DateTime.now().toUtc();

      await bob.groupRepo.saveGroup(GroupModel(
        id: groupId,
        name: 'Multi Key Group',
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: now,
        createdBy: 'alice-peer',
        myRole: GroupRole.member,
      ));

      // Admin with all keys
      await bob.groupRepo.saveMember(GroupMember(
        groupId: groupId,
        peerId: 'alice-peer',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-alice-real',
        mlKemPublicKey: 'mlkem-alice',
        joinedAt: now,
      ));

      // Bob himself
      await bob.groupRepo.saveMember(GroupMember(
        groupId: groupId,
        peerId: 'bob-peer',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-bob-real',
        joinedAt: now,
      ));

      await bob.groupRepo.saveKey(GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 2,
        encryptedKey: 'key-gen2',
        createdAt: now,
      ));

      // -- act --
      await rejoinGroupTopics(
        bridge: bob.bridge,
        groupRepo: bob.groupRepo,
      );

      // -- assert --
      final joinCommands = bob.bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));

      final config =
          joinCommands.first['payload']['groupConfig'] as Map<String, dynamic>;
      final members = config['members'] as List<dynamic>;

      // Both members should have publicKey set
      for (final member in members) {
        final m = member as Map<String, dynamic>;
        expect(m['publicKey'], isNotNull,
            reason: 'publicKey must be set for ${m['peerId']}');
        expect(m['publicKey'], isNotEmpty,
            reason: 'publicKey must be non-empty for ${m['peerId']}');
      }

      // Verify Alice's mlKemPublicKey is included
      final aliceMember =
          members.firstWhere((m) => (m as Map)['peerId'] == 'alice-peer');
      expect(aliceMember['mlKemPublicKey'], 'mlkem-alice');

      // -- cleanup --
      bob.dispose();
    });
  });
}
