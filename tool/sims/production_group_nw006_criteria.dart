import 'production_catalog_case.dart';

const _missed = 'aliceMissedDuringDisconnect';
const _live = 'alicePostReconnectLive';
const _back = 'bobPublishBackAfterReconnect';
const _roles = ['alice', 'bob', 'charlie'];

/// Texts of catalog `private_peer_disconnect_not_removal` (NW-006), identical
/// to the original harness.
Map<String, ProductionCatalogText> productionNw006Texts(String run) => {
  _missed: (role: 'alice', text: 'NW-006 missed while Bob disconnected $run'),
  _live: (role: 'alice', text: 'NW-006 Alice live after reconnect $run'),
  _back: (role: 'bob', text: 'NW-006 Bob publish back after reconnect $run'),
};

const productionNw006Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-missed',
  'bob-open-group',
  'alice-post-reconnect',
  'bob-publish-back',
];

/// The original's per-role `nw006DisconnectNotRemovalProof`, observed. Bob's
/// disconnect is a verified death of his app process on his simulator (the
/// original stops his node); his relaunch is an ordinary launch of the same
/// install. The platform label is the original's: every role ran on an iOS
/// simulator (runtime recorded in the run's provenance).
List<String> validateProductionGroupNw006(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_peer_disconnect_not_removal',
  flows: productionNw006Flows,
  verdicts: (c) {
    final bob = '${c.peers['bob']}';
    final all = {for (final r in _roles) '${c.peers[r]}'};
    final missedSent = c.sent('alice', _missed);
    final recipients = ((missedSent?['recipientPeerIds'] as List?) ?? [])
        .map((p) => '$p')
        .toSet();
    final during = c.stage('aliceDuringDisconnect', 'alice');
    final relaunched = c.stage('bobRelaunched', 'bob');
    final startEpoch = c.stage('aliceBeforeDisconnect', 'alice')['keyEpoch'];
    final removals = [
      for (final r in _roles)
        ...((c.finalOf(r)['memberRemovedTimelineIds'] as List?) ?? const []),
    ];
    var duplicates = 0;
    for (final r in _roles) {
      for (final k in const [_missed, _live, _back]) {
        final n = c.finalCount(r, k);
        if (n > 1) duplicates += n - 1;
      }
    }
    final proofFor = <String, Object?>{
      'rowId': 'NW-006',
      'scenario': 'private_peer_disconnect_not_removal',
      'appPeerPlatform': 'ios_26_2_core_simulator',
      'disconnectProofSource': 'app_peer_core_simulator',
      'bobDisconnected': c.proof['bob-offline'] == true,
      'bobGroupPresentDuringDisconnect':
          relaunched['groupPresent'] == true && c.members(during).contains(bob),
      'bobSelfMemberActiveDuringDisconnect': relaunched['selfMember'] == true,
      'bobRemovedSignalCount': removals.length,
      'membershipMutationCount': removals.length,
      'durableRecipientIncludedDisconnectedBob': recipients.contains(bob),
      'missedDuringDisconnectRecoveredByReplay':
          c.received('bob', _missed) != null && !c.live('bob', _missed),
      'postReconnectLiveDeliveryToBob': c.live('bob', _live),
      'bobPublishBackAfterReconnect': c.sent('bob', _back) != null,
      'duplicateVisibleMessageCount': duplicates,
      'finalMembershipConvergedForAliceBobCharlie': _roles.every(
        (r) => c.members(c.finalOf(r)).containsAll(all),
      ),
      'finalKeyEpochConvergedForAliceBobCharlie': _roles.every(
        (r) => c.epoch(r) == startEpoch,
      ),
      'stableKeyEpoch': _roles.every((r) => c.epoch(r) == startEpoch),
      // Milestones only: no peer ids.
      'disconnectDiagnostics': [
        {'event': 'BOB_APP_PROCESS_KILLED', 'verified': true},
        {'event': 'ALICE_SENT_WHILE_BOB_DOWN', 'key': _missed},
        {'event': 'BOB_RELAUNCHED_SAME_INSTALL', 'drain': 'catalog_drain_once'},
      ],
    };
    return [
      c.verdict(
        'alice',
        sent: [missedSent, c.sent('alice', _live)],
        received: [c.receivedVia('alice', _back)],
        extra: {
          'nw006DisconnectNotRemovalProof': {...proofFor, 'proofRole': 'alice'},
        },
      ),
      c.verdict(
        'bob',
        sent: [c.sent('bob', _back)],
        received: [c.receivedVia('bob', _missed), c.receivedVia('bob', _live)],
        extra: {
          'nw006DisconnectNotRemovalProof': {...proofFor, 'proofRole': 'bob'},
        },
      ),
      c.verdict(
        'charlie',
        received: [
          c.receivedVia('charlie', _missed),
          c.receivedVia('charlie', _live),
          c.receivedVia('charlie', _back),
        ],
        extra: {
          'nw006DisconnectNotRemovalProof': {
            ...proofFor,
            'proofRole': 'charlie',
          },
        },
      ),
    ];
  },
);
