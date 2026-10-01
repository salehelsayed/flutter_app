import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_gm019_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'gm019',
  productionGm019Texts('run'),
  productionGm019Flows,
);
const _w = 'aliceGm019RemovedWindow';
const _a = 'aliceGm019AfterReadd';
const _b = 'bobGm019AfterReadd';
const _ts = {
  _w: '2026-10-01T12:00:10.000Z',
  _a: '2026-10-01T12:00:30.000Z',
  _b: '2026-10-01T12:00:40.000Z',
};

Map<String, Object?> _row(String k, bool incoming) =>
    _f.row(k, incoming: incoming, timestamp: _ts[k]!);

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceRemoved'] = _f.snap(
    'alice',
    members: ['peer-a', 'peer-b'],
    extra: {'lastMembershipEventAt': '2026-10-01T12:00:00.000Z'},
  );
  Map<String, Object?> got(String r, String k) =>
      _f.snap(r, watched: {k: [_row(k, true)]});
  p['got:$_w:bob'] = got('bob', _w);
  p['got:$_a:bob'] = got('bob', _a);
  p['got:$_a:charlie'] = got('charlie', _a);
  p['got:$_b:alice'] = got('alice', _b);
  p['got:$_b:charlie'] = got('charlie', _b);
  p['charlieRemovedWindow'] = _f.snap('charlie', self: false, epoch: 0);
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: {
      _w: [_row(_w, false)],
      _a: [_row(_a, false)],
      _b: [_row(_b, true)],
    },
    extra: {
      'lastMembershipEventAt': '2026-10-01T12:00:20.000Z',
      'deliveries': [
        _f.delivery(_w, ['bob']),
        _f.delivery(_a, ['bob', 'charlie']),
      ],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: {
      _w: [_row(_w, true)],
      _a: [_row(_a, true)],
      _b: [_row(_b, false)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_b, ['alice', 'charlie']),
      ],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: {
      _a: [_row(_a, true)],
      _b: [_row(_b, true)],
    },
  );
  return p;
}

void main() {
  test('observed GM-019 durable recipient window passes the oracle', () {
    expect(validateProductionGroupGm019(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'removed-window copy addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'post re-add copy missing Charlie': (p) =>
        p['aliceFinal']['deliveries'][1]['recipientPeerIds'] = ['peer-b'],
    'Charlie decrypted the removed window': (p) =>
        p['charlieFinal']['watched'][_w] = [_row(_w, true)],
    're-add after the post re-add send': (p) =>
        p['aliceFinal']['lastMembershipEventAt'] = '2026-10-01T12:00:35.000Z',
    'removal after the removed-window send': (p) =>
        p['aliceRemoved']['lastMembershipEventAt'] = '2026-10-01T12:00:15.000Z',
    'Bob copy missing Alice': (p) =>
        p['bobFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-c'],
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = copyProof(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm019(proof), isNotEmpty);
    });
  }
}
