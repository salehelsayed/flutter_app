import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import 'pending_group_invite_repository.dart';

class PendingGroupInviteRepositoryImpl implements PendingGroupInviteRepository {
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertPendingGroupInvite;
  final Future<List<Map<String, Object?>>> Function() dbLoadPendingGroupInvites;
  final Future<Map<String, Object?>?> Function(String groupId)
  dbLoadPendingGroupInvite;
  final Future<void> Function(String groupId) dbDeletePendingGroupInvite;
  final Future<int> Function(String cutoff) dbDeleteExpiredPendingGroupInvites;

  PendingGroupInviteRepositoryImpl({
    required this.dbUpsertPendingGroupInvite,
    required this.dbLoadPendingGroupInvites,
    required this.dbLoadPendingGroupInvite,
    required this.dbDeletePendingGroupInvite,
    required this.dbDeleteExpiredPendingGroupInvites,
  });

  @override
  Future<void> savePendingInvite(PendingGroupInvite invite) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_REPO_SAVE_START',
      details: {
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );

    await dbUpsertPendingGroupInvite(invite.toMap());

    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_GROUP_INVITE_REPO_SAVE_SUCCESS',
      details: {
        'groupId': invite.groupId.length > 8
            ? invite.groupId.substring(0, 8)
            : invite.groupId,
      },
    );
  }

  @override
  Future<List<PendingGroupInvite>> getPendingInvites() async {
    final rows = await dbLoadPendingGroupInvites();
    return rows.map((row) => PendingGroupInvite.fromMap(row)).toList();
  }

  @override
  Future<PendingGroupInvite?> getPendingInvite(String groupId) async {
    final row = await dbLoadPendingGroupInvite(groupId);
    if (row == null) {
      return null;
    }
    return PendingGroupInvite.fromMap(row);
  }

  @override
  Future<void> deletePendingInvite(String groupId) async {
    await dbDeletePendingGroupInvite(groupId);
  }

  @override
  Future<int> deleteExpiredPendingInvites(DateTime now) async {
    final cutoff = now.toUtc().toIso8601String();
    return dbDeleteExpiredPendingGroupInvites(cutoff);
  }
}
