import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/sims/production_performance_criteria.dart';

Map<String, Object?> _fixture() {
  Map<String, Object?> metric(
    String event, [
    String phase = 'cold_start',
    int ms = 100,
  ]) => {
    'event': event,
    'details': {'phase': phase, 'totalMs': ms, 'source': 'test-fixture'},
  };
  Map<String, Object?> snap(
    int index,
    List<Map<String, Object?>> events, {
    String state = 'resumed',
    String badge = 'onlineDotted',
  }) {
    final copied = jsonDecode(jsonEncode(events)) as List;
    for (var i = 0; i < copied.length; i++) {
      copied[i]['sequence'] = i + 1;
      copied[i]['observedMicros'] = (i + 1) * 10000000;
    }
    return {
      'runId': 'run',
      'profileId': 'android.e2e.performance_relay',
      'localDiscoveryDisabled': true,
      'role': 'alice',
      'nonce': 'n$index',
      'processId': 100 + index,
      'nodePeerId': 'peer-$index',
      'captureStartedBeforeRuntime': true,
      'timingScope': 'production node readiness and actual OS lifecycle',
      'lifecycle': state,
      'nodeStarted': true,
      'sendReady': true,
      'inboxReady': true,
      'badge': badge,
      'observedMicros': (copied.length + 1) * 10000000,
      'events': copied,
    };
  }

  final coldEvents = [
    metric('P2P_SERVICE_START_NODE_CORE_BEGIN'),
    metric('TIME_TO_ONLINE_BADGE'),
    metric('TIME_TO_SENDABLE_BADGE'),
    metric('TIME_TO_RELAY_READY_BADGE', 'cold_start', 110),
    {
      'event': 'node:startup_timing',
      'details': {'totalToDiscoverableMs': 90},
    },
  ];
  final proof = <String, Object?>{
    'runId': 'run',
    'cold': [for (var i = 0; i < 6; i++) snap(i, coldEvents)],
  };
  Map<String, Object?> lifecycle(String state) => {
    'event': 'APPLICATION_LIFECYCLE',
    'details': {'state': state},
  };
  for (final name in [
    'hot-core',
    'hot-node',
    'healthy',
    'degraded',
    'extended',
    'recovery',
    'repeated-recovery-1',
    'repeated-recovery-2',
    'repeated-recovery-3',
  ]) {
    final recovery =
        name == 'recovery' || name.startsWith('repeated-recovery-');
    final es = [...coldEvents];
    final w = <String, Object?>{
      'before': snap(5, es),
      'sendableWaitMs': 100,
      'relayWaitMs': 100,
    };
    if (name.startsWith('hot-')) {
      es.add(metric('P2P_SERVICE_START_NODE_CORE_BEGIN'));
      if (name == 'hot-core') {
        es.add(metric('P2P_SERVICE_START_NODE_CORE_ALREADY_RUNNING'));
      } else {
        es.add(metric('TIME_TO_SENDABLE_BADGE', 'hot_restart'));
      }
      w['started'] = true;
    } else {
      if (!recovery) {
        es.add(lifecycle('paused'));
        w['background'] = snap(5, es, state: 'paused');
      }
      if (name == 'degraded' || recovery) {
        w['degraded'] = snap(
          5,
          es,
          state: name == 'degraded' ? 'paused' : 'resumed',
          badge: 'connecting',
        );
        w['disconnectCount'] = 1;
        w['degradeWaitMs'] = 10;
      }
      // Two real-metric placeholders establish a >30-second extended interval
      // in this deterministic fixture's monotonic clock.
      es.add(metric('FIRST_SEND_SUCCESS_IN_WINDOW'));
      es.add(metric('FIRST_INBOX_SUCCESS_IN_WINDOW'));
      if (!recovery) es.add(lifecycle('resumed'));
      if (name == 'healthy' || name == 'extended') {
        es.add(
          metric('TIME_TO_ONLINE_BADGE', 'background_resume_already_online'),
        );
      } else {
        es.add(metric('TIME_TO_SENDABLE_BADGE', 'recovery'));
        es.add(metric('TIME_TO_RELAY_READY_BADGE', 'recovery'));
        es.add(metric('RELAY_OUTAGE_TIMING', 'recovered'));
      }
    }
    final after = snap(5, es);
    if (name == 'hot-core') {
      after['sendReady'] = false;
      after['inboxReady'] = false;
      after['badge'] = 'connecting';
      w.remove('sendableWaitMs');
      w.remove('relayWaitMs');
    }
    w['after'] = after;
    proof[name] = w;
  }
  return proof;
}

