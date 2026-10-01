import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const productionCatalogRoles = ['alice', 'bob', 'charlie'];

/// One original proof send: [role] sends [text] under the original [key] and
/// every other role must receive it exactly once.
final class ProductionSendStep {
  const ProductionSendStep(this.role, this.key, this.text);

  final String role;
  final String key;
  final String text;

  String get label => '$role-send-$key';
}

/// The exact ordered UI flows of a create-accept-send-sequence journey.
List<String> productionSendSequenceFlows(List<ProductionSendStep> steps) => [
  'create',
  'accept-bob',
  'accept-charlie',
  for (final s in steps) s.label,
];

/// Facts one role's scenario-specific proof builder may use.
final class ProductionSendSequenceContext {
  ProductionSendSequenceContext(this.proof, this.peers, this.finals);

  final Map<String, Object?> proof;
  final Map peers;
  final Map<String, Map> finals;

  /// The sender's own outgoing row for [key].
  final sent = <String, Map>{};

  /// The receiver's incoming row for [key], keyed `role:key`.
  final received = <String, Map>{};

  /// Total persisted rows per `role:key` in the final snapshot.
  final finalCounts = <String, int>{};
}

/// Validates a create-accept-send-sequence production proof and feeds the
/// derived per-role verdicts to the unchanged original oracle. [extra] adds
/// each role's scenario proof maps (for example `de001LiveDeliveryProof`).
List<String> validateProductionSendSequence({
  required Map<String, Object?> proof,
  required String scenario,
  required List<ProductionSendStep> steps,
  required Map<String, Object?> Function(
    String role,
    ProductionSendSequenceContext context,
  )
  extra,
}) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final peers = proof['peers'] as Map;
    require(
      productionCatalogRoles.map((r) => peers[r]).toSet().length == 3,
      'three distinct peers',
    );
    require(
      (proof['flows'] as List).join(',') ==
          productionSendSequenceFlows(steps).join(','),
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

    final finals = {for (final r in productionCatalogRoles) r: stage('${r}Final', r)};
    final ctx = ProductionSendSequenceContext(proof, peers, finals);
    for (final step in steps) {
      final own = productionCatalogRows(finals[step.role]!, step.key);
      require(
        own.length == 1 && own.single['isIncoming'] == false,
        '${step.role}: own outgoing ${step.key} row',
      );
      if (own.isNotEmpty) ctx.sent[step.key] = own.first;
      for (final role in productionCatalogRoles.where((r) => r != step.role)) {
        final rows = productionCatalogRows(
          stage('got:${step.key}:$role', role),
          step.key,
        );
        require(
          rows.length == 1 && rows.single['isIncoming'] == true,
          '$role: exactly one incoming ${step.key} row',
        );
        if (rows.isNotEmpty) ctx.received['$role:${step.key}'] = rows.first;
        ctx.finalCounts['$role:${step.key}'] = productionCatalogRows(
          finals[role]!,
          step.key,
        ).length;
      }
    }
    final verdicts = <Map<String, dynamic>>[
      for (final role in productionCatalogRoles)
        Map<String, dynamic>.from({
          ...productionCatalogBaseVerdict(
            scenario: scenario,
            role: role,
            run: run,
            snapshot: finals[role]!,
          ),
          'sentMessages': [
            for (final s in steps)
              if (s.role == role && ctx.sent[s.key] != null)
                productionCatalogSent(ctx.sent[s.key]!, s.key),
          ],
          'receivedMessages': [
            for (final s in steps)
              if (ctx.received['$role:${s.key}'] case final row?)
                productionCatalogReceived(
                  row,
                  s.key,
                  ctx.finalCounts['$role:${s.key}']!,
                ),
          ],
          'persistedMessageCounts': {
            for (final s in steps) s.key: ?ctx.finalCounts['$role:${s.key}'],
          },
          ...extra(role, ctx),
        }),
    ];
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: scenario,
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed $scenario proof: ${error.runtimeType} $error');
  }
  return failures;
}
