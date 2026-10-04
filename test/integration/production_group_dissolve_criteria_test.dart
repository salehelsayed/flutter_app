import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_dissolve_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'private_online_dissolve_convergence',
  productionDissolveTexts('run'),
  productionDissolveFlows,
);

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceBinding'] = {'deviceIdPresent': true, 'transportPeerIdPresent': true};
  for (final r in ['alice', 'bob', 'charlie']) {
    p['${r}Final'] = _f.snap(
      r,
      extra: {
        'isDissolved': true,
        'dissolveTimelineTexts': ['Journeyalice dissolved the group'],
        'flowEvents': [
          if (r == 'alice') {'event': 'GROUP_DISSOLVE_USE_CASE_SUCCESS'},
        ],
      },
    );
  }
  return p;
}

void main() {
  test('observed I-01 dissolve passes the original oracle', () {
    expect(validateProductionGroupDissolve(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Alice dissolve not successful': (p) =>
        p['aliceFinal']['flowEvents'] = <Object?>[],
    'no sender binding': (p) =>
        p['aliceBinding']['transportPeerIdPresent'] = false,
    'Bob never dissolved': (p) => p['bobFinal']['isDissolved'] = false,
    'Charlie has no dissolve row': (p) =>
        p['charlieFinal']['dissolveTimelineTexts'] = <String>[],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupDissolve(proof), isNotEmpty);
    });
  }
}