void main() {
  test('retains complete B/M/BR production observations and exact budgets', () {
    expect(validateProductionPerformance(_fixture()), isEmpty);
  });
  final mutations = <String, void Function(Map<String, Object?>)>{
    'wrong production variant': (p) =>
        (p['cold'] as List)[0]['profileId'] = 'android.e2e.main',
    'LAN topology enabled': (p) =>
        (p['cold'] as List)[0]['localDiscoveryDisabled'] = false,
    'malformed events': (p) => (p['cold'] as List)[0]['events'][0] = 'bad',
    'malformed sequence': (p) =>
        (p['cold'] as List)[0]['events'][0]['sequence'] = 'bad',
    'different hot peer': (p) =>
        (p['hot-node'] as Map)['after']['nodePeerId'] = 'foreign',
    'rewritten capture prefix': (p) =>
        (p['healthy'] as Map)['after']['events'][0]['event'] = 'rewritten',
    'foreign degraded process': (p) =>
        (p['degraded'] as Map)['degraded']['processId'] = 999,
    'hot deadline relaxed': (p) =>
        (p['hot-node'] as Map)['relayWaitMs'] = 10001,
    'missing cold sample': (p) => (p['cold'] as List).removeLast(),
    'reused cold identity': (p) =>
        (p['cold'] as List)[1]['nodePeerId'] = 'peer-0',
    'reused cold process': (p) => (p['cold'] as List)[1]['processId'] = 100,
    'reused nonce': (p) => (p['cold'] as List)[1]['nonce'] = 'n0',
    'wrong actor': (p) => (p['cold'] as List)[0]['role'] = 'bob',
    'missing early observer': (p) =>
        (p['cold'] as List)[0]['captureStartedBeforeRuntime'] = false,
    'incorrect scope': (p) =>
        (p['cold'] as List)[0]['timingScope'] = 'whole application launch',
    'false ready state': (p) => (p['cold'] as List)[0]['inboxReady'] = false,
    'late observer': (p) =>
        (p['cold'] as List)[0]['events'][0]['event'] = 'irrelevant',
    'absent cold sendable': (p) =>
        (p['cold'] as List)[0]['events'][2]['event'] = 'irrelevant',
    'equal cold limit': (p) =>
        (p['cold'] as List)[0]['events'][2]['details']['totalMs'] = 6000,
    'equal online limit': (p) =>
        (p['cold'] as List)[0]['events'][1]['details']['totalMs'] = 6000,
    'equal native limit': (p) =>
        (p['cold']
                as List)[0]['events'][4]['details']['totalToDiscoverableMs'] =
            5000,
    'slow relay ready': (p) =>
        (p['cold'] as List)[0]['events'][3]['details']['totalMs'] = 5101,
    'negative metric': (p) =>
        (p['cold'] as List)[0]['events'][2]['details']['totalMs'] = -1,
    'duplicate event sequence': (p) =>
        (p['cold'] as List)[0]['events'][2]['sequence'] = 2,
    'clock regression': (p) =>
        (p['cold'] as List)[0]['events'][2]['observedMicros'] = 0,
    'missing metric source': (p) =>
        (p['cold'] as List)[0]['events'][2]['details']['source'] = '',
    'hot operation failed': (p) => (p['hot-node'] as Map)['started'] = false,
    'hot process restarted': (p) =>
        (p['hot-core'] as Map)['after']['processId'] = 999,
    'hot original call skipped': (p) =>
        (p['hot-core'] as Map)['after']['events'][5]['event'] = 'irrelevant',
    'healthy no pause': (p) =>
        (p['healthy'] as Map)['after']['events'][5]['event'] = 'irrelevant',
    'healthy not paused': (p) =>
        (p['healthy'] as Map)['background']['lifecycle'] = 'resumed',
    'healthy no resume': (p) =>
        (p['healthy'] as Map)['after']['events'][8]['event'] = 'irrelevant',
    'healthy wrong phase': (p) =>
        (p['healthy'] as Map)['after']['events'][9]['details']['phase'] =
            'cold_start',
    'short extended hold': (p) =>
        (p['extended'] as Map)['after']['events'][5]['observedMicros'] =
            61000000,
    'degrade failed': (p) =>
        (p['degraded'] as Map)['degraded']['badge'] = 'onlineDotted',
    'no actual relay fault': (p) =>
        (p['degraded'] as Map)['disconnectCount'] = 0,
    'degrade timeout relaxed': (p) =>
        (p['degraded'] as Map)['degradeWaitMs'] = 15001,
    'recovery omitted': (p) =>
        (p['degraded'] as Map)['after']['events'].removeLast(),
    'sendable deadline relaxed': (p) =>
        (p['healthy'] as Map)['sendableWaitMs'] = 30001,
    'relay deadline relaxed': (p) =>
        (p['recovery'] as Map)['relayWaitMs'] = 30001,
    'repeated recovery cycle omitted': (p) => p.remove('repeated-recovery-2'),
    'repeated recovery loss neither seen nor streamed': (p) {
      final degraded = (p['repeated-recovery-2'] as Map)['degraded'] as Map;
      degraded['badge'] = 'onlineDotted';
      degraded['relayLossObserved'] = false;
    },
    'streamed loss cannot excuse M-Sim-2 recovery': (p) {
      final degraded = (p['recovery'] as Map)['degraded'] as Map;
      degraded['badge'] = 'onlineDotted';
      degraded['relayLossObserved'] = true;
    },
    'repeated recovery without relay loss': (p) =>
        (p['repeated-recovery-3'] as Map)['degraded']['badge'] = 'onlineDotted',
    'repeated recovery degrade relaxed': (p) =>
        (p['repeated-recovery-1'] as Map)['degradeWaitMs'] = 15001,
    'repeated recovery relay deadline relaxed': (p) =>
        (p['repeated-recovery-2'] as Map)['relayWaitMs'] = 30001,
  };
  for (final entry in mutations.entries) {
    test('rejects ${entry.key}', () {
      final proof = _fixture();
      entry.value(proof);
      expect(validateProductionPerformance(proof), isNotEmpty);
    });
  }
  test('accepts a C-Sim-2 loss seen only on the production state stream', () {
    final proof = _fixture();
    final degraded = (proof['repeated-recovery-1'] as Map)['degraded'] as Map;
    degraded['badge'] = 'onlineDotted';
    degraded['relayLossObserved'] = true;
    expect(validateProductionPerformance(proof), isEmpty);
  });
  test('does not invent the optional original online/native events', () {
    final proof = _fixture();
    final es = (proof['cold'] as List)[0]['events'] as List;
    es[1]['event'] = 'not-reported';
    es[4]['event'] = 'not-reported';
    expect(validateProductionPerformance(proof), isEmpty);
  });
}
