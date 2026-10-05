import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/production_message_latency_criteria.dart';

Map<String, Object?> _send(String name, int index) {
  final group = name == 'GP';
  return {
    'key': '$name-$index',
    'result': group ? 'success' : 'success',
    'messageId': 'm-$name-$index',
    'timings': [
      {
        'event': group ? 'GROUP_SEND_MSG_TIMING' : 'CHAT_MSG_SEND_TIMING',
        'details': {
          'elapsedMs': 100 + index,
          'outcome': 'success',
          'connectionReused': index > 1,
        },
      },
    ],
  };
}

Map<String, Object?> _fixture() {
  final cases = <String, Object?>{
    for (final entry in productionMessageLatencyPlan.entries)
      entry.key: <String, Object?>{
        'sends': <Object?>[
          for (var i = 0; i < entry.value; i++) _send(entry.key, i + 1),
        ],
      },
  };
  (cases['R-Sim-3']! as Map)['unregister'] = {'ok': true};
  (cases['R-Sim-3']! as Map)['register'] = {'ok': true};
  (cases['R-Sim-7']! as Map)['stop'] = {'result': true};
  (cases['R-Sim-7']! as Map)['start'] = {'result': true};
  return {
    'interval': productionMessageLatencyInterval,
    'notReproduced': productionMessageLatencyNotReproduced,
    'cases': cases,
  };
}

Map<String, Object?> _case(Map<String, Object?> p, String name) =>
    (p['cases']! as Map)[name] as Map<String, Object?>;
List _sends(Map<String, Object?> p, String name) =>
    _case(p, name)['sends']! as List;

void main() {
  test('accepts every planned send with one timing event', () {
    expect(validateProductionMessageLatency(_fixture()), isEmpty);
  });

  test('a failed direct send still counts when it emitted its timing', () {
    final proof = _fixture();
    (_sends(proof, 'A-Sim-3').first as Map)['result'] = 'sendFailed';
    expect(validateProductionMessageLatency(proof), isEmpty);
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'interval not named': (p) => p['interval'] = 'other',
    'R-Sim-6 reason missing': (p) =>
        p['notReproduced'] = {'R-Sim-8': 'report-only'},
    'case missing': (p) => (p['cases']! as Map).remove('R-Sim-4'),
    'a send skipped': (p) => _sends(p, 'A-Sim-2').removeLast(),
    'a send repeated': (p) =>
        (_sends(p, 'R-Sim-1')[1] as Map)['key'] = 'R-Sim-1-1',
    'timing event missing': (p) =>
        (_sends(p, 'R-Sim-3').first as Map)['timings'] = <Object?>[],
    'two timing events for one send': (p) {
      final send = _sends(p, 'A-Sim-1').first as Map;
      send['timings'] = [
        ...send['timings'] as List,
        ...send['timings'] as List,
      ];
    },
    'wrong timing event': (p) =>
        ((_sends(p, 'GP').first as Map)['timings'] as List).first['event'] =
            'CHAT_MSG_SEND_TIMING',
    'no elapsedMs': (p) =>
        (((_sends(p, 'R-Sim-7')[6] as Map)['timings'] as List).first['details']
                as Map)
            .remove('elapsedMs'),
    'group send failed': (p) => (_sends(p, 'GP')[2] as Map)['result'] = 'error',
    'rendezvous never left': (p) =>
        _case(p, 'R-Sim-3')['unregister'] = {'ok': false},
    'rendezvous not restored': (p) => _case(p, 'R-Sim-3').remove('register'),
    'receiver never stopped': (p) =>
        _case(p, 'R-Sim-7')['stop'] = {'result': false},
    'receiver never restarted': (p) => _case(p, 'R-Sim-7').remove('start'),
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _fixture();
      entry.value(proof);
      expect(validateProductionMessageLatency(proof), isNotEmpty);
    });
  }

  test('stats report p50, p95 and n over the timing events', () {
    final stats = productionLatencyStats(
      [for (var i = 1; i <= 5; i++) _send('A-Sim-1', i)].cast(),
    );
    expect(stats, {'n': 5, 'p50Ms': 103, 'p95Ms': 105});
  });
}
