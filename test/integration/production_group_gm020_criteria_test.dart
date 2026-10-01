import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm020_criteria.dart';

final _t = productionGm020Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _pair = ['peer-a', 'peer-b'];
const _keys = [productionGm020ImmediateKey, productionGm020OfflineKey];

Map<String, Object?> _row(String key, bool incoming) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': 'peer-a',
  'timestamp': key == productionGm020ImmediateKey
      ? '2026-10-01T12:00:10.000Z'
      : '2026-10-01T12:00:40.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  bool self = true,
  Map<String, Object?> watched = const {},
  List<Map<String, Object?>> deliveries = const [],
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'gm020',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': 2,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': _pair,
  'selfMember': self,
  'watched': watched,
  'deliveries': deliveries,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionGm020Flows],
  'removedAt': '2026-10-01T12:00:00.000Z',
  'charlieOffline': true,
  'aliceRemoved': _snap('alice'),
  for (final k in _keys)
    'got:$k:bob': _snap(
      'bob',
      watched: {
        k: [_row(k, true)],
      },
    ),
  'aliceFinal': _snap(
    'alice',
    watched: {
      for (final k in _keys) k: [_row(k, false)],
    },
    deliveries: [
      for (final k in _keys)
        {
          'cmd': 'group:sendReliable',
          'messageId': 'm-$k',
          'ok': true,
          'recipientPeerIds': ['peer-b'],
        },
    ],
  ),
  'bobFinal': _snap(
    'bob',
    watched: {
      for (final k in _keys) k: [_row(k, true)],
    },
  ),
  'charlieFinal': _snap('charlie', self: false),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed GM-020 removal and exclusion passes the original oracle', () {
    expect(validateProductionGroupGm020(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never removed': (p) =>
        p['aliceRemoved']['memberPeerIds'] = [..._pair, 'peer-c'],
    'immediate copy addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'no durable delivery observed': (p) =>
        (p['aliceFinal']['deliveries'] as List).removeLast(),
    'Charlie never went offline': (p) => p['charlieOffline'] = false,
    'Charlie decrypted the offline message': (p) =>
        p['charlieFinal']['watched'] = {
          productionGm020OfflineKey: [_row(productionGm020OfflineKey, true)],
        },
    'Bob missed the immediate message': (p) =>
        p['got:$productionGm020ImmediateKey:bob']['watched'] =
            <String, Object?>{},
    'removal after the first send': (p) =>
        p['removedAt'] = '2026-10-01T12:00:20.000Z',
    'skipped the offline send flow': (p) =>
        (p['flows'] as List).remove('alice-offline'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm020(proof), isNotEmpty);
    });
  }
}
