import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

class _TimeoutCommandBridge extends FakeBridge {
  final String command;

  _TimeoutCommandBridge(this.command);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == command) {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw TimeoutException('Simulated $command timeout');
    }
    return super.send(message);
  }
}

/// Fails `group:join` for one specific groupId only; every other group joins
/// normally. Lets a test prove that one transient per-group error does not
/// erase the recoverable outcomes of the other groups.
class _SelectiveJoinFailureBridge extends FakeBridge {
  final String failGroupId;

  _SelectiveJoinFailureBridge({required this.failGroupId});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:join') {
      final payload = parsed['payload'] as Map<String, dynamic>?;
      if (payload != null && payload['groupId'] == failGroupId) {
        sendCallCount++;
        lastSentMessage = message;
        sentMessages.add(message);
        lastCommand = cmd;
        commandLog.add(cmd!);
        throw TimeoutException('Simulated join failure for $failGroupId');
      }
    }
    return super.send(message);
  }
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;

  setUp(() {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
  });

  /// Helper to create a group with members and a key in the repo.
  Future<void> seedGroup({
    required String groupId,
    required String name,
    List<GroupMember>? members,
    GroupKeyInfo? keyInfo,
  }) async {
    await groupRepo.saveGroup(
      GroupModel(
        id: groupId,
        name: name,
        type: GroupType.chat,
        topicName: 'topic-$groupId',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'admin-peer',
        myRole: GroupRole.admin,
      ),
    );

    if (members != null) {
      for (final m in members) {
        await groupRepo.saveMember(m);
      }
    }

    if (keyInfo != null) {
      await groupRepo.saveKey(keyInfo);
    }
  }

  group('rejoinGroupTopics', () {
    test('calls callGroupJoinWithConfig for each active group', () async {
      // -- arrange --
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-1',
        name: 'Group One',
        members: [
          GroupMember(
            groupId: 'group-1',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
          GroupMember(
            groupId: 'group-1',
            peerId: 'bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'key-1-base64',
          createdAt: now,
        ),
      );

      await seedGroup(
        groupId: 'group-2',
        name: 'Group Two',
        members: [
          GroupMember(
            groupId: 'group-2',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-2',
          keyGeneration: 3,
          encryptedKey: 'key-2-base64',
          createdAt: now,
        ),
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(2));

      final groupIds = joinCommands
          .map((c) => c['payload']['groupId'] as String)
          .toSet();
      expect(groupIds, {'group-1', 'group-2'});
    });

    test(
      'G4: triggers a per-group broadcast drain for each successfully rejoined '
      'group',
      () async {
        final drained = <String>[];
        setGroupPendingBroadcastDrainSinks(
          forGroup: (groupId) async {
            drained.add(groupId);
            return 0;
          },
          all: null,
        );
        addTearDown(
          () => setGroupPendingBroadcastDrainSinks(forGroup: null, all: null),
        );

        final now = DateTime.now().toUtc();
        await seedGroup(
          groupId: 'group-1',
          name: 'Group One',
          keyInfo: GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'key-1-base64',
            createdAt: now,
          ),
        );
        await seedGroup(
          groupId: 'group-2',
          name: 'Group Two',
          keyInfo: GroupKeyInfo(
            groupId: 'group-2',
            keyGeneration: 1,
            encryptedKey: 'key-2-base64',
            createdAt: now,
          ),
        );

        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

        expect(drained, containsAll(<String>['group-1', 'group-2']));
        expect(drained, hasLength(2));
      },
    );

    test(
      'PB264-11 rejoin eligibility follows exit phase and drains before processing',
      () async {
        final statesByGroup = <String, GroupExitIntentState>{};
        final now = DateTime.utc(2026, 7, 21, 8);
        for (final state in GroupExitIntentState.values) {
          final groupId = 'group-${state.databaseValue}';
          statesByGroup[groupId] = state;
          await seedGroup(
            groupId: groupId,
            name: state.databaseValue,
            keyInfo: GroupKeyInfo(
              groupId: groupId,
              keyGeneration: 1,
              encryptedKey: 'key-${state.databaseValue}',
              createdAt: now,
            ),
          );
        }

        final orderByGroup = <String, List<String>>{};
        setGroupPendingBroadcastDrainSinks(
          forGroup: (groupId) async {
            orderByGroup.putIfAbsent(groupId, () => <String>[]).add('drain');
            return 0;
          },
          all: null,
        );
        addTearDown(
          () => setGroupPendingBroadcastDrainSinks(forGroup: null, all: null),
        );

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          canRejoinForExitIntent: (groupId) async =>
              !statesByGroup[groupId]!.preventsRejoin,
          processExitIntent: (groupId) async {
            orderByGroup.putIfAbsent(groupId, () => <String>[]).add('process');
          },
        );

        final joinedGroupIds = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:join')
            .map(
              (message) =>
                  (message['payload'] as Map<String, dynamic>)['groupId']
                      as String,
            )
            .toSet();
        for (final entry in statesByGroup.entries) {
          if (entry.value.preventsRejoin) {
            expect(joinedGroupIds, isNot(contains(entry.key)));
            expect(
              result.perGroupOutcomes[entry.key],
              RejoinOutcome.skippedExitInProgress,
            );
            expect(orderByGroup[entry.key], <String>['process']);
          } else {
            expect(joinedGroupIds, contains(entry.key));
            expect(result.perGroupOutcomes[entry.key], RejoinOutcome.joined);
            expect(orderByGroup[entry.key], <String>['drain', 'process']);
          }
        }
      },
    );

    test(
      'G4: does not trigger a per-group drain for a group skipped for no key',
      () async {
        final drained = <String>[];
        setGroupPendingBroadcastDrainSinks(
          forGroup: (groupId) async {
            drained.add(groupId);
            return 0;
          },
          all: null,
        );
        addTearDown(
          () => setGroupPendingBroadcastDrainSinks(forGroup: null, all: null),
        );

        final now = DateTime.now().toUtc();
        // group-1 has a key (joins); group-2 has none (skippedNoKey).
        await seedGroup(
          groupId: 'group-1',
          name: 'Group One',
          keyInfo: GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 1,
            encryptedKey: 'key-1-base64',
            createdAt: now,
          ),
        );
        await seedGroup(groupId: 'group-2', name: 'Group Two');

        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

        expect(drained, <String>['group-1']);
      },
    );

    test(
      'PB264-11 every visited rejoin outcome advances durable exit work but only joined drains',
      () async {
        final now = DateTime.utc(2026, 7, 21, 9);
        const withKey = <String>{
          'branch-joined',
          'branch-exit',
          'branch-dissolved',
          'branch-self-removed',
          'branch-deferred',
          'branch-error',
        };
        for (final groupId in <String>{...withKey, 'branch-no-key'}) {
          await seedGroup(
            groupId: groupId,
            name: groupId,
            keyInfo: withKey.contains(groupId)
                ? GroupKeyInfo(
                    groupId: groupId,
                    keyGeneration: 1,
                    encryptedKey: 'key-$groupId',
                    createdAt: now,
                  )
                : null,
          );
        }
        final dissolved = await groupRepo.getGroup('branch-dissolved');
        await groupRepo.updateGroup(
          dissolved!.copyWith(
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'admin-peer',
          ),
        );
        final removed = await groupRepo.getGroup('branch-self-removed');
        await groupRepo.updateGroup(removed!.copyWith(selfRemovedAt: now));
        await groupRepo.recordGroupRejoinFailure(
          'branch-deferred',
          nextEligibleAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        );

        final drained = <String>[];
        setGroupPendingBroadcastDrainSinks(
          forGroup: (groupId) async {
            drained.add(groupId);
            return 0;
          },
          all: null,
        );
        addTearDown(
          () => setGroupPendingBroadcastDrainSinks(forGroup: null, all: null),
        );
        final processed = <String>[];
        bridge = _SelectiveJoinFailureBridge(failGroupId: 'branch-error');

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          canRejoinForExitIntent: (groupId) async => groupId != 'branch-exit',
          processExitIntent: (groupId) async => processed.add(groupId),
        );

        expect(
          result.perGroupOutcomes,
          containsPair('branch-joined', RejoinOutcome.joined),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-exit', RejoinOutcome.skippedExitInProgress),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-dissolved', RejoinOutcome.skippedDissolved),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-self-removed', RejoinOutcome.skippedSelfRemoved),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-no-key', RejoinOutcome.skippedNoKey),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-deferred', RejoinOutcome.deferred),
        );
        expect(
          result.perGroupOutcomes,
          containsPair('branch-error', RejoinOutcome.error),
        );
        expect(processed.toSet(), <String>{...withKey, 'branch-no-key'});
        expect(processed, hasLength(7));
        expect(drained, <String>['branch-joined']);
      },
    );

    test('emits GROUP_REJOIN_TOPICS_TIMING with batch metadata', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-1',
        name: 'Group One',
        members: [
          GroupMember(
            groupId: 'group-1',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'key-1-base64',
          createdAt: now,
        ),
      );

      final events = await captureFlowEvents(() async {
        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
      });

      final begin = events.firstWhere(
        (event) => event['event'] == 'GROUP_REJOIN_TOPICS_BEGIN',
      );
      expect(begin['details']['reason'], RejoinReason.startup.name);

      final joined = events.firstWhere(
        (event) => event['event'] == 'GROUP_REJOIN_TOPICS_JOINED',
      );
      expect(joined['details']['groupId'], 'group-1');
      expect(joined['details']['keyEpoch'], 1);
      expect(joined['details']['memberCount'], 1);

      final done = events.firstWhere(
        (event) => event['event'] == 'GROUP_REJOIN_TOPICS_DONE',
      );
      expect(done['details']['groupCount'], 1);
      expect(done['details']['joinedGroupCount'], 1);
      expect(done['details']['skippedNoKeyCount'], 0);
      expect(done['details']['errorCount'], 0);

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_REJOIN_TOPICS_TIMING',
      );
      expect(timing['details']['outcome'], 'complete');
      expect(timing['details']['scope'], 'batch');
      expect(timing['details']['groupCount'], 1);
      expect(timing['details']['joinedGroupCount'], 1);
      expect(timing['details']['reason'], RejoinReason.startup.name);
      expect(timing['details']['elapsedMs'], isA<int>());
    });

    test('skips groups with no key info', () async {
      final now = DateTime.now().toUtc();

      // Group with key
      await seedGroup(
        groupId: 'group-with-key',
        name: 'Has Key',
        members: [
          GroupMember(
            groupId: 'group-with-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-with-key',
          keyGeneration: 1,
          encryptedKey: 'key-base64',
          createdAt: now,
        ),
      );

      // Group without key — should be skipped
      await seedGroup(
        groupId: 'group-no-key',
        name: 'No Key',
        members: [
          GroupMember(
            groupId: 'group-no-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        // No keyInfo
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-with-key');
    });

    test('continues on individual join error', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-fail',
        name: 'Will Fail',
        members: [
          GroupMember(
            groupId: 'group-fail',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-fail',
          keyGeneration: 1,
          encryptedKey: 'key-fail',
          createdAt: now,
        ),
      );

      await seedGroup(
        groupId: 'group-ok',
        name: 'Will Succeed',
        members: [
          GroupMember(
            groupId: 'group-ok',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-ok',
          keyGeneration: 1,
          encryptedKey: 'key-ok',
          createdAt: now,
        ),
      );

      // Make all joins fail — the important thing is the function doesn't throw
      bridge.responses['group:join'] = {'ok': false, 'errorCode': 'TEST_FAIL'};

      // -- act -- (should not throw)
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert: both groups were attempted despite errors --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(
        joinCommands,
        hasLength(2),
        reason: 'Both groups should be attempted even when joins fail',
      );
    });

    test('does nothing when no active groups exist', () async {
      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      expect(bridge.sendCallCount, 0);
      expect(bridge.sentMessages, isEmpty);
    });

    test('builds correct groupConfig from stored members', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-config',
        name: 'Config Test',
        members: [
          GroupMember(
            groupId: 'group-config',
            peerId: 'admin-peer',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            mlKemPublicKey: 'mlkem-admin',
            joinedAt: now,
          ),
          GroupMember(
            groupId: 'group-config',
            peerId: 'member-peer',
            username: 'Member',
            role: MemberRole.writer,
            publicKey: 'pk-member',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-config',
          keyGeneration: 5,
          encryptedKey: 'key-config-base64',
          createdAt: now,
        ),
      );

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      final payload = joinCommands.first['payload'] as Map<String, dynamic>;

      expect(payload['groupId'], 'group-config');
      expect(payload['groupKey'], 'key-config-base64');
      expect(payload['keyEpoch'], 5);

      final config = payload['groupConfig'] as Map<String, dynamic>;
      expect(config['name'], 'Config Test');
      expect(config['groupType'], 'chat');

      final members = config['members'] as List<dynamic>;
      expect(members, hasLength(2));

      final adminMember = members.firstWhere(
        (m) => (m as Map<String, dynamic>)['peerId'] == 'admin-peer',
      );
      expect(adminMember['publicKey'], 'pk-admin');
      expect(adminMember['mlKemPublicKey'], 'mlkem-admin');
      expect(adminMember['role'], 'admin');

      final regularMember = members.firstWhere(
        (m) => (m as Map<String, dynamic>)['peerId'] == 'member-peer',
      );
      expect(regularMember['publicKey'], 'pk-member');
      expect(regularMember['role'], 'writer');
    });

    test('rejoin is idempotent when topic already active', () async {
      // When Go returns ALREADY_JOINED, the rejoin should succeed without
      // error. This tests idempotency for cases where a topic is already
      // subscribed.
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-active-topic',
        name: 'Already Active',
        members: [
          GroupMember(
            groupId: 'group-active-topic',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-active-topic',
          keyGeneration: 1,
          encryptedKey: 'key-already',
          createdAt: now,
        ),
      );

      // Simulate Go returning ALREADY_JOINED (still ok:true).
      bridge.responses['group:join'] = {'ok': true, 'note': 'ALREADY_JOINED'};

      // Should not throw despite "already joined".
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
    });

    test(
      'BB-008 sends latest full config and key material when already joined',
      () async {
        final now = DateTime.now().toUtc();

        await seedGroup(
          groupId: 'bb-008-latest-material',
          name: 'BB-008 Latest',
          members: [
            GroupMember(
              groupId: 'bb-008-latest-material',
              peerId: 'admin-peer',
              username: 'Admin',
              role: MemberRole.admin,
              publicKey: 'pk-admin-latest',
              mlKemPublicKey: 'mlkem-admin-latest',
              joinedAt: now,
            ),
            GroupMember(
              groupId: 'bb-008-latest-material',
              peerId: 'writer-peer',
              username: 'Writer',
              role: MemberRole.writer,
              publicKey: 'pk-writer-latest',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'bb-008-latest-material',
            keyGeneration: 2,
            encryptedKey: 'key-bb008-epoch-2',
            createdAt: now,
          ),
        );

        bridge.responses['group:join'] = {'ok': true, 'note': 'ALREADY_JOINED'};

        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

        final joinCommands = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();

        expect(joinCommands, hasLength(1));
        final payload = joinCommands.first['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], 'bb-008-latest-material');
        expect(payload['groupKey'], 'key-bb008-epoch-2');
        expect(payload['keyEpoch'], 2);

        final config = payload['groupConfig'] as Map<String, dynamic>;
        expect(config['name'], 'BB-008 Latest');
        expect(config['groupType'], 'chat');
        final members = config['members'] as List<dynamic>;
        expect(members, hasLength(2));
        expect(
          members,
          contains(
            allOf(
              isA<Map<String, dynamic>>(),
              containsPair('peerId', 'admin-peer'),
              containsPair('publicKey', 'pk-admin-latest'),
              containsPair('mlKemPublicKey', 'mlkem-admin-latest'),
              containsPair('role', 'admin'),
            ),
          ),
        );
        expect(
          members,
          contains(
            allOf(
              isA<Map<String, dynamic>>(),
              containsPair('peerId', 'writer-peer'),
              containsPair('publicKey', 'pk-writer-latest'),
              containsPair('role', 'writer'),
            ),
          ),
        );
      },
    );

    test(
      'RA-015 sends current re-add config and key when Go returns ALREADY_JOINED',
      () async {
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final now = DateTime.now().toUtc();
        final removedAt = now.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await seedGroup(
          groupId: 'ra015-already-joined-readd',
          name: 'RA-015 Readd',
          members: [
            GroupMember(
              groupId: 'ra015-already-joined-readd',
              peerId: 'alice-peer',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice-current',
              mlKemPublicKey: 'mlkem-alice-current',
              joinedAt: now,
            ),
            GroupMember(
              groupId: 'ra015-already-joined-readd',
              peerId: 'bob-peer',
              username: 'Bob',
              role: MemberRole.writer,
              publicKey: 'pk-bob-current',
              mlKemPublicKey: 'mlkem-bob-current',
              joinedAt: now,
            ),
            GroupMember(
              groupId: 'ra015-already-joined-readd',
              peerId: 'charlie-peer',
              username: 'Charlie',
              role: MemberRole.writer,
              publicKey: 'pk-charlie-readded',
              mlKemPublicKey: 'mlkem-charlie-readded',
              joinedAt: readdAt,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'ra015-already-joined-readd',
            keyGeneration: 3,
            encryptedKey: 'key-ra015-current-epoch-3',
            createdAt: readdAt,
          ),
        );

        bridge.responses['group:join'] = {'ok': true, 'note': 'ALREADY_JOINED'};

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          reason: RejoinReason.inPlaceRecovery,
        );

        expect(result.joinedGroupCount, 1);
        expect(result.errorCount, 0);

        final joinCommands = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(1));

        final payload = joinCommands.single['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], 'ra015-already-joined-readd');
        expect(payload['groupKey'], 'key-ra015-current-epoch-3');
        expect(payload['keyEpoch'], 3);

        final config = payload['groupConfig'] as Map<String, dynamic>;
        expect(config['name'], 'RA-015 Readd');
        final members = config['members'] as List<dynamic>;
        expect(members, hasLength(3));
        expect(
          members,
          contains(
            allOf(
              isA<Map<String, dynamic>>(),
              containsPair('peerId', 'charlie-peer'),
              containsPair('publicKey', 'pk-charlie-readded'),
              containsPair('mlKemPublicKey', 'mlkem-charlie-readded'),
              containsPair('role', 'writer'),
            ),
          ),
        );

        final responseEvent = flowEvents.lastWhere(
          (event) => event['event'] == 'GROUP_FL_BRIDGE_JOIN_CONFIG_RESPONSE',
        );
        final details = responseEvent['details'] as Map<String, dynamic>;
        expect(details['ok'], isTrue);
        expect(details['note'], 'ALREADY_JOINED');

        final latestKey = await groupRepo.getLatestKey(
          'ra015-already-joined-readd',
        );
        expect(latestKey?.keyGeneration, 3);
        expect(latestKey?.encryptedKey, 'key-ra015-current-epoch-3');
        final charlie = await groupRepo.getMember(
          'ra015-already-joined-readd',
          'charlie-peer',
        );
        expect(charlie?.joinedAt, readdAt);
        expect(removedAt.isBefore(charlie!.joinedAt), isTrue);
      },
    );

    test(
      'NW-005 rejoin publishes current membership as discovery authority after churn',
      () async {
        final now = DateTime.now().toUtc();
        final removedAt = now.add(const Duration(minutes: 1));
        final readdAt = removedAt.add(const Duration(minutes: 1));

        await seedGroup(
          groupId: 'nw005-rendezvous-membership-truth',
          name: 'NW-005 Rejoin',
          members: [
            GroupMember(
              groupId: 'nw005-rendezvous-membership-truth',
              peerId: 'alice-peer',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice-current',
              mlKemPublicKey: 'mlkem-alice-current',
              joinedAt: now,
            ),
            GroupMember(
              groupId: 'nw005-rendezvous-membership-truth',
              peerId: 'bob-peer',
              username: 'Bob',
              role: MemberRole.writer,
              publicKey: 'pk-bob-current',
              mlKemPublicKey: 'mlkem-bob-current',
              joinedAt: now,
            ),
            GroupMember(
              groupId: 'nw005-rendezvous-membership-truth',
              peerId: 'charlie-peer',
              username: 'Charlie',
              role: MemberRole.writer,
              publicKey: 'pk-charlie-readded',
              mlKemPublicKey: 'mlkem-charlie-readded',
              joinedAt: readdAt,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'nw005-rendezvous-membership-truth',
            keyGeneration: 2,
            encryptedKey: 'key-nw005-current-epoch-2',
            createdAt: readdAt,
          ),
        );

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          reason: RejoinReason.nodeRequestedRecovery,
        );

        expect(result.joinedGroupCount, 1);
        expect(result.errorCount, 0);

        final joinCommands = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(joinCommands, hasLength(1));

        final payload = joinCommands.single['payload'] as Map<String, dynamic>;
        expect(payload['groupId'], 'nw005-rendezvous-membership-truth');
        expect(payload['groupKey'], 'key-nw005-current-epoch-2');
        expect(payload['keyEpoch'], 2);

        final config = payload['groupConfig'] as Map<String, dynamic>;
        final members = (config['members'] as List<dynamic>)
            .cast<Map<dynamic, dynamic>>();
        final memberIds = members.map((member) => member['peerId']).toSet();
        expect(memberIds, {'alice-peer', 'bob-peer', 'charlie-peer'});
        expect(memberIds, isNot(contains('stale-charlie-transport-peer')));
        expect(memberIds, isNot(contains('fresh-rendezvous-outsider-peer')));
        expect(
          members.singleWhere(
            (member) => member['peerId'] == 'charlie-peer',
          )['publicKey'],
          'pk-charlie-readded',
        );
        final charlie = await groupRepo.getMember(
          'nw005-rendezvous-membership-truth',
          'charlie-peer',
        );
        expect(charlie?.joinedAt, readdAt);
        expect(removedAt.isBefore(charlie!.joinedAt), isTrue);
      },
    );

    test(
      'BB-011 rejoins every persisted active private group with latest config and key material',
      () async {
        final baseTime = DateTime.utc(2026, 5, 11, 8);
        const groupIds = [
          'bb011-group-alpha',
          'bb011-group-beta',
          'bb011-group-gamma',
        ];
        const latestEpochs = {
          'bb011-group-alpha': 3,
          'bb011-group-beta': 7,
          'bb011-group-gamma': 11,
        };
        const latestKeys = {
          'bb011-group-alpha': 'latest-key-alpha',
          'bb011-group-beta': 'latest-key-beta',
          'bb011-group-gamma': 'latest-key-gamma',
        };

        for (var index = 0; index < groupIds.length; index++) {
          final groupId = groupIds[index];
          final createdAt = baseTime.add(Duration(minutes: index));
          final metadataAt = createdAt.add(const Duration(hours: 2));

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
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'admin-$groupId',
              username: 'Stale Admin',
              role: MemberRole.admin,
              publicKey: 'stale-admin-pk-$groupId',
              joinedAt: createdAt,
            ),
          );
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: latestEpochs[groupId]! - 1,
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
          await groupRepo.saveMember(
            GroupMember(
              groupId: groupId,
              peerId: 'reader-$groupId',
              username: 'Reader $groupId',
              role: MemberRole.reader,
              publicKey: 'latest-reader-pk-$groupId',
              joinedAt: createdAt.add(const Duration(minutes: 2)),
            ),
          );
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupId,
              keyGeneration: latestEpochs[groupId]!,
              encryptedKey: latestKeys[groupId]!,
              createdAt: metadataAt,
            ),
          );
        }

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
          reason: RejoinReason.nodeRequestedRecovery,
        );

        expect(result.joinedGroupCount, groupIds.length);
        expect(result.skippedNoKeyCount, 0);
        expect(result.errorCount, 0);

        final sentCommands = bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .toList();
        expect(
          sentCommands.where(
            (command) => command['cmd'] == 'group:acknowledgeRecovery',
          ),
          isEmpty,
          reason: 'rejoinGroupTopics must not acknowledge recovery directly',
        );

        final joinPayloads = sentCommands
            .where((command) => command['cmd'] == 'group:join')
            .map((command) => command['payload'] as Map<String, dynamic>)
            .toList();
        expect(joinPayloads, hasLength(groupIds.length));

        for (final groupId in groupIds) {
          final payload = joinPayloads.singleWhere(
            (payload) => payload['groupId'] == groupId,
          );
          expect(payload['groupKey'], latestKeys[groupId]);
          expect(payload['keyEpoch'], latestEpochs[groupId]);

          final config = payload['groupConfig'] as Map<String, dynamic>;
          final metadataAt = baseTime
              .add(Duration(minutes: groupIds.indexOf(groupId)))
              .add(const Duration(hours: 2));
          expect(config['name'], 'Latest $groupId');
          expect(config['description'], 'Latest description $groupId');
          expect(config['groupType'], GroupType.chat.toValue());
          expect(config['createdBy'], 'admin-$groupId');
          expect(
            config[groupConfigVersionField],
            metadataAt.toUtc().toIso8601String(),
          );
          expect(
            config['metadataUpdatedAt'],
            metadataAt.toUtc().toIso8601String(),
          );
          expect(
            isGroupConfigStateHashValid(groupId: groupId, groupConfig: config),
            isTrue,
          );

          final members = (config['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          expect(members, hasLength(3));
          expect(
            members,
            contains(
              allOf(
                containsPair('peerId', 'admin-$groupId'),
                containsPair('publicKey', 'latest-admin-pk-$groupId'),
                containsPair('mlKemPublicKey', 'latest-admin-mlkem-$groupId'),
                containsPair('role', MemberRole.admin.toValue()),
              ),
            ),
          );
          expect(
            members,
            contains(
              allOf(
                containsPair('peerId', 'writer-$groupId'),
                containsPair('publicKey', 'latest-writer-pk-$groupId'),
                containsPair('role', MemberRole.writer.toValue()),
              ),
            ),
          );
          expect(
            members,
            contains(
              allOf(
                containsPair('peerId', 'reader-$groupId'),
                containsPair('publicKey', 'latest-reader-pk-$groupId'),
                containsPair('role', MemberRole.reader.toValue()),
              ),
            ),
          );
        }
      },
    );

    test('BB-016 rejoin sends metadata fields with valid state hash', () async {
      final createdAt = DateTime.utc(2026, 5, 15, 9, 42);
      final metadataAt = DateTime.utc(2026, 5, 15, 10, 42);
      const groupId = 'bb016-rejoin-metadata';

      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'BB-016 Metadata Group',
          type: GroupType.chat,
          topicName: 'topic-$groupId',
          description: 'BB-016 latest description',
          avatarBlobId: 'blob-bb016-avatar',
          avatarMime: 'image/png',
          createdAt: createdAt,
          createdBy: 'peer-bb016-admin',
          myRole: GroupRole.member,
          lastMetadataEventAt: metadataAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-bb016-admin',
          username: 'BB-016 Admin',
          role: MemberRole.admin,
          publicKey: 'pk-bb016-admin',
          mlKemPublicKey: 'mlkem-bb016-admin',
          joinedAt: createdAt,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 4,
          encryptedKey: 'bb016-latest-key',
          createdAt: metadataAt,
        ),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.startup,
      );

      expect(result.joinedGroupCount, 1);
      expect(result.errorCount, 0);

      final joinMessage = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .singleWhere((command) => command['cmd'] == 'group:join');
      final payload = joinMessage['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], groupId);
      expect(payload['groupKey'], 'bb016-latest-key');
      expect(payload['keyEpoch'], 4);

      final config = payload['groupConfig'] as Map<String, dynamic>;
      expect(config['description'], 'BB-016 latest description');
      expect(config['avatarBlobId'], 'blob-bb016-avatar');
      expect(config['avatarMime'], 'image/png');
      expect(config['metadataUpdatedAt'], metadataAt.toUtc().toIso8601String());
      expect(
        config[groupConfigVersionField],
        metadataAt.toUtc().toIso8601String(),
      );
      expect(
        isGroupConfigStateHashValid(groupId: groupId, groupConfig: config),
        isTrue,
      );
    });

    test('rejoin runs after watchdog restart', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-watchdog',
        name: 'Watchdog Group',
        members: [
          GroupMember(
            groupId: 'group-watchdog',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-watchdog',
          keyGeneration: 2,
          encryptedKey: 'key-watchdog',
          createdAt: now,
        ),
      );

      // Rejoin with watchdog restart reason should proceed normally.
      await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.watchdogRestart,
      );

      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-watchdog');
    });

    test('node-requested recovery rejoins topics', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-node-requested',
        name: 'Node Requested Group',
        members: [
          GroupMember(
            groupId: 'group-node-requested',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-node-requested',
          keyGeneration: 1,
          encryptedKey: 'key-node-requested',
          createdAt: now,
        ),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.nodeRequestedRecovery,
      );

      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(result.skipped, isFalse);
      expect(result.errorCount, 0);
    });

    test('in-place recovery refreshes topics idempotently', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-inplace',
        name: 'In-Place Group',
        members: [
          GroupMember(
            groupId: 'group-inplace',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-inplace',
          keyGeneration: 1,
          encryptedKey: 'key-inplace',
          createdAt: now,
        ),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.inPlaceRecovery,
      );

      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-inplace');
      expect(result.skipped, isFalse);
    });

    test(
      'announcement groups are rejoined and refreshed like normal groups',
      () async {
        final now = DateTime.now().toUtc();

        // Create an announcement group.
        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-announce',
            name: 'Announcements',
            type: GroupType.announcement,
            topicName: 'topic-group-announce',
            createdAt: now,
            createdBy: 'admin-peer',
            myRole: GroupRole.admin,
          ),
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-announce',
            peerId: 'admin-peer',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            joinedAt: now,
          ),
        );

        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce',
            keyGeneration: 1,
            encryptedKey: 'key-announce',
            createdAt: now,
          ),
        );

        // Also create a normal chat group.
        await seedGroup(
          groupId: 'group-chat',
          name: 'Chat Group',
          members: [
            GroupMember(
              groupId: 'group-chat',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-chat',
            keyGeneration: 1,
            encryptedKey: 'key-chat',
            createdAt: now,
          ),
        );

        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

        final joinCommands = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();

        // Both announcement and chat groups should be rejoined.
        expect(joinCommands, hasLength(2));
        final groupIds = joinCommands
            .map((c) => c['payload']['groupId'] as String)
            .toSet();
        expect(groupIds, {'group-announce', 'group-chat'});

        // Verify announcement group config includes groupType=announcement.
        final announceCmd = joinCommands.firstWhere(
          (c) => c['payload']['groupId'] == 'group-announce',
        );
        final config =
            announceCmd['payload']['groupConfig'] as Map<String, dynamic>;
        expect(config['groupType'], 'announcement');
      },
    );

    // -------------------------------------------------------------------------
    // Phase 6: Group recovery on resume and watchdog
    // -------------------------------------------------------------------------

    test('watchdog restart triggers group rejoin for all groups', () async {
      final now = DateTime.now().toUtc();

      // Create 3 groups with keys
      for (var i = 1; i <= 3; i++) {
        await seedGroup(
          groupId: 'group-wd-$i',
          name: 'WD Group $i',
          members: [
            GroupMember(
              groupId: 'group-wd-$i',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-wd-$i',
            keyGeneration: 1,
            encryptedKey: 'key-wd-$i',
            createdAt: now,
          ),
        );
      }

      // Call rejoinGroupTopics with watchdogRestart reason
      await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.watchdogRestart,
      );

      // Verify bridge received 3 group:join commands
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(3));
    });

    test('in place relay recovery still refreshes group topics', () async {
      final now = DateTime.now().toUtc();

      // Create groups
      await seedGroup(
        groupId: 'group-ip-1',
        name: 'IP Group',
        members: [
          GroupMember(
            groupId: 'group-ip-1',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-ip-1',
          keyGeneration: 1,
          encryptedKey: 'key-ip-1',
          createdAt: now,
        ),
      );

      // Call rejoinGroupTopics with inPlaceRecovery reason
      await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.inPlaceRecovery,
      );

      // Verify bridge still refreshes the topic join idempotently.
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], equals('group-ip-1'));
    });

    test('startup triggers group rejoin for all groups', () async {
      final now = DateTime.now().toUtc();

      // Create groups
      for (var i = 1; i <= 2; i++) {
        await seedGroup(
          groupId: 'group-start-$i',
          name: 'Start Group $i',
          members: [
            GroupMember(
              groupId: 'group-start-$i',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-start-$i',
            keyGeneration: 1,
            encryptedKey: 'key-start-$i',
            createdAt: now,
          ),
        );
      }

      // Call rejoinGroupTopics with startup reason (default)
      await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
        reason: RejoinReason.startup,
      );

      // Verify bridge received group:join commands for all groups
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(2));
    });

    test('groups without key material are skipped', () async {
      final now = DateTime.now().toUtc();

      // Create 2 groups, only 1 has a key
      await seedGroup(
        groupId: 'group-has-key',
        name: 'Has Key',
        members: [
          GroupMember(
            groupId: 'group-has-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-has-key',
          keyGeneration: 1,
          encryptedKey: 'key-has',
          createdAt: now,
        ),
      );

      await seedGroup(
        groupId: 'group-lacks-key',
        name: 'Lacks Key',
        members: [
          GroupMember(
            groupId: 'group-lacks-key',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        // No keyInfo
      );

      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // Verify only 1 group:join command was sent
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();
      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], equals('group-has-key'));
    });

    test(
      'error in one group does not prevent other groups from being rejoined',
      () async {
        final now = DateTime.now().toUtc();

        // Create 2 groups with keys
        await seedGroup(
          groupId: 'group-err-1',
          name: 'Error Group',
          members: [
            GroupMember(
              groupId: 'group-err-1',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-err-1',
            keyGeneration: 1,
            encryptedKey: 'key-err-1',
            createdAt: now,
          ),
        );

        await seedGroup(
          groupId: 'group-err-2',
          name: 'OK Group',
          members: [
            GroupMember(
              groupId: 'group-err-2',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-err-2',
            keyGeneration: 1,
            encryptedKey: 'key-err-2',
            createdAt: now,
          ),
        );

        // Configure bridge to fail on all group:join commands (returns ok:false)
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'TEST_FAIL',
        };

        final events = await captureFlowEvents(() async {
          await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
        });

        // Both groups should have been attempted
        final joinCommands = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .where((m) => m['cmd'] == 'group:join')
            .toList();
        expect(
          joinCommands,
          hasLength(2),
          reason: 'Second group should still be attempted after first fails',
        );

        final errorEvents = events
            .where((event) => event['event'] == 'GROUP_REJOIN_TOPICS_ERROR')
            .toList();
        expect(errorEvents, hasLength(2));
        expect(
          errorEvents.every(
            (event) => (event['details'] as Map<String, dynamic>)['error']
                .toString()
                .contains('TEST_FAIL'),
          ),
          isTrue,
        );

        final groupTimingEvents = events
            .where(
              (event) =>
                  event['event'] == 'GROUP_REJOIN_TOPICS_TIMING' &&
                  (event['details'] as Map<String, dynamic>)['scope'] ==
                      'group',
            )
            .toList();
        expect(groupTimingEvents, hasLength(2));
        expect(
          groupTimingEvents.every(
            (event) =>
                (event['details'] as Map<String, dynamic>)['outcome'] ==
                'error',
          ),
          isTrue,
        );
      },
    );

    test(
      'BB-002 group:join NOT_INITIALIZED records error without local mutation',
      () async {
        final now = DateTime.now().toUtc();
        await seedGroup(
          groupId: 'group-bb002-rejoin',
          name: 'Pre-init Rejoin',
          members: [
            GroupMember(
              groupId: 'group-bb002-rejoin',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-bb002-rejoin',
            keyGeneration: 1,
            encryptedKey: 'old-key',
            createdAt: now,
          ),
        );
        bridge.responses['group:join'] = {
          'ok': false,
          'errorCode': 'NOT_INITIALIZED',
          'errorMessage': 'native node not initialized',
        };

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
        );

        expect(result.joinedGroupCount, 0);
        expect(result.errorCount, 1);
        expect(result.skippedNoKeyCount, 0);
        expect(result.skipped, isFalse);
        expect(bridge.commandLog, contains('group:join'));

        final group = await groupRepo.getGroup('group-bb002-rejoin');
        final members = await groupRepo.getMembers('group-bb002-rejoin');
        final key = await groupRepo.getLatestKey('group-bb002-rejoin');
        expect(group, isNotNull);
        expect(members, hasLength(1));
        expect(members.single.peerId, 'alice');
        expect(key, isNotNull);
        expect(key!.keyGeneration, 1);
        expect(key.encryptedKey, 'old-key');
      },
    );

    test(
      'BB-013 group:join timeout records an error and does not count as joined',
      () async {
        final now = DateTime.now().toUtc();
        await seedGroup(
          groupId: 'group-bb013-rejoin',
          name: 'Timeout Rejoin',
          members: [
            GroupMember(
              groupId: 'group-bb013-rejoin',
              peerId: 'alice',
              username: 'Alice',
              role: MemberRole.admin,
              publicKey: 'pk-alice',
              joinedAt: now,
            ),
          ],
          keyInfo: GroupKeyInfo(
            groupId: 'group-bb013-rejoin',
            keyGeneration: 1,
            encryptedKey: 'old-key',
            createdAt: now,
          ),
        );
        final timeoutBridge = _TimeoutCommandBridge('group:join');

        final result = await rejoinGroupTopics(
          bridge: timeoutBridge,
          groupRepo: groupRepo,
        );

        expect(result.joinedGroupCount, 0);
        expect(result.errorCount, 1);
        expect(result.skippedNoKeyCount, 0);
        expect(timeoutBridge.commandLog, ['group:join']);

        final group = await groupRepo.getGroup('group-bb013-rejoin');
        final members = await groupRepo.getMembers('group-bb013-rejoin');
        final key = await groupRepo.getLatestKey('group-bb013-rejoin');
        expect(group, isNotNull);
        expect(members, hasLength(1));
        expect(members.single.peerId, 'alice');
        expect(key, isNotNull);
        expect(key!.keyGeneration, 1);
        expect(key.encryptedKey, 'old-key');
      },
    );

    test('rejoins archived groups', () async {
      final now = DateTime.now().toUtc();

      // Active group
      await seedGroup(
        groupId: 'group-active',
        name: 'Active',
        members: [
          GroupMember(
            groupId: 'group-active',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-active',
          keyGeneration: 1,
          encryptedKey: 'key-active',
          createdAt: now,
        ),
      );

      // Archived group — should still be rejoined
      await seedGroup(
        groupId: 'group-archived',
        name: 'Archived',
        members: [
          GroupMember(
            groupId: 'group-archived',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-archived',
          keyGeneration: 1,
          encryptedKey: 'key-archived',
          createdAt: now,
        ),
      );
      await groupRepo.archiveGroup('group-archived');

      // -- act --
      await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);

      // -- assert --
      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(2));
      final groupIds = joinCommands
          .map((c) => c['payload']['groupId'] as String)
          .toSet();
      expect(groupIds, {'group-active', 'group-archived'});
    });

    test('skips dissolved groups', () async {
      final now = DateTime.now().toUtc();

      await seedGroup(
        groupId: 'group-active',
        name: 'Active',
        members: [
          GroupMember(
            groupId: 'group-active',
            peerId: 'alice',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-alice',
            joinedAt: now,
          ),
        ],
        keyInfo: GroupKeyInfo(
          groupId: 'group-active',
          keyGeneration: 1,
          encryptedKey: 'key-active',
          createdAt: now,
        ),
      );

      await groupRepo.saveGroup(
        GroupModel(
          id: 'group-dissolved',
          name: 'Dissolved',
          type: GroupType.chat,
          topicName: 'topic-group-dissolved',
          createdAt: now,
          createdBy: 'admin-peer',
          myRole: GroupRole.admin,
          isDissolved: true,
          dissolvedAt: now,
          dissolvedBy: 'admin-peer',
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-dissolved',
          peerId: 'alice',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-alice',
          joinedAt: now,
        ),
      );
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-dissolved',
          keyGeneration: 1,
          encryptedKey: 'key-dissolved',
          createdAt: now,
        ),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );

      final joinCommands = bridge.sentMessages
          .map((m) => jsonDecode(m) as Map<String, dynamic>)
          .where((m) => m['cmd'] == 'group:join')
          .toList();

      expect(joinCommands, hasLength(1));
      expect(joinCommands.first['payload']['groupId'], 'group-active');
      expect(result.joinedGroupCount, 1);
      expect(result.skippedNoKeyCount, 0);
      expect(result.errorCount, 0);
    });
  });

  group('Phase 3 — per-recoverable-set ack eligibility', () {
    GroupMember adminMember(String groupId) {
      return GroupMember(
        groupId: groupId,
        peerId: 'alice',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-alice',
        joinedAt: DateTime.now().toUtc(),
      );
    }

    GroupKeyInfo keyFor(String groupId) {
      return GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'key-base64',
        createdAt: DateTime.now().toUtc(),
      );
    }

    test('a no-key group does NOT block canAcknowledgeGroupRecovery '
        '(the recoverable set acks; no sticky needsGroupRecovery)', () async {
      await seedGroup(
        groupId: 'group-with-key',
        name: 'Has Key',
        members: [adminMember('group-with-key')],
        keyInfo: keyFor('group-with-key'),
      );
      await seedGroup(
        groupId: 'group-no-key',
        name: 'No Key',
        members: [adminMember('group-no-key')],
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );

      expect(result.skippedNoKeyCount, 1);
      expect(result.errorCount, 0);
      // The fix: a permanently-un-rejoinable no-key group no longer blocks
      // the node-wide ack (would be false under the old whole-batch rule).
      expect(result.canAcknowledgeGroupRecovery, isTrue);
      expect(result.perGroupOutcomes['group-with-key'], RejoinOutcome.joined);
      expect(
        result.perGroupOutcomes['group-no-key'],
        RejoinOutcome.skippedNoKey,
      );
    });

    test('a transient per-group rejoin error STILL blocks '
        'canAcknowledgeGroupRecovery (conservative node-wide ack)', () async {
      bridge = _TimeoutCommandBridge('group:join');
      await seedGroup(
        groupId: 'group-fail',
        name: 'Fails To Join',
        members: [adminMember('group-fail')],
        keyInfo: keyFor('group-fail'),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );

      expect(result.errorCount, 1);
      expect(result.canAcknowledgeGroupRecovery, isFalse);
      expect(result.perGroupOutcomes['group-fail'], RejoinOutcome.error);
    });

    test(
      'one transient error does not erase the recoverable outcomes of the '
      'other groups (per-group map is independent of the ack gate)',
      () async {
        await seedGroup(
          groupId: 'group-ok',
          name: 'OK',
          members: [adminMember('group-ok')],
          keyInfo: keyFor('group-ok'),
        );
        await seedGroup(
          groupId: 'group-no-key',
          name: 'No Key',
          members: [adminMember('group-no-key')],
        );
        // group-bad fails only on join; group-ok still joins.
        bridge = _SelectiveJoinFailureBridge(failGroupId: 'group-bad');
        await seedGroup(
          groupId: 'group-bad',
          name: 'Bad',
          members: [adminMember('group-bad')],
          keyInfo: keyFor('group-bad'),
        );

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
        );

        expect(result.perGroupOutcomes['group-ok'], RejoinOutcome.joined);
        expect(
          result.perGroupOutcomes['group-no-key'],
          RejoinOutcome.skippedNoKey,
        );
        expect(result.perGroupOutcomes['group-bad'], RejoinOutcome.error);
        // The transient error still withholds the node-wide ack this pass.
        expect(result.canAcknowledgeGroupRecovery, isFalse);
      },
    );

    test(
      'a dissolved group is recorded skippedDissolved and does not block ack',
      () async {
        final now = DateTime.now().toUtc();
        await seedGroup(
          groupId: 'group-active',
          name: 'Active',
          members: [adminMember('group-active')],
          keyInfo: keyFor('group-active'),
        );
        await groupRepo.saveGroup(
          GroupModel(
            id: 'group-dissolved',
            name: 'Dissolved',
            type: GroupType.chat,
            topicName: 'topic-group-dissolved',
            createdAt: now,
            createdBy: 'admin-peer',
            myRole: GroupRole.admin,
            isDissolved: true,
            dissolvedAt: now,
            dissolvedBy: 'admin-peer',
          ),
        );

        final result = await rejoinGroupTopics(
          bridge: bridge,
          groupRepo: groupRepo,
        );

        expect(result.perGroupOutcomes['group-active'], RejoinOutcome.joined);
        expect(
          result.perGroupOutcomes['group-dissolved'],
          RejoinOutcome.skippedDissolved,
        );
        expect(result.canAcknowledgeGroupRecovery, isTrue);
      },
    );
  });

  group('Phase 3 — bounded per-group rejoin retry', () {
    GroupMember adminMember(String groupId) => GroupMember(
      groupId: groupId,
      peerId: 'alice',
      username: 'Alice',
      role: MemberRole.admin,
      publicKey: 'pk-alice',
      joinedAt: DateTime.now().toUtc(),
    );
    GroupKeyInfo keyFor(String groupId) => GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'key-base64',
      createdAt: DateTime.now().toUtc(),
    );

    test('a failed rejoin records backoff and is skipped (deferred) next pass '
        'without blocking the node-wide ack', () async {
      bridge = _TimeoutCommandBridge('group:join');
      await seedGroup(
        groupId: 'g-bk',
        name: 'Backoff',
        members: [adminMember('g-bk')],
        keyInfo: keyFor('g-bk'),
      );

      final first = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );
      expect(first.perGroupOutcomes['g-bk'], RejoinOutcome.error);
      final states = await groupRepo.loadGroupRejoinStates();
      expect(states['g-bk']!.attemptCount, 1);
      expect(
        states['g-bk']!.nextEligibleAt!.isAfter(DateTime.now().toUtc()),
        isTrue,
      );

      // Immediately re-run: still inside the backoff window → deferred.
      final second = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );
      expect(second.perGroupOutcomes['g-bk'], RejoinOutcome.deferred);
      expect(second.deferredCount, 1);
      expect(second.errorCount, 0);
      // A deferred (backed-off) group does NOT block the ack.
      expect(second.canAcknowledgeGroupRecovery, isTrue);
    });

    test('a group exceeding the rejoin attempt cap emits '
        'GROUP_REJOIN_PERMANENTLY_STUCK', () async {
      bridge = _TimeoutCommandBridge('group:join');
      await seedGroup(
        groupId: 'g-stuck',
        name: 'Stuck',
        members: [adminMember('g-stuck')],
        keyInfo: keyFor('g-stuck'),
      );
      // Pre-seed 9 prior failures, each eligible now (past window), so this
      // pass is attempt 10 and trips the cap.
      for (var i = 0; i < 9; i++) {
        await groupRepo.recordGroupRejoinFailure(
          'g-stuck',
          nextEligibleAt: DateTime.now().toUtc().subtract(
            const Duration(days: 1),
          ),
        );
      }

      final events = await captureFlowEvents(() async {
        await rejoinGroupTopics(bridge: bridge, groupRepo: groupRepo);
      });
      expect(
        events.any((e) => e['event'] == 'GROUP_REJOIN_PERMANENTLY_STUCK'),
        isTrue,
      );
      expect(
        (await groupRepo.loadGroupRejoinStates())['g-stuck']!.attemptCount,
        10,
      );
    });

    test('a successful rejoin clears the backoff state', () async {
      await seedGroup(
        groupId: 'g-ok',
        name: 'OK',
        members: [adminMember('g-ok')],
        keyInfo: keyFor('g-ok'),
      );
      // A prior failure, now eligible (past window) so it is attempted again.
      await groupRepo.recordGroupRejoinFailure(
        'g-ok',
        nextEligibleAt: DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        ),
      );
      expect((await groupRepo.loadGroupRejoinStates())['g-ok'], isNotNull);

      // The default bridge joins successfully → state cleared.
      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );
      expect(result.perGroupOutcomes['g-ok'], RejoinOutcome.joined);
      expect((await groupRepo.loadGroupRejoinStates())['g-ok'], isNull);
    });
  });
}
