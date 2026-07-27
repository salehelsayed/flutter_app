import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_rejoin_state_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fakes/in_memory_group_message_repository.dart';
import '../fakes/in_memory_group_repository.dart';
import 'durable_group_exit_driver.dart';

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
    required GroupPendingBroadcast? roleBroadcast,
    required this.intentRepository,
    required this.pendingRepository,
    required this.coordinator,
    this.runner,
    this.driver,
    GroupRepository? surfaceGroupRepository,
    GroupMessageRepository? surfaceMessageRepository,
    Future<void> Function()? beforeSurfaceCleanupProjection,
  }) : _roleBroadcast = roleBroadcast,
       _surfaceGroupRepository = surfaceGroupRepository,
       _surfaceMessageRepository = surfaceMessageRepository,
       _beforeSurfaceCleanupProjection = beforeSurfaceCleanupProjection;

  final Database database;
  final String groupId;
  final String selfPeerId;
  final DateTime selfJoinedAt;
  final GroupPendingBroadcast? _roleBroadcast;
  final GroupExitIntentRepository intentRepository;
  final GroupPendingBroadcastRepository pendingRepository;
  final GroupExitIntentCoordinator coordinator;
  final GroupExitIntentRunner? runner;
  final DurableGroupExitDriver? driver;
  final GroupRepository? _surfaceGroupRepository;
  final GroupMessageRepository? _surfaceMessageRepository;
  final Future<void> Function()? _beforeSurfaceCleanupProjection;

  int uiSnapshotLoads = 0;
  int requestLeaveCalls = 0;
  int requestLeaveCompletions = 0;
  int queueLeaveCalls = 0;
  int queueLeaveCompletions = 0;
  int retryLeaveCalls = 0;
  int retryLeaveCompletions = 0;
  int rolePushAttempts = 0;
  int surfaceCleanupProjections = 0;
  bool roleInsertedAfterSnapshot = false;
  GroupExitIntent? lastObservedIntent;
  GroupExitIntentRequestResult? lastRequestResult;
  GroupExitIntentRequestResult? lastRetryResult;
  Object? lastSurfaceCleanupProjectionError;

  final Set<String> _projectedCleanupGroupIds = <String>{};
  bool _closed = false;

  int get noticePrepareAttempts => driver?.noticePrepareCount ?? 0;
  int get noticeAttemptAttempts => driver?.noticeAttemptCount ?? 0;
  int get rotationAttempts => driver?.rotationAttemptCount ?? 0;
  int get nativeLeaveAttempts => driver?.nativeLeaveCount ?? 0;
  String? get lastPreparedTimelineMessageId =>
      driver?.lastPreparedTimelineMessageId;

  /// The injected post-snapshot role row for the original PB264 race fixture.
  ///
  /// Surface-mode harnesses do not inject such a row and should not read this
  /// property.
  GroupPendingBroadcast get roleBroadcast =>
      _roleBroadcast ??
      (throw StateError('This durable surface has no injected role row.'));

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

  /// Creates the production-shaped durable runner used by wired Leave surfaces.
  ///
  /// The durable intent, pending notice, and timeline message live in a real
  /// v103 SQLite database, and one production [GroupRepositoryImpl] owns every
  /// durable workflow phase. External bridge/P2P outcomes remain injected. A
  /// detached presentation repository is projected clean only after the exact
  /// SQLite intent and group parent have disappeared.
  static Future<DurableGroupExitSurfaceHarness> createForSurface({
    required String groupId,
    required Bridge bridge,
    required GroupRepository groupRepository,
    required IdentityRepository identityRepository,
    GroupRepository? durableSeedGroupRepository,
    GroupMessageRepository? messageRepository,
    GroupKeyInfo? fallbackDurableKey,
    Future<bool> Function(String peerId, String message)? sendP2PMessage,
    Future<bool> Function(String peerId, String message)?
    storeP2PMessageInInbox,
    DateTime Function()? now,
    GroupExitIntentRepository Function(GroupExitIntentRepository repository)?
    coordinatorIntentRepositoryDecorator,
    Future<void> Function(GroupExitIntent intent)? beforeNativeLeave,
    Future<void> Function()? beforeSurfaceCleanupProjection,
    AfterDurableGroupExitNoticeAttempt? afterNoticeAttempt,
  }) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null || identity.peerId.trim().isEmpty) {
      throw StateError('Current group-exit identity is unavailable.');
    }
    final seedGroupRepository = durableSeedGroupRepository ?? groupRepository;
    final group = await seedGroupRepository.getGroup(groupId);
    if (group == null) {
      throw StateError('Group exit parent is unavailable.');
    }
    final members = await seedGroupRepository.getMembers(groupId);
    final selfMembers = members
        .where((member) => member.peerId == identity.peerId)
        .toList(growable: false);
    if (selfMembers.length != 1) {
      throw StateError('Exact group-exit self membership is unavailable.');
    }
    final selfMember = selfMembers.single;

    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      await runProductionOnCreate(database, 103);
      await database.insert('identity', <String, Object?>{
        'id': 1,
        'peer_id': identity.peerId,
        'public_key': identity.publicKey,
        'private_key': null,
        'mnemonic12': null,
        'username': identity.username,
        'created_at': identity.createdAt,
        'updated_at': identity.updatedAt,
      });
      final durableGroupRepository = _sqliteGroupRepository(
        database,
        groupKeyStore: _MemorySecureKeyStore(),
      );
      await durableGroupRepository.saveGroup(group);
      for (final member in members) {
        await durableGroupRepository.saveMember(member);
      }
      final latestKey = await seedGroupRepository.getLatestKey(groupId);
      final durableKey = latestKey ?? fallbackDurableKey;
      if (durableKey != null) {
        if (durableKey.groupId != groupId) {
          throw StateError(
            'Fallback durable group key belongs to another group.',
          );
        }
        await durableGroupRepository.saveKey(durableKey);
      }
      if (messageRepository != null) {
        await _seedDurableMessages(
          database: database,
          groupId: groupId,
          messageRepository: messageRepository,
        );
      }

      final intentRepository = _sqliteIntentRepository(database);
      final pendingRepository = _sqlitePendingRepository(database);
      var deterministicTick = 0;
      final currentNow =
          now ??
          () => DateTime.utc(
            2026,
            7,
            26,
            12,
          ).add(Duration(microseconds: deterministicTick++));
      var nextId = 0;
      final driver = DurableGroupExitDriver.compose(
        bridge: bridge,
        intentRepository: intentRepository,
        pendingRepository: pendingRepository,
        groupRepository: durableGroupRepository,
        identityRepository: identityRepository,
        loadMessage: (messageId) async {
          final row = await dbLoadGroupMessage(database, messageId);
          return row == null
              ? null
              : GroupMessage.fromMap(Map<String, dynamic>.from(row));
        },
        rePushPendingBroadcast: (_) async => false,
        coordinatorIntentRepository: coordinatorIntentRepositoryDecorator?.call(
          intentRepository,
        ),
        newId: () => 'durable-exit-surface-${++nextId}',
        now: () => currentNow().toUtc(),
        sendP2PMessage: sendP2PMessage,
        storeP2PMessageInInbox: storeP2PMessageInInbox,
        afterNoticeAttempt: afterNoticeAttempt,
        beforeNativeLeave: beforeNativeLeave,
      );
      final harness = DurableGroupExitSurfaceHarness._(
        database: database,
        groupId: groupId,
        selfPeerId: selfMember.peerId,
        selfJoinedAt: selfMember.joinedAt.toUtc(),
        roleBroadcast: null,
        intentRepository: intentRepository,
        pendingRepository: pendingRepository,
        coordinator: driver.coordinator,
        runner: driver.runner,
        driver: driver,
        surfaceGroupRepository: groupRepository,
        surfaceMessageRepository: messageRepository,
        beforeSurfaceCleanupProjection: beforeSurfaceCleanupProjection,
      );
      return harness;
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  /// Installs concrete action/access authority and the snapshot-race injector.
  void install() {
    setGroupExitIntentActionSinks(
      resolveSnapshot: (requestedGroupId) async {
        final identity = await coordinator.identityRepository.loadIdentity();
        final selfPeerId = identity?.peerId.trim();
        if (selfPeerId == null || selfPeerId.isEmpty) {
          throw StateError('Current group-exit identity is unavailable.');
        }
        return resolveGroupExitSnapshot(
          groupRepo: coordinator.groupRepository,
          groupId: requestedGroupId,
          selfPeerId: selfPeerId,
          messageRepo: _surfaceMessageRepository,
          loadPendingBroadcasts: _loadUiSnapshot,
        );
      },
      requestLeave: requestLeaveForTest,
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
      retry: retryForTest,
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
    final role = _roleBroadcast;
    if (role != null &&
        !roleInsertedAfterSnapshot &&
        requestedGroupId == groupId) {
      await pendingRepository.enqueue(role);
      roleInsertedAfterSnapshot = true;
    }
    return snapshot;
  }

  Future<GroupExitIntentRequestResult> requestLeaveForTest([
    String? requestedGroupId,
  ]) async {
    final targetGroupId = requestedGroupId ?? groupId;
    requestLeaveCalls++;
    try {
      final currentDriver = driver;
      final result = currentDriver == null
          ? await coordinator.requestLeave(targetGroupId)
          : (await currentDriver.requestLeave(targetGroupId)).requestResult;
      lastRequestResult = result;
      await _observeAndProjectCommittedCleanup(targetGroupId, result: result);
      return result;
    } finally {
      requestLeaveCompletions++;
    }
  }

  Future<GroupExitIntentRequestResult> retryForTest([
    String? requestedGroupId,
  ]) async {
    final targetGroupId = requestedGroupId ?? groupId;
    retryLeaveCalls++;
    try {
      final hadIntent = await intentRepository.forGroup(targetGroupId) != null;
      final currentDriver = driver;
      final result = currentDriver == null
          ? await coordinator.retry(targetGroupId)
          : (await currentDriver.retry(targetGroupId)).requestResult;
      lastRetryResult = result;
      await _observeAndProjectCommittedCleanup(
        targetGroupId,
        result: result,
        hadIntentBefore: hadIntent,
      );
      return result;
    } finally {
      retryLeaveCompletions++;
    }
  }

  Future<void> _observeAndProjectCommittedCleanup(
    String requestedGroupId, {
    required GroupExitIntentRequestResult result,
    bool hadIntentBefore = false,
  }) async {
    final current = await intentRepository.forGroup(requestedGroupId);
    lastObservedIntent = current ?? result.intent;
    if (current != null ||
        (!hadIntentBefore && result.intent == null) ||
        _projectedCleanupGroupIds.contains(requestedGroupId)) {
      return;
    }
    if (await hasDurableGroup(requestedGroupId)) {
      // Exact retirement for terminal/newer membership also removes an intent,
      // but it deliberately leaves the durable group parent untouched. Only
      // the cleanup transaction removes both, so absence of both is the
      // fixture's non-fabricated projection authority.
      return;
    }
    final surfaceGroupRepository = _surfaceGroupRepository;
    if (surfaceGroupRepository == null) return;
    if (!_projectedCleanupGroupIds.add(requestedGroupId)) return;

    // The durable runner is the sole phase/result authority. This bounded
    // projection exists only because wired-widget repositories are detached
    // from the harness SQLite database. Its fake-only CAS cannot run while an
    // exact retry intent remains and never yields between membership
    // comparison and paired group/message deletion.
    try {
      await _beforeSurfaceCleanupProjection?.call();
      if (surfaceGroupRepository is! InMemoryGroupRepository) {
        throw StateError(
          'Detached cleanup projection requires an in-memory group surface.',
        );
      }
      final surfaceMessageRepository = _surfaceMessageRepository;
      if (surfaceMessageRepository != null &&
          surfaceMessageRepository is! InMemoryGroupMessageRepository) {
        throw StateError(
          'Detached cleanup projection requires an in-memory message surface.',
        );
      }
      final projected = surfaceGroupRepository
          .deleteExactMembershipSurfaceForTest(
            groupId: requestedGroupId,
            selfPeerId: selfPeerId,
            selfJoinedAt: selfJoinedAt,
            deleteMessagesForGroup:
                surfaceMessageRepository is InMemoryGroupMessageRepository
                ? surfaceMessageRepository
                      .deleteMessagesForGroupSynchronouslyForTest
                : null,
          );
      if (!projected) {
        // The detached surface moved to a newer membership generation after
        // durable completion. Refusal preserves that group and its history.
        return;
      }
      surfaceCleanupProjections++;
    } catch (error) {
      // Durable completion is the result authority. Detached presentation
      // cleanup is observable for assertions but cannot replace that result.
      lastSurfaceCleanupProjectionError = error;
    }
  }

  Future<GroupExitIntent?> loadIntent([String? requestedGroupId]) =>
      intentRepository.forGroup(requestedGroupId ?? groupId);

  Future<bool> hasDurableGroup([String? requestedGroupId]) async {
    final rows = await database.query(
      'groups',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[requestedGroupId ?? groupId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<GroupMessage?> loadDurableTimelineMessage() async {
    final timelineMessageId = lastPreparedTimelineMessageId;
    if (timelineMessageId == null) return null;
    return loadDurableMessage(timelineMessageId);
  }

  Future<GroupMessage?> loadDurableMessage(String messageId) async {
    final row = await dbLoadGroupMessage(database, messageId);
    return row == null
        ? null
        : GroupMessage.fromMap(Map<String, dynamic>.from(row));
  }

  Future<List<GroupMessage>> loadDurableMessages([
    String? requestedGroupId,
  ]) async {
    final rows = await dbLoadGroupMessagesPage(
      database,
      requestedGroupId ?? groupId,
      limit: 500,
    );
    return rows
        .map((row) => GroupMessage.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<void> close() async {
    setGroupPendingBroadcastAccessSinks();
    setGroupExitIntentAccessSinks();
    setGroupExitIntentActionSinks();
    if (_closed) return;
    _closed = true;
    await database.close();
  }
}

Future<void> _seedDurableMessages({
  required Database database,
  required String groupId,
  required GroupMessageRepository messageRepository,
}) async {
  const pageSize = 200;
  var offset = 0;
  while (true) {
    final page = await messageRepository.getMessagesPage(
      groupId,
      limit: pageSize,
      offset: offset,
    );
    for (final message in page) {
      final inserted = await dbInsertGroupMessage(database, message.toMap());
      if (!inserted) {
        throw StateError(
          'Durable surface history seed was refused for ${message.id}.',
        );
      }
    }
    if (page.length < pageSize) return;
    offset += page.length;
  }
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

GroupRepositoryImpl _sqliteGroupRepository(
  Database database, {
  required SecureKeyStore groupKeyStore,
}) => GroupRepositoryImpl(
  dbInsertGroup: (row) => dbInsertGroup(database, row),
  dbLoadAllGroups: () => dbLoadAllGroups(database),
  dbLoadGroup: (id) => dbLoadGroup(database, id),
  dbUpdateGroup: (row) => dbUpdateGroup(database, row),
  dbDeleteGroup: (id) => dbDeleteGroup(database, id),
  dbLoadActiveGroups: () => dbLoadActiveGroups(database),
  dbArchiveGroup: (id) => dbArchiveGroup(database, id),
  dbUnarchiveGroup: (id) => dbUnarchiveGroup(database, id),
  dbInsertGroupMember: (row) => dbInsertGroupMember(database, row),
  dbLoadAllGroupMembers: (groupId) => dbLoadAllGroupMembers(database, groupId),
  dbLoadGroupMember: (groupId, peerId) =>
      dbLoadGroupMember(database, groupId, peerId),
  dbUpdateGroupMemberRole: (groupId, peerId, role) =>
      dbUpdateGroupMemberRole(database, groupId, peerId, role),
  dbDeleteGroupMember: (groupId, peerId) =>
      dbDeleteGroupMember(database, groupId, peerId),
  dbDeleteAllGroupMembers: (groupId) =>
      dbDeleteAllGroupMembers(database, groupId),
  dbLoadGroupRejoinStatesFn: () => dbLoadGroupRejoinStates(database),
  dbRecordGroupRejoinFailureFn: (groupId, {required nextEligibleAtMs}) =>
      dbRecordGroupRejoinFailure(
        database,
        groupId,
        nextEligibleAtMs: nextEligibleAtMs,
      ),
  dbClearGroupRejoinStateFn: (groupId) =>
      dbClearGroupRejoinState(database, groupId),
  dbForceGroupRejoinEligibleFn: (groupId) =>
      dbForceGroupRejoinEligible(database, groupId),
  dbInsertGroupKey: (row) => dbInsertGroupKey(database, row),
  dbLoadLatestGroupKey: (groupId) => dbLoadLatestGroupKey(database, groupId),
  dbLoadGroupKeyByGeneration: (groupId, generation) =>
      dbLoadGroupKeyByGeneration(database, groupId, generation),
  dbDeleteAllGroupKeys: (groupId) => dbDeleteAllGroupKeys(database, groupId),
  dbLoadAllGroupKeys: (groupId) => dbLoadAllGroupKeys(database, groupId),
  dbDeleteGroupKeysBeforeGeneration: (groupId, minKeyGenerationToKeep) =>
      dbDeleteGroupKeysBeforeGeneration(
        database,
        groupId,
        minKeyGenerationToKeep,
      ),
  dbUpsertPendingGroupKeyRotation: (row) =>
      dbUpsertPendingGroupKeyRotation(database, row),
  dbLoadPendingGroupKeyRotation: (groupId) =>
      dbLoadPendingGroupKeyRotation(database, groupId),
  dbDeletePendingGroupKeyRotation: (groupId, keyGeneration) =>
      dbDeletePendingGroupKeyRotation(database, groupId, keyGeneration),
  dbDeletePendingGroupKeyRotations: (groupId) =>
      dbDeletePendingGroupKeyRotations(database, groupId),
  groupKeyStore: groupKeyStore,
  dbHasGroupExitCleanupPending: (groupId) async {
    final row = await dbLoadGroupExitIntentForGroup(database, groupId);
    return row?['state'] == 'cleanup_pending';
  },
);

class _MemorySecureKeyStore implements SecureKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
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
