import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/pending_group_invite_repository.dart';

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

class GroupMessageNotificationDisplayEligibility {
  final bool shouldDisplay;
  final String reason;

  const GroupMessageNotificationDisplayEligibility._({
    required this.shouldDisplay,
    required this.reason,
  });

  const GroupMessageNotificationDisplayEligibility.allowCurrentMember()
    : this._(shouldDisplay: true, reason: 'current_member');

  const GroupMessageNotificationDisplayEligibility.suppressed(String reason)
    : this._(shouldDisplay: false, reason: reason);
}

Future<GroupNotificationRouteResolution> resolveGroupNotificationRouteTarget({
  required String groupId,
  required GroupRepository groupRepo,
  PendingGroupInviteRepository? pendingInviteRepo,
  Future<void> Function()? drainOfflineInbox,
  String? localPeerId,
}) async {
  final normalizedLocalPeerId = localPeerId?.trim();
  final requiresCurrentLocalMembership =
      normalizedLocalPeerId != null && normalizedLocalPeerId.isNotEmpty;

  Future<GroupNotificationRouteResolution?> resolveCurrentState() async {
    final existingGroup = await groupRepo.getGroup(groupId);
    if (existingGroup != null) {
      if (!requiresCurrentLocalMembership) {
        return GroupNotificationRouteResolution.group(existingGroup);
      }
      final localMember = await groupRepo.getMember(
        groupId,
        normalizedLocalPeerId,
      );
      if (localMember != null) {
        return GroupNotificationRouteResolution.group(existingGroup);
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
    if (localMember != null) {
      return const GroupMessageNotificationDisplayEligibility.allowCurrentMember();
    }
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
