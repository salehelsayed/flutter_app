import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_group_removal_pair_criteria.dart';

const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
const _pair = ['peer-a', 'peer-b'];

Map<String, Object?> _snap(
  ProductionRemovalPairCase c,
  String role, {
  List<String> members = _pair,
  bool self = true,
  Map<String, Object?> watched = const {},
  List<Map<String, Object?>> deliveries = const [],
}) => {
  'runId': 'run',
  'role': role,
  'scenario': c.scenario,
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': 2,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': members,
  'selfMember': self,
  'watched': watched,
  'deliveries': deliveries,
};

Map<String, dynamic> fixture(ProductionRemovalPairCase c) {
  final steps = c.steps('run');
  Map<String, Object?> row(int i, bool incoming) => {
    'messageId': 'm$i',
    'groupId': 'g',
    'text': steps[i].text,
    'senderPeerId': _p[c.sender],
    'timestamp': '2026-10-01T12:00:0$i.000Z',
    'keyEpoch': 2,
    'isIncoming': incoming,
    'status': incoming ? 'received' : 'sent',
  };
  final proof = <String, dynamic>{
    'runId': 'run',
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'peers': _p,
    'flows': c.flows('run'),
    'removedAt': '2026-10-01T11:59:00.000Z',
    'aliceRemoved': _snap(c, 'alice'),
    'bobExcluded': _snap(c, 'bob'),
  };
  for (var i = 0; i < steps.length; i++) {
    proof['got:${steps[i].key}:${c.receiver}'] = _snap(
      c,
      c.receiver,
      watched: {
        steps[i].key: [row(i, true)],
      },
    );
  }
  proof['${c.sender}Final'] = _snap(
    c,
    c.sender,
    watched: {
      for (var i = 0; i < steps.length; i++) steps[i].key: [row(i, false)],
    },
    deliveries: [
      for (var i = 0; i < steps.length; i++)
        {
          'cmd': 'group:sendReliable',
          'messageId': 'm$i',
          'ok': true,
          'recipientPeerIds': [_p[c.receiver]],
        },
    ],
  );
  proof['${c.receiver}Final'] = _snap(
    c,
    c.receiver,
    watched: {
      for (var i = 0; i < steps.length; i++) steps[i].key: [row(i, true)],
    },
  );
  proof['charlieFinal'] = _snap(c, 'charlie', self: false);
  return proof;
}

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  for (final c in [productionGe002Case, productionGe003Case]) {
    group(c.scenario, () {
      List<String> validate(Map<String, dynamic> p) =>
          validateProductionRemovalPair(c, p);
      final last = c.steps('run').last.key;
      test('observed removal and ten pair sends pass the original oracle', () {
        expect(validate(fixture(c)), isEmpty);
      });
      final mutations = <String, void Function(Map<String, dynamic>)>{
        'Charlie never removed': (p) =>
            p['aliceRemoved']['memberPeerIds'] = [..._pair, 'peer-c'],
        'durable copy addressed to Charlie': (p) =>
            p['${c.sender}Final']['deliveries'][9]['recipientPeerIds'] = [
              _p[c.receiver],
              'peer-c',
            ],
        'no durable delivery observed': (p) =>
            (p['${c.sender}Final']['deliveries'] as List).removeLast(),
        'receiver missed the last message': (p) =>
            p['got:$last:${c.receiver}']['watched'] = <String, Object?>{},
        'Charlie decrypted a post-removal message': (p) =>
            p['charlieFinal']['watched'] = {
              last: [
                {'messageId': 'x', 'isIncoming': true},
              ],
            },
        'Charlie still a member': (p) =>
            p['charlieFinal']['selfMember'] = true,
        'Charlie lost the retained group': (p) =>
            p['charlieFinal']['groupPresent'] = false,
        'skipped a send flow': (p) =>
            (p['flows'] as List).remove('${c.sender}-send-$last'),
      };
      for (final entry in mutations.entries) {
        test('rejects ${entry.key}', () {
          final proof = _copy(fixture(c));
          entry.value(proof);
          expect(validate(proof), isNotEmpty);
        });
      }
    });
  }
}
