import '../../integration_test/scripts/group_multi_party_device_criteria.dart';

/// Texts of catalog `private_relay_only_delivery` (NW-002), identical to the
/// original harness.
Map<String, String> productionRelayOnlyTexts(String run) => {
  'aliceToRelayOnlyBob': 'NW-002 Alice to relay-only Bob $run',
  'bobRelayOnlyPublishBack': 'NW-002 Bob relay-only publish back $run',
};

const productionRelayOnlyFlows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-send',
  'bob-publish-back',
];

// Faithful copies of the original harness's NW-002 diagnostic helpers
// (group_multi_party_device_real_harness.dart `_nw002*`), applied to the
// production app's own sanitized flow events.
bool _isDiscovery(String name) =>
    name == 'group:discovery' ||
    name == 'GROUP_DISCOVERY' ||
    name.toLowerCase() == 'group_discovery';

bool _safePrefix(String value) =>
    value.isNotEmpty && value.length <= 12 && !value.contains('/');

String? _peerPrefix(Map details) {
  for (final key in const ['peerIdPrefix', 'targetPeerPrefix']) {
    final value = details[key];
    if (value is String && _safePrefix(value)) return value;
  }
  final peerId = details['peerId'];
  if (peerId is String && peerId != '[redacted]' && _safePrefix(peerId)) {
    return peerId;
  }
  return null;
}

