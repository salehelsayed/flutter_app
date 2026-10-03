import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _during = 'aliceDuringCharlieRestartedRemoval';
const _charlie = 'charlieAfterRestartReadd';
const _after = 'aliceAfterRestartReadd';
const _rejected = 'charlieDuringRestartedRemoval';

/// Texts of catalog `gm008`, identical to the original harness.
Map<String, ProductionCatalogText> productionGm008Texts(String run) => {
  _during: (
    role: 'alice',
    text: 'GM-008 Alice during restarted Charlie removal $run',
  ),
  _charlie: (role: 'charlie', text: 'GM-008 Charlie after restart re-add $run'),
  _after: (role: 'alice', text: 'GM-008 Alice after restart re-add $run'),
  _rejected: (
    role: 'charlie',
    text: 'GM-008 Charlie should not send while restarted removed $run',
  ),
};

const productionGm008Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-during-removal',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'charlie-after-readd',
  'alice-after-readd',
];

/// GM-008. Charlie applies his removal, restarts (verified process death and
/// an ordinary relaunch keeping his own state), his one publish attempt is
/// rejected by the production send use case, then Alice re-adds him through
/// the UI. Unlike the original, the restart keeps Charlie's database.
List<String> validateProductionGroupGm008(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'gm008',
      flows: productionGm008Flows,
      verdicts: (c) {
        final alice = '${c.peers['alice']}';
        final bob = '${c.peers['bob']}';
        final charlie = '${c.peers['charlie']}';
        bool has(String role, String id) =>
            c.members(c.finalOf(role)).contains(id);
        final epochs = {
          for (final r in const ['alice', 'bob', 'charlie']) r: c.epoch(r),
        };
        final removedApplied =
            c.stage('charlieRemoved', 'charlie')['selfMember'] == false;
        final restarted = proof['charlieRestarted'] == true;
        final afterRestart = c.stage('charlieAfterRestart', 'charlie');
        final rejected = proof['charlieRejected'] as Map;
        c.require(
          rejected['key'] == _rejected &&
              rejected['text'] == productionGm008Texts(c.run)[_rejected]!.text,
          'Charlie attempted the original removed-window text',
        );
        final readdEpoch =
            c.stage('aliceReadded', 'alice')['keyEpoch'] as int? ?? 0;
        final window = c.stage('charlieRemovedWindow', 'charlie');
        final leak =
            productionCatalogRows(window, _during).length +
            c.finalCount('charlie', _during);
        final aDuring = c.sent('alice', _during);
        final aAfter = c.sent('alice', _after);
        final cSent = c.sent('charlie', _charlie);
        final aGotC = c.received('alice', _charlie);
        final bGot = [
          for (final k in const [_during, _charlie, _after])
            c.received('bob', k),
        ];
        final cGotA = c.received('charlie', _after);
        final bobExcludedBeforeRestart = !c
            .members(c.stage('bobExcluded', 'bob'))
            .contains(charlie);
        return [
          c.verdict(
            'alice',
            sent: [aDuring, aAfter],
            received: [aGotC],
            extra: {
              'gm008RestartReaddProof': {
                'removedCharlie': !c
                    .members(c.stage('aliceRemoved', 'alice'))
                    .contains(charlie),
                'charlieRestartedBeforeReadd': restarted,
                'distributedCurrentEpochToRemainingOnly':
                    (aDuring?['keyEpoch'] as int? ?? 0) >= 2 &&
                    (window['keyEpoch'] as int? ?? 0) == 0,
                'sentRemovedWindowAfterRestartBeforeReadd':
                    aDuring?['accepted'] == true,
                'readdedCharlie': has('alice', charlie),
                'receivedCharliePostReaddMessage': aGotC != null,
                'removedPeerId': charlie,
                'memberListIncludesCharlie': has('alice', charlie),
                'finalEpoch': epochs['alice'],
              },
            },
          ),
          c.verdict(
            'bob',
            received: bGot,
            extra: {
              'gm008RestartReaddProof': {
                'observedCharlieRestartBoundary': bobExcludedBeforeRestart,
                'receivedRemovedWindowMessage': bGot[0] != null,
                'receivedCharliePostReaddMessage': bGot[1] != null,
                'receivedAlicePostReaddMessage': bGot[2] != null,
                'memberListIncludesCharlie': has('bob', charlie),
                'finalEpoch': epochs['bob'],
              },
            },
          ),
          c.verdict(
            'charlie',
            sent: [cSent],
            received: [cGotA],
            extra: {
              'gm008RestartReaddProof': {
                'runtimeRestartedAfterRemoval': removedApplied && restarted,
                'preReaddGroupPresentAfterRestart':
                    afterRestart['groupPresent'] == true,
                'preReaddKeyEpochAfterRestart': afterRestart['keyEpoch'],
                'preReaddSendRejected': rejected['accepted'] != true,
                'rejoinedFromCurrentPersistedEpoch':
                    epochs['charlie']! >= readdEpoch,
                'memberListIncludesAliceBob':
                    has('charlie', alice) && has('charlie', bob),
                'memberListIncludesCharlie': has('charlie', charlie),
                'removedWindowPlaintextCount': leak,
                'hasStaleEpochAfterRestartReadd':
                    epochs['charlie']! < readdEpoch,
                'postReaddPublishAccepted': cSent?['accepted'] == true,
                'receivedAlicePostReaddMessage': cGotA != null,
                'finalEpoch': epochs['charlie'],
              },
            },
          ),
        ];
      },
    );
