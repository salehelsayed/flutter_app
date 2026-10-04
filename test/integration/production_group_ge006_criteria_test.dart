import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge006_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('ge006', productionGe006Texts('run'), productionGe006Flows);
const _removed = 'aliceGe006RemovedWindow';
const _alicePost = 'aliceGe006PostReadd';
const _bobPost = 'bobGe006PostReadd';
const _charliePost = 'charlieGe006PostCatchUp';
const _pair = ['peer-a', 'peer-b'];

Map<String, Object?> _rows(String role, List<String> keys) => {
  for (final k in keys)
    k: [_f.row(k, incoming: productionGe006Texts('run')[k]!.role != role)],
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['charlieOffline'] = true;
  p['aliceRemoved'] = _f.snap('alice', members: _pair);
  p['aliceReadded'] = _f.snap('alice');
  p['got:$_removed:bob'] = _f.got('bob', _removed);
  for (final (role, key) in [
    ('bob', _alicePost),
    ('charlie', _alicePost),
    ('alice', _bobPost),
    ('charlie', _bobPost),
    ('alice', _charliePost),
    ('bob', _charliePost),
  ]) {
    p['got:$key:$role'] = _f.got(role, key);
  }
  p['aliceFinal'] = _f.snap(
    'alice',
    watched: _rows('alice', [_removed, _alicePost, _bobPost, _charliePost]),
    extra: {
      'deliveries': [
        _f.delivery(_removed, ['bob']),
        _f.delivery(_alicePost, ['bob', 'charlie']),
      ],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    watched: _rows('bob', [_removed, _alicePost, _bobPost, _charliePost]),
    extra: {
      'deliveries': [
        _f.delivery(_bobPost, ['alice', 'charlie']),
      ],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: _rows('charlie', [_alicePost, _bobPost, _charliePost]),
    extra: {
      'liveMessageIds': <String>[],
      'deliveries': [
        _f.delivery(_charliePost, ['alice', 'bob']),
      ],
    },
  );
  return p;
}

void main() {
  test('observed GE-006 offline re-add passes the original oracle', () {
    expect(validateProductionGroupGe006(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie stayed online': (p) => p['charlieOffline'] = false,
    'removal not applied on Alice': (p) =>
        p['aliceRemoved']['memberPeerIds'] = CatalogFixture.all,
    'removed-window copy addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'post-re-add copy omits pending Charlie (GE-009)': (p) =>
        p['aliceFinal']['deliveries'][1]['recipientPeerIds'] = ['peer-b'],
    'Charlie got the post-re-add message live': (p) =>
        p['charlieFinal']['liveMessageIds'] = ['m-$_alicePost'],
    'Charlie holds the removed-window message': (p) =>
        p['charlieFinal']['watched'][_removed] = [
          _f.row(_removed, incoming: true),
        ],
    'Charlie never caught up on Bob': (p) =>
        p['got:$_bobPost:charlie']['watched'] = <String, Object?>{},
    'Bob never got Charlie': (p) =>
        p['got:$_charliePost:bob']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe006(proof), isNotEmpty);
    });
  }
}
