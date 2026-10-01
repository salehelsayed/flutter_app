import 'dart:convert';

import '../../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../../tool/sims/production_catalog_case.dart';

/// Builds synthetic catalog proofs for adapter tests: three peers, stage
/// snapshots with watched rows, durable deliveries and exact flows.
final class CatalogFixture {
  CatalogFixture(this.scenario, this.texts, this.flows);

  final String scenario;
  final Map<String, ProductionCatalogText> texts;
  final List<String> flows;

  static const peers = {'alice': 'peer-a', 'bob': 'peer-b', 'charlie': 'peer-c'};
  static const all = ['peer-a', 'peer-b', 'peer-c'];

  Map<String, Object?> row(
    String key, {
    required bool incoming,
    int epoch = 2,
    String timestamp = '2026-10-01T12:00:00.000Z',
  }) => {
    'messageId': 'm-$key',
    'groupId': 'g',
    'text': texts[key]!.text,
    'senderPeerId': peers[texts[key]!.role],
    'timestamp': timestamp,
    'keyEpoch': epoch,
    'isIncoming': incoming,
    'status': incoming ? 'received' : 'sent',
  };

  Map<String, Object?> snap(
    String role, {
    List<String> members = all,
    bool self = true,
    int epoch = 2,
    Map<String, Object?> watched = const {},
    Map<String, Object?> extra = const {},
  }) => {
    'runId': 'run',
    'role': role,
    'scenario': scenario,
    'peerId': peers[role],
    'transportPeerId': peers[role],
    'relayReady': true,
    'lifecycle': 'resumed',
    'groupPresent': true,
    'groupId': 'g',
    'topicName': '/mknoon/group/g',
    'keyEpoch': epoch,
    'groupConfigStateHash': 'hash',
    'memberPeerIds': members,
    'selfMember': self,
    'watched': watched,
    ...extra,
  };

  /// A stage snapshot holding one incoming row for [key].
  Map<String, Object?> got(String role, String key, {int epoch = 2}) => snap(
    role,
    watched: {
      key: [row(key, incoming: true, epoch: epoch)],
    },
  );

  /// One successful durable delivery of [key] addressed to [to].
  Map<String, Object?> delivery(String key, List<String> to) => {
    'cmd': 'group:sendReliable',
    'messageId': 'm-$key',
    'ok': true,
    'recipientPeerIds': [for (final r in to) peers[r]],
  };

  Map<String, dynamic> base() => {
    'runId': 'run',
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'peers': peers,
    'flows': [...flows],
  };
}

Map<String, dynamic> copyProof(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
