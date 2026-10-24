import 'dart:convert';

import 'package:crypto/crypto.dart';

const productionDirectSendCut = 'production.direct_catalog.inflight_sender_cut';
const directSendCutRuntime = 'production.routing_smoke';

// Below the production interactiveInboxBudget (3s). A host preservation test
// must keep this conservative bound below that actual application constant.
// Both the fresh message timestamp and post-kill date come from the same
// emulator clock; a sampled "sending" row alone cannot certify the cut.
const directSendCutMaximumAgeMs = 2500;

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _rows(Map snapshot) => snapshot['messages'] is List
    ? (snapshot['messages'] as List).whereType<Map>().map(_map).toList()
    : [];

List<String> validateProductionDirectSendCut(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool value, String detail) {
    if (!value) failures.add(detail);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run required'];
  final peers = _map(proof['peers']);
  require(
    proof['runtimeScenario'] == directSendCutRuntime &&
        proof['emulatorPair'] == true &&
        peers['alice'] is String &&
        peers['bob'] is String &&
        (peers['alice']! as String).isNotEmpty &&
        (peers['bob']! as String).isNotEmpty &&
        peers['alice'] != peers['bob'],
    'existing read-only routing runtime and distinct emulator accounts required',
  );
  final cut = _map(proof['cut']);
  final source = _map(cut['source']);
  final rows = _rows(source);
  require(
    source['observedRunId'] == run &&
        source['observedRole'] == 'alice' &&
        rows.length == 1,
    'one current-run sending source row required',
  );
  if (rows.length != 1) return failures;
  final original = rows.single;
  final id = original['id'];
  final stamp = DateTime.tryParse('${original['timestamp']}');
  final cutTime = cut['deviceUnixMsAfterVerifiedDeath'];
  require(
    id is String &&
        id.isNotEmpty &&
        original['text'] == 'In-flight sender cut $run' &&
        original['lane'] == 'direct' &&
        original['incoming'] == false &&
        original['conversationId'] == peers['bob'] &&
        original['status'] == 'sending' &&
        stamp != null,
    'cut must target the actual persisted in-flight text, identity and account',
  );
  require(
    stamp != null &&
        cutTime is int &&
        cutTime >= stamp.millisecondsSinceEpoch &&
        cutTime - stamp.millisecondsSinceEpoch < directSendCutMaximumAgeMs,
    'verified death must precede the original production store timeout',
  );
  final digest = sha256.convert(utf8.encode('$id')).toString();
  for (final name in ['gateBeforeKill', 'gateAfterKill']) {
    final gate = _map(cut[name]);
    require(
      gate['schema'] == 'mknoon.direct-text-send-checkpoint.v1' &&
          gate['armed'] == true &&
          gate['held'] == true &&
          gate['released'] == false &&
          gate['timedOut'] == false &&
          gate['messageSha256'] == digest,
      '$name: the same committed real-store acknowledgement must remain withheld',
    );
  }
  require(
    _map(cut['ownedKill'])['verifiedUidKill'] == true &&
        cut['recipientForceStopped'] == true &&
        cut['recipientAbsentAfterCut'] == true,
    'actual sender UID death and recipient absence required',
  );
  final ui = _map(cut['uiReceipt']);
  require(
    ui['status'] == 'PASS' &&
        ui['exit_status'] == 0 &&
        ui['flows'] is List &&
        (ui['flows'] as List).join('\u0000') ==
            'production_direct_send_checkpoint',
    'actual exact-text and in-flight status UI flow required',
  );
  final nonces = _map(proof['nonces']);
  final restartKills = _map(proof['restartKills']);
  for (final role in ['alice', 'bob']) {
    final values = nonces[role];
    require(
      values is List &&
          values.length == 3 &&
          values.every((v) => v is String && v.isNotEmpty) &&
          values.toSet().length == 3,
      '$role: initial and both fresh restart invocations required',
    );
    require(
      _map(restartKills[role])['verifiedUidKill'] == true,
      '$role: second owned process-death receipt required',
    );
  }
  final phases = _map(proof['phases']);
  for (final phase in ['firstReplay', 'bothRestarted']) {
    final actors = _map(phases[phase]);
    for (final role in ['alice', 'bob']) {
      final snapshot = _map(actors[role]);
      final received = _rows(snapshot);
      require(
        snapshot['observedRunId'] == run &&
            snapshot['observedRole'] == role &&
            received.length == 1,
        '$phase/$role: exact-once current-run transcript required',
      );
      if (received.length != 1) continue;
      final row = received.single;
      require(
        row['id'] == id &&
            row['text'] == original['text'] &&
            row['timestamp'] == original['timestamp'] &&
            row['lane'] == 'direct' &&
            row['incoming'] == (role == 'bob') &&
            row['conversationId'] == peers[role == 'alice' ? 'bob' : 'alice'] &&
            (role != 'alice' || row['status'] == 'delivered'),
        '$phase/$role: recovery changed logical identity/content or did not converge',
      );
    }
  }
  return failures;
}
