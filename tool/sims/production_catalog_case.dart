import '../../integration_test/scripts/group_multi_party_device_criteria.dart';
import 'production_catalog_verdicts.dart';

const _roles = ['alice', 'bob', 'charlie'];

/// One original proof message: the sending [role] and its exact [text].
typedef ProductionCatalogText = ({String role, String text});

/// Read access to one catalog proof for a scenario adapter: identity-checked
/// stages, sent and received original proof messages, and verdict assembly.
final class ProductionCatalogCase {
  ProductionCatalogCase._(this.proof, this.scenario, this.failures)
    : run = proof['runId'] as String,
      peers = proof['peers'] as Map;

  final Map<String, Object?> proof;
  final String scenario;
  final List<String> failures;
  final String run;
  final Map peers;

  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  /// The snapshot recorded as [name], checked to belong to [role] in this run.
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

  Map finalOf(String role) => stage('${role}Final', role);

  Set<String> members(Map snapshot) => {
    for (final p in (snapshot['memberPeerIds'] as List?) ?? const []) '$p',
  };

  int epoch(String role) => (finalOf(role)['keyEpoch'] as int?) ?? 0;

  /// [role]'s own outgoing row for [key] with its observed durable
  /// recipients; null (and a failure) when absent.
  Map<String, Object?>? sent(String role, String key) {
    final f = finalOf(role);
    final rows = productionCatalogRows(f, key);
    require(
      rows.length == 1 && rows.single['isIncoming'] == false,
      '$role: own outgoing $key row',
    );
    if (rows.isEmpty) return null;
    return productionCatalogDurableSent(
      rows.single,
      key,
      (f['deliveries'] as List?) ?? const [],
    );
  }

  /// [sent] plus the publish evidence of that message
  /// ([productionCatalogFanout]); null (and a failure) when absent.
  Map<String, Object?>? sentFanout(String role, String key) {
    final s = sent(role, key);
    if (s == null) return null;
    final row = productionCatalogRows(finalOf(role), key).single;
    return {
      ...s,
      ...productionCatalogFanout(
        row,
        (finalOf(role)['deliveries'] as List?) ?? const [],
      ),
    };
  }

  /// Whether [role]'s copy of [key] arrived live on the topic (its message id
  /// is in the final snapshot's `liveMessageIds`); false when it came from
  /// the offline inbox or is absent.
  bool live(String role, String key) {
    final rows = productionCatalogRows(finalOf(role), key);
    final ids = (finalOf(role)['liveMessageIds'] as List?) ?? const [];
    return rows.length == 1 && ids.contains(rows.single['messageId']);
  }

  /// [role]'s incoming row for [key] from stage `got:<key>:<role>`, with the
  /// final persisted count; null (and a failure) when absent.
  Map<String, Object?>? received(String role, String key) {
    final rows = productionCatalogRows(stage('got:$key:$role', role), key);
    require(
      rows.length == 1 && rows.single['isIncoming'] == true,
      '$role: exactly one incoming $key row',
    );
    if (rows.isEmpty) return null;
    return productionCatalogReceived(
      rows.single,
      key,
      productionCatalogRows(finalOf(role), key).length,
    );
  }

  /// [received] with the original's `liveOnly` and `usedOfflineDrain`,
  /// observed: live means the message id arrived on the topic
  /// (`liveMessageIds`), otherwise it came from the offline inbox.
  Map<String, Object?>? receivedVia(String role, String key) {
    final r = received(role, key);
    if (r == null) return null;
    final viaTopic = live(role, key);
    return {...r, 'liveOnly': viaTopic, 'usedOfflineDrain': !viaTopic};
  }

  /// [role]'s incoming row for [key] read from its final snapshot (for long
  /// cycle runs that keep no per-receipt stage); null (and a failure) when
  /// absent or not exactly one.
  Map<String, Object?>? receivedAtEnd(String role, String key) {
    final rows = productionCatalogRows(finalOf(role), key);
    require(
      rows.length == 1 && rows.single['isIncoming'] == true,
      '$role: exactly one incoming $key row at the end',
    );
    return rows.length == 1
        ? productionCatalogReceived(rows.single, key, 1)
        : null;
  }

  /// Rows of [key] in [role]'s final snapshot.
  int finalCount(String role, String key) =>
      productionCatalogRows(finalOf(role), key).length;

  /// One original per-role verdict from the final snapshot.
  Map<String, dynamic> verdict(
    String role, {
    List<Map<String, Object?>?> sent = const [],
    List<Map<String, Object?>?> received = const [],
    Map<String, Object?> extra = const {},
  }) {
    final rx = received.whereType<Map<String, Object?>>().toList();
    return Map<String, dynamic>.from({
      ...productionCatalogBaseVerdict(
        scenario: scenario,
        role: role,
        run: run,
        snapshot: finalOf(role),
      ),
      'sentMessages': sent.whereType<Map<String, Object?>>().toList(),
      'receivedMessages': rx,
      'persistedMessageCounts': {
        for (final r in rx) '${r['key']}': r['persistedCount'],
      },
      ...extra,
    });
  }
}

/// Validates one catalog proof: distinct peers, the exact ordered UI flows,
/// then the case's [verdicts] fed to the unchanged original oracle.
List<String> validateProductionCatalogCase({
  required Map<String, Object?> proof,
  required String scenario,
  required List<String> flows,
  required List<Map<String, dynamic>> Function(ProductionCatalogCase c)
  verdicts,
}) {
  final failures = <String>[];
  try {
    final c = ProductionCatalogCase._(proof, scenario, failures);
    // Alice, Bob and Charlie always; four-person cases add Dana.
    final roles = {..._roles, ...c.peers.keys.cast<String>()};
    c.require(
      roles.map((r) => c.peers[r]).whereType<String>().toSet().length ==
          roles.length,
      roles.length == 3 ? 'three distinct peers' : 'distinct peer per role',
    );
    c.require(
      (proof['flows'] as List).join(',') == flows.join(','),
      'exact ordered UI flows',
    );
    final built = verdicts(c);
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: scenario,
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: built,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed $scenario proof: ${error.runtimeType} $error');
  }
  return failures;
}
