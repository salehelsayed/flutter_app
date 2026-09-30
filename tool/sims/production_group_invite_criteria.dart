/// Preserves the F/C/D invitation reliability intermediates. Host polling
/// intervals retain their original upper bounds; they are not latency metrics.
List<String> validateProductionGroupInvite(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  Map object(Object? value) => value is Map ? value : const {};
  List<Map> rows(Object? value) => value is List && value.every((v) => v is Map)
      ? value.cast<Map>()
      : const [];
  bool nonempty(Object? value) => value is String && value.isNotEmpty;
  final run = proof['runId'];
  final peers = object(proof['peers']);
  final groupId = proof['groupId'];
  require(
    nonempty(run) && nonempty(groupId),
    'run and group identities required',
  );
  require(
    nonempty(peers['alice']) &&
        nonempty(peers['bob']) &&
        peers['alice'] != peers['bob'],
    'distinct exact peers required',
  );
  final name = 'Invite Reliability $run';
  final stageRoles = {
    'created': 'alice',
    'receivedFirst': 'bob',
    'declinedRecipient': 'bob',
    'declinedSender': 'alice',
    'resent': 'alice',
    'receivedSecond': 'bob',
    'revokedSender': 'alice',
    'revokedRecipient': 'bob',
    'staleRecipient': 'bob',
    'freshSender': 'alice',
    'convergedRecipient': 'bob',
  };
  Map stage(String value) => object(proof[value]);
  Map group(String value) => object(stage(value)['group']);
  Map attempt(String value) => object(stage(value)['attempt']);
  for (final entry in stageRoles.entries) {
    final s = stage(entry.key);
    require(
      s['runId'] == run &&
          s['role'] == entry.value &&
          s['peerId'] == peers[entry.value == 'alice' ? 'bob' : 'alice'] &&
          s['groupId'] == groupId,
      '${entry.key} invocation binding',
    );
    require(
      s['lifecycle'] == 'resumed',
      '${entry.key} actual foreground lifecycle',
    );
    require(
      s['pending'] is List && s['revoked'] is List && s['consumed'] is List,
      '${entry.key} repository observations required',
    );
  }
  for (final value in [
    'created',
    'declinedSender',
    'resent',
    'revokedSender',
    'freshSender',
    'staleRecipient',
    'convergedRecipient',
  ]) {
    final g = group(value);
    final bob = stageRoles[value] == 'bob';
    require(
      g['id'] == groupId &&
          g['createdBy'] == peers['alice'] &&
          g['role'] == (bob ? 'member' : 'admin') &&
          g['type'] == 'chat',
      '$value production group authority',
    );
    final members = rows(stage(value)['members']);
    require(
      members.length == 2 &&
          members
                  .where(
                    (m) =>
                        m['peerId'] == peers['alice'] && m['role'] == 'admin',
                  )
                  .length ==
              1 &&
          members
                  .where(
                    (m) => m['peerId'] == peers['bob'] && m['role'] == 'writer',
                  )
                  .length ==
              1,
      '$value exact two-member roster',
    );
    require(
      stage(value)['keyGeneration'] is int &&
          stage(value)['keyGeneration'] == stage('created')['keyGeneration'],
      '$value original key generation retained',
    );
  }
  final first =
      rows(stage('receivedFirst')['pending']).singleOrNull ?? const {};
  final second =
      rows(stage('receivedSecond')['pending']).singleOrNull ?? const {};
  for (final invite in [first, second]) {
    require(
      nonempty(invite['inviteId']) &&
          invite['groupId'] == groupId &&
          invite['senderPeerId'] == peers['alice'] &&
          invite['name'] == name,
      'exact received invitation authority',
    );
  }
  require(
    first['inviteId'] != second['inviteId'],
    'resend must issue a fresh invite ID',
  );
  for (final value in [
    'created',
    'declinedSender',
    'resent',
    'revokedSender',
  ]) {
    final a = attempt(value);
    final old = value == 'created' || value == 'declinedSender';
    require(
      a['group_id'] == groupId &&
          a['peer_id'] == peers['bob'] &&
          nonempty(a['invite_id']) &&
          a['invite_id'] == (old ? first['inviteId'] : second['inviteId']),
      '$value exact persisted delivery attempt',
    );
    require(
      value == 'declinedSender'
          ? a['status'] == 'declined'
          : value == 'revokedSender'
          ? a['status'] == 'revoked'
          : ['sent', 'queued'].contains(a['status']),
      '$value delivery status',
    );
  }
  for (final value in [
    'declinedRecipient',
    'revokedRecipient',
    'staleRecipient',
    'convergedRecipient',
  ]) {
    require(
      stage(value)['pending'] is List &&
          (stage(value)['pending'] as List).isEmpty,
      '$value exact pending invite retired',
    );
  }
  require(
    rows(stage('declinedRecipient')['consumed']).any(
      (r) => r['group_id'] == groupId && r['invite_id'] == first['inviteId'],
    ),
    'decline must persist exact first-invite consumption',
  );
  final revoked = rows(stage('revokedRecipient')['revoked']);
  require(
    revoked.length == 1 &&
        revoked.single['group_id'] == groupId &&
        revoked.single['invite_id'] == second['inviteId'] &&
        revoked.single['revoked_by'] == peers['alice'],
    'exact second-invite revocation tombstone',
  );
  require(
    group('created')['name'] == name &&
        group('staleRecipient')['name'] == name &&
        group('freshSender')['name'] == '$name (fresh)' &&
        group('convergedRecipient')['name'] == '$name (fresh)',
    'real stale to fresh metadata convergence',
  );
  final freshAt = DateTime.tryParse('${group('freshSender')['metadataAt']}');
  final staleAt = DateTime.tryParse('${group('staleRecipient')['metadataAt']}');
  require(
    freshAt != null &&
        (staleAt == null || freshAt.isAfter(staleAt)) &&
        group('convergedRecipient')['metadataAt'] ==
            group('freshSender')['metadataAt'],
    'authoritative newer metadata timestamp converges exactly',
  );
  final request = object(proof['metadataRequest']);
  require(
    request['result'] == 'success' &&
        request['groupId'] == groupId &&
        request['requesterPeerId'] == peers['bob'] &&
        request['inviterPeerId'] == peers['alice'],
    'actual encrypted config request succeeds',
  );
  final waits = object(proof['waits']);
  for (final bound in {
    'receivedFirst': 240000,
    'declinedSender': 150000,
    'receivedSecond': 150000,
    'revokedRecipient': 150000,
    'convergedRecipient': 240000,
  }.entries) {
    final value = waits[bound.key];
    require(
      value is int && value >= 0 && value <= bound.value,
      '${bound.key} original deadline',
    );
  }
  final cases = rows(proof['cases']);
  require(
    cases.length == 3 &&
        cases.map((r) => r['id']).join(',') == 'F,C,D' &&
        cases.every((r) => r['status'] == 'PASS'),
    'all original terminal case receipts required',
  );
  return failures;
}
