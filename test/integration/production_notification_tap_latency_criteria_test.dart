import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/production_notification_tap_latency_criteria.dart';

Map<String, Object?> _timing(String ts, {int elapsed = 180}) => {
  'event': 'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
  'ts': ts,
  'details': {
    'elapsedMs': elapsed,
    'routeKind': 'conversation',
    'milestone': 'stale_render',
  },
};

Map<String, Object?> _case(String id, int clock) => {
  'id': id,
  'tapLatency': <String, Object?>{
    'deviceTapClockMs': clock,
    'timings': [
      _timing(
        DateTime.fromMillisecondsSinceEpoch(
          clock + 2500,
          isUtc: true,
        ).toIso8601String(),
      ),
    ],
  },
};

Map<String, Object?> _fixture() => {
  'cases': [
    _case('warm-other-chat', 1000000),
    _case('cold-start', 2000000),
    _case('same-peer', 3000000),
  ],
};

Map _latency(Map<String, Object?> p, int i) =>
    ((p['cases']! as List)[i] as Map)['tapLatency'] as Map;

void main() {
  test('accepts one timing per real tap with both intervals', () {
    expect(validateProductionNotificationTapLatency(_fixture()), isEmpty);
    expect(
      productionTapUpperBoundMs(
        Map<String, Object?>.from(_latency(_fixture(), 0)),
      ),
      2500,
    );
  });

  test('new timings exclude events the before snapshot already held', () {
    final old = _timing('2026-10-05T10:00:00.000Z');
    final fresh = _timing('2026-10-05T10:00:05.000Z');
    expect(
      productionNewTapTimings(
        {
          'flowEvents': [old],
        },
        {
          'flowEvents': [old, fresh],
        },
      ),
      [fresh],
    );
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'a case missing': (p) => (p['cases']! as List).removeAt(1),
    'latency missing': (p) =>
        ((p['cases']! as List)[0] as Map).remove('tapLatency'),
    'no timing for a tap': (p) => _latency(p, 1)['timings'] = <Object?>[],
    'two timings for a tap': (p) {
      final timings = _latency(p, 2)['timings'] as List;
      timings.add(timings.first);
    },
    'negative elapsed': (p) =>
        ((_latency(p, 0)['timings'] as List).first['details']
                as Map)['elapsedMs'] =
            -1,
    'not a conversation route': (p) =>
        ((_latency(p, 0)['timings'] as List).first['details']
                as Map)['routeKind'] =
            'home',
    'not the first readable frame': (p) =>
        ((_latency(p, 0)['timings'] as List).first['details']
                as Map)['milestone'] =
            'live_render',
    'device clock missing': (p) => _latency(p, 1)['deviceTapClockMs'] = null,
    'event before the tap': (p) => _latency(p, 2)['deviceTapClockMs'] = 4000000,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _fixture();
      entry.value(proof);
      expect(validateProductionNotificationTapLatency(proof), isNotEmpty);
    });
  }
}
