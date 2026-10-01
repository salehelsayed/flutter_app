import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_ge004_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture(
  'ge004',
  productionGe004Texts('run'),
  productionGe004Flows,
);
const _own = {
  'alice': 'aliceGe004PostReadd',
  'bob': 'bobGe004PostReadd',
  'charlie': 'charlieGe004PostReadd',
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceRemoved'] = _f.snap('alice', members: ['peer-a', 'peer-b']);
  for (final role in _own.keys) {
    for (final other in _own.keys.where((r) => r != role)) {
      p['got:${_own[other]}:$role'] = _f.got(role, _own[other]!);
    }
    p['${role}Final'] = _f.snap(
      role,
      watched: {
        for (final r in _own.keys)
          _own[r]!: [_f.row(_own[r]!, incoming: r != role)],
      },
      extra: {
        'deliveries': [
          _f.delivery(_own[role]!, [
            for (final r in _own.keys)
              if (r != role) r,
          ]),
        ],
      },
    );
  }
  return p;
}

void main() {
  test('observed GE-004 re-add exchange passes the original oracle', () {
    expect(validateProductionGroupGe004(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never removed': (p) =>
        p['aliceRemoved']['memberPeerIds'] = CatalogFixture.all,
    'Charlie not re-added': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Alice copy not addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = ['peer-b'],
    'no durable delivery for Charlie': (p) =>
        p['charlieFinal']['deliveries'] = <Object>[],
    'Bob missed Charlie': (p) =>
        p['got:charlieGe004PostReadd:bob']['watched'] = <String, Object?>{},
    'skipped the re-add acceptance': (p) =>
        (p['flows'] as List).remove('accept-charlie-readd'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = copyProof(fixture());
      entry.value(proof);
      expect(validateProductionGroupGe004(proof), isNotEmpty);
    });
  }
}
