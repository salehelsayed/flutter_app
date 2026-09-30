import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

/// Uses the preserved catalog as its selection authority. An unimplemented
/// module remains an explicit outstanding obligation, never a passing subset.
List<String> selectProductionGroupCatalog(String selector) =>
    List<String>.unmodifiable(switch (selector) {
      'all' => allGroupMultiPartyDeviceScenarioIds,
      'smoke' => smokeGroupMultiPartyDeviceScenarioIds,
      'slice_b_live' => sliceBLiveGateGroupMultiPartyDeviceScenarioIds,
      _ when allGroupMultiPartyDeviceScenarioIds.contains(selector) => [
        selector,
      ],
      _ => throw ArgumentError.value(
        selector,
        'selector',
        'unknown catalog selection',
      ),
    });

List<String> productionGroupCatalogRoles(String scenario) =>
    List<String>.unmodifiable(scenarioRequirement(scenario).roles);
