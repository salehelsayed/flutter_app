import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

void main() {
  test(
    'PB265-02 inbox timeout and throw degrade only after durable notice checkpoint',
    () async {
      final observations = <_Observation>[];
      for (final fault in _InboxFault.values) {
        observations.add(await _runFaultCase(fault));
      }

      for (final observation in observations) {
        expect(
          observation.durableNoticeWasExact,
          isTrue,
          reason: observation.fault.name,
        );
        expect(observation.primarySignCount, 1, reason: observation.fault.name);
        expect(observation.prepareCalls, 0, reason: observation.fault.name);
        expect(observation.attemptedNotices, hasLength(1));
        expect(
          sameExactGroupPendingBroadcast(
            observation.attemptedNotices.single,
            observation.durableNotice,
          ),
          isTrue,
          reason: observation.fault.name,
        );
        expect(
          observation.result.status,
          GroupExitIntentProcessStatus.completed,
          reason: observation.fault.name,
        );
        expect(
          observation.result.cause,
          isNull,
          reason: observation.fault.name,
        );
        expect(observation.nativeLeaves, 1, reason: observation.fault.name);
        expect(
          observation.attempt.classification,
          VoluntaryLeaveNoticeAttemptClassification.degraded,
          reason: observation.fault.name,
        );
        expect(
          observation.intentRepository.completionCodes,
          <String>[GroupExitPersistedOutcome.noticeDegraded.persistedCode],
          reason: observation.fault.name,
        );
        expect(
          observation.intentRepository.persistedDiagnosticValues.toSet(),
          <String>{GroupExitPersistedOutcome.noticeDegraded.persistedCode},
          reason: observation.fault.name,
        );
        expect(
          observation.intentRepository.persistedDiagnosticValues.join('|'),
          isNot(contains(observation.fault.rawMarker)),
          reason: observation.fault.name,
        );
      }

      for (final observation in observations) {
        final inboxPayloads = observation.bridge.sentMessages
            .map((message) => jsonDecode(message) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxStore')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .toList(growable: false);

        expect(inboxPayloads.length, 1, reason: observation.fault.name);
        expect(
          inboxPayloads.single['recipientPeerIds'],
          observation.durableNotice.recipientPeerIds,
          reason: observation.fault.name,
        );
        expect(
          inboxPayloads.single['preserveRecipientPeerIds'],
          isTrue,
          reason: observation.fault.name,
        );
        expect(
          observation.attempt.offlineReplayStatus,
          VoluntaryLeaveOfflineReplayStatus.aggregateStoreDegraded,
          reason: observation.fault.name,
        );
      }
    },
  );

  test(
    'PB265-03 replay encrypt and second-sign faults degrade after state inputs are pinned',
    () async {
      for (final replayFault in const <_ReplayFault>[
        _ReplayFault.encrypt,
        _ReplayFault.envelopeSign,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-03-${replayFault.name}',
        );
        final observation = await fixture.run(
          _ScriptedLeaveBridge(replayFault: replayFault),
        );

        _expectCompletedAttempt(
          observation,
          classification: VoluntaryLeaveNoticeAttemptClassification.degraded,
          offlineStatus: VoluntaryLeaveOfflineReplayStatus.preparationDegraded,
          completionOutcome: GroupExitPersistedOutcome.noticeDegraded,
          finalOutcome: GroupExitPersistedOutcome.noticeDegraded,
        );
        expect(
          fixture.groupRepository.latestKeyLoads,
          1,
          reason: replayFault.name,
        );
        expect(
          _commandCount(observation.bridge, 'group.encrypt'),
          1,
          reason: replayFault.name,
        );
        expect(
          _commandCount(observation.bridge, 'group:inboxStore'),
          0,
          reason: replayFault.name,
        );
        expect(
          observation.bridge.payloadSignCalls,
          replayFault == _ReplayFault.encrypt ? 1 : 2,
          reason: replayFault.name,
        );
        _expectNoRawDiagnostic(observation, replayFault.rawMarker);
      }
    },
  );

  test(
    'PB265-04 live publish non-ok and throw stay degraded and still attempt offline replay',
    () async {
      for (final liveFault in const <_LiveFault>[
        _LiveFault.nonOk,
        _LiveFault.timeout,
        _LiveFault.malformed,
        _LiveFault.genericThrow,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-04-${liveFault.name}',
        );
        final observation = await fixture.run(
          _ScriptedLeaveBridge(liveFault: liveFault),
        );

        _expectCompletedAttempt(
          observation,
          classification: VoluntaryLeaveNoticeAttemptClassification.degraded,
          offlineStatus: VoluntaryLeaveOfflineReplayStatus.aggregateAccepted,
          completionOutcome: GroupExitPersistedOutcome.noticeDegraded,
          finalOutcome: GroupExitPersistedOutcome.noticeDegraded,
        );
        final inboxPayloads = _commandPayloads(
          observation.bridge,
          'group:inboxStore',
        );
        expect(inboxPayloads.length, 1, reason: liveFault.name);
        expect(
          inboxPayloads.single['recipientPeerIds'],
          fixture.durableNotice.recipientPeerIds,
          reason: liveFault.name,
        );
        expect(
          observation.bridge.commandLog.indexOf('group:publish'),
          lessThan(observation.bridge.commandLog.indexOf('group:inboxStore')),
          reason: liveFault.name,
        );
        _expectNoRawDiagnostic(observation, liveFault.rawMarker);
      }
    },
  );

  test(
    'PB265-05 zero-peer or failed live plus inbox failure leaves once without custody claim',
    () async {
      for (final liveFault in const <_LiveFault>[
        _LiveFault.nonOk,
        _LiveFault.okZeroPeers,
        _LiveFault.genericThrow,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-05-${liveFault.name}',
        );
        final observation = await fixture.run(
          _ScriptedLeaveBridge(
            liveFault: liveFault,
            inboxFault: _InboxStoreFault.nonOk,
          ),
        );

        _expectCompletedAttempt(
          observation,
          classification: VoluntaryLeaveNoticeAttemptClassification.degraded,
          offlineStatus:
              VoluntaryLeaveOfflineReplayStatus.aggregateStoreDegraded,
          completionOutcome: GroupExitPersistedOutcome.noticeDegraded,
          finalOutcome: GroupExitPersistedOutcome.noticeDegraded,
        );
        expect(
          observation.attempt!.classification,
          isNot(VoluntaryLeaveNoticeAttemptClassification.delivered),
          reason: liveFault.name,
        );
        expect(
          _commandCount(observation.bridge, 'group:inboxStore'),
          1,
          reason: liveFault.name,
        );
        if (liveFault == _LiveFault.okZeroPeers) {
          expect(observation.attempt!.livePublishResult?['ok'], isTrue);
          expect(observation.attempt!.livePublishResult?['topicPeers'], 0);
        }
        _expectNoRawDiagnostic(observation, liveFault.rawMarker);
        _expectNoRawDiagnostic(observation, _InboxStoreFault.nonOk.rawMarker);
      }
    },
  );

  test(
    'PB265-07 state lookup or completion CAS failure retains the exact notice',
    () async {
      for (final keyBehavior in const <_ReplayKeyBehavior>[
        _ReplayKeyBehavior.missing,
        _ReplayKeyBehavior.throws,
        _ReplayKeyBehavior.wrongGroup,
        _ReplayKeyBehavior.emptyMaterial,
        _ReplayKeyBehavior.invalidEpoch,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-07-key-${keyBehavior.name}',
          keyBehavior: keyBehavior,
        );
        final observation = await fixture.run(_ScriptedLeaveBridge());

        expect(observation.processError, isNull, reason: keyBehavior.name);
        expect(
          observation.result?.status,
          GroupExitIntentProcessStatus.waitingForNoticeRetry,
          reason: keyBehavior.name,
        );
        expect(
          observation.attempt?.classification,
          VoluntaryLeaveNoticeAttemptClassification.retryable,
          reason: keyBehavior.name,
        );
        expect(
          observation.attempt?.offlineReplayStatus,
          VoluntaryLeaveOfflineReplayStatus.notAttempted,
          reason: keyBehavior.name,
        );
        expect(observation.rotationCalls, 0, reason: keyBehavior.name);
        expect(observation.nativeLeaves, 0, reason: keyBehavior.name);
        expect(
          _commandCount(observation.bridge, 'group:inboxStore'),
          0,
          reason: keyBehavior.name,
        );
        expect(
          _commandCount(observation.bridge, 'group.encrypt'),
          0,
          reason: keyBehavior.name,
        );
        expect(
          await fixture.retainsExactNoticeAndIntent(),
          isTrue,
          reason: keyBehavior.name,
        );
        expect(fixture.intentRepository.completionCodes, isEmpty);
      }

      for (final completionBehavior in const <_CompletionBehavior>[
        _CompletionBehavior.refuses,
        _CompletionBehavior.throws,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-07-complete-${completionBehavior.name}',
          completionBehavior: completionBehavior,
        );
        final observation = await fixture.run(_ScriptedLeaveBridge());

        expect(
          observation.attempt?.classification,
          VoluntaryLeaveNoticeAttemptClassification.delivered,
          reason: completionBehavior.name,
        );
        expect(
          observation.attempt?.offlineReplayStatus,
          VoluntaryLeaveOfflineReplayStatus.aggregateAccepted,
          reason: completionBehavior.name,
        );
        if (completionBehavior == _CompletionBehavior.refuses) {
          expect(observation.processError, isNull);
          expect(
            observation.result?.status,
            GroupExitIntentProcessStatus.failed,
          );
        } else {
          expect(observation.result, isNull);
          expect(observation.processError, isA<StateError>());
        }
        expect(observation.rotationCalls, 0);
        expect(observation.nativeLeaves, 0);
        expect(
          await fixture.retainsExactNoticeAndIntent(),
          isTrue,
          reason: completionBehavior.name,
        );
        expect(fixture.intentRepository.completionCodes, isEmpty);
        expect(fixture.intentRepository.persistedDiagnosticValues, isEmpty);
        expect(
          fixture.intentRepository.persistedDiagnosticValues.join('|'),
          isNot(contains(completionBehavior.rawMarker)),
        );
      }
    },
  );

  test(
    'PB265-09 aggregate attempt preserves signed recipients and explicit bridge authority',
    () async {
      final fixture = await _PreparedLeaveFixture.create(
        'pb265-09',
        reversePersistedRecipients: true,
      );
      final observation = await fixture.run(_ScriptedLeaveBridge());

      _expectCompletedAttempt(
        observation,
        classification: VoluntaryLeaveNoticeAttemptClassification.delivered,
        offlineStatus: VoluntaryLeaveOfflineReplayStatus.aggregateAccepted,
        completionOutcome: GroupExitPersistedOutcome.noticeDelivered,
        finalOutcome: GroupExitPersistedOutcome.noticeDelivered,
      );
      const normalizedRecipients = <String>['peer-admin', 'peer-third'];
      const persistedNonLexicalRecipients = <String>[
        'peer-third',
        'peer-admin',
      ];
      expect(
        fixture.durableNotice.recipientPeerIds,
        persistedNonLexicalRecipients,
      );

      final signedNotice =
          jsonDecode(fixture.durableNotice.sysText) as Map<String, dynamic>;
      final groupConfig = signedNotice['groupConfig'] as Map<String, dynamic>;
      final persistedSignedRecipientIds =
          (groupConfig['members'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map((member) => member['peerId'] as String)
              .toList(growable: false);
      expect(persistedSignedRecipientIds, persistedNonLexicalRecipients);
      final normalizedSignedRecipientIds =
          persistedSignedRecipientIds.toSet().toList(growable: true)..sort();
      expect(normalizedSignedRecipientIds, normalizedRecipients);

      final inboxPayloads = _commandPayloads(
        observation.bridge,
        'group:inboxStore',
      );
      expect(inboxPayloads.length, 1);
      final outer = inboxPayloads.single;
      expect(outer['recipientPeerIds'], normalizedRecipients);
      expect(outer['preserveRecipientPeerIds'], isTrue);
      final envelope =
          jsonDecode(outer['message'] as String) as Map<String, dynamic>;
      expect(envelope['recipientPeerIds'], normalizedRecipients);
      final replaySignedPayload =
          jsonDecode(envelope['signedPayload'] as String)
              as Map<String, dynamic>;
      final expectedRecipientSetHash = sha256
          .convert(utf8.encode(jsonEncode(normalizedRecipients)))
          .toString();
      expect(envelope['recipientSetHash'], expectedRecipientSetHash);
      expect(replaySignedPayload['recipientSetHash'], expectedRecipientSetHash);
      expect(
        observation.fixture.intentRepository.persistedDiagnosticValues.join(
          '|',
        ),
        isNot(anyOf(contains('peer-admin'), contains('peer-third'))),
      );
    },
  );

  test(
    'PB265-11 delivery and rotation faults retain the accepted combined outcome',
    () async {
      for (final rotationFault in const <_RotationFault>[
        _RotationFault.typedDeferred,
        _RotationFault.genericThrow,
      ]) {
        final fixture = await _PreparedLeaveFixture.create(
          'pb265-11-${rotationFault.name}',
        );
        final observation = await fixture.run(
          _ScriptedLeaveBridge(inboxFault: _InboxStoreFault.nonOk),
          rotationFault: rotationFault,
        );
        final composite =
            GroupExitPersistedOutcome.noticeDegradedRotationDeferred;

        _expectCompletedAttempt(
          observation,
          classification: VoluntaryLeaveNoticeAttemptClassification.degraded,
          offlineStatus:
              VoluntaryLeaveOfflineReplayStatus.aggregateStoreDegraded,
          completionOutcome: GroupExitPersistedOutcome.noticeDegraded,
          finalOutcome: composite,
        );
        expect(observation.rotationCalls, 1, reason: rotationFault.name);
        expect(
          fixture.intentRepository.codeWrittenFor(
            GroupExitIntentState.nativeLeavePending,
          ),
          composite.persistedCode,
          reason: rotationFault.name,
        );
        expect(
          fixture.intentRepository.codeWrittenFor(
            GroupExitIntentState.cleanupPending,
          ),
          composite.persistedCode,
          reason: rotationFault.name,
        );
        expect(
          fixture.intentRepository.cleanupExpectedCodes,
          <String?>[composite.persistedCode],
          reason: rotationFault.name,
        );
        _expectNoRawDiagnostic(observation, rotationFault.rawMarker);
      }

      final restartFixture = await _PreparedLeaveFixture.create(
        'pb265-11-restart',
      );
      await restartFixture.pendingRepository.remove(
        restartFixture.durableNotice.id,
      );
      restartFixture.intentRepository.current = restartFixture.initialIntent
          .copyWith(
            state: GroupExitIntentState.rotationClaimed,
            revision: 3,
            lastErrorCode:
                GroupExitPersistedOutcome.noticeDegraded.persistedCode,
          );
      final restarted = await restartFixture.run(_ScriptedLeaveBridge());
      final restartComposite =
          GroupExitPersistedOutcome.noticeDegradedRotationDeferredRestart;

      expect(restarted.processError, isNull);
      expect(restarted.result?.status, GroupExitIntentProcessStatus.completed);
      expect(restarted.attempt, isNull);
      expect(restarted.attemptedNotices, isEmpty);
      expect(restarted.rotationCalls, 0);
      expect(restarted.nativeLeaves, 1);
      expect(
        restartFixture.intentRepository.codeWrittenFor(
          GroupExitIntentState.nativeLeavePending,
        ),
        restartComposite.persistedCode,
      );
      expect(
        restartFixture.intentRepository.codeWrittenFor(
          GroupExitIntentState.cleanupPending,
        ),
        restartComposite.persistedCode,
      );
      expect(restartFixture.intentRepository.cleanupExpectedCodes, <String?>[
        restartComposite.persistedCode,
      ]);
    },
  );
}

Future<_Observation> _runFaultCase(_InboxFault fault) async {
  final now = DateTime.utc(2026, 7, 21, 16, fault.index);
  final groupId = 'pb265-02-${fault.name}';
  const selfPeerId = 'peer-self';
  const adminPeerId = 'peer-admin';
  const thirdPeerId = 'peer-third';

  GroupMember member(String peerId, MemberRole role) => GroupMember(
    groupId: groupId,
    peerId: peerId,
    username: peerId,
    role: role,
    publicKey: 'pk-$peerId',
    mlKemPublicKey: 'mlkem-$peerId',
    joinedAt: now,
  );

  final group = GroupModel(
    id: groupId,
    name: 'PB265 degradation',
    type: GroupType.chat,
    topicName: 'topic-$groupId',
    createdAt: now,
    createdBy: adminPeerId,
    myRole: GroupRole.member,
  );
  final groupRepository = InMemoryGroupRepository();
  await groupRepository.saveGroup(group);
  await groupRepository.saveMember(member(selfPeerId, MemberRole.writer));
  await groupRepository.saveMember(member(adminPeerId, MemberRole.admin));
  await groupRepository.saveMember(member(thirdPeerId, MemberRole.writer));
  await groupRepository.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: 1,
      encryptedKey: 'group-key-1',
      createdAt: now,
    ),
  );

  final identityRepository = FakeIdentityRepository()
    ..seed(
      FakeIdentityRepository.makeIdentity(
        peerId: selfPeerId,
        publicKey: 'pk-$selfPeerId',
        privateKey: 'sk-$selfPeerId',
        mlKemPublicKey: 'mlkem-$selfPeerId',
      ),
    );
  final prepareBridge = FakeBridge();
  final sourceEventId = 'member_removed:$groupId:$selfPeerId:intent-$groupId';
  final preparation = await prepareVoluntaryLeaveNotice(
    bridge: prepareBridge,
    groupRepo: groupRepository,
    group: group,
    identityRepo: identityRepository,
    expectedSelfPeerId: selfPeerId,
    sourceEventId: sourceEventId,
    eventAt: now,
  );
  final prepared = requirePreparedVoluntaryLeaveNotice(preparation);
  final durableNotice = prepared.pendingBroadcast;
  final intent = GroupExitIntent(
    groupId: groupId,
    intentId: 'intent-$groupId',
    selfPeerId: selfPeerId,
    selfJoinedAt: now,
    state: GroupExitIntentState.leaveNoticePending,
    pendingBroadcastId: durableNotice.id,
    sourceEventId: sourceEventId,
    eventAt: now,
    revision: 1,
    createdAt: now,
    updatedAt: now,
  );
  final pendingRepository = _PendingRepository(durableNotice);
  final intentRepository = _IntentRepository(
    pendingRepository: pendingRepository,
    initial: intent,
  );
  final durableRows = await pendingRepository.forGroup(groupId);
  final durableIntent = await intentRepository.forGroup(groupId);
  final durableNoticeWasExact =
      durableIntent != null &&
      sameExactGroupExitIntent(durableIntent, intent) &&
      durableRows.length == 1 &&
      sameExactGroupPendingBroadcast(durableRows.single, durableNotice) &&
      hasExactSignedVoluntaryLeaveNoticeAuthority(
        pendingBroadcast: durableRows.single,
        expectedGroupId: groupId,
        expectedSelfPeerId: selfPeerId,
        expectedSourceEventId: sourceEventId,
        expectedEventAt: now,
      );

  final bridge = _CommandScopedInboxFailureBridge(fault);
  final attemptedNotices = <GroupPendingBroadcast>[];
  late VoluntaryLeaveNoticeAttemptResult attempt;
  var prepareCalls = 0;
  var nativeLeaves = 0;
  final runner = GroupExitIntentRunner(
    intentRepository: intentRepository,
    pendingRepository: pendingRepository,
    pendingBroadcastRunner: GroupPendingBroadcastRunner(
      repository: pendingRepository,
      rePush: (_) async => true,
    ),
    groupRepository: groupRepository,
    loadCurrentSelfPeerId: () async => selfPeerId,
    prepareNotice:
        ({required intent, required sourceEventId, required eventAt}) async {
          prepareCalls++;
          throw StateError('durable notice must not be prepared again');
        },
    attemptNotice: ({required intent, required pendingBroadcast}) async {
      attemptedNotices.add(pendingBroadcast);
      attempt = await attemptPreparedVoluntaryLeaveNotice(
        bridge: bridge,
        groupRepo: groupRepository,
        prepared: PreparedVoluntaryLeaveNotice(
          pendingBroadcast: pendingBroadcast,
          timelineMessage: prepared.timelineMessage,
          identity: prepared.identity,
          senderBinding: prepared.senderBinding,
          remainingMembers: prepared.remainingMembers,
        ),
        expectedSelfPeerId: intent.selfPeerId,
      );
      return switch (attempt.classification) {
        VoluntaryLeaveNoticeAttemptClassification.delivered =>
          GroupExitNoticeAttemptDisposition.delivered,
        VoluntaryLeaveNoticeAttemptClassification.degraded =>
          GroupExitNoticeAttemptDisposition.degraded,
        VoluntaryLeaveNoticeAttemptClassification.retryable =>
          GroupExitNoticeAttemptDisposition.retryable,
      };
    },
    rotateKeys: (_) async {},
    nativeLeave: (_) async => nativeLeaves++,
    now: () => now,
  );

  final result = await runner.processGroup(groupId, drainRoleBroadcasts: false);
  return _Observation(
    fault: fault,
    bridge: bridge,
    durableNotice: durableNotice,
    durableNoticeWasExact: durableNoticeWasExact,
    primarySignCount: prepareBridge.commandLog
        .where((command) => command == 'payload.sign')
        .length,
    prepareCalls: prepareCalls,
    attemptedNotices: attemptedNotices,
    attempt: attempt,
    result: result,
    nativeLeaves: nativeLeaves,
    intentRepository: intentRepository,
  );
}

enum _InboxFault {
  timeout('raw timeout detail must not persist'),
  genericThrow('raw generic transport detail must not persist');

  const _InboxFault(this.rawMarker);

  final String rawMarker;
}

class _CommandScopedInboxFailureBridge extends FakeBridge {
  _CommandScopedInboxFailureBridge(this.fault);

  final _InboxFault fault;

  @override
  Future<String> send(String message) async {
    final response = await super.send(message);
    final command = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (command != 'group:inboxStore') return response;
    switch (fault) {
      case _InboxFault.timeout:
        throw TimeoutException(fault.rawMarker);
      case _InboxFault.genericThrow:
        throw Exception(fault.rawMarker);
    }
  }
}

class _PendingRepository implements GroupPendingBroadcastRepository {
  _PendingRepository(GroupPendingBroadcast initial)
    : rows = <String, GroupPendingBroadcast>{initial.id: initial};

  final Map<String, GroupPendingBroadcast> rows;

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    rows[broadcast.id] = broadcast;
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async => rows
      .values
      .where((row) => row.groupId == groupId)
      .toList(growable: false);

  @override
  Future<List<GroupPendingBroadcast>> all() async =>
      rows.values.toList(growable: false);

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((row) => row.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, row) => row.groupId == groupId);
  }
}

