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
    test(
      'rejoin topics then receive live messages after simulated restart',
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
        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'test-key-base64',
            createdAt: DateTime.now().toUtc(),
          ),
        );

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
          groupId: groupId,
          text: 'While Bob is offline',
        );
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        // Bob still has only 1 incoming (from before restart)
        expect(bobMessages.where((m) => m.isIncoming), hasLength(1));

        // -- act: rejoin topics (simulates startup rejoin) --
        // rejoinGroupTopics calls bridge but doesn't interact with the fake network.
        // We need to also re-subscribe Bob on the fake network to simulate the
        // Go node actually subscribing to the topic.
        await rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo);

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
          groupId: groupId,
          text: 'After Bob rejoined',
        );
        await pump();
        bobMessages = await bob.loadGroupMessages(groupId);
        final incoming = bobMessages.where((m) => m.isIncoming).toList();
        expect(incoming, hasLength(2));
        expect(incoming.map((m) => m.text).toSet(), {
          'Before restart',
          'After Bob rejoined',
        });

        // -- cleanup --
        alice.dispose();
        bob.dispose();
      },
    );

    test(
      'GL-018 restart rejoin restores all persisted groups exactly once and resumes delivery',
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

        const groupA = 'gl018-group-a';
        const groupB = 'gl018-group-b';
        const groupC = 'gl018-group-c';
        const groupIds = [groupA, groupB, groupC];
        const groupNames = {
          groupA: 'GL-018 Group A',
          groupB: 'GL-018 Group B',
          groupC: 'GL-018 Group C',
        };
        const groupKeys = {
          groupA: 'gl018-key-a',
          groupB: 'gl018-key-b',
          groupC: 'gl018-key-c',
        };
        const groupEpochs = {groupA: 11, groupB: 22, groupC: 33};

        final baseTime = DateTime.utc(2026, 1, 1, 12);

        for (var i = 0; i < groupIds.length; i++) {
          final groupId = groupIds[i];
          await alice.createGroup(
            groupId: groupId,
            name: groupNames[groupId]!,
            createdAt: baseTime.add(Duration(minutes: i)),
          );
          await alice.addMember(
            groupId: groupId,
            invitee: bob,
            joinedAt: baseTime.add(Duration(minutes: 10 + i)),
          );
          await bob.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: groupEpochs[groupId]!,
              encryptedKey: groupKeys[groupId]!,
              createdAt: baseTime.add(Duration(minutes: 20 + i)),
            ),
          );
        }

        await alice.addMember(
          groupId: groupC,
          invitee: charlie,
          joinedAt: baseTime.add(const Duration(minutes: 30)),
        );
        final charlieMembership = await alice.groupRepo.getMember(
          groupC,
          charlie.peerId,
        );
        expect(charlieMembership, isNotNull);
        await bob.groupRepo.saveMember(charlieMembership!);

        alice.start();
        bob.start();

        for (final groupId in groupIds) {
          await alice.sendGroupMessage(
            groupId: groupId,
            text: 'Before restart $groupId',
          );
        }
        await pump();

        for (final groupId in groupIds) {
          final incoming = (await bob.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(
            incoming.map((message) => message.text),
            contains('Before restart $groupId'),
            reason: 'pre-restart setup should be live for $groupId',
          );
          expect(
            incoming.where(
              (message) => message.text == 'Before restart $groupId',
            ),
            hasLength(1),
            reason: 'pre-restart message should arrive once for $groupId',
          );
        }

        for (final groupId in groupIds) {
          network.unsubscribe(groupId, bob.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isFalse);
        }

        bob.bridge.sentMessages.clear();
        bob.bridge.commandLog.clear();
        bob.bridge.sendCallCount = 0;
        bob.bridge.lastCommand = null;
        bob.bridge.lastSentMessage = null;

        final result = await rejoinGroupTopics(
          bridge: bob.bridge,
          groupRepo: bob.groupRepo,
          reason: RejoinReason.startup,
        );

        expect(result.joinedGroupCount, groupIds.length);
        expect(result.skippedNoKeyCount, 0);
        expect(result.errorCount, 0);

        final joinPayloads = bob.bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:join')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .toList();

        expect(joinPayloads, hasLength(groupIds.length));
        for (final groupId in groupIds) {
          final payloadsForGroup = joinPayloads
              .where((payload) => payload['groupId'] == groupId)
              .toList();
          expect(
            payloadsForGroup,
            hasLength(1),
            reason: '$groupId should be joined exactly once',
          );

          final payload = payloadsForGroup.single;
          expect(payload['groupKey'], groupKeys[groupId]);
          expect(payload['keyEpoch'], groupEpochs[groupId]);

          final config = payload['groupConfig'] as Map<String, dynamic>;
          expect(config['name'], groupNames[groupId]);
          expect(config['groupType'], GroupType.chat.toValue());

          final members = (config['members'] as List<dynamic>)
              .map((member) => member as Map<String, dynamic>)
              .toList();
          final membersByPeerId = {
            for (final member in members) member['peerId'] as String: member,
          };
          final expectedPeerIds = {
            alice.peerId,
            bob.peerId,
            if (groupId == groupC) charlie.peerId,
          };
          expect(membersByPeerId.keys.toSet(), expectedPeerIds);
          expect(membersByPeerId[alice.peerId]!['publicKey'], alice.publicKey);
          expect(membersByPeerId[bob.peerId]!['publicKey'], bob.publicKey);
          if (groupId == groupC) {
            expect(
              membersByPeerId[charlie.peerId]!['publicKey'],
              charlie.publicKey,
            );
          }
        }

        for (final groupId in groupIds) {
          network.subscribe(groupId, bob.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isTrue);
        }

        for (final groupId in groupIds) {
          await alice.sendGroupMessage(
            groupId: groupId,
            text: 'After rejoin $groupId',
          );
        }
        await pump();

        for (final groupId in groupIds) {
          final incoming = (await bob.loadGroupMessages(
            groupId,
          )).where((message) => message.isIncoming).toList();
          expect(incoming.map((message) => message.text).toSet(), {
            'Before restart $groupId',
            'After rejoin $groupId',
          });
          expect(
            incoming.where(
              (message) => message.text == 'After rejoin $groupId',
            ),
            hasLength(1),
            reason: 'post-rejoin message should arrive once for $groupId',
          );
        }

        alice.dispose();
        bob.dispose();
        charlie.dispose();
      },
    );

    test('rejoin + drain handles groups with no offline messages', () async {
      // -- arrange --
      final alice = GroupTestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );

      const groupId = 'group-empty';
      await alice.createGroup(groupId: groupId, name: 'Empty Group');
      await alice.groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'key-base64',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      // -- act: rejoin with no messages --
      await rejoinGroupTopics(bridge: alice.bridge, groupRepo: alice.groupRepo);

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

    test(
      'rejoin sends correct groupConfig with all member public keys',
      () async {
        // -- arrange: Bob has a group with multiple members --
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );

        const groupId = 'group-multikey';
        final now = DateTime.now().toUtc();

        await bob.groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Multi Key Group',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: now,
            createdBy: 'alice-peer',
            myRole: GroupRole.member,
          ),
        );

        // Admin with all keys
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-peer',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice-real',
            mlKemPublicKey: 'mlkem-alice',
            joinedAt: now,
          ),
        );

        // Bob himself
        await bob.groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'bob-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob-real',
            joinedAt: now,
          ),
        );

        await bob.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 2,
            encryptedKey: 'key-gen2',
            createdAt: now,
          ),
        );

        // -- act --
        await rejoinGroupTopics(bridge: bob.bridge, groupRepo: bob.groupRepo);

        // -- assert --
        final joinCommands = bob.bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(1));

        final config =
            joinCommands.first['payload']['groupConfig']
                as Map<String, dynamic>;
        final members = config['members'] as List<dynamic>;

        // Both members should have publicKey set
        for (final member in members) {
          final m = member as Map<String, dynamic>;
          expect(
            m['publicKey'],
            isNotNull,
            reason: 'publicKey must be set for ${m['peerId']}',
          );
          expect(
            m['publicKey'],
            isNotEmpty,
            reason: 'publicKey must be non-empty for ${m['peerId']}',
          );
        }

        // Verify Alice's mlKemPublicKey is included
        final aliceMember = members.firstWhere(
          (m) => (m as Map)['peerId'] == 'alice-peer',
        );
        expect(aliceMember['mlKemPublicKey'], 'mlkem-alice');

        // -- cleanup --
        bob.dispose();
      },
    );
  });
}
