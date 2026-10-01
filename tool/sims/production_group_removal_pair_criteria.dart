import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_send_sequence.dart';
import 'production_catalog_verdicts.dart';

/// One removal-then-remaining-pair catalog case: after Alice removes Charlie,
/// [sender] sends ten original texts that [receiver] must receive and the
/// removed Charlie must never decrypt.
final class ProductionRemovalPairCase {
  const ProductionRemovalPairCase({
    required this.scenario,
    required this.row,
    required this.proofName,
    required this.sender,
    required this.keyPrefix,
  });

  final String scenario;
  final String row;
  final String proofName;
  final String sender;
  final String keyPrefix;

  String get receiver => sender == 'alice' ? 'bob' : 'alice';

  List<ProductionSendStep> steps(String run) => [
    for (var i = 1; i <= 10; i++)
      ProductionSendStep(
        sender,
        '$keyPrefix${i.toString().padLeft(2, '0')}',
        '$row ${sender[0].toUpperCase()}${sender.substring(1)} post-removal $i $run',
      ),
  ];

  List<String> flows(String run) => [
    'create',
    'accept-bob',
    'accept-charlie',
    'remove-charlie',
    'alice-back-to-chat',
    for (final s in steps(run)) s.label,
  ];
}

const productionGe002Case = ProductionRemovalPairCase(
  scenario: 'ge002',
  row: 'GE-002',
  proofName: 'ge002RemovalContinuityProof',
  sender: 'alice',
  keyPrefix: 'aliceGe002PostRemoval',
);

const productionGe003Case = ProductionRemovalPairCase(
  scenario: 'ge003',
  row: 'GE-003',
  proofName: 'ge003RemainingPairProof',
  sender: 'bob',
  keyPrefix: 'bobGe003PostRemoval',
);

List<String> validateProductionRemovalPair(
  ProductionRemovalPairCase c,
  Map<String, Object?> proof,
) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    final steps = c.steps(run);
    final keys = [for (final s in steps) s.key];
    require(
      productionCatalogRoles.map((r) => peers[r]).toSet().length == 3,
      'three distinct peers',
    );
    require(
      (proof['flows'] as List).join(',') == c.flows(run).join(','),
      'exact ordered UI flows',
    );
    Map stage(String name, String role) {
      final s = proof[name] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['peerId'] == peers[role] &&
            s['scenario'] == c.scenario &&
            s['lifecycle'] == 'resumed',
        '$name: observation identity',
      );
      return s;
    }

    Set members(Map s) => ((s['memberPeerIds'] as List?) ?? const []).toSet();
    final removed = stage('aliceRemoved', 'alice');
    final removedCharlie = !members(removed).contains(peers['charlie']);
    require(removedCharlie, 'Alice removed Charlie before the sends');
    require(
      !members(stage('bobExcluded', 'bob')).contains(peers['charlie']),
      'Bob excluded Charlie before the sends',
    );
    final finals = {
      for (final r in productionCatalogRoles) r: stage('${r}Final', r),
    };
    final deliveries = [
      for (final d in (finals[c.sender]!['deliveries'] as List? ?? const []))
        d as Map,
    ];
    final sent = <Map<String, Object?>>[];
    final received = <Map<String, Object?>>[];
    for (final s in steps) {
      final own = productionCatalogRows(finals[c.sender]!, s.key);
      require(
        own.length == 1 && own.single['isIncoming'] == false,
        '${c.sender}: own outgoing ${s.key} row',
      );
      if (own.isNotEmpty) {
        final id = own.single['messageId'];
        final durable = deliveries
            .where((d) => d['messageId'] == id && d['ok'] == true)
            .toList();
        final recipients = durable.isEmpty
            ? null
            : (durable.last['recipientPeerIds'] as List).toList();
        sent.add({
          ...productionCatalogSent(own.single, s.key),
          'recipientPeerIds': recipients ?? const [],
          'actualDurablePayloadProof': recipients != null,
        });
      }
      final rows = productionCatalogRows(
        stage('got:${s.key}:${c.receiver}', c.receiver),
        s.key,
      );
      require(
        rows.length == 1 && rows.single['isIncoming'] == true,
        '${c.receiver}: exactly one incoming ${s.key} row',
      );
      if (rows.isNotEmpty) {
        received.add(
          productionCatalogReceived(
            rows.single,
            s.key,
            productionCatalogRows(finals[c.receiver]!, s.key).length,
          ),
        );
      }
    }
    final charlie = finals['charlie']!;
    var leaked = 0;
    for (final key in keys) {
      leaked += productionCatalogRows(charlie, key).length;
    }
    final removedPeerId = peers['charlie'];
    final senderProof = {
      'actualDurablePayloadProof': sent.length == keys.length &&
          sent.every((x) => x['actualDurablePayloadProof'] == true),
      'actualLiveTopicPeerProof': false,
      'postRemovalMessageCount': sent.length,
      'postRemovalMessageKeys': keys,
      'everyPostRemovalExcludedCharlie': sent.length == keys.length &&
          sent.every(
            (x) =>
                (x['recipientPeerIds'] as List).length == 1 &&
                (x['recipientPeerIds'] as List).single == peers[c.receiver],
          ),
    };
    final receiverProof = {
      'receivedEveryPostRemovalMessage': received.length == keys.length,
      'postRemovalReceiptCount': received.length,
      'postRemovalMessageKeys': keys,
    };
    final removalFacts = {
      'removedCharlie': removedCharlie,
      'removedPeerId': removedPeerId,
      'removedAt': proof['removedAt'],
    };
    Map<String, Object?> roleProof(String role) => switch (role) {
      'charlie' => {
        'selfRemoved': charlie['selfMember'] == false,
        'groupPresentAfterRemoval': charlie['groupPresent'] == true,
        'selfMemberPresentAfterRemoval': charlie['selfMember'] == true,
        'postRemovalPlaintextCount': leaked,
        'checkedPostRemovalMessageCount': keys.length,
        'postRemovalMessageKeys': keys,
      },
      _ when role == c.sender => {
        if (role == 'alice') ...removalFacts,
        ...senderProof,
      },
      _ => {if (role == 'alice') ...removalFacts, ...receiverProof},
    };
    final verdicts = [
      for (final role in productionCatalogRoles)
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: c.scenario,
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': role == c.sender ? sent : const [],
          'receivedMessages': role == c.receiver ? received : const [],
          'persistedMessageCounts': {
            if (role == c.receiver)
              for (final r in received) '${r['key']}': r['persistedCount'],
          },
          c.proofName: roleProof(role),
        }),
    ];
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: c.scenario,
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed ${c.scenario} proof: ${error.runtimeType} $error');
  }
  return failures;
}

List<String> validateProductionGroupGe002(Map<String, Object?> proof) =>
    validateProductionRemovalPair(productionGe002Case, proof);

List<String> validateProductionGroupGe003(Map<String, Object?> proof) =>
    validateProductionRemovalPair(productionGe003Case, proof);
