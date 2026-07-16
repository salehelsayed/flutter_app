import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_notification_payload_campaign.dart';

void main() {
  test('cold notification leg explicitly kills the headless FCM process', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runColdPayloadLeg()',
    );
    final end = source.indexOf(
      'Future<Map<String, Object?>> _restartAndDrain',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final coldLeg = source.substring(start, end);

    expect(
      RegExp(
        r'await _waitForNotification\(marker\);\s*'
        r'await _terminateReceiver\(\);\s*'
        r'await _setNetworkAvailable\(false\);',
      ).hasMatch(coldLeg),
      isTrue,
    );
    expect(
      coldLeg,
      isNot(contains('headless FCM process exit before cold tap')),
    );
  });

  test(
    'receiver termination uses bounded stop-app fallback without force-stop',
    () {
      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> _terminateReceiver()');
      final end = source.indexOf(
        'Future<bool> _receiverProcessAbsentWithin',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      final home = method.indexOf("'KEYCODE_HOME'");
      final settle = method.indexOf('Duration(milliseconds: 750)', home);
      final kill = method.indexOf("'kill'", settle);
      final boundedProbe = method.indexOf(
        '_receiverProcessAbsentWithin(const Duration(seconds: 5))',
        kill,
      );
      final stopApp = method.indexOf("'stop-app'", boundedProbe);
      final finalWait = method.indexOf(
        "'receiver process termination'",
        stopApp,
      );
      final emptyPid = method.indexOf(
        '(await _pidof(emulator)).isEmpty',
        finalWait,
      );
      expect(home, greaterThan(0));
      expect(settle, greaterThan(home));
      expect(kill, greaterThan(settle));
      expect(boundedProbe, greaterThan(kill));
      expect(stopApp, greaterThan(boundedProbe));
      expect(finalWait, greaterThan(stopApp));
      expect(emptyPid, greaterThan(finalWait));
      expect(method, contains("'cmd'"));
      expect(method, contains("'activity'"));
      expect(method, isNot(contains("'force-stop'")));
    },
  );

  test('bounded receiver termination probe polls pidof for five seconds', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> _receiverProcessAbsentWithin');
    final end = source.indexOf('Future<String> _pidof', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    expect(helper, contains('DateTime.now().add(timeout)'));
    expect(helper, contains('(await _pidof(emulator)).isEmpty'));
    expect(helper, contains('Duration(milliseconds: 500)'));
    expect(helper, contains('return false'));
  });

  test('installed action results distinguish binding and action failures', () {
    final config = <String, Object?>{
      'transport_action': androidNotificationDrainObserveAction,
      'stepId': 'notification-notification_drain_observe-run-1',
      'runId': 'run-1',
      'nonce': 'nonce-1',
    };
    final result = <String, Object?>{
      'schema': androidNotificationPayloadE2EResultSchema,
      'transport_action': androidNotificationDrainObserveAction,
      'scenario': androidNotificationPayloadE2EScenario,
      'stepId': config['stepId'],
      'runId': config['runId'],
      'nonce': config['nonce'],
      'status': 'complete',
      'success': true,
    };

    expect(
      classifyAndroidNotificationActionResult(
        result: result,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.accepted,
    );

    for (final bindingKey in <String>[
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'runId',
      'nonce',
    ]) {
      final mismatched = Map<String, Object?>.from(result)
        ..[bindingKey] = 'wrong-$bindingKey';
      expect(
        classifyAndroidNotificationActionResult(
          result: mismatched,
          config: config,
          expectedStatus: 'complete',
        ),
        AndroidNotificationActionResultDisposition.bindingMismatch,
        reason: bindingKey,
      );
    }

    final failed = Map<String, Object?>.from(result)
      ..['status'] = 'failed'
      ..['success'] = false
      ..['errorType'] = 'StateError';
    expect(
      classifyAndroidNotificationActionResult(
        result: failed,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.boundFailure,
    );

    final mismatchedFailure = Map<String, Object?>.from(failed)
      ..['nonce'] = 'wrong-nonce';
    expect(
      classifyAndroidNotificationActionResult(
        result: mismatchedFailure,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.bindingMismatch,
    );

    final invalid = Map<String, Object?>.from(result)..['success'] = false;
    expect(
      classifyAndroidNotificationActionResult(
        result: invalid,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.invalidCompletion,
    );
  });

  test('installed action failure diagnostics allowlist error type only', () {
    expect(safeAndroidNotificationActionErrorType('StateError'), 'StateError');
    expect(
      safeAndroidNotificationActionErrorType('TimeoutException'),
      'TimeoutException',
    );
    expect(
      safeAndroidNotificationActionErrorType(
        'StateError: secret peer and plaintext marker',
      ),
      'unavailable',
    );
    expect(
      safeAndroidNotificationActionErrorType(<String, Object?>{
        'message': 'secret peer and plaintext marker',
      }),
      'unavailable',
    );
  });

  test('accepts one exact production FCM staged ciphertext tuple', () {
    final observation = parseAndroidStagedEnvelopeObservation(
      jsonEncode(<String, Object?>{
        'kind': 'chat',
        'kem': 'raw-kem',
        'ciphertext': 'raw-ciphertext',
        'nonce': 'raw-nonce',
        'senderPeerId': 'peer-sender',
        'messageId': 'message-123456789',
        'receivedAtMs': 2000,
      }),
      expectedMessageId: 'message-123456789',
      expectedSenderPeerId: 'peer-sender',
      notBefore: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

    expect(observation.messageId, 'message-123456789');
    expect(observation.toJson()['messageIdPrefix'], 'message-');
    expect(observation.ciphertextSha256, hasLength(64));
    expect(observation.nonceSha256, hasLength(64));
    expect(observation.toJson().toString(), isNot(contains('raw-ciphertext')));
    expect(observation.toJson().toString(), isNot(contains('raw-nonce')));
  });

  test(
    'rejects wrong sender, message, kind, stale time, and missing crypto',
    () {
      final base = <String, Object?>{
        'kind': 'chat',
        'kem': 'kem',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
        'senderPeerId': 'peer-sender',
        'messageId': 'message-1',
        'receivedAtMs': 2000,
      };
      for (final mutate in <void Function(Map<String, Object?>)>[
        (value) => value['kind'] = 'reaction',
        (value) => value['kem'] = '',
        (value) => value['ciphertext'] = '',
        (value) => value['nonce'] = '',
        (value) => value['senderPeerId'] = 'peer-other',
        (value) => value['messageId'] = 'message-other',
        (value) => value['receivedAtMs'] = 999,
      ]) {
        final value = Map<String, Object?>.from(base);
        mutate(value);
        expect(
          () => parseAndroidStagedEnvelopeObservation(
            jsonEncode(value),
            expectedMessageId: 'message-1',
            expectedSenderPeerId: 'peer-sender',
            notBefore: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('provider journal match is recipient-prefix-bound', () {
    const peer = '12D3KooWRecipientPeerIdentifierLong';
    expect(
      relayJournalContainsAndroidProviderSend(
        '[PUSH] Notification sent to 12D3KooWRecipientPee (attempt 1/3)',
        recipientPeerId: peer,
      ),
      isTrue,
    );
    expect(
      relayJournalContainsAndroidProviderSend(
        '[PUSH] Notification sent to 12D3KooWSomeoneElse (attempt 1/3)',
        recipientPeerId: peer,
      ),
      isFalse,
    );
  });

  test('relay drain discriminator accepts only the production event name', () {
    expect(
      notificationWindowContainsRelayDrain(
        '[FLOW] P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
      ),
      isTrue,
    );
    expect(
      notificationWindowContainsRelayDrain('P2P_SERVICE_STAGED_DRAIN_SUCCESS'),
      isFalse,
    );
  });

  test('notification channel fingerprint ignores only last-post time', () {
    const before = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mLastNotificationUpdateTimeMs=10}
      AppSettings: another.package (10124)
''';
    const afterPost = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const changedPolicy = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=2, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';

    expect(
      androidNotificationChannelStateSha256(
        before,
        packageName: 'com.mknoon.app',
      ),
      androidNotificationChannelStateSha256(
        afterPost,
        packageName: 'com.mknoon.app',
      ),
    );
    expect(
      androidNotificationChannelStateSha256(
        changedPolicy,
        packageName: 'com.mknoon.app',
      ),
      isNot(
        androidNotificationChannelStateSha256(
          before,
          packageName: 'com.mknoon.app',
        ),
      ),
    );
  });
}
