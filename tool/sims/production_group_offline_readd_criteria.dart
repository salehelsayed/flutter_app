import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

/// Texts of catalog `private_offline_readd` (RA-003), identical to the
/// original harness.
Map<String, String> productionOfflineReaddTexts(String run) => {
  'aliceDuringCharlieRemoval': 'RA-003 Alice during Charlie removal $run',
  'charlieAfterImmediateReadd': 'RA-003 Charlie after offline re-add $run',
  'aliceAfterImmediateReadd': 'RA-003 Alice after offline re-add $run',
  'bobAfterOfflineReadd': 'RA-003 Bob after offline re-add $run',
};

const productionOfflineReaddFlows = [
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
  'bob-after-readd',
];

const _receipts = [
  ('bobGotDuring', 'bob', 'aliceDuringCharlieRemoval'),
  ('aliceGotCharlie', 'alice', 'charlieAfterImmediateReadd'),
  ('bobGotCharlie', 'bob', 'charlieAfterImmediateReadd'),
  ('bobGotAfter', 'bob', 'aliceAfterImmediateReadd'),
  ('charlieGotAfter', 'charlie', 'aliceAfterImmediateReadd'),
  ('aliceGotBob', 'alice', 'bobAfterOfflineReadd'),
  ('charlieGotBob', 'charlie', 'bobAfterOfflineReadd'),
];

List<String> validateProductionGroupOfflineReadd(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    final alice = peers['alice'], bob = peers['bob'], charlie = peers['charlie'];
    require({alice, bob, charlie}.length == 3, 'three distinct peers');
    require(
      (proof['flows'] as List).join(',') ==
          productionOfflineReaddFlows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'private_offline_readd' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();
    final stale = stage('charlieStale', 'charlie');
    final offline = proof['charlieOffline'] == true;
    require(offline, 'Charlie process death verified before the removal');
    require(
      stale['selfMember'] == true && stale['keyEpoch'] == 1,
      'Charlie held the old membership before going offline',
    );
    final removed = stage('aliceRemoved', 'alice');
    final bobExcluded = stage('bobExcluded', 'bob');
    final resolved = stage('charlieResolved', 'charlie');
    final received = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: <Map<String, Object?>>[],
    };
    for (final (name, role, key) in _receipts) {
      final rows = productionCatalogRows(stage(name, role), key);
      require(
        rows.length == 1 && rows.first['isIncoming'] == true,
        '$name: exactly one incoming $key row',
      );
      if (rows.isNotEmpty) {
        received[role]!.add(productionCatalogReceived(rows.first, key, 1));
      }
    }
    bool got(String role, String key) =>
        received[role]!.any((r) => r['key'] == key);
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    Map<String, Object?>? own(String role, String key) {
      final rows = productionCatalogRows(finals[role]!, key);
      require(
        rows.length == 1 && rows.first['isIncoming'] == false,
        '$role: own outgoing $key row',
      );
      return rows.isEmpty ? null : productionCatalogSent(rows.first, key);
    }

    final aliceDuring = own('alice', 'aliceDuringCharlieRemoval');
    final aliceAfter = own('alice', 'aliceAfterImmediateReadd');
    final charlieAfter = own('charlie', 'charlieAfterImmediateReadd');
    final bobAfter = own('bob', 'bobAfterOfflineReadd');
    final leak =
        productionCatalogRows(
          stage('charlieRemovedWindow', 'charlie'),
          'aliceDuringCharlieRemoval',
        ).length +
        productionCatalogRows(
          finals['charlie']!,
          'aliceDuringCharlieRemoval',
        ).length;
    int epoch(String role) => (finals[role]!['keyEpoch'] as int?) ?? 0;
    final removedWhileOffline = offline && !members(removed).contains(charlie);
    final resolvedBeforeReadd = resolved['selfMember'] == false;

    Map<String, dynamic> verdict(
      String role,
      List<Map<String, Object?>?> sent,
      Map<String, Object?> ra003,
    ) => Map<String, dynamic>.from({
      ...productionCatalogBaseVerdict(
        scenario: 'private_offline_readd',
        role: role,
        run: run,
        snapshot: finals[role]!,
      ),
      'sentMessages': sent.whereType<Map<String, Object?>>().toList(),
      'receivedMessages': received[role],
      'persistedMessageCounts': {
        for (final r in received[role]!) '${r['key']}': r['persistedCount'],
      },
      'ra003OfflineReaddProof': {
        'rowId': 'RA-003',
        ...ra003,
        'finalEpoch': epoch(role),
      },
    });

    final verdicts = [
      verdict('alice', [aliceDuring, aliceAfter], {
        'removedCharlieWhileOffline': removedWhileOffline,
        'sentRemovedWindowWhileCharlieOffline': aliceDuring?['accepted'] == true,
        'waitedForCharlieRemovalResolutionBeforeReadd': resolvedBeforeReadd,
        'readdedCharlieAfterReconnect': members(
          finals['alice']!,
        ).contains(charlie),
        'sentPostReaddAfterOfflineReconnect': aliceAfter?['accepted'] == true,
        'receivedCharliePostReaddAfterOfflineReconnect': got(
          'alice',
          'charlieAfterImmediateReadd',
        ),
        'receivedBobPostReaddAfterOfflineReconnect': got(
          'alice',
          'bobAfterOfflineReadd',
        ),
        'removedPeerId': charlie,
      }),
      verdict('bob', [bobAfter], {
        'observedCharlieRemovedWhileOffline':
            offline && !members(bobExcluded).contains(charlie),
        'receivedRemovedWindowWhileCharlieOffline': got(
          'bob',
          'aliceDuringCharlieRemoval',
        ),
        'observedCharlieReaddedAfterReconnect': members(
          finals['bob']!,
        ).contains(charlie),
        'receivedAlicePostReaddAfterOfflineReconnect': got(
          'bob',
          'aliceAfterImmediateReadd',
        ),
        'sentBobPostReaddAfterOfflineReconnect': bobAfter?['accepted'] == true,
        'receivedCharliePostReaddAfterOfflineReconnect': got(
          'bob',
          'charlieAfterImmediateReadd',
        ),
      }),
      verdict('charlie', [charlieAfter], {
        'offlineDuringRemoval': offline,
        'reconnectedBeforeReadd': proof['charlieReconnected'] == true,
        'resolvedRemovalBeforeReadd': resolvedBeforeReadd,
        'removedWindowPlaintextCount': leak,
        'rejoinedAfterOfflineRemoval': finals['charlie']!['selfMember'] == true,
        'receivedAlicePostReaddAfterOfflineReconnect': got(
          'charlie',
          'aliceAfterImmediateReadd',
        ),
        'receivedBobPostReaddAfterOfflineReconnect': got(
          'charlie',
          'bobAfterOfflineReadd',
        ),
        'postReaddPublishAccepted': charlieAfter?['accepted'] == true,
        'memberListIncludesAliceBob':
            members(finals['charlie']!).contains(alice) &&
            members(finals['charlie']!).contains(bob),
        'memberListIncludesCharlie': members(
          finals['charlie']!,
        ).contains(charlie),
      }),
    ];
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_readd',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add(
      'malformed private_offline_readd proof: ${error.runtimeType} $error',
    );
  }
  return failures;
}
