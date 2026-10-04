import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'production_catalog_case.dart';

const _alice = 'aliceAfterCharlieRemove';
const _bob = 'bobAfterCharlieRemove';

/// Texts of catalog `private_removed_notification_privacy` (UP-012), which
/// runs the original GM-004 role scripts.
Map<String, ProductionCatalogText> productionUp012Texts(String run) => {
  _alice: (role: 'alice', text: 'GM-004 Alice after Charlie removal $run'),
  _bob: (role: 'bob', text: 'GM-004 Bob after Charlie removal $run'),
};

const productionUp012Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-home',
  'bob-after-remove',
  'alice-open-group',
  'bob-home',
  'alice-after-remove',
];

/// Visible (not silent) notification requests of [role]'s app process, as
/// the production notification observer recorded them. Like the original's
/// counts, these cover the process lifetime (no baseline).
List<Map> _shown(ProductionCatalogCase c, String role) => [
  for (final n in (c.finalOf(role)['notifications'] as List?) ?? const [])
    if ((n as Map)['silent'] != true) n,
];

/// The original's per-role `up012NotificationPrivacyProof`, observed from
/// read-only snapshots and the production notification observer. A preview
/// leak is a notification whose body hash equals a post-removal text hash.
List<String> validateProductionGroupUp012(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_removed_notification_privacy',
  flows: productionUp012Flows,
  verdicts: (c) {
    final charlie = '${c.peers['charlie']}';
    final texts = productionUp012Texts(c.run);
    final textHashes = {
      for (final t in texts.values)
        sha256.convert(utf8.encode(t.text)).toString(),
    };
    final removedByAlice = !c
        .members(c.stage('aliceRemoved', 'alice'))
        .contains(charlie);
    Map<String, Object?> pair(String role, String other, String key) {
      final shown = _shown(c, role);
      final received = c.received(role, key) != null;
      return {
        'rowId': 'UP-012',
        'removedCharlie': removedByAlice,
        'memberListExcludesCharlie': !c
            .members(c.finalOf(role))
            .contains(charlie),
        'received${other}AfterRemoval': received,
        'legitimatePostRemovalNotificationShown': received && shown.isNotEmpty,
        'removedPeerId': charlie,
        'postRemovalNotificationCount': shown.length,
      };
    }

    final before = c.stage('charlieBefore', 'charlie');
    final charlieFinal = c.finalOf('charlie');
    final charlieShown = _shown(c, 'charlie');
    final charlieProof = {
      'rowId': 'UP-012',
      'onlineBeforeRemoval': before['relayReady'] == true,
      'currentMemberBeforeRemoval': before['selfMember'] == true,
      'groupPresentAfterRemoval': charlieFinal['groupPresent'] == true,
      'selfMemberPresentAfterRemoval': charlieFinal['selfMember'] == true,
      'receivedAliceAfterRemoval': c.finalCount('charlie', _alice) > 0,
      'receivedBobAfterRemoval': c.finalCount('charlie', _bob) > 0,
      'noLocalNotificationsAfterRemoval': charlieShown.isEmpty,
      'noPostRemovalNotificationPreviews': !charlieShown.any(
        (n) => textHashes.contains(n['bodySha256']),
      ),
      'postRemovalNotificationCount': charlieShown.length,
      'postRemovalPlaintextCount':
          c.finalCount('charlie', _alice) + c.finalCount('charlie', _bob),
    };
    final bobSent = c.sent('bob', _bob);
    return [
      c.verdict(
        'alice',
        sent: [c.sent('alice', _alice)],
        received: [c.received('alice', _bob)],
        extra: {'up012NotificationPrivacyProof': pair('alice', 'Bob', _bob)},
      ),
      c.verdict(
        'bob',
        sent: [bobSent],
        received: [c.received('bob', _alice)],
        extra: {
          'up012NotificationPrivacyProof': {
            ...pair('bob', 'Alice', _alice),
            'sentPostRemovalAccepted': bobSent?['outcome'] == 'success',
          },
        },
      ),
      c.verdict(
        'charlie',
        extra: {'up012NotificationPrivacyProof': charlieProof},
      ),
    ];
  },
);
