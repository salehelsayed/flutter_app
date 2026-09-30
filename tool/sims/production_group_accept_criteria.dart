/// Preserves INVITE_ACCEPT_SPINNER on production devices: Alice's real UI
/// invite reaches Bob; Bob's Accept opens the joined group chat within the
/// original 10 s bound (enforced by the Maestro wait), the pending invite is
/// cleared, the group is persisted, and no SnackBar is mounted.
const productionAcceptFlowLabels = ['alice-create', 'bob-accept'];

List<String> validateProductionGroupAccept(Map<String, Object?> proof) {
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
  final alice = peers['alice'], bob = peers['bob'];
  require(nonempty(run), 'run identity required');
  require(
    nonempty(alice) && nonempty(bob) && alice != bob,
    'distinct exact peers required',
  );
  Map stage(String name, String role) {
    final s = object(proof[name]);
    require(
      s['runId'] == run && s['role'] == role && s['selfPeerId'] == peers[role],
      '$name invocation binding',
    );
    require(s['lifecycle'] == 'resumed', '$name actual foreground lifecycle');
    return s;
  }

  final invited = stage('invited', 'bob');
  final pending = rows(invited['pending']);
  require(
    pending.length == 1 &&
        pending.single['senderPeerId'] == alice &&
        nonempty(pending.single['groupId']) &&
        rows(invited['groups']).isEmpty,
    'invited: exactly one pending invite from Alice and no group yet',
  );
  final groupId = pending.isEmpty ? null : pending.first['groupId'];

  final accepted = stage('accepted', 'bob');
  final groups = rows(accepted['groups']);
  require(rows(accepted['pending']).isEmpty, 'accepted: pending invite cleared');
  require(
    groups.length == 1 &&
        groups.single['id'] == groupId &&
        groups.single['createdBy'] == alice &&
        groups.single['role'] == 'member',
    'accepted: the invited group is persisted for Bob',
  );
  require(accepted['mountedSnackBars'] == 0, 'accepted: no SnackBar mounted');
  require(
    accepted['mountedGroupConversations'] == 1,
    'accepted: the joined group conversation is open',
  );

  final creator = rows(stage('creator', 'alice')['groups']);
  require(
    creator.length == 1 &&
        creator.single['id'] == groupId &&
        creator.single['role'] == 'admin',
    'creator: Alice owns the same group',
  );

  final flows = proof['flows'];
  require(
    flows is List &&
        flows.length == productionAcceptFlowLabels.length &&
        [
          for (var i = 0; i < flows.length; i++)
            flows[i] == productionAcceptFlowLabels[i],
        ].every((ok) => ok),
    'exact ordered Maestro flows',
  );
  final cases = rows(proof['cases']);
  require(
    cases.length == 1 &&
        cases.single['id'] == 'INVITE_ACCEPT_SPINNER' &&
        cases.single['status'] == 'PASS',
    'exact INVITE_ACCEPT_SPINNER case',
  );
  return failures;
}
