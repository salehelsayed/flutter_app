import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_readd_cycles_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'private_readd_cycles',
  productionMl008Texts('run'),
  productionMl008Flows(),
);
final _cycles = [for (var c = 1; c <= 20; c++) c];

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['completedCycles'] = 20;
  for (final c in _cycles) {
    p['charlieSelfRemoved:$c'] = true;
    p['bobCharlieRows:$c'] = 1;
    if (productionMl008RestartRole(c) != null) p['restart:$c'] = true;
  }
  Map<String, Object?> w(String role) => {
    for (final c in _cycles)
      for (final k in [
        productionMl008RemovedKey(c),
        productionMl008AlicePostKey(c),
        productionMl008CharliePostKey(c),
      ])
        if (!(role == 'charlie' && k == productionMl008RemovedKey(c)))
          k: [
            _f.row(
              k,
              incoming: !k.startsWith(role == 'alice' ? 'ml008Alice' : role == 'charlie' ? 'ml008Charlie' : '~'),
              epoch: 41,
            ),
          ],
  };
  for (final r in ['alice', 'bob', 'charlie']) {
    p['${r}Final'] = _f.snap(r, epoch: 41, watched: w(r));
  }
  return p;
}

void main() {
  test('observed ML-008 re-add cycles pass the original oracle', () {
    expect(validateProductionGroupReaddCycles(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'one restart missing': (p) => p['restart:10'] = false,
    'Charlie decrypted a removed window': (p) =>
        p['charlieFinal']['watched'][productionMl008RemovedKey(4)] = [
          _f.row(productionMl008RemovedKey(4), incoming: true, epoch: 41),
        ],
    'Bob saw two Charlie rows': (p) => p['bobCharlieRows:3'] = 2,
    'stopped after 19 cycles': (p) => p['completedCycles'] = 19,
    'epochs diverged': (p) => p['bobFinal']['keyEpoch'] = 40,
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupReaddCycles(proof), isNotEmpty);
    });
  }
}
