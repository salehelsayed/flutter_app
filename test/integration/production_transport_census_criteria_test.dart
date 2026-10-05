import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/production_transport_census_criteria.dart';

Map<String, Object?> _condition(String name, int n, bool cold) {
  final texts = [for (var i = 1; i <= n; i++) 'census-run-$name-$i'];
  return {
    'name': name,
    'n': n,
    'cold': cold,
    'sendIntervalMs': 2500,
    'texts': texts,
    'sends': [
      for (var i = 1; i <= n; i++)
        {
          'condition': name,
          'index': i,
          'cold': cold,
          // The last cold send fails, as a real census may record.
          'result': cold && i == n ? 'sendFailed' : 'success',
          'messageId': cold && i == n ? null : 'm-$name-$i',
          'transport': 'relay',
          'elapsedMs': 120,
        },
    ],
    'delivered': cold ? n - 1 : n,
    'failed': cold ? 1 : 0,
    'report': {
      'totalTransportSamples': cold ? n - 1 : n,
      'transportMix': {'relay': cold ? n - 1 : n},
      'latencyByTransport': {
        'relay': {'n': cold ? n - 1 : n, 'medianMs': 110, 'p95Ms': 300},
      },
    },
    'receivedTexts': [
      'an unrelated earlier message',
      for (var i = 1; i <= (cold ? n - 1 : n); i++) texts[i - 1],
    ],
  };
}

Map<String, Object?> _fixture() => {
  'runId': 'run',
  'interval': productionTransportCensusInterval,
  'conditions': [_condition('A_cold', 5, true), _condition('B_warm', 3, false)],
};

Map<String, Object?> _cold(Map<String, Object?> p) =>
    (p['conditions']! as List).first as Map<String, Object?>;

void main() {
  test('accepts a reconciled census with one failed cold send', () {
    expect(validateProductionTransportCensus(_fixture()), isEmpty);
  });

  final mutations = <String, void Function(Map<String, Object?>)>{
    'no condition': (p) => p['conditions'] = <Object?>[],
    'interval not named': (p) => p['interval'] = 'something else',
    'send skipped': (p) => (_cold(p)['sends']! as List).removeLast(),
    'send repeated': (p) {
      final sends = _cold(p)['sends']! as List;
      (sends[1] as Map)['index'] = 1;
    },
    'cold lever not applied': (p) =>
        ((_cold(p)['sends']! as List).first as Map)['cold'] = false,
    'delivered count inflated': (p) => _cold(p)['delivered'] = 5,
    'failed count hidden': (p) => _cold(p)['failed'] = 0,
    'delivered text never stored': (p) =>
        (_cold(p)['receivedTexts']! as List).removeLast(),
    'delivered text stored twice': (p) =>
        (_cold(p)['receivedTexts']! as List).add('census-run-A_cold-1'),
    'no transport samples': (p) =>
        (_cold(p)['report']! as Map)['totalTransportSamples'] = 0,
    'no transport mix': (p) =>
        (_cold(p)['report']! as Map)['transportMix'] = <String, Object?>{},
    'no latency samples': (p) =>
        (_cold(p)['report']! as Map)['latencyByTransport'] =
            <String, Object?>{},
    'nothing delivered anywhere': (p) {
      for (final c in (p['conditions']! as List).cast<Map>()) {
        for (final s in (c['sends']! as List).cast<Map>()) {
          s['result'] = 'sendFailed';
          s['messageId'] = null;
        }
        c['delivered'] = 0;
        c['failed'] = (c['sends']! as List).length;
        c['receivedTexts'] = <Object?>[];
      }
    },
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _fixture();
      entry.value(proof);
      expect(validateProductionTransportCensus(proof), isNotEmpty);
    });
  }
}
