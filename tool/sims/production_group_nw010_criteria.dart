import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

const _before = 'aliceDuringBackgroundBeforeEdit';
const _after = 'aliceDuringBackgroundAfterEdit';
const _live = 'alicePostForegroundLive';
const _back = 'bobPostForegroundPublishBack';
const _roles = ['alice', 'bob', 'charlie'];

/// Texts of catalog `private_background_resume_group_delivery` (NW-010 and
/// OB-011), identical to the original harness.
Map<String, ProductionCatalogText> productionNw010Texts(String run) => {
  _before: (role: 'alice', text: 'NW-010 missed before membership edit $run'),
  _after: (role: 'alice', text: 'NW-010 missed after membership edit $run'),
  _live: (role: 'alice', text: 'NW-010 Alice live after foreground $run'),
  _back: (role: 'bob', text: 'NW-010 Bob publish after foreground $run'),
};

const productionNw010Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-edit',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-edit',
  'bob-open-group',
  'alice-post-foreground',
  'bob-publish-back',
];

List<String> _order(ProductionCatalogCase c) =>
    ((c.proof['order'] as List?) ?? const []).cast<String>();

bool _before2(ProductionCatalogCase c, String a, String b) {
  final o = _order(c);
  return o.contains(a) && o.contains(b) && o.indexOf(a) < o.indexOf(b);
}

/// The keys Bob's relaunched process applied, in order: the two posts (by
/// message id or text) and Charlie's removal (`memberRemovedCharlie`).
List<String> _bobApplyOrder(ProductionCatalogCase c) {
  final f = c.finalOf('bob');
  final ids = <String, String>{};
  for (final k in const [_before, _after]) {
    for (final row in productionCatalogRows(f, k)) {
      ids['${row['messageId']}'] = k;
      ids['${row['text']}'] = k;
    }
  }
  final keys = <String>[];
  for (final raw in (f['flowEvents'] as List?) ?? const []) {
    final event = raw as Map;
    final details = (event['details'] as Map?) ?? const {};
    final String? key = switch ('${event['event']}') {
      'GROUP_HANDLE_INCOMING_MSG_SUCCESS' =>
        details.values.map((v) => ids['$v']).whereType<String>().firstOrNull,
      'GROUP_MESSAGE_LISTENER_MEMBER_REMOVED' => 'memberRemovedCharlie',
      _ => null,
    };
    if (key != null && !keys.contains(key)) keys.add(key);
  }
  return keys;
}

