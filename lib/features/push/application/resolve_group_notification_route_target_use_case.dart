import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';

export 'package:flutter_app/features/push/application/group_notification_display_policy.dart'
    show GroupMessageNotificationDisplayEligibility;

class GroupNotificationRouteResolution {
  final GroupModel? group;
  final PendingGroupInvite? pendingInvite;

  const GroupNotificationRouteResolution._({this.group, this.pendingInvite});

  const GroupNotificationRouteResolution.group(GroupModel group)
    : this._(group: group);

  const GroupNotificationRouteResolution.pendingInvite(
    PendingGroupInvite pendingInvite,
  ) : this._(pendingInvite: pendingInvite);

  const GroupNotificationRouteResolution.missing() : this._();

  bool get hasGroup => group != null;
  bool get hasPendingInvite => pendingInvite != null;
}

Future<GroupNotificationRouteResolution> resolveGroupNotificationRouteTarget({
  required String groupId,
  required GroupRepository groupRepo,
  PendingGroupInviteRepository? pendingInviteRepo,
  Future<void> Function()? drainOfflineInbox,
  String? localPeerId,
  bool requireCurrentLocalMembership = false,
}) async {
  final normalizedLocalPeerId = localPeerId?.trim();
  final hasLocalPeerId =
      normalizedLocalPeerId != null && normalizedLocalPeerId.isNotEmpty;
  final requiresCurrentLocalMembership =
      requireCurrentLocalMembership || hasLocalPeerId;

  Future<GroupNotificationRouteResolution?> resolveCurrentState() async {
    final existingGroup = await groupRepo.getGroup(groupId);
    if (existingGroup != null) {
      if (!requiresCurrentLocalMembership) {
        return GroupNotificationRouteResolution.group(existingGroup);
      }
      if (hasLocalPeerId) {
        final localMember = await groupRepo.getMember(
          groupId,
          normalizedLocalPeerId,
        );
        if (localMember != null) {
          return GroupNotificationRouteResolution.group(existingGroup);
        }
      }
    }

    final existingPendingInvite = await pendingInviteRepo?.getPendingInvite(
      groupId,
    );
    if (existingPendingInvite != null) {
      return GroupNotificationRouteResolution.pendingInvite(
        existingPendingInvite,
      );
    }

    return null;
  }

  final existingResolution = await resolveCurrentState();
  if (existingResolution != null) {
    return existingResolution;
  }

  if (drainOfflineInbox == null) {
    return const GroupNotificationRouteResolution.missing();
  }

  await drainOfflineInbox();

  final recoveredResolution = await resolveCurrentState();
  if (recoveredResolution != null) {
    return recoveredResolution;
  }

  return const GroupNotificationRouteResolution.missing();
}

Future<GroupMessageNotificationDisplayEligibility>
resolveGroupMessageNotificationDisplayEligibility({
  required String groupId,
  required GroupRepository groupRepo,
  PendingGroupInviteRepository? pendingInviteRepo,
  required String? localPeerId,
}) async {
  final normalizedLocalPeerId = localPeerId?.trim();
  if (normalizedLocalPeerId == null || normalizedLocalPeerId.isEmpty) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'unknown_local_identity',
    );
  }

  final existingGroup = await groupRepo.getGroup(groupId);
  if (existingGroup != null) {
    final localMember = await groupRepo.getMember(
      groupId,
      normalizedLocalPeerId,
    );
    return evaluateGroupNotificationDisplayPolicy(
      GroupNotificationDisplayPolicyInput(
        groupExists: true,
        hasCurrentLocalMembership: localMember != null,
        groupType: existingGroup.type.toValue(),
        isMuted: existingGroup.isMuted,
        isArchived: existingGroup.isArchived,
        isDissolved: existingGroup.isDissolved,
        hasDissolvedAt: existingGroup.dissolvedAt != null,
        hasSelfRemovedAt: existingGroup.selfRemovedAt != null,
      ),
    );
  }

  final existingPendingInvite = await pendingInviteRepo?.getPendingInvite(
    groupId,
  );
  if (existingPendingInvite != null) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'pending_invite',
    );
  }

  if (existingGroup != null) {
    return const GroupMessageNotificationDisplayEligibility.suppressed(
      'local_member_missing',
    );
  }

  return const GroupMessageNotificationDisplayEligibility.suppressed(
    'group_missing',
  );
}
