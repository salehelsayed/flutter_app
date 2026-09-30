import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_reaction_toggle_criteria.dart';
import 'production_group_reaction_criteria_test.dart' show reactionProofFixture;

Map<String, dynamic> reactionToggleProofFixture() {
  final p =
      jsonDecode(
            jsonEncode(reactionProofFixture())
                .replaceAll(
                  'private_reaction_roundtrip',
                  'private_reaction_toggle_convergence',
                )
                .replaceAll(
                  'PL-009 Alice reaction target',
                  'RT-001 Alice reaction toggle target',
                ),
          )
          as Map<String, dynamic>;
  (p['ui'] as Map).remove('react-bob');
  p['toggleExecution'] = {
    'runId': 'run',
    'role': 'bob',
    'groupId': 'group',
    'messageId': 'message',
    'reactorPeerId': 'bob-peer',
    'outcomes': [
      {'operation': 'add', 'outcome': 'success', 'reactionId': 'initial'},
      {'operation': 'remove', 'outcome': 'success'},
      {'operation': 'readd', 'outcome': 'success', 'reactionId': 'final'},
    ],
    'returnToNextCallMs': [500, 501],
  };
  for (final role in ['alice', 'bob', 'charlie']) {
    final s = p['reactionFinal'][role];
    s['reactions'][0]['emoji'] = '✅';
    s['reactions'][0]['id'] = 'final';
    s['outcomes'] = [
      if (role == 'bob') ...[
        {'outcome': 'success', 'reactionId': 'initial'},
        {'outcome': 'success', 'reactionId': 'final'},
      ],
    ];
    s['changes'] = [
      if (role != 'bob')
        {'type': 'removed', 'messageId': 'message', 'senderPeerId': 'bob-peer'},
    ];
  }
  return p;
}

void main() {
  test(
    'preserved RT-001 oracle requires actual removal and final convergence',
    () {
      expect(
        validateProductionGroupReactionToggle(reactionToggleProofFixture()),
        isEmpty,
      );
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'missing return': (p) =>
        (p['toggleExecution']['outcomes'] as List).removeLast(),
    'queued initial add': (p) =>
        p['toggleExecution']['outcomes'][0]['outcome'] = 'queuedForRetry',
    'queued remove': (p) =>
        p['toggleExecution']['outcomes'][1]['outcome'] = 'queuedForRetry',
    'queued re-add': (p) =>
        p['toggleExecution']['outcomes'][2]['outcome'] = 'queuedForRetry',
    'wrong operation order': (p) =>
        p['toggleExecution']['outcomes'][1]['operation'] = 'add',
    'missing controlled spacing': (p) =>
        p['toggleExecution']['returnToNextCallMs'] = [],
    'short controlled spacing': (p) =>
        p['toggleExecution']['returnToNextCallMs'][0] = 499,
    'foreign invocation': (p) => p['toggleExecution']['runId'] = 'other',
    'foreign reactor': (p) =>
        p['toggleExecution']['reactorPeerId'] = 'alice-peer',
    'missing observer arm': (p) =>
        (p['reactionArmed'] as Map).remove('charlie'),
    'preexisting reaction': (p) =>
        p['reactionArmed']['alice']['initialReactionCount'] = 1,
    'missing actual send observation': (p) =>
        p['reactionFinal']['bob']['outcomes'] = [],
    'divergent actual send': (p) =>
        p['reactionFinal']['bob']['outcomes'][1]['reactionId'] = 'other',
    'unexpected receiver send': (p) => p['reactionFinal']['alice']['outcomes'] =
        p['reactionFinal']['bob']['outcomes'],
    'Alice never saw removal': (p) =>
        p['reactionFinal']['alice']['changes'] = [],
    'Charlie never saw removal': (p) =>
        p['reactionFinal']['charlie']['changes'] = [],
    'foreign removal target': (p) =>
        p['reactionFinal']['alice']['changes'][0]['messageId'] = 'other',
    'foreign removal sender': (p) =>
        p['reactionFinal']['charlie']['changes'][0]['senderPeerId'] = 'other',
    'initial emoji survives': (p) =>
        p['reactionFinal']['charlie']['reactions'][0]['emoji'] = '🔥',
    'empty final state': (p) => p['reactionFinal']['alice']['reactions'] = [],
    'duplicate final state': (p) =>
        (p['reactionFinal']['bob']['reactions'] as List).add(
          p['reactionFinal']['bob']['reactions'][0],
        ),
    'stale tombstone': (p) =>
        p['reactionFinal']['bob']['reactions'][0]['removed_at'] = 'at',
    'wrong final ID': (p) =>
        p['reactionFinal']['alice']['reactions'][0]['id'] = 'initial',
    'wrong case': (p) =>
        p['final']['charlie']['scenario'] = 'private_reaction_roundtrip',
    'divergent configuration': (p) =>
        p['final']['charlie']['group']['groupConfigStateHash'] = 'other',
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final p = reactionToggleProofFixture();
      entry.value(p);
      expect(validateProductionGroupReactionToggle(p), isNotEmpty);
    });
  }
}
