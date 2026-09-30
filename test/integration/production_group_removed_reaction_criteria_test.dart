import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/sims/production_group_removed_reaction_criteria.dart';
import 'production_group_create_criteria_test.dart'
    show groupCreateProofFixture;

Map<String, dynamic> removedReactionProofFixture() {
  final p =
      jsonDecode(
            jsonEncode(groupCreateProofFixture())
                .replaceAll(
                  'private_abc_create',
                  'private_removed_reaction_rejected',
                )
                .replaceAll(
                  'ML-001 private ABC hello',
                  'PL-010 Alice pre-removal reaction target',
                ),
          )
          as Map<String, dynamic>;
  Map<String, Object?> identity(String role) => {
    'runId': 'run',
    'role': role,
    'groupId': 'group',
    'messageId': 'message',
    'reactorPeerId': 'charlie-peer',
  };
  p['ui']['remove-charlie'] = {
    'status': 'PASS',
    'exit_status': 0,
    'flows': ['production_catalog_remove_charlie'],
    'path': 'remove-charlie',
  };
  p['reactionArmed'] = {
    for (final role in ['alice', 'bob', 'charlie'])
      role: {...identity(role), 'armed': true, 'initialReactionCount': 0},
  };
  p['removedBeforeAttempt'] = {
    for (final role in ['alice', 'bob', 'charlie'])
      role: {
        ...identity(role),
        'memberPeerIds': ['alice-peer', 'bob-peer'],
        'keyEpoch': role == 'charlie' ? 1 : 2,
        'groupConfigStateHash': 'after-removal',
        'target': {
          'messageId': 'message',
          'groupId': 'group',
          'senderPeerId': 'alice-peer',
          'text': 'PL-010 Alice pre-removal reaction target run',
        },
        'reactions': [],
      },
  };
  p['removedFinal'] = jsonDecode(jsonEncode(p['removedBeforeAttempt']));
  for (final role in ['alice', 'bob', 'charlie']) {
    p['removedFinal'][role]['changes'] = [];
    p['removedFinal'][role]['outcomes'] = [
      if (role == 'charlie') {'outcome': 'notMember', 'reactionId': null},
    ];
  }
  p['removedAttempt'] = {
    ...identity('charlie'),
    'outcome': 'notMember',
    'accepted': false,
    'localReactionCountAfterAttempt': 0,
  };
  p['absenceWindowMs'] = 5000;
  return p;
}

void main() {
  test(
    'unchanged PL-010 oracle accepts actual rejection and independent absence',
    () {
      expect(
        validateProductionGroupRemovedReaction(removedReactionProofFixture()),
        isEmpty,
      );
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'wrong original scenario': (p) =>
        p['final']['alice']['scenario'] = 'private_abc_create',
    'UI removal failed': (p) => p['ui']['remove-charlie']['status'] = 'FAIL',
    'different UI operation': (p) =>
        p['ui']['remove-charlie']['flows'] = ['production_catalog_react'],
    'reused UI receipt': (p) =>
        p['ui']['remove-charlie']['path'] = p['ui']['create']['path'],
    'Charlie still a member before attempt': (p) =>
        p['removedBeforeAttempt']['charlie']['memberPeerIds'].add(
          'charlie-peer',
        ),
    'Alice retains removed member': (p) =>
        p['removedFinal']['alice']['memberPeerIds'].add('charlie-peer'),
    'Bob loses remaining member': (p) =>
        p['removedFinal']['bob']['memberPeerIds'].remove('alice-peer'),
    'wrong post-removal target': (p) =>
        p['removedBeforeAttempt']['charlie']['target']['messageId'] = 'foreign',
    'lost old target': (p) => p['removedFinal']['charlie']['target'] = null,
    'different old target author': (p) =>
        p['removedFinal']['charlie']['target']['senderPeerId'] = 'bob-peer',
    'wrong initial observer': (p) =>
        p['reactionArmed']['charlie']['reactorPeerId'] = 'bob-peer',
    'preexisting reaction': (p) =>
        p['reactionArmed']['alice']['initialReactionCount'] = 1,
    'foreign attempt': (p) => p['removedAttempt']['runId'] = 'other',
    'accepted removed reaction': (p) => p['removedAttempt']['accepted'] = true,
    'queued is not rejection': (p) =>
        p['removedAttempt']['outcome'] = 'queuedForRetry',
    'success is not rejection': (p) =>
        p['removedAttempt']['outcome'] = 'success',
    'optimistic local reaction': (p) =>
        p['removedAttempt']['localReactionCountAfterAttempt'] = 1,
    'missing real outcome': (p) =>
        p['removedFinal']['charlie']['outcomes'] = [],
    'duplicate actual operation': (p) =>
        p['removedFinal']['charlie']['outcomes'].add({'outcome': 'notMember'}),
    'mismatched actual outcome': (p) =>
        p['removedFinal']['charlie']['outcomes'][0]['outcome'] = 'success',
    'short absence window': (p) => p['absenceWindowMs'] = 4999,
    'rotated key missing': (p) => p['removedFinal']['bob']['keyEpoch'] = 1,
    'Alice stored reaction': (p) =>
        p['removedFinal']['alice']['reactions'].add({'id': 'forbidden'}),
    'Bob saw transient reaction': (p) =>
        p['removedFinal']['bob']['changes'].add({'type': 'upserted'}),
    'missing Bob snapshot': (p) => p['removedFinal'].remove('bob'),
  };
  for (final mutation in mutations.entries) {
    test(mutation.key, () {
      final p = removedReactionProofFixture();
      mutation.value(p);
      expect(validateProductionGroupRemovedReaction(p), isNotEmpty);
    });
  }
}
