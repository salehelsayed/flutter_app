import 'production_catalog_case.dart';
import 'production_catalog_verdicts.dart';

/// Texts of the four-person add cases, identical to the original harness
/// (gm002 and ML-002 share one role script, as do gm003 and ML-003).
Map<String, ProductionCatalogText> productionGm002Texts(String run) => {
  'aliceAfterDanaAdd': (
    role: 'alice',
    text: 'GM-002 alice after Dana add $run',
  ),
  'danaAfterJoin': (role: 'dana', text: 'GM-002 Dana after join $run'),
};

Map<String, ProductionCatalogText> productionMl002Texts(String run) => {
  ...productionGm002Texts(run),
  'bobAfterDanaAdd': (role: 'bob', text: 'ML-002 Bob after Dana add $run'),
};

Map<String, ProductionCatalogText> productionGm003Texts(String run) => {
  'aliceBeforeDanaAdd': (
    role: 'alice',
    text: 'GM-003 alice before Dana add $run',
  ),
  'aliceAfterDanaOfflineAdd': (
    role: 'alice',
    text: 'GM-003 alice after offline Dana add $run',
  ),
  'danaAfterOfflineJoin': (
    role: 'dana',
    text: 'GM-003 Dana after offline join $run',
  ),
};

Map<String, ProductionCatalogText> productionMl003Texts(String run) => {
  'aliceBeforeDanaAdd': (
    role: 'alice',
    text: 'ML-003 alice pre-add control $run',
  ),
  'aliceAfterDanaOfflineAdd': (
    role: 'alice',
    text: 'ML-003 alice after offline Dana add $run',
  ),
  'bobAfterDanaOfflineAdd': (
    role: 'bob',
    text: 'ML-003 Bob after offline Dana add $run',
  ),
  'aliceLiveAfterDanaDrain': (
    role: 'alice',
    text: 'ML-003 alice live after Dana drain $run',
  ),
};

const productionGm002Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'add-dana',
  'accept-dana',
  'alice-after-add',
  'dana-after-join',
];

const productionMl002Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'add-dana',
  'accept-dana',
  'alice-after-add',
  'bob-after-add',
  'dana-after-join',
];

const productionGm003Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-add',
  'add-dana',
  'alice-after-add',
  'accept-dana',
  'dana-after-join',
];

const productionMl003Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-add',
  'add-dana',
  'alice-after-add',
  'bob-after-add',
  'accept-dana',
  'alice-live-after-drain',
];

const _all = ['alice', 'bob', 'charlie', 'dana'];

/// Runner milestones in the order they happened (`proof['order']`).
List<String> _order(ProductionCatalogCase c) =>
    ((c.proof['order'] as List?) ?? const []).cast<String>();

bool _before(ProductionCatalogCase c, String a, String b) {
  final order = _order(c);
  return order.contains(a) &&
      order.contains(b) &&
      order.indexOf(a) < order.indexOf(b);
}

bool _danaEverywhere(ProductionCatalogCase c) =>
    _all.every((r) => c.members(c.finalOf(r)).contains('${c.peers['dana']}'));

/// Dana held no group before accepting: no membership and no group row.
bool _danaNotMemberBefore(ProductionCatalogCase c) {
  final s = c.stage('danaBeforeAccept', 'dana');
  return s['selfMember'] != true &&
      !c.members(s).contains('${c.peers['dana']}');
}

bool _danaAccepted(ProductionCatalogCase c) {
  final f = c.finalOf('dana');
  return (c.proof['flows'] as List).contains('accept-dana') &&
      f['selfMember'] == true &&
      ((f['keyEpoch'] as int?) ?? 0) >= 1;
}

bool _pendingOnce(ProductionCatalogCase c) =>
    (((c.proof['danaPending'] as Map?)?['pending'] as List?) ?? const [])
        .length ==
    1;

List<String> validateProductionGroupGm002(Map<String, Object?> proof) =>
    validateProductionCatalogCase(
      proof: proof,
      scenario: 'gm002',
      flows: productionGm002Flows,
      verdicts: (c) => [
        c.verdict(
          'alice',
          sent: [c.sent('alice', 'aliceAfterDanaAdd')],
          received: [c.received('alice', 'danaAfterJoin')],
        ),
        for (final role in const ['bob', 'charlie'])
          c.verdict(
            role,
            received: [
              c.received(role, 'aliceAfterDanaAdd'),
              c.received(role, 'danaAfterJoin'),
            ],
          ),
        c.verdict(
          'dana',
          sent: [c.sent('dana', 'danaAfterJoin')],
          received: [c.received('dana', 'aliceAfterDanaAdd')],
        ),
      ],
    );

