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
