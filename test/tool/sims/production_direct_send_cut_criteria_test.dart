import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart'
    show interactiveInboxBudget;

import '../../../tool/sims/production_direct_send_cut_criteria.dart';

const _run = 'sender-cut-fixture';
final _stamp = DateTime.utc(2026, 10, 23);

Map<String, Object?> _proof() {
  Map<String, Object?> row(String role, String status) => {
    'id': 'fixture-logical-message',
    'text': 'In-flight sender cut $_run',
    'timestamp': _stamp.toIso8601String(),
    'conversationId': role == 'alice' ? 'bob-account' : 'alice-account',
    'lane': 'direct',
    'incoming': role == 'bob',
    'status': status,
  };
  Map<String, Object?> snapshot(String role, String status) => {
    'observedRunId': _run,
    'observedRole': role,
    'messages': [row(role, status)],
  };
  Map<String, Object?> gate() => {
    'schema': 'mknoon.direct-text-send-checkpoint.v1',
    'armed': true,
    'held': true,
    'released': false,
    'timedOut': false,
    'messageSha256': sha256
        .convert(utf8.encode('fixture-logical-message'))
        .toString(),
  };
  return {
    'runId': _run,
    'runtimeScenario': directSendCutRuntime,
    'emulatorPair': true,
    'peers': {'alice': 'alice-account', 'bob': 'bob-account'},
    'cut': {
      'source': snapshot('alice', 'sending'),
      'deviceUnixMsAfterVerifiedDeath': _stamp.millisecondsSinceEpoch + 1000,
      'gateBeforeKill': gate(),
      'gateAfterKill': gate(),
      'ownedKill': {'verifiedUidKill': true},
      'recipientForceStopped': true,
      'recipientAbsentAfterCut': true,
      'uiReceipt': {
        'status': 'PASS',
        'exit_status': 0,
        'flows': ['production_direct_send_checkpoint'],
      },
    },
    'nonces': {
      for (final role in ['alice', 'bob'])
        role: ['$role-first', '$role-second', '$role-third'],
    },
    'restartKills': {
      for (final role in ['alice', 'bob']) role: {'verifiedUidKill': true},
    },
    'phases': {
      for (final phase in ['firstReplay', 'bothRestarted'])
        phase: {
          for (final role in ['alice', 'bob'])
            role: snapshot(role, 'delivered'),
        },
    },
  };
}

Map _cut(Map proof) => proof['cut'] as Map;
Map _sourceRow(Map proof) =>
    (((_cut(proof)['source'] as Map)['messages']) as List).single as Map;
List _rows(Map proof, String phase, String role) =>
    (((proof['phases'] as Map)[phase] as Map)[role] as Map)['messages'] as List;

void main() {
  test('cut proof bound stays below the actual application store timeout', () {
    expect(
      directSendCutMaximumAgeMs,
      lessThan(interactiveInboxBudget.inMilliseconds),
    );
  });

  test(
    'real checkpoint plus verified in-budget cut and stable replay is accepted',
    () {
      expect(validateProductionDirectSendCut(_proof()), isEmpty);
    },
  );

  test(
    'a stale sending sample cannot certify a cut after the bounded window',
    () {
      final proof = _proof();
      _cut(proof)['deviceUnixMsAfterVerifiedDeath'] =
          _stamp.millisecondsSinceEpoch + directSendCutMaximumAgeMs;
      expect(validateProductionDirectSendCut(proof), isNotEmpty);
      _cut(proof)['deviceUnixMsAfterVerifiedDeath'] =
          _stamp.millisecondsSinceEpoch - 1;
      expect(validateProductionDirectSendCut(proof), isNotEmpty);
    },
  );

  test('an already failed row is not an in-flight crash checkpoint', () {
    final proof = _proof();
    _sourceRow(proof)['status'] = 'failed';
    expect(validateProductionDirectSendCut(proof), isNotEmpty);
  });

  test(
    'an early released, timed-out or unrelated store cannot certify the cut',
    () {
      for (final change in <String, Object?>{
        'released': true,
        'timedOut': true,
        'held': false,
        'messageSha256': 'unrelated',
      }.entries) {
        final proof = _proof();
        (_cut(proof)['gateAfterKill'] as Map)[change.key] = change.value;
        expect(
          validateProductionDirectSendCut(proof),
          isNotEmpty,
          reason: change.key,
        );
      }
    },
  );

  test(
    'receiver duplicate after the second restart fails exact-once delivery',
    () {
      final proof = _proof();
      final rows = _rows(proof, 'bothRestarted', 'bob');
      rows.add(Map<String, Object?>.from(rows.single as Map));
      expect(validateProductionDirectSendCut(proof), isNotEmpty);
    },
  );

  test(
    'replacing logical identity on retry is rejected even with identical text',
    () {
      final proof = _proof();
      (_rows(proof, 'firstReplay', 'bob').single as Map)['id'] = 'replacement';
      expect(validateProductionDirectSendCut(proof), isNotEmpty);
    },
  );

  test(
    'wrong transcript account or stale invocation cannot certify recovery',
    () {
      final crossed = _proof();
      (_rows(crossed, 'bothRestarted', 'bob').single as Map)['conversationId'] =
          'unrelated-account';
      expect(validateProductionDirectSendCut(crossed), isNotEmpty);
      final stale = _proof();
      (stale['nonces'] as Map)['alice'] = [
        'alice-first',
        'alice-second',
        'alice-second',
      ];
      expect(validateProductionDirectSendCut(stale), isNotEmpty);
    },
  );

  test(
    'missing actual UI status witness and an unexpectedly online recipient fail',
    () {
      final missingUi = _proof();
      (_cut(missingUi)['uiReceipt'] as Map)['status'] = 'FAIL';
      expect(validateProductionDirectSendCut(missingUi), isNotEmpty);
      final online = _proof();
      _cut(online)['recipientAbsentAfterCut'] = false;
      expect(validateProductionDirectSendCut(online), isNotEmpty);
    },
  );
}
