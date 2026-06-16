import 'package:flutter_app/core/config/multi_device_sync_flag.dart';

enum GroupMultiDeviceScope { sharedAcrossJoinedDevices, deviceLocal }

enum GroupMultiDeviceFacet {
  membershipState,
  groupMetadata,
  messageHistory,
  mutePreference,
  unreadCounters,
  localNotifications,
  pendingInviteReview,
  composerDrafts,
}

// `scope` below is the *contractual intent*, not a runtime guarantee. The
// `sharedAcrossJoinedDevices` facets (membership/metadata/history) are NOT
// produced at runtime today: a freshly restored second device hydrates no group
// state and no keys (it even re-mints its ML-KEM keypair, so it cannot decrypt
// keys ever distributed to the prior device). Shared scope only becomes real
// once the Part-B convergence build (sibling-device admission + restore-time key
// continuity + peer hydration) ships behind `kMultiDeviceSyncEnabled` and is
// device-matrix verified — see `groupMultiDeviceImplemented` below and
// `Test-Flight-Improv/.../12-P2-multi-device-honesty.md`. The device-local
// facets ARE produced at runtime today. This repo defines no account-wide sync
// channel for pending-invite review or other installation-local preferences.
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
  GroupMultiDeviceFacet.composerDrafts: GroupMultiDeviceScope.deviceLocal,
};

GroupMultiDeviceScope groupMultiDeviceScopeFor(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopes[facet]!;

bool isGroupMultiDeviceShared(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopeFor(facet) ==
    GroupMultiDeviceScope.sharedAcrossJoinedDevices;

bool isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceScopeFor(facet) == GroupMultiDeviceScope.deviceLocal;

// Whether a facet's declared scope is actually *produced at runtime*, as opposed
// to merely being contractual intent (see the comment on `groupMultiDeviceScopes`).
//
// - Device-local facets are implemented today: each device keeps its own
//   mute/unread/notification/draft/invite-review state and that works.
// - The `sharedAcrossJoinedDevices` convergence facets
//   (membershipState/groupMetadata/messageHistory) are implemented ONLY when the
//   Part-B convergence build is enabled via `kMultiDeviceSyncEnabled`. Until then
//   a restored second device hydrates nothing, so they are honestly NOT
//   implemented. This is the single mechanical hook tying the UX-013 matrix claim
//   to runtime reality: the policy contract test asserts these stay unimplemented
//   while the flag is off, and the rollout only enables the flag after on-device
//   verification — so UX-013 cannot be re-closed ahead of the code.
const Map<GroupMultiDeviceFacet, bool> groupMultiDeviceImplemented = {
  GroupMultiDeviceFacet.membershipState: kMultiDeviceSyncEnabled,
  GroupMultiDeviceFacet.groupMetadata: kMultiDeviceSyncEnabled,
  GroupMultiDeviceFacet.messageHistory: kMultiDeviceSyncEnabled,
  GroupMultiDeviceFacet.mutePreference: true,
  GroupMultiDeviceFacet.unreadCounters: true,
  GroupMultiDeviceFacet.localNotifications: true,
  GroupMultiDeviceFacet.pendingInviteReview: true,
  GroupMultiDeviceFacet.composerDrafts: true,
};

bool isGroupMultiDeviceImplemented(GroupMultiDeviceFacet facet) =>
    groupMultiDeviceImplemented[facet]!;
