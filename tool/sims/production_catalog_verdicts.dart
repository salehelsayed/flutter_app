/// Shared builders for original multi-party verdict entries from production
/// repository rows (the `watched` rows of `catalog_watch_snapshot`).
Map<String, Object?> productionCatalogSent(Map row, String key) {
  final ok = ['sent', 'delivered'].contains(row['status']);
  return {
    'key': key,
    'messageId': row['messageId'],
    'groupId': row['groupId'],
    'text': row['text'],
    'outcome': ok ? 'success' : 'status:${row['status']}',
    'senderPeerId': row['senderPeerId'],
    'keyEpoch': row['keyEpoch'],
    'timestamp': row['timestamp'],
    'accepted': ok,
  };
}

Map<String, Object?> productionCatalogReceived(
  Map row,
  String key,
  int persistedCount,
) => {
  'key': key,
  'messageId': row['messageId'],
  'groupId': row['groupId'],
  'text': row['text'],
  'senderPeerId': row['senderPeerId'],
  if (row['senderUsername'] != null) 'senderUsername': row['senderUsername'],
  'timestamp': row['timestamp'],
  'keyEpoch': row['keyEpoch'],
  'isIncoming': row['isIncoming'],
  'persistedCount': persistedCount,
};

/// Common verdict fields from one role's final production snapshot.
Map<String, Object?> productionCatalogBaseVerdict({
  required String scenario,
  required String role,
  required String run,
  required Map snapshot,
}) => {
  'scenario': scenario,
  'role': role,
  'runId': run,
  'deviceId': snapshot['transportPeerId'],
  'peerId': snapshot['peerId'],
  'transportPeerId': snapshot['transportPeerId'],
  'groupId': snapshot['groupId'],
  if (snapshot['topicName'] != null) 'topicName': snapshot['topicName'],
  'keyEpoch': snapshot['keyEpoch'],
  'relayLifecycleProof': true,
  'memberPeerIds': snapshot['memberPeerIds'],
  'activeMemberPeerIds': snapshot['memberPeerIds'],
  if (snapshot['groupConfigStateHash'] != null)
    'groupConfigStateHash': snapshot['groupConfigStateHash'],
};

/// The watched rows for [key] in a snapshot.
List<Map> productionCatalogRows(Map snapshot, String key) =>
    ((((snapshot['watched'] as Map?)?[key]) as List?) ?? const [])
        .cast<Map>();

/// [productionCatalogSent] plus the durable recipients the debug delivery
/// observer recorded for the same message id (`deliveries` of a snapshot).
Map<String, Object?> productionCatalogDurableSent(
  Map row,
  String key,
  List deliveries,
) {
  final durable = [
    for (final d in deliveries)
      if (d is Map && d['messageId'] == row['messageId'] && d['ok'] == true) d,
  ];
  final recipients = durable.isEmpty
      ? null
      : [for (final r in durable.last['recipientPeerIds'] as List) '$r'];
  return {
    ...productionCatalogSent(row, key),
    'recipientPeerIds': recipients ?? const <String>[],
    'actualDurablePayloadProof': recipients != null,
  };
}

/// The publish evidence the debug delivery observer recorded for [row]'s
/// message id: topic peers at send, inbox custody and the live fanout state.
/// The outcome and fanout state follow `send_group_message_use_case.dart`
/// (`successNoPeers` is zero topic peers with inbox custody; the state is
/// `_classifyGroupPublishLiveFanout`).
Map<String, Object?> productionCatalogFanout(Map row, List deliveries) {
  final durable = [
    for (final d in deliveries)
      if (d is Map && d['messageId'] == row['messageId'] && d['ok'] == true) d,
  ];
  if (durable.isEmpty) return {'actualTopicPeerProof': false};
  final d = durable.last;
  final peers = d['topicPeers'] as int?;
  final expected = d['expectedRecipientCount'] as int?;
  final inbox = d['inboxStored'] == true;
  final sent = ['sent', 'delivered'].contains(row['status']);
  return {
    'topicPeers': peers,
    'actualTopicPeerProof': peers != null,
    'inboxStored': inbox,
    'expectedRecipientCount': expected,
    'liveFanoutState': peers == null
        ? 'legacy_unknown'
        : peers <= 0
        ? 'zero_peers'
        : expected != null && peers < expected
        ? 'partial_peers'
        : 'full_peers',
    if (sent) 'outcome': peers == 0 && inbox ? 'successNoPeers' : 'success',
  };
}
