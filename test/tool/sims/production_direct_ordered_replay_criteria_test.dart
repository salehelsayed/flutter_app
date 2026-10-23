import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_direct_ordered_replay_criteria.dart';

const _run = 'ordered-fixture';

Map<String, Object?> _proof() {
  final texts = directOrderedReplayTexts(_run);
  List<Map<String, Object?>> rows(String role, int count) => [
    for (var i = 0; i < count; i++)
      {
        'id': 'message-$i',
        'text': texts[i],
        'timestamp': DateTime.utc(
          2026,
          10,
          23,
        ).add(Duration(milliseconds: i * 20)).toIso8601String(),
        'lane': 'direct',
        'conversationId': role == 'alice' ? 'bob-account' : 'alice-account',
        'incoming': role == 'bob',
        'status': role == 'alice' && i >= 100 ? 'inboxed' : 'delivered',
        'transport': i >= 100 ? 'inbox' : 'direct',
      },
  ];
  Map<String, Object?> snapshot(String role, int count) => {
    'observedRole': role,
    'observedRunId': _run,
    'messages': rows(role, count),
  };
  return {
    'runId': _run,
    'runtimeScenario': directOrderedReplayRuntime,
    'peers': {'alice': 'alice-account', 'bob': 'bob-account'},
    'emulatorPair': true,
    'offlineDwellMs': 60000,
    'offlineGuard': {
      'ownedPackageForceStopped': true,
      'absentBeforeRelaunch': true,
    },
    'ownedKills': {
      for (final key in ['bobOffline', 'aliceRestart', 'bobRestart'])
        key: {'verifiedUidKill': true},
    },
    'initialNonces': {'alice': 'alice-first', 'bob': 'bob-first'},
    'finalNonces': {'alice': 'alice-second', 'bob': 'bob-second'},
    'uiBatches': [
      for (var i = 0; i < 22; i++)
        {
          'firstIndex': i * 5,
          'phase': i < 20 ? 'online' : 'offline',
          'path': 'fixture-flow-$i.json',
          'receipt': {
            'status': 'PASS',
            'exit_status': 0,
            'flows': ['production_direct_send_batch5'],
          },
        },
    ],
    'senderBeforeReplay': snapshot('alice', 110),
    'phases': {
      'online': {'alice': snapshot('alice', 100), 'bob': snapshot('bob', 100)},
      for (final phase in ['firstReplay', 'bothRestarted'])
        phase: {'alice': snapshot('alice', 110), 'bob': snapshot('bob', 110)},
    },
  };
}

List<Map<String, Object?>> _phaseRows(
  Map<String, Object?> proof,
  String phase,
  String role,
) =>
    (((proof['phases'] as Map)[phase] as Map)[role] as Map)['messages']
        as List<Map<String, Object?>>;

void main() {
  test(
    'complete UI/order/offline/restart fixture satisfies both scoped rows',
    () {
      expect(validateProductionDirectOrderedReplay(_proof()), isEmpty);
    },
  );

  test(
    '99/100 online receipts cannot stand in for complete burst delivery',
    () {
      final proof = _proof();
      _phaseRows(proof, 'online', 'bob').removeLast();
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
    },
  );

  test(
    'post-restart duplicate is rejected even when every expected text exists',
    () {
      final proof = _proof();
      final rows = _phaseRows(proof, 'bothRestarted', 'bob');
      rows.add({...rows.first});
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
    },
  );

  test(
    'same text with a different logical identity is not a successful replay',
    () {
      final proof = _proof();
      _phaseRows(proof, 'firstReplay', 'bob')[100]['id'] = 'replacement';
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
    },
  );

  test(
    'matching content with changed timestamps does not prove preserved order',
    () {
      final proof = _proof();
      final rows = _phaseRows(proof, 'bothRestarted', 'bob');
      rows[1]['timestamp'] = rows[0]['timestamp'];
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
    },
  );

  test('offline send without persisted inbox custody is rejected', () {
    final proof = _proof();
    final rows = (proof['senderBeforeReplay'] as Map)['messages'] as List;
    (rows[100] as Map)['status'] = 'sent';
    expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
  });

  test(
    'short dwell and an unexpectedly restarted recipient are not offline proof',
    () {
      final proof = _proof();
      proof['offlineDwellMs'] = 59999;
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
      proof['offlineDwellMs'] = 60000;
      (proof['offlineGuard'] as Map)['absentBeforeRelaunch'] = false;
      expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
    },
  );

  test('unchanged runtime nonce cannot certify a process restart', () {
    final proof = _proof();
    (proof['finalNonces'] as Map)['bob'] = 'bob-first';
    expect(validateProductionDirectOrderedReplay(proof), isNotEmpty);
  });

  test('missing, failed and reused UI flow receipts are rejected', () {
    final missing = _proof();
    (missing['uiBatches'] as List).removeLast();
    expect(validateProductionDirectOrderedReplay(missing), isNotEmpty);
    final failed = _proof();
    (((failed['uiBatches'] as List).first as Map)['receipt'] as Map)['status'] =
        'FAIL';
    expect(validateProductionDirectOrderedReplay(failed), isNotEmpty);
    final reused = _proof();
    final batches = reused['uiBatches'] as List;
    (batches[1] as Map)['path'] = (batches.first as Map)['path'];
    expect(validateProductionDirectOrderedReplay(reused), isNotEmpty);
  });
}