class _IntentRepository implements GroupExitIntentRepository {
  _IntentRepository({
    required this.pendingRepository,
    required GroupExitIntent initial,
    this.completionBehavior = _CompletionBehavior.succeeds,
  }) : current = initial;

  final _PendingRepository pendingRepository;
  final _CompletionBehavior completionBehavior;
  GroupExitIntent? current;
  final List<String> persistedDiagnosticValues = <String>[];
  final List<String> completionCodes = <String>[];
  final List<_AdvanceWrite> advanceWrites = <_AdvanceWrite>[];
  final List<String?> cleanupExpectedCodes = <String?>[];

  GroupExitIntentMutationResult _conflict() => GroupExitIntentMutationResult(
    disposition: GroupExitIntentMutationDisposition.refusedConflict,
    current: current,
  );

  GroupExitIntentMutationResult _commit(GroupExitIntent next) {
    current = next;
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: next,
    );
  }

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async =>
      current?.groupId == groupId ? current : null;

  @override
  Future<List<GroupExitIntent>> all() async =>
      current == null ? const <GroupExitIntent>[] : <GroupExitIntent>[current!];

  @override
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  }) async {
    final loaded = current;
    final queued = pendingRepository.rows[pendingBroadcast.id];
    if (loaded == null ||
        !sameExactGroupExitIntent(loaded, expected) ||
        queued == null ||
        !sameExactGroupPendingBroadcast(queued, pendingBroadcast)) {
      return _conflict();
    }
    switch (completionBehavior) {
      case _CompletionBehavior.succeeds:
        break;
      case _CompletionBehavior.refuses:
        return GroupExitIntentMutationResult(
          disposition: GroupExitIntentMutationDisposition.refusedNoticeMissing,
          current: loaded,
        );
      case _CompletionBehavior.throws:
        throw StateError(completionBehavior.rawMarker);
    }
    await pendingRepository.remove(pendingBroadcast.id);
    completionCodes.add(completionCode);
    persistedDiagnosticValues.add(completionCode);
    return _commit(
      loaded.copyWith(
        state: GroupExitIntentState.leaveNoticeAttempted,
        revision: loaded.revision + 1,
        updatedAt: updatedAt,
        lastErrorCode: completionCode,
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> advance({
    required GroupExitIntent expected,
    required GroupExitIntentState nextState,
    required DateTime updatedAt,
    String? lastErrorCode,
  }) async {
    final loaded = current;
    if (loaded == null || !sameExactGroupExitIntent(loaded, expected)) {
      return _conflict();
    }
    if (lastErrorCode != null) {
      persistedDiagnosticValues.add(lastErrorCode);
    }
    advanceWrites.add(_AdvanceWrite(nextState, lastErrorCode));
    return _commit(
      loaded.copyWith(
        state: nextState,
        revision: loaded.revision + 1,
        updatedAt: updatedAt,
        lastErrorCode: lastErrorCode,
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    final loaded = current;
    if (loaded == null || !sameExactGroupExitIntent(loaded, expected)) {
      return _conflict();
    }
    cleanupExpectedCodes.add(loaded.lastErrorCode);
    current = null;
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> retireExact(
    GroupExitIntent expected,
  ) async {
    final loaded = current;
    if (loaded == null || !sameExactGroupExitIntent(loaded, expected)) {
      return _conflict();
    }
    current = null;
    await pendingRepository.remove(expected.pendingBroadcastId);
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<int> terminalizeForGroup(String groupId) async {
    final loaded = current;
    if (loaded == null || loaded.groupId != groupId) return 0;
    current = null;
    await pendingRepository.remove(loaded.pendingBroadcastId);
    return 1;
  }

  String? codeWrittenFor(GroupExitIntentState state) =>
      advanceWrites.singleWhere((write) => write.state == state).lastErrorCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected repository call: ${invocation.memberName}',
  );
}

class _Observation {
  const _Observation({
    required this.fault,
    required this.bridge,
    required this.durableNotice,
    required this.durableNoticeWasExact,
    required this.primarySignCount,
    required this.prepareCalls,
    required this.attemptedNotices,
    required this.attempt,
    required this.result,
    required this.nativeLeaves,
    required this.intentRepository,
  });

  final _InboxFault fault;
  final _CommandScopedInboxFailureBridge bridge;
  final GroupPendingBroadcast durableNotice;
  final bool durableNoticeWasExact;
  final int primarySignCount;
  final int prepareCalls;
  final List<GroupPendingBroadcast> attemptedNotices;
  final VoluntaryLeaveNoticeAttemptResult attempt;
  final GroupExitIntentProcessResult result;
  final int nativeLeaves;
  final _IntentRepository intentRepository;
}

class _AdvanceWrite {
  const _AdvanceWrite(this.state, this.lastErrorCode);

  final GroupExitIntentState state;
  final String? lastErrorCode;
}

enum _CompletionBehavior {
  succeeds(''),
  refuses('raw completion refusal must not persist'),
  throws('raw completion throw must not persist');

  const _CompletionBehavior(this.rawMarker);

  final String rawMarker;
}

enum _ReplayKeyBehavior {
  available(''),
  missing('raw missing replay key detail must not persist'),
  throws('raw replay key lookup throw must not persist'),
  wrongGroup('raw wrong-group replay key detail must not persist'),
  emptyMaterial('raw empty replay key detail must not persist'),
  invalidEpoch('raw invalid replay key epoch detail must not persist');

  const _ReplayKeyBehavior(this.rawMarker);

  final String rawMarker;
}

enum _ReplayFault {
  none(''),
  encrypt('raw replay encrypt detail must not persist'),
  envelopeSign('raw replay envelope sign detail must not persist');

  const _ReplayFault(this.rawMarker);

  final String rawMarker;
}

enum _LiveFault {
  successWithPeers(''),
  nonOk('raw live non-ok detail must not persist'),
  timeout('raw live timeout detail must not persist'),
  malformed('raw malformed live response must not persist'),
  genericThrow('raw live generic throw must not persist'),
  okZeroPeers('');

  const _LiveFault(this.rawMarker);

  final String rawMarker;
}

enum _InboxStoreFault {
  none(''),
  nonOk('raw inbox non-ok detail must not persist');

  const _InboxStoreFault(this.rawMarker);

  final String rawMarker;
}

enum _RotationFault {
  none(''),
  typedDeferred('typed rotation defer detail must not persist'),
  genericThrow('raw rotation throw detail must not persist');

  const _RotationFault(this.rawMarker);

  final String rawMarker;
}

class _TrackingGroupRepository extends InMemoryGroupRepository {
  _TrackingGroupRepository();

  _ReplayKeyBehavior keyBehavior = _ReplayKeyBehavior.available;
  int latestKeyLoads = 0;

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    latestKeyLoads++;
    final available = await super.getLatestKey(groupId);
    switch (keyBehavior) {
      case _ReplayKeyBehavior.available:
        return available;
      case _ReplayKeyBehavior.missing:
        return null;
      case _ReplayKeyBehavior.throws:
        throw StateError(keyBehavior.rawMarker);
      case _ReplayKeyBehavior.wrongGroup:
        return GroupKeyInfo(
          groupId: 'wrong-$groupId',
          keyGeneration: available!.keyGeneration,
          encryptedKey: available.encryptedKey,
          createdAt: available.createdAt,
        );
      case _ReplayKeyBehavior.emptyMaterial:
        return GroupKeyInfo(
          groupId: groupId,
          keyGeneration: available!.keyGeneration,
          encryptedKey: '',
          createdAt: available.createdAt,
        );
      case _ReplayKeyBehavior.invalidEpoch:
        return GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 0,
          encryptedKey: available!.encryptedKey,
          createdAt: available.createdAt,
        );
    }
  }
}

class _ScriptedLeaveBridge extends FakeBridge {
  _ScriptedLeaveBridge({
    this.replayFault = _ReplayFault.none,
    this.liveFault = _LiveFault.successWithPeers,
    this.inboxFault = _InboxStoreFault.none,
  });

  final _ReplayFault replayFault;
  final _LiveFault liveFault;
  final _InboxStoreFault inboxFault;
  int payloadSignCalls = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final command = parsed['cmd'] as String?;
    if (command == 'payload.sign') payloadSignCalls++;
    final response = await super.send(message);

    if (command == 'group:publish') {
      switch (liveFault) {
        case _LiveFault.successWithPeers:
          return jsonEncode(<String, Object?>{
            'ok': true,
            'messageId': 'live-published',
            'topicPeers': 1,
          });
        case _LiveFault.nonOk:
          return jsonEncode(<String, Object?>{
            'ok': false,
            'errorCode': 'LIVE_NON_OK',
            'errorMessage': liveFault.rawMarker,
          });
        case _LiveFault.timeout:
          throw TimeoutException(liveFault.rawMarker);
        case _LiveFault.malformed:
          return liveFault.rawMarker;
        case _LiveFault.genericThrow:
          throw Exception(liveFault.rawMarker);
        case _LiveFault.okZeroPeers:
          return jsonEncode(<String, Object?>{
            'ok': true,
            'messageId': 'live-zero-peer',
            'topicPeers': 0,
          });
      }
    }
    if (command == 'group.encrypt' && replayFault == _ReplayFault.encrypt) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'errorCode': 'REPLAY_ENCRYPT_FAILED',
        'errorMessage': replayFault.rawMarker,
      });
    }
    if (command == 'payload.sign' &&
        replayFault == _ReplayFault.envelopeSign &&
        payloadSignCalls == 2) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'errorCode': 'REPLAY_SIGN_FAILED',
        'errorMessage': replayFault.rawMarker,
      });
    }
    if (command == 'group:inboxStore' && inboxFault == _InboxStoreFault.nonOk) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'errorCode': 'INBOX_STORE_FAILED',
        'errorMessage': inboxFault.rawMarker,
      });
    }
    return response;
  }
}

