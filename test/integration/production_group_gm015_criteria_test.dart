import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_gm015_criteria.dart';
import 'support/production_catalog_fixture.dart';

final _f = CatalogFixture('gm015', productionGm015Texts('run'), productionGm015Flows);
const _bob = 'bobAfterBlockedAdminSelfRemoval';
const _charlie = 'charlieAfterBlockedAdminLeave';
const _details = [
  {'peerId': 'peer-a', 'role': 'admin'},
  {'peerId': 'peer-b', 'role': 'writer'},
  {'peerId': 'peer-c', 'role': 'writer'},
];

Map<String, Object?> _group(Map<String, Object?> extra) => {
  'createdBy': 'peer-a',
  'isDissolved': false,
  'memberDetails': _details,
  'topicLeaves': <String, int>{},
  'memberRemovedTimelineIds': <String>[],
  ...extra,
};

Map<String, dynamic> fixture() {
  final p = _f.base();
  for (final r in ['alice', 'bob', 'charlie']) {
    p['${r}Before'] = _f.snap(r, extra: _group({}));
  }
  p['aliceAfterAttempt'] = _f.snap(
    'alice',
    extra: _group({
      'exits': {
        'g': {
          'counts': {'request_leave': 1},
          'request': {'status': 'blockedLastAdmin'},
        },
      },
    }),
  );
  p['aliceExitAfter'] = {'intentPresent': false, 'pendingBroadcastIds': []};
  for (final (role, key) in [
    ('alice', _bob),
    ('charlie', _bob),
    ('alice', _charlie),
    ('bob', _charlie),
  ]) {
    p['got:$key:$role'] = _f.got(role, key);
  }
  Map<String, Object?> rows(String role) => {
    for (final k in [_bob, _charlie])
      k: [_f.row(k, incoming: productionGm015Texts('run')[k]!.role != role)],
  };
  p['aliceFinal'] = _f.snap('alice', watched: rows('alice'), extra: _group({}));
  p['bobFinal'] = _f.snap(
    'bob',
    watched: rows('bob'),
    extra: _group({
      'deliveries': [_f.delivery(_bob, ['alice', 'charlie'])],
    }),
  );
  p['charlieFinal'] = _f.snap(
    'charlie',
    watched: rows('charlie'),
    extra: _group({
      'deliveries': [_f.delivery(_charlie, ['alice', 'bob'])],
    }),
  );
  return p;
}

void main() {
  test('observed GM-015 blocked admin leave passes the original oracle', () {
    expect(validateProductionGroupGm015(fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'the leave was not blocked': (p) =>
        p['aliceAfterAttempt']['exits']['g']['request']['status'] = 'started',
    'no leave request reached the app': (p) =>
        p['aliceAfterAttempt']['exits'] = {},
    'a notice was prepared anyway': (p) =>
        p['aliceAfterAttempt']['exits']['g']['counts']['notice_prepare'] = 1,
    'a native topic leave happened': (p) =>
        p['aliceAfterAttempt']['topicLeaves'] = {'g': 1},
    'an exit intent was left behind': (p) =>
        p['aliceExitAfter']['intentPresent'] = true,
    'Bob lost Charlie': (p) =>
        p['bobFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'the key rotated': (p) => p['charlieFinal']['keyEpoch'] = 3,
    'Alice is no longer sole admin': (p) =>
        p['bobFinal']['memberDetails'] = [
          {'peerId': 'peer-a', 'role': 'admin'},
          {'peerId': 'peer-b', 'role': 'admin'},
        ],
    'Charlie never got Bob': (p) =>
        p['got:$_bob:charlie']['watched'] = <String, Object?>{},
  };
  for (final e in mutations.entries) {
    test('rejects ${e.key}', () {
      final proof = copyProof(fixture());
      e.value(proof);
      expect(validateProductionGroupGm015(proof), isNotEmpty);
    });
  }
}