/// The original's per-role NW-010 and OB-011 proofs, observed. Bob's
/// backgrounding is a verified death of his app process (the original stops
/// his node); foregrounding is an ordinary relaunch of the same install.
/// OB-011 lists a missed-delivery cause only when its observation holds. The
/// platform label is the original's: every role ran on an iOS simulator.
List<String> validateProductionGroupNw010(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_background_resume_group_delivery',
  flows: productionNw010Flows,
  verdicts: (c) {
    final charlie = '${c.peers['charlie']}';
    final pair = {'${c.peers['alice']}', '${c.peers['bob']}'};
    final drainOrder = _bobApplyOrder(c);
    const expectedOrder = [_before, 'memberRemovedCharlie', _after];
    final ordered =
        expectedOrder.every(drainOrder.contains) &&
        [
              for (final k in drainOrder)
                if (expectedOrder.contains(k)) k,
            ].join(',') ==
            expectedOrder.join(',');
    final bobDown = c.proof['bob-offline'] == true;
    final viaInbox = [
      _before,
      _after,
    ].every((k) => c.received('bob', k) != null && !c.live('bob', k));
    final removedFirst =
        !c.members(c.stage('aliceRemoved', 'alice')).contains(charlie) &&
        _before2(c, 'remove-charlie', 'alice-after-edit');
    final filtered = c.finalCount('charlie', _after) == 0;
    var duplicates = 0;
    for (final r in _roles) {
      for (final k in const [_before, _after, _live, _back]) {
        final n = c.finalCount(r, k);
        if (n > 1) duplicates += n - 1;
      }
    }
    final nw010 = <String, Object?>{
      'rowId': 'NW-010',
      'scenario': 'private_background_resume_group_delivery',
      'appPeerPlatform': 'ios_26_2_core_simulator',
      'backgroundProofSource': 'app_peer_core_simulator_lifecycle_pause_resume',
      'bobBackgroundedDuringAliceActivity': bobDown,
      'bobForegroundedAfterMembershipEdit': _before2(
        c,
        'remove-charlie',
        'bob-online',
      ),
      'bobReceivedNoLiveCopyWhileBackgrounded': viaInbox,
      'groupTopicsRejoinedAfterForeground': c.live('bob', _live),
      'groupReplayDrainCompleted': viaInbox,
      'recoveryAckSentAfterRejoinAndDrain':
          (c.proof['bobRecovered'] as Map?)?['groupRecoveryActive'] == false,
      'orderedDrainIncludesContentAndMembership': ordered,
      'orderedDrainKeys': drainOrder,
      'entitlementFilteringPreserved': filtered,
      'postForegroundLiveDeliveryToBob': c.live('bob', _live),
      'bobPublishBackAfterForeground': c.sent('bob', _back) != null,
      'duplicateVisibleMessageCount': duplicates,
      'finalMembershipConvergedForAliceBob': ['alice', 'bob'].every((r) {
        final m = c.members(c.finalOf(r));
        return m.length == 2 && m.containsAll(pair);
      }),
      'finalKeyEpochConvergedForAliceBob':
          c.epoch('alice') == c.epoch('bob') && c.epoch('bob') >= 1,
      'charlieRemovedBeforeSecondBackgroundMessage': removedFirst,
      // Milestones only: no peer ids.
      'lifecycleDiagnostics': [
        {'event': 'BOB_APP_PROCESS_KILLED', 'verified': bobDown},
        {'event': 'CHARLIE_REMOVED_WHILE_BOB_DOWN', 'applied': removedFirst},
        {
          'event': 'BOB_RELAUNCHED_SAME_INSTALL',
          'drainOrder': drainOrder.join(','),
        },
      ],
    };
    List<Map<String, Object?>> missed(String role) => [
      if (role == 'bob' &&
          c.received('bob', _before) != null &&
          !c.live('bob', _before))
        {
          'messageKey': _before,
          'recipientRole': 'bob',
          'cause': 'transport',
          'sourceEvent': 'APP_PEER_BACKGROUND_PAUSE',
          'resolution': 'offline_replay_drained',
        },
      if (role == 'bob' &&
          c.received('bob', _after) != null &&
          !c.live('bob', _after))
        {
          'messageKey': _after,
          'recipientRole': 'bob',
          'cause': 'replay',
          'sourceEvent': 'GROUP_REJOIN_AND_DRAIN',
          'resolution': 'offline_replay_drained',
        },
      if (role == 'charlie' && removedFirst)
        {
          'messageKey': _after,
          'recipientRole': 'charlie',
          'cause': 'membership',
          'sourceEvent': 'CHARLIE_SELF_REMOVAL_OBSERVED',
          'resolution': 'not_entitled_after_removal',
        },
      if (role == 'charlie' && filtered)
        {
          'messageKey': _after,
          'recipientRole': 'charlie',
          'cause': 'ui_filter',
          'sourceEvent': 'ENTITLEMENT_FILTER_PRESERVED',
          'resolution': 'filtered_removed_member_window',
        },
    ];
    Map<String, Object?> ob011(String role) {
      final diagnostics = missed(role);
      return {
        'rowId': 'OB-011',
        'scenario': 'private_background_resume_group_delivery',
        'appPeerPlatform': 'ios_26_2_core_simulator',
        'releaseTelemetryProofSource': 'app_peer_background_resume_verdict',
        'proofRole': role,
        'missedDiagnostics': diagnostics,
        'coveredCauseClasses': {
          for (final d in diagnostics) '${d['cause']}',
        }.toList()..sort(),
        'unknownCount': 0,
        'hostCanonicalCauseCoverageRequired': const [
          'dispatcher',
          'key',
          'membership',
          'replay',
          'transport',
          'ui_filter',
        ],
      };
    }

    Map<String, Object?> extra(String role) => {
      'nw010BackgroundResumeDeliveryProof': {...nw010, 'proofRole': role},
      'ob011ReleaseTelemetryProof': ob011(role),
    };
    return [
      c.verdict(
        'alice',
        sent: [
          c.sent('alice', _before),
          c.sent('alice', _after),
          c.sent('alice', _live),
        ],
        received: [c.receivedVia('alice', _back)],
        extra: extra('alice'),
      ),
      c.verdict(
        'bob',
        sent: [c.sent('bob', _back)],
        received: [
          c.receivedVia('bob', _before),
          c.receivedVia('bob', _after),
          c.receivedVia('bob', _live),
        ],
        extra: extra('bob'),
      ),
      c.verdict(
        'charlie',
        received: [c.receivedVia('charlie', _before)],
        extra: extra('charlie'),
      ),
    ];
  },
);
