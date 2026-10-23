const productionDirectActions = 'production.direct_catalog.actions_convergence';
const directActionsRuntime = 'production.routing_smoke';

Map<String, String> directActionsTexts(String run) => {
  'parent': 'Action parent $run',
  'reply': 'Action reply $run',
  'edited': 'Action edited reply $run',
  'deleted': 'Action deletion target $run',
};

/// Patterns target one rendered message's semantics, using the established
/// quote-reply recipe. They prove rendered quote/reaction/edit state, not raw
/// quotedMessageId or reaction-table fields absent from routing_snapshot.
Map<String, String> directActionsPatterns(String run) {
  final texts = directActionsTexts(
    run,
  ).map((key, value) => MapEntry(key, RegExp.escape(value)));
  return {
    'quote': '${texts['parent']}.*${texts['reply']}',
    'editedQuote': '${texts['parent']}.*${texts['edited']}.*\\(edited\\)',
    'deleted': texts['deleted']!,
  };
}

Map<String, Object?> _object(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : {};
List<Map<String, Object?>> _rows(Object? value) =>
    value is List ? value.whereType<Map>().map(_object).toList() : [];

/// DC-006 requires actual action receipts, both rendered projections, stable
/// logical identities, and fresh process-death replay. A delete-only fixture
/// or a matching replacement message cannot satisfy it.
List<String> validateProductionDirectActions(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool value, String reason) {
    if (!value) failures.add(reason);
  }

  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['exact run required'];
  final peers = _object(proof['peers']);
  require(
    proof['runtimeScenario'] == directActionsRuntime &&
        proof['emulatorPair'] == true &&
        peers['alice'] is String &&
        peers['bob'] is String &&
        '${peers['alice']}'.isNotEmpty &&
        '${peers['bob']}'.isNotEmpty &&
        peers['alice'] != peers['bob'],
    'existing routing runtime and two distinct disposable accounts required',
  );
  final texts = directActionsTexts(run);
  final patterns = directActionsPatterns(run);
  final phases = _object(proof['phases']);
  final original = _rows(
    _object(_object(phases['quoted'])['alice'])['messages'],
  );
  final ids = <String, String>{};
  final timestamps = <String, Object?>{};
  for (final key in ['parent', 'reply', 'deleted']) {
    final rows = original.where((row) => row['text'] == texts[key]).toList();
    require(rows.length == 1, '$key: one original logical row required');
    if (rows.length != 1) continue;
    final id = rows.single['id'];
    require(
      id is String && id.isNotEmpty && !ids.containsValue(id),
      '$key: distinct nonempty logical identity required',
    );
    if (id is String) ids[key] = id;
    timestamps[key] = rows.single['timestamp'];
    require(
      DateTime.tryParse('${timestamps[key]}') != null,
      '$key: original timestamp required',
    );
  }
  final ui = _object(proof['ui']);
  final requiredUi = <String, (String, Map<String, String>)>{
    'open-alice': ('production_direct_open', {'PEER_ID': '${peers['bob']}'}),
    'open-bob': ('production_direct_open', {'PEER_ID': '${peers['alice']}'}),
    'send-parent': (
      'production_direct_send',
      {
        'MESSAGE': texts['parent']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['parent']!),
      },
    ),
    'reply-bob': (
      'production_catalog_quote_reply',
      {
        'PARENT_PATTERN': RegExp.escape(texts['parent']!),
        'MESSAGE': texts['reply']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['reply']!),
      },
    ),
    'send-deletion-target': (
      'production_direct_send',
      {
        'MESSAGE': texts['deleted']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['deleted']!),
      },
    ),
    for (final action in ['add', 'remove'])
      'reaction-$action': (
        'production_direct_reaction_toggle',
        {'MESSAGE_ID': ids['parent'] ?? ''},
      ),
    'edit-bob': (
      'production_direct_edit',
      {
        'MESSAGE_ID': ids['reply'] ?? '',
        'EDITED_MESSAGE': texts['edited']!,
        'EDITED_PATTERN': RegExp.escape(texts['edited']!),
      },
    ),
    'delete-alice': (
      'production_direct_delete',
      {'MESSAGE_PATTERN': RegExp.escape(texts['deleted']!)},
    ),
    for (final role in ['alice', 'bob']) ...{
      'quote-$role': (
        'production_direct_assert_action',
        {
          'VISIBLE_PATTERN': patterns['quote']!,
          'ABSENT_PATTERN': 'NEVER_PRESENT_SENTINEL_$run',
        },
      ),
      'reaction-added-$role': (
        'production_direct_assert_reaction_present',
        {'MESSAGE_ID': ids['parent'] ?? ''},
      ),
      'reaction-removed-$role': (
        'production_direct_assert_reaction_absent',
        {'MESSAGE_ID': ids['parent'] ?? ''},
      ),
      'edited-$role': (
        'production_direct_assert_action',
        {
          'VISIBLE_PATTERN': patterns['editedQuote']!,
          'ABSENT_PATTERN': RegExp.escape(texts['reply']!),
        },
      ),
      for (final phase in ['deleted', 'restarted']) ...{
        '$phase-$role': (
          'production_direct_assert_action',
          {
            'VISIBLE_PATTERN': patterns['editedQuote']!,
            'ABSENT_PATTERN': patterns['deleted']!,
          },
        ),
        '$phase-placeholder-$role': (
          'production_direct_assert_action',
          {
            'VISIBLE_PATTERN': 'This message was deleted',
            'ABSENT_PATTERN': patterns['deleted']!,
          },
        ),
        '$phase-reaction-removed-$role': (
          'production_direct_assert_reaction_absent',
          {'MESSAGE_ID': ids['parent'] ?? ''},
        ),
      },
      'reopen-$role': (
        'production_direct_open',
        {'PEER_ID': '${peers[role == 'alice' ? 'bob' : 'alice']}'},
      ),
    },
  };
  final paths = <Object?>{};
  for (final entry in requiredUi.entries) {
    final item = _object(ui[entry.key]);
    final receipt = _object(item['receipt']);
    final flows = receipt['flows'];
    final values = _object(item['values']);
    require(
      item['path'] is String &&
          '${item['path']}'.isNotEmpty &&
          paths.add(item['path']) &&
          item['flow'] == entry.value.$1 &&
          receipt['status'] == 'PASS' &&
          receipt['exit_status'] == 0 &&
          flows is List &&
          flows.length == 1 &&
          flows.single == entry.value.$1 &&
          entry.value.$2.entries.every((e) => values[e.key] == e.value),
      '${entry.key}: distinct exact successful UI receipt and bound values required',
    );
  }
  final nonces = _object(proof['nonces']);
  for (final role in ['alice', 'bob']) {
    final pair = nonces[role];
    require(
      pair is List &&
          pair.length == 2 &&
          pair.every((v) => v is String && v.isNotEmpty) &&
          pair[0] != pair[1],
      '$role: fresh initial and replay invocations required',
    );
    require(
      _object(_object(proof['ownedKills'])[role])['verifiedUidKill'] == true,
      '$role: actual owned process-death receipt required',
    );
    for (final phase in ['quoted', 'edited', 'deleted', 'restarted']) {
      final snapshot = _object(_object(phases[phase])[role]);
      final rows = _rows(snapshot['messages']);
      final afterDeletion = phase == 'deleted' || phase == 'restarted';
      final afterEdit = phase != 'quoted';
      require(
        snapshot['observedRunId'] == run &&
            snapshot['observedRole'] == role &&
            pair is List &&
            pair.length == 2 &&
            snapshot['observedNonce'] == pair[phase == 'restarted' ? 1 : 0] &&
            rows.length == 3,
        '$phase/$role: exact current-run transcript and invocation required',
      );
      for (final key in ['parent', 'reply', if (!afterDeletion) 'deleted']) {
        final matching = rows.where((r) => r['id'] == ids[key]).toList();
        require(
          matching.length == 1,
          '$phase/$role/$key: same identity exactly once required',
        );
        if (matching.length != 1) continue;
        final row = matching.single;
        final authoredByBob = key == 'reply';
        require(
          row['text'] == texts[key == 'reply' && afterEdit ? 'edited' : key] &&
              row['timestamp'] == timestamps[key] &&
              row['lane'] == 'direct' &&
              row['conversationId'] ==
                  peers[role == 'alice' ? 'bob' : 'alice'] &&
              row['incoming'] ==
                  (authoredByBob ? role == 'alice' : role == 'bob') &&
              row['deletedAt'] == null,
          '$phase/$role/$key: edited text or preserved row authority diverged',
        );
      }
      if (afterDeletion) {
        final tombstones = _rows(snapshot['tombstones']);
        final deletedRows = rows
            .where((r) => r['id'] == ids['deleted'])
            .toList();
        require(
          tombstones.length == 1 &&
              tombstones.single['id'] == ids['deleted'] &&
              tombstones.single['contactPeerId'] ==
                  peers[role == 'alice' ? 'bob' : 'alice'] &&
              DateTime.tryParse('${tombstones.single['deletedAt']}') != null &&
              deletedRows.length == 1 &&
              deletedRows.single['deletedAt'] ==
                  tombstones.single['deletedAt'] &&
              deletedRows.single['timestamp'] == timestamps['deleted'] &&
              deletedRows.single['lane'] == 'direct' &&
              deletedRows.single['incoming'] == (role == 'bob') &&
              deletedRows.single['conversationId'] ==
                  peers[role == 'alice' ? 'bob' : 'alice'],
          '$phase/$role: same deleted logical row needs a durable tombstone',
        );
      }
    }
  }
  return failures;
}
