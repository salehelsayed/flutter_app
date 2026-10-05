/// Pure oracle for the production notification tap measurement (Wave 4).
///
/// The original (benchmark_notification_tap_harness.dart) sets its own tap
/// time on fake services and asserts that the timing event exists for a cold
/// and a warm open. Production records two named intervals per real OS tap:
/// (a) NOTIFICATION_TAP_TO_MESSAGE_TIMING elapsedMs, from Dart receiving the
/// open to the first readable (stale-render) conversation frame; for the cold
/// case it excludes process start; and (b) an upper bound from the device
/// clock just before the Maestro tap flow to that event, which also includes
/// the shade swipe and Maestro start-up. Like the original, the timing is
/// required for the warm and cold opens; a same-peer tap finds the
/// conversation already open (CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE),
/// so production builds no screen and emits no timing for it.
const productionNotificationTapIntervals = {
  'a':
      'NOTIFICATION_TAP_TO_MESSAGE_TIMING elapsedMs: Dart open receipt to '
      'the first readable conversation frame (cold excludes process start)',
  'b':
      'device clock before the tap flow to the timing event (upper bound '
      'incl. shade swipe and Maestro start-up)',
};

/// Timing events in [after] that [before] did not already hold (matched by
/// timestamp and name; a cold open's new process has only new events).
List<Map<String, Object?>> productionNewTapTimings(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  String key(Map e) => '${e['ts']}|${e['event']}';
  List<Map> timings(Map<String, Object?> s) => [
    for (final e in (s['flowEvents'] as List? ?? const []))
      if (e is Map && e['event'] == 'NOTIFICATION_TAP_TO_MESSAGE_TIMING') e,
  ];
  final seen = {for (final e in timings(before)) key(e)};
  return [
    for (final e in timings(after))
      if (!seen.contains(key(e))) Map<String, Object?>.from(e),
  ];
}

/// Interval (b) in milliseconds, or null when it cannot be computed.
int? productionTapUpperBoundMs(Map<String, Object?> latency) {
  final clock = latency['deviceTapClockMs'];
  final timings = latency['timings'];
  if (clock is! int || timings is! List || timings.length != 1) return null;
  final ts = DateTime.tryParse('${(timings.first as Map)['ts']}');
  if (ts == null) return null;
  return ts.millisecondsSinceEpoch - clock;
}

List<String> validateProductionNotificationTapLatency(
  Map<String, Object?> proof,
) {
  final failures = <String>[];
  void require(bool ok, String message) {
    if (!ok) failures.add(message);
  }

  final cases = proof['cases'];
  if (cases is! List) return ['no notification tap cases'];
  final ids = {
    for (final c in cases)
      if (c is Map) c['id'],
  };
  require(
    ids.containsAll({'warm-other-chat', 'cold-start', 'same-peer'}),
    'warm, cold and same-peer taps measured',
  );
  for (final raw in cases) {
    if (raw is! Map) continue;
    final id = raw['id'];
    final latency = raw['tapLatency'];
    if (latency is! Map) {
      failures.add('$id: tap latency missing');
      continue;
    }
    final timings = latency['timings'];
    if (id == 'same-peer') {
      require(
        timings is List && timings.isEmpty,
        '$id: no new screen, so no tap-to-message timing',
      );
      continue;
    }
    final one =
        timings is List &&
        timings.length == 1 &&
        timings.first is Map &&
        (timings.first as Map)['details'] is Map;
    require(one, '$id: exactly one tap-to-message timing for this tap');
    if (!one) continue;
    final details = (timings.first as Map)['details'] as Map;
    require(
      details['elapsedMs'] is int && (details['elapsedMs'] as int) >= 0,
      '$id: interval (a) elapsedMs',
    );
    require(details['routeKind'] == 'conversation', '$id: conversation route');
    require(
      details['milestone'] == 'stale_render',
      '$id: first readable frame',
    );
    final upper = productionTapUpperBoundMs(Map<String, Object?>.from(latency));
    require(upper != null && upper >= 0, '$id: interval (b) upper bound');
  }
  return failures;
}
