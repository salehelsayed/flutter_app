import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../shared/fakes/in_memory_group_repository.dart';

class _PendingRepo implements GroupPendingBroadcastRepository {
  final Map<String, GroupPendingBroadcast> rows =
      <String, GroupPendingBroadcast>{};

  @override
  Future<void> enqueue(GroupPendingBroadcast broadcast) async {
    rows[broadcast.id] = broadcast;
  }

  @override
  Future<List<GroupPendingBroadcast>> forGroup(String groupId) async => rows
      .values
      .where((broadcast) => broadcast.groupId == groupId)
      .toList(growable: false);

  @override
  Future<List<GroupPendingBroadcast>> all() async => rows.values.toList();

  @override
  Future<int> countForGroup(String groupId) async =>
      rows.values.where((broadcast) => broadcast.groupId == groupId).length;

  @override
  Future<void> remove(String id) async {
    rows.remove(id);
  }

  @override
  Future<void> removeForGroup(String groupId) async {
    rows.removeWhere((_, broadcast) => broadcast.groupId == groupId);
  }
}

class _ExitCleanupProbeGroupRepository extends InMemoryGroupRepository {
  final List<String> events = <String>[];
  bool failNextExternalCleanup = false;

  @override
  Future<T> cleanupExactVoluntaryExit<T>({
    required String groupId,
    required String selfPeerId,
    required DateTime selfJoinedAt,
    required Future<T> Function() finalizeSql,
  }) async {
    events.add('external');
    if (failNextExternalCleanup) {
      failNextExternalCleanup = false;
      throw StateError('injected external cleanup failure');
    }
    return super.cleanupExactVoluntaryExit<T>(
      groupId: groupId,
      selfPeerId: selfPeerId,
      selfJoinedAt: selfJoinedAt,
      finalizeSql: () async {
        events.add('sql');
        return finalizeSql();
      },
    );
  }
}

class _SqliteExitCleanupGroupRepository extends InMemoryGroupRepository {
  _SqliteExitCleanupGroupRepository(this.loadDb);

  final Database Function() loadDb;

  @override
  Future<GroupModel?> getGroup(String id) async {
    final rows = await loadDb().query(
      'groups',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : GroupModel.fromMap(rows.single);
  }

  @override
  Future<GroupMember?> getMember(String groupId, String peerId) async {
    final rows = await loadDb().query(
      'group_members',
      where: 'group_id = ? AND peer_id = ?',
      whereArgs: <Object?>[groupId, peerId],
      limit: 1,
    );
    return rows.isEmpty ? null : GroupMember.fromMap(rows.single);
  }

  @override
  Future<T> cleanupExactVoluntaryExit<T>({
    required String groupId,
    required String selfPeerId,
    required DateTime selfJoinedAt,
    required Future<T> Function() finalizeSql,
  }) async {
    final group = await getGroup(groupId);
    final self = await getMember(groupId, selfPeerId);
    if (group == null ||
        group.selfRemovedAt != null ||
        group.isDissolved ||
        self == null ||
        !self.joinedAt.toUtc().isAtSameMomentAs(selfJoinedAt.toUtc())) {
      throw StateError('Exact SQLite cleanup authority is unavailable.');
    }
    return finalizeSql();
  }
}

class _IntentRepo implements GroupExitIntentRepository {
  _IntentRepo(this.pendingRepo);

  final _PendingRepo pendingRepo;
  final Map<String, GroupExitIntent> rows = <String, GroupExitIntent>{};
  final List<GroupPendingBroadcast> preparedNotices = <GroupPendingBroadcast>[];
  final List<String> completionCodes = <String>[];

  void seed(GroupExitIntent intent) => rows[intent.groupId] = intent;

  GroupExitIntentMutationResult _conflict(GroupExitIntent? current) =>
      GroupExitIntentMutationResult(
        disposition: GroupExitIntentMutationDisposition.refusedConflict,
        current: current,
      );

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async => rows[groupId];

  @override
  Future<List<GroupExitIntent>> all() async => rows.values.toList();

  @override
  Future<GroupExitIntentMutationResult> enqueue(GroupExitIntent intent) async {
    if (rows.containsKey(intent.groupId)) {
      return _conflict(rows[intent.groupId]);
    }
    rows[intent.groupId] = intent;
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
    if (current == null ||
        !sameExactGroupExitIntent(current, expected) ||
        !current.isCancelable) {
      return _conflict(current);
    }
    rows.remove(expected.groupId);
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> prepareLeaveNotice({
    required GroupExitIntent expected,
    required timelineMessage,
    required GroupPendingBroadcast pendingBroadcast,
    required DateTime updatedAt,
  }) async {
    final current = rows[expected.groupId];
    if (current == null || !sameExactGroupExitIntent(current, expected)) {
      return _conflict(current);
    }
    await pendingRepo.enqueue(pendingBroadcast);
    preparedNotices.add(pendingBroadcast);
    final next = current.copyWith(
      state: GroupExitIntentState.leaveNoticePending,
      sourceEventId: pendingBroadcast.sourceMessageId,
      eventAt: pendingBroadcast.eventAt,
      revision: current.revision + 1,
      updatedAt: updatedAt,
      lastErrorCode: null,
    );
    rows[current.groupId] = next;
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: next,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  }) async {
    final current = rows[expected.groupId];
    final queued = pendingRepo.rows[pendingBroadcast.id];
    if (current == null ||
        !sameExactGroupExitIntent(current, expected) ||
        queued == null ||
        !sameExactGroupPendingBroadcast(queued, pendingBroadcast)) {
      return _conflict(current);
    }
    await pendingRepo.remove(pendingBroadcast.id);
    completionCodes.add(completionCode);
    final next = current.copyWith(
      state: GroupExitIntentState.leaveNoticeAttempted,
      revision: current.revision + 1,
      updatedAt: updatedAt,
      lastErrorCode: completionCode,
    );
    rows[current.groupId] = next;
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: next,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> advance({
    required GroupExitIntent expected,
    required GroupExitIntentState nextState,
    required DateTime updatedAt,
    String? lastErrorCode,
  }) async {
    final current = rows[expected.groupId];
    if (current == null || !sameExactGroupExitIntent(current, expected)) {
      return _conflict(current);
    }
    final next = current.copyWith(
      state: nextState,
      revision: current.revision + 1,
      updatedAt: updatedAt,
      lastErrorCode: lastErrorCode,
    );
    rows[current.groupId] = next;
    return GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
      current: next,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    final current = rows[expected.groupId];
    if (current == null || !sameExactGroupExitIntent(current, expected)) {
      return _conflict(current);
    }
    rows.remove(expected.groupId);
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<GroupExitIntentMutationResult> retireExact(
    GroupExitIntent expected,
  ) async {
    final current = rows[expected.groupId];
    if (current == null || !sameExactGroupExitIntent(current, expected)) {
      return _conflict(current);
    }
    rows.remove(expected.groupId);
    await pendingRepo.remove(expected.pendingBroadcastId);
    return const GroupExitIntentMutationResult(
      disposition: GroupExitIntentMutationDisposition.committed,
    );
  }

  @override
  Future<int> terminalizeForGroup(String groupId) async {
    final current = rows.remove(groupId);
    if (current == null) return 0;
    await pendingRepo.remove(current.pendingBroadcastId);
    return 1;
  }
}

class _TriggerProbeIntentRepo extends _IntentRepo {
  _TriggerProbeIntentRepo(
    super.pendingRepo, {
    required this.blockedGroupId,
    required this.unrelatedGroupId,
  });

  final String blockedGroupId;
  final String unrelatedGroupId;
  final Completer<void> firstBlockedLoadEntered = Completer<void>();
  final Completer<void> releaseBlockedLoads = Completer<void>();
  final Completer<void> unrelatedCleanupCompleted = Completer<void>();
  final Set<String> failNextLoadFor = <String>{};

  int blockedLoadStarts = 0;
  int _activeBlockedLoads = 0;
  int maxConcurrentBlockedLoads = 0;

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async {
    if (failNextLoadFor.remove(groupId)) {
      throw StateError('forced transient load failure for $groupId');
    }
    if (groupId != blockedGroupId || releaseBlockedLoads.isCompleted) {
      return super.forGroup(groupId);
    }

    blockedLoadStarts++;
    _activeBlockedLoads++;
    if (_activeBlockedLoads > maxConcurrentBlockedLoads) {
      maxConcurrentBlockedLoads = _activeBlockedLoads;
    }
    if (!firstBlockedLoadEntered.isCompleted) {
      firstBlockedLoadEntered.complete();
    }
    try {
      await releaseBlockedLoads.future;
      return super.forGroup(groupId);
    } finally {
      _activeBlockedLoads--;
    }
  }

  @override
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    final result = await super.cleanupOrRetire(expected, updatedAt: updatedAt);
    _completeUnrelatedCleanup(expected.groupId);
    return result;
  }

  @override
  Future<GroupExitIntentMutationResult> retireExact(
    GroupExitIntent expected,
  ) async {
    final result = await super.retireExact(expected);
    _completeUnrelatedCleanup(expected.groupId);
    return result;
  }

  void _completeUnrelatedCleanup(String groupId) {
    if (groupId == unrelatedGroupId && !unrelatedCleanupCompleted.isCompleted) {
      unrelatedCleanupCompleted.complete();
    }
  }
}

class _FailOnceCompleteIntentRepo extends _IntentRepo {
  _FailOnceCompleteIntentRepo(super.pendingRepo);

