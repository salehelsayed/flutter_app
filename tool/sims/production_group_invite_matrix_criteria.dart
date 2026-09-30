import 'dart:convert';

/// Preserves the original invite-status matrix display proof (UP-005 creator
/// matrix plus member role attach) over seeded production repository rows.
/// Like the original it is not a relay lifecycle proof.
const productionInviteMatrixFlowLabels = [
  'alice-open-matrix',
  'alice-invite-matrix',
  'bob-open-matrix',
  'bob-info-self',
];

const _slots = [
  'acceptedOne',
  'acceptedTwo',
  'sent',
  'queued',
  'resend',
  'cannot',
  'unknown',
];

const _usernames = {
  'acceptedOne': 'Accepted One',
  'acceptedTwo': 'Accepted Two',
  'sent': 'Sent Member',
  'queued': 'Queued Member',
  'resend': 'Resend Member',
  'cannot': 'Cannot Member',
  'unknown': 'Unknown Member',
};

const _attempts = {
  'acceptedTwo': ('sent', null),
  'sent': ('sent', null),
  'queued': ('queued', null),
  'resend': ('needsResend', null),
  'cannot': ('cannotSend', 'missing_secure_key'),
};

List<String> validateProductionGroupInviteMatrix(Map<String, Object?> proof) {
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
  final alice = peers['alice'];
  final bob = peers['bob'];
  require(nonempty(run), 'run identity required');
  require(
    nonempty(alice) && nonempty(bob) && alice != bob,
    'distinct exact peers required',
  );
  final groupId = 'invite-status-matrix-$run';
  require(proof['groupId'] == groupId, 'deterministic run-owned group');
  final expected = {
    for (final slot in _slots)
      slot: slot == 'acceptedOne' ? bob : 'matrix-$run-$slot',
  };
  final bySlot = {for (final e in expected.entries) e.value: e.key};

  final stages = {
    'creatorSeeded': 'alice',
    'memberSeeded': 'bob',
    'creatorObserved': 'alice',
    'memberObserved': 'bob',
  };
  for (final entry in stages.entries) {
    final name = entry.key;
    final role = entry.value;
    final s = object(proof[name]);
    require(
      s['runId'] == run &&
          s['role'] == role &&
          s['selfPeerId'] == peers[role] &&
          s['groupId'] == groupId,
      '$name invocation binding',
    );
    final g = object(s['group']);
    require(
      g['id'] == groupId &&
          g['name'] == 'Invite Status Matrix $run' &&
          g['createdBy'] == alice &&
          g['role'] == (role == 'alice' ? 'admin' : 'member') &&
          g['type'] == 'chat',
      '$name production group authority',
    );
    final members = rows(s['members']);
    final memberIds = members.map((m) => m['peerId']).toSet();
    require(
      members.length == 8 &&
          memberIds.length == 8 &&
          memberIds.containsAll({alice, ...expected.values}),
      '$name exact original eight members',
    );
    for (final m in members) {
      final slot = bySlot[m['peerId']];
      final admin = m['peerId'] == alice;
      require(
        admin
            ? m['role'] == 'admin' && m['joinedEvidenceAt'] == null
            : slot != null &&
                  m['username'] == _usernames[slot] &&
                  m['role'] == 'writer' &&
                  (m['joinedEvidenceAt'] != null) ==
                      (slot == 'acceptedOne' || slot == 'acceptedTwo'),
        '$name member ${slot ?? m['peerId']} seeded as original',
      );
    }
    final attempts = rows(s['attempts']);
    final attemptSlots = attempts.map((a) => bySlot[a['peerId']]).toList();
    require(
      attempts.length == _attempts.length &&
          attemptSlots.toSet().length == _attempts.length &&
          attemptSlots.toSet().containsAll(_attempts.keys),
      '$name exact original invite attempts',
    );
    for (final a in attempts) {
      final want = _attempts[bySlot[a['peerId']]];
      require(
        want != null && a['status'] == want.$1 && a['lastError'] == want.$2,
        '$name attempt ${bySlot[a['peerId']]} status',
      );
    }
    // Accepted Two keeps a stale "sent" attempt; its later member_joined
    // evidence is what makes the production projection show Joined.
    final two = members
        .where((m) => m['peerId'] == expected['acceptedTwo'])
        .firstOrNull;
    final twoAttempt = attempts
        .where((a) => a['peerId'] == expected['acceptedTwo'])
        .firstOrNull;
    final joined = DateTime.tryParse('${two?['joinedEvidenceAt']}');
    final attempted = DateTime.tryParse('${twoAttempt?['attemptedAt']}');
    require(
      joined != null && attempted != null && !joined.isBefore(attempted),
      '$name accepted-two join evidence follows its stale attempt',
    );
  }
  for (final (seeded, observed) in [
    ('creatorSeeded', 'creatorObserved'),
    ('memberSeeded', 'memberObserved'),
  ]) {
    final before = object(proof[seeded]);
    final after = object(proof[observed]);
    require(
      after['lifecycle'] == 'resumed',
      '$observed actual foreground lifecycle',
    );
    require(
      jsonEncode(before['members']) == jsonEncode(after['members']) &&
          jsonEncode(before['attempts']) == jsonEncode(after['attempts']),
      '$observed seeded rows unchanged through the UI check',
    );
  }
  final flows = proof['flows'];
  require(
    flows is List &&
        jsonEncode(flows) == jsonEncode(productionInviteMatrixFlowLabels),
    'exact ordered Maestro flows',
  );
  final cases = rows(proof['cases']);
  require(
    cases.length == 2 &&
        cases[0]['id'] == 'UP-005' &&
        cases[1]['id'] == 'MEMBER-ROLE-ATTACH' &&
        cases.every((c) => c['status'] == 'PASS'),
    'exact UP-005 and member role cases',
  );
  return failures;
}
