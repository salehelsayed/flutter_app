import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/leave_group_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_group_pubsub_network.dart';
import '../../../shared/fakes/group_test_user.dart';

class _RecoveryJoinBridge extends FakeBridge {
  _RecoveryJoinBridge({
    required this.trace,
    required this.network,
    required this.peerId,
    Map<String, List<Map<String, dynamic>>>? inboxMessagesByGroup,
    this.blockedDrainGroupId,
  }) : inboxMessagesByGroup =
           inboxMessagesByGroup ?? <String, List<Map<String, dynamic>>>{},
       super(
         initialResponses: {
           'group:acknowledgeRecovery': {'ok': true},
         },
       );

  final List<String> trace;
  final FakeGroupPubSubNetwork network;
  final String peerId;
  final Map<String, List<Map<String, dynamic>>> inboxMessagesByGroup;
  final String? blockedDrainGroupId;
  final Completer<void> drainStarted = Completer<void>();
  final Completer<void> allowDrain = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:join') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      _recordCommand(message, cmd);
      trace.add('join:start:$groupId');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      network.subscribe(groupId, peerId);
      trace.add('join:complete:$groupId');
      return jsonEncode({'ok': true});
    }

    if (cmd == 'group:acknowledgeRecovery') {
      _recordCommand(message, cmd);
      trace.add('ack:start');
      trace.add('ack:complete');
      return jsonEncode({'ok': true});
    }

    if (cmd == 'group:inboxRetrieveCursor') {
      final payload = parsed['payload'] as Map<String, dynamic>;
      final groupId = payload['groupId'] as String;
      _recordCommand(message, cmd);
      trace.add('drain:start:$groupId');
      if (!drainStarted.isCompleted) {
        drainStarted.complete();
      }
      if (groupId == blockedDrainGroupId) {
        await allowDrain.future;
      }
      final messages = inboxMessagesByGroup[groupId] ?? const [];
      trace.add('drain:complete:$groupId');
      return jsonEncode({'ok': true, 'messages': messages, 'cursor': ''});
    }

    return super.send(message);
  }

  void _recordCommand(String message, String? cmd) {
    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    if (cmd != null) {
      commandLog.add(cmd);
    }
  }
}

class _RestartEmptyRotationBridge extends FakeBridge {
  int? _restoredEpoch;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:generateNextKey') {
      final generatedEpoch = _restoredEpoch == null ? 2 : _restoredEpoch! + 1;
      responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'epoch${generatedEpoch}Key==',
        'keyEpoch': generatedEpoch,
      };
      return super.send(message);
    }

    final response = await super.send(message);
    if (cmd == 'group:updateKey') {
      final responseMap = jsonDecode(response) as Map<String, dynamic>;
      final payload = parsed['payload'] as Map<String, dynamic>;
      if (responseMap['ok'] == true) {
        _restoredEpoch = payload['keyEpoch'] as int;
      }
    }
    return response;
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

