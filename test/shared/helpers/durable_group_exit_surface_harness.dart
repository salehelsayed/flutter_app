import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mutation-sensitive presentation fixture for TC-264-16.
///
/// The first UI classifier reads an actually-empty SQLite snapshot. Only after
/// that read returns does this fixture insert a durable role row. Presentation
/// then crosses the process-wide sink into the real coordinator, keyed pending
/// runner, repository implementations, and v103 helpers. This keeps widget
/// appearance from being a vacuous substitute for persisted intent identity.
class DurableGroupExitSurfaceHarness {
  DurableGroupExitSurfaceHarness._({
    required this.database,
    required this.groupId,
    required this.selfPeerId,
    required this.selfJoinedAt,
    required this.roleBroadcast,
    required this.intentRepository,
    required this.pendingRepository,
    required this.coordinator,
  });

  final Database database;
  final String groupId;
  final String selfPeerId;
  final DateTime selfJoinedAt;
  final GroupPendingBroadcast roleBroadcast;
  final GroupExitIntentRepository intentRepository;
  final GroupPendingBroadcastRepository pendingRepository;
  final GroupExitIntentCoordinator coordinator;

  int uiSnapshotLoads = 0;
  int requestLeaveCalls = 0;
  int requestLeaveCompletions = 0;
  int queueLeaveCalls = 0;
  int queueLeaveCompletions = 0;
  int rolePushAttempts = 0;
  bool roleInsertedAfterSnapshot = false;

  static Future<DurableGroupExitSurfaceHarness> create({
    required GroupModel group,
    required GroupMember selfMember,
    required GroupRepository groupRepository,
    required IdentityRepository identityRepository,
    required String recipientPeerId,
  }) async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await runProductionOnCreate(database, 103);
    await database.insert('identity', <String, Object?>{
      'id': 1,
      'peer_id': selfMember.peerId,
      'public_key': '',
      'private_key': null,
      'mnemonic12': null,
      'username': selfMember.username,
      'created_at': group.createdAt.toUtc().toIso8601String(),
      'updated_at': group.createdAt.toUtc().toIso8601String(),
    });
    await database.insert('groups', group.toMap());
    await database.insert('group_members', selfMember.toMap());

    final intentRepository = _sqliteIntentRepository(database);
    final pendingRepository = _sqlitePendingRepository(database);
    final processor = _KeepQueuedProcessor();
    late DurableGroupExitSurfaceHarness harness;
    var nextId = 0;
    final coordinator = GroupExitIntentCoordinator(
      intentRepository: intentRepository,
      pendingRepository: pendingRepository,
      pendingBroadcastRunner: GroupPendingBroadcastRunner(
        repository: pendingRepository,
        rePush: (_) async {
          harness.rolePushAttempts++;
          return false;
        },
      ),
      processor: processor,
      groupRepository: groupRepository,
      identityRepository: identityRepository,
      newId: () => 'pb264-surface-${++nextId}',
      now: () => DateTime.utc(2026, 7, 21, 12),
    );
    final roleAt = group.createdAt.toUtc().add(const Duration(minutes: 1));
    harness = DurableGroupExitSurfaceHarness._(
      database: database,
      groupId: group.id,
      selfPeerId: selfMember.peerId,
      selfJoinedAt: selfMember.joinedAt.toUtc(),
      roleBroadcast: GroupPendingBroadcast(
        id: 'pb264-surface-role-${group.id}',
        groupId: group.id,
        kind: groupPendingBroadcastKindMemberRoleUpdated,
        sysText: '{"kind":"member_role_updated"}',
        recipientPeerIds: <String>[recipientPeerId],
        eventAt: roleAt,
        sourceMessageId: 'pb264-surface-role-source-${group.id}',
        createdAt: roleAt,
        updatedAt: roleAt,
      ),
      intentRepository: intentRepository,
      pendingRepository: pendingRepository,
      coordinator: coordinator,
    );
    return harness;
  }

  /// Installs concrete action/access authority and the snapshot-race injector.
  void install() {
    setGroupExitIntentActionSinks(
      requestLeave: (requestedGroupId) async {
        requestLeaveCalls++;
        try {
          return await coordinator.requestLeave(requestedGroupId);
        } finally {
          requestLeaveCompletions++;
        }
      },
      queueLeaveWhenSyncCompletes: (requestedGroupId) async {
        queueLeaveCalls++;
        try {
          return await coordinator.queueLeaveWhenSyncCompletes(
            requestedGroupId,
          );
        } finally {
          queueLeaveCompletions++;
        }
      },
      retry: coordinator.retry,
      cancelQueued: coordinator.cancelQueued,
    );
    setGroupExitIntentAccessSinks(
      forGroup: intentRepository.forGroup,
      all: intentRepository.all,
    );
    setGroupPendingBroadcastAccessSinks(loadForGroup: _loadUiSnapshot);
  }

  Future<List<GroupPendingBroadcast>> _loadUiSnapshot(
    String requestedGroupId,
  ) async {
    uiSnapshotLoads++;
    final snapshot = await pendingRepository.forGroup(requestedGroupId);
    if (!roleInsertedAfterSnapshot && requestedGroupId == groupId) {
      await pendingRepository.enqueue(roleBroadcast);
      roleInsertedAfterSnapshot = true;
    }
    return snapshot;
  }

  Future<GroupExitIntent?> loadIntent() => intentRepository.forGroup(groupId);

  Future<void> close() => database.close();
}

