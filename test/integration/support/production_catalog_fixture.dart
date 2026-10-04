import 'dart:convert';

import '../../../integration_test/scripts/group_multi_party_device_criteria.dart';
import '../../../tool/sims/production_catalog_case.dart';

/// Builds synthetic catalog proofs for adapter tests: three peers, stage
/// snapshots with watched rows, durable deliveries and exact flows.
final class CatalogFixture {
  CatalogFixture(this.scenario, this.texts, this.flows, {this.dana = false});

  final String scenario;
  final Map<String, ProductionCatalogText> texts;
  final List<String> flows;

  /// Four-person cases: Dana is a fourth peer.
  final bool dana;

  static const peers = {
    'alice': 'peer-a',
    'bob': 'peer-b',
    'charlie': 'peer-c',
  };
  static const all = ['peer-a', 'peer-b', 'peer-c'];
  static const fourPeers = {...peers, 'dana': 'peer-d'};

  Map<String, String> get _peers => dana ? fourPeers : peers;

  Map<String, Object?> row(
    String key, {
    required bool incoming,
    int epoch = 2,
    String timestamp = '2026-10-01T12:00:00.000Z',
  }) => {
    'messageId': 'm-$key',
    'groupId': 'g',
    'text': texts[key]!.text,
    'senderPeerId': _peers[texts[key]!.role],
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
    'peerId': _peers[role],
    'transportPeerId': _peers[role],
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
    'recipientPeerIds': [for (final r in to) _peers[r]],
  };

  Map<String, dynamic> base() => {
    'runId': 'run',
    'relayAddresses': expectedMultiPartyRelayAddresses,
    'peers': _peers,
    'flows': [...flows],
  };
}

Map<String, dynamic> copyProof(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
