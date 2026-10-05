/// Pure oracle for the production message latency measurement (Wave 4).
///
/// The originals (1:1 send A, routing paths R, group publish GP) report
/// timings and have no thresholds; R-Sim-3 must observe its send event and
/// every GP send must succeed. The production measurement keeps those and
/// makes the rest exact: every planned send ran once and produced exactly one
/// production timing event, and each case's setup step really happened.
const productionMessageLatencyInterval =
    'production send use case: CHAT_MSG_SEND_TIMING / GROUP_SEND_MSG_TIMING '
    'elapsedMs (call to outcome) per send, sender vantage';

/// Cases and planned send counts, in run order.
const productionMessageLatencyPlan = <String, int>{
  'A-Sim-1': 5,
  'A-Sim-2': 11, // one warmup, then ten sequential sends
  'A-Sim-3': 1,
  'R-Sim-1': 6, // one cold, five warm
  'R-Sim-2d': 1,
  'R-Sim-3': 1,
  'R-Sim-4': 1,
  'R-Sim-5': 1,
  'GP': 5,
  'R-Sim-7': 11, // cold, five warm, offline, reconnect, three warm
};

/// Original cases this measurement does not reproduce, with the reason.
const productionMessageLatencyNotReproduced = <String, String>{
  'R-Sim-6':
      'the original never makes the inbox fail either; same setup as R-Sim-4',
  'R-Sim-8':
      'compares against a baseline file from an earlier run on the same host; '
      'report-only, no production baseline exists yet',
};

List<String> validateProductionMessageLatency(Map<String, Object?> proof) {
  final failures = <String>[];
  void require(bool ok, String message) {
    if (!ok) failures.add(message);
  }

  require(
    proof['interval'] == productionMessageLatencyInterval,
    'latency interval named',
  );
  final notReproduced = proof['notReproduced'];
  require(
    notReproduced is Map &&
        notReproduced.keys.toSet().containsAll(
          productionMessageLatencyNotReproduced.keys,
        ),
    'unreproduced originals recorded with a reason',
  );
  final cases = proof['cases'];
  if (cases is! Map) return [...failures, 'no latency cases'];
  for (final entry in productionMessageLatencyPlan.entries) {
    final name = entry.key;
    final record = cases[name];
    if (record is! Map) {
      failures.add('$name: case missing');
      continue;
    }
    final sends = record['sends'];
    if (sends is! List || sends.length != entry.value) {
      failures.add('$name: ${entry.value} planned sends attempted');
      continue;
    }
    final keys = <Object?>{};
    final event = name == 'GP'
        ? 'GROUP_SEND_MSG_TIMING'
        : 'CHAT_MSG_SEND_TIMING';
    for (final raw in sends) {
      if (raw is! Map) {
        failures.add('$name: malformed send');
        continue;
      }
      keys.add(raw['key']);
      final timings = raw['timings'];
      final ok =
          timings is List &&
          timings.length == 1 &&
          timings.first is Map &&
          (timings.first as Map)['event'] == event &&
          ((timings.first as Map)['details'] is Map) &&
          ((timings.first as Map)['details'] as Map)['elapsedMs'] is int &&
          (((timings.first as Map)['details'] as Map)['elapsedMs'] as int) >=
              0 &&
          ((timings.first as Map)['details'] as Map)['outcome'] is String;
      require(ok, '$name ${raw['key']}: exactly one $event with elapsedMs');
      if (name == 'GP') {
        require(
          raw['result'] == 'success' || raw['result'] == 'successNoPeers',
          '$name ${raw['key']}: group send succeeded',
        );
      }
    }
    require(keys.length == sends.length, '$name: each send once');
  }
  final r3 = cases['R-Sim-3'];
  require(
    r3 is Map &&
        r3['unregister'] is Map &&
        (r3['unregister'] as Map)['ok'] == true &&
        r3['register'] is Map &&
        (r3['register'] as Map)['ok'] == true,
    'R-Sim-3: receiver left rendezvous and was restored',
  );
  final r7 = cases['R-Sim-7'];
  require(
    r7 is Map &&
        r7['stop'] is Map &&
        (r7['stop'] as Map)['result'] == true &&
        r7['start'] is Map &&
        (r7['start'] as Map)['result'] == true,
    'R-Sim-7: receiver node really stopped and restarted',
  );
  return failures;
}

/// p50/p95/n of the timing events of [sends], optionally filtered.
Map<String, Object?> productionLatencyStats(
  List<Map<String, Object?>> sends, {
  bool Function(Map<String, Object?> details)? where,
}) {
  final values = <int>[];
  for (final s in sends) {
    final timings = s['timings'];
    if (timings is! List || timings.isEmpty) continue;
    final details = (timings.first as Map)['details'];
    if (details is! Map) continue;
    final d = Map<String, Object?>.from(details);
    if (where != null && !where(d)) continue;
    final ms = d['elapsedMs'];
    if (ms is int) values.add(ms);
  }
  values.sort();
  int? pct(double p) => values.isEmpty
      ? null
      : values[((values.length - 1) * p).round().clamp(0, values.length - 1)];
  return {'n': values.length, 'p50Ms': pct(0.5), 'p95Ms': pct(0.95)};
}
