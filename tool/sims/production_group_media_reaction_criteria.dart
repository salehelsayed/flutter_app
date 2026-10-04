import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _target = 'aliceMediaReactionTarget';
const _roles = ['alice', 'bob', 'charlie'];

/// Text of catalog `private_media_reaction_roundtrip` (L-01), identical to the
/// original harness; Alice sends it as the caption of one real image.
Map<String, ProductionCatalogText> productionMediaReactionTexts(String run) => {
  _target: (role: 'alice', text: 'L-01 Alice media reaction target $run'),
};

const productionMediaReactionFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'send-media',
  'react-bob',
];

/// The original's L-01 proof from actual production observations: Alice's
/// real image message (its attachment row count), Bob's UI reaction with
/// its publish outcome, and each role's persisted reaction row and receiver
/// stream change (`catalog_arm_reaction` / `catalog_reaction_snapshot`).
List<String> validateProductionGroupMediaReaction(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'private_media_reaction_roundtrip',
      flows: productionMediaReactionFlows,
      verdicts: (c) {
        final sent = c.sent('alice', _target);
        final received = {
          for (final role in const ['bob', 'charlie'])
            role: c.received(role, _target),
        };
        final target = sent?['messageId'];
        final group = sent?['groupId'];
        final reactor = c.peers['bob'];
        final arms = proof['reactionArmed'] as Map;
        final snapshots = proof['reactionFinal'] as Map;
        c.require(
          arms.length == 3 && snapshots.length == 3,
          'exact reaction roles required',
        );
        final outcomes = (snapshots['bob'] as Map)['outcomes'] as List;
        c.require(outcomes.length == 1, 'exact Bob send outcome required');
        final outcome = outcomes.isEmpty ? const {} : outcomes.single as Map;
        final reactionId = outcome['reactionId'];
        c.require(
          outcome['outcome'] == 'success' &&
              reactionId is String &&
              reactionId.isNotEmpty,
          'Bob reaction did not publish successfully',
        );
        final stream = <String, bool>{};
        final rowsOf = <String, List>{};
        for (final role in _roles) {
          final arm = arms[role] as Map;
          final snapshot = snapshots[role] as Map;
          for (final observation in [arm, snapshot]) {
            c.require(
              observation['runId'] == c.run &&
                  observation['role'] == role &&
                  observation['groupId'] == group &&
                  observation['messageId'] == target &&
                  observation['reactorPeerId'] == reactor,
              '$role: reaction identity mismatch',
            );
          }
          c.require(
            arm['armed'] == true && arm['initialReactionCount'] == 0,
            '$role: fresh reaction observation required',
          );
          if (role != 'bob') {
            c.require(
              (snapshot['outcomes'] as List).isEmpty,
              '$role: unexpected send outcome',
            );
          }
          final rows = rowsOf[role] = snapshot['reactions'] as List;
          final row = rows.length == 1 ? rows.single as Map : const {};
          c.require(
            rows.length == 1 &&
                row['id'] == reactionId &&
                row['message_id'] == target &&
                row['sender_peer_id'] == reactor &&
                row['emoji'] == '🔥' &&
                row['removed_at'] == null,
            '$role: persisted reaction mismatch',
          );
          stream[role] = (snapshot['changes'] as List).any((raw) {
            final change = raw as Map;
            return change['type'] == 'upserted' &&
                change['reactionId'] == reactionId &&
                change['messageId'] == target &&
                change['senderPeerId'] == reactor &&
                change['emoji'] == '🔥' &&
                change['timestamp'] == row['timestamp'];
          });
        }
        int mediaCount(String role) {
          final rows = productionCatalogRows(c.finalOf(role), _target);
          return rows.length == 1
              ? (rows.single['mediaAttachmentCount'] as int?) ?? 0
              : 0;
        }

        Map<String, Object?> l01(String role) => {
          'rowId': 'L-01',
          'scenario': 'private_media_reaction_roundtrip',
          'activeRoles': _roles,
          'targetMessageId': target,
          'targetIsMedia': mediaCount(role) >= 1,
          'targetMediaCount': mediaCount(role),
          'reactorRole': 'bob',
          'reactionEmoji': '🔥',
          'reactionOutcome': outcome['outcome'],
          'reactionAccepted': outcome['outcome'] == 'success',
          'observedByRole': role,
          'receivedViaGroupReactionStream': stream[role],
          'appliedOnceToTarget': rowsOf[role]!.length == 1,
          'persistedReactionCount': rowsOf[role]!.length,
          'aliceObservedSignal': stream['alice'],
          'charlieObservedSignal': stream['charlie'],
        };

        return [
          c.verdict(
            'alice',
            sent: [sent],
            extra: {'l01MediaReactionRoundtripProof': l01('alice')},
          ),
          for (final role in const ['bob', 'charlie'])
            c.verdict(
              role,
              received: [received[role]],
              extra: {'l01MediaReactionRoundtripProof': l01(role)},
            ),
        ];
      },
    );
