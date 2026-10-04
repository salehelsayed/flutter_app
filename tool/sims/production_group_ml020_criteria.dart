import 'production_catalog_case.dart';

const _aliceRemoved = 'aliceRemovedWindowAfterDemotion';
const _bobRemoved = 'bobRemovedWindowAfterAliceDemotion';
const _aliceAfter = 'aliceAfterCharlieReadd';
const _bobAfter = 'bobAfterCharlieReadd';
const _charlieAfter = 'charlieAfterRoleReadd';
const _roles = ['alice', 'bob', 'charlie'];
const _expectedRoles = {'alice': 'writer', 'bob': 'admin', 'charlie': 'writer'};

/// Texts of catalog `private_admin_role_transfer_delivery` (ML-020),
/// identical to the original harness.
Map<String, ProductionCatalogText> productionMl020Texts(String run) => {
  _aliceRemoved: (role: 'alice', text: 'ML-020 Alice removed-window $run'),
  _bobRemoved: (role: 'bob', text: 'ML-020 Bob removed-window $run'),
  _aliceAfter: (role: 'alice', text: 'ML-020 Alice after Charlie re-add $run'),
  _bobAfter: (role: 'bob', text: 'ML-020 Bob after Charlie re-add $run'),
  _charlieAfter: (
    role: 'charlie',
    text: 'ML-020 Charlie after role re-add $run',
  ),
};

const productionMl020Flows = [
  'create',
  'accept-bob',
  'accept-charlie',
  'alice-promotes-bob',
  'bob-demotes-alice',
  'remove-charlie',
  'bob-back-to-chat',
  'alice-removed-window',
  'bob-removed-window',
  'readd-charlie',
  'charlie-home',
  'accept-charlie-readd',
  'alice-after-readd',
  'bob-after-readd',
  'charlie-after-readd',
];

/// Role name of each catalog role as [snapshot]'s own roster shows it.
Map<String, String?> _rolesIn(ProductionCatalogCase c, Map snapshot) {
  final byPeer = {
    for (final m in (snapshot['memberDetails'] as List?) ?? const [])
      '${(m as Map)['peerId']}': m['role'] as String?,
  };
  return {for (final r in _roles) r: byPeer['${c.peers[r]}']};
}

/// The original's per-role `ml020AdminRoleDeliveryProof`, observed: role
/// changes from the rosters after each UI edit, removal and re-add from the
/// membership snapshots, the removed window from Charlie's plaintext count
/// (five seconds after the sends and at the end). The platform label is the
/// original's: every role ran on an iOS simulator.
List<String> validateProductionGroupMl020(
  Map<String, Object?> proof,
) => validateProductionCatalogCase(
  proof: proof,
  scenario: 'private_admin_role_transfer_delivery',
  flows: productionMl020Flows,
  verdicts: (c) {
    final charlie = '${c.peers['charlie']}';
    final promoted = _rolesIn(c, c.stage('bobPromoted', 'alice'));
    final demoted = c.stage('aliceDemoted', 'bob');
    final aliceDemoted =
        _rolesIn(c, demoted)['alice'] == 'writer' &&
        c.members(demoted).contains('${c.peers['alice']}');
    final removed =
        c.stage('charlieRemoved', 'charlie')['selfMember'] == false &&
        !c.members(c.stage('bobRemovedCharlie', 'bob')).contains(charlie);
    final window = c.stage('charlieRemovedWindow', 'charlie');
    var plaintext = 0;
    for (final k in const [_aliceRemoved, _bobRemoved]) {
      plaintext += c.finalCount('charlie', k);
      plaintext += (((window['watched'] as Map?)?[k] as List?) ?? []).length;
    }
    final postReadd = {
      for (final (role, keys) in const [
        ('alice', [_bobAfter, _charlieAfter]),
        ('bob', [_aliceAfter, _charlieAfter]),
        ('charlie', [_aliceAfter, _bobAfter]),
      ])
        role: [for (final k in keys) c.received(role, k)],
    };
    final delivered = postReadd.values.every(
      (rows) => rows.every((r) => r != null),
    );
    final readded =
        (c.proof['flows'] as List).contains('accept-charlie-readd') &&
        _roles.every((r) => c.members(c.finalOf(r)).contains(charlie));

    Map<String, Object?> proofFor(String role) {
      final finalRoles = _rolesIn(c, c.finalOf(role));
      final members = c.members(c.finalOf(role));
      return {
        'rowId': 'ML-020',
        'scenario': 'private_admin_role_transfer_delivery',
        'proofRole': role,
        'appPeerPlatform': 'ios_26_2_core_simulator',
        'roleChangeProofSource': 'app_peer_core_simulator',
        'bobPromotedToAdmin': promoted['bob'] == 'admin',
        'aliceDemotedButActive': aliceDemoted,
        'charlieRemovedBeforeReadd': removed,
        'charlieReaddedAfterRemoval': readded,
        'removedWindowDeliveryExcludedCharlie': plaintext == 0,
        'postReaddDeliveryToAllActiveMembers': delivered,
        'roleStateConverged': _expectedRoles.entries.every(
          (e) => finalRoles[e.key] == e.value,
        ),
        'memberStateConverged':
            members.length == 3 &&
            _roles.every((r) => members.contains('${c.peers[r]}')),
        'finalKeyConverged': c.epoch(role) > 0,
        // Delivery went on with the creator demoted and from a writer.
        'creatorRequiredForDelivery': !(aliceDemoted && delivered),
        'adminOnlyDelivery': !delivered,
        'charlieReceivedRemovedWindow': plaintext > 0,
        'removedWindowPlaintextCount': plaintext,
        'finalEpoch': c.epoch(role),
        'finalMemberRoles': finalRoles,
      };
    }

    return [
      c.verdict(
        'alice',
        sent: [c.sent('alice', _aliceRemoved), c.sent('alice', _aliceAfter)],
        received: [c.received('alice', _bobRemoved), ...postReadd['alice']!],
        extra: {'ml020AdminRoleDeliveryProof': proofFor('alice')},
      ),
      c.verdict(
        'bob',
        sent: [c.sent('bob', _bobRemoved), c.sent('bob', _bobAfter)],
        received: [c.received('bob', _aliceRemoved), ...postReadd['bob']!],
        extra: {'ml020AdminRoleDeliveryProof': proofFor('bob')},
      ),
      c.verdict(
        'charlie',
        sent: [c.sent('charlie', _charlieAfter)],
        received: postReadd['charlie']!,
        extra: {'ml020AdminRoleDeliveryProof': proofFor('charlie')},
      ),
    ];
  },
);
