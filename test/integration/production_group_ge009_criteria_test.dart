import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge009_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _t = productionGe009Texts('run');
final _f = CatalogFixture('ge009', _t, productionGe009Flows);
const _roles = ['alice', 'bob', 'charlie'];

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceRemoved'] = _f.snap('alice', members: ['peer-a', 'peer-b']);
  p['bobExcluded'] = _f.snap('bob', members: ['peer-a', 'peer-b']);
  p['charliePartitioned'] = _f.snap('charlie', self: false, epoch: 0);
  for (final MapEntry(:key, :value) in _t.entries) {
    final receivers = key.endsWith('PostReadd')
        ? [
            ...['alice', 'bob'].where((r) => r != value.role),
            'charlie',
          ]
        : _roles.where((r) => r != value.role).toList();
    for (final r in receivers) {
      p['got:$key:$r'] = _f.got(r, key);
    }
  }
  for (final role in _roles) {
    p['${role}Final'] = _f.snap(
      role,
      watched: {
        for (final MapEntry(:key, :value) in _t.entries)
          key: [_f.row(key, incoming: value.role != role)],
      },
      extra: {
        'deliveries': [
          for (final MapEntry(:key, :value) in _t.entries)
            if (value.role == role)
              _f.delivery(key, _roles.where((r) => r != role).toList()),
        ],
      },
    );
  }
  return p;
}

void main() {
  test('observed GE-009 partition heal passes the original oracle', () {
    expect(validateProductionGroupGe009(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie decrypted live while partitioned': (p) =>
        p['charliePartitioned']['watched'] = {
          'aliceGe009PostReadd': [
            _f.row('aliceGe009PostReadd', incoming: true),
          ],
        },
    'Alice post copy not addressed to Charlie': (p) =>
        (p['aliceFinal']['deliveries'] as List)[1]['recipientPeerIds'] = [
          'peer-b',
        ],
    'Charlie never caught up on Bob': (p) =>
        p['got:bobGe009PostReadd:charlie']['watched'] = <String, Object?>{},
    'Bob still lists Charlie after removal': (p) =>
        p['bobExcluded']['memberPeerIds'] = CatalogFixture.all,
    'Charlie not healed': (p) => p['charlieFinal']['selfMember'] = false,
    'skipped the heal acceptance': (p) =>
        (p['flows'] as List).remove('accept-charlie-readd'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = copyProof(fixture());
      entry.value(proof);
      expect(validateProductionGroupGe009(proof), isNotEmpty);
    });
  }
}
