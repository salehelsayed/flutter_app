import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';

class _TracingBridge extends FakeBridge {
  final List<String> trace;

  _TracingBridge(this.trace)
    : super(
        initialResponses: {
          'group:join': {'ok': true},
          'group:inboxRetrieveCursor': {
            'ok': true,
            'messages': [],
            'cursor': '',
          },
        },
      );

  @override
  Future<String> send(String message) async {
    if (message.contains('"cmd":"group:join"')) {
      trace.add('rejoin');
    } else if (message.contains('"cmd":"group:inboxRetrieveCursor"')) {
      trace.add('drain');
    }
    return super.send(message);
  }
}

class _BlockingDrainBridge extends FakeBridge {
  _BlockingDrainBridge({required this.messages})
    : super(
        initialResponses: {
          'group:join': {'ok': true},
          'group:acknowledgeRecovery': {'ok': true},
          'group:leave': {'ok': true},
        },
      );

  final List<Map<String, dynamic>> messages;
  final Completer<void> drainStarted = Completer<void>();
  final Completer<void> allowDrain = Completer<void>();

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
      if (!drainStarted.isCompleted) {
        drainStarted.complete();
      }
      await allowDrain.future;
      return jsonEncode({'ok': true, 'messages': messages, 'cursor': ''});
    }

    return super.send(message);
  }
}

class _RecoveryOrderingBridge extends FakeBridge {
  _RecoveryOrderingBridge({
    required this.trace,
    this.failedGroupId,
    this.failedDrainGroupId,
    this.blockedDrainGroupId,
  }) : super(
         initialResponses: {
           'group:acknowledgeRecovery': {'ok': true},
         },
       );

  final List<String> trace;
  final String? failedGroupId;
  final String? failedDrainGroupId;
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
      trace.add('join:complete:$groupId');
      if (groupId == failedGroupId) {
        return jsonEncode({
          'ok': false,
          'errorCode': 'GROUP_ERROR',
          'errorMessage': 'forced failure for $groupId',
        });
      }
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
      if (groupId == failedDrainGroupId) {
        trace.add('drain:error:$groupId');
        return jsonEncode({
          'ok': false,
          'errorCode': 'GROUP_INBOX_ERROR',
          'errorMessage': 'forced drain failure for $groupId',
        });
      }
      trace.add('drain:complete:$groupId');
      return jsonEncode({'ok': true, 'messages': [], 'cursor': ''});
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

class _RelayReconnectP2PService extends FakeP2PService {
  _RelayReconnectP2PService(this.trace)
    : super(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          relayState: 'degraded',
          healthyRelayCount: 0,
          needsGroupRecovery: true,
        ),
        recoveryMethod: 'watchdog_restart',
      );

  final List<String> trace;

  @override
  Future<void> performImmediateHealthCheck() async {
    trace.add('relayReconnect/healthCheck');
    await super.performImmediateHealthCheck();
    emitState(
      const NodeState(
        isStarted: true,
        peerId: 'my-peer',
        circuitAddresses: ['/p2p-circuit/recovered'],
        relayState: 'online',
        healthyRelayCount: 1,
        needsGroupRecovery: true,
      ),
    );
  }
}

