const productionDirectSenderOffline =
    'production.direct_catalog.sender_offline_recovery';
const directSenderOfflineRuntime = 'production.routing_smoke';

String directSenderOfflineText(String run) => 'Sender offline recovery $run';

/// Actual English transport semantics shipped by LetterCard. This scenario
/// records those semantics separately from persisted delivery status: there
/// is no delivered double-check or proposed read-status ladder.
String? directSenderOfflineTransportLabel(
  Object? transport, {
  required bool incoming,
}) {
  final labels = incoming
      ? <String, String>{
          'relay': 'Received via cellular relay',
          'direct': 'Received via direct connection',
          'reuse': 'Received via direct connection',
          'upgraded': 'Received via upgraded direct connection',
          'wifi': 'Received via Wi-Fi',
          'local': 'Received via Wi-Fi',
          'inbox': 'Received via inbox',
        }
      : <String, String>{
          'relay': 'Sent via cellular relay',
          'direct': 'Sent via direct connection',
          'reuse': 'Sent via direct connection',
          'upgraded': 'Upgraded to direct connection',
          'wifi': 'Sent via Wi-Fi',
          'local': 'Sent via Wi-Fi',
          'inbox': 'Sent to inbox',
        };
  return labels[transport];
}

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _rows(Map snapshot) => snapshot['messages'] is List
    ? (snapshot['messages'] as List).whereType<Map>().map(_map).toList()
    : [];

/// DC-022's ordinary-text custody-aware automatic recovery path, with partial
/// DC-007 pending/transport evidence. The stopped production node is the
/// networking prerequisite; this does not claim OS airplane-mode coverage or
/// exercise a terminal manual-Retry row lacking a staged envelope.
List<String> validateProductionDirectSenderOffline(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool value, String reason) {
    if (!value) failures.add(reason);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run required'];
  final peers = _map(proof['peers']);
  require(
    proof['runtimeScenario'] == directSenderOfflineRuntime &&
        proof['emulatorPair'] == true &&
        peers['alice'] is String &&
        peers['bob'] is String &&
        '${peers['alice']}'.isNotEmpty &&
        '${peers['bob']}'.isNotEmpty &&
        peers['alice'] != peers['bob'],
    'existing routing runtime and distinct disposable accounts required',
  );
  final stop = _map(proof['stop']);
  final stopped = _map(stop['after']);
  require(
    stop['operation'] == 'stop' &&
        stop['result'] == true &&
        stopped['isStarted'] == false &&
        stopped['connections'] is List &&
        (stopped['connections'] as List).isEmpty,
    'actual successful production-node stop, not an inferred offline badge, required',
  );
  final phases = _map(proof['phases']);
  final offline = _map(phases['offline']);
  final sender = _map(offline['alice']);
  final source = _rows(sender);
  require(
    source.length == 1 &&
        _map(sender['node'])['isStarted'] == false &&
        _rows(_map(offline['bob'])).isEmpty,
    'one persisted failed submission while sender transport remains stopped and receiver has no delivery required',
  );
  if (source.length != 1) return failures;
  final original = source.single;
  final id = original['id'];
  require(
    id is String &&
        id.isNotEmpty &&
        original['status'] == 'failed' &&
        original['text'] == directSenderOfflineText(run) &&
        original['lane'] == 'direct' &&
        original['incoming'] == false &&
        original['conversationId'] == peers['bob'] &&
        DateTime.tryParse('${original['timestamp']}') != null,
    'ordinary production node-not-running outcome must be preserved as its actual authoritative failed row',
  );
  final start = _map(proof['start']);
  final warm = _map(proof['warm']);
  require(
    start['operation'] == 'start' &&
        start['result'] == true &&
        _map(start['after'])['isStarted'] == true &&
        warm['operation'] == 'warm_background' &&
        warm['result'] == true,
    'actual production reconnect and supported recovery prerequisite required',
  );
  final ui = _map(proof['ui']);
  final paths = <Object?>{};
  void receipt(String label, String flow, Map<String, String> expected) {
    final item = _map(ui[label]);
    final value = _map(item['receipt']);
    final flows = value['flows'];
    final args = _map(item['values']);
    require(
      item['flow'] == flow &&
          item['path'] is String &&
          '${item['path']}'.isNotEmpty &&
          paths.add(item['path']) &&
          value['status'] == 'PASS' &&
          value['exit_status'] == 0 &&
          flows is List &&
          flows.length == 1 &&
          flows.single == flow &&
          expected.entries.every((e) => args[e.key] == e.value),
      '$label: exact fresh UI receipt and bound values required',
    );
  }

  final text = RegExp.escape(directSenderOfflineText(run));
  receipt('send-offline', 'production_direct_send_checkpoint', {
    'MESSAGE': directSenderOfflineText(run),
    'MESSAGE_PATTERN': text,
  });
  receipt('offline-ui', 'production_direct_assert_action', {
    'VISIBLE_PATTERN': '$text.*Message status: sending',
    'ABSENT_PATTERN': '$text.*(?:Message status: failed|Retry)',
  });
  final nonces = _map(proof['nonces']);
  for (final role in ['alice', 'bob']) {
    final pair = nonces[role];
    require(
      pair is List &&
          pair.length == 2 &&
          pair.every((v) => v is String && v.isNotEmpty) &&
          pair[0] != pair[1],
      '$role: fresh initial and restart invocation required',
    );
    require(
      _map(_map(proof['ownedKills'])[role])['verifiedUidKill'] == true,
      '$role: actual owned process-death receipt required',
    );
    final offlineSnapshot = _map(offline[role]);
    require(
      offlineSnapshot['observedRunId'] == run &&
          offlineSnapshot['observedRole'] == role &&
          pair is List &&
          pair.length == 2 &&
          offlineSnapshot['observedNonce'] == pair[0],
      '$role: current initial invocation required for the offline witness',
    );
    for (final phase in ['reconnected', 'restarted']) {
      final snapshot = _map(_map(phases[phase])[role]);
      final rows = _rows(snapshot);
      final node = _map(snapshot['node']);
      require(
        rows.length == 1 &&
            snapshot['observedRunId'] == run &&
            snapshot['observedRole'] == role &&
            pair is List &&
            pair.length == 2 &&
            snapshot['observedNonce'] == pair[phase == 'restarted' ? 1 : 0] &&
            node['isStarted'] == true &&
            node['sendCapabilityReady'] == true &&
            node['inboxCapabilityReady'] == true,
        '$phase/$role: exact ready production invocation and one recovered row required',
      );
      if (rows.length != 1) continue;
      final row = rows.single;
      require(
        row['id'] == id &&
            row['text'] == original['text'] &&
            row['timestamp'] == original['timestamp'] &&
            row['lane'] == 'direct' &&
            row['conversationId'] == peers[role == 'alice' ? 'bob' : 'alice'] &&
            row['incoming'] == (role == 'bob') &&
            row['deletedAt'] == null &&
            (role != 'alice' || row['status'] == 'delivered'),
        '$phase/$role: automatic recovery changed logical identity or downgraded delivery',
      );
      final label = directSenderOfflineTransportLabel(
        row['transport'],
        incoming: role == 'bob',
      );
      require(
        label != null,
        '$phase/$role: actual supported persisted transport required',
      );
      receipt('$phase-ui-$role', 'production_direct_assert_action', {
        'VISIBLE_PATTERN':
            '$text.*${RegExp.escape(label ?? 'UNSUPPORTED_TRANSPORT')}',
        'ABSENT_PATTERN': '$text.*(?:Message status: failed|Retry)',
      });
    }
  }
  return failures;
}
