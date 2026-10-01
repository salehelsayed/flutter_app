import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

/// Texts of catalog `gm006`, identical to the original harness.
Map<String, String> productionGm006Texts(String run) => {
  'aliceDuringCharlieRemoval': 'GM-006 Alice during Charlie removal $run',
  'charlieAfterImmediateReadd': 'GM-006 Charlie after immediate re-add $run',
  'aliceAfterImmediateReadd': 'GM-006 Alice after immediate re-add $run',
};

const productionGm006Flows = [
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

const _receipts = [
  ('bobGotDuring', 'bob', 'aliceDuringCharlieRemoval'),
  ('aliceGotCharlie', 'alice', 'charlieAfterImmediateReadd'),
  ('bobGotCharlie', 'bob', 'charlieAfterImmediateReadd'),
  ('bobGotAfter', 'bob', 'aliceAfterImmediateReadd'),
  ('charlieGotAfter', 'charlie', 'aliceAfterImmediateReadd'),
];

List<String> validateProductionGroupGm006(Map<String, Object?> proof) {
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
      (proof['flows'] as List).join(',') == productionGm006Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm006' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    final removed = stage('aliceRemoved', 'alice');
    require(
      !(removed['memberPeerIds'] as List).contains(charlie),
      'Alice removed Charlie before the removed-window send',
    );
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
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    Map? own(String role, String key) {
      final rows = productionCatalogRows(finals[role]!, key);
      require(
        rows.length == 1 && rows.first['isIncoming'] == false,
        '$role: own outgoing $key row',
      );
      return rows.isEmpty ? null : rows.first;
    }

    final aliceDuring = own('alice', 'aliceDuringCharlieRemoval');
    final aliceAfter = own('alice', 'aliceAfterImmediateReadd');
    final charlieAfter = own('charlie', 'charlieAfterImmediateReadd');
    // Before plus after the re-add, as the original counts it.
    final removedWindowLeak =
        productionCatalogRows(
          stage('charlieRemovedWindow', 'charlie'),
          'aliceDuringCharlieRemoval',
        ).length +
        productionCatalogRows(
          finals['charlie']!,
          'aliceDuringCharlieRemoval',
        ).length;
    Set members(String role) =>
        ((finals[role]!['memberPeerIds'] as List?) ?? const []).toSet();
    int epoch(String role) => (finals[role]!['keyEpoch'] as int?) ?? 0;
    final charlieSent = charlieAfter == null
        ? <String, Object?>{}
        : productionCatalogSent(charlieAfter, 'charlieAfterImmediateReadd');

    Map<String, Object?> verdict(
      String role,
      List<Map<String, Object?>> sent,
      Map<String, Object?> gm006,
    ) => {
      ...productionCatalogBaseVerdict(
        scenario: 'gm006',
        role: role,
        run: run,
        snapshot: finals[role]!,
      ),
      'sentMessages': sent,
      'receivedMessages': received[role],
      'persistedMessageCounts': {
        for (final r in received[role]!) '${r['key']}': r['persistedCount'],
      },
      'gm006ImmediateReaddProof': {...gm006, 'finalEpoch': epoch(role)},
    };

    final verdicts = <Map<String, dynamic>>[
      verdict(
        'alice',
        [
          if (aliceDuring != null)
            productionCatalogSent(aliceDuring, 'aliceDuringCharlieRemoval'),
          if (aliceAfter != null)
            productionCatalogSent(aliceAfter, 'aliceAfterImmediateReadd'),
        ],
        {
          'removedCharlie': !(removed['memberPeerIds'] as List).contains(
            charlie,
          ),
          'readdedCharlie': members('alice').contains(charlie),
          'removedPeerId': charlie,
          'memberListIncludesCharlie': members('alice').contains(charlie),
          'sentRemovedWindowBeforeReadd': aliceDuring != null,
          'receivedCharliePostReaddMessage': received['alice']!.isNotEmpty,
        },
      ),
      verdict('bob', const [], {
        'memberListIncludesCharlie': members('bob').contains(charlie),
        'receivedRemovedWindowMessage': received['bob']!.any(
          (r) => r['key'] == 'aliceDuringCharlieRemoval',
        ),
        'receivedCharliePostReaddMessage': received['bob']!.any(
          (r) => r['key'] == 'charlieAfterImmediateReadd',
        ),
        'receivedAlicePostReaddMessage': received['bob']!.any(
          (r) => r['key'] == 'aliceAfterImmediateReadd',
        ),
      }),
      verdict('charlie', [if (charlieAfter != null) charlieSent], {
        'memberListIncludesAliceBob':
            members('charlie').contains(alice) &&
            members('charlie').contains(bob),
        'memberListIncludesCharlie': members('charlie').contains(charlie),
        'hasStaleEpochAfterReadd': epoch('charlie') < 2,
        'postReaddPublishAccepted': charlieSent['outcome'] == 'success',
        'receivedAlicePostReaddMessage': received['charlie']!.isNotEmpty,
        'removedWindowPlaintextCount': removedWindowLeak,
      }),
    ].map(Map<String, dynamic>.from).toList();
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm006',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed gm006 proof: ${error.runtimeType} $error');
  }
  return failures;
}