  var shouldFailCompletion = true;

  @override
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  }) {
    if (shouldFailCompletion) {
      shouldFailCompletion = false;
      throw StateError('forced notice completion transaction failure');
    }
    return super.completeLeaveNoticeAttempt(
      expected: expected,
      pendingBroadcast: pendingBroadcast,
      completionCode: completionCode,
      updatedAt: updatedAt,
    );
  }
}

GroupExitIntent _intent(
  GroupExitIntentState state, {
  String groupId = 'group-1',
}) {
  final createdAt = DateTime.utc(2026, 7, 21, 8);
  final hasNotice = state != GroupExitIntentState.queued;
  return GroupExitIntent(
    groupId: groupId,
    intentId: 'intent-$groupId',
    selfPeerId: 'peer-self',
    selfJoinedAt: DateTime.utc(2026, 7, 20),
    state: state,
    pendingBroadcastId: 'leave-notice-$groupId',
    sourceEventId: hasNotice
        ? 'member_removed:$groupId:peer-self:intent-$groupId'
        : null,
    eventAt: hasNotice ? createdAt : null,
    revision: state.index,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

GroupPendingBroadcast _noticeFor(GroupExitIntent intent) =>
    GroupPendingBroadcast(
      id: intent.pendingBroadcastId,
      groupId: intent.groupId,
      kind: groupPendingBroadcastKindExitLeaveNotice,
      sysText: _signedNoticeText(intent),
      recipientPeerIds: const <String>['peer-other'],
      eventAt: intent.eventAt!,
      sourceMessageId: intent.sourceEventId,
      createdAt: intent.createdAt,
      updatedAt: intent.updatedAt,
    );

String _signedNoticeText(
  GroupExitIntent intent, {
  String? peerId,
  String? sourceEventId,
  DateTime? eventAt,
}) {
  final actorPeerId = peerId ?? intent.selfPeerId;
  final stableSourceEventId = sourceEventId ?? intent.sourceEventId!;
  final stableEventAt = (eventAt ?? intent.eventAt!).toUtc();
  final transitionSubject = <String, Object?>{
    'member': <String, Object?>{'peerId': actorPeerId, 'username': 'Self'},
    'removedAt': stableEventAt.toIso8601String(),
    'groupConfigHash': 'test-group-config-hash',
  };
  return jsonEncode(<String, Object?>{
    '__sys': 'member_removed',
    'member': <String, Object?>{'peerId': actorPeerId, 'username': 'Self'},
    'removedAt': stableEventAt.toIso8601String(),
    'groupConfig': <String, Object?>{
      'members': <Object?>[
        <String, Object?>{'peerId': 'peer-other', 'username': 'Other'},
      ],
    },
    'signedTransitionAudit': <String, Object?>{
      'transitionType': 'member_removed',
      'groupId': intent.groupId,
      'sourceEventId': stableSourceEventId,
      'eventAt': stableEventAt.toIso8601String(),
      'signedPayload': jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'transitionType': 'member_removed',
        'groupId': intent.groupId,
        'sourceEventId': stableSourceEventId,
        'eventAt': stableEventAt.toIso8601String(),
        'actor': <String, Object?>{'peerId': actorPeerId},
        'transitionSubject': transitionSubject,
      }),
      'signature': 'test-signature',
    },
  });
}

Future<InMemoryGroupRepository> _activeGroupRepo({
  DateTime? watermark,
  InMemoryGroupRepository? repository,
}) async {
  final repo = repository ?? InMemoryGroupRepository();
  final joinedAt = DateTime.utc(2026, 7, 20);
  await repo.saveGroup(
    GroupModel(
      id: 'group-1',
      name: 'Group',
      type: GroupType.chat,
      topicName: 'topic-group-1',
      createdAt: joinedAt,
      createdBy: 'peer-other',
      myRole: GroupRole.member,
      lastMembershipEventAt: watermark ?? DateTime.utc(2026, 7, 21, 7, 59),
      lastMembershipEventId: 'role-watermark',
    ),
  );
  await repo.saveMember(
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-self',
      username: 'Self',
      role: MemberRole.writer,
      joinedAt: joinedAt,
    ),
  );
  await repo.saveMember(
    GroupMember(
      groupId: 'group-1',
      peerId: 'peer-other',
      username: 'Other',
      role: MemberRole.admin,
      joinedAt: joinedAt,
    ),
  );
  return repo;
}

GroupExitIntentRepository _sqliteIntentRepository(Database db) =>
    GroupExitIntentRepositoryImpl(
      dbLoadForGroup: (groupId) => dbLoadGroupExitIntentForGroup(db, groupId),
      dbLoadAll: () => dbLoadAllGroupExitIntents(db),
      dbEnqueue: (row) => dbEnqueueGroupExitIntent(db, row),
      dbCancelQueued: ({required expected, required updatedAt}) =>
          dbCancelQueuedGroupExitIntent(
            db,
            expected: expected,
            updatedAt: updatedAt,
          ),
      dbPrepareLeaveNotice:
          ({
            required expected,
            required timelineRow,
            required pendingBroadcastRow,
            required updatedAt,
          }) => dbPrepareGroupExitLeaveNotice(
            db,
            expected: expected,
            timelineRow: timelineRow,
            pendingBroadcastRow: pendingBroadcastRow,
            updatedAt: updatedAt,
          ),
      dbCompleteLeaveNoticeAttempt:
          ({
            required expected,
            required pendingBroadcastRow,
            required completionCode,
            required updatedAt,
          }) => dbCompleteGroupExitLeaveNotice(
            db,
            expected: expected,
            pendingBroadcastRow: pendingBroadcastRow,
            completionCode: completionCode,
            updatedAt: updatedAt,
          ),
      dbAdvance:
          ({
            required expected,
            required nextState,
            required updatedAt,
            lastErrorCode,
          }) => dbAdvanceGroupExitIntent(
            db,
            expected: expected,
            nextState: nextState,
            updatedAt: updatedAt,
            lastErrorCode: lastErrorCode,
          ),
      dbCleanupOrRetire: ({required expected, required updatedAt}) =>
          dbCleanupOrRetireGroupExitIntent(
            db,
            expected: expected,
            updatedAt: updatedAt,
          ),
      dbRetireExact: (expected) => dbRetireExactGroupExitIntent(db, expected),
      dbTerminalizeForGroup: (groupId) =>
          dbTerminalizeGroupExitIntentForGroup(db, groupId),
    );

GroupPendingBroadcastRepository _sqlitePendingRepository(Database db) =>
    GroupPendingBroadcastRepositoryImpl(
      dbInsert: (row) => dbInsertPendingGroupBroadcast(db, row),
      dbLoadForGroup: (groupId) =>
          dbLoadPendingGroupBroadcastsForGroup(db, groupId),
      dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(db),
      dbCountForGroup: (groupId) =>
          dbCountPendingGroupBroadcastsForGroup(db, groupId),
      dbDelete: (id) => dbDeletePendingGroupBroadcast(db, id),
      dbDeleteIfExact: (expected) =>
          dbDeletePendingGroupBroadcastIfExact(db, expected),
      dbDeleteForGroup: (groupId) =>
          dbDeletePendingGroupBroadcastsForGroup(db, groupId),
    );

