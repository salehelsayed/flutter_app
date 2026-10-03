import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge007_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('ge007', productionGe007Texts('run'), productionGe007Flows);
const _w = 'aliceGe007RemovedWindow';
const _ap = 'aliceGe007PostReadd';
const _cp = 'charlieGe007PostReadd';
const _bc = 'bobGe007PostCatchUp';

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['bobOffline'] = true;
  p['bobDrain'] = {'completedDrainCount': 1};
  p['charlieRemoved'] = _f.snap('charlie', self: false, epoch: 0, members: ['peer-a', 'peer-b']);
  p['got:$_cp:alice'] = _f.got('alice', _cp);
  p['got:$_bc:alice'] = _f.got('alice', _bc);
  for (final k in [_w, _ap, _cp]) {
    p['got:$k:bob'] = _f.got('bob', k);
  }
  p['got:$_ap:charlie'] = _f.got('charlie', _ap);
  p['got:$_bc:charlie'] = _f.got('charlie', _bc);
  p['aliceFinal'] = _f.snap('alice', watched: {
    _w: [_f.row(_w, incoming: false)],
    _ap: [_f.row(_ap, incoming: false)],
    _cp: [_f.row(_cp, incoming: true)],
    _bc: [_f.row(_bc, incoming: true)],
  }, extra: {
    'deliveries': [_f.delivery(_w, ['bob']), _f.delivery(_ap, ['bob', 'charlie'])],
  });
  p['bobFinal'] = _f.snap('bob', watched: {
    for (final k in [_w, _ap, _cp]) k: [_f.row(k, incoming: true)],
    _bc: [_f.row(_bc, incoming: false)],
  });
  p['charlieFinal'] = _f.snap('charlie', watched: {
    _cp: [_f.row(_cp, incoming: false)],
    _ap: [_f.row(_ap, incoming: true)],
    _bc: [_f.row(_bc, incoming: true)],
  });
  return p;
}

void main() {
  test('observed GE-007 offline observer passes the original oracle', () {
    expect(validateProductionGroupGe007(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob never went offline': (p) => p['bobOffline'] = false,
    'removed-window copy missing Bob': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-c'],
    'Bob missed Charlie post re-add': (p) =>
        p['got:$_cp:bob']['watched'] = <String, Object?>{},
    'Bob no catch-up drain': (p) => p['bobDrain'] = {'completedDrainCount': 0},
    'Bob roster missing Charlie': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Charlie missed Bob catch-up': (p) =>
        p['got:$_bc:charlie']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe007(proof), isNotEmpty);
    });
  }
}
