import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const productionMl017BeforeKey = 'aliceBeforeHistoryRemoval';
const productionMl017AliceAfterKey = 'alicePostHistoryRemoval';
const productionMl017BobAfterKey = 'bobPostHistoryRemoval';
const productionMl017CharlieKey = 'charliePostHistoryRemoval';

/// Texts of catalog `private_history_retention` (ML-017), identical to the
/// original harness.
Map<String, String> productionMl017Texts(String run) => {
  productionMl017BeforeKey: 'ML-017 Alice before Charlie removal $run',
  productionMl017AliceAfterKey: 'ML-017 Alice after Charlie removal $run',
  productionMl017BobAfterKey: 'ML-017 Bob after Charlie removal $run',
  productionMl017CharlieKey: 'ML-017 Charlie after removal $run',
};

const productionMl017Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-before-removal',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-after-removal',
  'bob-after-removal',
];

List<String> validateProductionGroupHistoryRetention(
  Map<String, Object?> proof,
) {
  const scenario = 'private_history_retention';
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
      (proof['flows'] as List).join(',') == productionMl017Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == scenario &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    Map<String, Object?>? own(String role, String key) {
      final rows = productionCatalogRows(finals[role]!, key);
      require(
        rows.length == 1 && rows.single['isIncoming'] == false,
        '$role: own outgoing $key row',
      );
      return rows.isEmpty ? null : productionCatalogSent(rows.single, key);
    }

    Map<String, Object?>? got(String role, String key) {
      final rows = productionCatalogRows(stage('got:$key:$role', role), key);
      require(
        rows.length == 1 && rows.single['isIncoming'] == true,
        '$role: exactly one incoming $key row',
      );
      return rows.isEmpty
          ? null
          : productionCatalogReceived(
              rows.single,
              key,
              productionCatalogRows(finals[role]!, key).length,
            );
    }

    final aliceBefore = own('alice', productionMl017BeforeKey);
    final aliceAfter = own('alice', productionMl017AliceAfterKey);
    final bobAfter = own('bob', productionMl017BobAfterKey);
    final bobGotBefore = got('bob', productionMl017BeforeKey);
    final charlieGotBefore = got('charlie', productionMl017BeforeKey);
    final bobGotAfter = got('bob', productionMl017AliceAfterKey);
    final aliceGotBob = got('alice', productionMl017BobAfterKey);
    final removed = stage('aliceRemoved', 'alice');
    final rejected = proof['charlieRejected'] as Map;
    require(
      rejected['key'] == productionMl017CharlieKey &&
          rejected['text'] == productionMl017Texts(run)[productionMl017CharlieKey],
      'Charlie attempted the original post-removal text',
    );
    final aliceEpoch = finals['alice']!['keyEpoch'] as int? ?? 0;
    require(
      aliceEpoch >= 2 && finals['bob']!['keyEpoch'] == aliceEpoch,
      'Alice rotated the key and Bob holds the rotated epoch',
    );
    if (failures.isNotEmpty) return failures;
    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();
    final rotated = finals['alice']!['keyEpoch'] as int;
    final charlieFinal = finals['charlie']!;
    final aliceLeak = productionCatalogRows(
      charlieFinal,
      productionMl017AliceAfterKey,
    ).length;
    final bobLeak = productionCatalogRows(
      charlieFinal,
      productionMl017BobAfterKey,
    ).length;
    final retained = charlieFinal['groupPresent'] == true;
    final selfGone = charlieFinal['selfMember'] == false;
    final noKey = (charlieFinal['keyEpoch'] as int? ?? 0) == 0;
    final roleProof = <String, Map<String, Object?>>{
      'alice': {
        'removedCharlie': !members(removed).contains(charlie),
        'removedPeerId': charlie,
        'sentPreRemovalHistory': aliceBefore!['accepted'] == true,
        'sentPostRemovalMessage': aliceAfter!['accepted'] == true,
        'receivedBobPostRemovalMessage': aliceGotBob != null,
        'memberListExcludesCharlie': !members(
          finals['alice']!,
        ).contains(charlie),
        'rotatedEpoch': rotated,
      },
      'bob': {
        'receivedPreRemovalHistory': bobGotBefore != null,
        'receivedAlicePostRemovalMessage': bobGotAfter != null,
        'sentBobPostRemovalMessage': bobAfter!['accepted'] == true,
        'memberListExcludesCharlie': !members(finals['bob']!).contains(charlie),
        'hasRotatedEpoch': finals['bob']!['keyEpoch'] == rotated,
        'rotatedEpoch': rotated,
      },
      'charlie': {
        'retainedLocalGroup': retained,
        'retainedPreRemovalHistory':
            productionCatalogRows(charlieFinal, productionMl017BeforeKey)
                .length ==
            1,
        'composeDisabled': selfGone,
        // The original's own definition of a rejected send.
        'postRemovalSendRejected': rejected['outcome'] == 'unauthorized',
        'selfMemberRemoved': selfGone,
        'noCurrentKey': noKey,
        'selfRemovalCleanupObserved': retained && selfGone && noKey,
        'receivedAlicePostRemovalMessage': aliceLeak > 0,
        'receivedBobPostRemovalMessage': bobLeak > 0,
        'postRemovalPublishAccepted': rejected['accepted'] == true,
        'postRemovalPlaintextCount': aliceLeak + bobLeak,
        'postRemovalSendOutcome': rejected['outcome'],
      },
    };
    final sentByRole = {
      'alice': [aliceBefore, aliceAfter],
      'bob': [bobAfter],
      'charlie': [Map<String, Object?>.from(rejected)],
    };
    final receivedByRole = {
      'alice': [aliceGotBob!],
      'bob': [bobGotBefore!, bobGotAfter!],
      'charlie': [charlieGotBefore!],
    };
    final verdicts = [
      for (final role in const ['alice', 'bob', 'charlie'])
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: scenario,
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': sentByRole[role],
          'receivedMessages': receivedByRole[role],
          'persistedMessageCounts': {
            for (final r in receivedByRole[role]!)
              '${r['key']}': r['persistedCount'],
          },
          'ml017HistoryRetentionProof': {
            'rowId': 'ML-017',
            ...roleProof[role]!,
          },
        }),
    ];
    final original = evaluateGroupMultiPartyVerdicts(
      scenario: scenario,
      relayAddresses: proof['relayAddresses'] as String,
      verdicts: verdicts,
    );
    if (!original.ok) failures.add(original.detail);
  } catch (error) {
    failures.add('malformed $scenario proof: ${error.runtimeType} $error');
  }
  return failures;
}
