import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_up012_criteria.dart';
import 'support/production_catalog_fixture.dart';

const _alice = 'aliceAfterCharlieRemove';
const _bob = 'bobAfterCharlieRemove';
final _f = CatalogFixture(
  'private_removed_notification_privacy',
  productionUp012Texts('run'),
  productionUp012Flows,
);
const _pair = ['peer-a', 'peer-b'];

Map<String, Object?> _note(String body) => {
  'kind': 'message',
  'silent': false,
  'bodySha256': sha256.convert(utf8.encode(body)).toString(),
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  p['aliceFinal'] = _f.snap(
    'alice',
    members: _pair,
    watched: {
      _alice: [_f.row(_alice, incoming: false)],
      _bob: [_f.row(_bob, incoming: true)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_alice, ['bob']),
      ],
      'notifications': [_note('Journeybob: x')],
    },
  );
  p['bobFinal'] = _f.snap(
    'bob',
    members: _pair,
    watched: {
      _bob: [_f.row(_bob, incoming: false)],
      _alice: [_f.row(_alice, incoming: true)],
    },
    extra: {
      'deliveries': [
        _f.delivery(_bob, ['alice']),
      ],
      'notifications': [_note('Journeyalice: x')],
    },
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    members: _pair,
    self: false,
    extra: {'notifications': <Object?>[]},
  );
  p['got:$_bob:alice'] = _f.got('alice', _bob);
  p['got:$_alice:bob'] = _f.got('bob', _alice);
  p['aliceRemoved'] = _f.snap('alice', members: _pair);
  p['charlieBefore'] = _f.snap('charlie');
  return p;
}

void main() {
  test('observed UP-012 passes the original oracle', () {
    expect(validateProductionGroupUp012(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'removed Charlie showed a notification': (p) =>
        p['charlieFinal']['notifications'] = [_note('anything')],
    'Charlie holds a post-removal message': (p) =>
        p['charlieFinal']['watched'] = {
          _bob: [_f.row(_bob, incoming: true)],
        },
    'Alice showed no notification': (p) =>
        p['aliceFinal']['notifications'] = <Object?>[],
    'Bob still lists Charlie': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b', 'peer-c'],
    'Charlie was not a member before the removal': (p) =>
        p['charlieBefore']['selfMember'] = false,
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupUp012(proof), isNotEmpty);
    });
  }
}
