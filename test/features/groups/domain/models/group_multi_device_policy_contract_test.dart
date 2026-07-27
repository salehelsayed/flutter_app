import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/config/multi_device_sync_flag.dart';
import 'package:flutter_app/features/groups/domain/models/group_multi_device_policy.dart';

/// GUARDRAIL CONTRACT TEST — keeps the UX-013 matrix claim honest.
///
/// This test is the mechanical gate referenced by the multi-device-honesty
/// proposal (Test-Flight-Improv/.../12-P2-multi-device-honesty.md, A3): it fails
/// if any facet's *declared scope* drifts from "what the code actually does", and
/// it fails if a convergence facet (membership/metadata/history) is ever marked
/// *implemented* while the convergence build is still gated off. As long as this
/// test is green with the flag default-off, UX-013 must NOT be re-closed as a
/// realized runtime guarantee — only as a contractual intent.
void main() {
  group('group multi-device policy CONTRACT', () {
    // The convergence facets whose shared scope is aspirational until Part B.
    const convergenceFacets = <GroupMultiDeviceFacet>[
      GroupMultiDeviceFacet.membershipState,
      GroupMultiDeviceFacet.groupMetadata,
      GroupMultiDeviceFacet.messageHistory,
    ];

    // The facets that genuinely behave installation-locally today.
    const deviceLocalFacets = <GroupMultiDeviceFacet>[
      GroupMultiDeviceFacet.mutePreference,
      GroupMultiDeviceFacet.unreadCounters,
      GroupMultiDeviceFacet.localNotifications,
      GroupMultiDeviceFacet.pendingInviteReview,
      GroupMultiDeviceFacet.composerDrafts,
    ];

    test('every facet has a scope and an implemented entry (no gaps)', () {
      for (final facet in GroupMultiDeviceFacet.values) {
        expect(
          groupMultiDeviceScopes.containsKey(facet),
          isTrue,
          reason: 'facet $facet is missing a declared scope',
        );
        expect(
          groupMultiDeviceImplemented.containsKey(facet),
          isTrue,
          reason: 'facet $facet is missing an implemented entry',
        );
      }
    });

    test('declared scope fixture matches the mapping exactly', () {
      // The single source of truth for "what scope each facet is contractually
      // declared to have". If a scope changes, change it here deliberately.
      const expectedScopes = <GroupMultiDeviceFacet, GroupMultiDeviceScope>{
        GroupMultiDeviceFacet.membershipState:
            GroupMultiDeviceScope.sharedAcrossJoinedDevices,
        GroupMultiDeviceFacet.groupMetadata:
            GroupMultiDeviceScope.sharedAcrossJoinedDevices,
        GroupMultiDeviceFacet.messageHistory:
            GroupMultiDeviceScope.sharedAcrossJoinedDevices,
        GroupMultiDeviceFacet.mutePreference: GroupMultiDeviceScope.deviceLocal,
        GroupMultiDeviceFacet.unreadCounters: GroupMultiDeviceScope.deviceLocal,
        GroupMultiDeviceFacet.localNotifications:
            GroupMultiDeviceScope.deviceLocal,
        GroupMultiDeviceFacet.pendingInviteReview:
            GroupMultiDeviceScope.deviceLocal,
        GroupMultiDeviceFacet.composerDrafts: GroupMultiDeviceScope.deviceLocal,
      };
      expect(groupMultiDeviceScopes, expectedScopes);
    });

    test('device-local facets are implemented today (they work per-device)', () {
      for (final facet in deviceLocalFacets) {
        expect(
          isGroupMultiDeviceDeviceLocal(facet),
          isTrue,
          reason: '$facet must be device-local',
        );
        expect(
          isGroupMultiDeviceImplemented(facet),
          isTrue,
          reason: '$facet is produced at runtime today and must be implemented',
        );
      }
    });

    test(
      'convergence facets are implemented ONLY when the multiDeviceSync flag is on',
      () {
        for (final facet in convergenceFacets) {
          expect(
            isGroupMultiDeviceShared(facet),
            isTrue,
            reason: '$facet is contractually shared',
          );
          // Implemented status is tied to the build flag. With the flag off
          // (the default, including this CI run) the convergence build is not
          // present, so the facet must report NOT implemented — which is what
          // keeps UX-013 honestly "Partial / device-local".
          expect(
            isGroupMultiDeviceImplemented(facet),
            kMultiDeviceSyncEnabled,
            reason:
                '$facet may only be marked implemented behind '
                'kMultiDeviceSyncEnabled (Part B). Re-closing UX-013 requires '
                'shipping + device-verifying the convergence build, not editing '
                'this map.',
          );
        }
      },
    );

    test(
      'GUARD: with the flag off, NO convergence facet may claim implemented',
      () {
        // The explicit safety net the proposal asks for: messageHistory (and its
        // siblings) must never be marked implemented without the hydration
        // entry point shipping, which is gated behind the flag.
        expect(
          kMultiDeviceSyncEnabled,
          isFalse,
          reason:
              'The default build must remain honest until fresh-device group '
              'state convergence ships with on-device verification.',
        );
        for (final facet in convergenceFacets) {
          expect(
            isGroupMultiDeviceImplemented(facet),
            isFalse,
            reason:
                'A freshly restored device hydrates no group $facet today. '
                'Do not flip this without the Part-B hydration path + '
                'on-device verification.',
          );
        }
      },
    );
  });
}
