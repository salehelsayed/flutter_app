import 'package:flutter_test/flutter_test.dart';
import '../../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../../tool/sims/production_group_catalog.dart';

void main() {
  test('all keeps every original catalog case and exact order', () {
    final selected = selectProductionGroupCatalog('all');
    expect(selected.length, greaterThanOrEqualTo(109));
    expect(selected, allGroupMultiPartyDeviceScenarioIds);
    expect(selected.toSet().length, selected.length);
    for (final id in selected) {
      expect(selectProductionGroupCatalog(id), [id]);
      expect(productionGroupCatalogRoles(id), scenarioRequirement(id).roles);
    }
  });
  test('retains smoke and slice selections', () {
    expect(
      selectProductionGroupCatalog('smoke'),
      smokeGroupMultiPartyDeviceScenarioIds,
    );
    expect(
      selectProductionGroupCatalog('slice_b_live'),
      sliceBLiveGateGroupMultiPartyDeviceScenarioIds,
    );
  });
  test('unknown selection cannot fall back to a partial catalog', () {
    expect(() => selectProductionGroupCatalog('unknown'), throwsArgumentError);
    expect(
      () => selectProductionGroupCatalog('all').clear(),
      throwsUnsupportedError,
    );
  });
}
