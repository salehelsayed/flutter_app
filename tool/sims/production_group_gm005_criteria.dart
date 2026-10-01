import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

/// Texts of catalog `gm005`, identical to the original harness.
Map<String, String> productionGm005Texts(String run) => {
  for (var i = 1; i <= 3; i++)
    'aliceAfterCharlieOfflineRemove$i':
        'GM-005 Alice after offline Charlie removal $i $run',
};

const productionGm005Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-remove-1',
  'alice-after-remove-2',
  'alice-after-remove-3',
];

List<String> validateProductionGroupGm005(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    final charlie = peers['charlie'];
    require(
      {peers['alice'], peers['bob'], charlie}.length == 3,
      'three distinct peers',
    );
    require(
      (proof['flows'] as List).join(',') == productionGm005Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm005' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    final stale = stage('charlieStale', 'charlie');
    require(
      stale['selfMember'] == true && stale['keyEpoch'] == 1,
      'Charlie holds the old configuration and key before going offline',
    );
    require(proof['charlieOffline'] == true, 'verified Charlie process death');
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final rotated = finals['alice']!['keyEpoch'] as int;
    bool excludes(Map s) => !(s['memberPeerIds'] as List).contains(charlie);
    final keys = productionGm005Texts(run).keys.toList();
    final aliceSent = <Map<String, Object?>>[];
    final bobReceived = <Map<String, Object?>>[];
    for (final (i, key) in keys.indexed) {
      final sentRows = productionCatalogRows(
        stage('aliceSent${i + 1}', 'alice'),
        key,
      );
      final gotRows = productionCatalogRows(stage('bobGot${i + 1}', 'bob'), key);
      require(
        sentRows.length == 1 && gotRows.length == 1,
        '$key: exact single sent and received rows',
      );
      if (sentRows.isNotEmpty) {
        aliceSent.add(productionCatalogSent(sentRows.first, key));
      }
      if (gotRows.isNotEmpty) {
        bobReceived.add(
          productionCatalogReceived(gotRows.first, key, gotRows.length),
        );
      }
    }
    final drain = Map<String, Object?>.from(proof['charlieDrain'] as Map);
    final leaks = [
      for (final key in keys)
        productionCatalogRows(finals['charlie']!, key).length,
    ];
    final charlieEpoch = (finals['charlie']!['keyEpoch'] as int?) ?? 0;
    final rejected = Map<String, Object?>.from(proof['charlieRejected'] as Map);
    final selfPresent = finals['charlie']!['selfMember'] == true;

    final verdicts = <Map<String, dynamic>>[
      {
        ...productionCatalogBaseVerdict(
          scenario: 'gm005',
          role: 'alice',
          run: run,
          snapshot: finals['alice']!,
        ),
        'sentMessages': aliceSent,
        'receivedMessages': const [],
        'persistedMessageCounts': const {},
        'gm005OfflineRemovalProof': {
          'charlieOfflineBeforeRemoval': proof['charlieOffline'] == true,
          'removedCharlie': excludes(finals['alice']!),
          'removedPeerId': charlie,
          'memberListExcludesCharlie': excludes(finals['alice']!),
          'rotatedEpoch': rotated,
          'postRemovalMessageCount': aliceSent.length,
        },
      },
      {
        ...productionCatalogBaseVerdict(
          scenario: 'gm005',
          role: 'bob',
          run: run,
          snapshot: finals['bob']!,
        ),
        'sentMessages': const [],
        'receivedMessages': bobReceived,
        'persistedMessageCounts': {
          for (final r in bobReceived) '${r['key']}': r['persistedCount'],
        },
        'gm005OfflineRemovalProof': {
          'memberListExcludesCharlie': excludes(finals['bob']!),
          'hasRotatedEpoch': finals['bob']!['keyEpoch'] == rotated,
          'rotatedEpoch': rotated,
          'receivedAllAlicePostRemovalMessages': bobReceived.length == 3,
        },
      },
      {
        ...productionCatalogBaseVerdict(
          scenario: 'gm005',
          role: 'charlie',
          run: run,
          snapshot: finals['charlie']!,
        ),
        'groupId': finals['alice']!['groupId'],
        'keyEpoch': charlieEpoch,
        'sentMessages': [rejected],
        'receivedMessages': const [],
        'persistedMessageCounts': const {},
        'gm005OfflineRemovalProof': {
          'hadOldConfigBeforeOffline': stale['selfMember'] == true,
          'hadOldKeyBeforeOffline': stale['keyEpoch'] == 1,
          'offlineDuringRemoval': proof['charlieOffline'] == true,
          'reconnectedWithStaleState': stale['keyEpoch'] == 1,
          'restoredStaleStateFromFixture': false,
          'staleKeyEpochBeforeDrain': stale['keyEpoch'],
          'retrievedInboxAfterReconnect':
              ((drain['completedDrainCount'] as int?) ?? 0) > 0,
          ...drain,
          'convergedRemoved': !selfPresent,
          'groupPresentAfterCatchUp': finals['charlie']!['groupPresent'] == true,
          'selfMemberPresentAfterCatchUp': selfPresent,
          'hasRotatedEpoch': charlieEpoch >= 2,
          'rotatedEpoch': charlieEpoch,
          'postRemovalPlaintextCount': leaks.fold<int>(0, (a, b) => a + b),
          'postRemovalSendOutcome': rejected['outcome'],
          'postRemovalPublishAccepted': rejected['accepted'] == true,
        },
      },
    ].map(Map<String, dynamic>.from).toList();
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm005',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed gm005 proof: ${error.runtimeType} $error');
  }
  return failures;
}