List<String> validateProductionGroupMl002(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_online_add',
  flows: productionMl002Flows,
  verdicts: (c) {
    final dana = '${c.peers['dana']}';
    final online = c.stage('danaBeforeAccept', 'dana')['relayReady'] == true;
    final notActive =
        _danaNotMemberBefore(c) &&
        !c.members(c.stage('aliceBeforeAdd', 'alice')).contains(dana);
    final added = c.members(c.stage('aliceAddedDana', 'alice')).contains(dana);
    final everywhere = _danaEverywhere(c);
    final aliceSent = c.sent('alice', 'aliceAfterDanaAdd');
    final bobSent = c.sent('bob', 'bobAfterDanaAdd');
    final acceptedEpoch = c.stage('danaAccepted', 'dana')['keyEpoch'];
    bool liveAtDana(String key) => c.live('dana', key);
    bool epochInstalled(String key) {
      final rows = productionCatalogRows(c.finalOf('dana'), key);
      return rows.length == 1 &&
          acceptedEpoch is int &&
          rows.single['keyEpoch'] == acceptedEpoch;
    }

    Map<String, Object?> proofFor(String role) => {
      'rowId': 'ML-002',
      if (role == 'alice') ...{
        'danaOnlineBeforeAdd': online,
        'danaNotActiveBeforeAdd': notActive,
        'aliceAddedDana': added,
        'danaJoinedAfterAdd': _danaAccepted(c),
        'allRolesSeeDanaActiveAfterJoin': everywhere,
        'aliceSentPostJoin': aliceSent != null,
        'bobSentPostJoin': bobSent != null,
      },
      if (role == 'bob') ...{
        'danaActiveAfterJoin': c.members(c.finalOf('bob')).contains(dana),
        'bobSentPostJoin': bobSent != null,
      },
      if (role == 'charlie')
        'danaActiveAfterJoin': c.members(c.finalOf('charlie')).contains(dana),
      if (role == 'dana') ...{
        'danaOnlineBeforeAdd': online,
        'danaNotActiveBeforeAdd': notActive,
        'joinedViaGroupJoinWithConfig': _danaAccepted(c),
        'currentKeyEpochInstalledBeforeLiveReceive':
            epochInstalled('aliceAfterDanaAdd') &&
            epochInstalled('bobAfterDanaAdd'),
        'receivedAlicePostJoinLiveNoDrain': liveAtDana('aliceAfterDanaAdd'),
        'receivedBobPostJoinLiveNoDrain': liveAtDana('bobAfterDanaAdd'),
        'noOfflineDrainBeforeLiveReceipts':
            liveAtDana('aliceAfterDanaAdd') && liveAtDana('bobAfterDanaAdd'),
      },
    };

    return [
      c.verdict(
        'alice',
        sent: [aliceSent],
        received: [
          c.received('alice', 'bobAfterDanaAdd'),
          c.received('alice', 'danaAfterJoin'),
        ],
        extra: {'ml002OnlineAddProof': proofFor('alice')},
      ),
      c.verdict(
        'bob',
        sent: [bobSent],
        received: [
          c.received('bob', 'aliceAfterDanaAdd'),
          c.received('bob', 'danaAfterJoin'),
        ],
        extra: {'ml002OnlineAddProof': proofFor('bob')},
      ),
      c.verdict(
        'charlie',
        received: [
          c.received('charlie', 'aliceAfterDanaAdd'),
          c.received('charlie', 'bobAfterDanaAdd'),
          c.received('charlie', 'danaAfterJoin'),
        ],
        extra: {'ml002OnlineAddProof': proofFor('charlie')},
      ),
      c.verdict(
        'dana',
        sent: [c.sent('dana', 'danaAfterJoin')],
        received: [
          c.receivedVia('dana', 'aliceAfterDanaAdd'),
          c.receivedVia('dana', 'bobAfterDanaAdd'),
        ],
        extra: {'ml002OnlineAddProof': proofFor('dana')},
      ),
    ];
  },
);

List<String> validateProductionGroupGm003(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'gm003',
  flows: productionGm003Flows,
  verdicts: (c) {
    final offline =
        c.proof['dana-offline'] == true &&
        _before(c, 'dana-offline', 'add-dana');
    final launchedAfter = _before(c, 'alice-after-add', 'dana-online');
    final caughtUp = c.received('dana', 'aliceAfterDanaOfflineAdd') != null;
    return [
      c.verdict(
        'alice',
        sent: [
          c.sent('alice', 'aliceBeforeDanaAdd'),
          c.sent('alice', 'aliceAfterDanaOfflineAdd'),
        ],
        received: [c.received('alice', 'danaAfterOfflineJoin')],
        extra: {
          'gm003OfflineAddProof': {
            'danaOfflineDuringAdd': offline,
            'postAddSentBeforeDanaLaunch': launchedAfter,
            'danaLaunchedAfterPostAddSend': launchedAfter,
          },
        },
      ),
      for (final role in const ['bob', 'charlie'])
        c.verdict(
          role,
          received: [
            c.received(role, 'aliceBeforeDanaAdd'),
            c.received(role, 'aliceAfterDanaOfflineAdd'),
            c.received(role, 'danaAfterOfflineJoin'),
          ],
        ),
      c.verdict(
        'dana',
        sent: [c.sent('dana', 'danaAfterOfflineJoin')],
        received: [c.received('dana', 'aliceAfterDanaOfflineAdd')],
        extra: {
          'gm003OfflineCatchUpProof': {
            'startedAfterPostAddSend': launchedAfter,
            'installedGroupConfigBeforeCatchUp':
                _danaAccepted(c) && _before(c, 'accept-dana', 'dana-caught-up'),
            'drainedOfflineInbox': !c.live('dana', 'aliceAfterDanaOfflineAdd'),
            'preAddMessageAbsent':
                c.finalCount('dana', 'aliceBeforeDanaAdd') == 0,
            'postAddMessageCaughtUp': caughtUp,
          },
        },
      ),
    ];
  },
);

