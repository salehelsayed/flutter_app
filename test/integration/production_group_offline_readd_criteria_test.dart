import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_offline_readd_criteria.dart';

final _t = productionOfflineReaddTexts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _all = ['peer-a', 'peer-b', 'peer-c'];

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice')
      ? 'peer-a'
      : key.startsWith('bob')
      ? 'peer-b'
      : 'peer-c',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  int epoch = 2,
  List<String> members = _all,
  bool self = true,
  Map<String, List<Map<String, Object?>>> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_offline_readd',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
};

Map<String, Object?> _got(String role, String key) => _snap(
  role,
  watched: {
    key: [_row(key, incoming: true)],
  },
);

Map<String, List<Map<String, Object?>>> _own(List<String> keys) => {
  for (final k in keys) k: [_row(k, incoming: false)],
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionOfflineReaddFlows],
  'charlieStale': _snap('charlie', epoch: 1),
  'charlieOffline': true,
  'charlieReconnected': true,
  'aliceRemoved': _snap('alice', members: ['peer-a', 'peer-b']),
  'bobExcluded': _snap('bob', members: ['peer-a', 'peer-b']),
  'bobGotDuring': _got('bob', 'aliceDuringCharlieRemoval'),
  'charlieResolved': _snap('charlie', epoch: 1, self: false),
  'charlieRemovedWindow': _snap('charlie', epoch: 1, self: false),
  'aliceGotCharlie': _got('alice', 'charlieAfterImmediateReadd'),
  'bobGotCharlie': _got('bob', 'charlieAfterImmediateReadd'),
  'bobGotAfter': _got('bob', 'aliceAfterImmediateReadd'),
  'charlieGotAfter': _got('charlie', 'aliceAfterImmediateReadd'),
  'aliceGotBob': _got('alice', 'bobAfterOfflineReadd'),
  'charlieGotBob': _got('charlie', 'bobAfterOfflineReadd'),
  'aliceFinal': _snap(
    'alice',
    watched: _own(['aliceDuringCharlieRemoval', 'aliceAfterImmediateReadd']),
  ),
  'bobFinal': _snap('bob', watched: _own(['bobAfterOfflineReadd'])),
  'charlieFinal': _snap(
    'charlie',
    watched: _own(['charlieAfterImmediateReadd']),
  ),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed RA-003 offline re-add passes the unchanged original oracle', () {
    expect(validateProductionGroupOfflineReadd(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never went offline': (p) => p['charlieOffline'] = false,
    'Charlie never reconnected': (p) => p['charlieReconnected'] = false,
    'removal not resolved before re-add': (p) =>
        p['charlieResolved']['selfMember'] = true,
    'Bob still lists Charlie while offline': (p) =>
        p['bobExcluded']['memberPeerIds'] = _all,
    'Charlie not re-added': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Charlie not rejoined': (p) => p['charlieFinal']['selfMember'] = false,
    'Charlie stale epoch': (p) => p['charlieFinal']['keyEpoch'] = 1,
    'Charlie read the removed-window message after re-add': (p) =>
        p['charlieFinal']['watched']['aliceDuringCharlieRemoval'] = [
          _row('aliceDuringCharlieRemoval', incoming: true),
        ],
    'Charlie missed Bob': (p) =>
        p['charlieGotBob']['watched'] = <String, Object?>{},
    'Alice missed Bob': (p) =>
        p['aliceGotBob']['watched'] = <String, Object?>{},
    'Bob send failed': (p) =>
        p['bobFinal']['watched']['bobAfterOfflineReadd'][0]['status'] =
            'failed',
    'skipped Bob send flow': (p) =>
        (p['flows'] as List).remove('bob-after-readd'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupOfflineReadd(proof), isNotEmpty);
    });
  }
}
