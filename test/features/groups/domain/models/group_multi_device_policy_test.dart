import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/groups/domain/models/group_multi_device_policy.dart';

void main() {
  group('group multi-device policy', () {
    test('shares only joined-device group-authoritative state', () {
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.membershipState),
        GroupMultiDeviceScope.sharedAcrossJoinedDevices,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.groupMetadata),
        GroupMultiDeviceScope.sharedAcrossJoinedDevices,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.messageHistory),
        GroupMultiDeviceScope.sharedAcrossJoinedDevices,
      );
    });

    test('keeps local installation state device-specific', () {
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.mutePreference),
        GroupMultiDeviceScope.deviceLocal,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.unreadCounters),
        GroupMultiDeviceScope.deviceLocal,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.localNotifications),
        GroupMultiDeviceScope.deviceLocal,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.pendingInviteReview),
        GroupMultiDeviceScope.deviceLocal,
      );
      expect(
        groupMultiDeviceScopeFor(GroupMultiDeviceFacet.composerDrafts),
        GroupMultiDeviceScope.deviceLocal,
      );
    });

    test('shared and device-local helpers stay aligned with the mapping', () {
      expect(
        isGroupMultiDeviceShared(GroupMultiDeviceFacet.messageHistory),
        isTrue,
      );
      expect(
        isGroupMultiDeviceShared(GroupMultiDeviceFacet.pendingInviteReview),
        isFalse,
      );
      expect(
        isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.mutePreference),
        isTrue,
      );
      expect(
        isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.composerDrafts),
        isTrue,
      );
      expect(
        isGroupMultiDeviceDeviceLocal(GroupMultiDeviceFacet.membershipState),
        isFalse,
      );
    });
  });
}