void main() {
  late FakeGroupPubSubNetwork network;

  setUp(() {
    network = FakeGroupPubSubNetwork();
    groupRecoveryGate.resetForTest();
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
  });

  Future<void> pump() => Future.delayed(const Duration(milliseconds: 50));

  group('Startup rejoin smoke tests', () {
    test(
      'KE-013 restart-empty Go rotation restores persisted epoch before generate',
      () async {
        final rotationBridge = _RestartEmptyRotationBridge();
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
          bridge: rotationBridge,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
        );
        const groupId = 'ke013-restart-rotation';

        try {
          await alice.createGroup(groupId: groupId, name: 'KE-013 Group');
          await alice.addMember(groupId: groupId, invitee: bob);
          await alice.groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 7,
              encryptedKey: 'epoch7Key==',
              createdAt: DateTime.utc(2026, 5, 11, 12),
            ),
          );

          final sentP2P = <(String, String)>[];
          final result = await rotateAndDistributeGroupKey(
            bridge: rotationBridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            selfPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderUsername: alice.username,
            sendP2PMessage: (peerId, message) async {
              sentP2P.add((peerId, message));
              return true;
            },
          );

          expect(result, isNotNull);
          expect(result!.keyGeneration, 8);
          expect(result.encryptedKey, 'epoch8Key==');
          expect(
            _bridgeCommandIndex(rotationBridge, 'group:updateKey', keyEpoch: 7),
            lessThan(
              _bridgeCommandIndex(rotationBridge, 'group:generateNextKey'),
            ),
          );
          expect(
            _bridgeCommandIndex(rotationBridge, 'group:updateKey', keyEpoch: 8),
            greaterThan(_bridgeCommandIndex(rotationBridge, 'message.encrypt')),
          );
          expect(sentP2P, isNotEmpty);

          final latestKey = await alice.groupRepo.getLatestKey(groupId);
          expect(latestKey, isNotNull);
          expect(latestKey!.keyGeneration, 8);
          expect(await alice.groupRepo.getKeyByGeneration(groupId, 2), isNull);
        } finally {
          alice.dispose();
          bob.dispose();
        }
      },
    );

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

    test(
      'BB-011 restart recovery rejoins all persisted groups before ack and remains live',
      () async {
        final trace = <String>[];
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bobBridge = _RecoveryJoinBridge(
          trace: trace,
          network: network,
          peerId: 'bob-peer',
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'bob-peer',
            circuitAddresses: ['/p2p-circuit/bob'],
            needsGroupRecovery: true,
          ),
        );

        const groupIds = [
          'bb011-smoke-alpha',
          'bb011-smoke-beta',
          'bb011-smoke-gamma',
        ];
        const groupNames = {
          'bb011-smoke-alpha': 'BB-011 Smoke Alpha',
          'bb011-smoke-beta': 'BB-011 Smoke Beta',
          'bb011-smoke-gamma': 'BB-011 Smoke Gamma',
        };
        const latestEpochs = {
          'bb011-smoke-alpha': 3,
          'bb011-smoke-beta': 7,
          'bb011-smoke-gamma': 11,
        };
        const latestKeys = {
          'bb011-smoke-alpha': 'bb011-smoke-key-alpha',
          'bb011-smoke-beta': 'bb011-smoke-key-beta',
          'bb011-smoke-gamma': 'bb011-smoke-key-gamma',
        };
        final baseTime = DateTime.utc(2026, 5, 11, 11);

        try {
          for (var index = 0; index < groupIds.length; index++) {
            final groupId = groupIds[index];
            await alice.createGroup(
              groupId: groupId,
              name: groupNames[groupId]!,
              createdAt: baseTime.add(Duration(minutes: index)),
            );
            await alice.addMember(
              groupId: groupId,
              invitee: bob,
              joinedAt: baseTime.add(Duration(minutes: 10 + index)),
            );
            await bob.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: latestEpochs[groupId]! - 1,
                encryptedKey: 'stale-smoke-key-$groupId',
                createdAt: baseTime.add(Duration(minutes: 20 + index)),
              ),
            );
            await bob.groupRepo.saveKey(
              GroupKeyInfo(
                groupId: groupId,
                keyGeneration: latestEpochs[groupId]!,
                encryptedKey: latestKeys[groupId]!,
                createdAt: baseTime.add(Duration(minutes: 30 + index)),
              ),
            );
          }

          const groupWithCharlie = 'bb011-smoke-gamma';
          await alice.addMember(
            groupId: groupWithCharlie,
            invitee: charlie,
            joinedAt: baseTime.add(const Duration(minutes: 40)),
          );
          final charlieMembership = await alice.groupRepo.getMember(
            groupWithCharlie,
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

          await handleAppResumed(
            bridge: bob.bridge,
            p2pService: p2pService,
            groupRepo: bob.groupRepo,
            groupMsgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          expect(
            bob.bridge.commandLog.where(
              (command) => command == 'group:acknowledgeRecovery',
            ),
            hasLength(1),
          );
          final ackStart = trace.indexOf('ack:start');
          expect(ackStart, isNot(-1));
          for (final groupId in groupIds) {
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);
            final joinComplete = trace.indexOf('join:complete:$groupId');
            expect(joinComplete, isNot(-1));
            expect(
              joinComplete,
              lessThan(ackStart),
              reason:
                  'ack must wait for the $groupId fake-network subscribe join',
            );
          }

          final joinPayloads = bob.bridge.sentMessages
              .map((message) => jsonDecode(message) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:join')
              .map((message) => message['payload'] as Map<String, dynamic>)
              .toList();
          expect(joinPayloads, hasLength(groupIds.length));
          for (final groupId in groupIds) {
            final payload = joinPayloads.singleWhere(
              (payload) => payload['groupId'] == groupId,
            );
            expect(payload['groupKey'], latestKeys[groupId]);
            expect(payload['keyEpoch'], latestEpochs[groupId]);

            final config = payload['groupConfig'] as Map<String, dynamic>;
            expect(config['name'], groupNames[groupId]);
            expect(config['groupType'], GroupType.chat.toValue());
            expect(
              isGroupConfigStateHashValid(
                groupId: groupId,
                groupConfig: config,
              ),
              isTrue,
            );
            final members = (config['members'] as List<dynamic>)
                .cast<Map<String, dynamic>>();
            final memberPeerIds = members
                .map((member) => member['peerId'] as String)
                .toSet();
            expect(memberPeerIds, containsAll({alice.peerId, bob.peerId}));
            if (groupId == groupWithCharlie) {
              expect(memberPeerIds, contains(charlie.peerId));
            }
          }

          for (final groupId in groupIds) {
            await alice.sendGroupMessage(
              groupId: groupId,
              text: 'After ack $groupId',
            );
          }
          await pump();

          for (final groupId in groupIds) {
            final incoming = (await bob.loadGroupMessages(
              groupId,
            )).where((message) => message.isIncoming).toList();
            expect(
              incoming.where((message) => message.text == 'After ack $groupId'),
              hasLength(1),
              reason: 'post-ack publish should stay live for $groupId',
            );
          }
        } finally {
          p2pService.dispose();
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        }
      },
    );

    test(
      'BB-012 restart recovery drains replay before ack and stays live',
      () async {
        final trace = <String>[];
        final bobBridge = _RecoveryJoinBridge(
          trace: trace,
          network: network,
          peerId: 'bob-peer',
        );
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'bob-peer',
            circuitAddresses: ['/p2p-circuit/bob'],
            needsGroupRecovery: true,
          ),
        );
        const groupId = 'bb012-smoke-replay';
        const replayMessageId = 'bb012-smoke-replay-message';
        final createdAt = DateTime.utc(2026, 5, 11, 14);
        final replayAt = createdAt.add(const Duration(minutes: 5));
        final keyInfo = GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'bb012-smoke-key',
          createdAt: createdAt,
        );

        try {
          await alice.createGroup(
            groupId: groupId,
            name: 'BB-012 Smoke Replay',
            createdAt: createdAt,
          );
          await alice.groupRepo.saveKey(keyInfo);
          await alice.addMember(
            groupId: groupId,
            invitee: bob,
            joinedAt: createdAt.add(const Duration(minutes: 1)),
          );
          await bob.groupRepo.saveKey(keyInfo);

          final replayPayload = {
            'groupId': groupId,
            'senderId': alice.peerId,
            'senderUsername': alice.username,
            'senderDeviceId': alice.deviceId,
            'transportPeerId': alice.deviceId,
            'keyEpoch': keyInfo.keyGeneration,
            'text': 'Replay before ack',
            'timestamp': replayAt.toIso8601String(),
            'messageId': replayMessageId,
          };
          final replayEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode(replayPayload),
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderDeviceId: alice.deviceId,
            senderTransportPeerId: alice.deviceId,
            messageId: replayMessageId,
            keyInfo: keyInfo,
            recipientPeerIds: [bob.peerId],
          );
          bobBridge.inboxMessagesByGroup[groupId] = [
            {
              'from': alice.deviceId,
              'message': replayEnvelope,
              'timestamp': replayAt.millisecondsSinceEpoch,
            },
          ];

          alice.start();
          bob.start();
          network.unsubscribe(groupId, bob.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isFalse);

          await handleAppResumed(
            bridge: bob.bridge,
            p2pService: p2pService,
            groupRepo: bob.groupRepo,
            groupMsgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final drainComplete = trace.indexOf('drain:complete:$groupId');
          final ackStart = trace.indexOf('ack:start');
          expect(drainComplete, isNot(-1));
          expect(ackStart, isNot(-1));
          expect(
            drainComplete,
            lessThan(ackStart),
            reason: 'replayed group inbox message must drain before ack',
          );

          final replayedMessages = await bob.loadGroupMessages(groupId);
          expect(
            replayedMessages.where(
              (message) =>
                  message.id == replayMessageId &&
                  message.text == 'Replay before ack' &&
                  message.isIncoming,
            ),
            hasLength(1),
          );

          await alice.sendGroupMessage(
            groupId: groupId,
            text: 'Post-ack live message',
          );
          await pump();

          final afterAckMessages = await bob.loadGroupMessages(groupId);
          expect(
            afterAckMessages.where(
              (message) =>
                  message.text == 'Post-ack live message' && message.isIncoming,
            ),
            hasLength(1),
          );
        } finally {
          p2pService.dispose();
          alice.dispose();
          bob.dispose();
        }
      },
    );

    test(
      'NW-004 reconnect recovery stays live after ack across multiple groups',
      () async {
        final trace = <String>[];
        final bobBridge = _RecoveryJoinBridge(
          trace: trace,
          network: network,
          peerId: 'bob-peer',
        );
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final charlie = GroupTestUser.create(
          peerId: 'charlie-peer',
          username: 'Charlie',
          network: network,
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'bob-peer',
            circuitAddresses: ['/p2p-circuit/bob-repaired'],
            needsGroupRecovery: true,
          ),
        );
        const groupIds = <String>['nw004-smoke-alpha', 'nw004-smoke-beta'];
        final createdAt = DateTime.utc(2026, 5, 13, 9);

        try {
          for (var i = 0; i < groupIds.length; i++) {
            final groupId = groupIds[i];
            final keyInfo = GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'nw004-smoke-key-$i',
              createdAt: createdAt,
            );
            await alice.createGroup(
              groupId: groupId,
              name: 'NW-004 Smoke $i',
              createdAt: createdAt,
            );
            await alice.groupRepo.saveKey(keyInfo);
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
            await bob.groupRepo.saveKey(keyInfo);
            await charlie.groupRepo.saveKey(keyInfo);

            final replayPayload = {
              'groupId': groupId,
              'senderId': alice.peerId,
              'senderUsername': alice.username,
              'senderDeviceId': alice.deviceId,
              'transportPeerId': alice.deviceId,
              'keyEpoch': keyInfo.keyGeneration,
              'text': 'NW-004 replay before ack $groupId',
              'timestamp': createdAt
                  .add(Duration(minutes: 10 + i))
                  .toIso8601String(),
              'messageId': 'nw004-smoke-replay-$groupId',
            };
            final replayEnvelope = await buildGroupOfflineReplayEnvelope(
              bridge: alice.bridge,
              groupRepo: alice.groupRepo,
              groupId: groupId,
              payloadType: groupOfflineReplayPayloadTypeMessage,
              plaintext: jsonEncode(replayPayload),
              senderPeerId: alice.peerId,
              senderPublicKey: alice.publicKey,
              senderPrivateKey: alice.privateKey,
              senderDeviceId: alice.deviceId,
              senderTransportPeerId: alice.deviceId,
              messageId: replayPayload['messageId'] as String,
              keyInfo: keyInfo,
              recipientPeerIds: [bob.peerId],
            );
            bobBridge.inboxMessagesByGroup[groupId] = [
              {
                'from': alice.deviceId,
                'message': replayEnvelope,
                'timestamp': createdAt
                    .add(Duration(minutes: 10 + i))
                    .millisecondsSinceEpoch,
              },
            ];
          }

          alice.start();
          bob.start();
          charlie.start();
          for (final groupId in groupIds) {
            network.unsubscribe(groupId, bob.peerId);
            expect(network.isSubscribed(groupId, bob.peerId), isFalse);
          }

          await handleAppResumed(
            bridge: bob.bridge,
            p2pService: p2pService,
            groupRepo: bob.groupRepo,
            groupMsgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          final ackStart = trace.indexOf('ack:start');
          expect(ackStart, isNot(-1));
          for (final groupId in groupIds) {
            final joinComplete = trace.indexOf('join:complete:$groupId');
            final drainComplete = trace.indexOf('drain:complete:$groupId');
            expect(joinComplete, isNot(-1));
            expect(drainComplete, isNot(-1));
            expect(joinComplete, lessThan(ackStart));
            expect(drainComplete, lessThan(ackStart));
            expect(network.isSubscribed(groupId, bob.peerId), isTrue);
            final replayed = await bob.loadGroupMessages(groupId);
            expect(
              replayed.where(
                (message) =>
                    message.id == 'nw004-smoke-replay-$groupId' &&
                    message.text == 'NW-004 replay before ack $groupId' &&
                    message.isIncoming,
              ),
              hasLength(1),
            );
          }

          for (final groupId in groupIds) {
            await alice.sendGroupMessage(
              groupId: groupId,
              text: 'NW-004 post-ack live $groupId',
              messageId: 'nw004-smoke-live-$groupId',
            );
          }
          await pump();

          for (final groupId in groupIds) {
            final messages = await bob.loadGroupMessages(groupId);
            expect(
              messages.where(
                (message) =>
                    message.text == 'NW-004 post-ack live $groupId' &&
                    message.isIncoming,
              ),
              hasLength(1),
            );
          }
        } finally {
          p2pService.dispose();
          alice.dispose();
          bob.dispose();
          charlie.dispose();
        }
      },
    );

    test(
      'IR-018 restart recovery keeps recovering state until replay drains and live stays active',
      () async {
        final trace = <String>[];
        final bobBridge = _RecoveryJoinBridge(
          trace: trace,
          network: network,
          peerId: 'bob-peer',
          blockedDrainGroupId: 'ir018-smoke-replay',
        );
        final alice = GroupTestUser.create(
          peerId: 'alice-peer',
          username: 'Alice',
          network: network,
        );
        final bob = GroupTestUser.create(
          peerId: 'bob-peer',
          username: 'Bob',
          network: network,
          bridge: bobBridge,
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'bob-peer',
            circuitAddresses: ['/p2p-circuit/bob'],
            needsGroupRecovery: true,
          ),
        );
        const groupId = 'ir018-smoke-replay';
        const replayMessageId = 'ir018-smoke-replay-message';
        final createdAt = DateTime.utc(2026, 5, 12, 10);
        final replayAt = createdAt.add(const Duration(minutes: 6));
        final keyInfo = GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'ir018-smoke-key',
          createdAt: createdAt,
        );

        try {
          await alice.createGroup(
            groupId: groupId,
            name: 'IR-018 Smoke Replay',
            createdAt: createdAt,
          );
          await alice.groupRepo.saveKey(keyInfo);
          await alice.addMember(
            groupId: groupId,
            invitee: bob,
            joinedAt: createdAt.add(const Duration(minutes: 1)),
          );
          await bob.groupRepo.saveKey(keyInfo);

          final replayPayload = {
            'groupId': groupId,
            'senderId': alice.peerId,
            'senderUsername': alice.username,
            'senderDeviceId': alice.deviceId,
            'transportPeerId': alice.deviceId,
            'keyEpoch': keyInfo.keyGeneration,
            'text': 'IR-018 replay before current',
            'timestamp': replayAt.toIso8601String(),
            'messageId': replayMessageId,
          };
          final replayEnvelope = await buildGroupOfflineReplayEnvelope(
            bridge: alice.bridge,
            groupRepo: alice.groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode(replayPayload),
            senderPeerId: alice.peerId,
            senderPublicKey: alice.publicKey,
            senderPrivateKey: alice.privateKey,
            senderDeviceId: alice.deviceId,
            senderTransportPeerId: alice.deviceId,
            messageId: replayMessageId,
            keyInfo: keyInfo,
            recipientPeerIds: [bob.peerId],
          );
          bobBridge.inboxMessagesByGroup[groupId] = [
            {
              'from': alice.deviceId,
              'message': replayEnvelope,
              'timestamp': replayAt.millisecondsSinceEpoch,
            },
          ];

          alice.start();
          bob.start();
          network.unsubscribe(groupId, bob.peerId);
          expect(network.isSubscribed(groupId, bob.peerId), isFalse);

          final resumeFuture = handleAppResumed(
            bridge: bob.bridge,
            p2pService: p2pService,
            groupRepo: bob.groupRepo,
            groupMsgRepo: bob.msgRepo,
            groupMessageListener: bob.groupMessageListener,
          );

          await bobBridge.drainStarted.future;
          expect(isGroupRecoveryInProgress(), isTrue);
          expect(trace, isNot(contains('ack:start')));
          expect(await bob.msgRepo.getMessage(replayMessageId), isNull);

          await alice.sendGroupMessage(
            groupId: groupId,
            text: 'IR-018 live during recovery',
          );
          await pump();
          var bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.text == 'IR-018 live during recovery' &&
                  message.isIncoming,
            ),
            hasLength(1),
          );
          expect(
            bobMessages.where((message) => message.id == replayMessageId),
            isEmpty,
          );

          bobBridge.allowDrain.complete();
          await resumeFuture;

          final drainComplete = trace.indexOf('drain:complete:$groupId');
          final ackStart = trace.indexOf('ack:start');
          expect(drainComplete, isNot(-1));
          expect(ackStart, isNot(-1));
          expect(drainComplete, lessThan(ackStart));
          expect(isGroupRecoveryInProgress(), isFalse);

          bobMessages = await bob.loadGroupMessages(groupId);
          expect(
            bobMessages.where(
              (message) =>
                  message.id == replayMessageId &&
                  message.text == 'IR-018 replay before current' &&
                  message.isIncoming,
            ),
            hasLength(1),
          );
          expect(
            bobMessages.where(
              (message) =>
                  message.text == 'IR-018 live during recovery' &&
                  message.isIncoming,
            ),
            hasLength(1),
          );
        } finally {
          p2pService.dispose();
          alice.dispose();
          bob.dispose();
        }
      },
    );

    test(
      'GM-016 deleted removed-member state is not rejoined from stale pubsub state',
      () async {
        const groupId = 'gm016-rejoin-guard';

        final alice = GroupTestUser.create(
          peerId: 'gm016-alice',
          username: 'Alice',
          network: network,
        );
        final charlie = GroupTestUser.create(
          peerId: 'gm016-charlie',
          username: 'Charlie',
          network: network,
        );

        await alice.createGroup(groupId: groupId, name: 'GM-016 Guard');
        await alice.addMember(groupId: groupId, invitee: charlie);
        await charlie.groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'gm016-charlie-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);

        await leaveGroup(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
          groupId: groupId,
        );

        // Simulate stale transport/discovery state that outlives deleted app
        // persistence. Rejoin must be driven by stored groups/keys only.
        network.subscribe(groupId, charlie.peerId);
        expect(network.isSubscribed(groupId, charlie.peerId), isTrue);
        charlie.bridge.commandLog.clear();

        final result = await rejoinGroupTopics(
          bridge: charlie.bridge,
          groupRepo: charlie.groupRepo,
        );

        expect(result.joinedGroupCount, 0);
        expect(result.skippedNoKeyCount, 0);
        expect(result.errorCount, 0);
        expect(charlie.bridge.commandLog, isNot(contains('group:join')));
        expect(await charlie.groupRepo.getGroup(groupId), isNull);
        expect(await charlie.groupRepo.getMembers(groupId), isEmpty);
        expect(await charlie.groupRepo.getLatestKey(groupId), isNull);

        alice.dispose();
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
