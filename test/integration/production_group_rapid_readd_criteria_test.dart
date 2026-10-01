import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_rapid_readd_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'private_rapid_readd',
  productionRapidReaddTexts('run'),
  productionRapidReaddFlows,
);
const _d = 'aliceDuringRapidRemove';
const _a = 'alicePostRapidReadd';
const _b = 'bobPostRapidReadd';

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['readdWithoutWaitingForRemovalAcks'] = true;
  p['aliceRemoved'] = _f.snap('alice', members: ['peer-a', 'peer-b']);
  p['got:$_d:bob'] = _f.got('bob', _d);
  p['got:$_a:bob'] = _f.got('bob', _a);
  p['got:$_a:charlie'] = _f.got('charlie', _a);
  p['got:$_b:alice'] = _f.got('alice', _b);
  p['got:$_b:charlie'] = _f.got('charlie', _b);
  p['charlieRemovedWindow'] = _f.snap('charlie', self: false, epoch: 0);
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _d: [_f.row(_d, incoming: false)],
      _a: [_f.row(_a, incoming: false)],
      _b: [_f.row(_b, incoming: true)],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: {
      _d: [_f.row(_d, incoming: true)],
      _a: [_f.row(_a, incoming: true)],
      _b: [_f.row(_b, incoming: false)],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: {
      _a: [_f.row(_a, incoming: true)],
      _b: [_f.row(_b, incoming: true)],
    },
  );
  return p;
}

void main() {
  test('observed ML-009 rapid re-add passes the original oracle', () {
    expect(validateProductionGroupRapidReadd(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    're-add waited for the removal acks': (p) =>
        p['readdWithoutWaitingForRemovalAcks'] = false,
    'Charlie decrypted the removed window': (p) =>
        p['charlieFinal']['watched'][_d] = [_f.row(_d, incoming: true)],
    'stale removal won on Bob': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Charlie stale epoch': (p) => p['charlieFinal']['keyEpoch'] = 1,
    'Charlie missed Bob after re-add': (p) =>
        p['got:$_b:charlie']['watched'] = <String, Object?>{},
    'Charlie never removed': (p) =>
        p['aliceRemoved']['memberPeerIds'] = CatalogFixture.all,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = copyProof(fixture());
      entry.value(proof);
      expect(validateProductionGroupRapidReadd(proof), isNotEmpty);
    });
  }
}
