import 'dart:convert';

/// Preserves DELETE_PRESERVES_FRIENDS on production devices: Bob deletes the
/// group from Orbit (swipe, Leave, Leave & Delete); only that group and its
/// messages go, both friends and both 1:1 threads stay and still render. The
/// original's single leave broadcast is proven on the receiving side: the
/// admin's production roster drops Bob.
Map<String, String> productionDeleteTexts(String run) => {
  'aliceHello': 'Friend A hello $run',
  'aliceReply': 'Friend A reply $run',
  'charlieHello': 'Friend C hello $run',
  'charlieReply': 'Friend C reply $run',
  'groupOne': 'Game night one $run',
  'groupTwo': 'Game night two $run',
};

const productionDeleteFlowLabels = [
  'alice-send-bob',
  'bob-send-alice',
  'charlie-send-bob',
  'bob-send-charlie',
  'alice-group-one',
  'alice-group-two',
  'bob-leave-delete',
  'bob-open-alice',
  'bob-render-alice',
  'bob-back-alice',
  'bob-open-charlie',
  'bob-render-charlie',
  'bob-back-charlie',
];

List<String> validateProductionGroupDelete(Map<String, Object?> proof) {
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
  final alice = peers['alice'], bob = peers['bob'], charlie = peers['charlie'];
  final groupId = proof['groupId'];
  require(nonempty(run) && nonempty(groupId), 'run and group identity');
  require(
    [alice, bob, charlie].every(nonempty) &&
        {alice, bob, charlie}.length == 3,
    'three distinct exact peers required',
  );
  final texts = productionDeleteTexts('$run');

  Map stage(String name, String role) {
    final s = object(proof[name]);
    require(
      s['runId'] == run &&
          s['role'] == role &&
          s['selfPeerId'] == peers[role] &&
          s['groupId'] == groupId,
      '$name invocation binding',
    );
    require(s['lifecycle'] == 'resumed', '$name actual foreground lifecycle');
    return s;
  }

  List<String> texts0(Map s, String peer) => [
    for (final m in rows(object(s['direct'])[peer])) '${m['text']}',
  ];
  List<Object?> ids(Map s, String peer) => [
    for (final m in rows(object(s['direct'])[peer])) m['id'],
  ];
  bool thread(Map s, String peer, String incoming, String outgoing) {
    final messages = rows(object(s['direct'])[peer]);
    return messages.length == 2 &&
        messages.any((m) => m['text'] == incoming && m['incoming'] == true) &&
        messages.any((m) => m['text'] == outgoing && m['incoming'] == false);
  }

  final before = stage('beforeDelete', 'bob');
  final group = object(before['group']);
  require(
    group['id'] == groupId &&
        group['name'] == 'Game Night $run' &&
        group['createdBy'] == alice &&
        group['role'] == 'member' &&
        (group['members'] is List) &&
        (group['members'] as List).contains(alice) &&
        (group['members'] as List).contains(bob),
    'beforeDelete production group membership',
  );
  final groupTexts = rows(before['groupMessages']).map((m) => m['text']);
  require(
    groupTexts.contains(texts['groupOne']) &&
        groupTexts.contains(texts['groupTwo']),
    'beforeDelete both group messages received',
  );
  final contacts = (before['contacts'] as List?)?.toSet() ?? const {};
  require(
    contacts.contains(alice) && contacts.contains(charlie),
    'beforeDelete both friends are contacts',
  );
  require(
    thread(before, '$alice', texts['aliceHello']!, texts['aliceReply']!),
    'beforeDelete exact Alice 1:1 thread',
  );
  require(
    thread(before, '$charlie', texts['charlieHello']!, texts['charlieReply']!),
    'beforeDelete exact Charlie 1:1 thread',
  );

  for (final name in ['afterDelete', 'afterUi']) {
    final s = stage(name, 'bob');
    require(s['group'] == null, '$name group deleted');
    require(
      rows(s['groupMessages']).isEmpty,
      '$name group messages purged',
    );
    List<String> sorted(Object? value) => [
      for (final v in value is List ? value : const []) '$v',
    ]..sort();
    require(
      s['contacts'] is List &&
          jsonEncode(sorted(s['contacts'])) ==
              jsonEncode(sorted(before['contacts'])),
      '$name contacts intact',
    );
    for (final peer in ['$alice', '$charlie']) {
      require(
        jsonEncode(ids(s, peer)) == jsonEncode(ids(before, peer)) &&
            jsonEncode(texts0(s, peer)) == jsonEncode(texts0(before, peer)),
        '$name 1:1 thread with $peer intact',
      );
    }
  }

  final adminBefore = object(object(stage('adminBefore', 'alice'))['group']);
  final adminAfter = object(object(stage('adminAfter', 'alice'))['group']);
  require(
    adminBefore['role'] == 'admin' &&
        (adminBefore['members'] as List?)?.contains(bob) == true,
    'admin roster includes Bob before leave',
  );
  require(
    adminAfter['id'] == groupId &&
        adminAfter['role'] == 'admin' &&
        (adminAfter['members'] as List?)?.contains(bob) == false,
    'admin roster drops Bob after his leave',
  );

  require(
    jsonEncode(proof['flows']) == jsonEncode(productionDeleteFlowLabels),
    'exact ordered Maestro flows',
  );
  final cases = rows(proof['cases']);
  require(
    cases.length == 1 &&
        cases.single['id'] == 'DELETE_PRESERVES_FRIENDS' &&
        cases.single['status'] == 'PASS',
    'exact DELETE_PRESERVES_FRIENDS case',
  );
  return failures;
}
