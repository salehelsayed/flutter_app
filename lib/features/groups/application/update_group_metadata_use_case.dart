import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef BeforePersistGroupMetadataUpdate =
    FutureOr<void> Function(GroupModel updated);

typedef CurrentGroupMetadataAuthorityCheck =
    Future<bool> Function(GroupModel current);

Future<GroupModel> updateGroupMetadata({
  required GroupRepository groupRepo,
  required String groupId,
  required String name,
  String? description,
  String? avatarBlobId,
  String? avatarMime,
  String? avatarPath,
  DateTime? eventAt,
  BeforePersistGroupMetadataUpdate? beforePersist,
  CurrentGroupMetadataAuthorityCheck? currentAuthorityCheck,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_UPDATE_METADATA_USE_CASE_BEGIN',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'hasDescription': description != null,
      'hasAvatar': avatarBlobId != null && avatarMime != null,
    },
  );

  if (isGroupRecoveryInProgress()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_METADATA_USE_CASE_RECOVERY_PENDING',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      },
    );
    throw StateError(groupRecoveryPendingError);
  }

  final group = await groupRepo.getGroup(groupId);
  if (group == null) {
    throw StateError('Group not found: $groupId');
  }

  if (group.isDissolved || group.selfRemovedAt != null) {
    throw StateError('Group is no longer active');
  }

  if (group.myRole != GroupRole.admin) {
    emitFlowEvent(
      layer: 'FL',
      event: 'GROUP_UPDATE_METADATA_USE_CASE_NOT_ADMIN',
      details: {'role': group.myRole.toValue()},
    );
    throw StateError('Only admins can edit group details');
  }

  final resolvedName = name.trim();
  if (resolvedName.isEmpty) {
    throw StateError('Group name cannot be empty');
  }

  final trimmedDescription = description?.trim();
  final resolvedDescription =
      trimmedDescription == null || trimmedDescription.isEmpty
      ? null
      : trimmedDescription;
  final resolvedEventAt = (eventAt ?? DateTime.now()).toUtc();

  final updated = group.copyWith(
    name: resolvedName,
    description: resolvedDescription,
    avatarBlobId: avatarBlobId,
    avatarMime: avatarMime,
    avatarPath: avatarPath,
    lastMetadataEventAt: resolvedEventAt,
  );
  await beforePersist?.call(updated);

  final committed = await runGroupMembershipMutationLocked<GroupModel>(
    groupId: groupId,
    action: () async {
      final current = await groupRepo.getGroup(groupId);
      if (current == null ||
          current.isDissolved ||
          current.selfRemovedAt != null) {
        throw StateError('Group is no longer active');
      }
      if (current.myRole != GroupRole.admin) {
        throw StateError('Only admins can edit group details');
      }
      if (currentAuthorityCheck != null &&
          !await currentAuthorityCheck(current)) {
        throw StateError('Group metadata authority changed');
      }
      final exactUpdate = current.copyWith(
        name: resolvedName,
        description: resolvedDescription,
        avatarBlobId: avatarBlobId,
        avatarMime: avatarMime,
        avatarPath: avatarPath,
        lastMetadataEventAt: resolvedEventAt,
      );
      await groupRepo.updateGroup(exactUpdate);
      return exactUpdate;
    },
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_UPDATE_METADATA_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'hasAvatar': avatarBlobId != null && avatarMime != null,
    },
  );

  return committed;
}