PreparedVoluntaryLeaveNotice _withReversedPersistedRecipientAuthority(
  PreparedVoluntaryLeaveNotice prepared,
) {
  final pending = prepared.pendingBroadcast;
  final reversedRecipientIds = pending.recipientPeerIds.reversed.toList(
    growable: false,
  );
  final payload = Map<String, dynamic>.from(jsonDecode(pending.sysText) as Map);
  final groupConfig = Map<String, dynamic>.from(payload['groupConfig'] as Map);
  final members = (groupConfig['members'] as List<dynamic>)
      .map((member) => Map<String, dynamic>.from(member as Map))
      .toList(growable: false);
  final membersByPeerId = <String, Map<String, dynamic>>{
    for (final member in members) member['peerId'] as String: member,
  };
  groupConfig['members'] = <Map<String, dynamic>>[
    for (final peerId in reversedRecipientIds) membersByPeerId[peerId]!,
  ];
  payload['groupConfig'] = groupConfig;

  final reorderedPending = GroupPendingBroadcast(
    id: pending.id,
    groupId: pending.groupId,
    kind: pending.kind,
    sysText: jsonEncode(payload),
    recipientPeerIds: reversedRecipientIds,
    eventAt: pending.eventAt,
    sourceMessageId: pending.sourceMessageId,
    createdAt: pending.createdAt,
    updatedAt: pending.updatedAt,
  );
  final remainingByPeerId = <String, GroupMember>{
    for (final member in prepared.remainingMembers) member.peerId: member,
  };
  return PreparedVoluntaryLeaveNotice(
    pendingBroadcast: reorderedPending,
    timelineMessage: prepared.timelineMessage,
    identity: prepared.identity,
    senderBinding: prepared.senderBinding,
    remainingMembers: <GroupMember>[
      for (final peerId in reversedRecipientIds) remainingByPeerId[peerId]!,
    ],
  );
}