GroupExitIntentRunner _cleanupOnlyRunner(
  GroupExitIntentRepository intentRepository, {
  GroupRepository? groupRepository,
}) {
  final pendingRepository = _PendingRepo();
  return GroupExitIntentRunner(
    intentRepository: intentRepository,
    pendingRepository: pendingRepository,
    pendingBroadcastRunner: GroupPendingBroadcastRunner(
      repository: pendingRepository,
      rePush: (_) async => true,
    ),
    groupRepository: groupRepository ?? InMemoryGroupRepository(),
    loadCurrentSelfPeerId: () async => 'peer-self',
    prepareNotice:
        ({required intent, required sourceEventId, required eventAt}) async =>
            throw StateError('cleanup must not prepare a notice'),
    attemptNotice: ({required intent, required pendingBroadcast}) async =>
        throw StateError('cleanup must not attempt a notice'),
    rotateKeys: (_) async => throw StateError('cleanup must not rotate keys'),
    nativeLeave: (_) async =>
        throw StateError('cleanup must not call native leave'),
    now: () => DateTime.utc(2026, 7, 21, 12),
  );
}

Future<void> _seedSqliteIdentity(Database db) =>
    db.insert('identity', <String, Object?>{
      'id': 1,
      'peer_id': 'peer-self',
      'public_key': '',
      'private_key': null,
      'mnemonic12': null,
      'username': 'Self',
      'created_at': '2026-07-21T08:00:00.000Z',
      'updated_at': '2026-07-21T08:00:00.000Z',
    });

Future<void> _seedSqliteGroup(
  Database db,
  String groupId, {
  required DateTime joinedAt,
  bool withSelf = true,
}) async {
  await db.insert('groups', <String, Object?>{
    'id': groupId,
    'name': groupId,
    'type': 'chat',
    'topic_name': 'topic-$groupId',
    'created_at': '2026-07-21T08:00:00.000Z',
    'created_by': 'peer-other',
    'my_role': 'member',
    'is_dissolved': 0,
    'self_removed_at': null,
    'last_membership_event_at': '2026-07-21T08:00:00.000Z',
  });
  if (!withSelf) return;
  await db.insert('group_members', <String, Object?>{
    'group_id': groupId,
    'peer_id': 'peer-self',
    'role': 'writer',
    'joined_at': joinedAt.toUtc().toIso8601String(),
  });
}

Map<String, Object?> _sqliteTimelineRow(String groupId) => <String, Object?>{
  'id': 'timeline-$groupId',
  'group_id': groupId,
  'sender_peer_id': 'peer-self',
  'text': '{"__sys":"member_removed"}',
  'timestamp': '2026-07-21T08:00:00.000Z',
  'key_generation': 1,
  'status': 'sent',
  'is_incoming': 0,
  'created_at': '2026-07-21T08:00:00.000Z',
};

Future<int> _scopedCount(Database db, String table, String groupId) => db
    .rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE group_id = ?',
      <Object?>[groupId],
    )
    .then((rows) => rows.single['count'] as int);

