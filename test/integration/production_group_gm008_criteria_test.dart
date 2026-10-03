import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_gm008_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _t = productionGm008Texts('run');
final _f = CatalogFixture('gm008', _t, productionGm008Flows);
const _d = 'aliceDuringCharlieRestartedRemoval';
const _c = 'charlieAfterRestartReadd';
const _a = 'aliceAfterRestartReadd';

Map<String, dynamic> fixture() {
  final p = _f.base();
  const pair = ['peer-a', 'peer-b'];
  p['aliceRemoved'] = _f.snap('alice', members: pair);
  p['bobExcluded'] = _f.snap('bob', members: pair);
  p['charlieRemoved'] = _f.snap('charlie', self: false, epoch: 0, members: pair);
  p['charlieRestarted'] = true;
  p['charlieAfterRestart'] = _f.snap('charlie', self: false, epoch: 0, members: pair);
  p['charlieRejected'] = {
    'key': 'charlieDuringRestartedRemoval',
    'text': _t['charlieDuringRestartedRemoval']!.text,
    'outcome': 'groupNotFound',
    'accepted': false,
  };
  p['charlieRemovedWindow'] = _f.snap('charlie', self: false, epoch: 0, members: pair);
  p['aliceReadded'] = _f.snap('alice');
  p['got:$_c:alice'] = _f.got('alice', _c);
  for (final k in [_d, _c, _a]) {
    p['got:$k:bob'] = _f.got('bob', k);
  }
  p['got:$_a:charlie'] = _f.got('charlie', _a);
  p['aliceFinal'] = _f.snap('alice', watched: {
    _d: [_f.row(_d, incoming: false)],
    _a: [_f.row(_a, incoming: false)],
    _c: [_f.row(_c, incoming: true)],
  });
  p['bobFinal'] = _f.snap('bob', watched: {
    for (final k in [_d, _c, _a]) k: [_f.row(k, incoming: true)],
  });
  p['charlieFinal'] = _f.snap('charlie', watched: {
    _c: [_f.row(_c, incoming: false)],
    _a: [_f.row(_a, incoming: true)],
  });
  return p;
}

void main() {
  test('observed GM-008 restart re-add passes the original oracle', () {
    expect(validateProductionGroupGm008(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never restarted': (p) => p['charlieRestarted'] = false,
    'removed send accepted': (p) => p['charlieRejected']['accepted'] = true,
    'Charlie decrypted the removed window': (p) =>
        p['charlieFinal']['watched'][_d] = [_f.row(_d, incoming: true)],
    'Charlie stale epoch after re-add': (p) =>
        p['charlieFinal']['keyEpoch'] = 1,
    'Alice missed Charlie': (p) =>
        p['got:$_c:alice']['watched'] = <String, Object?>{},
    'Charlie not re-added': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGm008(proof), isNotEmpty);
    });
  }
}
