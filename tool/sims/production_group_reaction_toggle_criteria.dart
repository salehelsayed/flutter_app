import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_group_create_criteria.dart';

/// RT-001 retains the original 500 ms, return-to-next-call protocol spacing.
/// Receiver stream removal and final SQL convergence remain independent from
/// the three actual sender returns; a final optimistic row cannot prove them.
List<String> validateProductionGroupReactionToggle(Map<String, Object?> proof) {
  final observed = observeProductionCatalogMessage(
    proof,
    scenario: 'private_reaction_toggle_convergence',
  );
  final failures = [...observed.failures];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  if (failures.isNotEmpty) return failures;
  try {
    final roles = {for (final v in observed.verdicts) v['role']: v};
    final run = proof['runId'];
    final group = roles['alice']!['groupId'];
    final target =
        (roles['alice']!['sentMessages'] as List).single['messageId'];
    final reactor = roles['bob']!['peerId'];
    void identity(Map value, String role) => require(
      value['runId'] == run &&
          value['role'] == role &&
          value['groupId'] == group &&
          value['messageId'] == target &&
          value['reactorPeerId'] == reactor,
      '$role: toggle observation identity mismatch',
    );
    final execution = proof['toggleExecution'] as Map;
    identity(execution, 'bob');
    final returns = execution['outcomes'] as List;
    require(returns.length == 3, 'exact add/remove/re-add returns required');
    for (var i = 0; i < 3; i++) {
      final result = returns[i] as Map;
      require(
        result['operation'] == const ['add', 'remove', 'readd'][i] &&
            result['outcome'] == 'success',
        'toggle operation $i did not publish',
      );
    }
    final gaps = execution['returnToNextCallMs'] as List;
    require(
      gaps.length == 2 && gaps.every((v) => v is int && v >= 500),
      'original 500 ms protocol spacing required',
    );
    final reactionId = returns.last['reactionId'];
    require(
      reactionId is String && reactionId.isNotEmpty,
      'final reaction identity absent',
    );
    final arms = proof['reactionArmed'] as Map;
    final snapshots = proof['reactionFinal'] as Map;
    require(
      arms.length == 3 && snapshots.length == 3,
      'exact toggle roles required',
    );
    final removals = <String, bool>{};
    for (final role in const ['alice', 'bob', 'charlie']) {
      final arm = arms[role] as Map;
      final snapshot = snapshots[role] as Map;
      identity(arm, role);
      identity(snapshot, role);
      require(
        arm['armed'] == true && arm['initialReactionCount'] == 0,
        '$role: fresh toggle observer required',
      );
      final sends = snapshot['outcomes'] as List;
      require(
        sends.length == (role == 'bob' ? 2 : 0),
        '$role: unexpected observed send results',
      );
      if (role == 'bob') {
        for (var i = 0; i < 2; i++) {
          require(
            sends[i]['outcome'] == 'success' &&
                sends[i]['reactionId'] == returns[i * 2]['reactionId'],
            'Bob: actual add/re-add return observation mismatch',
          );
        }
      }
      final rows = snapshot['reactions'] as List;
      require(
        rows.length == 1,
        '$role: final reaction must persist exactly once',
      );
      final row = rows.single as Map;
      require(
        row['id'] == reactionId &&
            row['message_id'] == target &&
            row['sender_peer_id'] == reactor &&
            row['emoji'] == '✅' &&
            row['removed_at'] == null,
        '$role: final reaction did not converge',
      );
      removals[role] = (snapshot['changes'] as List).any((raw) {
        final change = raw as Map;
        return change['type'] == 'removed' &&
            change['messageId'] == target &&
            change['senderPeerId'] == reactor;
      });
      if (role != 'bob') {
        require(removals[role]!, '$role: actual removal stream missing');
      }
    }
    for (final role in const ['alice', 'bob', 'charlie']) {
      roles[role]!['reactionToggleConvergenceProof'] = {
        'rowId': 'RT-001',
        'activeRoles': ['alice', 'bob', 'charlie'],
        'targetMessageId': target,
        'reactorRole': 'bob',
        'finalEmoji': '✅',
        'observedByRole': role,
        'convergedToFinalEmoji':
            snapshots[role]['reactions'].single['emoji'] == '✅',
        'finalReactionCount': (snapshots[role]['reactions'] as List).length,
        'addOutcome': returns[0]['outcome'],
        'removeOutcome': returns[1]['outcome'],
        'readdOutcome': returns[2]['outcome'],
        'observedRemoveEvent': removals[role],
        'aliceConvergedSignal':
            snapshots['alice']['reactions'].single['emoji'] == '✅',
        'charlieConvergedSignal':
            snapshots['charlie']['reactions'].single['emoji'] == '✅',
      };
    }
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'private_reaction_toggle_convergence',
      relayAddresses: observed.relayAddresses,
      verdicts: observed.verdicts,
    );
    require(original.ok, original.detail);
  } catch (error) {
    failures.add('malformed or incomplete toggle proof: ${error.runtimeType}');
  }
  return failures;
}
