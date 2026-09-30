/// Application-boundary assertions kept alongside the original isolated
/// encryption, policy, expiry and download proofs. No remote-revocation claim.
List<String> validateProductionPrivateMedia(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool condition, String reason) {
    if (!condition) failures.add(reason);
  }

  Map object(Object? value) => value is Map ? value : const {};
  List<Map> maps(Object? value) => value is List && value.every((v) => v is Map)
      ? value.cast<Map>()
      : const [];
  final run = proof['runId'];
  final peers = object(proof['peers']);
  require(run is String && run.isNotEmpty, 'run identity required');
  require(
    peers['alice'] is String &&
        peers['bob'] is String &&
        peers['alice'] != peers['bob'],
    'distinct peers required',
  );
  final names = [
    'projection',
    'deleted',
    'incomingViewing',
    'incomingConsumed',
    'incomingColdConsumed',
    'incomingRefused',
    'available',
    'viewing',
    'consumed',
    'coldConsumed',
    'refused',
  ];
  Map snapshot(String name) => object(proof[name]);
  Map row(String stage, String name) =>
      maps(snapshot(stage)['rows'])
          .where((r) => r['id'] == 'private-$run-$name' && r['name'] == name)
          .singleOrNull ??
      const {};
  Map sql(String stage, String name) =>
      maps(row(stage, name)['sql']).singleOrNull ?? const {};
  Map projection(String stage) => object(snapshot(stage)['projection']);
  Map visual(String stage, String name) =>
      maps(
        projection(stage)['rows'],
      ).where((r) => r['id'] == 'private-$run-$name').singleOrNull ??
      const {};
  for (final stage in names) {
    final s = snapshot(stage);
    final role =
        stage == 'projection' ||
            stage == 'deleted' ||
            stage.startsWith('incoming')
        ? 'bob'
        : 'alice';
    final expectedNames = role == 'bob'
        ? ['outgoing', 'protected_thumbnail', 'incoming', 'terminal']
        : ['sender_pending'];
    require(
      s['runId'] == run &&
          s['role'] == role &&
          s['peerId'] == peers[role == 'alice' ? 'bob' : 'alice'],
      '$stage identity binding',
    );
    require(s['lifecycle'] == 'resumed', '$stage real resumed lifecycle');
    require(
      maps(s['rows']).length == expectedNames.length,
      '$stage exact fixture row count',
    );
    for (final name in expectedNames) {
      final r = row(stage, name);
      final q = sql(stage, name);
      require(
        maps(r['sql']).length == 1 &&
            q['id'] == r['id'] &&
            q['is_incoming'] ==
                (name == 'incoming' || name == 'terminal' ? 1 : 0) &&
            q['private_media_policy_version'] == 1 &&
            q['private_media_mode'] ==
                ({'outgoing', 'protected_thumbnail'}.contains(name)
                    ? 'protected'
                    : 'view_once'),
        '$stage/$name exact SQL authority',
      );
      require(q['deleted_at'] == null, '$stage/$name unexpected deletion');
    }
    require(
      projection(stage)['viewers'] ==
          (stage == 'viewing' || stage == 'incomingViewing' ? 1 : 0),
      '$stage viewer count',
    );
    if (stage != 'viewing' && stage != 'incomingViewing') {
      require(
        projection(stage)['conversations'] == 1,
        '$stage actual conversation',
      );
    }
  }
  for (final name in [
    'outgoing',
    'protected_thumbnail',
    'incoming',
    'terminal',
  ]) {
    final v = visual('projection', name);
    for (final field in [
      'rows',
      'letterCards',
      'slots',
      'decoratedBodies',
      'slotsInsideBodies',
    ]) {
      require(v[field] == 1, '$name exact $field');
    }
    final sizes = maps(v['slotSizes']);
    require(
      sizes.length == 1 &&
          (sizes.single['width'] as num? ?? 0) > 0 &&
          (sizes.single['height'] as num? ?? 0) > 0,
      '$name nonzero slot',
    );
    require(
      v['imageWidgets'] == (name == 'protected_thumbnail' ? 2 : 0) &&
          v['decorationImages'] == 0,
      '$name placeholder privacy',
    );
    final actions = maps(v['actions']);
    final key = name == 'protected_thumbnail'
        ? 'private-media-thumbnail-tile'
        : name == 'outgoing' || name == 'incoming'
        ? 'private-media-card-visual'
        : 'private-terminal-view-once-consumed-summary';
    final action = actions.where((a) => a['key'] == key).singleOrNull;
    require(
      action != null &&
          (action['width'] as num? ?? 0) > 0 &&
          (action['height'] as num? ?? 0) > 0,
      '$name exact visible action',
    );
    if (name == 'outgoing') {
      require(
        action?['height'] == 88 &&
            !actions.any((a) => a['key'] == 'private-media-open'),
        'missing-byte outgoing card has no unavailable open action',
      );
    }
    if (name == 'incoming') {
      require(
        action?['height'] == 150 &&
            !actions.any((a) => a['key'] == 'private-media-open'),
        'incoming 150px tile without retired button',
      );
    }
    if (name == 'terminal') {
      require(
        !actions.any((a) => a['key'] == 'private-action-deleteForMe'),
        'terminal has no inline delete',
      );
    }
    require(
      sql('projection', name)['hidden_at'] == null,
      '$name initially visible SQL row',
    );
    require(
      sql('projection', name)['private_media_state'] ==
          (name == 'terminal' ? 'consumed' : 'available'),
      '$name initial state',
    );
    require(
      visual('deleted', name)['rows'] == (name == 'terminal' ? 0 : 1),
      '$name deletion projection',
    );
    require(
      (sql('deleted', name)['hidden_at'] != null) == (name == 'terminal'),
      '$name exact delete-for-me target',
    );
  }
  for (final entry in {
    'protectedWindow': ('bob', true),
    'senderBeforeWindow': ('alice', false),
    'senderViewingWindow': ('alice', true),
    'senderAfterWindow': ('alice', false),
  }.entries) {
    final window = object(proof[entry.key]);
    require(
      window['package'] == 'com.mknoon.sims.connectivity' &&
          window['role'] == entry.value.$1 &&
          window['ownedWindowCount'] == 1 &&
          window['secure'] == entry.value.$2 &&
          window['visible'] == true,
      '${entry.key} exact owned visible window protection',
    );
  }
  require(
    row('projection', 'outgoing')['fileExists'] == false,
    'outgoing placeholder requires explicit missing-byte fallback',
  );
  require(
    row('projection', 'protected_thumbnail')['fileExists'] == true &&
        row('projection', 'protected_thumbnail')['fileSha256'] ==
            row('projection', 'protected_thumbnail')['fixtureSha256'],
    'protected thumbnail requires exact fixture bytes',
  );
  for (final recipient in [false, true]) {
    final name = recipient ? 'incoming' : 'sender_pending';
    final initial = recipient ? 'deleted' : 'available';
    final viewing = recipient ? 'incomingViewing' : 'viewing';
    final consumed = recipient ? 'incomingConsumed' : 'consumed';
    final cold = recipient ? 'incomingColdConsumed' : 'coldConsumed';
    final refused = recipient ? 'incomingRefused' : 'refused';
    final before = row(initial, name);
    final attachment = maps(before['attachments']).singleOrNull;
    require(
      attachment != null &&
          attachment['id'] == 'private-$run-$name-attachment' &&
          attachment['message_id'] == 'private-$run-$name' &&
          attachment['owner_lane'] == 'direct' &&
          attachment['download_status'] ==
              (recipient ? 'done' : 'upload_pending') &&
          attachment['exactOwnedPath'] == true &&
          before['storageOwner'] ==
              (recipient ? 'canonical_incoming' : 'pending_upload') &&
          (attachment['size'] as num? ?? 0) > 0 &&
          before['repositoryAttachmentCount'] == 1 &&
          before['fileExists'] == true &&
          before['fileSha256'] is String &&
          before['fileSha256'] == before['fixtureSha256'],
      '$name exact canonical attachment and bytes',
    );
    for (final stage in [initial, viewing, consumed, cold, refused]) {
      final r = row(stage, name);
      require(
        sql(stage, name)['private_media_state'] ==
            (stage == initial
                ? 'available'
                : stage == viewing
                ? 'viewing'
                : 'consumed'),
        '$stage committed SQL state',
      );
      require(
        sql(stage, name)['hidden_at'] == null,
        '$stage private row remains visible',
      );
      if ([consumed, cold, refused].contains(stage)) {
        require(
          r['attachments'] is List &&
              (r['attachments'] as List).isEmpty &&
              r['repositoryAttachmentCount'] == 0 &&
              r['fileExists'] == false,
          '$stage attachment and owned file removed',
        );
      }
    }
    final sequence = <String>['available'];
    var lastTime = -1;
    final allowedNames = recipient
        ? ['outgoing', 'protected_thumbnail', 'incoming', 'terminal']
        : ['sender_pending'];
    for (final event in maps(snapshot(consumed)['committed'])) {
      require(
        allowedNames.any((n) => event['messageId'] == 'private-$run-$n') &&
            event['source'] == 'production-repository-committed-change' &&
            event['observedAtMicros'] is int &&
            (event['observedAtMicros'] as int) >= lastTime,
        '$name committed mutation provenance and order',
      );
      if (event['observedAtMicros'] is int) {
        lastTime = event['observedAtMicros'] as int;
      }
      if (event['messageId'] != 'private-$run-$name') continue;
      final state = event['state'];
      if (state is String && sequence.last != state) sequence.add(state);
    }
    require(
      sequence.join(',') == 'available,opening,viewing,consumed',
      '$name exact committed SQL lifecycle sequence',
    );
    final oldNonce = proof[recipient ? 'recipientBeforeNonce' : 'beforeNonce'];
    final newNonce = proof[recipient ? 'recipientAfterNonce' : 'afterNonce'];
    require(
      oldNonce is String &&
          oldNonce.isNotEmpty &&
          newNonce is String &&
          newNonce.isNotEmpty &&
          oldNonce != newNonce,
      '$name cold restart requires fresh invocation',
    );
  }
  require(
    proof['claims'] is Map &&
        object(proof['claims'])['remoteRevocation'] == false &&
        object(proof['claims'])['accountWideConsumption'] == false,
    'local-only claim boundary',
  );
  return failures;
}

/// Read-only native evidence, scoped to the disposable application's own base
/// window. Another window's SECURE flag cannot satisfy this observation.
Map<String, Object?> observeProductionPrivateWindow(String dump) {
  const package = 'com.mknoon.sims.connectivity';
  final headers = RegExp(
    r'^  Window #[^\n]*:',
    multiLine: true,
  ).allMatches(dump).toList();
  final owned = <String>[];
  for (var i = 0; i < headers.length; i++) {
    final match = headers[i];
    final title = dump.substring(match.start, match.end);
    if (!title.contains(' $package/com.mknoon.app.MainActivity}')) continue;
    owned.add(
      dump.substring(
        match.start,
        i + 1 < headers.length ? headers[i + 1].start : dump.length,
      ),
    );
  }
  final block = owned.length == 1 ? owned.single : '';
  final flags =
      RegExp(
        r'^\s+fl=([^\n]+)',
        multiLine: true,
      ).firstMatch(block)?.group(1)?.split(RegExp(r'\s+')) ??
      [];
  return {
    'package': package,
    'ownedWindowCount': owned.length,
    'secure': flags.contains('SECURE'),
    'visible':
        block.contains('mHasSurface=true') && block.contains('isOnScreen=true'),
  };
}
