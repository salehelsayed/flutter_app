import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge005_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('ge005', productionGe005Texts('run'), productionGe005Flows());
final _removed = [for (var c = 1; c <= 20; c++) productionGe005RemovedKey(c)];
final _readd = [for (var c = 1; c <= 20; c++) productionGe005ReaddKey(c)];

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['completedCycles'] = 20;
  p['aliceFinal'] = _f.snap('alice', epoch: 21, watched: {
    for (final k in _removed) k: [_f.row(k, incoming: false, epoch: 21)],
    for (final k in _readd) k: [_f.row(k, incoming: true, epoch: 21)],
  }, extra: {
    'deliveries': [for (final k in _removed) _f.delivery(k, ['bob'])],
  });
  p['bobFinal'] = _f.snap('bob', epoch: 21, watched: {
    for (final k in _removed) k: [_f.row(k, incoming: true, epoch: 21)],
    for (final k in _readd) k: [_f.row(k, incoming: false, epoch: 21)],
  }, extra: {
    'deliveries': [for (final k in _readd) _f.delivery(k, ['alice', 'charlie'])],
  });
  p['charlieFinal'] = _f.snap('charlie', epoch: 21, watched: {
    for (final k in _readd) k: [_f.row(k, incoming: true, epoch: 21)],
  });
  return p;
}

void main() {
  test('observed GE-005 remove/re-add loop passes the original oracle', () {
    expect(validateProductionGroupGe005(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'only 19 cycles completed': (p) => p['completedCycles'] = 19,
    'Charlie decrypted one removed window': (p) =>
        p['charlieFinal']['watched'][_removed[7]] = [
          _f.row(_removed[7], incoming: true, epoch: 21),
        ],
    'one removed copy addressed to Charlie': (p) =>
        (p['aliceFinal']['deliveries'] as List)[3]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'Charlie missed one re-add message': (p) =>
        (p['charlieFinal']['watched'] as Map).remove(_readd[12]),
    'Bob re-add copy missing Charlie': (p) =>
        (p['bobFinal']['deliveries'] as List)[5]['recipientPeerIds'] = [
          'peer-a',
        ],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe005(proof), isNotEmpty);
    });
  }
}
