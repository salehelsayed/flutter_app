import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_reaction_criteria.dart';
import 'production_group_create_criteria_test.dart'
    show groupCreateProofFixture;

Map<String, dynamic> reactionProofFixture() {
  // Shared invitation fixture, with authentic reaction-case identities throughout.
  final proof =
      jsonDecode(
            jsonEncode(groupCreateProofFixture())
                .replaceAll('private_abc_create', 'private_reaction_roundtrip')
                .replaceAll(
                  'ML-001 private ABC hello',
                  'PL-009 Alice reaction target',
                ),
          )
          as Map<String, dynamic>;
  proof['ui']['react-bob'] = {
    'status': 'PASS',
    'exit_status': 0,
    'flows': ['production_catalog_react'],
    'path': 'react-bob',
  };
  Map<String, Object?> identity(String role) => {
    'runId': 'run',
    'role': role,
    'groupId': 'group',
    'messageId': 'message',
    'reactorPeerId': 'bob-peer',
  };
  proof['reactionArmed'] = {
    for (final role in ['alice', 'bob', 'charlie'])
      role: {...identity(role), 'armed': true, 'initialReactionCount': 0},
  };
  proof['reactionFinal'] = {
    for (final role in ['alice', 'bob', 'charlie'])
      role: {
        ...identity(role),
        'outcomes': [
          if (role == 'bob') {'outcome': 'success', 'reactionId': 'reaction'},
        ],
        'changes': [
          if (role != 'bob')
            {
              'type': 'upserted',
              'reactionId': 'reaction',
              'messageId': 'message',
              'senderPeerId': 'bob-peer',
              'emoji': '🔥',
              'timestamp': 'at',
            },
        ],
        'reactions': [
          {
            'id': 'reaction',
            'message_id': 'message',
            'sender_peer_id': 'bob-peer',
            'emoji': '🔥',
            'timestamp': 'at',
            'removed_at': null,
          },
        ],
      },
  };
  return jsonDecode(jsonEncode(proof)) as Map<String, dynamic>;
}

void main() {
  test(
    'preserved PL-009 oracle accepts independently observed real delivery',
    () {
      expect(validateProductionGroupReaction(reactionProofFixture()), isEmpty);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'optimistic row with queued publish': (p) =>
        p['reactionFinal']['bob']['outcomes'][0]['outcome'] = 'queuedForRetry',
    'missing publish outcome': (p) =>
        p['reactionFinal']['bob']['outcomes'] = [],
    'duplicate publish outcome': (p) =>
        (p['reactionFinal']['bob']['outcomes'] as List).add(
          p['reactionFinal']['bob']['outcomes'][0],
        ),
    'Alice SQL without stream': (p) =>
        p['reactionFinal']['alice']['changes'] = [],
    'Charlie SQL without stream': (p) =>
        p['reactionFinal']['charlie']['changes'] = [],
    'wrong stream reaction': (p) =>
        p['reactionFinal']['charlie']['changes'][0]['reactionId'] = 'other',
    'wrong stream emoji': (p) =>
        p['reactionFinal']['alice']['changes'][0]['emoji'] = '👍',
    'removed stream': (p) =>
        p['reactionFinal']['alice']['changes'][0]['type'] = 'removed',
    'wrong stream timestamp': (p) =>
        p['reactionFinal']['alice']['changes'][0]['timestamp'] = 'stale',
    'missing persisted reaction': (p) =>
        p['reactionFinal']['alice']['reactions'] = [],
    'duplicate persisted reaction': (p) =>
        (p['reactionFinal']['bob']['reactions'] as List).add(
          p['reactionFinal']['bob']['reactions'][0],
        ),
    'wrong stored target': (p) =>
        p['reactionFinal']['bob']['reactions'][0]['message_id'] = 'other',
    'wrong stored sender': (p) =>
        p['reactionFinal']['bob']['reactions'][0]['sender_peer_id'] = 'other',
    'tombstoned reaction': (p) =>
        p['reactionFinal']['charlie']['reactions'][0]['removed_at'] = 'later',
    'preexisting reaction': (p) =>
        p['reactionArmed']['bob']['initialReactionCount'] = 1,
    'unarmed receiver': (p) => p['reactionArmed']['alice']['armed'] = false,
    'foreign arm run': (p) => p['reactionArmed']['charlie']['runId'] = 'other',
    'foreign snapshot group': (p) =>
        p['reactionFinal']['charlie']['groupId'] = 'other',
    'missing Charlie': (p) => (p['reactionFinal'] as Map).remove('charlie'),
    'unexpected Alice send': (p) => p['reactionFinal']['alice']['outcomes'] =
        p['reactionFinal']['bob']['outcomes'],
    'failed UI': (p) => p['ui']['react-bob']['status'] = 'FAIL',
    'wrong UI': (p) =>
        p['ui']['react-bob']['flows'] = ['production_catalog_group_send'],
    'reused UI receipt': (p) => p['ui']['react-bob']['path'] = 'send',
    'creation masquerading as reaction': (p) =>
        p['final']['bob']['scenario'] = 'private_abc_create',
    'changed target message identity': (p) =>
        p['final']['bob']['group']['messages'].last['messageId'] = 'other',
    'changed key epoch': (p) => p['final']['charlie']['group']['keyEpoch'] = 2,
    'diverged configuration': (p) =>
        p['final']['charlie']['group']['groupConfigStateHash'] = 'other',
    'unconsumed pending invitation': (p) =>
        p['accepted']['bob']['consumed'] = null,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = reactionProofFixture();
      entry.value(proof);
      expect(validateProductionGroupReaction(proof), isNotEmpty);
    });
  }
}
