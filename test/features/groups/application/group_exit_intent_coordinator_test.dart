import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';

import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

class _IntentRepo implements GroupExitIntentRepository {
  final Map<String, GroupExitIntent> rows = <String, GroupExitIntent>{};
  bool throwOnLoad = false;
  Object? loadError;
  Object? enqueueError;
  bool refuseEnqueueWithoutCurrent = false;
  Completer<void>? enqueueGate;
  List<String>? events;
  int loadCalls = 0;
  int enqueueCalls = 0;
  GroupExitIntentMutationDisposition? cancelDisposition;
  bool removeBeforeCancelResult = false;

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async {
    loadCalls++;
    final error = loadError;
    if (error != null) throw error;
    if (throwOnLoad) throw StateError('intent storage unavailable');
    return rows[groupId];
  }

  @override
  Future<List<GroupExitIntent>> all() async => rows.values.toList();

  @override
  Future<GroupExitIntentMutationResult> enqueue(GroupExitIntent intent) async {
    enqueueCalls++;
    events?.add('intent-enqueue-start');
    final gate = enqueueGate;
    if (gate != null) await gate.future;
    final error = enqueueError;
    if (error != null) throw error;
    if (refuseEnqueueWithoutCurrent) {
      return const GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
      );
    }
    final existing = rows[intent.groupId];
    if (existing != null) {
      return GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
        current: existing,
      );
    }
    rows[intent.groupId] = intent;
    events?.add('intent-enqueue-committed');
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: intent,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> cancelQueued(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    final current = rows[expected.groupId];
    final disposition = cancelDisposition;
    if (disposition != null) {
      if (removeBeforeCancelResult) rows.remove(expected.groupId);
      return GroupExitIntentMutationResult(
        disposition: disposition,
        current: removeBeforeCancelResult ? null : current,
      );
    }
    if (current == null ||
        !sameExactGroupExitIntent(current, expected) ||
        !current.isCancelable) {
      return GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
        current: current,
      );
    }
    rows.remove(expected.groupId);
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> advance({
    required GroupExitIntent expected,
    required GroupExitIntentState nextState,
    required DateTime updatedAt,
    String? lastErrorCode,
  }) => throw UnimplementedError();

  @override
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<GroupExitIntentMutationResult> prepareLeaveNotice({
    required GroupExitIntent expected,
    required timelineMessage,
    required GroupPendingBroadcast pendingBroadcast,
    required DateTime updatedAt,
  }) => throw UnimplementedError();

  @override
  Future<GroupExitIntentMutationResult> retireExact(GroupExitIntent expected) =>
      throw UnimplementedError();

  @override
  Future<int> terminalizeForGroup(String groupId) => throw UnimplementedError();
}

class _PendingRepo implements GroupPendingBroadcastRepository {
  final Map<String, GroupPendingBroadcast> rows =
      <String, GroupPendingBroadcast>{};
  Object? loadError;
  final Map<int, Object> loadErrorsByCall = <int, Object>{};
  int forGroupCalls = 0;
  int removeCalls = 0;

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    rows[broadcast.id] = broadcast;
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async {
    forGroupCalls++;
    final callError = loadErrorsByCall[forGroupCalls];
    if (callError != null) throw callError;
    final error = loadError;
    if (error != null) throw error;
    return rows.values
        .where((broadcast) => broadcast.groupId == groupId)
        .toList(growable: false);
  }

  @override
  Future<List<GroupPendingBroadcast>> all() async => rows.values.toList();

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((broadcast) => broadcast.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    removeCalls++;
    rows.remove(id);
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, broadcast) => broadcast.groupId == groupId);
  }
}

class _VanishingPendingRepo extends _PendingRepo {
  bool vanishAfterFirstLoad = false;

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async {
    final loaded = await super.forGroup(groupId);
    if (vanishAfterFirstLoad && forGroupCalls == 1) {
      rows.clear();
    }
    return loaded;
  }
}

class _Processor implements GroupExitIntentProcessor {
  int calls = 0;
  final List<bool> drainFlags = <bool>[];
  GroupExitIntentProcessStatus status = GroupExitIntentProcessStatus.completed;
  GroupExitIntentProcessResult? result;
  Object? processError;
  Completer<void>? gate;
  List<String>? events;

  @override
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  }) async {
    calls++;
    drainFlags.add(drainRoleBroadcasts);
    events?.add('processor-start');
    final currentGate = gate;
    if (currentGate != null) await currentGate.future;
    final error = processError;
    if (error != null) throw error;
    return result ?? GroupExitIntentProcessResult(status: status);
  }

  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async =>
      <String, GroupExitIntentProcessResult>{};
}

