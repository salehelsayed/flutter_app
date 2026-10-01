import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm004_criteria.dart';

final _t = productionGm004Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? 'peer-a' : 'peer-b',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  int epoch = 2,
  List<String> members = const ['peer-a', 'peer-b'],
  bool self = true,
  bool present = true,
  Map<String, List<Map<String, Object?>>> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'gm004',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'relayReady': true,
  'lifecycle': 'resumed',
  'groupPresent': present,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': role == 'charlie' ? 'old' : 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionGm004Flows],
  'charlieBefore': _snap(
    'charlie',
    epoch: 1,
    members: ['peer-a', 'peer-b', 'peer-c'],
  ),
  'aliceSentAfter': _snap(
    'alice',
    watched: {
      'aliceAfterCharlieRemove': [
        _row('aliceAfterCharlieRemove', incoming: false),
      ],
    },
  ),
  'bobGotAlice': _snap(
    'bob',
    watched: {
      'aliceAfterCharlieRemove': [
        _row('aliceAfterCharlieRemove', incoming: true),
      ],
    },
  ),
  'bobSentAfter': _snap(
    'bob',
    watched: {
      'bobAfterCharlieRemove': [_row('bobAfterCharlieRemove', incoming: false)],
    },
  ),
  'aliceGotBob': _snap(
    'alice',
    watched: {
      'bobAfterCharlieRemove': [_row('bobAfterCharlieRemove', incoming: true)],
    },
  ),
  'charlieLeak': _snap('charlie', epoch: 1, self: false),
  'charlieRejected': {
    'key': 'charlieAfterCharlieRemove',
    'messageId': 'm-c',
    'text': 'GM-004 Charlie after removal run',
    'outcome': 'groupNotFound',
    'senderPeerId': 'peer-c',
    'keyEpoch': 1,
    'accepted': false,
  },
  'aliceFinal': _snap('alice'),
  'bobFinal': _snap('bob'),
  'charlieFinal': _snap('charlie', epoch: 1, self: false),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed GM-004 removal passes the unchanged original oracle', () {
    expect(validateProductionGroupGm004(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie still a member for Alice': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b', 'peer-c'],
    'Bob without rotated key': (p) => p['bobFinal']['keyEpoch'] = 1,
    'Charlie leaked Alice': (p) => p['charlieLeak']['watched'] = {
      'aliceAfterCharlieRemove': [
        _row('aliceAfterCharlieRemove', incoming: true),
      ],
    },
    'Charlie send accepted': (p) {
      p['charlieRejected']['outcome'] = 'success';
      p['charlieRejected']['accepted'] = true;
    },
    'Charlie holds rotated key': (p) => p['charlieFinal']['keyEpoch'] = 2,
    'Charlie lost the retained group': (p) =>
        p['charlieFinal']['groupPresent'] = false,
    'Bob never received Alice': (p) =>
        p['bobGotAlice']['watched'] = <String, Object?>{},
    'Alice never received Bob': (p) =>
        p['aliceGotBob']['watched'] = <String, Object?>{},
    'skipped back-to-chat flow': (p) =>
        (p['flows'] as List).remove('alice-back-to-chat'),
    'wrong device role': (p) => p['bobFinal']['peerId'] = 'peer-a',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm004(proof), isNotEmpty);
    });
  }
}
