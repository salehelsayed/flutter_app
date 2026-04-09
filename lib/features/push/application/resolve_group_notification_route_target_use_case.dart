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
}) async {
  final existingGroup = await groupRepo.getGroup(groupId);
  if (existingGroup != null) {
    return GroupNotificationRouteResolution.group(existingGroup);
  }

  final existingPendingInvite = await pendingInviteRepo?.getPendingInvite(
    groupId,
  );
  if (existingPendingInvite != null) {
    return GroupNotificationRouteResolution.pendingInvite(
      existingPendingInvite,
    );
  }

  if (drainOfflineInbox == null) {
    return const GroupNotificationRouteResolution.missing();
  }

  await drainOfflineInbox();

  final recoveredGroup = await groupRepo.getGroup(groupId);
  if (recoveredGroup != null) {
    return GroupNotificationRouteResolution.group(recoveredGroup);
  }

  final recoveredPendingInvite = await pendingInviteRepo?.getPendingInvite(
    groupId,
  );
  if (recoveredPendingInvite != null) {
    return GroupNotificationRouteResolution.pendingInvite(
      recoveredPendingInvite,
    );
  }

  return const GroupNotificationRouteResolution.missing();
}