void main() {
  sqfliteFfiInit();

  test(
    'PB264-09 signed leave notice is watermark-newer, stable, and atomically handed off',
    () async {
      final pendingRepo = _PendingRepo();
      final queued = _intent(GroupExitIntentState.queued);
      final intentRepo = _IntentRepo(pendingRepo)..seed(queued);
      final groupRepo = await _activeGroupRepo(watermark: queued.createdAt);
      var prepareCount = 0;
      var attemptCount = 0;
      var rotationCount = 0;
      var nativeCount = 0;
      final runner = GroupExitIntentRunner(
        intentRepository: intentRepo,
        pendingRepository: pendingRepo,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pendingRepo,
          rePush: (_) async => true,
        ),
        groupRepository: groupRepo,
        loadCurrentSelfPeerId: () async => 'peer-self',
        prepareNotice:
            ({
              required intent,
              required sourceEventId,
              required eventAt,
            }) async {
              prepareCount++;
              return GroupExitPreparedNotice(
                timelineMessage: buildMemberRemovedTimelineMessage(
                  groupId: intent.groupId,
                  removedPeerId: intent.selfPeerId,
                  removedUsername: 'Self',
                  senderId: intent.selfPeerId,
                  senderUsername: 'Self',
                  eventAt: eventAt,
                ),
                pendingBroadcast: GroupPendingBroadcast(
                  id: intent.pendingBroadcastId,
                  groupId: intent.groupId,
                  kind: groupPendingBroadcastKindExitLeaveNotice,
                  sysText: _signedNoticeText(
                    intent.copyWith(
                      sourceEventId: sourceEventId,
                      eventAt: eventAt,
                    ),
                  ),
                  recipientPeerIds: const <String>['peer-other'],
                  eventAt: eventAt,
                  sourceMessageId: sourceEventId,
                  createdAt: intent.createdAt,
                  updatedAt: intent.updatedAt,
                ),
              );
            },
        attemptNotice: ({required intent, required pendingBroadcast}) async {
          attemptCount++;
          return GroupExitNoticeAttemptDisposition.delivered;
        },
        rotateKeys: (_) async => rotationCount++,
        nativeLeave: (_) async => nativeCount++,
      );

      final result = await runner.processGroup('group-1');

      expect(result.status, GroupExitIntentProcessStatus.completed);
      expect(prepareCount, 1);
      expect(attemptCount, 1);
      expect(rotationCount, 1);
      expect(nativeCount, 1);
      expect(await intentRepo.forGroup('group-1'), isNull);
      expect(await pendingRepo.forGroup('group-1'), isEmpty);
      final prepared = intentRepo.preparedNotices.single;
      expect(
        prepared.eventAt,
        DateTime.utc(2026, 7, 21, 8).add(const Duration(microseconds: 1)),
        reason: 'equal authority must advance strictly beyond the watermark',
      );
      expect(
        prepared.sourceMessageId,
        'member_removed:group-1:peer-self:intent-group-1',
      );
    },
  );

  test(
    'PB264-09 queued runner trusts exact self-admin row over stale group projection',
    () async {
      final pendingRepo = _PendingRepo();
      final queued = _intent(GroupExitIntentState.queued);
      final intentRepo = _IntentRepo(pendingRepo)..seed(queued);
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: queued.groupId,
          name: 'Stale role projection',
          type: GroupType.chat,
          topicName: 'topic-${queued.groupId}',
          createdAt: queued.createdAt,
          createdBy: 'peer-self',
          myRole: GroupRole.member,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: queued.groupId,
          peerId: queued.selfPeerId,
          username: 'Self',
          role: MemberRole.admin,
          joinedAt: queued.selfJoinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: queued.groupId,
          peerId: 'peer-other',
          username: 'Other',
          role: MemberRole.writer,
          joinedAt: queued.selfJoinedAt,
        ),
      );
      var prepares = 0;
      final runner = GroupExitIntentRunner(
        intentRepository: intentRepo,
        pendingRepository: pendingRepo,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pendingRepo,
          rePush: (_) async => true,
        ),
        groupRepository: groupRepo,
        loadCurrentSelfPeerId: () async => queued.selfPeerId,
        prepareNotice:
            ({
              required intent,
              required sourceEventId,
              required eventAt,
            }) async {
              prepares++;
              throw StateError('must not prepare');
            },
        attemptNotice: ({required intent, required pendingBroadcast}) async =>
            throw StateError('must not attempt'),
        rotateKeys: (_) async => throw StateError('must not rotate'),
        nativeLeave: (_) async => throw StateError('must not leave'),
      );

      final result = await runner.processGroup(queued.groupId);

      expect(result.status, GroupExitIntentProcessStatus.blockedLastAdmin);
      expect(prepares, 0);
      expect(
        (await intentRepo.forGroup(queued.groupId))?.state,
        GroupExitIntentState.queued,
      );
    },
  );

  test(
    'PB264-09 prepared leave actor and subject must match the exact intent identity',
    () async {
      final pendingRepo = _PendingRepo();
      final queued = _intent(GroupExitIntentState.queued);
      final intentRepo = _IntentRepo(pendingRepo)..seed(queued);
      final groupRepo = await _activeGroupRepo();
      var attempted = 0;
      var rotated = 0;
      var native = 0;
      final runner = GroupExitIntentRunner(
        intentRepository: intentRepo,
        pendingRepository: pendingRepo,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pendingRepo,
          rePush: (_) async => true,
        ),
        groupRepository: groupRepo,
        loadCurrentSelfPeerId: () async => 'peer-self',
        prepareNotice:
            ({
              required intent,
              required sourceEventId,
              required eventAt,
            }) async {
              const wrongPeerId = 'peer-other-identity';
              final preparedIntent = intent.copyWith(
                sourceEventId: sourceEventId,
                eventAt: eventAt,
              );
              return GroupExitPreparedNotice(
                timelineMessage: buildMemberRemovedTimelineMessage(
                  groupId: intent.groupId,
                  removedPeerId: wrongPeerId,
                  removedUsername: 'Wrong identity',
                  senderId: wrongPeerId,
                  senderUsername: 'Wrong identity',
                  eventAt: eventAt,
                ),
                pendingBroadcast: GroupPendingBroadcast(
                  id: intent.pendingBroadcastId,
                  groupId: intent.groupId,
                  kind: groupPendingBroadcastKindExitLeaveNotice,
                  sysText: _signedNoticeText(
                    preparedIntent,
                    peerId: wrongPeerId,
                  ),
                  recipientPeerIds: const <String>['peer-other'],
                  eventAt: eventAt,
                  sourceMessageId: sourceEventId,
                  createdAt: intent.createdAt,
                  updatedAt: intent.updatedAt,
                ),
              );
            },
        attemptNotice: ({required intent, required pendingBroadcast}) async {
          attempted++;
          return GroupExitNoticeAttemptDisposition.delivered;
        },
        rotateKeys: (_) async => rotated++,
        nativeLeave: (_) async => native++,
      );

      final result = await runner.processGroup(queued.groupId);

      expect(result.status, GroupExitIntentProcessStatus.failed);
      expect(result.cause, isA<StateError>());
      expect(attempted, 0);
      expect(rotated, 0);
      expect(native, 0);
      expect(
        (await intentRepo.forGroup(queued.groupId))?.state,
        GroupExitIntentState.queued,
      );
      expect(await pendingRepo.forGroup(queued.groupId), isEmpty);
    },
  );

  test(
    'PB264-09 process recreation refuses a different current identity before every side effect',
    () async {
      for (final state in GroupExitIntentState.values) {
        final pendingRepo = _PendingRepo();
        final intent = _intent(state);
        final intentRepo = _IntentRepo(pendingRepo)..seed(intent);
        if (state != GroupExitIntentState.queued) {
          await pendingRepo.enqueue(_noticeFor(intent));
        } else {
          await pendingRepo.enqueue(
            GroupPendingBroadcast(
              id: 'role-before-account-switch',
              groupId: intent.groupId,
              kind: groupPendingBroadcastKindMemberRoleUpdated,
              sysText: '{}',
              recipientPeerIds: const <String>['peer-other'],
              eventAt: intent.createdAt,
              sourceMessageId: 'role-before-account-switch',
              createdAt: intent.createdAt,
              updatedAt: intent.updatedAt,
            ),
          );
        }
        final cleanupProbe = _ExitCleanupProbeGroupRepository();
        final groupRepo = await _activeGroupRepo(repository: cleanupProbe);
        var prepared = 0;
        var attempted = 0;
        var rotated = 0;
        var native = 0;
        var rePushed = 0;
        final runner = GroupExitIntentRunner(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async {
              rePushed++;
              return true;
            },
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async => 'peer-different-account',
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async {
                prepared++;
                throw StateError('must not prepare');
              },
          attemptNotice: ({required intent, required pendingBroadcast}) async {
            attempted++;
            return GroupExitNoticeAttemptDisposition.delivered;
          },
          rotateKeys: (_) async => rotated++,
          nativeLeave: (_) async => native++,
        );

        final result = await runner.processGroup(intent.groupId);

        expect(
          result.status,
          GroupExitIntentProcessStatus.failed,
          reason: state.name,
        );
        expect(result.cause, isA<StateError>(), reason: state.name);
        expect(prepared, 0, reason: state.name);
        expect(attempted, 0, reason: state.name);
        expect(rotated, 0, reason: state.name);
        expect(native, 0, reason: state.name);
        expect(rePushed, 0, reason: state.name);
        expect(cleanupProbe.events, isEmpty, reason: state.name);
        expect(
          (await intentRepo.forGroup(intent.groupId))?.state,
          state,
          reason: state.name,
        );
      }
    },
  );

  test(
    'PB264-09 terminal group authority retires stale work before loading a changed identity',
    () async {
      for (final terminal in <String>['absent', 'dissolved', 'self_removed']) {
        final pendingRepo = _PendingRepo();
        final intent = _intent(GroupExitIntentState.queued);
        final intentRepo = _IntentRepo(pendingRepo)..seed(intent);
        await pendingRepo.enqueue(
          GroupPendingBroadcast(
            id: 'must-not-repush-$terminal',
            groupId: intent.groupId,
            kind: groupPendingBroadcastKindMemberRoleUpdated,
            sysText: '{}',
            recipientPeerIds: const <String>['peer-other'],
            eventAt: intent.createdAt,
            sourceMessageId: 'must-not-repush-$terminal',
            createdAt: intent.createdAt,
            updatedAt: intent.updatedAt,
          ),
        );
        final groupRepo = _ExitCleanupProbeGroupRepository();
        if (terminal != 'absent') {
          await groupRepo.saveGroup(
            GroupModel(
              id: intent.groupId,
              name: 'Terminal',
              type: GroupType.chat,
              topicName: 'topic-terminal',
              createdAt: intent.createdAt,
              createdBy: 'peer-other',
              myRole: GroupRole.member,
              isDissolved: terminal == 'dissolved',
              dissolvedAt: terminal == 'dissolved' ? intent.updatedAt : null,
              selfRemovedAt: terminal == 'self_removed'
                  ? intent.updatedAt
                  : null,
            ),
          );
        }
        var identityLoads = 0;
        var rePushed = 0;
        final runner = GroupExitIntentRunner(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async {
              rePushed++;
              return true;
            },
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async {
            identityLoads++;
            throw StateError('replacement account must not be consulted');
          },
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async => throw StateError('must not prepare'),
          attemptNotice: ({required intent, required pendingBroadcast}) async =>
              throw StateError('must not attempt'),
          rotateKeys: (_) async => throw StateError('must not rotate'),
          nativeLeave: (_) async => throw StateError('must not leave'),
        );

        final result = await runner.processGroup(intent.groupId);

        expect(
          result.status,
          GroupExitIntentProcessStatus.completed,
          reason: terminal,
        );
        expect(await intentRepo.forGroup(intent.groupId), isNull);
        expect(identityLoads, 0, reason: terminal);
        expect(rePushed, 0, reason: terminal);
        expect(groupRepo.events, isEmpty, reason: terminal);
        expect(
          pendingRepo.rows.containsKey('must-not-repush-$terminal'),
          isTrue,
          reason: 'terminal retirement is exact: $terminal',
        );
      }
    },
  );

  test(
    'PB264-09 missing exact notice waits while degraded completion retires only that notice',
    () async {
      Future<
        ({
          GroupExitIntentProcessResult result,
          _IntentRepo intents,
          _PendingRepo pending,
          int attempts,
          int rotations,
          int nativeLeaves,
        })
      >
      run({required bool seedNotice}) async {
        final pendingRepo = _PendingRepo();
        final pendingIntent = _intent(GroupExitIntentState.leaveNoticePending);
        final intentRepo = _IntentRepo(pendingRepo)..seed(pendingIntent);
        if (seedNotice) await pendingRepo.enqueue(_noticeFor(pendingIntent));
        await pendingRepo.enqueue(
          GroupPendingBroadcast(
            id: 'generic-role-control',
            groupId: pendingIntent.groupId,
            kind: 'member_role_updated',
            sysText: '{"role":"pending"}',
            recipientPeerIds: const <String>['peer-other'],
            eventAt: pendingIntent.eventAt!,
            sourceMessageId: 'role-control-source',
            createdAt: pendingIntent.createdAt,
            updatedAt: pendingIntent.updatedAt,
          ),
        );
        final groupRepo = await _activeGroupRepo();
        var attempts = 0;
        var rotations = 0;
        var nativeLeaves = 0;
        final runner = GroupExitIntentRunner(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async => false,
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async => 'peer-self',
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async => throw StateError('must not prepare'),
          attemptNotice: ({required intent, required pendingBroadcast}) async {
            attempts++;
            return GroupExitNoticeAttemptDisposition.degraded;
          },
          rotateKeys: (_) async => rotations++,
          nativeLeave: (_) async => nativeLeaves++,
        );
        return (
          result: await runner.processGroup(pendingIntent.groupId),
          intents: intentRepo,
          pending: pendingRepo,
          attempts: attempts,
          rotations: rotations,
          nativeLeaves: nativeLeaves,
        );
      }

      final missing = await run(seedNotice: false);
      expect(
        missing.result.status,
        GroupExitIntentProcessStatus.waitingForNoticeRetry,
      );
      expect(missing.attempts, 0);
      expect(missing.rotations, 0);
      expect(missing.nativeLeaves, 0);
      expect(
        (await missing.intents.forGroup('group-1'))?.state,
        GroupExitIntentState.leaveNoticePending,
      );
      expect(
        (await missing.pending.forGroup('group-1')).single.id,
        'generic-role-control',
      );

      final degraded = await run(seedNotice: true);
      expect(degraded.result.status, GroupExitIntentProcessStatus.completed);
      expect(degraded.attempts, 1);
      expect(degraded.rotations, 1);
      expect(degraded.nativeLeaves, 1);
      expect(degraded.intents.completionCodes, ['notice_degraded']);
      expect(
        (await degraded.pending.forGroup('group-1')).single.id,
        'generic-role-control',
        reason: 'degraded exit policy must not retire ordinary role work',
      );
    },
  );

  test(
    'PB264-09 completion fault and restart reuse the exact durable notice without reminting',
    () async {
      final pendingRepo = _PendingRepo();
      final pendingIntent = _intent(GroupExitIntentState.leaveNoticePending);
      final intentRepo = _FailOnceCompleteIntentRepo(pendingRepo)
        ..seed(pendingIntent);
      final durableNotice = _noticeFor(pendingIntent);
      await pendingRepo.enqueue(durableNotice);
      final groupRepo = await _activeGroupRepo();
      var prepares = 0;
      final attemptedNotices = <GroupPendingBroadcast>[];
      var rotations = 0;
      var nativeLeaves = 0;

      GroupExitIntentRunner recreate() => GroupExitIntentRunner(
        intentRepository: intentRepo,
        pendingRepository: pendingRepo,
        pendingBroadcastRunner: GroupPendingBroadcastRunner(
          repository: pendingRepo,
          rePush: (_) async => true,
        ),
        groupRepository: groupRepo,
        loadCurrentSelfPeerId: () async => 'peer-self',
        prepareNotice:
            ({
              required intent,
              required sourceEventId,
              required eventAt,
            }) async {
              prepares++;
              throw StateError('durable notice must not be prepared again');
            },
        attemptNotice: ({required intent, required pendingBroadcast}) async {
          attemptedNotices.add(pendingBroadcast);
          return GroupExitNoticeAttemptDisposition.delivered;
        },
        rotateKeys: (_) async => rotations++,
        nativeLeave: (_) async => nativeLeaves++,
      );

      await expectLater(
        recreate().processGroup(pendingIntent.groupId),
        throwsA(isA<StateError>()),
      );
      expect(
        sameExactGroupPendingBroadcast(
          (await pendingRepo.forGroup(pendingIntent.groupId)).single,
          durableNotice,
        ),
        isTrue,
      );
      expect(
        (await intentRepo.forGroup(pendingIntent.groupId))?.state,
        GroupExitIntentState.leaveNoticePending,
      );

      final completed = await recreate().processGroup(pendingIntent.groupId);
      expect(completed.status, GroupExitIntentProcessStatus.completed);
      expect(prepares, 0);
      expect(attemptedNotices, hasLength(2));
      expect(
        sameExactGroupPendingBroadcast(
          attemptedNotices.first,
          attemptedNotices.last,
        ),
        isTrue,
      );
      expect(rotations, 1);
      expect(nativeLeaves, 1);
    },
  );

  test(
    'PB264-09 real SQLite prepare and completion faults roll back atomically and restart reuses the durable signature',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'pb264-notice-atomicity-',
      );
      final databasePath = '${tempDirectory.path}/notice.sqlite';
      var db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      await runProductionOnCreate(db, 103);
      await _seedSqliteIdentity(db);

      final queued = _intent(GroupExitIntentState.queued);
      await _seedSqliteGroup(db, queued.groupId, joinedAt: queued.selfJoinedAt);
      expect(
        (await _sqliteIntentRepository(db).enqueue(queued)).committed,
        isTrue,
      );
      final groupRepo = await _activeGroupRepo(watermark: queued.createdAt);
      final preparedNotices = <GroupPendingBroadcast>[];
      final attemptedNotices = <GroupPendingBroadcast>[];
      var prepareCalls = 0;

      GroupExitIntentRunner recreate({bool forbidPrepare = false}) {
        final intentRepository = _sqliteIntentRepository(db);
        final pendingRepository = _sqlitePendingRepository(db);
        return GroupExitIntentRunner(
          intentRepository: intentRepository,
          pendingRepository: pendingRepository,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepository,
            rePush: (_) async => true,
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async => queued.selfPeerId,
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async {
                prepareCalls++;
                if (forbidPrepare) {
                  throw StateError(
                    'a committed durable notice must never be reminted',
                  );
                }
                final preparedIntent = intent.copyWith(
                  sourceEventId: sourceEventId,
                  eventAt: eventAt,
                );
                final notice = GroupPendingBroadcast(
                  id: intent.pendingBroadcastId,
                  groupId: intent.groupId,
                  kind: groupPendingBroadcastKindExitLeaveNotice,
                  sysText: _signedNoticeText(preparedIntent),
                  recipientPeerIds: const <String>['peer-other'],
                  eventAt: eventAt,
                  sourceMessageId: sourceEventId,
                  createdAt: intent.createdAt,
                  updatedAt: intent.updatedAt,
                );
                preparedNotices.add(notice);
                return GroupExitPreparedNotice(
                  timelineMessage: buildMemberRemovedTimelineMessage(
                    groupId: intent.groupId,
                    removedPeerId: intent.selfPeerId,
                    removedUsername: 'Self',
                    senderId: intent.selfPeerId,
                    senderUsername: 'Self',
                    eventAt: eventAt,
                  ),
                  pendingBroadcast: notice,
                );
              },
          attemptNotice: ({required intent, required pendingBroadcast}) async {
            attemptedNotices.add(pendingBroadcast);
            return GroupExitNoticeAttemptDisposition.delivered;
          },
          rotateKeys: (_) async {},
          nativeLeave: (_) async {},
          now: () => DateTime.utc(2026, 7, 21, 8, 5),
        );
      }

      Future<void> reopen() async {
        await db.close();
        db = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
      }

      // Fire only after both compound children are visible to the transaction.
      // The thrown DatabaseException must make SQLite roll all three writes back.
      await db.execute('''
        CREATE TRIGGER pb264_abort_notice_prepare
        BEFORE UPDATE OF state ON group_exit_intents
        WHEN OLD.group_id = 'group-1'
          AND OLD.state = 'queued'
          AND NEW.state = 'leave_notice_pending'
          AND EXISTS (
            SELECT 1 FROM group_messages
            WHERE group_id = OLD.group_id
          )
          AND EXISTS (
            SELECT 1 FROM pending_group_broadcasts
            WHERE group_id = OLD.group_id
              AND kind = 'member_removed_exit_intent'
          )
        BEGIN
          SELECT RAISE(ABORT, 'injected notice prepare failure');
        END
      ''');
      await expectLater(
        recreate().processGroup(queued.groupId),
        throwsA(isA<DatabaseException>()),
      );
      expect(prepareCalls, 1);

      await reopen();
      final afterPrepareFault = await _sqliteIntentRepository(
        db,
      ).forGroup(queued.groupId);
      expect(afterPrepareFault?.state, GroupExitIntentState.queued);
      expect(afterPrepareFault?.revision, 0);
      expect(afterPrepareFault?.sourceEventId, isNull);
      expect(afterPrepareFault?.eventAt, isNull);
      expect(await _scopedCount(db, 'group_messages', queued.groupId), 0);
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', queued.groupId),
        0,
      );

      await db.execute('DROP TRIGGER pb264_abort_notice_prepare');
      // Completion deletes the exact outbox row before its phase CAS. Abort at
      // that CAS to prove the delete and phase move share one transaction.
      await db.execute('''
        CREATE TRIGGER pb264_abort_notice_completion
        BEFORE UPDATE OF state ON group_exit_intents
        WHEN OLD.group_id = 'group-1'
          AND OLD.state = 'leave_notice_pending'
          AND NEW.state = 'leave_notice_attempted'
          AND NOT EXISTS (
            SELECT 1 FROM pending_group_broadcasts
            WHERE id = OLD.pending_broadcast_id
          )
        BEGIN
          SELECT RAISE(ABORT, 'injected notice completion failure');
        END
      ''');
      await expectLater(
        recreate().processGroup(queued.groupId),
        throwsA(isA<DatabaseException>()),
      );
      expect(prepareCalls, 2);
      expect(attemptedNotices, hasLength(1));
      expect(preparedNotices, hasLength(2));
      expect(
        sameExactGroupPendingBroadcast(
          preparedNotices.first,
          preparedNotices.last,
        ),
        isTrue,
        reason:
            'a rolled-back prepare retry must deterministically reproduce the signed notice',
      );
      final durableNotice = preparedNotices.last;

      await reopen();
      final afterCompletionFault = await _sqliteIntentRepository(
        db,
      ).forGroup(queued.groupId);
      expect(
        afterCompletionFault?.state,
        GroupExitIntentState.leaveNoticePending,
      );
      expect(afterCompletionFault?.revision, 1);
      expect(
        afterCompletionFault?.sourceEventId,
        durableNotice.sourceMessageId,
      );
      expect(afterCompletionFault?.eventAt, durableNotice.eventAt);
      final persistedNotice = (await _sqlitePendingRepository(
        db,
      ).forGroup(queued.groupId)).single;
      expect(
        sameExactGroupPendingBroadcast(persistedNotice, durableNotice),
        isTrue,
      );
      expect(
        sameExactGroupPendingBroadcast(attemptedNotices.single, durableNotice),
        isTrue,
      );
      expect(await _scopedCount(db, 'group_messages', queued.groupId), 1);

      await db.execute('DROP TRIGGER pb264_abort_notice_completion');
      // Fence the next transaction so successful completion remains observable
      // before the later rotation/native/cleanup phases run.
      await db.execute('''
        CREATE TRIGGER pb264_stop_after_notice_completion
        BEFORE UPDATE OF state ON group_exit_intents
        WHEN OLD.group_id = 'group-1'
          AND OLD.state = 'leave_notice_attempted'
          AND NEW.state = 'rotation_claimed'
          AND NOT EXISTS (
            SELECT 1 FROM pending_group_broadcasts
            WHERE id = OLD.pending_broadcast_id
          )
        BEGIN
          SELECT RAISE(ABORT, 'observe committed notice completion');
        END
      ''');
      final prepareCallsBeforeRestart = prepareCalls;
      await expectLater(
        recreate(forbidPrepare: true).processGroup(queued.groupId),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        prepareCalls,
        prepareCallsBeforeRestart,
        reason: 'leave_notice_pending must load, not remint, its signed row',
      );
      expect(attemptedNotices, hasLength(2));
      expect(
        sameExactGroupPendingBroadcast(
          attemptedNotices.first,
          attemptedNotices.last,
        ),
        isTrue,
      );

      await reopen();
      final completed = await _sqliteIntentRepository(
        db,
      ).forGroup(queued.groupId);
      expect(completed?.state, GroupExitIntentState.leaveNoticeAttempted);
      expect(completed?.revision, 2);
      expect(completed?.lastErrorCode, 'notice_delivered');
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', queued.groupId),
        0,
      );
      expect(await _scopedCount(db, 'group_messages', queued.groupId), 1);
    },
  );

  test(
    'PB264-10 process recreation at every durable phase never repeats an earlier side effect',
    () async {
      Future<void> runCase(
        GroupExitIntentState state, {
        required int expectedPrepare,
        required int expectedAttempt,
        required int expectedRotation,
        required int expectedNative,
      }) async {
        final pendingRepo = _PendingRepo();
        final intent = _intent(state);
        final intentRepo = _IntentRepo(pendingRepo)..seed(intent);
        if (state == GroupExitIntentState.leaveNoticePending) {
          await pendingRepo.enqueue(_noticeFor(intent));
        }
        final groupRepo = await _activeGroupRepo();
        var prepared = 0;
        var attempted = 0;
        var rotated = 0;
        var native = 0;
        final runner = GroupExitIntentRunner(
          intentRepository: intentRepo,
          pendingRepository: pendingRepo,
          pendingBroadcastRunner: GroupPendingBroadcastRunner(
            repository: pendingRepo,
            rePush: (_) async => true,
          ),
          groupRepository: groupRepo,
          loadCurrentSelfPeerId: () async => 'peer-self',
          prepareNotice:
              ({
                required intent,
                required sourceEventId,
                required eventAt,
              }) async {
                prepared++;
                if (state != GroupExitIntentState.queued) {
                  throw StateError('an earlier phase must not prepare again');
                }
                final preparedIntent = intent.copyWith(
                  sourceEventId: sourceEventId,
                  eventAt: eventAt,
                );
                return GroupExitPreparedNotice(
                  timelineMessage: buildMemberRemovedTimelineMessage(
                    groupId: intent.groupId,
                    removedPeerId: intent.selfPeerId,
                    removedUsername: 'Self',
                    senderId: intent.selfPeerId,
                    senderUsername: 'Self',
                    eventAt: eventAt,
                  ),
                  pendingBroadcast: _noticeFor(preparedIntent),
                );
              },
          attemptNotice: ({required intent, required pendingBroadcast}) async {
            attempted++;
            return GroupExitNoticeAttemptDisposition.delivered;
          },
          rotateKeys: (_) async => rotated++,
          nativeLeave: (_) async => native++,
        );

        expect(
          (await runner.processGroup('group-1')).status,
          GroupExitIntentProcessStatus.completed,
        );
        expect(prepared, expectedPrepare);
        expect(attempted, expectedAttempt);
        expect(rotated, expectedRotation);
        expect(native, expectedNative);
      }

      await runCase(
        GroupExitIntentState.queued,
        expectedPrepare: 1,
        expectedAttempt: 1,
        expectedRotation: 1,
        expectedNative: 1,
      );
      await runCase(
        GroupExitIntentState.leaveNoticePending,
        expectedPrepare: 0,
        expectedAttempt: 1,
        expectedRotation: 1,
        expectedNative: 1,
      );
      await runCase(
        GroupExitIntentState.leaveNoticeAttempted,
        expectedPrepare: 0,
        expectedAttempt: 0,
        expectedRotation: 1,
        expectedNative: 1,
      );
      await runCase(
        GroupExitIntentState.rotationClaimed,
        expectedPrepare: 0,
        expectedAttempt: 0,
        expectedRotation: 0,
        expectedNative: 1,
      );
      await runCase(
        GroupExitIntentState.nativeLeavePending,
        expectedPrepare: 0,
        expectedAttempt: 0,
        expectedRotation: 0,
        expectedNative: 1,
      );
      await runCase(
        GroupExitIntentState.cleanupPending,
        expectedPrepare: 0,
        expectedAttempt: 0,
        expectedRotation: 0,
        expectedNative: 0,
      );
    },
  );

  test(
    'PB264-10 native ambiguity retries only native after process recreation',
    () async {
      final pendingRepo = _PendingRepo();
      final nativePending = _intent(GroupExitIntentState.nativeLeavePending);
      final intentRepo = _IntentRepo(pendingRepo)..seed(nativePending);
      final groupRepo = await _activeGroupRepo();
      var prepares = 0;
      var attempts = 0;
      var rotations = 0;
      var nativeCalls = 0;

      GroupExitIntentRunner recreatedRunner({required bool nativeFails}) =>
          GroupExitIntentRunner(
            intentRepository: intentRepo,
            pendingRepository: pendingRepo,
            pendingBroadcastRunner: GroupPendingBroadcastRunner(
              repository: pendingRepo,
              rePush: (_) async => true,
            ),
            groupRepository: groupRepo,
            loadCurrentSelfPeerId: () async => 'peer-self',
            prepareNotice:
                ({
                  required intent,
                  required sourceEventId,
                  required eventAt,
                }) async {
                  prepares++;
                  throw StateError('must not prepare');
                },
            attemptNotice:
                ({required intent, required pendingBroadcast}) async {
                  attempts++;
                  return GroupExitNoticeAttemptDisposition.delivered;
                },
            rotateKeys: (_) async => rotations++,
            nativeLeave: (_) async {
              nativeCalls++;
              if (nativeFails) throw StateError('native outcome unknown');
            },
          );

      final ambiguous = await recreatedRunner(
        nativeFails: true,
      ).processGroup(nativePending.groupId);
      expect(
        ambiguous.status,
        GroupExitIntentProcessStatus.waitingForNativeRetry,
      );
      expect(
        (await intentRepo.forGroup(nativePending.groupId))?.state,
        GroupExitIntentState.nativeLeavePending,
      );

      final completed = await recreatedRunner(
        nativeFails: false,
      ).processGroup(nativePending.groupId);
      expect(completed.status, GroupExitIntentProcessStatus.completed);
      expect(prepares, 0);
      expect(attempts, 0);
      expect(rotations, 0);
      expect(nativeCalls, 2);
      expect(await intentRepo.forGroup(nativePending.groupId), isNull);
    },
  );

  test(
    'PB264-10 normal deferred rotation records a bounded diagnostic and restart is native-only',
    () async {
      final pendingRepo = _PendingRepo();
      final intent = _intent(GroupExitIntentState.leaveNoticeAttempted);
      final intentRepo = _IntentRepo(pendingRepo)..seed(intent);
      final groupRepo = await _activeGroupRepo();
      var rotations = 0;
      var nativeCalls = 0;

      GroupExitIntentRunner recreated({required bool nativeFails}) =>
          GroupExitIntentRunner(
            intentRepository: intentRepo,
            pendingRepository: pendingRepo,
            pendingBroadcastRunner: GroupPendingBroadcastRunner(
              repository: pendingRepo,
              rePush: (_) async => true,
            ),
            groupRepository: groupRepo,
            loadCurrentSelfPeerId: () async => 'peer-self',
            prepareNotice:
                ({
                  required intent,
                  required sourceEventId,
                  required eventAt,
                }) async => throw StateError('must not prepare'),
            attemptNotice:
                ({required intent, required pendingBroadcast}) async =>
                    throw StateError('must not attempt'),
            rotateKeys: (_) async {
              rotations++;
              throw const GroupExitRotationDeferred();
            },
            nativeLeave: (_) async {
              nativeCalls++;
              if (nativeFails) throw StateError('native outcome unknown');
            },
          );

      final first = await recreated(
        nativeFails: true,
      ).processGroup(intent.groupId);
      expect(first.status, GroupExitIntentProcessStatus.waitingForNativeRetry);
      final afterDeferredRotation = await intentRepo.forGroup(intent.groupId);
      expect(
        afterDeferredRotation?.state,
        GroupExitIntentState.nativeLeavePending,
      );
      expect(afterDeferredRotation?.lastErrorCode, 'rotation_deferred');
      expect(rotations, 1);
      expect(nativeCalls, 1);

      final second = await recreated(
        nativeFails: false,
      ).processGroup(intent.groupId);
      expect(second.status, GroupExitIntentProcessStatus.completed);
      expect(rotations, 1, reason: 'restart must never rotate a second epoch');
      expect(nativeCalls, 2);
      expect(await intentRepo.forGroup(intent.groupId), isNull);
    },
  );

  test(
    'PB264-12 external cleanup fault retains the intent and restart finalizes SQL last',
    () async {
      final pendingRepository = _PendingRepo();
      final intentRepository = _IntentRepo(pendingRepository);
      final groupRepository = _ExitCleanupProbeGroupRepository();
      final intent = _intent(GroupExitIntentState.cleanupPending);
      await groupRepository.saveGroup(
        GroupModel(
          id: intent.groupId,
          name: 'Group',
          type: GroupType.chat,
          topicName: 'topic-${intent.groupId}',
          createdAt: intent.selfJoinedAt,
          createdBy: 'peer-other',
          myRole: GroupRole.member,
        ),
      );
      await groupRepository.saveMember(
        GroupMember(
          groupId: intent.groupId,
          peerId: intent.selfPeerId,
          username: 'Self',
          role: MemberRole.writer,
          joinedAt: intent.selfJoinedAt,
        ),
      );
      intentRepository.seed(intent);
      groupRepository.failNextExternalCleanup = true;

      final first = await _cleanupOnlyRunner(
        intentRepository,
        groupRepository: groupRepository,
      ).processGroup(intent.groupId);
      expect(first.status, GroupExitIntentProcessStatus.failed);
      expect(first.cause, isA<StateError>());
      expect(
        (await intentRepository.forGroup(intent.groupId))?.state,
        GroupExitIntentState.cleanupPending,
      );
      expect(groupRepository.events, <String>['external']);

      final restarted = await _cleanupOnlyRunner(
        intentRepository,
        groupRepository: groupRepository,
      ).processGroup(intent.groupId);
      expect(restarted.status, GroupExitIntentProcessStatus.completed);
      expect(await intentRepository.forGroup(intent.groupId), isNull);
      expect(groupRepository.events, <String>['external', 'external', 'sql']);
    },
  );

  test(
    'PB264-12 confirmed cleanup is atomic and membership-generation safe',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'pb264-runner-cleanup-',
      );
      final databasePath = '${tempDirectory.path}/cleanup.sqlite';
      var db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(() async {
        if (db.isOpen) await db.close();
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      });
      await runProductionOnCreate(db, 103);
      await _seedSqliteIdentity(db);
      final sqliteGroupRepository = _SqliteExitCleanupGroupRepository(() => db);

      final absent = _intent(
        GroupExitIntentState.cleanupPending,
        groupId: 'parent-absent',
      );
      await db.insert('group_exit_intents', absent.toMap());
      await db.insert('pending_group_broadcasts', _noticeFor(absent).toMap());
      expect(
        (await _cleanupOnlyRunner(
          _sqliteIntentRepository(db),
          groupRepository: sqliteGroupRepository,
        ).processGroup(absent.groupId)).status,
        GroupExitIntentProcessStatus.completed,
      );
      expect(await dbLoadGroupExitIntentForGroup(db, absent.groupId), isNull);
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', absent.groupId),
        0,
      );

      final missingSelf = _intent(
        GroupExitIntentState.cleanupPending,
        groupId: 'self-missing',
      );
      await _seedSqliteGroup(
        db,
        missingSelf.groupId,
        joinedAt: missingSelf.selfJoinedAt,
        withSelf: false,
      );
      await db.insert('group_exit_intents', missingSelf.toMap());
      final ambiguous = await _cleanupOnlyRunner(
        _sqliteIntentRepository(db),
        groupRepository: sqliteGroupRepository,
      ).processGroup(missingSelf.groupId);
      expect(ambiguous.status, GroupExitIntentProcessStatus.failed);
      expect(ambiguous.cause, isA<StateError>());
      expect(
        await dbLoadGroupExitIntentForGroup(db, missingSelf.groupId),
        isNotNull,
      );
      expect(
        await db.query(
          'groups',
          where: 'id = ?',
          whereArgs: [missingSelf.groupId],
        ),
        hasLength(1),
      );

      final stale = _intent(
        GroupExitIntentState.cleanupPending,
        groupId: 'same-id-rejoined',
      );
      final newerJoinedAt = stale.selfJoinedAt.add(const Duration(days: 1));
      await _seedSqliteGroup(db, stale.groupId, joinedAt: newerJoinedAt);
      await db.insert('group_exit_intents', stale.toMap());
      await db.insert('group_messages', _sqliteTimelineRow(stale.groupId));
      await db.insert('pending_group_broadcasts', _noticeFor(stale).toMap());
      expect(
        (await _cleanupOnlyRunner(
          _sqliteIntentRepository(db),
          groupRepository: sqliteGroupRepository,
        ).processGroup(stale.groupId)).status,
        GroupExitIntentProcessStatus.retiredStaleMembership,
      );
      expect(await dbLoadGroupExitIntentForGroup(db, stale.groupId), isNull);
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', stale.groupId),
        0,
      );
      expect(
        (await db.query(
          'group_members',
          where: 'group_id = ? AND peer_id = ?',
          whereArgs: [stale.groupId, stale.selfPeerId],
        )).single['joined_at'],
        newerJoinedAt.toIso8601String(),
      );
      expect(await _scopedCount(db, 'group_messages', stale.groupId), 1);

      final exact = _intent(
        GroupExitIntentState.cleanupPending,
        groupId: 'exact-old-membership',
      );
      await _seedSqliteGroup(db, exact.groupId, joinedAt: exact.selfJoinedAt);
      await db.insert('group_exit_intents', exact.toMap());
      await db.insert('group_messages', _sqliteTimelineRow(exact.groupId));
      await db.insert('pending_group_broadcasts', _noticeFor(exact).toMap());
      await db.insert('group_keys', <String, Object?>{
        'group_id': exact.groupId,
        'key_generation': 1,
        'encrypted_key': 'old-membership-key',
        'created_at': '2026-07-21T08:00:00.000Z',
      });
      await db.execute('''
        CREATE TRIGGER pb264_intent_deleted_last
        BEFORE DELETE ON group_exit_intents
        WHEN OLD.group_id = 'exact-old-membership' AND (
          EXISTS (SELECT 1 FROM groups WHERE id = OLD.group_id) OR
          EXISTS (SELECT 1 FROM group_members WHERE group_id = OLD.group_id) OR
          EXISTS (SELECT 1 FROM group_messages WHERE group_id = OLD.group_id) OR
          EXISTS (SELECT 1 FROM group_keys WHERE group_id = OLD.group_id) OR
          EXISTS (
            SELECT 1 FROM pending_group_broadcasts
            WHERE group_id = OLD.group_id
          )
        )
        BEGIN
          SELECT RAISE(ABORT, 'group exit intent must be deleted last');
        END
      ''');
      await db.execute('''
        CREATE TRIGGER pb264_abort_exact_cleanup
        BEFORE DELETE ON groups
        WHEN OLD.id = 'exact-old-membership'
        BEGIN
          SELECT RAISE(ABORT, 'injected cleanup failure');
        END
      ''');

      final failedCleanup = await _cleanupOnlyRunner(
        _sqliteIntentRepository(db),
        groupRepository: sqliteGroupRepository,
      ).processGroup(exact.groupId);
      expect(failedCleanup.status, GroupExitIntentProcessStatus.failed);
      expect(failedCleanup.cause, isA<DatabaseException>());
      await db.close();
      db = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      expect(await dbLoadGroupExitIntentForGroup(db, exact.groupId), isNotNull);
      expect(
        await db.query('groups', where: 'id = ?', whereArgs: [exact.groupId]),
        hasLength(1),
      );
      expect(await _scopedCount(db, 'group_members', exact.groupId), 1);
      expect(await _scopedCount(db, 'group_messages', exact.groupId), 1);
      expect(await _scopedCount(db, 'group_keys', exact.groupId), 1);
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', exact.groupId),
        1,
      );

      await db.execute('DROP TRIGGER pb264_abort_exact_cleanup');
      expect(
        (await _cleanupOnlyRunner(
          _sqliteIntentRepository(db),
          groupRepository: sqliteGroupRepository,
        ).processGroup(exact.groupId)).status,
        GroupExitIntentProcessStatus.completed,
      );
      expect(await dbLoadGroupExitIntentForGroup(db, exact.groupId), isNull);
      expect(
        await db.query('groups', where: 'id = ?', whereArgs: [exact.groupId]),
        isEmpty,
      );
      expect(await _scopedCount(db, 'group_members', exact.groupId), 0);
      expect(await _scopedCount(db, 'group_messages', exact.groupId), 0);
      expect(await _scopedCount(db, 'group_keys', exact.groupId), 0);
      expect(
        await _scopedCount(db, 'pending_group_broadcasts', exact.groupId),
        0,
      );
    },
  );

  test(
    'PB264-12 residual cleanup intent on a dissolved group retires without external cleanup',
    () async {
      final pendingRepository = _PendingRepo();
      final intentRepository = _IntentRepo(pendingRepository);
      final groupRepository = _ExitCleanupProbeGroupRepository();
      final intent = _intent(GroupExitIntentState.cleanupPending);
      await groupRepository.saveGroup(
        GroupModel(
          id: intent.groupId,
          name: 'Dissolved Group',
          type: GroupType.chat,
          topicName: 'topic-${intent.groupId}',
          createdAt: intent.selfJoinedAt,
          createdBy: 'peer-other',
          myRole: GroupRole.member,
          isDissolved: true,
          dissolvedAt: intent.updatedAt,
        ),
      );
      intentRepository.seed(intent);
      pendingRepository.rows[intent.pendingBroadcastId] = _noticeFor(intent);

      final result = await _cleanupOnlyRunner(
        intentRepository,
        groupRepository: groupRepository,
      ).processGroup(intent.groupId);

      expect(result.status, GroupExitIntentProcessStatus.completed);
      expect(await intentRepository.forGroup(intent.groupId), isNull);
      expect(
        pendingRepository.rows.containsKey(intent.pendingBroadcastId),
        isFalse,
      );
      expect(groupRepository.events, isEmpty);
    },
  );

  test(
    'PB264-18 enqueue, startup, rejoin, resume, and manual retry share one processor',
    () async {
      const sharedGroup = 'group-shared';
      const unrelatedGroup = 'group-unrelated';
      final pendingRepo = _PendingRepo();
      final intentRepo =
          _TriggerProbeIntentRepo(
              pendingRepo,
              blockedGroupId: sharedGroup,
              unrelatedGroupId: unrelatedGroup,
            )
            ..seed(
              _intent(
                GroupExitIntentState.cleanupPending,
                groupId: sharedGroup,
              ),
            )
            ..seed(
              _intent(
                GroupExitIntentState.cleanupPending,
                groupId: unrelatedGroup,
              ),
            );
      final runner = _cleanupOnlyRunner(intentRepo);

      final enqueueTrigger = runner.processGroup(sharedGroup);
      await intentRepo.firstBlockedLoadEntered.future;
      final startupTrigger = runner.processAll();
      final rejoinTrigger = runner.processGroup(sharedGroup);
      final resumeTrigger = runner.processAll();
      final manualRetryTrigger = runner.processGroup(sharedGroup);

      await intentRepo.unrelatedCleanupCompleted.future.timeout(
        const Duration(seconds: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        intentRepo.blockedLoadStarts,
        1,
        reason: 'all five trigger paths must enter one same-group tail',
      );
      expect(intentRepo.maxConcurrentBlockedLoads, 1);
      intentRepo.releaseBlockedLoads.complete();

      final triggerResults = await Future.wait<Object?>(<Future<Object?>>[
        enqueueTrigger,
        startupTrigger,
        rejoinTrigger,
        resumeTrigger,
        manualRetryTrigger,
      ]).timeout(const Duration(seconds: 2));
      expect(
        (triggerResults.first as GroupExitIntentProcessResult).status,
        GroupExitIntentProcessStatus.completed,
      );
      expect(await intentRepo.forGroup(sharedGroup), isNull);
      expect(await intentRepo.forGroup(unrelatedGroup), isNull);
      expect(intentRepo.maxConcurrentBlockedLoads, 1);

      const failingGroup = 'group-transient-failure';
      const healthyGroup = 'group-healthy';
      intentRepo
        ..seed(
          _intent(GroupExitIntentState.cleanupPending, groupId: failingGroup),
        )
        ..seed(
          _intent(GroupExitIntentState.cleanupPending, groupId: healthyGroup),
        )
        ..failNextLoadFor.add(failingGroup);

      final isolated = await runner.processAll();
      expect(
        isolated[failingGroup]!.status,
        GroupExitIntentProcessStatus.failed,
      );
      expect(isolated[failingGroup]!.cause, isA<StateError>());
      expect(
        isolated[healthyGroup]!.status,
        GroupExitIntentProcessStatus.completed,
      );
      expect(await intentRepo.forGroup(healthyGroup), isNull);

      expect(
        (await runner
                .processGroup(failingGroup)
                .timeout(const Duration(seconds: 2)))
            .status,
        GroupExitIntentProcessStatus.completed,
        reason: 'a failed processAll turn must release the keyed tail',
      );
      expect(await intentRepo.forGroup(failingGroup), isNull);
    },
  );
}