GroupPendingBroadcast _pending(String id, String kind) => GroupPendingBroadcast(
  id: id,
  groupId: 'group-1',
  kind: kind,
  sysText: '{}',
  recipientPeerIds: const <String>['peer-other'],
  eventAt: DateTime.utc(2026, 7, 21, 8),
  sourceMessageId: 'source-$id',
  createdAt: DateTime.utc(2026, 7, 21, 8),
  updatedAt: DateTime.utc(2026, 7, 21, 8),
);

Future<InMemoryGroupRepository> _groupRepo({
  GroupRole myRole = GroupRole.member,
  MemberRole selfRole = MemberRole.writer,
  bool includeOtherAdmin = true,
}) async {
  final repo = InMemoryGroupRepository();
  final joinedAt = DateTime.utc(2026, 7, 20);
  await repo.saveGroup(
    GroupModel(
      id: 'group-1',
      name: 'Group',
      type: GroupType.chat,
      topicName: 'topic-group-1',
      createdAt: joinedAt,
      createdBy: 'peer-other',
      myRole: myRole,
    ),
  );
  await repo.saveMember(
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-self',
      username: 'Self',
      role: selfRole,
      joinedAt: joinedAt,
    ),
  );
  if (includeOtherAdmin) {
    await repo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-other',
        username: 'Other',
        role: MemberRole.admin,
        joinedAt: joinedAt,
      ),
    );
  }
  return repo;
}

FakeIdentityRepository _identityRepo() => FakeIdentityRepository()
  ..seed(
    FakeIdentityRepository.makeIdentity(
      peerId: 'peer-self',
      publicKey: 'pk-self',
      privateKey: 'sk-self',
      mlKemPublicKey: 'mlkem-self',
    ),
  );

class _ThrowingAuthorityGroupRepository extends InMemoryGroupRepository {
  @override
  Future<GroupModel?> getGroup(String id) async {
    throw StateError('group authority unavailable');
  }
}

