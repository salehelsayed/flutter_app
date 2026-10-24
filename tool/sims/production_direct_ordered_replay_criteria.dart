const productionDirectOrderedReplay =
    'production.direct_catalog.ordered_offline_replay';
const directOrderedReplayRuntime = 'production.routing_smoke';
const directOrderedReplayCount = 100;
const directOrderedOfflineCount = 10;
const directOrderedTotalCount =
    directOrderedReplayCount + directOrderedOfflineCount;
const directOrderedReplayMinimumDwellMs = 60000;

List<String> directOrderedReplayTexts(String run) => [
  for (var i = 0; i < directOrderedReplayCount; i++)
    'Ordered online ${(i + 1).toString().padLeft(3, '0')} $run',
  for (var i = 0; i < directOrderedOfflineCount; i++)
    'Offline catchup ${(i + 1).toString().padLeft(3, '0')} $run',
];

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};

List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? value.whereType<Map>().map(_object).toList() : [];

/// DC-002 + DC-003: exact UI-submitted content/identity, actual offline custody,
/// complete ordered receiver replay and persistence after both owned processes
/// restart. Registration and a partial receipt count cannot satisfy this proof.
List<String> validateProductionDirectOrderedReplay(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool value, String reason) {
    if (!value) failures.add(reason);
  }

  final run = proof['runId'];
  final peers = _object(proof['peers']);
  require(run is String && run.isNotEmpty, 'exact run is required');
  require(
    proof['runtimeScenario'] == directOrderedReplayRuntime,
    'existing routing runtime must be explicitly identified',
  );
  require(
    peers['alice'] is String &&
        (peers['alice']! as String).isNotEmpty &&
        peers['bob'] is String &&
        (peers['bob']! as String).isNotEmpty &&
        peers['alice'] != peers['bob'],
    'two distinct account identities are required',
  );
  require(
    proof['emulatorPair'] == true,
    'this scenario requires an owned disposable emulator pair',
  );
  final dwell = proof['offlineDwellMs'];
  require(
    dwell is int && dwell >= directOrderedReplayMinimumDwellMs,
    'record the actual supported offline dwell',
  );
  final offlineGuard = _object(proof['offlineGuard']);
  require(
    offlineGuard['ownedPackageForceStopped'] == true &&
        offlineGuard['absentBeforeRelaunch'] == true,
    'the recipient must remain absent throughout the controlled offline leg',
  );
  final kills = _object(proof['ownedKills']);
  for (final name in ['bobOffline', 'aliceRestart', 'bobRestart']) {
    require(
      _object(kills[name])['verifiedUidKill'] == true,
      '$name must have an actual owned-process death receipt',
    );
  }
  final before = _object(proof['initialNonces']);
  final after = _object(proof['finalNonces']);
  for (final role in ['alice', 'bob']) {
    require(
      before[role] is String &&
          (before[role]! as String).isNotEmpty &&
          after[role] is String &&
          (after[role]! as String).isNotEmpty &&
          before[role] != after[role],
      '$role must use a fresh acknowledged invocation after restart',
    );
  }
  if (run is! String || run.isEmpty) return failures;
  final batches = _rows(proof['uiBatches']);
  final paths = <Object?>{};
  require(
    batches.length == 22,
    'all 22 five-message UI flow receipts are required',
  );
  for (var i = 0; i < batches.length; i++) {
    final batch = batches[i];
    final receipt = _object(batch['receipt']);
    final flows = receipt['flows'];
    require(
      batch['firstIndex'] == i * 5 &&
          batch['phase'] == (i < 20 ? 'online' : 'offline') &&
          batch['path'] is String &&
          (batch['path']! as String).isNotEmpty &&
          paths.add(batch['path']) &&
          receipt['status'] == 'PASS' &&
          receipt['exit_status'] == 0 &&
          flows is List &&
          flows.length == 1 &&
          flows.single == 'production_direct_send_batch5',
      'UI batch $i lacks an exact distinct successful submission receipt',
    );
  }
  final expected = directOrderedReplayTexts(run);
  final expectedSet = expected.toSet();
  List<Map<String, Object?>> selected(Object? snapshot) {
    final rows = _rows(
      _object(snapshot)['messages'],
    ).where((row) => expectedSet.contains(row['text'])).toList();
    require(
      rows.every((row) => DateTime.tryParse('${row['timestamp']}') != null),
      'canonical timestamps must be parseable',
    );
    final fallback = DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true);
    rows.sort(
      (a, b) => (DateTime.tryParse('${a['timestamp']}') ?? fallback).compareTo(
        DateTime.tryParse('${b['timestamp']}') ?? fallback,
      ),
    );
    return rows;
  }

  final pending = selected(proof['senderBeforeReplay']);
  final offline = pending
      .where(
        (row) => expected.skip(directOrderedReplayCount).contains(row['text']),
      )
      .toList();
  require(
    pending.length == directOrderedTotalCount &&
        offline.length == directOrderedOfflineCount &&
        offline.every(
          (row) =>
              row['incoming'] == false &&
              row['status'] == 'inboxed' &&
              row['transport'] == 'inbox',
        ),
    'all ten offline messages need persisted relay custody while the recipient is offline',
  );
  final pendingIds = pending.map((row) => row['id']).toList();
  require(
    pendingIds.every((id) => id is String && id.isNotEmpty) &&
        pendingIds.toSet().length == directOrderedTotalCount,
    '110 unique sender identities are required',
  );
  final phases = _object(proof['phases']);
  for (final phase in ['online', 'firstReplay', 'bothRestarted']) {
    final count = phase == 'online'
        ? directOrderedReplayCount
        : directOrderedTotalCount;
    final actors = _object(phases[phase]);
    for (final role in ['alice', 'bob']) {
      final snapshot = _object(actors[role]);
      require(
        snapshot['observedRole'] == role && snapshot['observedRunId'] == run,
        '$phase/$role snapshot is not bound to this acknowledged run',
      );
      final rows = selected(snapshot);
      require(
        rows.length == count,
        '$phase/$role must hold all $count exact rows without duplicates',
      );
      if (rows.length != count || pending.length != directOrderedTotalCount) {
        continue;
      }
      for (var i = 0; i < count; i++) {
        final row = rows[i];
        require(
          row['text'] == expected[i] &&
              row['id'] == pendingIds[i] &&
              row['timestamp'] == pending[i]['timestamp'] &&
              row['lane'] == 'direct' &&
              row['conversationId'] ==
                  peers[role == 'alice' ? 'bob' : 'alice'] &&
              row['incoming'] == (role == 'bob'),
          '$phase/$role row $i lost its content, send order, identity or ownership',
        );
      }
    }
  }
  require(
    pending.map((row) => row['text']).join('\u0000') == expected.join('\u0000'),
    'the source rows must themselves retain the UI submission order',
  );
  return failures;
}
