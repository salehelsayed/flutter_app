import 'package:flutter_app/core/database/helpers/group_exit_intents_db_helpers.dart';

import '../models/group_exit_intent.dart';
import '../models/group_message.dart';
import '../models/group_pending_broadcast.dart';
import 'group_exit_intent_repository.dart';

class GroupExitIntentRepositoryImpl implements GroupExitIntentRepository {
  GroupExitIntentRepositoryImpl({
    required this.dbLoadForGroup,
    required this.dbLoadAll,
    required this.dbEnqueue,
    required this.dbCancelQueued,
    required this.dbPrepareLeaveNotice,
    required this.dbCompleteLeaveNoticeAttempt,
    required this.dbAdvance,
    required this.dbCleanupOrRetire,
    required this.dbRetireExact,
    required this.dbTerminalizeForGroup,
  });

  final Future<Map<String, Object?>?> Function(String groupId) dbLoadForGroup;
  final Future<List<Map<String, Object?>>> Function() dbLoadAll;
  final Future<DbGroupExitIntentMutationResult> Function(
    Map<String, Object?> row,
  )
  dbEnqueue;
  final Future<DbGroupExitIntentMutationResult> Function({
    required Map<String, Object?> expected,
    required String updatedAt,
  })
  dbCancelQueued;
  final Future<DbGroupExitIntentMutationResult> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> timelineRow,
    required Map<String, Object?> pendingBroadcastRow,
    required String updatedAt,
  })
  dbPrepareLeaveNotice;
  final Future<DbGroupExitIntentMutationResult> Function({
    required Map<String, Object?> expected,
    required Map<String, Object?> pendingBroadcastRow,
    required String completionCode,
    required String updatedAt,
  })
  dbCompleteLeaveNoticeAttempt;
  final Future<DbGroupExitIntentMutationResult> Function({
    required Map<String, Object?> expected,
    required String nextState,
    required String updatedAt,
    String? lastErrorCode,
  })
  dbAdvance;
  final Future<DbGroupExitIntentMutationResult> Function({
    required Map<String, Object?> expected,
    required String updatedAt,
  })
  dbCleanupOrRetire;
  final Future<DbGroupExitIntentMutationResult> Function(
    Map<String, Object?> expected,
  )
  dbRetireExact;
  final Future<int> Function(String groupId) dbTerminalizeForGroup;

  @override
  Future<GroupExitIntent?> forGroup(String groupId) async {
    final row = await dbLoadForGroup(groupId);
    return row == null ? null : GroupExitIntent.fromMap(row);
  }

  @override
  Future<List<GroupExitIntent>> all() async {
    final rows = await dbLoadAll();
    return rows.map(GroupExitIntent.fromMap).toList(growable: false);
  }

  @override
  Future<GroupExitIntentMutationResult> enqueue(GroupExitIntent intent) async {
    return _mapResult(await dbEnqueue(intent.toMap()));
  }

  @override
  Future<GroupExitIntentMutationResult> cancelQueued(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    return _mapResult(
      await dbCancelQueued(
        expected: expected.toMap(),
        updatedAt: updatedAt.toUtc().toIso8601String(),
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> prepareLeaveNotice({
    required GroupExitIntent expected,
    required GroupMessage timelineMessage,
    required GroupPendingBroadcast pendingBroadcast,
    required DateTime updatedAt,
  }) async {
    return _mapResult(
      await dbPrepareLeaveNotice(
        expected: expected.toMap(),
        timelineRow: timelineMessage.toMap(),
        pendingBroadcastRow: pendingBroadcast.toMap(),
        updatedAt: updatedAt.toUtc().toIso8601String(),
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> completeLeaveNoticeAttempt({
    required GroupExitIntent expected,
    required GroupPendingBroadcast pendingBroadcast,
    required String completionCode,
    required DateTime updatedAt,
  }) async {
    return _mapResult(
      await dbCompleteLeaveNoticeAttempt(
        expected: expected.toMap(),
        pendingBroadcastRow: pendingBroadcast.toMap(),
        completionCode: completionCode,
        updatedAt: updatedAt.toUtc().toIso8601String(),
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
    return _mapResult(
      await dbAdvance(
        expected: expected.toMap(),
        nextState: nextState.databaseValue,
        updatedAt: updatedAt.toUtc().toIso8601String(),
        lastErrorCode: lastErrorCode,
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> cleanupOrRetire(
    GroupExitIntent expected, {
    required DateTime updatedAt,
  }) async {
    return _mapResult(
      await dbCleanupOrRetire(
        expected: expected.toMap(),
        updatedAt: updatedAt.toUtc().toIso8601String(),
      ),
    );
  }

  @override
  Future<GroupExitIntentMutationResult> retireExact(
    GroupExitIntent expected,
  ) async {
    return _mapResult(await dbRetireExact(expected.toMap()));
  }

  @override
  Future<int> terminalizeForGroup(String groupId) {
    return dbTerminalizeForGroup(groupId);
  }
}

GroupExitIntentMutationResult _mapResult(
  DbGroupExitIntentMutationResult result,
) {
  final current = result.current;
  return GroupExitIntentMutationResult(
    disposition: GroupExitIntentMutationDisposition.values.byName(
      result.disposition.name,
    ),
    current: current == null ? null : GroupExitIntent.fromMap(current),
  );
}
