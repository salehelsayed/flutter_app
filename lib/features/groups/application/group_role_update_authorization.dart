import 'package:flutter_app/features/groups/domain/models/group_member.dart';

const permissionEscalationBlockedMessage =
    'Members cannot grant roles or permissions they do not possess';

bool canApplyGroupMemberRoleUpdate({
  required GroupMember actor,
  required MemberRole newRole,
  MemberRole? existingRole,
  GroupMemberPermissions? requestedPermissions,
  GroupMemberPermissions? existingPermissions,
}) {
  final canManageRoles = actor.permissions.allows(
    GroupMemberPermission.manageRoles,
    actor.role,
  );
  if (!canManageRoles) {
    return false;
  }

  if (actor.role != MemberRole.admin &&
      newRole == MemberRole.admin &&
      existingRole != MemberRole.admin) {
    return false;
  }

  if (requestedPermissions == null) {
    return true;
  }

  for (final permission in GroupMemberPermission.values) {
    if (!_explicitlyAllows(requestedPermissions, permission)) {
      continue;
    }
    if (_explicitlyAllows(existingPermissions, permission)) {
      continue;
    }
    if (!actor.permissions.allows(permission, actor.role)) {
      return false;
    }
  }

  return true;
}

bool _explicitlyAllows(
  GroupMemberPermissions? permissions,
  GroupMemberPermission permission,
) {
  return permissions?.toJson()[permission.wireName] == true;
}