/// Alternates the real event loop used by sqflite FFI with deterministic
/// widget frames until a durable surface action reaches its observed state.
Future<void> pumpDurableGroupExitUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump();
  }
  if (!condition()) {
    throw StateError('Timed out driving durable group-exit widget work.');
  }
}

class _KeepQueuedProcessor implements GroupExitIntentProcessor {
  @override
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  }) async => const GroupExitIntentProcessResult(
    status: GroupExitIntentProcessStatus.waitingForRoleSync,
  );

  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async =>
      const <String, GroupExitIntentProcessResult>{};
}

GroupExitIntentRepository _sqliteIntentRepository(Database database) =>
    GroupExitIntentRepositoryImpl(
      dbLoadForGroup: (groupId) =>
          dbLoadGroupExitIntentForGroup(database, groupId),
      dbLoadAll: () => dbLoadAllGroupExitIntents(database),
      dbEnqueue: (row) => dbEnqueueGroupExitIntent(database, row),
      dbCancelQueued: ({required expected, required updatedAt}) =>
          dbCancelQueuedGroupExitIntent(
            database,
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
            database,
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
            database,
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
            database,
            expected: expected,
            nextState: nextState,
            updatedAt: updatedAt,
            lastErrorCode: lastErrorCode,
          ),
      dbCleanupOrRetire: ({required expected, required updatedAt}) =>
          dbCleanupOrRetireGroupExitIntent(
            database,
            expected: expected,
            updatedAt: updatedAt,
          ),
      dbRetireExact: (expected) =>
          dbRetireExactGroupExitIntent(database, expected),
      dbTerminalizeForGroup: (groupId) =>
          dbTerminalizeGroupExitIntentForGroup(database, groupId),
    );

GroupPendingBroadcastRepository _sqlitePendingRepository(Database database) =>
    GroupPendingBroadcastRepositoryImpl(
      dbInsert: (row) => dbInsertPendingGroupBroadcast(database, row),
      dbLoadForGroup: (groupId) =>
          dbLoadPendingGroupBroadcastsForGroup(database, groupId),
      dbLoadAll: () => dbLoadAllPendingGroupBroadcasts(database),
      dbCountForGroup: (groupId) =>
          dbCountPendingGroupBroadcastsForGroup(database, groupId),
      dbDelete: (id) => dbDeletePendingGroupBroadcast(database, id),
      dbDeleteIfExact: (expected) =>
          dbDeletePendingGroupBroadcastIfExact(database, expected),
      dbDeleteForGroup: (groupId) =>
          dbDeletePendingGroupBroadcastsForGroup(database, groupId),
    );
