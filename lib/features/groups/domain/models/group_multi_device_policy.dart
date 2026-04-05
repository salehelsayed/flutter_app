enum GroupMultiDeviceScope { sharedAcrossJoinedDevices, deviceLocal }

enum GroupMultiDeviceFacet {
  membershipState,
  groupMetadata,
  messageHistory,
  mutePreference,
  unreadCounters,
  localNotifications,
  pendingInviteReview,
}

// Shared state applies once a second device has already materialized the group
// locally. This repo does not define a separate account-wide sync channel for
// pending invite review or other installation-local preferences.
const Map<GroupMultiDeviceFacet, GroupMultiDeviceScope>
groupMultiDeviceScopes = {
  GroupMultiDeviceFacet.membershipState:
      GroupMultiDeviceScope.sharedAcrossJoinedDevices,
  GroupMultiDeviceFacet.groupMetadata:
      GroupMultiDeviceScope.sharedAcrossJoinedDevices,
  GroupMultiDeviceFacet.messageHistory:
      GroupMultiDeviceScope.sharedAcrossJoinedDevices,
  GroupMultiDeviceFacet.mutePreference: GroupMultiDeviceScope.deviceLocal,
  GroupMultiDeviceFacet.unreadCounters: GroupMultiDeviceScope.deviceLocal,
  GroupMultiDeviceFacet.localNotifications: GroupMultiDeviceScope.deviceLocal,
  GroupMultiDeviceFacet.pendingInviteReview: GroupMultiDeviceScope.deviceLocal,
};

GroupMultiDeviceScope groupMultiDeviceScopeFor(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopes[facet]!;

bool isGroupMultiDeviceShared(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopeFor(facet) ==
    GroupMultiDeviceScope.sharedAcrossJoinedDevices;

bool isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopeFor(facet) == GroupMultiDeviceScope.deviceLocal;
