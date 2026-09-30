import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_relay_only_criteria.dart';

final _t = productionRelayOnlyTexts('run');
const _peers = {
  'alice': '12D3KooWAlice000',
  'bob': '12D3KooWBobb000',
  'charlie': '12D3KooWChar000',
};

Map<String, Object?> _row(String key, {required bool incoming}) => {
  'messageId': 'm-$key',
  'groupId': 'g',
  'text': _t[key],
  'senderPeerId': key.startsWith('alice') ? _peers['alice'] : _peers['bob'],
  'timestamp': '2026-09-30T12:00:00.000Z',
  'keyEpoch': 1,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _discovery({
  String path = 'relay',
  bool attemptedDirect = false,
  int directAddrCount = 0,
}) => {
  'event': 'GROUP_DISCOVERY',
  'layer': 'GO',
  'details': {
    'peerIdPrefix': '12D3KooWBobb',
    'path': path,
    'attemptedDirect': attemptedDirect,
    'directAddrCount': directAddrCount,
  },
};

Map<String, Object?> _final(String role, Map<String, List<Map>> watched) => {
  'runId': 'run',
  'role': role,
  'scenario': 'private_relay_only_delivery',
  'peerId': _peers[role],
  'transportPeerId': _peers[role],
  'lifecycle': 'resumed',
  'flowEventOverflow': false,
  'advertisesRelayOnly': role == 'bob',
  'flowEvents': role == 'bob' ? [] : [_discovery()],
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': 1,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': _peers.values.toList(),
  'selfMember': true,
  'watched': watched,
};

Map<String, dynamic> fixture() => {
  'runId': 'run',
  'relayAddresses': expectedMultiPartyRelayAddresses,
  'flows': [...productionRelayOnlyFlows],
  'final': {
    'alice': _final('alice', {
      'aliceToRelayOnlyBob': [_row('aliceToRelayOnlyBob', incoming: false)],
      'bobRelayOnlyPublishBack': [
        _row('bobRelayOnlyPublishBack', incoming: true),
      ],
    }),
    'bob': _final('bob', {
      'aliceToRelayOnlyBob': [_row('aliceToRelayOnlyBob', incoming: true)],
      'bobRelayOnlyPublishBack': [
        _row('bobRelayOnlyPublishBack', incoming: false),
      ],
    }),
    'charlie': _final('charlie', {
      'aliceToRelayOnlyBob': [_row('aliceToRelayOnlyBob', incoming: true)],
      'bobRelayOnlyPublishBack': [
        _row('bobRelayOnlyPublishBack', incoming: true),
      ],
    }),
  },
};

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  test('relay-routed delivery passes the unchanged original oracle', () {
    expect(validateProductionGroupRelayOnly(fixture()), isEmpty);
  });

  Map fin(Map p, String role) => p['final'][role] as Map;
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'no relay route to Bob observed': (p) {
      for (final r in ['alice', 'charlie']) {
        fin(p, r)['flowEvents'] = [];
      }
    },
    'direct path attempted everywhere': (p) {
      for (final r in ['alice', 'charlie']) {
        fin(p, r)['flowEvents'] = [_discovery(attemptedDirect: true)];
      }
    },
    'Bob had direct addresses': (p) {
      for (final r in ['alice', 'charlie']) {
        fin(p, r)['flowEvents'] = [_discovery(directAddrCount: 2)];
      }
    },
    'route event for another peer': (p) {
      for (final r in ['alice', 'charlie']) {
        ((fin(p, r)['flowEvents'] as List).single as Map)['details']
            ['peerIdPrefix'] = '12D3KooWChar';
      }
    },
    'Charlie missed Bob': (p) =>
        (fin(p, 'charlie')['watched'] as Map)['bobRelayOnlyPublishBack'] = [],
    'duplicate at Bob': (p) =>
        ((fin(p, 'bob')['watched'] as Map)['aliceToRelayOnlyBob'] as List).add(
          _row('aliceToRelayOnlyBob', incoming: true),
        ),
    'Alice send failed': (p) =>
        (((fin(p, 'alice')['watched'] as Map)['aliceToRelayOnlyBob'] as List)
                .single
            as Map)['status'] = 'failed',
    'membership changed': (p) =>
        fin(p, 'charlie')['memberPeerIds'] = [_peers['alice'], _peers['charlie']],
    'flow events overflowed': (p) => fin(p, 'alice')['flowEventOverflow'] = true,
    'skipped publish back': (p) => (p['flows'] as List).removeLast(),
    'Bob not advertising relay-only': (p) =>
        fin(p, 'bob')['advertisesRelayOnly'] = false,
    'Alice advertising relay-only': (p) =>
        fin(p, 'alice')['advertisesRelayOnly'] = true,
    'background lifecycle': (p) => fin(p, 'bob')['lifecycle'] = 'paused',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _copy(fixture());
      entry.value(proof);
      expect(validateProductionGroupRelayOnly(proof), isNotEmpty);
    });
  }
}
