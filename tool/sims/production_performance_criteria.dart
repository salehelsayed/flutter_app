import 'dart:convert';

/// Original B/M/BR benchmark assertions on the production-composed node.
/// totalMs stays the production node's interval, never OS-to-frame latency.
List<String> validateProductionPerformance(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String reason) {
    if (!ok) failures.add(reason);
  }

  Map object(Object? v) => v is Map ? v : const {};
  List<Map> maps(Object? v) =>
      v is List && v.every((e) => e is Map) ? v.cast<Map>() : const [];
  final run = proof['runId'];
  int integer(Object? v, int fallback) => v is int ? v : fallback;
  bool nonempty(Object? v) => v is String && v.isNotEmpty;
  List<Map> events(Map s) => maps(s['events']);
  Map details(Map e) => object(e['details']);
  List<Map> metric(List<Map> es, String name, [String? phase]) => es
      .where(
        (e) =>
            e['event'] == name &&
            (phase == null || details(e)['phase'] == phase),
      )
      .toList();
  void snapshot(
    Map s,
    String label, {
    String lifecycle = 'resumed',
    bool ready = true,
  }) {
    require(
      nonempty(run) &&
          s['runId'] == run &&
          s['role'] == 'alice' &&
          nonempty(s['nonce']),
      '$label invocation',
    );
    require(
      s['processId'] is int && (s['processId'] as int) > 0,
      '$label process',
    );
    require(
      s['captureStartedBeforeRuntime'] == true &&
          s['timingScope'] ==
              'production node readiness and actual OS lifecycle',
      '$label timing scope',
    );
    require(
      s['profileId'] == 'android.e2e.performance_relay' &&
          s['localDiscoveryDisabled'] == true,
      '$label attested relay-only topology',
    );
    require(s['lifecycle'] == lifecycle, '$label lifecycle');
    if (ready) {
      require(
        s['nodeStarted'] == true &&
            s['sendReady'] == true &&
            s['inboxReady'] == true &&
            s['badge'] == 'onlineDotted',
        '$label truthful readiness',
      );
    }
    final es = events(s);
    require(
      s['events'] is List && (s['events'] as List).every((e) => e is Map),
      '$label events',
    );
    var previous = -1;
    for (var i = 0; i < es.length; i++) {
      final t = es[i]['observedMicros'];
      require(
        es[i]['sequence'] == i + 1 && t is int && t >= previous,
        '$label monotonic event provenance',
      );
      if (t is int) previous = t;
    }
    require(
      s['observedMicros'] is int && (s['observedMicros'] as int) >= previous,
      '$label observation clock',
    );
  }

  Map? phaseMetric(List<Map> es, String event, String phase, String label) {
    final values = metric(es, event, phase);
    require(values.isNotEmpty, '$label $event/$phase missing');
    if (values.isEmpty) return null;
    final d = details(values.first);
    require(
      d['totalMs'] is int &&
          (d['totalMs'] as int) >= 0 &&
          nonempty(d['source']),
      '$label real nonnegative metric',
    );
    return d;
  }

  final cold = maps(proof['cold']);
  require(cold.length == 6, 'one cold plus five distribution samples required');
  require(
    cold.map((s) => s['nonce']).toSet().length == 6,
    'fresh cold invocation identities required',
  );
  require(
    cold.map((s) => s['processId']).toSet().length == 6,
    'cold samples must use fresh processes',
  );
  require(
    cold.every((s) => nonempty(s['nodePeerId'])) &&
        cold.map((s) => s['nodePeerId']).toSet().length == 6,
    'original independent cold identities required',
  );
  for (var i = 0; i < cold.length; i++) {
    final s = cold[i];
    snapshot(s, 'cold-$i');
    final es = events(s);
    final starts = metric(es, 'P2P_SERVICE_START_NODE_CORE_BEGIN');
    final sends = metric(es, 'TIME_TO_SENDABLE_BADGE', 'cold_start');
    require(
      starts.isNotEmpty &&
          sends.isNotEmpty &&
          integer(starts.first['sequence'], 999999) <
              integer(sends.first['sequence'], -1),
      'cold-$i observer precedes node start',
    );
    final send = phaseMetric(
      es,
      'TIME_TO_SENDABLE_BADGE',
      'cold_start',
      'cold-$i',
    );
    final relay = phaseMetric(
      es,
      'TIME_TO_RELAY_READY_BADGE',
      'cold_start',
      'cold-$i',
    );
    if (send != null && relay != null) {
      require(
        send['totalMs'] is int &&
            relay['totalMs'] is int &&
            (relay['totalMs'] as int) - (send['totalMs'] as int) <= 5000,
        'cold-$i original relay-ready bound',
      );
    }
    if (i == 0) {
      require(
        send?['totalMs'] is int && (send!['totalMs'] as int) < 6000,
        'cold sendable <6000ms',
      );
      for (final e in metric(es, 'TIME_TO_ONLINE_BADGE')) {
        final ms = details(e)['totalMs'];
        require(ms is int && ms >= 0 && ms < 6000, 'original online <6000ms');
      }
      for (final e in metric(es, 'node:startup_timing')) {
        final ms = details(e)['totalToDiscoverableMs'];
        if (ms != null) {
          require(
            ms is num && ms >= 0 && ms < 5000,
            'original discoverable <5000ms',
          );
        }
      }
    }
  }
  for (final name in [
    'hot-core',
    'hot-node',
    'healthy',
    'degraded',
    'extended',
    'recovery',
    // C-Sim-2: three consecutive foreground recoveries, each judged like
    // M-Sim-2's single recovery (loss <=15 s, sendable and relay-ready <=30 s).
    'repeated-recovery-1',
    'repeated-recovery-2',
    'repeated-recovery-3',
  ]) {
    final recovery =
        name == 'recovery' || name.startsWith('repeated-recovery-');
    final window = object(proof[name]);
    final before = object(window['before']);
    final after = object(window['after']);
    snapshot(before, '$name before');
    snapshot(after, '$name after', ready: name != 'hot-core');
    require(
      cold.isNotEmpty &&
          before['nonce'] == cold.last['nonce'] &&
          before['processId'] == cold.last['processId'] &&
          before['nodePeerId'] == cold.last['nodePeerId'],
      '$name final cold runtime retained',
    );
    require(
      before['nonce'] == after['nonce'] &&
          before['processId'] == after['processId'] &&
          before['nodePeerId'] == after['nodePeerId'],
      '$name same runtime',
    );
    final start = events(before).length;
    require(
      events(after).length >= start &&
          jsonEncode(events(after).take(start).toList()) ==
              jsonEncode(events(before)) &&
          integer(after['observedMicros'], -1) >=
              integer(before['observedMicros'], 0),
      '$name immutable capture prefix and observation clock',
    );
    final es = events(
      after,
    ).where((e) => integer(e['sequence'], 0) > start).toList();
    require(events(after).length >= start, '$name capture cannot regress');
    if (name.startsWith('hot-')) {
      require(window['started'] == true, '$name real start returned true');
      require(
        metric(es, 'P2P_SERVICE_START_NODE_CORE_BEGIN').isNotEmpty,
        '$name actual core invocation',
      );
      if (name == 'hot-core') {
        require(
          after['nodeStarted'] == true &&
              after['sendReady'] is bool &&
              after['inboxReady'] is bool,
          'hot-core truthful return state',
        );
        require(
          metric(es, 'P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING').isNotEmpty,
          'hot-core actual existing-node resynchronization',
        );
        // Original B-Sim-3 captures core return and optional online timing.
        // Its API intentionally omits warm tasks; M owns the readiness waits.
        continue;
      }
      phaseMetric(es, 'TIME_TO_SENDABLE_BADGE', 'hot_restart', name);
      for (final wait in ['sendableWaitMs', 'relayWaitMs']) {
        require(
          window[wait] is int &&
              (window[wait] as int) >= 0 &&
              (window[wait] as int) <= 10000,
          '$name original hot wait bound',
        );
      }
      continue;
    }
    if (!recovery) {
      final background = object(window['background']);
      snapshot(background, '$name background', lifecycle: 'paused');
      require(
        background['nonce'] == before['nonce'] &&
            background['processId'] == before['processId'] &&
            background['nodePeerId'] == before['nodePeerId'],
        '$name same background runtime',
      );
      final pauses = es
          .where(
            (e) =>
                e['event'] == 'APPLICATION_LIFECYCLE' &&
                details(e)['state'] == 'paused',
          )
          .toList();
      final resumes = es
          .where(
            (e) =>
                e['event'] == 'APPLICATION_LIFECYCLE' &&
                details(e)['state'] == 'resumed',
          )
          .toList();
      require(
        pauses.isNotEmpty &&
            resumes.isNotEmpty &&
            integer(pauses.first['sequence'], 999999) <
                integer(resumes.last['sequence'], -1),
        '$name actual paused then resumed',
      );
      if (name == 'extended' && pauses.isNotEmpty && resumes.isNotEmpty) {
        require(
          integer(resumes.last['observedMicros'], 0) -
                  integer(pauses.first['observedMicros'], 0) >=
              30000000,
          'extended 30-second background retained',
        );
      }
    }
    if (name == 'healthy') {
      phaseMetric(
        es,
        'TIME_TO_ONLINE_BADGE',
        'background_resume_already_online',
        name,
      );
    } else {
      final phases = recovery
          ? ['recovery']
          : ['background_resume', 'recovery'];
      final matching = phases
          .where((p) => metric(es, 'TIME_TO_SENDABLE_BADGE', p).isNotEmpty)
          .toList();
      if (name == 'extended' && matching.isEmpty) {
        phaseMetric(
          es,
          'TIME_TO_ONLINE_BADGE',
          'background_resume_already_online',
          name,
        );
      } else {
        require(matching.isNotEmpty, '$name sendable recovery metric');
        if (matching.isNotEmpty) {
          phaseMetric(es, 'TIME_TO_SENDABLE_BADGE', matching.first, name);
          if (name != 'extended') {
            phaseMetric(es, 'TIME_TO_RELAY_READY_BADGE', matching.first, name);
          }
        }
      }
      if (name == 'degraded' || recovery) {
        final degraded = object(window['degraded']);
        snapshot(
          degraded,
          '$name degraded',
          lifecycle: name == 'degraded' ? 'paused' : 'resumed',
          ready: false,
        );
        // C-Sim-2 windows may prove the loss from the production state
        // stream (a relay can reconnect within one host poll).
        final lossSeen =
            degraded['badge'] != 'onlineDotted' ||
            (name.startsWith('repeated-recovery-') &&
                degraded['relayLossObserved'] == true);
        require(
          lossSeen &&
              degraded['nonce'] == before['nonce'] &&
              degraded['processId'] == before['processId'] &&
              degraded['nodePeerId'] == before['nodePeerId'],
          '$name observed actual relay loss',
        );
        require(
          window['disconnectCount'] is int &&
              (window['disconnectCount'] as int) > 0,
          '$name connected relay fault',
        );
        if (name == 'degraded') {
          // An outage closes either by an app-driven reconnect (`recovered`)
          // or by the node healing the relay itself (`self_healed`).
          require(
            metric(es, 'RELAY_OUTAGE_TIMING', 'recovered').isNotEmpty ||
                metric(es, 'RELAY_OUTAGE_TIMING', 'self_healed').isNotEmpty,
            'degraded recovered outage timing',
          );
        }
        require(
          window['degradeWaitMs'] is int &&
              (window['degradeWaitMs'] as int) >= 0 &&
              (window['degradeWaitMs'] as int) <= 15000,
          '$name original degrade bound',
        );
      }
    }
    for (final wait in ['sendableWaitMs', 'relayWaitMs']) {
      require(
        window[wait] is int &&
            (window[wait] as int) >= 0 &&
            (window[wait] as int) <= 30000,
        '$name original $wait bound',
      );
    }
  }
  return failures;
}
