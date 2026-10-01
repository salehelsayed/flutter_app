import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _during = 'aliceDuringRapidRemove';
const _aliceAfter = 'alicePostRapidReadd';
const _bobAfter = 'bobPostRapidReadd';

/// Texts of catalog `private_rapid_readd` (ML-009), identical to the
/// original harness.
Map<String, ProductionCatalogText> productionRapidReaddTexts(String run) => {
  _during: (role: 'alice', text: 'ML-009 Alice during rapid remove $run'),
  _aliceAfter: (role: 'alice', text: 'ML-009 Alice after rapid re-add $run'),
  _bobAfter: (role: 'bob', text: 'ML-009 Bob after rapid re-add $run'),
};

const productionRapidReaddFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-during-rapid-remove',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-after-readd',
  'bob-after-readd',
];

/// ML-009. Alice removes Charlie, sends and re-adds him through the UI
/// without waiting for Bob or Charlie to apply the removal; the runner
/// records that order (`readdWithoutWaitingForRemovalAcks`).
List<String> validateProductionGroupRapidReadd(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'private_rapid_readd',
      flows: productionRapidReaddFlows,
      verdicts: (c) {
        final alice = '${c.peers['alice']}';
        final bob = '${c.peers['bob']}';
        final charlie = '${c.peers['charlie']}';
        bool has(String role, String id) => c.members(c.finalOf(role)).contains(id);
        final epochs = {for (final r in const ['alice', 'bob', 'charlie']) r: c.epoch(r)};
        final aDuring = c.sent('alice', _during);
        final aAfter = c.sent('alice', _aliceAfter);
        final bAfter = c.sent('bob', _bobAfter);
        final aGotB = c.received('alice', _bobAfter);
        final bGotDuring = c.received('bob', _during);
        final bGotA = c.received('bob', _aliceAfter);
        final cGotA = c.received('charlie', _aliceAfter);
        final cGotB = c.received('charlie', _bobAfter);
        final leak =
            productionCatalogRows(
              c.stage('charlieRemovedWindow', 'charlie'),
              _during,
            ).length +
            c.finalCount('charlie', _during);
        Map<String, Object?> p(String role, Map<String, Object?> fields) => {
          'ml009RapidReaddProof': {
            'rowId': 'ML-009',
            ...fields,
            'finalEpoch': epochs[role],
          },
        };
        return [
          c.verdict(
            'alice',
            sent: [aDuring, aAfter],
            received: [aGotB],
            extra: p('alice', {
              'removedCharlie': !c
                  .members(c.stage('aliceRemoved', 'alice'))
                  .contains(charlie),
              'readdedCharlie': has('alice', charlie),
              'readdIssuedBeforeRemovalAcks':
                  proof['readdWithoutWaitingForRemovalAcks'] == true,
              'sentRemovedWindowBeforeReadd': aDuring?['accepted'] == true,
              'sentAlicePostReaddMessage': aAfter?['accepted'] == true,
              'receivedBobPostReaddMessage': aGotB != null,
              'removedPeerId': charlie,
              'memberListIncludesCharlie': has('alice', charlie),
            }),
          ),
          c.verdict(
            'bob',
            sent: [bAfter],
            received: [bGotDuring, bGotA],
            extra: p('bob', {
              'memberListIncludesCharlie': has('bob', charlie),
              'receivedRemovedWindowMessage': bGotDuring != null,
              'receivedAlicePostReaddMessage': bGotA != null,
              'sentBobPostReaddMessage': bAfter?['accepted'] == true,
              'staleRemoveIgnored': has('bob', charlie),
            }),
          ),
          c.verdict(
            'charlie',
            received: [cGotA, cGotB],
            extra: p('charlie', {
              'memberListIncludesAliceBob':
                  has('charlie', alice) && has('charlie', bob),
              'memberListIncludesCharlie': has('charlie', charlie),
              'receivedAlicePostReaddMessage': cGotA != null,
              'receivedBobPostReaddMessage': cGotB != null,
              'removedWindowPlaintextCount': leak,
              'staleRemoveIgnored': has('charlie', charlie),
              'hasStaleEpochAfterReadd': epochs['charlie']! < 2,
            }),
          ),
        ];
      },
    );
