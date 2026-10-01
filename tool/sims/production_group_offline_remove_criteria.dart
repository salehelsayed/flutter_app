import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

/// Texts of catalog `private_offline_remove` (ML-006/IR-004), identical to the
/// original harness.
Map<String, String> productionOfflineRemoveTexts(String run) => {
  'aliceAfterCharlieOfflineRemove':
      'ML-006 Alice after offline Charlie removal $run',
  'bobAfterCharlieOfflineRemove':
      'ML-006 Bob after offline Charlie removal $run',
};

const productionOfflineRemoveFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-remove',
  'bob-after-remove',
];

List<String> validateProductionGroupOfflineRemove(Map<String, Object?> proof) {
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
      (proof['flows'] as List).join(',') ==
          productionOfflineRemoveFlows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'private_offline_remove' &&
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
    final offline = proof['charlieOffline'] == true;
    require(offline, 'verified Charlie process death');
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final rotated = finals['alice']!['keyEpoch'] as int;
    bool excludes(Map s) => !(s['memberPeerIds'] as List).contains(charlie);
    Map? one(String name, String role, String key) {
      final rows = productionCatalogRows(stage(name, role), key);
      require(rows.length == 1, '$name: exactly one $key row');
      return rows.isEmpty ? null : rows.first;
    }

    final aliceSentRow = one(
      'aliceSentAfter',
      'alice',
      'aliceAfterCharlieOfflineRemove',
    );
    final bobGotRow = one('bobGotAlice', 'bob', 'aliceAfterCharlieOfflineRemove');
    final bobSentRow = one('bobSentAfter', 'bob', 'bobAfterCharlieOfflineRemove');
    final aliceGotRow = one(
      'aliceGotBob',
      'alice',
      'bobAfterCharlieOfflineRemove',
    );
    final aliceSent = productionCatalogSent(
      aliceSentRow ?? const {},
      'aliceAfterCharlieOfflineRemove',
    );
    final bobSent = productionCatalogSent(
      bobSentRow ?? const {},
      'bobAfterCharlieOfflineRemove',
    );
    final drain = Map<String, Object?>.from(proof['charlieDrain'] as Map);
    final aliceLeak = productionCatalogRows(
      finals['charlie']!,
      'aliceAfterCharlieOfflineRemove',
    ).length;
    final bobLeak = productionCatalogRows(
      finals['charlie']!,
      'bobAfterCharlieOfflineRemove',
    ).length;
    final charlieEpoch = (finals['charlie']!['keyEpoch'] as int?) ?? 0;
    final rejected = Map<String, Object?>.from(proof['charlieRejected'] as Map);
    final selfPresent = finals['charlie']!['selfMember'] == true;
    final retrieved = ((drain['completedDrainCount'] as int?) ?? 0) > 0;
    final catchUp = <String, Object?>{
      'hadOldConfigBeforeOffline': stale['selfMember'] == true,
      'hadOldKeyBeforeOffline': stale['keyEpoch'] == 1,
      'offlineDuringRemoval': offline,
      'reconnectedWithStaleState': stale['keyEpoch'] == 1,
      'restoredStaleStateFromFixture': false,
      'staleKeyEpochBeforeDrain': stale['keyEpoch'],
      'retrievedInboxAfterReconnect': retrieved,
      ...drain,
      'convergedRemoved': !selfPresent,
      'groupPresentAfterCatchUp': finals['charlie']!['groupPresent'] == true,
      'selfMemberPresentAfterCatchUp': selfPresent,
      'postRemovalPlaintextCount': aliceLeak + bobLeak,
      'postRemovalSendOutcome': rejected['outcome'],
      'postRemovalPublishAccepted': rejected['accepted'] == true,
    };

    final verdicts = <Map<String, dynamic>>[
      {
        ...productionCatalogBaseVerdict(
          scenario: 'private_offline_remove',
          role: 'alice',
          run: run,
          snapshot: finals['alice']!,
        ),
        'sentMessages': [aliceSent],
        'receivedMessages': [
          if (aliceGotRow != null)
            productionCatalogReceived(
              aliceGotRow,
              'bobAfterCharlieOfflineRemove',
              1,
            ),
        ],
        'persistedMessageCounts': {'bobAfterCharlieOfflineRemove': 1},
        'ml006OfflineRemovalProof': {
          'rowId': 'ML-006',
          'charlieOfflineBeforeRemoval': offline,
          'removedCharlie': excludes(finals['alice']!),
          'removedPeerId': charlie,
          'memberListExcludesCharlie': excludes(finals['alice']!),
          'sentPostRemovalAccepted': aliceSent['outcome'] == 'success',
          'receivedBobAfterRemoval': aliceGotRow != null,
          'rotatedEpoch': rotated,
        },
        'ir004PostRemovalReplayProof': {
          'rowId': 'IR-004',
          'charlieOfflineBeforeRemoval': offline,
          'removedCharlie': excludes(finals['alice']!),
          'removedPeerId': charlie,
          'memberListExcludesCharlie': excludes(finals['alice']!),
          'sentAlicePostRemoval': aliceSent['outcome'] == 'success',
          'receivedBobPostRemoval': aliceGotRow != null,
          'rotatedEpoch': rotated,
        },
      },
      {
        ...productionCatalogBaseVerdict(
          scenario: 'private_offline_remove',
          role: 'bob',
          run: run,
          snapshot: finals['bob']!,
        ),
        'sentMessages': [bobSent],
        'receivedMessages': [
          if (bobGotRow != null)
            productionCatalogReceived(
              bobGotRow,
              'aliceAfterCharlieOfflineRemove',
              1,
            ),
        ],
        'persistedMessageCounts': {'aliceAfterCharlieOfflineRemove': 1},
        'ml006OfflineRemovalProof': {
          'rowId': 'ML-006',
          'memberListExcludesCharlie': excludes(finals['bob']!),
          'hasRotatedEpoch': finals['bob']!['keyEpoch'] == rotated,
          'rotatedEpoch': rotated,
          'receivedAliceAfterRemoval': bobGotRow != null,
          'sentPostRemovalAccepted': bobSent['outcome'] == 'success',
        },
        'ir004PostRemovalReplayProof': {
          'rowId': 'IR-004',
          'memberListExcludesCharlie': excludes(finals['bob']!),
          'hasRotatedEpoch': finals['bob']!['keyEpoch'] == rotated,
          'rotatedEpoch': rotated,
          'receivedAlicePostRemoval': bobGotRow != null,
          'sentBobPostRemoval': bobSent['outcome'] == 'success',
        },
      },
      {
        ...productionCatalogBaseVerdict(
          scenario: 'private_offline_remove',
          role: 'charlie',
          run: run,
          snapshot: finals['charlie']!,
        ),
        'groupId': finals['alice']!['groupId'],
        'keyEpoch': charlieEpoch,
        'sentMessages': [rejected],
        'receivedMessages': const [],
        'persistedMessageCounts': const {},
        'ml006OfflineRemovalProof': {
          'rowId': 'ML-006',
          ...catchUp,
          'hasRotatedEpoch': charlieEpoch >= 2,
          'rotatedEpoch': charlieEpoch,
          'receivedAliceAfterRemoval': aliceLeak > 0,
          'receivedBobAfterRemoval': bobLeak > 0,
        },
        'ir004PostRemovalReplayProof': {
          'rowId': 'IR-004',
          ...catchUp,
          'retainedRotatedEpoch': charlieEpoch >= 2,
          'rotatedEpochAfterDrain': charlieEpoch,
          'receivedAlicePostRemoval': aliceLeak > 0,
          'receivedBobPostRemoval': bobLeak > 0,
        },
      },
    ].map(Map<String, dynamic>.from).toList();
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_offline_remove',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed offline-remove proof: ${error.runtimeType} $error');
  }
  return failures;
}
