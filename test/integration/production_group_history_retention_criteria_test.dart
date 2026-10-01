import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_history_retention_criteria.dart';

final _t = productionMl017Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _all = ['peer-a', 'peer-b', 'peer-c'];
const _pair = ['peer-a', 'peer-b'];

String _sender(String key) => key.startsWith('alice')
    ? 'peer-a'
    : key.startsWith('bob')
    ? 'peer-b'
    : 'peer-c';

Map<String, Object?> _row(String key, bool incoming, {int epoch = 2}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': _sender(key),
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': epoch,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  List<String> members = _pair,
  bool self = true,
  int epoch = 2,
  Map<String, Object?> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_history_retention',
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

Map<String, Object?> _got(String role, String key, {int epoch = 2}) => _snap(
  role,
  members: _all,
  watched: {
    key: [_row(key, true, epoch: epoch)],
  },
);

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionMl017Flows],
  'aliceRemoved': _snap('alice'),
  'got:$productionMl017BeforeKey:bob': _got(
    'bob',
    productionMl017BeforeKey,
    epoch: 1,
  ),
  'got:$productionMl017BeforeKey:charlie': _got(
    'charlie',
    productionMl017BeforeKey,
    epoch: 1,
  ),
  'got:$productionMl017AliceAfterKey:bob': _got(
    'bob',
    productionMl017AliceAfterKey,
  ),
  'got:$productionMl017BobAfterKey:alice': _got(
    'alice',
    productionMl017BobAfterKey,
  ),
  'charlieRejected': {
    'key': productionMl017CharlieKey,
    'messageId': 'm-c',
    'text': _t[productionMl017CharlieKey],
    'outcome': 'unauthorized',
    'senderPeerId': 'peer-c',
    'keyEpoch': 0,
    'accepted': false,
  },
  'aliceFinal': _snap(
    'alice',
    watched: {
      productionMl017BeforeKey: [_row(productionMl017BeforeKey, false, epoch: 1)],
      productionMl017AliceAfterKey: [_row(productionMl017AliceAfterKey, false)],
      productionMl017BobAfterKey: [_row(productionMl017BobAfterKey, true)],
    },
  ),
  'bobFinal': _snap(
    'bob',
    watched: {
      productionMl017BeforeKey: [_row(productionMl017BeforeKey, true, epoch: 1)],
      productionMl017AliceAfterKey: [_row(productionMl017AliceAfterKey, true)],
      productionMl017BobAfterKey: [_row(productionMl017BobAfterKey, false)],
    },
  ),
  'charlieFinal': _snap(
    'charlie',
    self: false,
    epoch: 0,
    watched: {
      productionMl017BeforeKey: [_row(productionMl017BeforeKey, true, epoch: 1)],
    },
  ),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed ML-017 history retention passes the original oracle', () {
    expect(validateProductionGroupHistoryRetention(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie lost the pre-removal history': (p) =>
        p['charlieFinal']['watched'] = <String, Object?>{},
    'Charlie kept a current key': (p) => p['charlieFinal']['keyEpoch'] = 1,
    'Charlie still a member': (p) => p['charlieFinal']['selfMember'] = true,
    'Charlie decrypted Bob after removal': (p) =>
        p['charlieFinal']['watched'][productionMl017BobAfterKey] = [
          _row(productionMl017BobAfterKey, true),
        ],
    'removed send accepted': (p) {
      p['charlieRejected']['outcome'] = 'success';
      p['charlieRejected']['accepted'] = true;
    },
    'Bob missed Alice after removal': (p) =>
        p['got:$productionMl017AliceAfterKey:bob']['watched'] =
            <String, Object?>{},
    'Bob kept the old epoch': (p) => p['bobFinal']['keyEpoch'] = 1,
    'skipped Bob send flow': (p) =>
        (p['flows'] as List).remove('bob-after-removal'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupHistoryRetention(proof), isNotEmpty);
    });
  }
}
