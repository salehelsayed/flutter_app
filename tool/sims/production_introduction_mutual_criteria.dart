const productionIntroductionMutual =
    'production.introduction_catalog.mutual_accept_direct_chat';
const introductionMutualRuntime = 'production.group_catalog.de002';

String introductionMutualText(String run) => 'Introduction mutual direct $run';

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? value.whereType<Map>().map(_map).toList() : [];

/// IN-002: selective A-B/A-C fixture, actual picker/decisions, naturally
/// rendered mutual contact/chat state before the active legacy probe, then
/// same-ID persistence after both participants' verified process deaths.
List<String> validateProductionIntroductionMutual(
  Map<String, Object?> proof, {
  bool offlineOutbox = false,
}) {
  final failures = <String>[];
  void require(bool value, String reason) {
    if (!value) failures.add(reason);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run required'];
  final peers = _map(proof['peers']);
  final names = _map(proof['names']);
  const roles = ['alice', 'bob', 'charlie'];
  require(
    proof['runtimeScenario'] == introductionMutualRuntime &&
        proof['emulatorTopology'] == true &&
        proof['prepareContactMesh'] == false &&
        roles.every(
          (r) =>
              peers[r] is String &&
              '${peers[r]}'.isNotEmpty &&
              names[r] is String &&
              '${names[r]}'.isNotEmpty,
        ) &&
        roles.map((r) => peers[r]).toSet().length == 3 &&
        roles.map((r) => names[r]).toSet().length == 3,
    'existing three-role runtime, distinct identities/names and selective contacts required',
  );
  final edges = _rows(proof['manualEdges']);
  require(
    edges.length == 4 &&
        edges.map((e) => '${e['actor']}->${e['peer']}').toSet().containsAll({
          'alice->bob',
          'bob->alice',
          'alice->charlie',
          'charlie->alice',
        }),
    'full-mesh preparation cannot prove an introduction between unconnected friends',
  );
  final nonces = _map(proof['nonces']);
  for (final role in roles) {
    final values = nonces[role];
    require(
      values is List &&
          values.length ==
              (offlineOutbox
                  ? (role == 'alice' ? 2 : 3)
                  : (role == 'alice' ? 1 : 2)) &&
          values.every((v) => v is String && v.isNotEmpty) &&
          values.toSet().length == values.length,
      '$role: exact initial and applicable fresh restart invocations required',
    );
    if (role != 'alice') {
      require(
        _map(_map(proof['ownedKills'])[role])['verifiedUidKill'] == true,
        '$role: actual owned process-death receipt required',
      );
    }
  }
  final trace = proof['trace'] is List ? proof['trace'] as List : [];
  bool before(String first, String second) =>
      trace.contains(first) &&
      trace.indexOf(second) > trace.indexOf(first) &&
      trace.lastIndexOf(first) == trace.indexOf(first) &&
      trace.lastIndexOf(second) == trace.indexOf(second);
  for (final role in roles) {
    require(
      before('probe-before-$role', 'introduce'),
      '$role: fixture baseline must precede introduction',
    );
    for (final witness in ['natural-pending-bob', 'natural-pending-charlie']) {
      require(
        before(witness, 'probe-pending-$role'),
        '$role: natural incoming UI must precede the generic inbox-draining probe',
      );
    }
    require(
      before('probe-pending-$role', 'accept-bob'),
      '$role: pending SQL witness must precede either user decision',
    );
    for (final witness in ['bob-ready', 'charlie-ready', 'received-charlie']) {
      require(
        before(witness, 'probe-mutual-$role'),
        '$role: mutual UI and actual chat delivery must precede the generic inbox-draining probe',
      );
    }
    for (final witness in ['replayed-bob', 'replayed-charlie']) {
      require(
        before(witness, 'probe-restarted-$role'),
        '$role: replay UI must precede the generic inbox-draining probe',
      );
    }
    for (final participant in ['bob', 'charlie']) {
      require(
        before('probe-mutual-$role', 'kill-$participant') &&
            before('kill-$participant', 'replayed-$participant'),
        '$participant: process cut must follow initial convergence and precede replay UI',
      );
    }
  }
  require(
    before('introduce', 'natural-pending-bob') &&
        before('introduce', 'natural-pending-charlie') &&
        before('accept-bob', 'accept-charlie') &&
        before('accept-charlie', 'bob-ready') &&
        before('accept-charlie', 'charlie-ready'),
    'separate actual picker/acceptance steps and their causal order required',
  );
  final text = introductionMutualText(run), pattern = RegExp.escape(text);
  final ui = _map(proof['ui']);
  final paths = <Object?>{};
  void flow(String label, String expected, Map<String, String> args) {
    final item = _map(ui[label]), receipt = _map(_map(ui[label])['receipt']);
    final flows = receipt['flows'], values = _map(item['values']);
    require(
      item['path'] is String &&
          '${item['path']}'.isNotEmpty &&
          paths.add(item['path']) &&
          item['flow'] == expected &&
          receipt['status'] == 'PASS' &&
          receipt['exit_status'] == 0 &&
          flows is List &&
          flows.length == 1 &&
          flows.single == expected &&
          args.entries.every((e) => values[e.key] == e.value),
      '$label: distinct exact successful UI receipt and bound fixture values required',
    );
  }

  flow('introduce', 'production_intro_send_one', {
    'RECIPIENT_PATTERN': RegExp.escape('${names['bob']}'),
    'FRIEND_PATTERN': RegExp.escape('${names['charlie']}'),
  });
  for (final role in ['bob', 'charlie']) {
    final other = role == 'bob' ? 'charlie' : 'bob';
    flow('natural-pending-$role', 'production_intro_review_pending', {
      'OTHER_PATTERN': RegExp.escape('${names[other]}'),
      'INTRODUCER_PATTERN': RegExp.escape('${names['alice']}'),
    });
    flow('accept-$role', 'production_intro_decide', {
      'OTHER_PATTERN': RegExp.escape('${names[other]}'),
      'DECISION_PATTERN': 'Accept',
      'EXPECTED_STATE_PATTERN': role == 'bob'
          ? RegExp.escape('Waiting for ${names['charlie']}')
          : 'No introductions yet',
    });
    if (offlineOutbox) {
      flow('$role-ready', 'production_direct_open', {
        'PEER_ID': '${peers[other]}',
      });
    } else {
      flow('$role-ready', 'production_intro_ready_chat', {
        'PEER_ID': '${peers[other]}',
        'OTHER_PATTERN': RegExp.escape('${names[other]}'),
      });
      flow('open-chat-$role', 'production_intro_open_chat', {
        'PEER_ID': '${peers[other]}',
        'OTHER_PATTERN': RegExp.escape('${names[other]}'),
      });
    }
    flow('reopen-$role', 'production_direct_open', {
      'PEER_ID': '${peers[other]}',
    });
    flow('replayed-$role', 'production_intro_read_chat', {
      'MESSAGE_PATTERN': pattern,
    });
  }
  flow('send-bob', 'production_direct_send', {
    'MESSAGE': text,
    'MESSAGE_PATTERN': pattern,
  });
  flow('received-charlie', 'production_intro_read_chat', {
    'MESSAGE_PATTERN': pattern,
  });
  final phases = _map(proof['phases']);
  final steps = <Object?>{};
  String? introId, messageId;
  DateTime? messageTime;
  final mutualBob = _map(_map(_map(phases['mutual'])['bob'])['snapshot']);
  final sent = [
    for (final conversation in _rows(mutualBob['chatMessages']))
      for (final message in _rows(conversation['messages']))
        if (message['text'] == text)
          {...message, 'contactPeerId': conversation['contactPeerId']},
  ];
  require(sent.length == 1, 'one actual original direct chat message required');
  if (sent.length == 1) {
    messageId = sent.single['id'] is String
        ? sent.single['id'] as String
        : null;
    messageTime = DateTime.tryParse('${sent.single['timestamp']}');
    require(
      messageId != null && messageId.isNotEmpty && messageTime != null,
      'original direct message identity and timestamp required',
    );
  }
  for (final phase in ['before', 'pending', 'mutual', 'restarted']) {
    final actors = _map(phases[phase]);
    for (final role in roles) {
      final envelope = _map(actors[role]),
          snapshot = _map(envelope['snapshot']);
      final values = nonces[role];
      final nonceIndex = !offlineOutbox
          ? (phase == 'restarted' && role != 'alice' ? 1 : 0)
          : phase == 'before'
          ? 0
          : role == 'alice'
          ? 1
          : phase == 'pending'
          ? 0
          : phase == 'restarted'
          ? 2
          : 1;
      require(
        envelope['status'] == 'complete' &&
            envelope['success'] == true &&
            envelope['observedRunId'] == run &&
            envelope['observedRole'] == role &&
            values is List &&
            values.length > nonceIndex &&
            envelope['observedNonce'] == values[nonceIndex] &&
            envelope['stepId'] is String &&
            '${envelope['stepId']}'.isNotEmpty &&
            steps.add(envelope['stepId']) &&
            envelope['probePreambleDrainsInbox'] == true &&
            _map(snapshot['identity'])['peerId'] == peers[role],
        '$phase/$role: current exact account/invocation/probe receipt required',
      );
      final connected = phase == 'mutual' || phase == 'restarted';
      final contacts = _rows(snapshot['contacts']);
      final expected = role == 'alice'
          ? {peers['bob'], peers['charlie']}
          : {
              peers['alice'],
              if (connected) peers[role == 'bob' ? 'charlie' : 'bob'],
            };
      require(
        contacts.length == expected.length &&
            contacts.map((c) => c['peerId']).toSet().containsAll(expected),
        '$phase/$role: exact selective or mutually introduced contact set required',
      );
      if (connected && role != 'alice') {
        final contact = contacts
            .where(
              (c) => c['peerId'] == peers[role == 'bob' ? 'charlie' : 'bob'],
            )
            .toList();
        require(
          contact.length == 1 &&
              contact.single['introducedByPeerId'] == peers['alice'],
          '$phase/$role: mutual contact must retain the actual introducer, not a synthetic full-mesh contact',
        );
      }
      final intros = _rows(snapshot['introductions']);
      require(
        intros.length == (phase == 'before' ? 0 : 1),
        '$phase/$role: one logical introduction exactly once required',
      );
      if (phase != 'before' && intros.length == 1) {
        final intro = intros.single;
        if (introId == null && intro['id'] is String) {
          introId = intro['id'] as String;
        }
        require(
          introId != null &&
              introId.isNotEmpty &&
              intro['id'] == introId &&
              intro['introducerId'] == peers['alice'] &&
              intro['recipientId'] == peers['bob'] &&
              intro['introducedId'] == peers['charlie'] &&
              intro['recipientStatus'] ==
                  (connected ? 'accepted' : 'pending') &&
              intro['introducedStatus'] ==
                  (connected ? 'accepted' : 'pending') &&
              intro['overallStatus'] ==
                  (connected ? 'mutual_accepted' : 'pending'),
          '$phase/$role: same introduction parties and actual decision state required',
        );
      }
      final matching = [
        for (final conversation in _rows(snapshot['chatMessages']))
          for (final row in _rows(conversation['messages']))
            if (row['text'] == text)
              {...row, 'contactPeerId': conversation['contactPeerId']},
      ];
      if (!connected || role == 'alice') {
        require(
          matching.isEmpty,
          '$phase/$role: direct chat must not preexist or leak to the introducer',
        );
      } else {
        require(
          matching.length == 1,
          '$phase/$role: received direct chat exactly once required',
        );
        if (matching.length != 1) continue;
        final row = matching.single,
            stamp = DateTime.tryParse('${matching.single['timestamp']}');
        require(
          row['id'] == messageId &&
              stamp != null &&
              messageTime != null &&
              stamp.isAtSameMomentAs(messageTime) &&
              row['isIncoming'] == (role == 'charlie') &&
              row['contactPeerId'] ==
                  peers[role == 'bob' ? 'charlie' : 'bob'] &&
              (role != 'bob' || row['status'] == 'delivered'),
          '$phase/$role: unchanged logical chat identity/time/direction and delivery required',
        );
      }
    }
  }
  return failures;
}
