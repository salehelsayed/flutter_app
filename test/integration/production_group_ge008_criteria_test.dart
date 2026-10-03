import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge008_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _t = productionGe008Texts('run');
final _f = CatalogFixture('ge008', _t, productionGe008Flows());
const _roles = ['alice', 'bob', 'charlie'];
final _pre = productionGe008Keys('pre', _roles);
final _rem = productionGe008Keys('removed', ['alice', 'bob']);
final _post = productionGe008Keys('post', _roles);

Map<String, dynamic> fixture() {
  final p = _f.base();
  const pair = ['peer-a', 'peer-b'];
  p['aliceRemoved'] = _f.snap('alice', members: pair);
  p['bobExcluded'] = _f.snap('bob', members: pair);
  p['charlieRemoved'] = _f.snap('charlie', self: false, epoch: 0, members: pair);
  p['charlieRemovedWindow'] = _f.snap('charlie', self: false, epoch: 0, members: pair);
  for (final k in ['charlieGe008RemovedStale0', 'charlieGe008RemovedStale1']) {
    p['charlieRejected:$k'] = {
      'key': k,
      'messageId': 'stale-$k',
      'outcome': 'groupNotFound',
      'accepted': false,
    };
  }
  for (final (keys, to) in [(_pre, _roles), (_rem, ['alice', 'bob']), (_post, _roles)]) {
    for (final k in keys) {
      for (final r in to.where((r) => r != _t[k]!.role)) {
        p['got:$k:$r'] = _f.got(r, k);
      }
    }
  }
  for (final role in _roles) {
    final mine = [..._pre, ..._rem, ..._post].where((k) => _t[k]!.role == role);
    final theirs = [
      ..._pre,
      if (role != 'charlie') ..._rem,
      ..._post,
    ].where((k) => _t[k]!.role != role);
    p['${role}Final'] = _f.snap(role, watched: {
      for (final k in mine) k: [_f.row(k, incoming: false)],
      for (final k in theirs) k: [_f.row(k, incoming: true)],
    }, extra: {
      'deliveries': [
        for (final k in mine)
          _f.delivery(
            k,
            _rem.contains(k)
                ? _roles.where((r) => r != role && r != 'charlie').toList()
                : _roles.where((r) => r != role).toList(),
          ),
      ],
    });
  }
  return p;
}

void main() {
  test('observed GE-008 send storm passes the original oracle', () {
    expect(validateProductionGroupGe008(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'a stale removed send accepted': (p) =>
        p['charlieRejected:charlieGe008RemovedStale1']['accepted'] = true,
    'Charlie decrypted the removed window': (p) =>
        p['charlieFinal']['watched'][_rem[0]] = [_f.row(_rem[0], incoming: true)],
    'removed copy addressed to Charlie': (p) {
      final d = (p['aliceFinal']['deliveries'] as List)
          .firstWhere((d) => d['messageId'] == 'm-${_rem[0]}');
      d['recipientPeerIds'] = ['peer-b', 'peer-c'];
    },
    'Bob missed a post message': (p) =>
        p['got:${_post.last}:bob']['watched'] = <String, Object?>{},
    'Alice persisted a pre message twice': (p) =>
        (p['aliceFinal']['watched'][_pre[2]] as List).add(
          _f.row(_pre[2], incoming: true),
        ),
    'Charlie not re-added': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGe008(proof), isNotEmpty);
    });
  }
}
