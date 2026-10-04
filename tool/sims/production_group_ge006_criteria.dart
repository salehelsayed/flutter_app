import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _removed = 'aliceGe006RemovedWindow';
const _alicePost = 'aliceGe006PostReadd';
const _bobPost = 'bobGe006PostReadd';
const _charliePost = 'charlieGe006PostCatchUp';
const _proof = 'ge006OfflineReaddProof';

/// Texts of catalog `ge006`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe006Texts(String run) => {
  _removed: (role: 'alice', text: 'GE-006 removed window $run'),
  _alicePost: (role: 'alice', text: 'GE-006 Alice post re-add $run'),
  _bobPost: (role: 'bob', text: 'GE-006 Bob post re-add $run'),
  _charliePost: (role: 'charlie', text: 'GE-006 Charlie post catch-up $run'),
};

const productionGe006Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-removed-window',
  'readd-charlie',
  'alice-post-readd',
  'bob-post-readd',
  'charlie-home',
  'accept-charlie-readd',
  'charlie-post-catch-up',
];

/// GE-006. Charlie goes offline by verified process death; Alice removes
/// him, rotates, sends a removed-window message only Bob receives, re-adds
/// him while he is still offline, and Alice and Bob each send; Charlie
/// relaunches with his own state, accepts the re-add, recovers both
/// post-re-add messages from the offline inbox (never the removed-window
/// one), then sends to both.
List<String> validateProductionGroupGe006(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge006',
      flows: productionGe006Flows,
      verdicts: (c) {
        final charlie = c.peers['charlie'];
        final offline = proof['charlieOffline'] == true;
        final removed = c.sent('alice', _removed);
        final alicePost = c.sent('alice', _alicePost);
        final bobPost = c.sent('bob', _bobPost);
        final charliePost = c.sent('charlie', _charliePost);
        final bobRemoved = c.received('bob', _removed);
        final bobAlice = c.received('bob', _alicePost);
        final bobCharlie = c.received('bob', _charliePost);
        final aliceBob = c.received('alice', _bobPost);
        final aliceCharlie = c.received('alice', _charliePost);
        final charlieAlice = c.received('charlie', _alicePost);
        final charlieBob = c.received('charlie', _bobPost);
        final aliceRemoved = c.stage('aliceRemoved', 'alice');
        final aliceReadded = c.stage('aliceReadded', 'alice');
        final charlieFinal = c.finalOf('charlie');
        final caughtUp = [charlieAlice, charlieBob].whereType<Map>().toList();
        final epochs = {
          for (final r in ['alice', 'bob', 'charlie']) r: c.epoch(r),
        };
        return [
          c.verdict(
            'alice',
            sent: [removed, alicePost],
            received: [aliceBob, aliceCharlie],
            extra: {
              _proof: {
                'removedPeerId': charlie,
                'removedCharlie': !c.members(aliceRemoved).contains(charlie),
                'readdedCharlie': c.members(aliceReadded).contains(charlie),
                // Charlie's process was verifiably dead from before the
                // removal until his relaunch after both post-re-add sends.
                'charlieOfflineDuringMutation': offline,
                'removedWindowExcludedCharlie':
                    removed?['actualDurablePayloadProof'] == true &&
                    !(removed!['recipientPeerIds'] as List).contains(charlie),
                'postReaddDurableIncludesCharlie': (alicePost?['recipientPeerIds']
                        as List? ?? const [])
                    .contains(charlie),
                'receivedBobPostReaddMessage': aliceBob != null,
                'receivedCharliePostCatchUpMessage': aliceCharlie != null,
                'finalEpoch': epochs['alice'],
              },
            },
          ),
          c.verdict(
            'bob',
            sent: [bobPost],
            received: [bobRemoved, bobAlice, bobCharlie],
            extra: {
              _proof: {
                'memberListIncludesCharlie': c
                    .members(c.finalOf('bob'))
                    .contains(charlie),
                'receivedRemovedWindowMessage': bobRemoved != null,
                'receivedAlicePostReaddMessage': bobAlice != null,
                'receivedCharliePostCatchUpMessage': bobCharlie != null,
                'finalEpoch': epochs['bob'],
              },
            },
          ),
          c.verdict(
            'charlie',
            sent: [charliePost],
            received: [charlieAlice, charlieBob],
            extra: {
              _proof: {
                'offlineDuringRemovalAndReadd': offline,
                'retrievedInboxAfterReconnect':
                    caughtUp.length == 2 &&
                    !c.live('charlie', _alicePost) &&
                    !c.live('charlie', _bobPost),
                'memberListIncludesAliceBob': c
                    .members(charlieFinal)
                    .containsAll([c.peers['alice'], c.peers['bob']]),
                'memberListIncludesCharlie': c
                    .members(charlieFinal)
                    .contains(charlie),
                'postCatchUpPublishAccepted': charliePost?['accepted'] == true,
                'removedWindowPlaintextCount': productionCatalogRows(
                  charlieFinal,
                  _removed,
                ).length,
                'postReaddReceivedCount': caughtUp.length,
                'postReaddReceivedKeys': [
                  for (final r in caughtUp) r['key'],
                ],
                'finalEpoch': epochs['charlie'],
              },
            },
          ),
        ];
      },
    );
