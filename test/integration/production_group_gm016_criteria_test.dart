import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm016_criteria.dart';

const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _all = ['peer-a', 'peer-b', 'peer-c'];
const _pair = ['peer-a', 'peer-b'];
const _k = productionGm016Key;

Map<String, Object?> _row(bool incoming) => {
  'messageId': 'm-a',
  'groupId': 'g',
  'text': productionGm016Text('run'),
  'senderPeerId': 'peer-a',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

const _leave = [
  {'event': 'GROUP_FL_BRIDGE_LEAVE_REQUEST'},
  {
    'event': 'GROUP_FL_BRIDGE_LEAVE_RESPONSE',
    'details': {'severity': 'info'},
  },
];

Map<String, Object?> _snap(
  String role, {
  List<String> members = _pair,
  bool self = true,
  int epoch = 2,
  bool relay = true,
  Map<String, Object?> watched = const {},
  Map<String, Object?> extra = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'gm016',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'relayReady': relay,
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
  ...extra,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionGm016Flows],
  'quietWindowMs': 5003,
  'charlieBefore': _snap('charlie', members: _all),
  'charlieAtRemoval': _snap(
    'charlie',
    self: false,
    epoch: 0,
    extra: {
      'flowEvents': _leave,
      'inbound': {'message': 4},
    },
  ),
  'charlieAfterQuiet': _snap(
    'charlie',
    self: false,
    epoch: 0,
    extra: {'flowEvents': _leave},
  ),
  'aliceRemoved': _snap('alice'),
  'got:$_k:bob': _snap(
    'bob',
    watched: {
      _k: [_row(true)],
    },
  ),
  'aliceFinal': _snap(
    'alice',
    watched: {
      _k: [_row(false)],
    },
    extra: {
      'deliveries': [
        {
          'messageId': 'm-a',
          'ok': true,
          'recipientPeerIds': ['peer-b'],
        },
      ],
    },
  ),
  'bobFinal': _snap(
    'bob',
    watched: {
      _k: [_row(true)],
    },
  ),
  'charlieFinal': _snap(
    'charlie',
    self: false,
    epoch: 0,
    extra: {
      'flowEvents': _leave,
      'inbound': {'message': 4},
    },
  ),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed GM-016 unsubscribe passes the original oracle', () {
    expect(validateProductionGroupGm016(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never requested a leave': (p) =>
        p['charlieFinal']['flowEvents'] = <Object>[],
    'Charlie still receives group traffic': (p) =>
        p['charlieFinal']['inbound'] = {'message': 5},
    'Charlie rejoined after the quiet window': (p) =>
        p['charlieFinal']['flowEvents'] = [
          ..._leave,
          {'event': 'GROUP_FL_BRIDGE_JOIN_REQUEST'},
        ],
    'Charlie kept a key': (p) => p['charlieFinal']['keyEpoch'] = 1,
    'Charlie retained his own member row': (p) =>
        p['charlieFinal']['memberPeerIds'] = _all,
    'durable copy addressed to Charlie': (p) =>
        p['aliceFinal']['deliveries'][0]['recipientPeerIds'] = [
          'peer-b',
          'peer-c',
        ],
    'quiet window too short': (p) => p['quietWindowMs'] = 1000,
    'Charlie was not active before': (p) =>
        p['charlieBefore']['selfMember'] = false,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm016(proof), isNotEmpty);
    });
  }
}
