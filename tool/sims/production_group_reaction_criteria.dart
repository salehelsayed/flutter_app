import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_group_create_criteria.dart';

/// Requires independent UI, actual send outcome, receiver stream and SQL proof.
/// Optimistic local storage alone cannot establish an accepted publication.
List<String> validateProductionGroupReaction(Map<String, Object?> proof) {
  final observed = observeProductionCatalogMessage(
    proof,
    scenario: 'private_reaction_roundtrip',
  );
  final failures = [...observed.failures];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  if (failures.isNotEmpty) return failures;
  try {
    final run = proof['runId'];
    final roles = {for (final v in observed.verdicts) v['role']: v};
    final group = roles['alice']!['groupId'];
    final target =
        (roles['alice']!['sentMessages'] as List).single['messageId'];
    final reactor = roles['bob']!['peerId'];
    final arms = proof['reactionArmed'] as Map;
    final snapshots = proof['reactionFinal'] as Map;
    require(
      arms.length == 3 && snapshots.length == 3,
      'exact reaction roles required',
    );
    final ui = proof['ui'] as Map;
    final receipt = ui['react-bob'] as Map;
    require(
      receipt['status'] == 'PASS' &&
          receipt['exit_status'] == 0 &&
          receipt['flows'] is List &&
          (receipt['flows'] as List).length == 1 &&
          (receipt['flows'] as List).single == 'production_catalog_react',
      'exact reaction UI receipt required',
    );
    require(
      receipt['path'] is String &&
          (receipt['path'] as String).isNotEmpty &&
          ui.entries
              .where((e) => e.key != 'react-bob')
              .every((e) => (e.value as Map)['path'] != receipt['path']),
      'independent reaction UI receipt required',
    );
    final outcomes = (snapshots['bob'] as Map)['outcomes'] as List;
    require(outcomes.length == 1, 'exact Bob send outcome required');
    final outcome = outcomes.single as Map;
    final reactionId = outcome['reactionId'];
    require(
      outcome['outcome'] == 'success' &&
          reactionId is String &&
          reactionId.isNotEmpty,
      'Bob reaction did not publish successfully',
    );
    final streamObserved = <String, bool>{};
    for (final role in const ['alice', 'bob', 'charlie']) {
      final arm = arms[role] as Map;
      final snapshot = snapshots[role] as Map;
      for (final observation in [arm, snapshot]) {
        require(
          observation['runId'] == run &&
              observation['role'] == role &&
              observation['groupId'] == group &&
              observation['messageId'] == target &&
              observation['reactorPeerId'] == reactor,
          '$role: reaction identity mismatch',
        );
      }
      require(
        arm['armed'] == true && arm['initialReactionCount'] == 0,
        '$role: fresh reaction observation required',
      );
      if (role != 'bob') {
        require(
          (snapshot['outcomes'] as List).isEmpty,
          '$role: unexpected send outcome',
        );
      }
      final rows = snapshot['reactions'] as List;
      require(rows.length == 1, '$role: reaction must persist exactly once');
      final row = rows.single as Map;
      require(
        row['id'] == reactionId &&
            row['message_id'] == target &&
            row['sender_peer_id'] == reactor &&
            row['emoji'] == '🔥' &&
            row['removed_at'] == null,
        '$role: persisted reaction mismatch',
      );
      final changes = snapshot['changes'] as List;
      streamObserved[role] = changes.any((raw) {
        final change = raw as Map;
        return change['type'] == 'upserted' &&
            change['reactionId'] == reactionId &&
            change['messageId'] == target &&
            change['senderPeerId'] == reactor &&
            change['emoji'] == '🔥' &&
            change['timestamp'] == row['timestamp'];
      });
      if (role != 'bob') {
        require(streamObserved[role]!, '$role: actual receiver stream missing');
      }
    }
    for (final role in const ['alice', 'bob', 'charlie']) {
      roles[role]!['pl009ReactionRoundtripProof'] = {
        'rowId': 'PL-009',
        'activeRoles': ['alice', 'bob', 'charlie'],
        'targetMessageId': target,
        'reactorRole': 'bob',
        'reactionEmoji': '🔥',
        'reactionOutcome': outcome['outcome'],
        'reactionAccepted': outcome['outcome'] == 'success',
        'observedByRole': role,
        'appliedOnceToTarget':
            (snapshots[role]['reactions'] as List).length == 1,
        'persistedReactionCount': (snapshots[role]['reactions'] as List).length,
        'receivedViaGroupReactionStream': streamObserved[role],
        'aliceObservedSignal': streamObserved['alice'],
        'charlieObservedSignal': streamObserved['charlie'],
      };
    }
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: 'private_reaction_roundtrip',
      relayAddresses: observed.relayAddresses,
      verdicts: observed.verdicts,
    );
    require(original.ok, original.detail);
  } catch (error) {
    failures.add(
      'malformed or incomplete reaction proof: ${error.runtimeType}',
    );
  }
  return failures;
}
