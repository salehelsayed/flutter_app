import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ml020_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _aliceRemoved = 'aliceRemovedWindowAfterDemotion';
const _bobRemoved = 'bobRemovedWindowAfterAliceDemotion';
const _aliceAfter = 'aliceAfterCharlieReadd';
const _bobAfter = 'bobAfterCharlieReadd';
const _charlieAfter = 'charlieAfterRoleReadd';
final _f = CatalogFixture(
  'private_admin_role_transfer_delivery',
  productionMl020Texts('run'),
  productionMl020Flows,
);

List<Map<String, Object?>> _details(Map<String, String> roles) => [
  for (final e in roles.entries)
    {'peerId': CatalogFixture.peers[e.key], 'role': e.value},
];

const _final = {'alice': 'writer', 'bob': 'admin', 'charlie': 'writer'};

Map<String, dynamic> fixture() {
  final p = _f.base();
  const table = {
    _aliceRemoved: ['bob'],
    _bobRemoved: ['alice'],
    _aliceAfter: ['bob', 'charlie'],
    _bobAfter: ['alice', 'charlie'],
    _charlieAfter: ['alice', 'bob'],
  };
  final watched = <String, Map<String, Object?>>{
    for (final r in const ['alice', 'bob', 'charlie']) r: {},
  };
  final deliveries = <String, List<Object?>>{
    for (final r in const ['alice', 'bob', 'charlie']) r: [],
  };
  for (final MapEntry(:key, value: to) in table.entries) {
    final sender = productionMl020Texts('run')[key]!.role;
    watched[sender]![key] = [_f.row(key, incoming: false)];
    deliveries[sender]!.add(_f.delivery(key, to));
    for (final r in to) {
      watched[r]![key] = [_f.row(key, incoming: true)];
      p['got:$key:$r'] = _f.got(r, key);
    }
  }
  for (final r in const ['alice', 'bob', 'charlie']) {
    p['${r}Final'] = _f.snap(
      r,
      watched: watched[r]!,
      extra: {'deliveries': deliveries[r], 'memberDetails': _details(_final)},
    );
  }
  p['bobPromoted'] = _f.snap(
    'alice',
    extra: {
      'memberDetails': _details({
        'alice': 'admin',
        'bob': 'admin',
        'charlie': 'writer',
      }),
    },
  );
  p['aliceDemoted'] = _f.snap(
    'bob',
    extra: {'memberDetails': _details(_final)},
  );
  p['bobRemovedCharlie'] = _f.snap('bob', members: const ['peer-a', 'peer-b']);
  p['charlieRemoved'] = _f.snap(
    'charlie',
    members: const ['peer-a', 'peer-b'],
    self: false,
  );
  p['charlieRemovedWindow'] = _f.snap(
    'charlie',
    members: const ['peer-a', 'peer-b'],
    self: false,
  );
  return p;
}

void main() {
  test('observed ML-020 passes the original oracle', () {
    expect(validateProductionGroupMl020(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Bob was never promoted': (p) => p['bobPromoted']['memberDetails'] =
        _details({'alice': 'admin', 'bob': 'writer', 'charlie': 'writer'}),
    'Alice kept her admin role': (p) => p['bobFinal']['memberDetails'] =
        _details({'alice': 'admin', 'bob': 'admin', 'charlie': 'writer'}),
    'Charlie held a removed-window post': (p) =>
        p['charlieRemovedWindow']['watched'] = {
          _bobRemoved: [_f.row(_bobRemoved, incoming: true)],
        },
    'Charlie was never removed': (p) =>
        p['charlieRemoved']['selfMember'] = true,
    'Charlie never got Bob\'s post-readd message': (p) =>
        p['got:$_bobAfter:charlie']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupMl020(proof), isNotEmpty);
    });
  }
}
