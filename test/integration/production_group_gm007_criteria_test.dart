import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_gm007_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'gm007',
  productionGm007Texts('run'),
  productionGm007Flows,
);
const _before = 'aliceBeforeCharlieRemoval';
const _after = 'aliceAfterCharlieReadd';
const _during = [
  'aliceDuringCharlieRemoval1',
  'aliceDuringCharlieRemoval2',
  'aliceDuringCharlieRemoval3',
];

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceRemoved'] = _f.snap('alice', members: ['peer-a', 'peer-b']);
  p['got:$_before:bob'] = _f.got('bob', _before, epoch: 1);
  p['got:$_before:charlie'] = _f.got('charlie', _before, epoch: 1);
  for (final k in _during) {
    p['got:$k:bob'] = _f.got('bob', k);
  }
  p['got:$_after:bob'] = _f.got('bob', _after);
  p['got:$_after:charlie'] = _f.got('charlie', _after);
  p['charlieRemovedWindow'] = _f.snap(
    'charlie',
    self: false,
    epoch: 0,
    members: ['peer-a', 'peer-b'],
  );
  p['charlieBeforeDrain'] = _f.snap('charlie');
  p['charlieDrain'] = {'completedDrainCount': 1};
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _before: [_f.row(_before, incoming: false, epoch: 1)],
      for (final k in [..._during, _after]) k: [_f.row(k, incoming: false)],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: {
      _before: [_f.row(_before, incoming: true, epoch: 1)],
      for (final k in [..._during, _after]) k: [_f.row(k, incoming: true)],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: {
      _before: [_f.row(_before, incoming: true, epoch: 1)],
      _after: [_f.row(_after, incoming: true)],
    },
  );
  return p;
}

void main() {
  test('observed GM-007 history boundary passes the original oracle', () {
    expect(validateProductionGroupGm007(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie decrypted a removed-window message': (p) =>
        p['charlieFinal']['watched'][_during[1]] = [
          _f.row(_during[1], incoming: true),
        ],
    'Bob missed a removed-window message': (p) =>
        p['got:${_during[2]}:bob']['watched'] = <String, Object?>{},
    'post re-add message at the old epoch': (p) {
      for (final r in ['alice', 'bob', 'charlie']) {
        (p['${r}Final']['watched'][_after] as List)[0]['keyEpoch'] = 1;
      }
      for (final r in ['bob', 'charlie']) {
        (p['got:$_after:$r']['watched'][_after] as List)[0]['keyEpoch'] = 1;
      }
    },
    'no drain and not live before drain': (p) =>
        p['charlieDrain'] = {'completedDrainCount': 0},
    'Charlie stale epoch after re-add': (p) =>
        p['charlieFinal']['keyEpoch'] = 1,
    'Charlie not re-added': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = copyProof(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm007(proof), isNotEmpty);
    });
  }
}
