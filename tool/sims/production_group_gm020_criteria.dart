import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const productionGm020ImmediateKey = 'aliceGm020ImmediatePostRemoval';
const productionGm020OfflineKey = 'aliceGm020OfflinePostRemoval';

/// Texts of catalog `gm020`, identical to the original harness.
Map<String, String> productionGm020Texts(String run) => {
  productionGm020ImmediateKey:
      'GM-020 Alice immediately after Charlie removal $run',
  productionGm020OfflineKey: 'GM-020 Alice after Charlie unavailable $run',
};

const productionGm020Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'remove-charlie',
  'alice-back-to-chat',
  'alice-immediate',
  'alice-offline',
];

const _keys = [productionGm020ImmediateKey, productionGm020OfflineKey];

List<String> validateProductionGroupGm020(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    require(
      {peers['alice'], peers['bob'], peers['charlie']}.length == 3,
      'three distinct peers',
    );
    require(
      (proof['flows'] as List).join(',') == productionGm020Flows.join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == 'gm020' &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();
    final removed = !members(
      stage('aliceRemoved', 'alice'),
    ).contains(peers['charlie']);
    require(removed, 'Alice removed Charlie before the sends');
    final finals = {
      for (final r in const ['alice', 'bob', 'charlie'])
        r: stage('${r}Final', r),
    };
    final deliveries = [
      for (final d in (finals['alice']!['deliveries'] as List? ?? const []))
        d as Map,
    ];
    final sent = <Map<String, Object?>>[];
    final received = <Map<String, Object?>>[];
    for (final key in _keys) {
      final own = productionCatalogRows(finals['alice']!, key);
      require(
        own.length == 1 && own.single['isIncoming'] == false,
        'alice: own outgoing $key row',
      );
      if (own.isNotEmpty) {
        final durable = deliveries
            .where(
              (d) => d['messageId'] == own.single['messageId'] && d['ok'] == true,
            )
            .toList();
        final recipients = durable.isEmpty
            ? null
            : (durable.last['recipientPeerIds'] as List).toList();
        sent.add({
          ...productionCatalogSent(own.single, key),
          'recipientPeerIds': recipients ?? const [],
          'actualDurablePayloadProof': recipients != null,
        });
      }
      final rows = productionCatalogRows(stage('got:$key:bob', 'bob'), key);
      require(
        rows.length == 1 && rows.single['isIncoming'] == true,
        'bob: exactly one incoming $key row',
      );
      if (rows.isNotEmpty) {
        received.add(
          productionCatalogReceived(
            rows.single,
            key,
            productionCatalogRows(finals['bob']!, key).length,
          ),
        );
      }
    }
    final unavailable = proof['charlieOffline'] == true;
    var leaked = 0;
    for (final key in _keys) {
      leaked += productionCatalogRows(finals['charlie']!, key).length;
    }
    final proofByRole = <String, Map<String, Object?>>{
      'alice': {
        'actualDurablePayloadProof':
            sent.length == 2 &&
            sent.every((x) => x['actualDurablePayloadProof'] == true),
        'removedPeerId': peers['charlie'],
        'removedAt': proof['removedAt'],
        'firstPostRemovalSentAt': sent.isEmpty ? null : sent.first['timestamp'],
        'offlinePostRemovalSentAt': sent.length < 2
            ? null
            : sent.last['timestamp'],
        'postRemovalMessageCount': sent.length,
        'postRemovalMessageKeys': _keys,
        'everyPostRemovalExcludedCharlie':
            sent.length == 2 &&
            sent.every(
              (x) =>
                  (x['recipientPeerIds'] as List).length == 1 &&
                  (x['recipientPeerIds'] as List).single == peers['bob'],
            ),
        'charlieUnavailableBeforeOfflinePostRemoval': unavailable,
      },
      'bob': {
        'receivedEveryPostRemovalMessage': received.length == 2,
        'postRemovalReceiptCount': received.length,
        'postRemovalMessageKeys': _keys,
      },
      'charlie': {
        'receivedPostRemovalPlaintext': leaked > 0,
        'postRemovalPlaintextCount': leaked,
        'unavailableBeforeOfflinePostRemoval': unavailable,
        'checkedPostRemovalMessageKeys': _keys,
      },
    };
    final verdicts = [
      for (final role in const ['alice', 'bob', 'charlie'])
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: 'gm020',
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': role == 'alice' ? sent : const [],
          'receivedMessages': role == 'bob' ? received : const [],
          'persistedMessageCounts': {
            if (role == 'bob')
              for (final r in received) '${r['key']}': r['persistedCount'],
          },
          'gm020ImmediateRecipientExclusionProof': proofByRole[role],
        }),
    ];
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'gm020',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed gm020 proof: ${error.runtimeType} $error');
  }
  return failures;
}
