import 'production_introduction_mutual_criteria.dart';

const productionIntroductionOffline =
    'production.introduction_catalog.offline_outbox_recovery';

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];

/// IN-009 accept-response leg: offers committed with a stopped sender survive
/// its crash; second acceptance has the first participant offline and survives
/// the responder's crash before that participant naturally receives it.
/// Pass-response/late-accept fencing remains a separate IN-003 leg.
List<String> validateProductionIntroductionOffline(Map<String, Object?> proof) {
  final failures = validateProductionIntroductionMutual(
    proof,
    offlineOutbox: true,
  );
  void require(bool value, String reason) {
    if (!value) failures.add(reason);
  }

  require(
    proof['offlineOutbox'] == true,
    'explicit offline lifecycle required',
  );
  final run = proof['runId'],
      peers = _map(proof['peers']),
      names = _map(proof['names']);
  final nonces = _map(proof['nonces']), kills = _map(proof['ownedKills']);
  final trace = proof['trace'] is List ? proof['trace'] as List : [];
  bool before(String a, String b) =>
      trace.contains(a) &&
      trace.indexOf(b) > trace.indexOf(a) &&
      trace.lastIndexOf(a) == trace.indexOf(a) &&
      trace.lastIndexOf(b) == trace.indexOf(b);
  for (final (a, b) in [
    ('introduce', 'offers-offline-snapshot'),
    ('offers-offline-snapshot', 'kill-offline-alice'),
    ('kill-offline-alice', 'restart-offline-alice'),
    ('restart-offline-alice', 'natural-pending-bob'),
    ('restart-offline-alice', 'natural-pending-charlie'),
    ('accept-bob', 'probe-first-accept-charlie'),
    ('probe-first-accept-charlie', 'response-offline-window'),
    ('response-offline-window', 'accept-charlie'),
    ('accept-charlie', 'response-ready-charlie'),
    ('response-ready-charlie', 'probe-response-committed-charlie'),
    ('probe-response-committed-charlie', 'kill-offline-charlie'),
    ('kill-offline-charlie', 'response-offline-snapshot'),
    ('response-offline-snapshot', 'kill-offline-bob'),
    ('kill-offline-bob', 'restart-offline-charlie'),
    ('restart-offline-charlie', 'restart-offline-bob'),
    ('restart-offline-bob', 'bob-ready'),
    ('restart-offline-bob', 'charlie-ready'),
  ]) {
    require(before(a, b), 'offline causal order missing: $a -> $b');
  }
  for (final role in ['alice', 'bob', 'charlie']) {
    require(
      _map(kills['$role-offline'])['verifiedUidKill'] == true,
      '$role: actual intermediate owned process death required',
    );
  }
  final steps = <Object?>{};
  for (final phase in _map(proof['phases']).values) {
    for (final value in _map(phase).values) {
      steps.add(_map(value)['stepId']);
    }
  }
  Map<String, Object?> receipt(
    String key,
    String role, {
    bool stopped = false,
    int settleDelayMs = 120000,
  }) {
    final value = _map(proof[key]),
        snapshot = _map(_map(proof[key])['snapshot']);
    final history = nonces[role];
    require(
      value['status'] == 'complete' &&
          value['success'] == true &&
          value['observedRunId'] == run &&
          value['observedRole'] == role &&
          history is List &&
          history.isNotEmpty &&
          value['observedNonce'] == history.first &&
          value['probePreambleDrainsInbox'] == true &&
          value['stepId'] is String &&
          '${value['stepId']}'.isNotEmpty &&
          steps.add(value['stepId']) &&
          _map(snapshot['identity'])['peerId'] == peers[role],
      '$key: exact original invocation/account/current probe receipt required',
    );
    if (stopped) {
      final node = _map(value['nodeAction']),
          window = _map(value['offlineWindow']);
      final event = _map(window['freshOwnedPidStopEvent']);
      final start = DateTime.tryParse('${window['actionStartedAt']}'),
          end = DateTime.tryParse('${window['actionCompletedAt']}');
      require(
        node['action'] == 'stop_node' &&
            node['stopped'] == true &&
            event['event'] == 'P2P_SERVICE_STOP_NODE_SUCCESS' &&
            DateTime.tryParse('${event['ts']}') != null &&
            window['onlineBeforeProbe'] == true &&
            window['onlineBeforeAction'] == false &&
            window['onlineAfterAction'] == false &&
            window['actionFinishedBeforeSnapshot'] == true &&
            window['settleDelayMs'] == settleDelayMs &&
            start != null &&
            end != null &&
            !end.isBefore(start) &&
            end.difference(start).inMilliseconds < settleDelayMs &&
            window['flowBeforePath'] is String &&
            '${window['flowBeforePath']}'.isNotEmpty &&
            window['flowStoppedPath'] is String &&
            '${window['flowStoppedPath']}'.isNotEmpty &&
            window['flowBeforePath'] != window['flowStoppedPath'],
        '$key: fresh owned native-stop event and bounded actual UI window required',
      );
    }
    return snapshot;
  }

  final recipientWindow = _map(
    _map(proof['offlineResponseReceiver'])['offlineWindow'],
  );
  final responderWindow = _map(
    _map(proof['offlineResponseCommitted'])['offlineWindow'],
  );
  final recipientStart = DateTime.tryParse(
    '${recipientWindow['actionStartedAt']}',
  );
  final recipientEnd = DateTime.tryParse(
    '${recipientWindow['actionCompletedAt']}',
  );
  final responderStart = DateTime.tryParse(
    '${responderWindow['actionStartedAt']}',
  );
  final responderEnd = DateTime.tryParse(
    '${responderWindow['actionCompletedAt']}',
  );
  require(
    recipientStart != null &&
        recipientEnd != null &&
        responderStart != null &&
        responderEnd != null &&
        !responderStart.isBefore(recipientStart) &&
        !responderEnd.isAfter(recipientEnd),
    'actual second acceptance must occur inside the other participant stopped-node window',
  );
  final offers = receipt('offlineOffers', 'alice', stopped: true);
  final receiver = receipt(
    'offlineResponseReceiver',
    'bob',
    stopped: true,
    settleDelayMs: 240000,
  );
  final responder = receipt(
    'offlineResponseCommitted',
    'charlie',
    stopped: true,
  );
  final offerIntros = _rows(offers['introductions']);
  require(
    offerIntros.length == 1,
    'one persisted offline introduction required',
  );
  if (offerIntros.length != 1) return failures;
  final intro = offerIntros.single, id = offerIntros.single['id'];
  final precondition = receipt('responsePrecondition', 'charlie');
  final firstResponses = _rows(precondition['introductions']);
  require(
    firstResponses.length == 1 &&
        firstResponses.single['id'] == id &&
        firstResponses.single['introducerId'] == peers['alice'] &&
        firstResponses.single['recipientId'] == peers['bob'] &&
        firstResponses.single['introducedId'] == peers['charlie'] &&
        firstResponses.single['recipientStatus'] == 'accepted' &&
        firstResponses.single['introducedStatus'] == 'pending' &&
        firstResponses.single['overallStatus'] == 'pending' &&
        _rows(precondition['contacts']).length == 1 &&
        _rows(precondition['contacts']).single['peerId'] == peers['alice'],
    'actual first acceptance must reach the still-unconnected responder before both nodes stop',
  );
  require(
    id is String &&
        id.isNotEmpty &&
        intro['introducerId'] == peers['alice'] &&
        intro['recipientId'] == peers['bob'] &&
        intro['introducedId'] == peers['charlie'] &&
        intro['recipientStatus'] == 'pending' &&
        intro['introducedStatus'] == 'pending' &&
        intro['overallStatus'] == 'pending',
    'offline offer must commit the actual pending parties before networking',
  );
  final outbox = _rows(offers['introOutboxDeliveries']);
  require(
    outbox.length == 2 &&
        outbox.map((d) => d['targetPeerId']).toSet().containsAll({
          peers['bob'],
          peers['charlie'],
        }) &&
        outbox.map((d) => d['deliveryId']).toSet().length == 2 &&
        outbox.every(
          (d) =>
              d['deliveryId'] is String &&
              '${d['deliveryId']}'.isNotEmpty &&
              d['introductionId'] == id &&
              d['status'] == 'failed',
        ),
    'both actual failed outbound offer carriers must be persisted before the sender crash',
  );
  for (final role in ['alice', 'bob', 'charlie']) {
    final snapshot = _map(
      _map(_map(_map(proof['phases'])['pending'])[role])['snapshot'],
    );
    final rows = _rows(snapshot['introductions']);
    require(
      rows.length == 1 && rows.single['id'] == id,
      '$role: natural offer arrival must retain the offline-committed introduction identity once',
    );
  }
  final receiving = _rows(receiver['introductions']);
  require(
    receiving.length == 1 &&
        receiving.single['id'] == id &&
        receiving.single['recipientStatus'] == 'accepted' &&
        receiving.single['introducedStatus'] == 'pending' &&
        receiving.single['overallStatus'] == 'pending',
    'first accepter must remain pending while its native node is stopped during second acceptance',
  );
  final contacts = _rows(receiver['contacts']);
  require(
    contacts.length == 1 && contacts.single['peerId'] == peers['alice'],
    'offline first accepter cannot gain the new contact before natural response delivery',
  );
  final responding = _rows(responder['introductions']);
  require(
    responding.length == 1 &&
        responding.single['id'] == id &&
        responding.single['recipientStatus'] == 'accepted' &&
        responding.single['introducedStatus'] == 'accepted' &&
        responding.single['overallStatus'] == 'mutual_accepted',
    'second actual UI decision must commit mutual consent before responder crash',
  );
  final pendingDelivery = _rows(responder['introOutboxDeliveries']);
  require(
    pendingDelivery.length == 2 &&
        pendingDelivery.map((d) => d['targetPeerId']).toSet().containsAll({
          peers['alice'],
          peers['bob'],
        }) &&
        pendingDelivery.map((d) => d['deliveryId']).toSet().length == 2 &&
        pendingDelivery.every(
          (d) =>
              d['introductionId'] == id &&
              d['deliveryId'] is String &&
              '${d['deliveryId']}'.isNotEmpty &&
              d['status'] == 'failed',
        ),
    'offline second acceptance must atomically retain both actual failed carriers before responder crash',
  );
  // Accepted inbox custody removes its outbound row in the current code.
  // Requiring a carrier merely because the recipient is offline would be
  // false. Stop the responder too and witness its actual failed carriers.
  final ui = _map(_map(proof['ui'])['response-ready-charlie']);
  final uiReceipt = _map(ui['receipt']), flows = uiReceipt['flows'];
  final otherUiPaths = _map(proof['ui']).entries
      .where((e) => e.key != 'response-ready-charlie')
      .map((e) => _map(e.value)['path'])
      .toSet();
  require(
    ui['flow'] == 'production_intro_ready_chat' &&
        ui['path'] is String &&
        '${ui['path']}'.isNotEmpty &&
        !otherUiPaths.contains(ui['path']) &&
        _map(ui['values'])['PEER_ID'] == peers['bob'] &&
        _map(ui['values'])['OTHER_PATTERN'] ==
            RegExp.escape('${names['bob']}') &&
        uiReceipt['status'] == 'PASS' &&
        uiReceipt['exit_status'] == 0 &&
        flows is List &&
        flows.length == 1 &&
        flows.single == 'production_intro_ready_chat',
    'natural second-acceptance UI must precede the active responder probe',
  );
  return failures;
}
