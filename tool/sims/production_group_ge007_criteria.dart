import 'production_catalog_case.dart';

const _window = 'aliceGe007RemovedWindow';
const _alicePost = 'aliceGe007PostReadd';
const _charliePost = 'charlieGe007PostReadd';
const _bobCatchUp = 'bobGe007PostCatchUp';

/// Texts of catalog `ge007`, identical to the original harness.
Map<String, ProductionCatalogText> productionGe007Texts(String run) => {
  _window: (role: 'alice', text: 'GE-007 removed window $run'),
  _alicePost: (role: 'alice', text: 'GE-007 Alice post re-add $run'),
  _charliePost: (role: 'charlie', text: 'GE-007 Charlie post re-add $run'),
  _bobCatchUp: (role: 'bob', text: 'GE-007 Bob post catch-up $run'),
};

const productionGe007Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-removed-window',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-post-readd',
  'charlie-post-readd',
  'bob-open-group',
  'bob-catch-up',
];

/// GE-007. Bob is offline (verified process death) while Alice removes and
/// re-adds Charlie and the post-re-add messages flow; Bob relaunches with
/// his own persisted state, runs one explicit production catch-up drain
/// (mirroring the original), receives what he is entitled to and sends.
List<String> validateProductionGroupGe007(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'ge007',
      flows: productionGe007Flows,
      verdicts: (c) {
        final alice = '${c.peers['alice']}';
        final bob = '${c.peers['bob']}';
        final charlie = '${c.peers['charlie']}';
        bool has(String role, String id) =>
            c.members(c.finalOf(role)).contains(id);
        final epochs = {
          for (final r in const ['alice', 'bob', 'charlie']) r: c.epoch(r),
        };
        final offline = proof['bobOffline'] == true;
        final drain = proof['bobDrain'] as Map?;
        final aWindow = c.sent('alice', _window);
        final aPost = c.sent('alice', _alicePost);
        final cPost = c.sent('charlie', _charliePost);
        final bCatch = c.sent('bob', _bobCatchUp);
        final aGotC = c.received('alice', _charliePost);
        final aGotB = c.received('alice', _bobCatchUp);
        final bGot = [
          for (final k in const [_window, _alicePost, _charliePost])
            c.received('bob', k),
        ];
        final cGotA = c.received('charlie', _alicePost);
        final cGotB = c.received('charlie', _bobCatchUp);
        List rc(Map? m) => (m?['recipientPeerIds'] as List?) ?? const [];
        return [
          c.verdict(
            'alice',
            sent: [aWindow, aPost],
            received: [aGotC, aGotB],
            extra: {
              'ge007OfflineObserverProof': {
                'removedCharlie':
                    c.stage('charlieRemoved', 'charlie')['selfMember'] == false,
                'readdedCharlie': has('alice', charlie),
                'bobOfflineDuringMutation': offline,
                'removedWindowDurableIncludesBob': rc(aWindow).contains(bob),
                'postReaddDurableIncludesBob': rc(aPost).contains(bob),
                'receivedCharliePostReaddMessage': aGotC != null,
                'receivedBobPostCatchUpMessage': aGotB != null,
                'offlinePeerId': bob,
                'finalEpoch': epochs['alice'],
              },
            },
          ),
          c.verdict(
            'bob',
            sent: [bCatch],
            received: bGot,
            extra: {
              'ge007OfflineObserverProof': {
                'offlineDuringMutation': offline,
                'retrievedInboxAfterReconnect':
                    (drain?['completedDrainCount'] as int? ?? 0) > 0,
                'memberListIncludesAliceCharlie':
                    has('bob', alice) && has('bob', charlie),
                'memberListIncludesBob': has('bob', bob),
                'receivedRemovedWindowMessage': bGot[0] != null,
                'receivedAlicePostReaddMessage': bGot[1] != null,
                'receivedCharliePostReaddMessage': bGot[2] != null,
                'postCatchUpPublishAccepted': bCatch?['accepted'] == true,
                'entitledReceivedCount': bGot.whereType<Map>().length,
                'entitledReceivedKeys': [
                  for (final g in bGot)
                    if (g != null) g['key'],
                ],
                'finalEpoch': epochs['bob'],
              },
            },
          ),
          c.verdict(
            'charlie',
            sent: [cPost],
            received: [cGotA, cGotB],
            extra: {
              'ge007OfflineObserverProof': {
                'selfRemovedDuringMutation':
                    c.stage('charlieRemoved', 'charlie')['selfMember'] == false,
                'readdedCharlie': has('charlie', charlie),
                'memberListIncludesBob': has('charlie', bob),
                'receivedAlicePostReaddMessage': cGotA != null,
                'receivedBobPostCatchUpMessage': cGotB != null,
                'finalEpoch': epochs['charlie'],
              },
            },
          ),
        ];
      },
    );
