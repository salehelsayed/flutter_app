import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_direct_sender_offline_criteria.dart';

const _run = 'sender-offline-fixture';

Map<String, Object?> _proof() {
  final peers = {'alice': 'alice-account', 'bob': 'bob-account'};
  final text = directSenderOfflineText(_run);
  final pattern = RegExp.escape(text);
  final ui = <String, Object?>{};
  void receipt(String label, String flow, Map<String, String> values) {
    ui[label] = {
      'path': '$label.json',
      'flow': flow,
      'values': values,
      'receipt': {
        'status': 'PASS',
        'exit_status': 0,
        'flows': [flow],
      },
    };
  }

  receipt('send-offline', 'production_direct_send_checkpoint', {
    'MESSAGE': text,
    'MESSAGE_PATTERN': pattern,
  });
  receipt('offline-ui', 'production_direct_assert_action', {
    'VISIBLE_PATTERN': '$pattern.*Message status: sending',
    'ABSENT_PATTERN': '$pattern.*(?:Message status: failed|Retry)',
  });
  for (final phase in ['reconnected', 'restarted']) {
    receipt('$phase-ui-alice', 'production_direct_assert_action', {
      'VISIBLE_PATTERN': '$pattern.*Sent to inbox',
      'ABSENT_PATTERN': '$pattern.*(?:Message status: failed|Retry)',
    });
    receipt('$phase-ui-bob', 'production_direct_assert_action', {
      'VISIBLE_PATTERN': '$pattern.*Received via inbox',
      'ABSENT_PATTERN': '$pattern.*(?:Message status: failed|Retry)',
    });
  }
  Map<String, Object?> snapshot(String role, String phase) => {
    'observedRunId': _run,
    'observedRole': role,
    'observedNonce': '$role-${phase == 'restarted' ? 'second' : 'first'}',
    'node': {
      'isStarted': !(role == 'alice' && phase == 'offline'),
      'sendCapabilityReady': phase != 'offline',
      'inboxCapabilityReady': phase != 'offline',
    },
    'messages': <Map<String, Object?>>[
      if (!(role == 'bob' && phase == 'offline'))
        {
          'id': 'original-logical-id',
          'text': text,
          'timestamp': '2026-10-23T14:00:00.000Z',
          'lane': 'direct',
          'conversationId': peers[role == 'alice' ? 'bob' : 'alice'],
          'incoming': role == 'bob',
          'deletedAt': null,
          'status': phase == 'offline' ? 'failed' : 'delivered',
          'transport': phase == 'offline' ? null : 'inbox',
        },
    ],
  };
  return {
    'runId': _run,
    'runtimeScenario': directSenderOfflineRuntime,
    'emulatorPair': true,
    'peers': peers,
    'ui': ui,
    'stop': {
      'operation': 'stop',
      'result': true,
      'after': {'isStarted': false, 'connections': []},
    },
    'start': {
      'operation': 'start',
      'result': true,
      'after': {'isStarted': true},
    },
    'warm': {'operation': 'warm_background', 'result': true},
    'nonces': {
      for (final role in ['alice', 'bob'])
        role: ['$role-first', '$role-second'],
    },
    'ownedKills': {
      for (final role in ['alice', 'bob']) role: {'verifiedUidKill': true},
    },
    'phases': {
      for (final phase in ['offline', 'reconnected', 'restarted'])
        phase: {
          for (final role in ['alice', 'bob']) role: snapshot(role, phase),
        },
    },
  };
}

Map _phase(Map proof, String phase, String role) =>
    (proof['phases'] as Map)[phase][role] as Map;
List _rows(Map proof, String phase, String role) =>
    _phase(proof, phase, role)['messages'] as List;

void main() {
  test(
    'authoritative failed row with pending UI recovers automatically under the same ID',
    () {
      expect(validateProductionDirectSenderOffline(_proof()), isEmpty);
    },
  );
  test(
    'an offline badge without actual stopped sender transport is insufficient',
    () {
      final proof = _proof();
      (_phase(proof, 'offline', 'alice')['node'] as Map)['isStarted'] = true;
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
    },
  );
  test(
    'a recipient delivery before reconnect refutes the controlled offline leg',
    () {
      final proof = _proof();
      _rows(proof, 'offline', 'bob').add(
        Map<String, Object?>.from(
          _rows(proof, 'reconnected', 'bob').single as Map,
        ),
      );
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
    },
  );
  test(
    'rewriting the original failed state into an invented queue state is rejected',
    () {
      final proof = _proof();
      (_rows(proof, 'offline', 'alice').single as Map)['status'] = 'queued';
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
    },
  );
  test(
    'persisted failed does not authorize a terminal failure or manual-Retry UI claim',
    () {
      final proof = _proof();
      ((((proof['ui'] as Map)['offline-ui'] as Map)['values'])
              as Map)['VISIBLE_PATTERN'] =
          'Message status: failed';
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
    },
  );
  test(
    'replacement identity or duplicate after replay cannot count as recovered delivery',
    () {
      final proof = _proof();
      (_rows(proof, 'reconnected', 'alice').single as Map)['id'] =
          'replacement-id';
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
      final duplicate = _proof();
      final rows = _rows(duplicate, 'restarted', 'bob');
      rows.add(Map<String, Object?>.from(rows.single as Map));
      expect(validateProductionDirectSenderOffline(duplicate), isNotEmpty);
    },
  );
  test(
    'persisted delivery cannot downgrade or render a different transport on restart',
    () {
      final proof = _proof();
      (_rows(proof, 'restarted', 'alice').single as Map)['status'] = 'failed';
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
      final wrongGlyph = _proof();
      (_rows(wrongGlyph, 'restarted', 'alice').single as Map)['transport'] =
          'direct';
      expect(
        validateProductionDirectSenderOffline(wrongGlyph),
        isNotEmpty,
        reason: 'recorded inbox UI cannot certify a persisted direct path',
      );
    },
  );
  test(
    'a stale nonce or absent owned death cannot establish durable restart replay',
    () {
      final proof = _proof();
      _phase(proof, 'restarted', 'bob')['observedNonce'] = 'bob-first';
      expect(validateProductionDirectSenderOffline(proof), isNotEmpty);
      final missing = _proof();
      (missing['ownedKills'] as Map).remove('bob');
      expect(validateProductionDirectSenderOffline(missing), isNotEmpty);
    },
  );
  test('transport labels follow the current English shipped semantics', () {
    final english =
        (jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map)
            .values
            .toSet();
    for (final transport in [
      'relay',
      'direct',
      'reuse',
      'upgraded',
      'wifi',
      'local',
      'inbox',
    ]) {
      for (final incoming in [true, false]) {
        expect(
          english,
          contains(
            directSenderOfflineTransportLabel(transport, incoming: incoming),
          ),
        );
      }
    }
    expect(
      directSenderOfflineTransportLabel('unrecognized', incoming: false),
      isNull,
    );
  });
}
