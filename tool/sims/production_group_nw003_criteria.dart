import 'production_catalog_case.dart';

const _baseline = 'aliceNw003Baseline';
const _removed = 'aliceRemovedWindow';
const _alicePost = 'alicePostHeal';
const _bobPost = 'bobPostHeal';
const _charliePost = 'charliePostHeal';
const _roles = ['alice', 'bob', 'charlie'];

/// Texts of catalog `private_partition_readd_heal` (NW-003), identical to
/// the original harness.
Map<String, ProductionCatalogText> productionNw003Texts(String run) => {
  _baseline: (role: 'alice', text: 'NW-003 baseline before partition $run'),
  _removed: (role: 'alice', text: 'NW-003 removed-window $run'),
  _alicePost: (role: 'alice', text: 'NW-003 Alice post-heal $run'),
  _bobPost: (role: 'bob', text: 'NW-003 Bob post-heal $run'),
  _charliePost: (role: 'charlie', text: 'NW-003 Charlie post-heal $run'),
};

const productionNw003Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-baseline',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-removed-window',
  'readd-charlie',
  'bob-open-group',
  'charlie-home',
  'accept-charlie-readd',
  'alice-post-heal',
  'bob-post-heal',
  'charlie-post-heal',
];

/// The original's per-role `nw003PartitionReaddHealProof`, observed. The
/// partition is a verified death of Bob's and Charlie's app processes (the
/// original stops their nodes); healing is an ordinary relaunch of the same
/// installs. The platform label is the original's: every role ran on an iOS
/// simulator.
List<String> validateProductionGroupNw003(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_partition_readd_heal',
  flows: productionNw003Flows,
  verdicts: (c) {
    final all = {for (final r in _roles) '${c.peers[r]}'};
    final bobDown = c.proof['bob-offline'] == true;
    final charlieDown = c.proof['charlie-offline'] == true;
    final removedSent = c.sent('alice', _removed);
    // Sent while both were dead: no topic peer, custody in the inbox.
    final blocked = bobDown && charlieDown && !c.live('bob', _removed);
    final charlieClean = c.finalCount('charlie', _removed) == 0;
    final epochs = {for (final r in _roles) c.epoch(r)};
    final post = {
      'alice': [
        c.received('bob', _alicePost),
        c.received('charlie', _alicePost),
      ],
      'bob': [c.received('alice', _bobPost), c.received('charlie', _bobPost)],
      'charlie': [
        c.received('alice', _charliePost),
        c.received('bob', _charliePost),
      ],
    };
    bool delivered(String role) => post[role]!.every((r) => r != null);
    final shared = <String, Object?>{
      'rowId': 'NW-003',
      'scenario': 'private_partition_readd_heal',
      'appPeerPlatform': 'ios_26_2_core_simulator',
      'partitionProofSource': 'app_peer_core_simulator',
      'fakeNetworkOnly': false,
      'alicePartitionedFromBob': bobDown,
      'alicePartitionedFromCharlie': charlieDown,
      'bobAndCharliePartitionedFromAlice': bobDown && charlieDown,
      'removedWindowSentWhileCharlieRemoved':
          removedSent != null &&
          !c
              .members(c.stage('aliceRemoved', 'alice'))
              .contains('${c.peers['charlie']}'),
      'removedWindowLiveDeliveryBlockedDuringPartition': blocked,
      'bobReceivedRemovedWindowAfterHeal': c.received('bob', _removed) != null,
      'charlieDidNotReceiveRemovedWindow': charlieClean,
      'finalMembershipConvergedForAliceBobCharlie': _roles.every(
        (r) => c.members(c.finalOf(r)).containsAll(all),
      ),
      'finalKeyEpochConvergedForAliceBobCharlie':
          epochs.length == 1 && epochs.single >= 2,
      'postHealAliceToBobCharlieDelivery': delivered('alice'),
      'postHealBobToAliceCharlieDelivery': delivered('bob'),
      'postHealCharlieToAliceBobDelivery': delivered('charlie'),
      // Milestones only: no peer ids.
      'routeDiagnostics': [
        {
          'sourceEvent': 'APP_PEER_PROCESS_DEATH_PARTITION',
          'roles': 'bob,charlie',
        },
        {'sourceEvent': 'REMOVED_WINDOW_SENT_TO_INBOX', 'key': _removed},
        {'sourceEvent': 'APP_PEER_RELAUNCH_HEAL', 'roles': 'bob,charlie'},
      ],
    };
    return [
      c.verdict(
        'alice',
        sent: [removedSent, c.sent('alice', _alicePost)],
        received: [
          c.received('alice', _bobPost),
          c.received('alice', _charliePost),
        ],
        extra: {
          'nw003PartitionReaddHealProof': {...shared, 'proofRole': 'alice'},
        },
      ),
      c.verdict(
        'bob',
        sent: [c.sent('bob', _bobPost)],
        received: [
          c.received('bob', _removed),
          c.received('bob', _alicePost),
          c.received('bob', _charliePost),
        ],
        extra: {
          'nw003PartitionReaddHealProof': {...shared, 'proofRole': 'bob'},
        },
      ),
      c.verdict(
        'charlie',
        sent: [c.sent('charlie', _charliePost)],
        received: [
          c.received('charlie', _alicePost),
          c.received('charlie', _bobPost),
        ],
        extra: {
          'nw003PartitionReaddHealProof': {...shared, 'proofRole': 'charlie'},
        },
      ),
    ];
  },
);