List<String> validateProductionGroupMl003(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_offline_add',
  flows: productionMl003Flows,
  verdicts: (c) {
    final dana = '${c.peers['dana']}';
    final offline =
        c.proof['dana-offline'] == true &&
        _before(c, 'dana-offline', 'add-dana') &&
        _before(c, 'add-dana', 'dana-online');
    final pendingAccepted =
        _pendingOnce(c) && _danaNotMemberBefore(c) && _danaAccepted(c);
    final replayKeys = ['aliceAfterDanaOfflineAdd', 'bobAfterDanaOfflineAdd'];
    bool replayed(String key) =>
        c.received('dana', key) != null && !c.live('dana', key);
    final liveAfter =
        c.live('dana', 'aliceLiveAfterDanaDrain') &&
        _before(c, 'accept-dana', 'alice-live-after-drain') &&
        !_before(c, 'accept-dana', 'dana-relaunch-after-accept');
    return [
      c.verdict(
        'alice',
        sent: [
          c.sent('alice', 'aliceAfterDanaOfflineAdd'),
          c.sent('alice', 'aliceLiveAfterDanaDrain'),
        ],
        received: [c.received('alice', 'bobAfterDanaOfflineAdd')],
        extra: {
          'ml003OfflineAddProof': {
            'rowId': 'ML-003',
            'invitePath': pendingAccepted
                ? 'supported_pending_invite'
                : 'unobserved',
            'danaOfflineDuringAdd': offline,
            'danaNotSubscribedDuringAdd': offline,
            'danaNotActiveBeforeAccept': _danaNotMemberBefore(c),
            'aliceAddedDana': c
                .members(c.stage('aliceAddedDana', 'alice'))
                .contains(dana),
            'aliceSentPostAddBeforeDanaAccept': _before(
              c,
              'alice-after-add',
              'accept-dana',
            ),
            'bobSentPostAddBeforeDanaAccept': _before(
              c,
              'bob-after-add',
              'accept-dana',
            ),
            'liveSentAfterDanaDrain': liveAfter,
          },
        },
      ),
      c.verdict(
        'bob',
        sent: [c.sent('bob', 'bobAfterDanaOfflineAdd')],
        received: [c.received('bob', 'aliceAfterDanaOfflineAdd')],
        extra: {
          'ml003OfflineAddProof': {
            'rowId': 'ML-003',
            'danaActiveInConfigBeforeBobSend': c
                .members(c.stage('bobBeforeSend', 'bob'))
                .contains(dana),
            'bobSentPostAddBeforeDanaAccept': _before(
              c,
              'bob-after-add',
              'accept-dana',
            ),
          },
        },
      ),
      c.verdict(
        'charlie',
        received: [
          c.received('charlie', 'aliceAfterDanaOfflineAdd'),
          c.received('charlie', 'bobAfterDanaOfflineAdd'),
        ],
      ),
      c.verdict(
        'dana',
        received: [
          for (final key in replayKeys) c.receivedVia('dana', key),
          c.receivedVia('dana', 'aliceLiveAfterDanaDrain'),
        ],
        extra: {
          'ml003OfflineAddProof': {
            'rowId': 'ML-003',
            'invitePath': pendingAccepted
                ? 'supported_pending_invite'
                : 'unobserved',
            'startedAfterPostAddSends': _before(
              c,
              'bob-after-add',
              'dana-online',
            ),
            'storedPendingInvite': _pendingOnce(c),
            'acceptedPendingInvite': pendingAccepted,
            'joinedViaGroupJoinWithConfig': _danaAccepted(c),
            'drainedOfflineInbox': replayKeys.every(replayed),
            'preAddMessageAbsent':
                c.finalCount('dana', 'aliceBeforeDanaAdd') == 0,
            'receivedAlicePostAddReplay': replayed('aliceAfterDanaOfflineAdd'),
            'receivedBobPostAddReplay': replayed('bobAfterDanaOfflineAdd'),
            'replayPersistedExactlyOnce': replayKeys.every(
              (k) => c.finalCount('dana', k) == 1,
            ),
            'liveAfterDrainWithoutRestart': liveAfter,
          },
        },
      ),
    ];
  },
);
