import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_group_create_criteria.dart';

/// PL-010 proves a real post-removal domain attempt, retaining the old target
/// and the original five-second receiver absence window. UI removal receipts
/// do not replace independently observed membership, send returns or SQL rows.
List<String> validateProductionGroupRemovedReaction(
  Map<String, Object?> proof,
) {
  final observed = observeProductionCatalogMessage(
    proof,
    scenario: 'private_removed_reaction_rejected',
  );
  final failures = [...observed.failures];
  void require(bool condition, String detail) {
    if (!condition) failures.add(detail);
  }

  if (failures.isNotEmpty) return failures;
  try {
    final roles = {for (final v in observed.verdicts) v['role']: v};
    final group = roles['alice']!['groupId'];
    final target =
        (roles['alice']!['sentMessages'] as List).single['messageId'];
    final reactor = roles['charlie']!['peerId'];
    final run = proof['runId'];
    void identity(Map value, String role) => require(
      value['runId'] == run &&
          value['role'] == role &&
          value['groupId'] == group &&
          value['messageId'] == target &&
          value['reactorPeerId'] == reactor,
      '$role: removed-reaction observation identity mismatch',
    );
    final ui = proof['ui'] as Map;
    final removal = ui['remove-charlie'] as Map;
    require(
      removal['status'] == 'PASS' &&
          removal['exit_status'] == 0 &&
          (removal['flows'] as List).length == 1 &&
          (removal['flows'] as List).single ==
              'production_catalog_remove_charlie',
      'Alice: exact UI removal receipt required',
    );
    require(
      removal['path'] is String &&
          (removal['path'] as String).isNotEmpty &&
          ui.values
                  .whereType<Map>()
                  .where((r) => r['path'] == removal['path'])
                  .length ==
              1,
      'Alice: independent removal receipt required',
    );
    final before = proof['removedBeforeAttempt'] as Map;
    final after = proof['removedFinal'] as Map;
    final armed = proof['reactionArmed'] as Map;
    require(
      before.length == 3 && after.length == 3 && armed.length == 3,
      'exact three removed-reaction roles required',
    );
    final attempt = proof['removedAttempt'] as Map;
    identity(attempt, 'charlie');
    const rejected = {
      'notMember',
      'groupNotFound',
      'groupDissolved',
      'publishFailed',
    };
    require(
      rejected.contains(attempt['outcome']) &&
          attempt['accepted'] == false &&
          attempt['localReactionCountAfterAttempt'] == 0,
      'Charlie: actual rejected attempt with no local reaction required',
    );
    final window = proof['absenceWindowMs'];
    require(
      window is int && window >= 5000,
      'original five-second absence window required',
    );
    for (final role in const ['alice', 'bob', 'charlie']) {
      final arm = armed[role] as Map;
      identity(arm, role);
      require(
        arm['armed'] == true && arm['initialReactionCount'] == 0,
        '$role: fresh observer required',
      );
      for (final raw in [before[role], after[role]]) {
        final state = raw as Map;
        identity(state, role);
        final members = state['memberPeerIds'] as List;
        require(
          !members.contains(reactor),
          '$role: Charlie must be excluded before and after attempt',
        );
        final message = state['target'] as Map;
        require(
          message['messageId'] == target &&
              message['groupId'] == group &&
              message['senderPeerId'] == roles['alice']!['peerId'] &&
              message['text'] ==
                  'PL-010 Alice pre-removal reaction target $run',
          '$role: exact old local target must remain',
        );
        require(
          (state['reactions'] as List).isEmpty,
          '$role: removed reaction mutated SQL state',
        );
        if (role != 'charlie') {
          require(
            members.length == 2 &&
                members.contains(roles['alice']!['peerId']) &&
                members.contains(roles['bob']!['peerId']),
            '$role: remaining membership diverged',
          );
          require(
            state['keyEpoch'] is int && (state['keyEpoch'] as int) >= 2,
            '$role: removal key rotation missing',
          );
        }
      }
      final finalState = after[role] as Map;
      final sends = finalState['outcomes'] as List;
      require(
        (finalState['changes'] as List).isEmpty,
        '$role: removed reaction changed receiver stream',
      );
      require(
        sends.length == (role == 'charlie' ? 1 : 0),
        '$role: exact actual attempt observation required',
      );
      if (role == 'charlie') {
        require(
          sends.single['outcome'] == attempt['outcome'] &&
              sends.single['reactionId'] == null,
          'Charlie: send return and observation disagree',
        );
      }
      roles[role]!.addAll({
        'memberPeerIds': finalState['memberPeerIds'],
        'activeMemberPeerIds': finalState['memberPeerIds'],
        'keyEpoch': finalState['keyEpoch'],
        'groupConfigStateHash': finalState['groupConfigStateHash'],
        'pl010RemovedReactionProof': {
          'rowId': 'PL-010',
          'activeRoles': ['alice', 'bob'],
          'removedRole': 'charlie',
          'reactorRole': 'charlie',
          'targetMessageId': target,
          'reactionEmoji': '🔥',
          'reactionOutcome': attempt['outcome'],
          'reactionAccepted': attempt['accepted'],
          'reactionRejectedOrIgnored': rejected.contains(attempt['outcome']),
          'observedByRole': role,
          'oldLocalMessageRetained': (after['charlie'] as Map)['target'] is Map,
          'removedMemberExcluded': !(finalState['memberPeerIds'] as List)
              .contains(reactor),
          'selfRemovedOrExcluded': !(finalState['memberPeerIds'] as List)
              .contains(reactor),
          'visibleReactionCountForRemovedMember':
              (finalState['reactions'] as List).length,
          'visibleReactionCountForTarget':
              (finalState['reactions'] as List).length,
          'visibleStateUnchanged': (finalState['reactions'] as List).isEmpty,
          'localReactionCountAfterAttempt':
              attempt['localReactionCountAfterAttempt'],
          'aliceObservedNoMutationSignal':
              (after['alice']['reactions'] as List).isEmpty,
          'bobObservedNoMutationSignal':
              (after['bob']['reactions'] as List).isEmpty,
        },
      });
    }
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'private_removed_reaction_rejected',
      relayAddresses: observed.relayAddresses,
      verdicts: observed.verdicts,
    );
    require(original.ok, original.detail);
  } catch (error) {
    failures.add(
      'malformed or incomplete removed-reaction proof: ${error.runtimeType}',
    );
  }
  return failures;
}
