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
