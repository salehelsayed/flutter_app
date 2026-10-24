const productionGroupOrderedRecovery =
    'production.group_catalog.ordered_text_recovery';
const groupOrderedRecoveryRuntime = 'production.group_catalog.de002';

Map<String, ({String role, String text})> groupOrderedRecoveryTexts(
  String run,
) => {
  for (var i = 0; i < 100; i++)
    'seq$i': (
      role: 'alice',
      text: 'Ordered group ${(i + 1).toString().padLeft(3, '0')} $run',
    ),
  'bob': (role: 'bob', text: 'Bob mutual proof $run'),
  'charlie': (role: 'charlie', text: 'Charlie mutual proof $run'),
  'accepted': (role: 'alice', text: 'Accepted sender crash proof $run'),
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _maps(Object? value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
List<Map<String, Object?>> _rows(Map snapshot, String key) =>
    _maps(_map(snapshot['watched'])[key]);

/// GC-002, plus the accepted-text leg of GC-005. GC-005's membership cuts
/// remain owned by the existing process-death-matrix companion scenario.
List<String> validateProductionGroupOrderedRecovery(
  Map<String, Object?> proof,
) {
  final failures = <String>[];
  void require(bool value, String detail) {
    if (!value) failures.add(detail);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run is required'];
  require(
    proof['runtimeScenario'] == groupOrderedRecoveryRuntime,
    'existing group observation runtime must be identified',
  );
  require(
    proof['emulatorTriple'] == true,
    'three disposable emulator roles required',
  );
  final peers = _map(proof['peers']);
  const roles = ['alice', 'bob', 'charlie'];
  require(
    roles.every(
          (r) => peers[r] is String && (peers[r]! as String).isNotEmpty,
        ) &&
        roles.map((r) => peers[r]).toSet().length == 3,
    'distinct account identities required',
  );
  final texts = groupOrderedRecoveryTexts(run);
  final pre = _map(proof['beforeCrash']);
  final post = _map(proof['afterRestart']);
  final accepted = _map(proof['acceptedSource']);
  final group = accepted['groupId'];
  require(group is String && group.isNotEmpty, 'exact group identity required');
  final expectedMembers = roles.map((r) => peers[r]).toSet();
  final canonical = <String, Map<String, Object?>>{};
  for (final entry in texts.entries) {
    final source = entry.key == 'accepted'
        ? accepted
        : _map(pre[entry.value.role]);
    final rows = _rows(source, entry.key);
    require(rows.length == 1, '${entry.key}: one actual author row required');
    if (rows.length != 1) continue;
    final row = rows.single;
    require(
      row['isIncoming'] == false &&
          row['senderPeerId'] == peers[entry.value.role] &&
          row['messageId'] is String &&
          (row['messageId']! as String).isNotEmpty &&
          row['text'] == entry.value.text &&
          row['groupId'] == group &&
          row['keyEpoch'] is int &&
          (row['keyEpoch']! as int) >= 0 &&
          DateTime.tryParse('${row['timestamp']}') != null &&
          ['sent', 'delivered'].contains(row['status']),
      '${entry.key}: actual accepted author identity/content required',
    );
    canonical[entry.key] = row;
  }
  require(
    canonical.values.map((r) => r['messageId']).toSet().length == 103,
    '103 distinct canonical messages required',
  );
  for (final (phase, actors, keys) in [
    ('beforeCrash', pre, texts.keys.where((k) => k != 'accepted')),
    ('afterRestart', post, texts.keys),
  ]) {
    for (final role in roles) {
      final snapshot = _map(actors[role]);
      final members = snapshot['memberPeerIds'];
      require(
        snapshot['runId'] == run &&
            snapshot['role'] == role &&
            snapshot['scenario'] == 'de002' &&
            snapshot['peerId'] == peers[role] &&
            snapshot['groupId'] == group &&
            snapshot['lifecycle'] == 'resumed' &&
            members is List &&
            members.length == 3 &&
            members.toSet().length == 3 &&
            members.toSet().containsAll(expectedMembers),
        '$phase/$role: exact run/group/membership required',
      );
      for (final key in keys) {
        final rows = _rows(snapshot, key);
        final source = canonical[key];
        require(rows.length == 1, '$phase/$role/$key: exact-once row required');
        if (rows.length != 1 || source == null) continue;
        final row = rows.single;
        require(
          row['messageId'] == source['messageId'] &&
              row['text'] == source['text'] &&
              row['senderPeerId'] == source['senderPeerId'] &&
              row['timestamp'] == source['timestamp'] &&
              row['keyEpoch'] == source['keyEpoch'] &&
              row['groupId'] == group &&
              row['isIncoming'] == (role != texts[key]!.role),
          '$phase/$role/$key: replay changed canonical content, ownership or identity',
        );
      }
      DateTime? previous;
      for (var i = 0; i < 100; i++) {
        final rows = _rows(snapshot, 'seq$i');
        final stamp = rows.length == 1
            ? DateTime.tryParse('${rows.single['timestamp']}')
            : null;
        require(
          stamp != null && (previous == null || stamp.isAfter(previous)),
          '$phase/$role: the 100 Alice messages must preserve send order',
        );
        previous = stamp;
      }
    }
  }
  final crashRow = canonical['accepted'];
  final custody = _maps(
    accepted['deliveries'],
  ).where((d) => d['messageId'] == crashRow?['messageId'] && d['ok'] == true);
  require(
    custody.any((d) {
      final recipients = d['recipientPeerIds'];
      return recipients is List &&
          recipients.toSet().length == 2 &&
          recipients.toSet().containsAll({peers['bob'], peers['charlie']}) &&
          d['inboxStored'] == true;
    }),
    'accepted text must have actual durable recipient custody before the sender cut',
  );
  final kills = _map(proof['ownedKills']);
  final initial = _map(proof['initialNonces']);
  final finalNonces = _map(proof['finalNonces']);
  for (final role in roles) {
    require(
      _map(kills[role])['verifiedUidKill'] == true &&
          initial[role] is String &&
          (initial[role]! as String).isNotEmpty &&
          finalNonces[role] is String &&
          (finalNonces[role]! as String).isNotEmpty &&
          initial[role] != finalNonces[role],
      '$role: actual owned kill and fresh invocation required',
    );
  }
  final offline = _map(proof['offlineRecipients']);
  require(
    offline['bob'] == true && offline['charlie'] == true,
    'both recipients must remain absent until after the accepted sender cut',
  );
  final flows = proof['flows'];
  final expectedFlows = [
    'create',
    'accept-bob',
    'accept-charlie',
    for (var i = 0; i < 100; i++) 'ordered-seq-$i',
    'ordered-bob',
    'ordered-charlie',
    'ordered-accepted',
  ];
  require(
    flows is List && flows.join('\u0000') == expectedFlows.join('\u0000'),
    'all exact UI submission flows must complete in order',
  );
  return failures;
}