GroupExitIntent _intent({
  GroupExitIntentState state = GroupExitIntentState.queued,
  String intentId = 'existing-intent',
}) {
  final at = DateTime.utc(2026, 7, 21, 8);
  return GroupExitIntent(
    groupId: 'group-1',
    intentId: intentId,
    selfPeerId: 'peer-self',
    selfJoinedAt: DateTime.utc(2026, 7, 20),
    state: state,
    pendingBroadcastId: 'notice-$intentId',
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  test(
    'PB264-08 unavailable storage or queue authority cannot authorize leave',
    () async {
      final cases =
          <
            ({
              String name,
              Object? intentLoadError,
              Object? pendingLoadError,
              Object? intentWriteError,
              bool identityMissing,
              bool authorityThrows,
              int expectedPendingLoads,
              int expectedEnqueueCalls,
            })
          >[
            (
              name: 'intent load unavailable',
              intentLoadError: StateError('intent load unavailable'),
              pendingLoadError: null,
              intentWriteError: null,
              identityMissing: false,
              authorityThrows: false,
              expectedPendingLoads: 0,
              expectedEnqueueCalls: 0,
            ),
            (
              name: 'identity authority unavailable',
              intentLoadError: null,
              pendingLoadError: null,
              intentWriteError: null,
              identityMissing: true,
              authorityThrows: false,
              expectedPendingLoads: 0,
              expectedEnqueueCalls: 0,
            ),
            (
              name: 'group authority load unavailable',
              intentLoadError: null,
              pendingLoadError: null,
              intentWriteError: null,
              identityMissing: false,
              authorityThrows: true,
              expectedPendingLoads: 0,
              expectedEnqueueCalls: 0,
            ),
            (
              name: 'pending queue classification unavailable',
              intentLoadError: null,
              pendingLoadError: StateError('pending load unavailable'),
              intentWriteError: null,
              identityMissing: false,
              authorityThrows: false,
              expectedPendingLoads: 1,
              expectedEnqueueCalls: 0,
            ),
            (
              name: 'intent write unavailable',
              intentLoadError: null,
              pendingLoadError: null,
              intentWriteError: StateError('intent write unavailable'),
              identityMissing: false,
              authorityThrows: false,
              expectedPendingLoads: 2,
              expectedEnqueueCalls: 1,
            ),
          ];

      for (final testCase in cases) {
        final intentRepo = _IntentRepo()
          ..loadError = testCase.intentLoadError
          ..enqueueError = testCase.intentWriteError;
        final pendingRepo = _PendingRepo()
          ..loadError = testCase.pendingLoadError;
        final processor = _Processor();
        final identityRepo = _identityRepo();
        if (testCase.identityMissing) identityRepo.seed(null);
        var rePushes = 0;
        final groupRepo = testCase.authorityThrows
            ? _ThrowingAuthorityGroupRepository()
            : await _groupRepo();
        final coordinator = GroupExitIntentCoordinator(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async {
              rePushes++;
              return true;
            },
          ),
          processor: processor,
          groupRepository: groupRepo,
          identityRepository: identityRepo,
          newId: () => 'fixed-id',
          now: () => DateTime.utc(2026, 7, 21, 8),
        );

        final result = await coordinator.requestLeave('group-1');

        expect(
          result.status,
          GroupExitIntentRequestStatus.unavailable,
          reason: testCase.name,
        );
        expect(result.diagnosticFacts, const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.authorityUnavailable(),
        ], reason: testCase.name);
        expect(intentRepo.rows, isEmpty, reason: testCase.name);
        expect(
          intentRepo.enqueueCalls,
          testCase.expectedEnqueueCalls,
          reason: testCase.name,
        );
        expect(
          pendingRepo.forGroupCalls,
          testCase.expectedPendingLoads,
          reason: testCase.name,
        );
        expect(rePushes, 0, reason: testCase.name);
        expect(processor.calls, 0, reason: testCase.name);
      }

      final refusingIntents = _IntentRepo()..refuseEnqueueWithoutCurrent = true;
      final refusingPending = _PendingRepo();
      final refusingProcessor = _Processor();
      final refusingCoordinator = GroupExitIntentCoordinator(
        intentRepository: refusingIntents,
        pendingRepository: refusingPending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: refusingPending,
          rePush: (_) async => true,
        ),
        processor: refusingProcessor,
        groupRepository: await _groupRepo(),
        identityRepository: _identityRepo(),
        newId: () => 'refused-id',
        now: () => DateTime.utc(2026, 7, 21, 8),
      );
      final refused = await refusingCoordinator.requestLeave('group-1');
      expect(refused.status, GroupExitIntentRequestStatus.failed);
      expect(refused.intent, isNull);
      expect(refused.diagnosticFacts, const <GroupExitProcessDiagnosticFact>[
        GroupExitProcessDiagnosticFact.authorityUnavailable(),
      ]);
      expect(refusingProcessor.calls, 0);

      // The process-wide facade is also required authority: an unwired action
      // or repository lookup must be typed unavailable, never a fabricated
      // empty/ready value that could fall through to a native side effect.
      setGroupExitIntentActionSinks();
      setGroupExitIntentAccessSinks();
      setGroupExitIntentRuntimeSinks();
      addTearDown(() {
        setGroupExitIntentActionSinks();
        setGroupExitIntentAccessSinks();
        setGroupExitIntentRuntimeSinks();
      });
      final missingRequest = await requestGroupExitIntentLeave('group-1');
      expect(
        missingRequest.diagnosticFacts,
        const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.authorityUnavailable(),
        ],
      );
      expect(missingRequest.status, GroupExitIntentRequestStatus.unavailable);
      expect(
        (await queueGroupExitIntentLeaveWhenSyncCompletes('group-1')).status,
        GroupExitIntentRequestStatus.unavailable,
      );
      expect(
        (await retryGroupExitIntentLeave('group-1')).status,
        GroupExitIntentRequestStatus.unavailable,
      );
      expect(
        (await cancelQueuedGroupExitIntent('group-1')).status,
        GroupExitIntentCancelStatus.unavailable,
      );
      expect(
        (await loadGroupExitIntent('group-1')).status,
        GroupExitIntentLookupStatus.unavailable,
      );
      expect(
        (await loadAllGroupExitIntents()).status,
        GroupExitIntentLookupStatus.unavailable,
      );
      expect(await canRejoinForExitIntent('group-1'), isFalse);
      await expectLater(
        processExistingGroupExitIntent('group-1'),
        throwsStateError,
      );
    },
  );

  test(
    'PB264-14 pending-role Leave retries once before offering or starting durable exit',
    () async {
      Future<
        ({
          GroupExitIntentCoordinator coordinator,
          _IntentRepo intents,
          _PendingRepo pending,
          _Processor processor,
          int Function() pushes,
        })
      >
      fixture({
        required bool rolePushSucceeds,
        bool drainLoadThrows = false,
        bool soleAdmin = false,
      }) async {
        final intents = _IntentRepo();
        final pending = _PendingRepo();
        if (drainLoadThrows) {
          // Call one is the coordinator's snapshot. Call two is the single
          // keyed immediate drain's authoritative reload.
          pending.loadErrorsByCall[2] = StateError('drain load failed');
        }
        final processor = _Processor();
        var pushes = 0;
        final coordinator = GroupExitIntentCoordinator(
          intentRepository: intents,
          pendingRepository: pending,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pending,
            rePush: (_) async {
              pushes++;
              return rolePushSucceeds;
            },
          ),
          processor: processor,
          groupRepository: await _groupRepo(
            myRole: soleAdmin ? GroupRole.admin : GroupRole.member,
            selfRole: soleAdmin ? MemberRole.admin : MemberRole.writer,
            includeOtherAdmin: !soleAdmin,
          ),
          identityRepository: _identityRepo(),
          newId: () => 'fixed-id',
          now: () => DateTime.utc(2026, 7, 21, 8),
        );
        return (
          coordinator: coordinator,
          intents: intents,
          pending: pending,
          processor: processor,
          pushes: () => pushes,
        );
      }

      final clears = await fixture(rolePushSucceeds: true);
      await clears.pending.enqueue(
        _pending('role-clears', groupPendingBroadcastKindMemberRoleUpdated),
      );
      final cleared = await clears.coordinator.requestLeave('group-1');
      expect(cleared.status, GroupExitIntentRequestStatus.started);
      expect(clears.pushes(), 1);
      expect(
        clears.pending.forGroupCalls,
        5,
        reason:
            'snapshot + drain + exact-remove CAS + reload + final claim read',
      );
      expect(clears.pending.removeCalls, 1);
      expect(clears.intents.rows, hasLength(1));
      expect(clears.processor.calls, 1);
      expect(clears.processor.drainFlags, [false]);

      final remains = await fixture(rolePushSucceeds: false);
      await remains.pending.enqueue(
        _pending('role-remains', groupPendingBroadcastKindMemberRoleUpdated),
      );
      final pending = await remains.coordinator.requestLeave('group-1');
      expect(pending.status, GroupExitIntentRequestStatus.pendingRoleSync);
      expect(pending.diagnosticFacts, isEmpty);
      expect(remains.pushes(), 1);
      expect(remains.pending.forGroupCalls, 3);
      expect(remains.pending.removeCalls, 0);
      expect(remains.intents.rows, isEmpty);
      expect(remains.processor.calls, 0);

      final queued = await remains.coordinator.queueLeaveWhenSyncCompletes(
        'group-1',
      );
      expect(queued.status, GroupExitIntentRequestStatus.queued);
      expect(queued.diagnosticFacts, isEmpty);
      expect(remains.intents.rows, hasLength(1));
      expect(remains.processor.calls, 1);
      expect(remains.processor.drainFlags, [false]);
      expect(
        remains.pending.forGroupCalls,
        3,
        reason: 'the queue choice persists without paying a second drain',
      );

      final drainThrows = await fixture(
        rolePushSucceeds: true,
        drainLoadThrows: true,
      );
      await drainThrows.pending.enqueue(
        _pending(
          'role-drain-throws',
          groupPendingBroadcastKindMemberRoleUpdated,
        ),
      );
      final threw = await drainThrows.coordinator.requestLeave('group-1');
      expect(threw.status, GroupExitIntentRequestStatus.pendingRoleSync);
      expect(threw.cause, isA<StateError>());
      expect(threw.diagnosticFacts, const <GroupExitProcessDiagnosticFact>[
        GroupExitProcessDiagnosticFact.roleSyncFailed(),
      ]);
      expect(drainThrows.pending.forGroupCalls, 2);
      expect(drainThrows.pushes(), 0);
      expect(drainThrows.intents.rows, isEmpty);
      expect(drainThrows.processor.calls, 0);

      final metadata = await fixture(rolePushSucceeds: true);
      await metadata.pending.enqueue(
        _pending('metadata', 'group_metadata_updated'),
      );
      final noRole = await metadata.coordinator.requestLeave('group-1');
      expect(noRole.status, GroupExitIntentRequestStatus.started);
      expect(metadata.pushes(), 0, reason: 'metadata is not a role delay');
      expect(metadata.pending.forGroupCalls, 2);
      expect(metadata.intents.rows, hasLength(1));
      expect(metadata.processor.calls, 1);

      final ordinary = await fixture(rolePushSucceeds: true);
      final noPending = await ordinary.coordinator.requestLeave('group-1');
      expect(noPending.status, GroupExitIntentRequestStatus.started);
      expect(ordinary.pushes(), 0);
      expect(ordinary.pending.forGroupCalls, 2);
      expect(ordinary.intents.rows, hasLength(1));
      expect(ordinary.processor.calls, 1);

      final soleAdmin = await fixture(rolePushSucceeds: true, soleAdmin: true);
      await soleAdmin.pending.enqueue(
        _pending('role-sole-admin', groupPendingBroadcastKindMemberRoleUpdated),
      );
      final blocked = await soleAdmin.coordinator.requestLeave('group-1');
      expect(blocked.status, GroupExitIntentRequestStatus.blockedLastAdmin);
      expect(soleAdmin.pushes(), 1);
      expect(soleAdmin.pending.forGroupCalls, 4);
      expect(soleAdmin.intents.rows, isEmpty);
      expect(soleAdmin.processor.calls, 0);
    },
  );

  test(
    'PB264-14 exact self-admin row blocks leave when group role projection is stale',
    () async {
      final intents = _IntentRepo();
      final pending = _PendingRepo();
      final processor = _Processor();
      final coordinator = GroupExitIntentCoordinator(
        intentRepository: intents,
        pendingRepository: pending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pending,
          rePush: (_) async => true,
        ),
        processor: processor,
        groupRepository: await _groupRepo(
          myRole: GroupRole.member,
          selfRole: MemberRole.admin,
          includeOtherAdmin: false,
        ),
        identityRepository: _identityRepo(),
        newId: () => 'must-not-enqueue',
        now: () => DateTime.utc(2026, 7, 21, 8),
      );

      final result = await coordinator.requestLeave('group-1');

      expect(result.status, GroupExitIntentRequestStatus.blockedLastAdmin);
      expect(intents.enqueueCalls, 0);
      expect(intents.rows, isEmpty);
      expect(processor.calls, 0);
    },
  );

  test(
    'PB264-14 sole admin queues only behind an exact role row that survives the decisive claim',
    () async {
      Future<GroupExitIntentCoordinator> coordinatorFor({
        required _IntentRepo intents,
        required _PendingRepo pending,
        required _Processor processor,
      }) async => GroupExitIntentCoordinator(
        intentRepository: intents,
        pendingRepository: pending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pending,
          rePush: (_) async => true,
        ),
        processor: processor,
        groupRepository: await _groupRepo(
          myRole: GroupRole.admin,
          selfRole: MemberRole.admin,
          includeOtherAdmin: false,
        ),
        identityRepository: _identityRepo(),
        newId: () => 'fixed-id',
        now: () => DateTime.utc(2026, 7, 21, 8),
      );

      final stableIntents = _IntentRepo();
      final stablePending = _PendingRepo();
      final stableProcessor = _Processor();
      await stablePending.enqueue(
        _pending('stable-role', groupPendingBroadcastKindMemberRoleUpdated),
      );
      final stable = await (await coordinatorFor(
        intents: stableIntents,
        pending: stablePending,
        processor: stableProcessor,
      )).queueLeaveWhenSyncCompletes('group-1');
      expect(stable.status, GroupExitIntentRequestStatus.queued);
      expect(stable.intent, same(stableIntents.rows['group-1']));
      expect(stableIntents.enqueueCalls, 1);
      expect(
        stablePending.forGroupCalls,
        2,
        reason: 'the role row is reloaded inside the membership phase',
      );

      final metadataIntents = _IntentRepo();
      final metadataPending = _PendingRepo();
      await metadataPending.enqueue(_pending('metadata', 'metadata_updated'));
      final metadata = await (await coordinatorFor(
        intents: metadataIntents,
        pending: metadataPending,
        processor: _Processor(),
      )).queueLeaveWhenSyncCompletes('group-1');
      expect(metadata.status, GroupExitIntentRequestStatus.blockedLastAdmin);
      expect(metadataIntents.enqueueCalls, 0);
      expect(metadataPending.forGroupCalls, 1);

      final vanishedIntents = _IntentRepo();
      final vanishedPending = _VanishingPendingRepo()
        ..vanishAfterFirstLoad = true;
      await vanishedPending.enqueue(
        _pending('vanishing-role', groupPendingBroadcastKindMemberRoleUpdated),
      );
      final vanished = await (await coordinatorFor(
        intents: vanishedIntents,
        pending: vanishedPending,
        processor: _Processor(),
      )).queueLeaveWhenSyncCompletes('group-1');
      expect(vanished.status, GroupExitIntentRequestStatus.blockedLastAdmin);
      expect(vanishedIntents.enqueueCalls, 0);
      expect(vanishedPending.forGroupCalls, 2);
    },
  );

  test(
    'PB264-14 queue choice commits durably before return and does not await processing',
    () async {
      final events = <String>[];
      final enqueueGate = Completer<void>();
      final processGate = Completer<void>();
      final intents = _IntentRepo()
        ..events = events
        ..enqueueGate = enqueueGate;
      final pending = _PendingRepo();
      final processor = _Processor()
        ..events = events
        ..gate = processGate;
      final coordinator = GroupExitIntentCoordinator(
        intentRepository: intents,
        pendingRepository: pending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pending,
          rePush: (_) async => true,
        ),
        processor: processor,
        groupRepository: await _groupRepo(),
        identityRepository: _identityRepo(),
        newId: () => 'fixed-id',
        now: () => DateTime.utc(2026, 7, 21, 8),
      );

      var returned = false;
      final request = coordinator.queueLeaveWhenSyncCompletes('group-1').then((
        result,
      ) {
        returned = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(intents.enqueueCalls, 1);
      expect(intents.rows, isEmpty);
      expect(processor.calls, 0);
      expect(returned, isFalse);
      expect(events, ['intent-enqueue-start']);

      enqueueGate.complete();
      final result = await request;
      expect(result.status, GroupExitIntentRequestStatus.queued);
      expect(returned, isTrue);
      expect(intents.rows, hasLength(1));
      expect(processor.calls, 1);
      expect(processor.drainFlags, [false]);
      expect(events, [
        'intent-enqueue-start',
        'intent-enqueue-committed',
        'processor-start',
      ]);

      processGate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'PB264-14 existing intent result mapping never starts a second exit',
    () async {
      final expectedByStatus =
          <GroupExitIntentProcessStatus, GroupExitIntentRequestStatus>{
            GroupExitIntentProcessStatus.noIntent:
                GroupExitIntentRequestStatus.noOp,
            GroupExitIntentProcessStatus.waitingForRoleSync:
                GroupExitIntentRequestStatus.queued,
            GroupExitIntentProcessStatus.blockedLastAdmin:
                GroupExitIntentRequestStatus.blockedLastAdmin,
            GroupExitIntentProcessStatus.waitingForNoticeRetry:
                GroupExitIntentRequestStatus.queued,
            GroupExitIntentProcessStatus.waitingForNativeRetry:
                GroupExitIntentRequestStatus.queued,
            GroupExitIntentProcessStatus.completed:
                GroupExitIntentRequestStatus.noOp,
            GroupExitIntentProcessStatus.retiredStaleMembership:
                GroupExitIntentRequestStatus.noOp,
            GroupExitIntentProcessStatus.failed:
                GroupExitIntentRequestStatus.failed,
          };

      for (final entry in expectedByStatus.entries) {
        final existing = _intent(intentId: 'existing-${entry.key.name}');
        final intents = _IntentRepo()..rows[existing.groupId] = existing;
        final pending = _PendingRepo();
        final processor = _Processor()
          ..result = GroupExitIntentProcessResult(
            status: entry.key,
            cause: StateError('process-${entry.key.name}'),
          );
        var pushes = 0;
        final coordinator = GroupExitIntentCoordinator(
          intentRepository: intents,
          pendingRepository: pending,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pending,
            rePush: (_) async {
              pushes++;
              return true;
            },
          ),
          processor: processor,
          groupRepository: await _groupRepo(),
          identityRepository: _identityRepo(),
          newId: () => 'must-not-mint',
          now: () => DateTime.utc(2026, 7, 21, 8),
        );

        final result = await coordinator.requestLeave(existing.groupId);

        expect(result.status, entry.value, reason: entry.key.name);
        final terminal = entry.value == GroupExitIntentRequestStatus.noOp;
        expect(
          result.intent,
          terminal ? isNull : same(existing),
          reason: entry.key.name,
        );
        expect(intents.enqueueCalls, 0, reason: entry.key.name);
        expect(pending.forGroupCalls, 0, reason: entry.key.name);
        expect(pushes, 0, reason: entry.key.name);
        expect(processor.calls, 1, reason: entry.key.name);
        expect(processor.drainFlags, [true], reason: entry.key.name);
      }
    },
  );

  test(
    'PB264-14 requestLeave preserves its known durable intent when processing throws',
    () async {
      for (final startsWithIntent in <bool>[true, false]) {
        final error = StateError(
          startsWithIntent ? 'existing process failed' : 'new process failed',
        );
        final intents = _IntentRepo();
        if (startsWithIntent) {
          final existing = _intent(intentId: 'already-durable');
          intents.rows[existing.groupId] = existing;
        }
        final pending = _PendingRepo();
        final processor = _Processor()..processError = error;
        final coordinator = GroupExitIntentCoordinator(
          intentRepository: intents,
          pendingRepository: pending,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pending,
            rePush: (_) async => true,
          ),
          processor: processor,
          groupRepository: await _groupRepo(),
          identityRepository: _identityRepo(),
          newId: () => 'fixed-id',
          now: () => DateTime.utc(2026, 7, 21, 8),
        );

        final result = await coordinator.requestLeave('group-1');
        final durable = intents.rows['group-1'];

        expect(
          result.status,
          GroupExitIntentRequestStatus.failed,
          reason: 'startsWithIntent=$startsWithIntent',
        );
        expect(result.intent, same(durable));
        expect(result.cause, same(error));
        expect(intents.enqueueCalls, startsWithIntent ? 0 : 1);
        expect(processor.calls, 1);
        expect(processor.drainFlags, [startsWithIntent]);
      }
    },
  );

  test(
    'PB264-14 retry preserves its known durable intent when processing throws',
    () async {
      final error = StateError('retry process failed');
      final existing = _intent(intentId: 'retry-durable');
      final intents = _IntentRepo()..rows[existing.groupId] = existing;
      final pending = _PendingRepo();
      final processor = _Processor()..processError = error;
      final coordinator = GroupExitIntentCoordinator(
        intentRepository: intents,
        pendingRepository: pending,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pending,
          rePush: (_) async => true,
        ),
        processor: processor,
        groupRepository: await _groupRepo(),
        identityRepository: _identityRepo(),
        newId: () => 'must-not-mint',
        now: () => DateTime.utc(2026, 7, 21, 8),
      );

      final result = await coordinator.retry('group-1');

      expect(result.status, GroupExitIntentRequestStatus.failed);
      expect(result.intent, same(existing));
      expect(result.cause, same(error));
      expect(intents.enqueueCalls, 0);
      expect(processor.calls, 1);
    },
  );

  test(
    'PB264-16 cancel losing to worker completion or stale-membership retirement reports too late',
    () async {
      for (final disposition in <GroupExitIntentMutationDisposition>[
        GroupExitIntentMutationDisposition.absent,
        GroupExitIntentMutationDisposition.retiredStaleMembership,
      ]) {
        final existing = _intent(intentId: 'cancel-${disposition.name}');
        final intents = _IntentRepo()
          ..rows[existing.groupId] = existing
          ..cancelDisposition = disposition
          ..removeBeforeCancelResult = true;
        final pending = _PendingRepo();
        final coordinator = GroupExitIntentCoordinator(
          intentRepository: intents,
          pendingRepository: pending,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pending,
            rePush: (_) async => true,
          ),
          processor: _Processor(),
          groupRepository: await _groupRepo(),
          identityRepository: _identityRepo(),
          newId: () => 'must-not-mint',
          now: () => DateTime.utc(2026, 7, 21, 8),
        );

        final result = await coordinator.cancelQueued(existing.groupId);

        expect(
          result.status,
          GroupExitIntentCancelStatus.tooLate,
          reason: disposition.name,
        );
        expect(result.current, isNull, reason: disposition.name);
        expect(intents.rows, isEmpty, reason: disposition.name);
      }
    },
  );

  test(
    'PB264-11 runtime rejoin authority binds early exit work to its account',
    () async {
      var identityLoads = 0;
      expect(
        await authorizeGroupRejoinForExitIntent(
          groupId: 'group-absent',
          loadIntent: (_) async => null,
          loadCurrentSelfPeerId: () async {
            identityLoads++;
            return 'peer-self';
          },
        ),
        isTrue,
      );
      expect(identityLoads, 0, reason: 'no intent needs no account authority');

      for (final state in <GroupExitIntentState>[
        GroupExitIntentState.queued,
        GroupExitIntentState.leaveNoticePending,
        GroupExitIntentState.leaveNoticeAttempted,
      ]) {
        expect(
          await authorizeGroupRejoinForExitIntent(
            groupId: 'group-1',
            loadIntent: (_) async => _intent(state: state),
            loadCurrentSelfPeerId: () async => 'peer-self',
          ),
          isTrue,
          reason: '${state.name} may rejoin only for the owning account',
        );
      }

      for (final state in <GroupExitIntentState>[
        GroupExitIntentState.rotationClaimed,
        GroupExitIntentState.nativeLeavePending,
        GroupExitIntentState.cleanupPending,
      ]) {
        expect(
          await authorizeGroupRejoinForExitIntent(
            groupId: 'group-1',
            loadIntent: (_) async => _intent(state: state),
            loadCurrentSelfPeerId: () async => 'peer-self',
          ),
          isFalse,
          reason: '${state.name} never re-arms native membership',
        );
      }

      expect(
        await authorizeGroupRejoinForExitIntent(
          groupId: 'group-1',
          loadIntent: (_) async => _intent(),
          loadCurrentSelfPeerId: () async => 'peer-other',
        ),
        isFalse,
        reason: 'a switched account cannot inherit queued rejoin authority',
      );
      expect(
        await authorizeGroupRejoinForExitIntent(
          groupId: 'group-1',
          loadIntent: (_) async => _intent(),
          loadCurrentSelfPeerId: () async => null,
        ),
        isFalse,
      );
      expect(
        await authorizeGroupRejoinForExitIntent(
          groupId: 'group-1',
          loadIntent: (_) async => throw StateError('intent unavailable'),
          loadCurrentSelfPeerId: () async => 'peer-self',
        ),
        isFalse,
      );
      expect(
        await authorizeGroupRejoinForExitIntent(
          groupId: 'group-1',
          loadIntent: (_) async => _intent(),
          loadCurrentSelfPeerId: () async =>
              throw StateError('identity unavailable'),
        ),
        isFalse,
      );
    },
  );

  test(
    'PB264-16 presentation sink is typed unavailable until concrete authority is wired',
    () async {
      setGroupExitIntentActionSinks();
      setGroupExitIntentAccessSinks();
      setGroupExitIntentRuntimeSinks();
      addTearDown(() {
        setGroupExitIntentActionSinks();
        setGroupExitIntentAccessSinks();
        setGroupExitIntentRuntimeSinks();
      });

      expect(
        (await requestGroupExitIntentLeave('group-1')).status,
        GroupExitIntentRequestStatus.unavailable,
      );
      expect(
        (await queueGroupExitIntentLeaveWhenSyncCompletes('group-1')).status,
        GroupExitIntentRequestStatus.unavailable,
      );
      expect(
        (await retryGroupExitIntentLeave('group-1')).status,
        GroupExitIntentRequestStatus.unavailable,
      );
      expect(
        (await cancelQueuedGroupExitIntent('group-1')).status,
        GroupExitIntentCancelStatus.unavailable,
      );
      expect(
        (await loadGroupExitIntent('group-1')).status,
        GroupExitIntentLookupStatus.unavailable,
      );
      expect(
        (await loadAllGroupExitIntents()).status,
        GroupExitIntentLookupStatus.unavailable,
      );
      expect(await canRejoinForExitIntent('group-1'), isFalse);
      await expectLater(
        processExistingGroupExitIntent('group-1'),
        throwsStateError,
      );

      final at = DateTime.utc(2026, 7, 21, 10);
      final intent = GroupExitIntent(
        groupId: 'group-1',
        intentId: 'intent-1',
        selfPeerId: 'self',
        selfJoinedAt: at,
        state: GroupExitIntentState.queued,
        pendingBroadcastId: 'notice-1',
        createdAt: at,
        updatedAt: at,
      );
      final actionCalls = <String>[];
      setGroupExitIntentActionSinks(
        requestLeave: (groupId) async {
          actionCalls.add('request:$groupId');
          return GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.queued,
            intent: intent,
          );
        },
        queueLeaveWhenSyncCompletes: (groupId) async {
          actionCalls.add('queue:$groupId');
          return GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.queued,
            intent: intent,
          );
        },
        retry: (groupId) async {
          actionCalls.add('retry:$groupId');
          return GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.queued,
            intent: intent,
          );
        },
        cancelQueued: (groupId) async {
          actionCalls.add('cancel:$groupId');
          return const GroupExitIntentCancelResult(
            status: GroupExitIntentCancelStatus.cancelled,
          );
        },
      );
      setGroupExitIntentAccessSinks(
        forGroup: (groupId) async => groupId == intent.groupId ? intent : null,
        all: () async => [intent],
      );
      await expectLater(
        processExistingGroupExitIntent('group-1'),
        throwsStateError,
      );
      final processed = <String>[];
      setGroupExitIntentRuntimeSinks(
        canRejoin: (groupId) async => groupId != intent.groupId,
        processExisting: (groupId) async => processed.add(groupId),
      );

      expect(
        (await requestGroupExitIntentLeave('group-1')).status,
        GroupExitIntentRequestStatus.queued,
      );
      expect(
        (await queueGroupExitIntentLeaveWhenSyncCompletes('group-1')).status,
        GroupExitIntentRequestStatus.queued,
      );
      expect(
        (await retryGroupExitIntentLeave('group-1')).status,
        GroupExitIntentRequestStatus.queued,
      );
      expect(
        (await cancelQueuedGroupExitIntent('group-1')).status,
        GroupExitIntentCancelStatus.cancelled,
      );
      final loaded = await loadGroupExitIntent('group-1');
      expect(loaded.status, GroupExitIntentLookupStatus.available);
      expect(loaded.intent, same(intent));
      final all = await loadAllGroupExitIntents();
      expect(all.status, GroupExitIntentLookupStatus.available);
      expect(all.intents, [same(intent)]);
      expect(await canRejoinForExitIntent('group-1'), isFalse);
      expect(await canRejoinForExitIntent('group-2'), isTrue);
      await processExistingGroupExitIntent('group-2');
      expect(processed, isEmpty, reason: 'an absent intent is never created');
      await processExistingGroupExitIntent('group-1');
      expect(processed, ['group-1']);
      expect(actionCalls, [
        'request:group-1',
        'queue:group-1',
        'retry:group-1',
        'cancel:group-1',
      ]);
    },
  );
}