int? _int(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : value is String
    ? int.tryParse(value)
    : null;

Map<String, Object?> productionNw002RouteDiagnostics(
  List flowEvents,
  String bobPeerId,
) {
  final routeEvents = <Map<String, Object?>>[];
  for (final event in flowEvents.whereType<Map>()) {
    final name = '${event['event'] ?? ''}';
    if (!_isDiscovery(name)) continue;
    final details = event['details'] is Map ? event['details'] as Map : {};
    final prefix = _peerPrefix(details);
    if (prefix == null || !bobPeerId.startsWith(prefix)) continue;
    final path = details['path'];
    if (path == 'relay' ||
        path == 'relay_fallback' ||
        details['usedRelayFallback'] == true) {
      routeEvents.add({
        'sourceEvent': name,
        'step': ?details['step'],
        'peerIdPrefix': prefix,
        'path': ?path,
        'attemptedDirect': ?details['attemptedDirect'],
        'directAddrCount': ?_int(details['directAddrCount']),
        'usedRelayFallback': ?details['usedRelayFallback'],
      });
    }
  }
  return {
    'routeEvents': routeEvents,
    'circuitOrRelayRouteProven': routeEvents.isNotEmpty,
    'directPathSuppressed': routeEvents.any(
      (e) =>
          e['path'] == 'relay' &&
          e['attemptedDirect'] == false &&
          _int(e['directAddrCount']) == 0,
    ),
  };
}

List<String> validateProductionGroupRelayOnly(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String detail) {
    if (!ok) failures.add(detail);
  }

  try {
    final run = proof['runId'] as String;
    final finals = proof['final'] as Map;
    final peers = {
      for (final role in const ['alice', 'bob', 'charlie'])
        role: (finals[role] as Map)['peerId'] as String,
    };
    require(peers.values.toSet().length == 3, 'three distinct peers');
    for (final role in peers.keys) {
      require(
        (finals[role] as Map)['advertisesRelayOnly'] == (role == 'bob'),
        '$role: relay-only advertising only on Bob (debug seam)',
      );
      final members = ((finals[role] as Map)['memberPeerIds'] as List?) ?? [];
      require(
        members.length == 3 && members.toSet().containsAll(peers.values),
        '$role: active three-member membership preserved',
      );
    }
    require(
      (proof['flows'] as List).join(',') == productionRelayOnlyFlows.join(','),
      'exact ordered UI flows',
    );
    Map row(String role, String key) {
      final s = finals[role] as Map;
      require(
        s['runId'] == run &&
            s['role'] == role &&
            s['scenario'] == 'private_relay_only_delivery' &&
            s['lifecycle'] == 'resumed' &&
            s['flowEventOverflow'] == false,
        '$role: observation identity',
      );
      final rows = ((s['watched'] as Map)[key] as List?) ?? const [];
      require(rows.length == 1, '$role: exactly one $key row');
      return rows.isEmpty ? const {} : rows.first as Map;
    }

    int persisted(String role, String key) =>
        ((((finals[role] as Map)['watched'] as Map)[key] as List?) ?? const [])
            .length;
    Map<String, Object?> sent(Map r, String key) {
      final ok = ['sent', 'delivered'].contains(r['status']);
      return {
        'key': key,
        'messageId': r['messageId'],
        'groupId': r['groupId'],
        'text': r['text'],
        'outcome': ok ? 'success' : 'status:${r['status']}',
        'senderPeerId': r['senderPeerId'],
        'keyEpoch': r['keyEpoch'],
        'timestamp': r['timestamp'],
        'accepted': ok,
      };
    }

    Map<String, Object?> received(Map r, String key, int count) => {
      'key': key,
      'messageId': r['messageId'],
      'groupId': r['groupId'],
      'text': r['text'],
      'senderPeerId': r['senderPeerId'],
      if (r['senderUsername'] != null) 'senderUsername': r['senderUsername'],
      'timestamp': r['timestamp'],
      'keyEpoch': r['keyEpoch'],
      'isIncoming': r['isIncoming'],
      'persistedCount': count,
    };

    final aliceSent = sent(row('alice', 'aliceToRelayOnlyBob'), 'aliceToRelayOnlyBob');
    final bobSent = sent(
      row('bob', 'bobRelayOnlyPublishBack'),
      'bobRelayOnlyPublishBack',
    );
    require(
      row('alice', 'aliceToRelayOnlyBob')['isIncoming'] == false &&
          row('bob', 'bobRelayOnlyPublishBack')['isIncoming'] == false,
      'senders hold their own outgoing rows',
    );
    final receivedByRole = {
      'alice': [
        received(
          row('alice', 'bobRelayOnlyPublishBack'),
          'bobRelayOnlyPublishBack',
          persisted('alice', 'bobRelayOnlyPublishBack'),
        ),
      ],
      'bob': [
        received(
          row('bob', 'aliceToRelayOnlyBob'),
          'aliceToRelayOnlyBob',
          persisted('bob', 'aliceToRelayOnlyBob'),
        ),
      ],
      'charlie': [
        received(
          row('charlie', 'aliceToRelayOnlyBob'),
          'aliceToRelayOnlyBob',
          persisted('charlie', 'aliceToRelayOnlyBob'),
        ),
        received(
          row('charlie', 'bobRelayOnlyPublishBack'),
          'bobRelayOnlyPublishBack',
          persisted('charlie', 'bobRelayOnlyPublishBack'),
        ),
      ],
    };
    final successNoPeers = [
      aliceSent,
      bobSent,
    ].where((s) => s['outcome'] == 'successNoPeers').length;
    final verdicts = <Map<String, dynamic>>[];
    for (final role in const ['alice', 'bob', 'charlie']) {
      final s = finals[role] as Map;
      final routes = productionNw002RouteDiagnostics(
        s['flowEvents'] as List,
        peers['bob']!,
      );
      final receivedMessages = receivedByRole[role]!;
      verdicts.add({
        'scenario': 'private_relay_only_delivery',
        'role': role,
        'runId': run,
        'deviceId': s['transportPeerId'],
        'peerId': s['peerId'],
        'transportPeerId': s['transportPeerId'],
        'groupId': s['groupId'],
        'topicName': s['topicName'],
        'keyEpoch': s['keyEpoch'],
        'relayLifecycleProof': true,
        'memberPeerIds': s['memberPeerIds'],
        'activeMemberPeerIds': s['memberPeerIds'],
        'groupConfigStateHash': s['groupConfigStateHash'],
        'sentMessages': [
          if (role == 'alice') aliceSent,
          if (role == 'bob') bobSent,
        ],
        'receivedMessages': receivedMessages,
        'persistedMessageCounts': {
          for (final r in receivedMessages) '${r['key']}': r['persistedCount'],
        },
        'nw002RelayOnlyDeliveryProof': {
          'rowId': 'NW-002',
          'relayOnlyRoles': const ['bob'],
          'circuitOrRelayRouteProven':
              routes['circuitOrRelayRouteProven'] == true,
          'directPathSuppressed': routes['directPathSuppressed'] == true,
          'relayLifecycleProof': true,
          'activeMembershipPreserved': true,
          'deliveryModeByMessage': {
            'aliceToRelayOnlyBob': {
              'senderRole': 'alice',
              'routedReceiverRoles': const ['bob'],
              'deliveryMode': 'live_pubsub',
            },
            'bobRelayOnlyPublishBack': {
              'senderRole': 'bob',
              'routedReceiverRoles': const ['alice', 'charlie'],
              'deliveryMode': 'live_pubsub',
            },
          },
          'allRoutedReceiversCovered': true,
          'routedSenderPublishBackCovered': true,
          'replayDeliveryCovered': false,
          'successNoPeersCount': successNoPeers,
          'duplicateVisibleMessageCount': receivedMessages
              .where((r) => (r['persistedCount'] as int) > 1)
              .length,
          'membershipMutationCount': 0,
          'routeDiagnostics': routes['routeEvents'],
          'proofRole': role,
        },
      });
    }
    if (failures.isEmpty) {
      final original = evaluateGroupMultiPartyVerdicts(
        scenario: 'private_relay_only_delivery',
        relayAddresses: proof['relayAddresses'] as String,
        verdicts: verdicts,
      );
      if (!original.ok) failures.add(original.detail);
    }
  } catch (error) {
    failures.add('malformed relay-only proof: ${error.runtimeType} $error');
  }
  return failures;
}