void main() {
  group('handleAppResumed group recovery', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late InMemoryGroupRepository groupRepo;
    late InMemoryGroupMessageRepository groupMsgRepo;

    setUp(() {
      bridge = _TracingBridge([]);
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
          needsGroupRecovery: true,
        ),
      );
      groupRepo = InMemoryGroupRepository();
      groupMsgRepo = InMemoryGroupMessageRepository();
      groupRecoveryGate.resetForTest();
    });

    tearDown(() {
      groupRecoveryGate.resetForTest();
      p2pService.dispose();
    });

    Future<void> seedRecoveryGroup({
      required String groupId,
      required int latestEpoch,
      required String latestKey,
      required DateTime createdAt,
    }) async {
      final metadataAt = createdAt.add(const Duration(hours: 1));
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Stale $groupId',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          createdAt: createdAt,
          createdBy: 'admin-$groupId',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: latestEpoch - 1,
          encryptedKey: 'stale-key-$groupId',
          createdAt: createdAt,
        ),
      );
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Latest $groupId',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          description: 'Latest description $groupId',
          createdAt: createdAt,
          createdBy: 'admin-$groupId',
          myRole: GroupRole.member,
          lastMetadataEventAt: metadataAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'admin-$groupId',
          username: 'Admin $groupId',
          role: MemberRole.admin,
          publicKey: 'latest-admin-pk-$groupId',
          mlKemPublicKey: 'latest-admin-mlkem-$groupId',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'writer-$groupId',
          username: 'Writer $groupId',
          role: MemberRole.writer,
          publicKey: 'latest-writer-pk-$groupId',
          joinedAt: createdAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: latestEpoch,
          encryptedKey: latestKey,
          createdAt: metadataAt,
        ),
      );
    }

    List<Map<String, dynamic>> sentJoinPayloads(FakeBridge bridge) {
      return bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((command) => command['cmd'] == 'group:join')
          .map((command) => command['payload'] as Map<String, dynamic>)
          .toList();
    }

    test(
      'BB-011 acknowledges recovery only after every persisted group rejoin succeeds',
      () async {
        final trace = <String>[];
        bridge = _RecoveryOrderingBridge(trace: trace);
        const groupIds = [
          'bb011-life-alpha',
          'bb011-life-beta',
          'bb011-life-gamma',
        ];
        const latestEpochs = {
          'bb011-life-alpha': 3,
          'bb011-life-beta': 7,
          'bb011-life-gamma': 11,
        };
        const latestKeys = {
          'bb011-life-alpha': 'life-key-alpha',
          'bb011-life-beta': 'life-key-beta',
          'bb011-life-gamma': 'life-key-gamma',
        };
        final baseTime = DateTime.utc(2026, 5, 11, 9);

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          await seedRecoveryGroup(
            groupId: groupId,
            latestEpoch: latestEpochs[groupId]!,
            latestKey: latestKeys[groupId]!,
            createdAt: baseTime.add(Duration(minutes: index)),
          );
        }

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );
        final ackStart = trace.indexOf('ack:start');
        expect(ackStart, isNot(-1));
        for (final groupId in groupIds) {
          expect(trace, contains('join:start:$groupId'));
          final joinComplete = trace.indexOf('join:complete:$groupId');
          expect(joinComplete, isNot(-1));
          expect(
            joinComplete,
            lessThan(ackStart),
            reason:
                'ack must wait for the $groupId group:join future to finish',
          );
        }

        final payloads = sentJoinPayloads(bridge);
        expect(payloads, hasLength(groupIds.length));
        for (final groupId in groupIds) {
          final payload = payloads.singleWhere(
            (payload) => payload['groupId'] == groupId,
          );
          expect(payload['groupKey'], latestKeys[groupId]);
          expect(payload['keyEpoch'], latestEpochs[groupId]);

          final config = payload['groupConfig'] as Map<String, dynamic>;
          expect(config['name'], 'Latest $groupId');
          expect(config['description'], 'Latest description $groupId');
          expect(config['groupType'], GroupType.chat.toValue());
          expect(
            isGroupConfigStateHashValid(groupId: groupId, groupConfig: config),
            isTrue,
          );
          final members = (config['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(
            members,
            contains(
              allOf(
                containsPair('peerId', 'admin-$groupId'),
                containsPair('publicKey', 'latest-admin-pk-$groupId'),
                containsPair('mlKemPublicKey', 'latest-admin-mlkem-$groupId'),
              ),
            ),
          );
          expect(
            members,
            contains(
              allOf(
                containsPair('peerId', 'writer-$groupId'),
                containsPair('publicKey', 'latest-writer-pk-$groupId'),
              ),
            ),
          );
        }
      },
    );

    test(
      'BB-011 does not acknowledge recovery when any persisted group rejoin fails',
      () async {
        final trace = <String>[];
        const failedGroupId = 'bb011-life-fail-beta';
        bridge = _RecoveryOrderingBridge(
          trace: trace,
          failedGroupId: failedGroupId,
        );
        const groupIds = [
          'bb011-life-fail-alpha',
          failedGroupId,
          'bb011-life-fail-gamma',
        ];
        const latestEpochs = {
          'bb011-life-fail-alpha': 3,
          failedGroupId: 7,
          'bb011-life-fail-gamma': 11,
        };
        final baseTime = DateTime.utc(2026, 5, 11, 10);

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          await seedRecoveryGroup(
            groupId: groupId,
            latestEpoch: latestEpochs[groupId]!,
            latestKey: 'life-fail-key-$groupId',
            createdAt: baseTime.add(Duration(minutes: index)),
          );
        }

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final attemptedGroupIds = sentJoinPayloads(
          bridge,
        ).map((payload) => payload['groupId'] as String).toSet();
        expect(attemptedGroupIds, groupIds.toSet());
        expect(trace, isNot(contains('ack:start')));
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
      },
    );

    test(
      'BB-012 acknowledges recovery only after joins and inbox drain finish',
      () async {
        final trace = <String>[];
        bridge = _RecoveryOrderingBridge(trace: trace);
        const groupIds = ['bb012-life-alpha', 'bb012-life-beta'];
        const latestEpochs = {'bb012-life-alpha': 3, 'bb012-life-beta': 5};
        final baseTime = DateTime.utc(2026, 5, 11, 11);

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          await seedRecoveryGroup(
            groupId: groupId,
            latestEpoch: latestEpochs[groupId]!,
            latestKey: 'bb012-key-$groupId',
            createdAt: baseTime.add(Duration(minutes: index)),
          );
        }

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );
        final ackStart = trace.indexOf('ack:start');
        expect(ackStart, isNot(-1));
        for (final groupId in groupIds) {
          final joinComplete = trace.indexOf('join:complete:$groupId');
          final drainComplete = trace.indexOf('drain:complete:$groupId');
          expect(joinComplete, isNot(-1));
          expect(drainComplete, isNot(-1));
          expect(
            joinComplete,
            lessThan(ackStart),
            reason: 'ack must wait for $groupId group:join completion',
          );
          expect(
            drainComplete,
            lessThan(ackStart),
            reason: 'ack must wait for $groupId inbox drain completion',
          );
        }
      },
    );

    test(
      'BB-012 does not acknowledge recovery while inbox drain is incomplete',
      () async {
        final trace = <String>[];
        const groupId = 'bb012-life-blocked-drain';
        final orderingBridge = _RecoveryOrderingBridge(
          trace: trace,
          blockedDrainGroupId: groupId,
        );
        bridge = orderingBridge;
        await seedRecoveryGroup(
          groupId: groupId,
          latestEpoch: 3,
          latestKey: 'bb012-blocked-key',
          createdAt: DateTime.utc(2026, 5, 11, 12),
        );

        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        await orderingBridge.drainStarted.future;
        expect(trace, isNot(contains('ack:start')));
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));

        orderingBridge.allowDrain.complete();
        await resumeFuture;

        final drainComplete = trace.indexOf('drain:complete:$groupId');
        final ackStart = trace.indexOf('ack:start');
        expect(drainComplete, isNot(-1));
        expect(ackStart, isNot(-1));
        expect(drainComplete, lessThan(ackStart));
      },
    );

    test(
      'NW-004 relay reconnect resume rejoins all groups drains replay then acknowledges recovery',
      () async {
        final trace = <String>[];
        p2pService = _RelayReconnectP2PService(trace);
        bridge = _RecoveryOrderingBridge(trace: trace);
        const groupIds = ['nw004-life-alpha', 'nw004-life-beta'];
        const latestEpochs = {'nw004-life-alpha': 4, 'nw004-life-beta': 9};
        const latestKeys = {
          'nw004-life-alpha': 'nw004-key-alpha',
          'nw004-life-beta': 'nw004-key-beta',
        };
        final baseTime = DateTime.utc(2026, 5, 13, 8);

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          await seedRecoveryGroup(
            groupId: groupId,
            latestEpoch: latestEpochs[groupId]!,
            latestKey: latestKeys[groupId]!,
            createdAt: baseTime.add(Duration(minutes: index)),
          );
        }

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        expect(trace.first, 'relayReconnect/healthCheck');
        final ackStart = trace.indexOf('ack:start');
        expect(ackStart, isNot(-1));
        for (final groupId in groupIds) {
          final joinStart = trace.indexOf('join:start:$groupId');
          final joinComplete = trace.indexOf('join:complete:$groupId');
          final drainComplete = trace.indexOf('drain:complete:$groupId');
          expect(joinStart, greaterThan(0));
          expect(joinComplete, greaterThan(joinStart));
          expect(drainComplete, greaterThan(joinComplete));
          expect(drainComplete, lessThan(ackStart));
        }

        final payloads = sentJoinPayloads(bridge);
        expect(payloads, hasLength(groupIds.length));
        for (final groupId in groupIds) {
          final payload = payloads.singleWhere(
            (payload) => payload['groupId'] == groupId,
          );
          expect(payload['groupKey'], latestKeys[groupId]);
          expect(payload['keyEpoch'], latestEpochs[groupId]);
          final config = payload['groupConfig'] as Map<String, dynamic>;
          expect(config['name'], 'Latest $groupId');
          expect(
            isGroupConfigStateHashValid(groupId: groupId, groupConfig: config),
            isTrue,
          );
        }
        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );

        final failureTrace = <String>[];
        final failedBridge = _RecoveryOrderingBridge(
          trace: failureTrace,
          failedDrainGroupId: groupIds.last,
        );
        final failedP2pService = _RelayReconnectP2PService(failureTrace);
        try {
          await handleAppResumed(
            bridge: failedBridge,
            p2pService: failedP2pService,
            groupRepo: groupRepo,
            groupMsgRepo: groupMsgRepo,
          );
        } finally {
          failedP2pService.dispose();
        }

        expect(failureTrace.first, 'relayReconnect/healthCheck');
        expect(failureTrace, contains('drain:error:${groupIds.last}'));
        expect(failureTrace, isNot(contains('ack:start')));
        expect(
          failedBridge.commandLog,
          isNot(contains('group:acknowledgeRecovery')),
        );
      },
    );

    test(
      'NW-006 resume recovery keeps disconnected active member state through rejoin and drain',
      () async {
        final trace = <String>[];
        bridge = _RecoveryOrderingBridge(trace: trace);
        const groupId = 'nw006-life-disconnect-not-removal';
        final createdAt = DateTime.utc(2026, 5, 13, 10);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'NW-006 Active Disconnect',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: createdAt,
            createdBy: 'alice-nw006',
            myRole: GroupRole.member,
            lastMetadataEventAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-nw006',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice-nw006',
            joinedAt: createdAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'my-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob-nw006',
            joinedAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'charlie-nw006',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie-nw006',
            joinedAt: createdAt.add(const Duration(minutes: 2)),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 6,
            encryptedKey: 'nw006-stable-key',
            createdAt: createdAt.add(const Duration(minutes: 3)),
          ),
        );

        final membersBefore = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyBefore = await groupRepo.getLatestKey(groupId);

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final joinComplete = trace.indexOf('join:complete:$groupId');
        final drainComplete = trace.indexOf('drain:complete:$groupId');
        final ackStart = trace.indexOf('ack:start');
        expect(joinComplete, isNot(-1));
        expect(drainComplete, greaterThan(joinComplete));
        expect(ackStart, greaterThan(drainComplete));
        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:leave')));

        final payload = sentJoinPayloads(
          bridge,
        ).singleWhere((payload) => payload['groupId'] == groupId);
        expect(payload['groupKey'], 'nw006-stable-key');
        expect(payload['keyEpoch'], 6);
        final config = payload['groupConfig'] as Map<String, dynamic>;
        final configMembers = (config['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          configMembers.map((member) => member['peerId']).toSet(),
          membersBefore,
        );

        final membersAfter = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyAfter = await groupRepo.getLatestKey(groupId);
        expect(membersAfter, membersBefore);
        expect(membersAfter, contains('my-peer'));
        expect(keyAfter?.keyGeneration, keyBefore?.keyGeneration);
        expect(keyAfter?.encryptedKey, keyBefore?.encryptedKey);
        expect(await groupRepo.getGroup(groupId), isNotNull);
        expect(
          (await groupMsgRepo.getMessagesPage(
            groupId,
          )).where((message) => message.text.contains('member_removed')),
          isEmpty,
        );
      },
    );

    test(
      'NW-007 zero topic peers do not disable resume recovery or clear members',
      () async {
        final trace = <String>[];
        const groupId = 'nw007-life-zero-topic-peers';
        final orderingBridge = _RecoveryOrderingBridge(
          trace: trace,
          blockedDrainGroupId: groupId,
        );
        bridge = orderingBridge;
        final createdAt = DateTime.utc(2026, 5, 13, 11);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'NW-007 Zero Topic Peers',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: createdAt,
            createdBy: 'alice-nw007',
            myRole: GroupRole.member,
            lastMetadataEventAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-nw007',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice-nw007',
            joinedAt: createdAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'my-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob-nw007',
            joinedAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'charlie-nw007',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie-nw007',
            joinedAt: createdAt.add(const Duration(minutes: 2)),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 7,
            encryptedKey: 'nw007-stable-key',
            createdAt: createdAt.add(const Duration(minutes: 3)),
          ),
        );

        final membersBefore = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyBefore = await groupRepo.getLatestKey(groupId);
        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        await orderingBridge.drainStarted.future;
        expect(groupRecoveryGate.isActive, isTrue);
        expect(trace, contains('join:complete:$groupId'));
        expect(trace, contains('drain:start:$groupId'));
        expect(trace, isNot(contains('ack:start')));
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
        expect(
          (await groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );

        orderingBridge.allowDrain.complete();
        await resumeFuture;

        final joinComplete = trace.indexOf('join:complete:$groupId');
        final drainComplete = trace.indexOf('drain:complete:$groupId');
        final ackStart = trace.indexOf('ack:start');
        expect(joinComplete, isNot(-1));
        expect(drainComplete, greaterThan(joinComplete));
        expect(ackStart, greaterThan(drainComplete));
        expect(groupRecoveryGate.isActive, isFalse);
        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:leave')));

        final membersAfter = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyAfter = await groupRepo.getLatestKey(groupId);
        expect(membersAfter, membersBefore);
        expect(keyAfter?.keyGeneration, keyBefore?.keyGeneration);
        expect(keyAfter?.encryptedKey, keyBefore?.encryptedKey);
        expect(await groupRepo.getGroup(groupId), isNotNull);
        expect(
          (await groupMsgRepo.getMessagesPage(
            groupId,
          )).where((message) => message.text.contains('member_removed')),
          isEmpty,
        );
      },
    );

    test(
      'NW-010 foreground resume rejoins drains then acknowledges background group recovery',
      () async {
        final trace = <String>[];
        const groupId = 'nw010-life-background-resume';
        final orderingBridge = _RecoveryOrderingBridge(
          trace: trace,
          blockedDrainGroupId: groupId,
        );
        bridge = orderingBridge;
        final createdAt = DateTime.utc(2026, 5, 13, 12);
        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'NW-010 Background Resume',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: createdAt,
            createdBy: 'alice-nw010',
            myRole: GroupRole.member,
            lastMetadataEventAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'alice-nw010',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice-nw010',
            joinedAt: createdAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'my-peer',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob-nw010',
            joinedAt: createdAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'charlie-nw010',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie-nw010',
            joinedAt: createdAt.add(const Duration(minutes: 2)),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 10,
            encryptedKey: 'nw010-stable-key',
            createdAt: createdAt.add(const Duration(minutes: 3)),
          ),
        );

        final membersBefore = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyBefore = await groupRepo.getLatestKey(groupId);
        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        await orderingBridge.drainStarted.future;
        expect(groupRecoveryGate.isActive, isTrue);
        expect(trace, contains('join:complete:$groupId'));
        expect(trace, contains('drain:start:$groupId'));
        expect(trace, isNot(contains('ack:start')));
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
        expect(
          (await groupRepo.getMembers(
            groupId,
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );

        orderingBridge.allowDrain.complete();
        await resumeFuture;

        final joinComplete = trace.indexOf('join:complete:$groupId');
        final drainComplete = trace.indexOf('drain:complete:$groupId');
        final ackStart = trace.indexOf('ack:start');
        expect(joinComplete, isNot(-1));
        expect(drainComplete, greaterThan(joinComplete));
        expect(ackStart, greaterThan(drainComplete));
        expect(groupRecoveryGate.isActive, isFalse);
        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );

        final payload = sentJoinPayloads(
          bridge,
        ).singleWhere((payload) => payload['groupId'] == groupId);
        expect(payload['groupKey'], 'nw010-stable-key');
        expect(payload['keyEpoch'], 10);
        final config = payload['groupConfig'] as Map<String, dynamic>;
        final configMembers = (config['members'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(
          configMembers.map((member) => member['peerId']).toSet(),
          membersBefore,
        );

        final membersAfter = (await groupRepo.getMembers(
          groupId,
        )).map((member) => member.peerId).toSet();
        final keyAfter = await groupRepo.getLatestKey(groupId);
        expect(membersAfter, membersBefore);
        expect(keyAfter?.keyGeneration, keyBefore?.keyGeneration);
        expect(keyAfter?.encryptedKey, keyBefore?.encryptedKey);
        expect(await groupRepo.getGroup(groupId), isNotNull);
      },
    );

    test(
      'NW-012 resume waits for rejoin and full long-offline drain before acknowledging recovery',
      () async {
        final trace = <String>[];
        const groupId = 'nw012-life-long-offline';
        bridge = _RecoveryOrderingBridge(trace: trace);
        await seedRecoveryGroup(
          groupId: groupId,
          latestEpoch: 4,
          latestKey: 'nw012-final-key',
          createdAt: DateTime.utc(2026, 5, 13, 8),
        );

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        final joinComplete = trace.indexOf('join:complete:$groupId');
        final drainComplete = trace.indexOf('drain:complete:$groupId');
        final ackStart = trace.indexOf('ack:start');
        expect(joinComplete, isNot(-1));
        expect(drainComplete, isNot(-1));
        expect(ackStart, isNot(-1));
        expect(joinComplete, lessThan(drainComplete));
        expect(drainComplete, lessThan(ackStart));
        expect((await groupRepo.getLatestKey(groupId))!.keyGeneration, 4);
        expect(
          bridge.commandLog.where(
            (command) => command == 'group:acknowledgeRecovery',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'IR-018 recovery gate stays active until pending replay drain completes',
      () async {
        const groupId = 'ir018-life-pending-replay';
        const messageId = 'ir018-life-replay-message';
        final createdAt = DateTime.utc(2026, 5, 12, 9);
        final replayAt = createdAt.add(const Duration(minutes: 4));
        await seedRecoveryGroup(
          groupId: groupId,
          latestEpoch: 3,
          latestKey: 'ir018-life-key',
          createdAt: createdAt,
        );
        final keyInfo = (await groupRepo.getLatestKey(groupId))!;
        final replayPayload = {
          'groupId': groupId,
          'senderId': 'admin-$groupId',
          'senderUsername': 'Admin $groupId',
          'senderDeviceId': 'admin-$groupId',
          'transportPeerId': 'admin-$groupId',
          'keyEpoch': keyInfo.keyGeneration,
          'text': 'IR-018 replay before current',
          'timestamp': replayAt.toIso8601String(),
          'messageId': messageId,
        };
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: FakeBridge(),
          groupRepo: groupRepo,
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode(replayPayload),
          senderPeerId: 'admin-$groupId',
          senderPublicKey: 'latest-admin-pk-$groupId',
          senderPrivateKey: 'admin-sk-$groupId',
          senderDeviceId: 'admin-$groupId',
          senderTransportPeerId: 'admin-$groupId',
          messageId: messageId,
          keyInfo: keyInfo,
          recipientPeerIds: const ['my-peer'],
        );
        final blockingBridge = _BlockingDrainBridge(
          messages: [
            {
              'from': 'admin-$groupId',
              'message': replayEnvelope,
              'timestamp': replayAt.millisecondsSinceEpoch,
            },
          ],
        );
        bridge = blockingBridge;

        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        await blockingBridge.drainStarted.future;
        expect(isGroupRecoveryInProgress(), isTrue);
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
        expect(await groupMsgRepo.getMessage(messageId), isNull);

        blockingBridge.allowDrain.complete();
        await resumeFuture;

        final replayed = await groupMsgRepo.getMessage(messageId);
        expect(replayed, isNotNull);
        expect(replayed!.text, 'IR-018 replay before current');
        expect(isGroupRecoveryInProgress(), isFalse);
        expect(bridge.commandLog, contains('group:acknowledgeRecovery'));
      },
    );

    test(
      'BB-012 does not acknowledge recovery when inbox drain reports an error',
      () async {
        final trace = <String>[];
        const failedGroupId = 'bb012-life-drain-fail-beta';
        bridge = _RecoveryOrderingBridge(
          trace: trace,
          failedDrainGroupId: failedGroupId,
        );
        const groupIds = ['bb012-life-drain-fail-alpha', failedGroupId];
        final baseTime = DateTime.utc(2026, 5, 11, 13);

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          await seedRecoveryGroup(
            groupId: groupId,
            latestEpoch: 4 + index,
            latestKey: 'bb012-drain-fail-key-$groupId',
            createdAt: baseTime.add(Duration(minutes: index)),
          );
        }

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
        );

        expect(trace, contains('drain:error:$failedGroupId'));
        expect(trace, isNot(contains('ack:start')));
        expect(bridge.commandLog, isNot(contains('group:acknowledgeRecovery')));
      },
    );

    test(
      'calls rejoin, drain, recoverStuck, retryIncompleteGroupUploads, retryFailed, then retryFailedGroupInboxStores',
      () async {
        final callOrder = <String>[];
        bridge = _TracingBridge(callOrder);

        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-1',
            name: 'Test Group',
            type: GroupType.chat,
            topicName: 'topic-1',
            createdAt: DateTime.utc(2026, 1, 15, 12),
            createdBy: 'peer-admin',
            myRole: GroupRole.member,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 0,
            encryptedKey: 'encrypted-key',
            createdAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 1, 15, 12),
          ),
        );

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          recoverStuckSendingGroupMessagesFn: () async {
            callOrder.add('recoverStuck');
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            callOrder.add('retryUploads');
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            callOrder.add('retryFailed');
            return 0;
          },
          retryFailedGroupInboxStoresFn: () async {
            callOrder.add('retryInbox');
            return 0;
          },
        );

        expect(callOrder, [
          'rejoin',
          'drain',
          'recoverStuck',
          'retryUploads',
          'retryFailed',
          'retryInbox',
        ]);
      },
    );

    test(
      'NW-011 resume retries failed or pending background send after rejoin and drain',
      () async {
        final callOrder = <String>[];
        bridge = _TracingBridge(callOrder);
        const groupId = 'group-nw011-resume-retry';

        await seedRecoveryGroup(
          groupId: groupId,
          latestEpoch: 1,
          latestKey: 'nw011-resume-key',
          createdAt: DateTime.utc(2026, 5, 13, 2),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'nw011-failed-send',
            groupId: groupId,
            senderPeerId: 'my-peer',
            senderUsername: 'Alice',
            text: 'NW-011 failed background send',
            timestamp: DateTime.utc(2026, 5, 13, 2, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 5, 13, 2, 1),
            wireEnvelope: '{"messageId":"nw011-failed-send"}',
            inboxRetryPayload:
                '{"groupId":"group-nw011-resume-retry","message":"failed"}',
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'nw011-pending-inbox',
            groupId: groupId,
            senderPeerId: 'my-peer',
            senderUsername: 'Alice',
            text: 'NW-011 pending inbox send',
            timestamp: DateTime.utc(2026, 5, 13, 2, 2),
            status: 'pending',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 5, 13, 2, 2),
            inboxRetryPayload:
                '{"groupId":"group-nw011-resume-retry","message":"pending"}',
          ),
        );

        await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          recoverStuckSendingGroupMessagesFn: () async {
            callOrder.add('recoverStuck');
            return 0;
          },
          retryIncompleteGroupUploadsFn: () async {
            callOrder.add('retryUploads');
            return 0;
          },
          retryFailedGroupMessagesFn: () async {
            final failed = await groupMsgRepo.getMessage('nw011-failed-send');
            expect(failed, isNotNull);
            expect(failed!.status, 'failed');
            expect(failed.wireEnvelope, isNotNull);
            callOrder.add('retryFailed');
            return 1;
          },
          retryFailedGroupInboxStoresFn: () async {
            final pending = await groupMsgRepo.getMessage(
              'nw011-pending-inbox',
            );
            expect(pending, isNotNull);
            expect(pending!.status, 'pending');
            expect(pending.inboxRetryPayload, isNotNull);
            callOrder.add('retryInbox');
            return 1;
          },
        );

        expect(callOrder, [
          'rejoin',
          'drain',
          'recoverStuck',
          'retryUploads',
          'retryFailed',
          'retryInbox',
        ]);
      },
    );

    test('feature gate disables group recovery callbacks', () async {
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
          needsGroupRecovery: true,
          featureFlags: {'enableResumeGroupRecovery': false},
        ),
      );

      var recoverCalled = false;
      var retryUploadsCalled = false;
      var retryCalled = false;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        recoverStuckSendingGroupMessagesFn: () async {
          recoverCalled = true;
          return 0;
        },
        retryIncompleteGroupUploadsFn: () async {
          retryUploadsCalled = true;
          return 0;
        },
        retryFailedGroupMessagesFn: () async {
          retryCalled = true;
          return 0;
        },
      );

      expect(recoverCalled, isFalse);
      expect(retryUploadsCalled, isFalse);
      expect(retryCalled, isFalse);
    });

    test(
      'blocks admin-only group actions until replayed membership removal settles',
      () async {
        final now = DateTime.utc(2026, 4, 5, 12);
        final removalEventAt = now.add(const Duration(minutes: 1));
        const groupId = 'group-stale-admin';
        final bridge = _BlockingDrainBridge(messages: []);
        final removalPayload = {
          'groupId': groupId,
          'senderId': 'peer-other-admin',
          'senderUsername': 'OtherAdmin',
          'senderDeviceId': 'peer-other-admin',
          'transportPeerId': 'peer-other-admin',
          'keyEpoch': 1,
          'text': jsonEncode({
            '__sys': 'member_removed',
            'member': {
              'peerId': 'my-peer',
              'username': 'Self',
              'role': 'admin',
              'publicKey': 'pk-self',
            },
            'groupConfig': {
              'name': 'Recovery Group',
              'groupType': 'chat',
              'members': [
                {
                  'peerId': 'peer-other-admin',
                  'username': 'OtherAdmin',
                  'role': 'admin',
                  'publicKey': 'pk-other-admin',
                },
                {
                  'peerId': 'peer-bystander',
                  'username': 'Bystander',
                  'role': 'writer',
                  'publicKey': 'pk-bystander',
                },
              ],
              'createdBy': 'peer-other-admin',
              'createdAt': now.toIso8601String(),
            },
          }),
          'timestamp': removalEventAt.toIso8601String(),
          'messageId': 'sys-remove-self',
        };
        final listener = GroupMessageListener(
          groupRepo: groupRepo,
          msgRepo: groupMsgRepo,
          bridge: bridge,
          getSelfPeerId: () async => 'my-peer',
        );

        await groupRepo.saveGroup(
          GroupModel(
            id: groupId,
            name: 'Recovery Group',
            type: GroupType.chat,
            topicName: 'topic-$groupId',
            createdAt: now,
            createdBy: 'my-peer',
            myRole: GroupRole.admin,
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupId,
            keyGeneration: 1,
            encryptedKey: 'key-1',
            createdAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'my-peer',
            username: 'Self',
            role: MemberRole.admin,
            publicKey: 'pk-self',
            joinedAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-other-admin',
            username: 'OtherAdmin',
            role: MemberRole.admin,
            publicKey: 'pk-other-admin',
            joinedAt: now,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: groupId,
            peerId: 'peer-bystander',
            username: 'Bystander',
            role: MemberRole.writer,
            publicKey: 'pk-bystander',
            joinedAt: now,
          ),
        );
        bridge.messages.add({
          'from': 'peer-other-admin',
          'message': await buildGroupOfflineReplayEnvelope(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            payloadType: groupOfflineReplayPayloadTypeMessage,
            plaintext: jsonEncode(removalPayload),
            senderPeerId: 'peer-other-admin',
            senderPublicKey: 'pk-other-admin',
            senderPrivateKey: 'sk-other-admin',
            messageId: 'sys-remove-self',
            senderDeviceId: 'peer-other-admin',
            senderTransportPeerId: 'peer-other-admin',
            recipientPeerIds: const ['my-peer'],
          ),
        });

        final resumeFuture = handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          groupMessageListener: listener,
        );

        await bridge.drainStarted.future;
        expect(isGroupRecoveryInProgress(), isTrue);

        await expectLater(
          removeGroupMember(
            bridge: bridge,
            groupRepo: groupRepo,
            groupId: groupId,
            memberPeerId: 'peer-bystander',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(groupRecoveryPendingError),
            ),
          ),
        );
        expect(bridge.commandLog, isNot(contains('group:updateConfig')));

        bridge.allowDrain.complete();
        await resumeFuture;

        expect(await groupRepo.getGroup(groupId), isNull);
        expect(isGroupRecoveryInProgress(), isFalse);
      },
    );
  });
}