class _PreparedLeaveFixture {
  const _PreparedLeaveFixture({
    required this.now,
    required this.groupId,
    required this.groupRepository,
    required this.prepared,
    required this.initialIntent,
    required this.pendingRepository,
    required this.intentRepository,
    required this.primarySignCount,
    required this.durableNoticeWasExact,
  });

  static Future<_PreparedLeaveFixture> create(
    String groupId, {
    _ReplayKeyBehavior keyBehavior = _ReplayKeyBehavior.available,
    _CompletionBehavior completionBehavior = _CompletionBehavior.succeeds,
    bool reversePersistedRecipients = false,
  }) async {
    final suffix = groupId.codeUnits.fold<int>(0, (sum, value) => sum + value);
    final now = DateTime.utc(
      2026,
      7,
      21,
      17,
    ).add(Duration(microseconds: suffix));
    const selfPeerId = 'peer-self';
    const adminPeerId = 'peer-admin';
    const thirdPeerId = 'peer-third';

    GroupMember member(String peerId, MemberRole role) => GroupMember(
      groupId: groupId,
      peerId: peerId,
      username: peerId,
      role: role,
      publicKey: 'pk-$peerId',
      mlKemPublicKey: 'mlkem-$peerId',
      joinedAt: now,
    );

    final group = GroupModel(
      id: groupId,
      name: 'PB265 degradation',
      type: GroupType.chat,
      topicName: 'topic-$groupId',
      createdAt: now,
      createdBy: adminPeerId,
      myRole: GroupRole.member,
    );
    final groupRepository = _TrackingGroupRepository();
    await groupRepository.saveGroup(group);
    await groupRepository.saveMember(member(selfPeerId, MemberRole.writer));
    await groupRepository.saveMember(member(adminPeerId, MemberRole.admin));
    await groupRepository.saveMember(member(thirdPeerId, MemberRole.writer));
    await groupRepository.saveKey(
      GroupKeyInfo(
        groupId: groupId,
        keyGeneration: 1,
        encryptedKey: 'group-key-1',
        createdAt: now,
      ),
    );

    final identityRepository = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: selfPeerId,
          publicKey: 'pk-$selfPeerId',
          privateKey: 'sk-$selfPeerId',
          mlKemPublicKey: 'mlkem-$selfPeerId',
        ),
      );
    final prepareBridge = FakeBridge();
    final sourceEventId = 'member_removed:$groupId:$selfPeerId:intent-$groupId';
    final preparation = await prepareVoluntaryLeaveNotice(
      bridge: prepareBridge,
      groupRepo: groupRepository,
      group: group,
      identityRepo: identityRepository,
      expectedSelfPeerId: selfPeerId,
      sourceEventId: sourceEventId,
      eventAt: now,
    );
    var prepared = requirePreparedVoluntaryLeaveNotice(preparation);
    if (reversePersistedRecipients) {
      prepared = _withReversedPersistedRecipientAuthority(prepared);
    }
    final durableNotice = prepared.pendingBroadcast;
    final initialIntent = GroupExitIntent(
      groupId: groupId,
      intentId: 'intent-$groupId',
      selfPeerId: selfPeerId,
      selfJoinedAt: now,
      state: GroupExitIntentState.leaveNoticePending,
      pendingBroadcastId: durableNotice.id,
      sourceEventId: sourceEventId,
      eventAt: now,
      revision: 1,
      createdAt: now,
      updatedAt: now,
    );
    final pendingRepository = _PendingRepository(durableNotice);
    final intentRepository = _IntentRepository(
      pendingRepository: pendingRepository,
      initial: initialIntent,
      completionBehavior: completionBehavior,
    );
    final durableRows = await pendingRepository.forGroup(groupId);
    final durableIntent = await intentRepository.forGroup(groupId);
    final durableNoticeWasExact =
        durableIntent != null &&
        sameExactGroupExitIntent(durableIntent, initialIntent) &&
        durableRows.length == 1 &&
        sameExactGroupPendingBroadcast(durableRows.single, durableNotice) &&
        hasExactSignedVoluntaryLeaveNoticeAuthority(
          pendingBroadcast: durableRows.single,
          expectedGroupId: groupId,
          expectedSelfPeerId: selfPeerId,
          expectedSourceEventId: sourceEventId,
          expectedEventAt: now,
        );
    groupRepository.latestKeyLoads = 0;
    groupRepository.keyBehavior = keyBehavior;
    return _PreparedLeaveFixture(
      now: now,
      groupId: groupId,
      groupRepository: groupRepository,
      prepared: prepared,
      initialIntent: initialIntent,
      pendingRepository: pendingRepository,
      intentRepository: intentRepository,
      primarySignCount: prepareBridge.commandLog
          .where((command) => command == 'payload.sign')
          .length,
      durableNoticeWasExact: durableNoticeWasExact,
    );
  }

  final DateTime now;
  final String groupId;
  final _TrackingGroupRepository groupRepository;
  final PreparedVoluntaryLeaveNotice prepared;
  final GroupExitIntent initialIntent;
  final _PendingRepository pendingRepository;
  final _IntentRepository intentRepository;
  final int primarySignCount;
  final bool durableNoticeWasExact;

  GroupPendingBroadcast get durableNotice => prepared.pendingBroadcast;

  Future<bool> retainsExactNoticeAndIntent() async {
    final current = await intentRepository.forGroup(groupId);
    final pending = await pendingRepository.forGroup(groupId);
    return current != null &&
        sameExactGroupExitIntent(current, initialIntent) &&
        pending.length == 1 &&
        sameExactGroupPendingBroadcast(pending.single, durableNotice);
  }

  Future<_RunObservation> run(
    _ScriptedLeaveBridge bridge, {
    _RotationFault rotationFault = _RotationFault.none,
  }) async {
    final attemptedNotices = <GroupPendingBroadcast>[];
    VoluntaryLeaveNoticeAttemptResult? attempt;
    var prepareCalls = 0;
    var rotationCalls = 0;
    var nativeLeaves = 0;
    final runner = GroupExitIntentRunner(
      intentRepository: intentRepository,
      pendingRepository: pendingRepository,
      pendingBroadcastRunner: GroupPendingBroadcastRunner(
        repository: pendingRepository,
        rePush: (_) async => true,
      ),
      groupRepository: groupRepository,
      loadCurrentSelfPeerId: () async => initialIntent.selfPeerId,
      prepareNotice:
          ({required intent, required sourceEventId, required eventAt}) async {
            prepareCalls++;
            throw StateError('durable notice must not be prepared again');
          },
      attemptNotice: ({required intent, required pendingBroadcast}) async {
        attemptedNotices.add(pendingBroadcast);
        attempt = await attemptPreparedVoluntaryLeaveNotice(
          bridge: bridge,
          groupRepo: groupRepository,
          prepared: PreparedVoluntaryLeaveNotice(
            pendingBroadcast: pendingBroadcast,
            timelineMessage: prepared.timelineMessage,
            identity: prepared.identity,
            senderBinding: prepared.senderBinding,
            remainingMembers: prepared.remainingMembers,
          ),
          expectedSelfPeerId: intent.selfPeerId,
        );
        return switch (attempt!.classification) {
          VoluntaryLeaveNoticeAttemptClassification.delivered =>
            GroupExitNoticeAttemptDisposition.delivered,
          VoluntaryLeaveNoticeAttemptClassification.degraded =>
            GroupExitNoticeAttemptDisposition.degraded,
          VoluntaryLeaveNoticeAttemptClassification.retryable =>
            GroupExitNoticeAttemptDisposition.retryable,
        };
      },
      rotateKeys: (_) async {
        rotationCalls++;
        switch (rotationFault) {
          case _RotationFault.none:
            return;
          case _RotationFault.typedDeferred:
            throw const GroupExitRotationDeferred();
          case _RotationFault.genericThrow:
            throw Exception(rotationFault.rawMarker);
        }
      },
      nativeLeave: (_) async => nativeLeaves++,
      now: () => now,
    );

    GroupExitIntentProcessResult? result;
    Object? processError;
    try {
      result = await runner.processGroup(groupId, drainRoleBroadcasts: false);
    } catch (error) {
      processError = error;
    }
    return _RunObservation(
      fixture: this,
      bridge: bridge,
      attemptedNotices: attemptedNotices,
      attempt: attempt,
      prepareCalls: prepareCalls,
      rotationCalls: rotationCalls,
      nativeLeaves: nativeLeaves,
      result: result,
      processError: processError,
    );
  }
}

