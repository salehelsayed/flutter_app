import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

void main() {
  group('group multi-party smoke tier', () {
    const expectedSmokeScenarios = <String>[
      'private_abc_create',
      'private_online_add',
      'private_online_remove',
      'private_offline_add',
      'private_reaction_roundtrip',
      'ge012',
      'private_relay_only_delivery',
      'private_admin_role_transfer_delivery',
      'private_process_death_matrix',
    ];

    test('is a strict valid subset of all multi-party scenarios', () {
      expect(smokeGroupMultiPartyDeviceScenarioIds, expectedSmokeScenarios);
      expect(
        smokeGroupMultiPartyDeviceScenarioIds.length,
        inInclusiveRange(8, 12),
      );
      expect(
        smokeGroupMultiPartyDeviceScenarioIds.length,
        lessThan(allGroupMultiPartyDeviceScenarioIds.length),
      );
      expect(
        allGroupMultiPartyDeviceScenarioIds,
        containsAll(smokeGroupMultiPartyDeviceScenarioIds),
      );

      for (final scenario in smokeGroupMultiPartyDeviceScenarioIds) {
        expect(scenarioRequirement(scenario).scenario, scenario);
      }
    });

    test('covers the routine-risk representatives frozen by Slice A', () {
      final smoke = smokeGroupMultiPartyDeviceScenarioIds.toSet();

      expect(smoke, contains('private_abc_create'));
      expect(
        smoke,
        containsAll(<String>['private_online_add', 'private_online_remove']),
      );
      expect(smoke, contains('private_offline_add'));
      expect(smoke, contains('private_reaction_roundtrip'));
      expect(
        smoke,
        containsAll(<String>['ge012', 'private_process_death_matrix']),
      );
      expect(smoke, contains('private_relay_only_delivery'));
      expect(smoke, contains('private_admin_role_transfer_delivery'));
      expect(scenarioRequirement('private_online_add').roles, contains('dana'));
    });
  });
}
