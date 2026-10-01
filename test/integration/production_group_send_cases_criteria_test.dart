import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../tool/sims/production_catalog_send_sequence.dart';
import '../../tool/sims/production_group_send_cases_criteria.dart';

const _p = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};

Map<String, Object?> _row(ProductionSendStep s, {required bool incoming}) => {
  'messageId': 'm-${s.key}',
  'groupId': 'g',
  'text': s.text,
  'senderPeerId': _p[s.role],
  'timestamp': '2026-10-01T12:00:00.000Z',
  'keyEpoch': 1,
  'isIncoming': incoming,
  'status': incoming ? 'received' : 'sent',
};

Map<String, Object?> _snap(
  String scenario,
  String role,
  Map<String, List<Map<String, Object?>>> watched,
) => {
  'runId': 'run',
  'role': role,
  'scenario': scenario,
  'peerId': _p[role],
  'transportPeerId': _p[role],
  'lifecycle': 'resumed',
  'groupPresent': true,
  'groupId': 'g',
  'topicName': '/mknoon/group/g',
  'keyEpoch': 1,
  'groupConfigStateHash': 'hash',
  'memberPeerIds': _p.values.toList(),
  'selfMember': true,
  'watched': watched,
};

Map<String, dynamic> fixture(String scenario, List<ProductionSendStep> steps) {
  final proof = <String, dynamic>{
    'runId': 'run',
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'peers': _p,
    'flows': productionSendSequenceFlows(steps),
  };
  for (final s in steps) {
    for (final r in productionCatalogRoles.where((r) => r != s.role)) {
      proof['got:${s.key}:$r'] = _snap(scenario, r, {
        s.key: [_row(s, incoming: true)],
      });
      proof['deReplay:$r'] = {'completedDrainCount': 1};
    }
  }
  for (final r in productionCatalogRoles) {
    proof['${r}Final'] = _snap(scenario, r, {
      for (final s in steps) s.key: [_row(s, incoming: s.role != r)],
    });
  }
  return proof;
}

Map<String, dynamic> _copy(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;

void main() {
  final cases = {
    'gm001': (productionGm001Steps('run'), validateProductionGroupGm001),
    'ge001': (productionGe001Steps('run'), validateProductionGroupGe001),
    'de003': (productionDe003Steps('run'), validateProductionGroupDe003),
  };
  for (final MapEntry(key: scenario, value: (steps, validate))
      in cases.entries) {
    group(scenario, () {
      test('observed sends pass the unchanged original oracle', () {
        expect(validate(fixture(scenario, steps)), isEmpty);
      });
      final last = steps.last;
      final receiver = productionCatalogRoles.firstWhere((r) => r != last.role);
      final mutations = <String, void Function(Map<String, dynamic>)>{
        'a receiver missed the message': (p) =>
            p['got:${last.key}:$receiver']['watched'] = <String, Object?>{},
        'a receiver persisted it twice': (p) =>
            (p['${receiver}Final']['watched'][last.key] as List).add(
              _row(last, incoming: true),
            ),
        'the send failed': (p) =>
            p['${last.role}Final']['watched'][last.key][0]['status'] = 'failed',
        'a different message id arrived': (p) =>
            p['got:${last.key}:$receiver']['watched'][last.key][0]['messageId'] =
                'other',
        'skipped a send flow': (p) => (p['flows'] as List).remove(last.label),
        'wrong scenario observed': (p) =>
            p['${receiver}Final']['scenario'] = 'other',
      };
      for (final entry in mutations.entries) {
        test('rejects ${entry.key}', () {
          final proof = _copy(fixture(scenario, steps));
          entry.value(proof);
          expect(validate(proof), isNotEmpty);
        });
      }
    });
  }
  test('de003 rejects a missing replay drain', () {
    final proof = _copy(fixture('de003', productionDe003Steps('run')));
    proof['deReplay:bob'] = {'completedDrainCount': 0};
    expect(validateProductionGroupDe003(proof), isNotEmpty);
  });
}