class _RunObservation {
  const _RunObservation({
    required this.fixture,
    required this.bridge,
    required this.attemptedNotices,
    required this.attempt,
    required this.prepareCalls,
    required this.rotationCalls,
    required this.nativeLeaves,
    required this.result,
    required this.processError,
  });

  final _PreparedLeaveFixture fixture;
  final _ScriptedLeaveBridge bridge;
  final List<GroupPendingBroadcast> attemptedNotices;
  final VoluntaryLeaveNoticeAttemptResult? attempt;
  final int prepareCalls;
  final int rotationCalls;
  final int nativeLeaves;
  final GroupExitIntentProcessResult? result;
  final Object? processError;
}

void _expectCompletedAttempt(
  _RunObservation observation, {
  required VoluntaryLeaveNoticeAttemptClassification classification,
  required VoluntaryLeaveOfflineReplayStatus offlineStatus,
  required GroupExitPersistedOutcome completionOutcome,
  required GroupExitPersistedOutcome finalOutcome,
}) {
  final fixture = observation.fixture;
  expect(fixture.durableNoticeWasExact, isTrue);
  expect(fixture.primarySignCount, 1);
  expect(observation.prepareCalls, 0);
  expect(observation.attemptedNotices, hasLength(1));
  expect(
    sameExactGroupPendingBroadcast(
      observation.attemptedNotices.single,
      fixture.durableNotice,
    ),
    isTrue,
  );
  expect(observation.processError, isNull);
  expect(observation.result?.status, GroupExitIntentProcessStatus.completed);
  expect(observation.result?.cause, isNull);
  expect(observation.attempt?.classification, classification);
  expect(observation.attempt?.offlineReplayStatus, offlineStatus);
  expect(observation.nativeLeaves, 1);
  expect(fixture.intentRepository.completionCodes, <String>[
    completionOutcome.persistedCode,
  ]);
  expect(fixture.intentRepository.cleanupExpectedCodes, <String?>[
    finalOutcome.persistedCode,
  ]);
  final allowlistedCodes = GroupExitPersistedOutcome.values
      .map((outcome) => outcome.persistedCode)
      .toSet();
  expect(
    fixture.intentRepository.persistedDiagnosticValues,
    everyElement(isIn(allowlistedCodes)),
  );
}

void _expectNoRawDiagnostic(_RunObservation observation, String rawMarker) {
  if (rawMarker.isEmpty) return;
  expect(
    observation.fixture.intentRepository.persistedDiagnosticValues.join('|'),
    isNot(contains(rawMarker)),
  );
}

int _commandCount(FakeBridge bridge, String command) =>
    bridge.commandLog.where((candidate) => candidate == command).length;

List<Map<String, dynamic>> _commandPayloads(
  FakeBridge bridge,
  String command,
) => bridge.sentMessages
    .map((message) => jsonDecode(message) as Map<String, dynamic>)
    .where((message) => message['cmd'] == command)
    .map((message) => message['payload'] as Map<String, dynamic>)
    .toList(growable: false);
