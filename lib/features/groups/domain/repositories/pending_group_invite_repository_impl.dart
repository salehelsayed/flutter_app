import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_consumption.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_revocation.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package_tombstone.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';

import 'pending_group_invite_repository.dart';

class PendingGroupInviteRepositoryImpl implements PendingGroupInviteRepository {
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertPendingGroupInvite;
  final Future<List<Map<String, Object?>>> Function() dbLoadPendingGroupInvites;
  final Future<Map<String, Object?>?> Function(String groupId)
  dbLoadPendingGroupInvite;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertGroupInviteRevocation;
  final Future<Map<String, Object?>?> Function(String inviteId)
  dbLoadGroupInviteRevocation;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertGroupInviteConsumption;
  final Future<Map<String, Object?>?> Function(String inviteId)
  dbLoadGroupInviteConsumption;
  final Future<void> Function(Map<String, Object?> row)
  dbUpsertGroupWelcomeKeyPackageTombstone;
  final Future<Map<String, Object?>?> Function({
    required String packageId,
    required String recipientDeviceId,
    required String groupId,
  })
  dbLoadGroupWelcomeKeyPackageTombstone;
  final Future<void> Function(String groupId) dbDeletePendingGroupInvite;
  final Future<int> Function(String cutoff) dbDeleteExpiredPendingGroupInvites;
  final Future<int> Function(String cutoff)
  dbDeleteExpiredGroupInviteRevocations;
  final Future<int> Function(String cutoff)
  dbDeleteExpiredGroupInviteConsumptions;
  final Future<int> Function(String cutoff)
  dbDeleteExpiredGroupWelcomeKeyPackageTombstones;

  PendingGroupInviteRepositoryImpl({
    required this.dbUpsertPendingGroupInvite,
    required this.dbLoadPendingGroupInvites,
    required this.dbLoadPendingGroupInvite,
    required this.dbUpsertGroupInviteRevocation,
    required this.dbLoadGroupInviteRevocation,
    required this.dbUpsertGroupInviteConsumption,
    required this.dbLoadGroupInviteConsumption,
    required this.dbUpsertGroupWelcomeKeyPackageTombstone,
    required this.dbLoadGroupWelcomeKeyPackageTombstone,
    required this.dbDeletePendingGroupInvite,
    required this.dbDeleteExpiredPendingGroupInvites,
    required this.dbDeleteExpiredGroupInviteRevocations,
    required this.dbDeleteExpiredGroupInviteConsumptions,
    required this.dbDeleteExpiredGroupWelcomeKeyPackageTombstones,
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
  Future<void> saveRevokedInvite(GroupInviteRevocation revocation) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_REPO_SAVE_START',
      details: {
        'inviteId': revocation.inviteId.length > 8
            ? revocation.inviteId.substring(0, 8)
            : revocation.inviteId,
      },
    );

    await dbUpsertGroupInviteRevocation(revocation.toMap());

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_REVOCATION_REPO_SAVE_SUCCESS',
      details: {
        'inviteId': revocation.inviteId.length > 8
            ? revocation.inviteId.substring(0, 8)
            : revocation.inviteId,
      },
    );
  }

  @override
  Future<void> saveConsumedInvite(GroupInviteConsumption consumption) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_CONSUMPTION_REPO_SAVE_START',
      details: {
        'inviteId': consumption.inviteId.length > 8
            ? consumption.inviteId.substring(0, 8)
            : consumption.inviteId,
      },
    );

    await dbUpsertGroupInviteConsumption(consumption.toMap());

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_INVITE_CONSUMPTION_REPO_SAVE_SUCCESS',
      details: {
        'inviteId': consumption.inviteId.length > 8
            ? consumption.inviteId.substring(0, 8)
            : consumption.inviteId,
      },
    );
  }

  @override
  Future<void> saveWelcomeKeyPackageTombstone(
    GroupWelcomeKeyPackageTombstone tombstone,
  ) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_REPO_SAVE_START',
      details: {
        'packageId': tombstone.packageId.length > 8
            ? tombstone.packageId.substring(0, 8)
            : tombstone.packageId,
      },
    );

    await dbUpsertGroupWelcomeKeyPackageTombstone(tombstone.toMap());

    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_REPO_SAVE_SUCCESS',
      details: {
        'packageId': tombstone.packageId.length > 8
            ? tombstone.packageId.substring(0, 8)
            : tombstone.packageId,
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
  Future<GroupInviteRevocation?> getRevokedInvite(String inviteId) async {
    final row = await dbLoadGroupInviteRevocation(inviteId);
    if (row == null) {
      return null;
    }
    return GroupInviteRevocation.fromMap(row);
  }

  @override
  Future<GroupInviteConsumption?> getConsumedInvite(String inviteId) async {
    final row = await dbLoadGroupInviteConsumption(inviteId);
    if (row == null) {
      return null;
    }
    return GroupInviteConsumption.fromMap(row);
  }

  @override
  Future<GroupWelcomeKeyPackageTombstone?> getWelcomeKeyPackageTombstone({
    required String packageId,
    required String recipientDeviceId,
    required String groupId,
  }) async {
    final row = await dbLoadGroupWelcomeKeyPackageTombstone(
      packageId: packageId,
      recipientDeviceId: recipientDeviceId,
      groupId: groupId,
    );
    if (row == null) {
      return null;
    }
    return GroupWelcomeKeyPackageTombstone.fromMap(row);
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

  @override
  Future<int> deleteExpiredRevokedInvites(DateTime now) async {
    final cutoff = now.toUtc().toIso8601String();
    return dbDeleteExpiredGroupInviteRevocations(cutoff);
  }

  @override
  Future<int> deleteExpiredConsumedInvites(DateTime now) async {
    final cutoff = now.toUtc().toIso8601String();
    return dbDeleteExpiredGroupInviteConsumptions(cutoff);
  }

  @override
  Future<int> deleteExpiredWelcomeKeyPackageTombstones(DateTime now) async {
    final cutoff = now.toUtc().toIso8601String();
    return dbDeleteExpiredGroupWelcomeKeyPackageTombstones(cutoff);
  }
}
