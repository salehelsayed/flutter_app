import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_notification_payload_campaign.dart';

void main() {
  test('channel-disabled leg keeps the silent channel OPEN so a leak shows', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runChannelDisabledLeg()',
    );
    final end = source.indexOf('Future<int?> _channelImportance', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // Only the AUDIBLE channel is blocked. The app picks between its two
    // message channels from tone state and has no channel read-back, so
    // leaving `mknoon_messages_silent` open is what keeps the leak route
    // observable — device-measured 2026-08-18, a card survived there while
    // `mknoon_messages` was IMPORTANCE_NONE. Blocking BOTH channels would make
    // the zero-card census pass without the app changing anything, masking
    // exactly the defect this leg is here to catch.
    expect(
      leg,
      contains('_setChannelEnabled(_audibleNotificationChannelId, false)'),
    );
    expect(
      leg,
      isNot(
        contains('_setChannelEnabled(_silentNotificationChannelId, false)'),
      ),
    );
    expect(leg, contains('blockedSilentImportance != 2'));
  });

  test('B13 proves the alert from the log and the settled primary card', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runB13DualPathLeg()',
    );
    final end = source.indexOf('_toneWindowSpacing = ', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // The log proves that the winning publication alerted. A later dump has a
    // different job: it proves the losing-path reconcile preserved the active
    // primary-channel card instead of demoting it.
    expect(
      leg,
      contains(
        'androidNotificationFirstPostAttemptSilent(\n        await _logcatSince(logcatCursor),\n      )',
      ),
    );
    expect(leg, contains('alertSilent != false'));
    expect(leg, contains('channels.single != _audibleNotificationChannelId'));
    expect(leg, isNot(contains('_requireAudibleChannel(')));
  });

  test('log windows come from a live stream, never a post-hoc dump', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();

    // The emulator's main ring is 2 MiB and a busy campaign minute emits
    // ~1.6 MB, so an event read 60-120s after it was logged can have rotated
    // out — and an aged-out window is EMPTY, which reads as "the app never
    // emitted it". The reader must therefore be live and started up front.
    expect(source, contains('_startDeviceLogStream()'));
    expect(source, contains('logcat -T 1 -v brief'));
    expect(source, contains('_stopDeviceLogStream'));
    // Cursors are byte offsets into that stream, and the window is a file
    // slice — no adb round trip, nothing that can rotate.
    expect(source, contains('handle.setPosition(start)'));
    // `adb` owns the write. Piping stdout into `file.openWrite()` races the
    // cursor reads: `IOSink.flush()` sets `_isBound`, so a flush concurrent
    // with the stdout listener throws `StreamSink is bound to a stream` — it
    // killed a real run at assertion 1.
    final streamStart = source.indexOf(
      'Future<void> _startDeviceLogStream() async {',
    );
    final streamEnd = source.indexOf(
      'Future<void> _stopDeviceLogStream()',
      streamStart,
    );
    expect(streamStart, greaterThanOrEqualTo(0));
    expect(streamEnd, greaterThan(streamStart));
    final starter = source.substring(streamStart, streamEnd);
    expect(starter, isNot(contains('openWrite()')));
    expect(starter, isNot(contains('.listen(')));
    expect(source, isNot(contains("'-d',")));
    // Clearing the shared device log is banned by the adapter contract.
    expect(source, isNot(contains("'logcat', '-c'")));
    expect(source, isNot(contains("'-c',\n      '-t',")));
  });

  test('permission-denied leg separates an OS precondition from a defect', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runPermissionDeniedLeg()',
    );
    final end = source.indexOf(
      'Future<Map<String, Object?>> _runTokenRefreshLeg()',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // A re-granted permission means the app was never asked the question, so
    // it is BLOCKED (environment), never a product failure.
    expect(leg, contains("'deviceOsState'"));
    final blockedAt = leg.indexOf("'deviceOsState'");
    final assertedAt = leg.indexOf('_awaitFlowRecords(');
    expect(blockedAt, greaterThanOrEqualTo(0));
    expect(assertedAt, greaterThan(blockedAt));
    // ...and the typed record is awaited right after the relaunch, not after
    // the send/census minutes later.
    expect(leg.indexOf('_sendSpacedMarker('), greaterThan(assertedAt));
  });

  test('pm path package census accepts API 37 silent absence', () {
    expect(
      androidPackagePresentFromPmPath(exitCode: 1, stdout: '', stderr: ''),
      isFalse,
    );
    expect(
      androidPackagePresentFromPmPath(
        exitCode: 1,
        stdout: '',
        stderr: 'Unknown package: com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      androidPackagePresentFromPmPath(
        exitCode: 0,
        stdout: 'package:/data/app/com.mknoon.app/base.apk\n',
        stderr: '',
      ),
      isTrue,
    );
    expect(
      () => androidPackagePresentFromPmPath(
        exitCode: 23,
        stdout: '',
        stderr: 'error: transport failure',
      ),
      throwsFormatException,
    );
  });

  test(
    'G24 app-op divergence is probe-derived and restores both baselines',
    () {
      expect(
        parseAndroidNotificationAppOpMode(
          'POST_NOTIFICATION: allow; time=+4m12s ago',
        ),
        'allow',
      );
      expect(
        parseAndroidNotificationAppOpMode(
          'Uid mode: POST_NOTIFICATION: ignore\nPOST_NOTIFICATION: ignore',
        ),
        'ignore',
      );
      expect(
        parseAndroidNotificationUidAppOpMode(
          'Uid mode: POST_NOTIFICATION: ignore\nPOST_NOTIFICATION: allow',
        ),
        'ignore',
      );
      expect(
        parseAndroidNotificationUidAppOpMode(
          'POST_NOTIFICATION: allow; time=+4m12s ago',
        ),
        'default',
      );
      expect(androidNotificationUidAppOpShellMode('default'), 'allow');
      expect(androidNotificationUidAppOpShellMode('ignore'), 'ignore');
      expect(
        () => androidNotificationUidAppOpShellMode('future-mode'),
        throwsFormatException,
      );
      expect(
        androidNotificationUidAppOpMutationBlocked(
          'Blocked setUidMode call for runtime permission app op: '
          'uid = 10252, code = POST_NOTIFICATION, mode = ignore',
        ),
        isTrue,
      );
      expect(
        androidNotificationUidAppOpMutationBlocked(
          'setUidMode accepted: code = POST_NOTIFICATION, mode = ignore',
        ),
        isFalse,
      );
      expect(
        () => parseAndroidNotificationAppOpMode(
          'POST_NOTIFICATION: mode-from-a-future-android',
        ),
        throwsFormatException,
      );

      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      expect(source, contains('androidPackagePresentFromPmPath('));
      final runStart = source.indexOf(
        'Future<AndroidNotificationCampaignResult> run() async',
      );
      final runEnd = source.indexOf('Future<void> _preflight()', runStart);
      expect(runStart, greaterThanOrEqualTo(0));
      expect(runEnd, greaterThan(runStart));
      final run = source.substring(runStart, runEnd);

      final guardCapture = run.indexOf('AndroidAppStateGuard.capture(');
      final entryCapture = run.indexOf(
        '_captureCampaignEntryNotificationAppOp()',
        guardCapture,
      );
      final firstInstall = run.indexOf('prepareFreshInstall(', entryCapture);
      final outerRestore = run.indexOf(
        'appStateGuard.restoreAll',
        firstInstall,
      );
      final entryRestore = run.indexOf(
        '_restoreCampaignEntryNotificationAppOp',
        outerRestore,
      );
      expect(guardCapture, greaterThanOrEqualTo(0));
      expect(entryCapture, greaterThan(guardCapture));
      expect(firstInstall, greaterThan(entryCapture));
      expect(outerRestore, greaterThan(firstInstall));
      expect(entryRestore, greaterThan(outerRestore));

      final legStart = source.indexOf(
        'Future<Map<String, Object?>> _runPermissionAppOpDivergenceLeg()',
      );
      final legEnd = source.indexOf(
        'Future<Map<String, Object?>> _runTokenRefreshLeg()',
        legStart,
      );
      expect(legStart, greaterThanOrEqualTo(0));
      expect(legEnd, greaterThan(legStart));
      final leg = source.substring(legStart, legEnd);
      expect(leg, contains('_notificationPermissionGranted()'));
      expect(leg, contains("_readNotificationAppOpMode()"));
      expect(leg, contains("_setNotificationAppOpMode('ignore')"));
      expect(leg, isNot(contains("'pm',\n      'revoke'")));

      final appOpReadStart = source.indexOf(
        'Future<String> _readNotificationAppOpMode()',
      );
      final appOpSetStart = source.indexOf(
        'Future<void> _setNotificationAppOpMode',
        appOpReadStart,
      );
      final appOpRestoreStart = source.indexOf(
        'Future<void> _restoreLegLocalNotificationAppOp()',
        appOpSetStart,
      );
      expect(appOpReadStart, greaterThanOrEqualTo(0));
      expect(appOpSetStart, greaterThan(appOpReadStart));
      expect(appOpRestoreStart, greaterThan(appOpSetStart));
      final appOpRead = source.substring(appOpReadStart, appOpSetStart);
      final appOpSet = source.substring(appOpSetStart, appOpRestoreStart);
      expect(appOpRead, contains("'get',\n      '--uid',"));
      expect(appOpRead, contains('parseAndroidNotificationUidAppOpMode'));
      expect(appOpSet, contains("'set',\n      '--uid',"));

      final mutationFlag = leg.indexOf('_g24AppOpMutated = true;');
      final mutation = leg.indexOf("_setNotificationAppOpMode('ignore')");
      final duringRead = leg.indexOf('_readNotificationAppOpMode()', mutation);
      final cursor = leg.indexOf('_deviceLogcatCursor()', duringRead);
      final relaunch = leg.indexOf('_launch(emulator)', cursor);
      final boundedRead = leg.indexOf('_flowRecordsSince(', relaunch);
      final localRestore = leg.indexOf(
        '_restoreLegLocalNotificationAppOp()',
        boundedRead,
      );
      final recovery = leg.indexOf(
        '_sendSpacedMarker(controlMarker',
        localRestore,
      );
      expect(mutationFlag, greaterThanOrEqualTo(0));
      expect(mutation, greaterThan(mutationFlag));
      expect(duringRead, greaterThan(mutation));
      expect(cursor, greaterThan(duringRead));
      expect(relaunch, greaterThan(cursor));
      expect(boundedRead, greaterThan(relaunch));
      expect(localRestore, greaterThan(boundedRead));
      expect(recovery, greaterThan(localRestore));

      for (final event in <String>[
        'PUSH_PERMISSION_OS_STATE_OVERRIDE',
        'PUSH_PERMISSION_REQUEST_RESULT',
        'PUSH_PERMISSION_OS_CHECK_FAILED',
        'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED',
      ]) {
        expect(leg, contains(event));
      }
      for (final field in <String>[
        'runtimePermissionGrantedBeforeOverride',
        'appOpModeAtCampaignEntry',
        'appOpModeBeforeOverride',
        'appOpModeDuringOverride',
        'appOpModeAfterRecovery',
        'appOpModeAfterCampaignRestore',
        'permissionOverrideRequestStatus',
        'permissionOverrideOsEnabled',
        'permissionResultStatus',
        'permissionResultGranted',
        'permissionResultOsEnabled',
        'permissionOsCheckFailedCount',
        'permissionDeniedHealthEvent',
        'disabledCardCount',
        'disabledMessageCount',
        'recoveryAlertChannel',
      ]) {
        expect(source, contains("'$field'"));
      }
    },
  );

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

  test('provider send helper accepts the v1.8.0 outcome journal', () {
    expect(
      relayJournalContainsAndroidProviderSend(
        'Aug 17 10:00:00 relay relay-server[1]: [PUSH] outcome=success '
        'attempt=1 total_attempts=3',
      ),
      isTrue,
      reason: 'inbox.go:626 is the ordinary provider-acceptance line',
    );
    expect(
      relayJournalContainsAndroidProviderSend(
        '[PUSH] outcome=success fallback=strict',
      ),
      isTrue,
      reason: 'inbox.go:664 is provider acceptance on the strict fallback',
    );
  });

  test('provider send helper rejects journals without an accepted send', () {
    for (final journal in const <String>[
      '',
      '[PUSH] outcome=failed attempts=3',
      '[PUSH] outcome=retrying attempt=1 total_attempts=3',
      '[PUSH] outcome=invalid_token reason=typed_unregistered',
      '[PUSH] provider unavailable outcome=provider_unavailable',
      '[PUSH] outcome=success_but_not_really',
      // The pre-v1.8.0 recipient-bearing line `8d86501e4` deleted. Accepting
      // it would let a rolled-back relay pass a grammar this plan re-derived.
      '[PUSH] Notification sent to 12D3KooWRecipientPee (attempt 1/3)',
    ]) {
      expect(
        relayJournalContainsAndroidProviderSend(journal),
        isFalse,
        reason: journal,
      );
    }
  });

  test('campaign provider wait passes a since-scoped journal slice', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _waitForProviderSend(');
    final end = source.indexOf('Future<String> _relayJournalSince(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    // Recipient binding lives in the journal SCOPE, not in the matched line;
    // dropping the scoping would widen the match to unrelated relay traffic.
    expect(source.substring(start, end), contains('_relayJournalSince(since)'));
    final slice = source.substring(
      end,
      source.indexOf(
        'Future<ActiveNotificationCard> _waitForNotification',
        end,
      ),
    );
    expect(slice, contains("'--since'"));
    expect(slice, contains('since.toUtc().millisecondsSinceEpoch'));
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

  test('notification channel fingerprint masks only volatile provenance', () {
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
    // Measured on emulator-5554 (SDK 36): a Settings toggle OFF then ON
    // restores mImportance exactly but leaves mUserLockedFields=4 behind.
    const afterChannelToggleCycle = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const stillBlocked = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=0, mUserLockedFields=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const beforeWithLockField = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=0, mLastNotificationUpdateTimeMs=10}
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
    expect(
      androidNotificationChannelStateSha256(
        afterChannelToggleCycle,
        packageName: 'com.mknoon.app',
      ),
      androidNotificationChannelStateSha256(
        beforeWithLockField,
        packageName: 'com.mknoon.app',
      ),
      reason: 'user-lock provenance is not channel policy',
    );
    expect(
      androidNotificationChannelStateSha256(
        stillBlocked,
        packageName: 'com.mknoon.app',
      ),
      isNot(
        androidNotificationChannelStateSha256(
          beforeWithLockField,
          packageName: 'com.mknoon.app',
        ),
      ),
      reason: 'a channel left blocked must still red the restoration verify',
    );
  });

  test('flow records survive shared-log noise and keep emission order', () {
    final logcat = <String>[
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_COORDINATOR_ATTEMPT","details":{"trigger":"startup"}}',
      'D/SomethingElse: unrelated device traffic',
      'I/flutter: [FLOW] not-json-at-all',
      'I/flutter: [FLOW] "a bare string payload"',
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_TOKEN_REFRESH_EVENT","details":{}}',
      'I/flutter: [FLOW] {"layer":"FL","details":{"trigger":"resume"}}',
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_COORDINATOR_SUCCESS","details":{"trigger":"token_refresh","tokenSha256":"deadbeef"}}',
    ].join('\n');

    final records = androidNotificationFlowRecords(logcat);
    expect(
      records.map((record) => record.event).toList(growable: false),
      <String>[
        'PUSH_REGISTER_COORDINATOR_ATTEMPT',
        'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
        'PUSH_REGISTER_COORDINATOR_SUCCESS',
      ],
    );
    expect(
      records.first.hasDetails(<String, Object?>{'trigger': 'startup'}),
      isTrue,
    );
    expect(records[1].details, isEmpty);
    // Extra proof digests must not defeat a trigger assertion.
    expect(
      records.last.hasDetails(<String, Object?>{'trigger': 'token_refresh'}),
      isTrue,
    );
    expect(
      records.last.hasDetails(<String, Object?>{'trigger': 'startup'}),
      isFalse,
    );
  });

  test('losing-path discriminator accepts the reconcile events too', () {
    String? sup(String event, String reason) =>
        androidNotificationLosingPathSuppression(
          'I/flutter: [FLOW] {"layer":"FL","event":"$event",'
          '"details":{"reason":"$reason","type":"new_message"}}',
        );

    // Measured on device: this is what the 1:1 live path actually emits when
    // it loses the race. Excluding it made tc_b13 unsatisfiable.
    expect(
      sup(
        'NOTIFICATION_LEGACY_CLAIM_RECONCILE',
        'message_event_already_claimed',
      ),
      'NOTIFICATION_LEGACY_CLAIM_RECONCILE:message_event_already_claimed',
    );
    expect(
      sup('NOTIFICATION_SUPPRESSED', 'recent_remote_push'),
      'NOTIFICATION_SUPPRESSED:recent_remote_push',
    );
    expect(
      sup('NOTIFICATION_DEFERRED', 'message_event_claim_pending'),
      'NOTIFICATION_DEFERRED:message_event_claim_pending',
      reason:
          'the background-owner-first ordering retains the live SQL row while '
          'the background isolate posts',
    );
    expect(
      sup(
        'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        'recent_duplicate_background_push',
      ),
      'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED:recent_duplicate_background_push',
    );

    // The REASON allow-list is unchanged: a novel stand-down still fails.
    expect(
      sup('NOTIFICATION_LEGACY_CLAIM_RECONCILE', 'some_new_reason'),
      isNull,
    );
    expect(sup('NOTIFICATION_SHOWN', 'message_event_already_claimed'), isNull);
    expect(
      sup('PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED', 'recent_remote_push'),
      isNull,
      reason: 'the FCM path has its own reason set',
    );
  });

  test('post-attempt union accepts either delivery path, receipt alone no', () {
    const receiptOnly =
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{}}\n'
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED","details":{"reason":"message_event_already_claimed"}}';
    // The wake arrived and then stood down: no post was ever attempted.
    expect(androidNotificationPostAttemptEvent(receiptOnly), isNull);

    expect(
      androidNotificationPostAttemptEvent(
        '$receiptOnly\n'
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1"}}',
      ),
      'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
    );
    expect(
      androidNotificationPostAttemptEvent(
        'I/flutter: [FLOW] {"layer":"FL","event":"NOTIFICATION_SHOWN","details":{"silent":false}}',
      ),
      'NOTIFICATION_SHOWN',
      reason: 'either path may win the race',
    );
    expect(androidNotificationPostAttemptEvent(''), isNull);
  });

  test('first post attempt silent flag is read from the winning path', () {
    const window = '''
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{"messageId":"m1"}}
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1","silent":false}}
I/flutter: [FLOW] {"event":"NOTIFICATION_LEGACY_CLAIM_RECONCILE","details":{"reason":"message_event_already_claimed"}}
I/flutter: [FLOW] {"event":"NOTIFICATION_SHOWN","details":{"silent":true}}
''';
    // The FIRST attempt is the alert; the later silent same-ID reconcile must
    // not be able to overwrite the verdict.
    expect(androidNotificationFirstPostAttemptSilent(window), isFalse);

    const silentWinner = '''
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1","silent":true}}
''';
    expect(androidNotificationFirstPostAttemptSilent(silentWinner), isTrue);

    // A wake receipt is not a post attempt, and a post that made no native
    // show carries no flag — both must read null rather than "audible".
    expect(
      androidNotificationFirstPostAttemptSilent(
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{"messageId":"m1"}}',
      ),
      isNull,
    );
    expect(
      androidNotificationFirstPostAttemptSilent(
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1"}}',
      ),
      isNull,
    );
  });

  test('settings switch node is addressed by its exact resource id', () {
    const dump =
        '<hierarchy>'
        '<node index="0" text="Show notifications" resource-id="com.android.settings:id/switch_text" bounds="[126,746][472,803]" />'
        '<node index="1" text="" resource-id="android:id/switch_widget" class="android.widget.Switch" checkable="true" checked="true" bounds="[848,711][985,837]" />'
        '<node index="2" text="" resource-id="com.android.settings:id/switchWidget" class="android.widget.Switch" checked="false" bounds="[859,1395][996,1521]" />'
        '</hierarchy>';

    final master = androidUiSwitchNodeByResourceId(
      dump,
      resourceId: 'android:id/switch_widget',
    );
    expect(master, isNotNull);
    expect(master!.x, (848 + 985) ~/ 2);
    expect(master.y, (711 + 837) ~/ 2);
    expect(master.checked, isTrue);

    final secondary = androidUiSwitchNodeByResourceId(
      dump,
      resourceId: 'com.android.settings:id/switchWidget',
    );
    expect(secondary!.checked, isFalse);

    expect(
      androidUiSwitchNodeByResourceId(dump, resourceId: 'android:id/absent'),
      isNull,
    );
  });

  test('channel importance is read from the package own dumpsys block', () {
    const dump = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=false
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=0}
        NotificationChannel{mId='mknoon_messages_silent', mImportance=2, mUserLockedFields=0}
      AppSettings: other.package (10124)
        NotificationChannel{mId='mknoon_messages', mImportance=0, mUserLockedFields=4}
''';

    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'mknoon_messages',
      ),
      4,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'mknoon_messages_silent',
      ),
      2,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'other.package',
        channelId: 'mknoon_messages',
      ),
      0,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'absent_channel',
      ),
      isNull,
    );
  });
}
