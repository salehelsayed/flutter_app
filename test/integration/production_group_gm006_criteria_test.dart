import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_gm006_criteria.dart';

final _t = productionGm006Texts('run');
const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _all = ['peer-a', 'peer-b', 'peer-c'];

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? 'peer-a' : 'peer-c',
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 2,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String role, {
  int epoch = 2,
  List<String> members = _all,
  Map<String, List<Map<String, Object?>>> watched = const {},
}) => {
  'runId': 'run',
  'role': role,
  'scenario': 'gm006',
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': epoch,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': true,
  'watched': watched,
};

Map<String, Object?> _got(String role, String key) => _snap(
  role,
  watched: {
    key: [_row(key, incoming: true)],
  },
);

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'peers': _p,
  'flows': [...productionGm006Flows],
  'aliceRemoved': _snap('alice', members: ['peer-a', 'peer-b']),
  'bobGotDuring': _got('bob', 'aliceDuringCharlieRemoval'),
  'charlieRemovedWindow': _snap('charlie', epoch: 1),
  'aliceGotCharlie': _got('alice', 'charlieAfterImmediateReadd'),
  'bobGotCharlie': _got('bob', 'charlieAfterImmediateReadd'),
  'bobGotAfter': _got('bob', 'aliceAfterImmediateReadd'),
  'charlieGotAfter': _got('charlie', 'aliceAfterImmediateReadd'),
  'aliceFinal': _snap(
    'alice',
    watched: {
      'aliceDuringCharlieRemoval': [
        _row('aliceDuringCharlieRemoval', incoming: false),
      ],
      'aliceAfterImmediateReadd': [
        _row('aliceAfterImmediateReadd', incoming: false),
      ],
    },
  ),
  'bobFinal': _snap('bob'),
  'charlieFinal': _snap(
    'charlie',
    watched: {
      'charlieAfterImmediateReadd': [
        _row('charlieAfterImmediateReadd', incoming: false),
      ],
    },
  ),
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('observed GM-006 immediate re-add passes the unchanged original oracle', () {
    expect(validateProductionGroupGm006(fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    'Charlie never removed': (p) =>
        p['aliceRemoved']['memberPeerIds'] = _all,
    'Charlie not re-added': (p) =>
        p['aliceFinal']['memberPeerIds'] = ['peer-a', 'peer-b'],
    'Charlie stale epoch after re-add': (p) =>
        p['charlieFinal']['keyEpoch'] = 1,
    'no rotation': (p) {
      for (final r in ['alice', 'bob', 'charlie']) {
        p['${r}Final']['keyEpoch'] = 1;
      }
    },
    'Charlie read the removed-window message': (p) =>
        p['charlieRemovedWindow']['watched'] = {
          'aliceDuringCharlieRemoval': [
            _row('aliceDuringCharlieRemoval', incoming: true),
          ],
        },
    'Bob missed the removed-window message': (p) =>
        p['bobGotDuring']['watched'] = <String, Object?>{},
    'Alice missed Charlie': (p) =>
        p['aliceGotCharlie']['watched'] = <String, Object?>{},
    'Charlie missed Alice': (p) =>
        p['charlieGotAfter']['watched'] = <String, Object?>{},
    'Charlie send failed': (p) =>
        p['charlieFinal']['watched']['charlieAfterImmediateReadd'][0]['status'] =
            'failed',
    'Charlie read the removed-window message after re-add': (p) =>
        p['charlieFinal']['watched']['aliceDuringCharlieRemoval'] = [
          _row('aliceDuringCharlieRemoval', incoming: true),
        ],
    'skipped the re-add flow': (p) =>
        (p['flows'] as List).remove('readd-charlie'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupGm006(proof), isNotEmpty);
    });
  }
}
