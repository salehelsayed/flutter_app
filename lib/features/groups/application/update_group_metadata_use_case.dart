import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

typedef BeforePersistGroupMetadataUpdate =
    FutureOr<void> Function(GroupModel updated);

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
  await groupRepo.updateGroup(updated);

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_UPDATE_METADATA_USE_CASE_SUCCESS',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'hasAvatar': avatarBlobId != null && avatarMime != null,
    },
  );

  return updated;
}
