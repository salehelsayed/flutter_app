const productionGroupLocalMediaDelete =
    'production.group_catalog.received_media_local_delete';
const groupLocalMediaDeleteRuntime = 'production.group_catalog.de002';

Map<String, ({String role, String text, bool media})>
groupLocalMediaDeleteTexts(String run) => {
  'target': (role: 'alice', text: 'Local deletion target $run', media: true),
  'marker': (role: 'alice', text: 'Preserved group text $run', media: false),
  'preserved': (role: 'alice', text: 'Preserved group image $run', media: true),
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _maps(Object? value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];
List<Map<String, Object?>> _rows(Map snapshot, String key) =>
    _maps(_map(snapshot['watched'])[key]);

/// Only GC-009's received-media local-deletion leg. Existing quote and
/// reaction scenarios remain complementary. This is not physical-file erasure
/// proof, attachment-key inspection or an image-decoding/frame oracle.
List<String> validateProductionGroupLocalMediaDelete(
  Map<String, Object?> proof,
) {
  final failures = <String>[];
  void require(bool value, String detail) {
    if (!value) failures.add(detail);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run is required'];
  const roles = ['alice', 'bob', 'charlie'];
  final peers = _map(proof['peers']);
  require(
    proof['runtimeScenario'] == groupLocalMediaDeleteRuntime &&
        proof['emulatorTriple'] == true &&
        roles.every(
          (r) => peers[r] is String && (peers[r]! as String).isNotEmpty,
        ) &&
        roles.map((r) => peers[r]).toSet().length == 3,
    'existing runtime and three distinct disposable accounts are required',
  );
  require(
    proof['fixtureSha256'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(proof['fixtureSha256']! as String),
    'actual existing gallery fixture digest is required',
  );
  final texts = groupLocalMediaDeleteTexts(run);
  final initial = _map(proof['initialNonces']);
  final finalNonces = _map(proof['finalNonces']);
  final kills = _map(proof['ownedKills']);
  final before = _map(proof['beforeDelete']);
  final base = _map(before['alice']);
  final group = base['groupId'];
  final config = base['groupConfigStateHash'];
  final epoch = base['keyEpoch'];
  require(
    group is String &&
        group.isNotEmpty &&
        config is String &&
        config.isNotEmpty &&
        epoch is int &&
        epoch >= 0,
    'canonical group/configuration/key epoch is required',
  );
  final canonical = <String, Map<String, Object?>>{};
  for (final entry in texts.entries) {
    final rows = _rows(_map(before[entry.value.role]), entry.key);
    require(rows.length == 1, '${entry.key}: exactly one actual author row');
    if (rows.length != 1) continue;
    final row = rows.single;
    require(
      row['messageId'] is String &&
          (row['messageId']! as String).isNotEmpty &&
          row['groupId'] == group &&
          row['text'] == entry.value.text &&
          row['senderPeerId'] == peers[entry.value.role] &&
          row['isIncoming'] == false &&
          row['mediaAttachmentCount'] == (entry.value.media ? 1 : 0) &&
          DateTime.tryParse('${row['timestamp']}') != null &&
          row['keyEpoch'] is int &&
          ['sent', 'delivered'].contains(row['status']),
      '${entry.key}: accepted author content/identity/attachment count',
    );
    canonical[entry.key] = row;
  }
  require(
    canonical.values.map((row) => row['messageId']).toSet().length == 3,
    'target, preserved text and preserved image must be distinct messages',
  );
  // The real Photo selectors are bracketed by this separately authored text.
  final targetTime = DateTime.tryParse('${canonical['target']?['timestamp']}');
  final markerTime = DateTime.tryParse('${canonical['marker']?['timestamp']}');
  final preservedTime = DateTime.tryParse(
    '${canonical['preserved']?['timestamp']}',
  );
  require(
    targetTime != null &&
        markerTime != null &&
        preservedTime != null &&
        markerTime.isAfter(targetTime) &&
        preservedTime.isAfter(markerTime),
    'actual source ordering must bracket the two gallery messages',
  );
  final wantedMembers = roles.map((role) => peers[role]).toSet();
  for (final phase in ['beforeDelete', 'afterDelete', 'afterRestart']) {
    final snapshots = _map(proof[phase]);
    for (final role in roles) {
      final snapshot = _map(snapshots[role]);
      final members = snapshot['memberPeerIds'];
      final configMembers = snapshot['configMemberPeerIds'];
      final nonce = phase == 'afterRestart' ? finalNonces[role] : initial[role];
      require(
        snapshot['runId'] == run &&
            snapshot['role'] == role &&
            snapshot['scenario'] == 'de002' &&
            snapshot['peerId'] == peers[role] &&
            snapshot['groupId'] == group &&
            snapshot['invocationNonce'] == nonce &&
            nonce is String &&
            nonce.isNotEmpty &&
            snapshot['lifecycle'] == 'resumed' &&
            snapshot['groupConfigStateHash'] == config &&
            snapshot['keyEpoch'] == epoch &&
            snapshot['lastMembershipEventAt'] ==
                base['lastMembershipEventAt'] &&
            members is List &&
            members.length == 3 &&
            members.toSet().length == 3 &&
            members.toSet().containsAll(wantedMembers) &&
            configMembers is List &&
            configMembers.length == 3 &&
            configMembers.toSet().length == 3 &&
            configMembers.toSet().containsAll(wantedMembers),
        '$phase/$role: original group/configuration/membership and fresh observation',
      );
      for (final entry in texts.entries) {
        final deleted =
            phase != 'beforeDelete' && role == 'bob' && entry.key == 'target';
        final rows = _rows(snapshot, entry.key);
        require(
          rows.length == (deleted ? 0 : 1),
          '$phase/$role/${entry.key}: local-only exact-once state',
        );
        if (deleted || rows.length != 1) continue;
        final row = rows.single;
        final expected = canonical[entry.key];
        require(
          expected != null &&
              row['messageId'] == expected['messageId'] &&
              row['text'] == expected['text'] &&
              row['groupId'] == group &&
              row['senderPeerId'] == expected['senderPeerId'] &&
              row['timestamp'] == expected['timestamp'] &&
              row['keyEpoch'] == expected['keyEpoch'] &&
              row['mediaAttachmentCount'] == (entry.value.media ? 1 : 0) &&
              row['isIncoming'] == (role != entry.value.role),
          '$phase/$role/${entry.key}: preserve original content/identity/media ownership',
        );
      }
    }
  }
  for (final role in roles) {
    require(
      _map(kills[role])['verifiedUidKill'] == true &&
          initial[role] is String &&
          (initial[role]! as String).isNotEmpty &&
          finalNonces[role] is String &&
          (finalNonces[role]! as String).isNotEmpty &&
          initial[role] != finalNonces[role],
      '$role: verified owned process death and fresh relaunch',
    );
  }
  final flows = proof['flows'];
  final wanted = [
    'create', 'accept-bob', 'accept-charlie',
    'send-target', 'send-marker', 'send-preserved',
    for (final role in roles) ...[
      'before-target-$role',
      'before-preserved-$role',
    ],
    'delete-target-bob',
    // Group navigation after the fresh owned relaunch is a separate UI receipt.
    for (final phase in ['afterDelete', 'afterRestart']) ...[
      if (phase == 'afterRestart')
        for (final role in roles) 'open-afterRestart-$role',
      for (final role in roles) ...[
        if (role != 'bob') '$phase-target-$role',
        '$phase-preserved-$role',
        if (role == 'bob') '$phase-absent-bob',
      ],
    ],
  ];
  require(
    flows is List && flows.join('\u0000') == wanted.join('\u0000'),
    'actual targeted image/menu/confirmation and preserved-content UI receipts required',
  );
  return failures;
}
