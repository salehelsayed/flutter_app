import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

/// Texts of catalog `gm004`, identical to the original harness.
Map<String, String> productionGm004Texts(String run) => {
  'aliceAfterCharlieRemove': 'GM-004 Alice after Charlie removal $run',
  'bobAfterCharlieRemove': 'GM-004 Bob after Charlie removal $run',
};

const productionGm004Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-remove',
  'bob-after-remove',
];

List<String> validateProductionGroupGm004(Map<String, Object?> proof) {
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
      (proof['flows'] as List).join(',') == productionGm004Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm004' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    final before = stage('charlieBefore', 'charlie');
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final aliceRows = productionCatalogRows(
      stage('aliceSentAfter', 'alice'),
      'aliceAfterCharlieRemove',
    );
    final bobRows = productionCatalogRows(
      stage('bobGotAlice', 'bob'),
      'aliceAfterCharlieRemove',
    );
    final bobSentRows = productionCatalogRows(
      stage('bobSentAfter', 'bob'),
      'bobAfterCharlieRemove',
    );
    final aliceGotRows = productionCatalogRows(
      stage('aliceGotBob', 'alice'),
      'bobAfterCharlieRemove',
    );
    final leak = stage('charlieLeak', 'charlie');
    final aliceLeak = productionCatalogRows(
      leak,
      'aliceAfterCharlieRemove',
    ).length;
    final bobLeak = productionCatalogRows(leak, 'bobAfterCharlieRemove').length;
    final rejected = proof['charlieRejected'] as Map;
    require(
      aliceRows.length == 1 &&
          bobRows.length == 1 &&
          bobSentRows.length == 1 &&
          aliceGotRows.length == 1,
      'exact single sent and received rows',
    );
    final rotated = finals['alice']!['keyEpoch'] as int;
    bool excludes(Map s) => !(s['memberPeerIds'] as List).contains(charlie);
    final charlieEpoch = (finals['charlie']!['keyEpoch'] as int?) ?? 0;

    Map<String, Object?> verdict(
      String role,
      List<Map<String, Object?>> sent,
      List<Map<String, Object?>> received,
      Map<String, Object?> removal,
    ) => {
      ...productionCatalogBaseVerdict(
        scenario: 'gm004',
        role: role,
        run: run,
        snapshot: finals[role]!,
      ),
      if (role == 'charlie') 'groupId': finals['alice']!['groupId'],
      if (role == 'charlie') 'keyEpoch': charlieEpoch,
      'sentMessages': sent,
      'receivedMessages': received,
      'persistedMessageCounts': {
        for (final r in received) '${r['key']}': r['persistedCount'],
      },
      'gm004RemovalProof': removal,
    };

    final verdicts = <Map<String, dynamic>>[
      verdict(
        'alice',
        [
          if (aliceRows.isNotEmpty)
            productionCatalogSent(aliceRows.first, 'aliceAfterCharlieRemove'),
        ],
        [
          if (aliceGotRows.isNotEmpty)
            productionCatalogReceived(
              aliceGotRows.first,
              'bobAfterCharlieRemove',
              aliceGotRows.length,
            ),
        ],
        {
          'charlieOnlineBeforeRemoval': before['relayReady'] == true,
          'removedCharlie': excludes(finals['alice']!),
          'removedPeerId': charlie,
          'memberListExcludesCharlie': excludes(finals['alice']!),
          'rotatedEpoch': rotated,
        },
      ),
      verdict(
        'bob',
        [
          if (bobSentRows.isNotEmpty)
            productionCatalogSent(bobSentRows.first, 'bobAfterCharlieRemove'),
        ],
        [
          if (bobRows.isNotEmpty)
            productionCatalogReceived(
              bobRows.first,
              'aliceAfterCharlieRemove',
              bobRows.length,
            ),
        ],
        {
          'memberListExcludesCharlie': excludes(finals['bob']!),
          'hasRotatedEpoch': finals['bob']!['keyEpoch'] == rotated,
          'rotatedEpoch': rotated,
        },
      ),
      verdict('charlie', [Map<String, Object?>.from(rejected)], const [], {
        'onlineBeforeRemoval': before['relayReady'] == true,
        'currentMemberBeforeRemoval': before['selfMember'] == true,
        'groupPresentAfterRemoval': finals['charlie']!['groupPresent'] == true,
        'selfMemberPresentAfterRemoval':
            finals['charlie']!['selfMember'] == true,
        'hasRotatedEpoch': charlieEpoch >= rotated,
        'rotatedEpoch': charlieEpoch,
        'postRemovalSendOutcome': rejected['outcome'],
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'receivedAliceAfterRemoval': aliceLeak > 0,
        'receivedBobAfterRemoval': bobLeak > 0,
        'postRemovalPlaintextCount': aliceLeak + bobLeak,
      }),
    ].map(Map<String, dynamic>.from).toList();
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm004',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed gm004 proof: ${error.runtimeType} $error');
  }
  return failures;
}
