import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/ios_notification_payload_xcui_driver.dart'
    as ios_payload_driver;

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('physical driver accepts only the exact producer activation shape', () {
    final payload = <String, Object?>{
      'fixture_schema': 'mknoon.sims.ios-payload-private-fixture.v1',
      'aps': <String, Object?>{
        'alert': <String, Object?>{'title': 'Title', 'body': 'Body'},
        'mutable-content': 1,
        'content-available': 1,
      },
      'type': 'new_message',
      'sender_id': '12D3KooW${List<String>.filled(44, 'b').join()}',
      'message_id': 'message-1',
      'gcm.message_id': 'ios-sims-bg-${List<String>.filled(32, 'c').join()}',
      'kem': 'opaque-kem',
      'ciphertext': 'opaque-ciphertext',
      'nonce': 'opaque-nonce',
    };

    bool accepts(Map<String, Object?> value) =>
        ios_payload_driver.isExactPrivateIosApnsPayload(
          value,
          expectedTitle: 'Title',
          expectedBody: 'Body',
        );

    expect(accepts(payload), isTrue);
    for (final mutation in <void Function(Map<String, dynamic>)>[
      (value) => value.remove('gcm.message_id'),
      (value) => value['gcm.message_id'] = 'arbitrary-id',
      (value) => value['unexpected'] = 'opaque',
      (value) =>
          (value['aps']! as Map<String, dynamic>).remove('content-available'),
      (value) =>
          (value['aps']! as Map<String, dynamic>)['content-available'] = 1.0,
      (value) =>
          (value['aps']! as Map<String, dynamic>)['mutable-content'] = 1.0,
      (value) =>
          (value['aps']! as Map<String, dynamic>)['unexpected'] = 'opaque',
    ]) {
      final malformed = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
      mutation(malformed);
      expect(accepts(malformed), isFalse);
    }
  });

  test('payload digest is bound before validation-triggered recovery', () {
    final source = File(
      'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
    ).readAsStringSync();
    final producer = _between(
      source,
      'Future<void> _produceApnsPayload() async {',
      'Future<void> _runSenderProjection({required String action}) async {',
    );
    final digest = producer.indexOf(
      '_apnsPayloadSha256 = sha256.convert(bytes).toString();',
    );
    final validation = producer.indexOf('isExactPrivateIosApnsPayload(');
    expect(digest, greaterThanOrEqualTo(0));
    expect(validation, greaterThan(digest));
  });

  test('cleanup owner failures are collected after every owner runs', () async {
    final events = <String>[];
    final failures = await ios_payload_driver
        .attemptAllCleanupOwners(<Future<void> Function()>[
          () async {
            events.add('ui');
            throw const FileSystemException('fixture UI cleanup failure');
          },
          () async => events.add('sender'),
          () async {
            events.add('provider-or-recovery');
            throw const FileSystemException('fixture provider cleanup failure');
          },
          () async => events.add('candidate-app'),
        ]);

    expect(events, <String>[
      'ui',
      'sender',
      'provider-or-recovery',
      'candidate-app',
    ]);
    expect(failures, hasLength(2));
    expect(failures, everyElement(isA<FileSystemException>()));
  });

  test('provider recovery remains eligible after provider cleanup fails', () {
    expect(
      ios_payload_driver.shouldAttemptProviderRecoveryAfterCleanup(
        providerCleanupComplete: false,
        providerRecoveryComplete: false,
        receiverHandoffExists: true,
        apnsPayloadExists: true,
      ),
      isTrue,
    );
    for (final blocked
        in <({bool cleanup, bool recovery, bool handoff, bool payload})>[
          (cleanup: true, recovery: false, handoff: true, payload: true),
          (cleanup: false, recovery: true, handoff: true, payload: true),
          (cleanup: false, recovery: false, handoff: false, payload: true),
          (cleanup: false, recovery: false, handoff: true, payload: false),
        ]) {
      expect(
        ios_payload_driver.shouldAttemptProviderRecoveryAfterCleanup(
          providerCleanupComplete: blocked.cleanup,
          providerRecoveryComplete: blocked.recovery,
          receiverHandoffExists: blocked.handoff,
          apnsPayloadExists: blocked.payload,
        ),
        isFalse,
      );
    }
  });

  test(
    'diagnostic I/O failure is aggregated after unconditional cleanup runs',
    () async {
      final events = <String>[];
      final failures = await ios_payload_driver
          .attemptDiagnosticCleanupAndPrivateDeletion(
            attemptDiagnosticRetention: () {
              events.add('diagnostic');
              throw const FileSystemException('fixture diagnostic failure');
            },
            cleanupOwners: <Future<void> Function()>[
              () async => events.add('ui'),
              () async => events.add('sender'),
              () async => events.add('provider-or-recovery'),
              () async => events.add('candidate-app'),
            ],
            privateDeletionOwners: <void Function()>[
              () {
                events.add('payload-snapshot');
                throw const FileSystemException('fixture deletion failure');
              },
              () => events.add('receiver-handoff'),
              () => events.add('raw-syslog'),
            ],
          );

      expect(events, <String>[
        'diagnostic',
        'ui',
        'sender',
        'provider-or-recovery',
        'candidate-app',
        'payload-snapshot',
        'receiver-handoff',
        'raw-syslog',
      ]);
      expect(failures, hasLength(2));
      expect(failures, everyElement(isA<FileSystemException>()));
    },
  );

  test('fast recovery and retry finalizers clean after diagnostic failure', () {
    final source = File(
      'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
    ).readAsStringSync();
    final fast = _between(
      source,
      'Future<_DriverResult> run() async {',
      'void _prepareCaptureFiles()',
    );
    final recovery = _between(
      source,
      'Future<_DriverResult> _runRecoveryPhase() async {',
      'Future<_DriverResult> _runRetryPhase() async {',
    );
    final retry = _between(
      source,
      'Future<_DriverResult> _runRetryPhase() async {',
      'Future<void> _preflight() async {',
    );

    for (final phase in <String>[fast, recovery, retry]) {
      final finalizer = phase.substring(phase.lastIndexOf('} finally {'));
      expect(
        finalizer,
        contains('attemptDiagnosticCleanupAndPrivateDeletion('),
      );
      expect(finalizer, contains('attemptDiagnosticRetention: ()'));
      expect(finalizer, contains('_cleanupAllAcquiredState,'));
      expect(
        finalizer,
        contains('privateDeletionOwners: _privateDeletionOwners()'),
      );
      expect(
        finalizer.indexOf('_writeCausalDiagnostic('),
        lessThan(finalizer.indexOf('_cleanupAllAcquiredState,')),
      );
      expect(
        finalizer.indexOf('_cleanupAllAcquiredState,'),
        lessThan(
          finalizer.indexOf('privateDeletionOwners: _privateDeletionOwners()'),
        ),
      );
      expect(
        finalizer.indexOf('privateDeletionOwners: _privateDeletionOwners()'),
        lessThan(finalizer.indexOf('_throwFinalizationFailures(')),
      );
    }

    final cleanup = _between(
      source,
      'Future<void> _cleanupAllAcquiredState() async {',
      'Future<void> _removeCandidateApplicationDirectly() async {',
    );
    expect(cleanup, contains('attemptAllCleanupOwners('));
    expect(cleanup, contains('cleanupFailures.length'));
    expect(cleanup, contains('shouldAttemptProviderRecoveryAfterCleanup('));
    expect(cleanup, contains('await _runUiCleanup()'));
    expect(cleanup, contains("action: 'cleanup-sender'"));
    expect(cleanup, contains('await _runProviderCleanup()'));
    expect(cleanup, contains('await _runProviderRecovery()'));
    expect(cleanup, contains('await _removeCandidateApplicationDirectly()'));
    final ownerEvidence = _between(
      source,
      'Map<String, Object?> _cleanupOwnerEvidence()',
      'Iterable<FutureOr<void> Function()> _privateDeletionOwners()',
    );
    for (final owner in const <String>[
      'ui',
      'sender',
      'providerCleanup',
      'providerRecovery',
      'directInstall',
    ]) {
      expect(ownerEvidence, contains("'$owner':"));
    }
    for (final attempted in const <String>[
      '_uiCleanupAttempted',
      '_senderProjectionCleanupAttempted',
      '_providerCleanupAttempted',
      '_providerRecoveryAttempted',
      '_directInstallCleanupAttempted',
    ]) {
      expect(ownerEvidence, contains("'attempted': $attempted"));
    }
    final privateDeletion = _between(
      source,
      'Iterable<FutureOr<void> Function()> _privateDeletionOwners()',
      'void _throwFinalizationFailures(',
    );
    expect(privateDeletion, contains('_rawSyslog,'));
    expect(privateDeletion, contains('_payloadReceiverHandoffFile,'));
    expect(privateDeletion, contains('_deliveryReceiverHandoffFile,'));
    expect(privateDeletion, contains('_apnsPayloadFile,'));
    expect(privateDeletion, contains('_senderSeedReceiptFile,'));
    expect(privateDeletion, contains('_senderCleanupReceiptFile,'));
    expect(privateDeletion, contains('..._sensitiveIntermediates'));
    expect(privateDeletion, contains('_uiResultBundles'));
    expect(RegExp("'passDiagnosticRetained':").allMatches(source).length, 2);
    expect(source, isNot(contains("'failureDiagnosticRetained'")));
    expect(source, isNot(contains("'cleanupUnconditional'")));
  });

  test('driver is prebuilt-only and slices logs before inline reconnect', () {
    final source = File(
      'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
    ).readAsStringSync();
    final relocator = File(
      'integration_test/support/ios_xctestrun_relocator.dart',
    ).readAsStringSync();
    final campaign = File(
      'integration_test/scripts/notification_ios_payload_campaign.dart',
    ).readAsStringSync();
    expect(source, contains('iosTestWithoutBuildingArguments('));
    expect(relocator, contains("'test-without-building'"));
    expect(source, isNot(contains("'build-for-testing'")));
    expect(source, isNot(contains("'flutter',")));
    expect(source, contains("'SIMS_CHILD_BUILDS_FORBIDDEN': '1'"));
    expect(source, contains("action == 'setup'"));
    expect(source, contains('const Duration(minutes: 6)'));
    expect(source, contains('const Duration(minutes: 4)'));
    expect(source, contains('const Duration(minutes: 3)'));
    expect(source, contains("action: 'rollback'"));
    expect(source, contains('ios_receiver_bootstrap.py'));
    expect(source, contains('SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH'));
    expect(source, contains('SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE'));
    expect(source, contains("'notificationAuthorization'"));
    expect(source, contains("'notificationAlertSetting'"));
    expect(
      source,
      contains("handoff['notificationAlertSetting'] != 'enabled'"),
    );
    expect(source, contains('if (output.existsSync()) output.deleteSync()'));
    expect(source, contains('const Duration(seconds: 20)'));
    expect(source, contains('SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER'));
    expect(source, contains("'--receiver-handoff'"));
    expect(source, contains("action: 'seed-sender'"));
    expect(source, contains("action: 'cleanup-sender'"));
    expect(
      source,
      contains('mknoon.sims.ios-sender-projection-host-receipt.v1'),
    );
    expect(source, contains("'payloadProducer': _payloadProducerSha256"));
    expect(source, contains('_apnsPayloadFile,'));
    expect(source, contains('privateFile.deleteSync()'));
    expect(source, contains('expectedTitle.length > 30'));
    expect(campaign, contains("'700',\n      captureDirectory.path"));
    expect(source, contains("'700',\n      options.captureDirectory.path"));
    expect(source, contains('_makeOwnerOnly(_patchedXctestrun)'));
    expect(source, contains('..._sensitiveIntermediates'));
    expect(source, contains('_uiResultBundles'));
    expect(source, contains('resultBundle.deleteSync(recursive: true)'));

    final payloadValidation = _between(
      source,
      'final bytes = _apnsPayloadFile.readAsBytesSync();',
      'final handoff = _readJson(\n      _payloadReceiverHandoffFile,',
    );
    expect(
      payloadValidation,
      contains("expectedBody: _request['expectedBody']! as String"),
      reason: 'the outgoing APNs fallback body stays request-bound',
    );
    expect(
      payloadValidation,
      contains(
        "payloadText.contains(_request['expectedMessageText']! as String)",
      ),
      reason: 'decrypted message plaintext must not leak into APNs bytes',
    );

    final relocationEnvironment = _between(
      source,
      'uiEnvironment: <String, String>{',
      '},\n    );',
    );
    expect(
      relocationEnvironment,
      contains(
        "'MKNOON_APNS_TAP_EXPECTED_BODY':\n"
        "            _request['expectedMessageText']! as String",
      ),
      reason: 'NSE success replaces the fallback body with decrypted text',
    );
    expect(
      relocationEnvironment,
      isNot(
        contains("'MKNOON_APNS_TAP_EXPECTED_BODY': _request['expectedBody']"),
      ),
    );

    final bundleExtraction = _between(
      source,
      "final bundle = await _runCommand('plutil'",
      'if (bundle.exitCode != 0',
    );
    expect(
      RegExp("'-extract'").allMatches(bundleExtraction).length,
      1,
      reason: 'plutil bundle extraction must contain exactly one -extract',
    );

    final window = _between(
      source,
      'final tap = await _runXcui(',
      "await _runSenderProjection(action: 'cleanup-sender');",
    );
    expect(window, contains('await _stopSyslog(requireLiveCapture: true);'));
    expect(
      window.indexOf('await _stopSyslog(requireLiveCapture: true);'),
      lessThan(window.indexOf('relayDrainCount')),
    );
    expect(window, contains("_markerTimestamp(tap, 'NETWORK_RESTORED')"));
    expect(
      window,
      contains('networkRestoredMarkerOffset <= visibleMarkerOffset'),
    );
    expect(
      window,
      contains('notificationTappedMarkerOffset <= airplaneEnabledMarkerOffset'),
    );
    expect(
      window,
      contains('visibleMarkerOffset <= notificationTappedMarkerOffset'),
    );
    expect(window, contains("'inline': 'true'"));
    expect(window, contains('_hasExactLogicalMarker('));
    expect(window, contains('_uiCleanupComplete = true;'));
    expect(
      window,
      contains('final syslogVisibleOffset = _uniqueMarkerOffset('),
    );
    expect(window, contains('at: messageVisibleAt'));
    expect(window, contains("'relay_drain_before_visibility': '0'"));
    expect(window, contains("'staged_envelope': 'true'"));
    expect(
      window,
      contains('final preVisibilityWindow = rawWindow.substring('),
    );
    expect(window, contains('allMatches(preVisibilityWindow).length'));
    expect(window, isNot(contains('allMatches(rawWindow).length')));
    expect(window, isNot(contains('await _runUiCleanup()')));
    expect(source, contains("'networkRestoredAt': networkRestoredAt"));

    final evidence = _between(
      source,
      '_RedactedEvidence _writeRedactedEvidence(',
      'String _redactUiText(',
    );
    expect(evidence, contains('required int visibilityBoundaryOffset'));
    expect(evidence, contains("'pre_visibility'"));
    expect(evidence, contains("'at_or_after_visibility'"));
    expect(evidence, contains('PHASE=\$phase'));
    expect(evidence, contains('boundary=timestamped_visible_marker'));
    expect(
      evidence,
      contains(
        'relayDrainCountBeforeVisibility=\$relayDrainCountBeforeVisibility',
      ),
    );

    final fallback = _between(
      source,
      '} finally {',
      'void _prepareCaptureFiles()',
    );
    expect(fallback, contains('_writeCausalDiagnostic('));
    expect(fallback, contains('_cleanupAllAcquiredState,'));
    expect(
      fallback,
      contains('privateDeletionOwners: _privateDeletionOwners()'),
    );
  });

  test('NSE observation spans APNs expiry and fails closed on log loss', () {
    final source = File(
      'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
    ).readAsStringSync();
    final provider = File(
      'integration_test/scripts/ios_notification_provider_adapter.py',
    ).readAsStringSync();
    final observation = _between(
      source,
      'Future<DateTime> _waitForNseSignals(',
      'Future<String> _runUiCleanup()',
    );
    final stop = _between(
      source,
      'Future<void> _stopSyslog(',
      'Future<String> _runXcui(',
    );
    final boundaryCapture = _between(
      source,
      '_SyslogObservationBoundary _captureSyslogObservationBoundary()',
      'Future<void> _stopSyslog(',
    );
    final boundaryIndex = source.indexOf(
      'final nseObservationBoundary = _captureSyslogObservationBoundary();',
    );
    final providerSetupIndex = source.indexOf(
      'final providerReceipt = await _runProviderSetup();',
    );

    expect(provider, contains('APNS_DELIVERY_WINDOW_SECONDS = 120'));
    expect(source, contains('const int _apnsDeliveryWindowSeconds = 120;'));
    expect(source, contains('const int _nseTerminalMarkerGraceSeconds = 35;'));
    expect(
      observation,
      contains('providerAcceptedAt.add(_nseObservationWindow)'),
      reason: 'host observation must outlive the provider delivery window',
    );
    expect(observation, isNot(contains('Duration(seconds: 90)')));
    expect(observation, contains('final syslogExitCode = _syslogExitCode;'));
    expect(observation, contains("status: 'stream-exited'"));
    expect(observation, contains('openSync(mode: FileMode.read)'));
    expect(observation, contains('readOffset += bytes.length'));
    expect(observation, contains("status: 'timed-out'"));
    expect(observation, contains("line.contains('PUSH_NSE_DID_RECEIVE')"));
    expect(observation, contains('var didReceiveMarkers = 0;'));
    expect(observation, contains('didReceiveMarkers += 1;'));
    expect(observation, contains('var stagedRejectedMarkers = 0;'));
    expect(observation, contains("line.contains(r'\"success\":\"false\"')"));
    expect(observation, contains('stagedRejectedMarkers += 1;'));
    expect(observation, contains("status: 'nse-envelope-stage-rejected'"));
    expect(observation, contains('PUSH_NSE_CONTENT_HANDOFF'));
    expect(observation, contains(r'"authorized":"true"'));
    expect(observation, contains("status: 'ready-for-card-check'"));
    expect(boundaryIndex, greaterThanOrEqualTo(0));
    expect(providerSetupIndex, greaterThan(boundaryIndex));
    expect(
      source,
      contains(
        'final nseObservedAt = await _waitForNseSignals(\n'
        '        providerAcceptedAt,\n'
        '        nseObservationBoundary,\n'
        '      );',
      ),
    );
    expect(
      boundaryCapture,
      contains('_syslogProcess == null || _syslogExitCode != null'),
    );
    expect(
      boundaryCapture,
      contains('final byteOffset = _rawSyslog.lengthSync()'),
    );
    expect(boundaryCapture, contains('reader.readByteSync()'));
    expect(boundaryCapture, contains('precedingByte == 0x0a'));
    expect(observation, contains('var readOffset = boundary.byteOffset;'));
    expect(observation, contains('var observedBytes = 0;'));
    expect(observation, contains('observedBytes += bytes.length;'));
    expect(observation, contains('discardInitialPartialLine'));
    expect(observation, contains('discardedBoundaryFragments += 1'));
    expect(
      observation,
      contains('if (orderedProgress == 1) orderedProgress = 2;'),
    );
    expect(
      observation,
      contains('if (orderedProgress == 2) orderedProgress = 3;'),
    );
    expect(observation, contains('orderedProgress == 3'));
    expect(observation, contains('orderedReadySequences += 1;'));
    expect(observation, contains('orderedRejectedMarkers > 0'));
    expect(observation, contains('if (orderedReadySequences > 0)'));
    expect(
      observation,
      isNot(
        contains(
          'stagedMarkers > 0 &&\n'
          '            decryptOkMarkers > 0 &&\n'
          '            contentHandoffOkMarkers > 0',
        ),
      ),
      reason: 'unordered marker counts must never satisfy the APNs proof',
    );
    expect(source, contains('mknoon.sims.ios-nse-observation-diagnostic.v2'));
    expect(
      source,
      isNot(contains('mknoon.sims.ios-nse-observation-diagnostic.v1')),
    );
    expect(
      source,
      contains("'observationStartOffset': observationStartOffset"),
    );
    expect(source, contains("'orderedReadySequences': orderedReadySequences"));
    expect(
      source,
      contains("'discardedBoundaryFragments': discardedBoundaryFragments"),
    );
    expect(source, contains("'didReceive': didReceiveMarkers"));
    expect(source, contains("'envelopeStagedRejected': stagedRejectedMarkers"));
    expect(source, contains('_makeOwnerOnly(diagnostic)'));
    expect(
      source,
      contains(
        "_rejectSecretBearingText(encoded, 'NSE observation diagnostic')",
      ),
    );
    expect(source, contains('_rawSyslog.deleteSync()'));
    expect(stop, contains('bool requireLiveCapture = false'));
    expect(stop, contains('await Future<void>.delayed(Duration.zero)'));
    expect(stop, contains('final preStopExitCode = _syslogExitCode'));
    expect(stop, contains('final terminationRequested = process.kill('));
    expect(stop, contains('preStopExitCode != null || !terminationRequested'));
  });

  test(
    'provider send binds the final registered launch without relaunching',
    () {
      final source = File(
        'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
      ).readAsStringSync();
      final bootstrap = File(
        'integration_test/scripts/ios_receiver_bootstrap.py',
      ).readAsStringSync();
      final uiTests = File(
        'ios/RunnerUITests/NotificationTapUITests.swift',
      ).readAsStringSync();
      final phases = <String>[
        _between(
          source,
          'Future<_DriverResult> run() async {',
          'void _prepareCaptureFiles()',
        ),
        _between(
          source,
          'Future<_DriverResult> _runRecoveryPhase() async {',
          'Future<_DriverResult> _runRetryPhase() async {',
        ),
        _between(
          source,
          'Future<_DriverResult> _runRetryPhase() async {',
          'Future<void> _preflight() async {',
        ),
      ];

      for (final phase in phases) {
        final payloadHandoff = phase.indexOf('deliveryBinding: false');
        final payload = phase.indexOf('await _produceApnsPayload();');
        final sender = phase.indexOf("action: 'seed-sender'");
        final finalHandoff = phase.indexOf('deliveryBinding: true');
        final finalBackground = phase.indexOf(
          'await _backgroundFinalRegisteredReceiver(',
        );
        final provider = phase.indexOf('await _runProviderSetup();');
        expect(payloadHandoff, greaterThanOrEqualTo(0));
        expect(payload, greaterThan(payloadHandoff));
        expect(sender, greaterThan(payload));
        expect(finalHandoff, greaterThan(sender));
        expect(finalBackground, greaterThan(finalHandoff));
        expect(provider, greaterThan(finalBackground));
      }

      expect(source, contains('_payloadReceiverHandoffFile'));
      expect(source, contains('_deliveryReceiverHandoffFile'));
      expect(source, contains('_payloadReceiverMlKemPublicKeySha256'));
      expect(
        source,
        contains('!capturedAt.isAfter(_payloadReceiverCapturedAt)'),
      );
      expect(source, contains('_payloadReceiverHandoffFile,'));
      expect(source, contains('_deliveryReceiverHandoffFile,'));

      final captureHandoff = _between(
        source,
        'Future<void> _captureReceiverHandoff({',
        'Future<void> _produceApnsPayload() async {',
      );
      expect(
        captureHandoff,
        contains(
          "deliveryBinding ? 'capture-receiver-final' : 'capture-receiver'",
        ),
        reason:
            'only the final delivery binding may preserve the successful '
            'capture launch',
      );
      expect(bootstrap, contains('"capture-receiver-final",'));
      expect(bootstrap, contains('options.action == "capture-receiver-final"'));
      final bootstrapCapture = _between(
        bootstrap,
        'def _capture(',
        '\ndef _required(',
      );
      expect(
        bootstrapCapture,
        contains(
          'successful_handoff = primary is None and handoff is not None',
        ),
      );
      expect(
        bootstrapCapture,
        contains('if not (preserve_successful_launch and successful_handoff):'),
      );
      expect(
        bootstrapCapture.indexOf(
          'if not (preserve_successful_launch and successful_handoff):',
        ),
        lessThan(bootstrapCapture.indexOf('control.launch("cleanup")')),
        reason: 'capture failure must retain the existing cleanup launch',
      );

      final backgroundOnly = _between(
        uiTests,
        'func testBackgroundRegisteredPayloadFastPathNotificationTap()',
        'func testPayloadFastPathNotificationTap()',
      );
      expect(backgroundOnly, contains('.runningForeground'));
      expect(backgroundOnly, contains('XCUIDevice.shared.press(.home)'));
      expect(backgroundOnly, contains('registration_bound'));
      expect(backgroundOnly, isNot(contains('app.terminate()')));
      expect(backgroundOnly, isNot(contains('app.launch()')));
    },
  );

  test('receiver handoff poll leaves a bounded app-readiness cushion', () {
    final source = File(
      'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
    ).readAsStringSync();
    final captureHandoff = _between(
      source,
      'Future<void> _captureReceiverHandoff({',
      'Future<void> _produceApnsPayload() async {',
    );

    expect(captureHandoff, contains("'--timeout-seconds',"));
    expect(captureHandoff, contains("'150',"));
    expect(captureHandoff, contains('const Duration(minutes: 3)'));
    expect(
      RegExp(r'await _runCommand\(').allMatches(captureHandoff),
      hasLength(1),
      reason: 'one handoff invocation must launch exactly one child command',
    );
    expect(
      captureHandoff,
      isNot(contains('while (')),
      reason: 'the timing repair must not add a relaunch retry loop',
    );
  });

  test(
    'Plan 333 recovery reuses one-payload legs and proves device badge nil',
    () {
      final driver = File(
        'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
      ).readAsStringSync();
      final campaign = File(
        'integration_test/scripts/notification_ios_payload_campaign.dart',
      ).readAsStringSync();
      final bootstrap = File(
        'integration_test/scripts/ios_receiver_bootstrap.py',
      ).readAsStringSync();
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final uiTests = File(
        'ios/RunnerUITests/NotificationTapUITests.swift',
      ).readAsStringSync();

      expect(campaign, contains("phase: 'fast-path'"));
      expect(campaign, contains("phase: 'recovery'"));
      expect(campaign, contains("phase: 'retry'"));
      expect(campaign, contains("'--phase',\n      phase"));
      expect(
        campaign,
        contains(
          'The fast-path driver performs full provider/app/notification cleanup.',
        ),
      );
      expect(driver, contains("options.phase == 'recovery'"));
      expect(driver, contains('testObservePayloadNotificationRecovery'));
      expect(
        driver,
        contains('testVerifyPayloadNotificationRecoveryRetirement'),
      );
      expect(driver, contains("'deliveredNotificationBadgeWasNil': true"));
      expect(driver, contains("'providerPayloadBadgeAbsent': true"));
      expect(driver, contains('_hasExactStringKeys(aps, _privateIosApsKeys)'));
      expect(driver, contains("'content-available',"));
      expect(bootstrap, contains('"deliveredNotificationBadgeWasNil"'));
      expect(
        appDelegate,
        contains('notifications[0].request.content.badge == nil'),
      );
      expect(appDelegate, contains('content.badge = nil'));
      expect(appDelegate, contains('identities: []'));
      expect(
        uiTests,
        contains('func testObservePayloadNotificationRecovery()'),
      );
      expect(
        uiTests,
        contains('func testVerifyPayloadNotificationRecoveryRetirement()'),
      );
      expect(uiTests, contains('waitForApplicationBadge(1'));
      expect(uiTests, contains('waitForApplicationBadge(0'));
      expect(uiTests, contains('Mknoon recovery sentinel'));
    },
  );

  test(
    'TC-396 retry is fenced, sampled after settle, and counted end to end',
    () {
      final source = File(
        'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
      ).readAsStringSync();
      final bootstrap = File(
        'integration_test/scripts/ios_receiver_bootstrap.py',
      ).readAsStringSync();
      final inventory = File(
        'ios/Runner/IosNotificationRecoveryCoordinator.swift',
      ).readAsStringSync();
      final retry = _between(
        source,
        'Future<_DriverResult> _runRetryPhase() async {',
        'Future<void> _preflight() async {',
      );

      final firstProvider = retry.indexOf(
        'final firstProviderReceipt = await _runProviderSetup();',
      );
      final firstHandoff = retry.indexOf("requiredPresentation: 'active'");
      final firstCard = retry.indexOf("'retry-first-observe'");
      final firstInventory = retry.indexOf("proofStage: 'retry_first'");
      final privateRetry = retry.indexOf(
        'final retryReceipt = await _runProviderRetry(firstProviderReceipt);',
      );
      final secondHandoff = retry.indexOf(
        "requiredPresentation: 'trusted_passive'",
      );
      final secondCard = retry.indexOf("'retry-second-observe'");
      final secondInventory = retry.indexOf("proofStage: 'retry_second'");
      final completeCounts = retry.indexOf(
        'final counts = _directWindowCounts(rawWindow, completeWindowBoundary);',
      );
      expect(firstProvider, greaterThanOrEqualTo(0));
      expect(firstHandoff, greaterThan(firstProvider));
      expect(firstCard, greaterThan(firstHandoff));
      expect(firstInventory, greaterThan(firstCard));
      expect(
        privateRetry,
        greaterThan(firstInventory),
        reason:
            'the first-send one-card fence must authorize the private retry',
      );
      expect(secondHandoff, greaterThan(privateRetry));
      expect(secondCard, greaterThan(secondHandoff));
      expect(secondInventory, greaterThan(secondCard));
      expect(completeCounts, greaterThan(secondInventory));
      expect(
        retry.indexOf(
          'final completeWindowBoundary = _captureSyslogObservationBoundary();',
        ),
        lessThan(firstProvider),
      );

      expect(bootstrap, contains('time.sleep(3.0)'));
      expect(inventory, contains('static let stableSampleTarget = 3'));
      expect(
        inventory,
        contains('static let stableSampleIntervalMilliseconds = 500'),
      );
      expect(inventory, contains('static let settleDelayMilliseconds = 3_000'));
      expect(
        inventory,
        contains('static let observationDeadlineMilliseconds = 8_000'),
      );
      expect(retry, contains('counts.nseEnvelopeStaged != 2'));
      expect(retry, contains('counts.nseAuthorizedHandoff != 2'));
      expect(retry, contains('counts.nseActiveHandoff != 1'));
      expect(retry, contains('counts.nseTrustedPassiveHandoff != 1'));
      expect(retry, contains('counts.backgroundHandler != 2'));
      expect(retry, contains('counts.recentRemoteSuppression != 2'));
      expect(retry, contains('counts.matchingNotificationShown != 0'));

      final finalizer = retry.substring(retry.lastIndexOf('} finally {'));
      expect(
        finalizer.indexOf('_writeCausalDiagnostic('),
        lessThan(finalizer.indexOf('_cleanupAllAcquiredState,')),
      );
      expect(
        finalizer.indexOf('_cleanupAllAcquiredState,'),
        lessThan(
          finalizer.indexOf('privateDeletionOwners: _privateDeletionOwners()'),
        ),
      );
      final cleanup = _between(
        source,
        'Future<void> _cleanupAllAcquiredState() async {',
        'Future<void> _removeCandidateApplicationDirectly() async {',
      );
      expect(cleanup, contains('if (_applicationInstalled'));
      expect(cleanup, contains('if (_senderProjectionSeeded'));
      expect(cleanup, contains('if (!_providerCleanupComplete)'));
      expect(cleanup, contains('await _runProviderRecovery()'));
      expect(cleanup, contains('await _removeCandidateApplicationDirectly()'));
    },
  );

  test(
    'cleanup verifies devicectl result apps rather than echoed arguments',
    () {
      expect(
        ios_payload_driver.devicectlResultAppsAreEmpty(
          '{"info":{"arguments":["--bundle-id","com.mknoon.app"]},'
          '"result":{"matchingBundleIdentifier":"com.mknoon.app","apps":[]}}',
        ),
        isTrue,
      );
      expect(
        ios_payload_driver.devicectlResultAppsAreEmpty(
          '{"result":{"apps":[{"bundleIdentifier":"com.mknoon.app"}]}}',
        ),
        isFalse,
      );
      expect(
        () => ios_payload_driver.devicectlResultAppsAreEmpty(
          '{"result":{"matchingBundleIdentifier":"com.mknoon.app"}}',
        ),
        throwsFormatException,
      );

      final source = File(
        'integration_test/scripts/ios_notification_payload_xcui_driver.dart',
      ).readAsStringSync();
      final cleanup = _between(
        source,
        'Future<void> _verifyCandidateApplicationRemoved() async {',
        'Future<File> _installedApplicationsJson',
      );
      expect(
        cleanup,
        contains('devicectlResultAppsAreEmpty(apps.readAsStringSync())'),
      );
      expect(
        cleanup,
        isNot(contains('apps.readAsStringSync().contains(_bundleId)')),
      );
    },
  );

  test(
    'XCUITest restores inline after visibility and retains fallback cleanup',
    () {
      final source = File(
        'ios/RunnerUITests/NotificationTapUITests.swift',
      ).readAsStringSync();
      final tap = _between(
        source,
        'func testPayloadFastPathNotificationTap()',
        'func testRestorePayloadFastPathNetwork()',
      );
      expect(tap, contains('try setAirplaneMode(true)'));
      expect(tap, contains('defer'));
      expect(tap, contains('networkRestored = try setAirplaneMode(false)'));
      expect(tap, contains('app.wait(for: .notRunning'));
      expect(tap, contains('"NETWORK_RESTORED"'));
      expect(tap, contains('"inline": "true"'));
      expect(
        tap.indexOf('defer {'),
        lessThan(tap.indexOf('guard configuredNotificationIsPresent()')),
        reason: 'restoration must already be registered before airplane mode',
      );
      expect(
        tap.indexOf('mustRestoreNetwork = true'),
        lessThan(tap.indexOf('guard try setAirplaneMode(true)')),
      );
      final finalization = _between(
        tap,
        'defer {',
        'guard configuredNotificationIsPresent()',
      );
      expect(
        finalization.indexOf('app.terminate()'),
        lessThan(finalization.indexOf('try setAirplaneMode(false)')),
      );
      expect(tap, contains('guard message.waitForExistence(timeout: 20) else'));
      expect(tap, contains('MKNOON_258'));

      final cleanup = _between(
        source,
        'func testRestorePayloadFastPathNetwork()',
        'func testReactionNotificationTap()',
      );
      expect(cleanup, contains('try setAirplaneMode(false)'));
      expect(cleanup, contains('app.terminate()'));
      expect(cleanup, contains('app_terminated'));
      expect(cleanup, contains('"inline": "false"'));
    },
  );

  test('airplane switch automation is exact, localized, and tri-state', () {
    final source = File(
      'ios/RunnerUITests/NotificationTapUITests.swift',
    ).readAsStringSync();
    final setter = _between(
      source,
      'private func setAirplaneMode(',
      'private func airplaneModeToggle(',
    );
    final decoder = _between(
      source,
      'private func airplaneModeToggle(',
      'private func emitPlan258Marker(',
    );

    expect(decoder, contains('matching(identifier: "airplane-mode-button")'));
    expect(decoder, contains(') -> Bool?'));
    expect(decoder, contains('CONTROL_CENTER_STATUS_AIRPLANE_MODE_ON'));
    expect(decoder, contains('CONTROL_CENTER_STATUS_AIRPLANE_MODE_OFF'));
    expect(decoder, contains('return isSelected ? true : nil'));
    expect(setter, contains('guard let initialState = airplaneToggleIsOn('));
    expect(
      setter,
      contains('currentToggle = airplaneModeToggle(in: springboard)'),
    );
    expect(
      RegExp(r'\.tap\(\)').allMatches(setter),
      hasLength(1),
      reason: 'state polling must never toggle airplane mode a second time',
    );
    expect(
      source,
      contains('An unknown switch value must never be collapsed to off'),
    );
  });

  test(
    'NSE emits direct staging outcome and pass requires disposable cleanup',
    () {
      final nse = File(
        'ios/NotificationService/NotificationService.swift',
      ).readAsStringSync();
      final resolver = File(
        'ios/NotificationService/NotificationPreviewResolver.swift',
      ).readAsStringSync();
      expect(nse, contains('PUSH_NSE_DID_RECEIVE'));
      expect(nse, contains('PUSH_NSE_ENVELOPE_STAGED'));
      expect(nse, contains('PUSH_NSE_CONTENT_HANDOFF'));
      expect(nse, contains('"authorized": didApplyPreview ? "true" : "false"'));
      expect(nse, contains('"success": envelopeStaged ? "true" : "false"'));
      expect(
        nse.indexOf('PUSH_NSE_DID_RECEIVE'),
        lessThan(nse.indexOf('NseMailboxWakeClassifier.isExactFixedWake')),
        reason:
            'NSE entry must be public before any classifier or store access',
      );
      // Plan 373's fixed-wake branch hands the claimed handler to its own
      // final-effect/generic owners earlier in the file; the rich completion
      // this proof gates is the apply-path handler call after the marker.
      expect(
        nse.indexOf('PUSH_NSE_CONTENT_HANDOFF'),
        lessThan(
          nse.indexOf(
            'contentHandler: handler',
            nse.indexOf('recentRemoteShownMarkerStore?.mark('),
          ),
        ),
        reason: 'the proof must be emitted before NSE completion can suspend',
      );
      expect(resolver, contains('func nsePublicProofPayload('));
      expect(resolver, contains('"[FLOW_PROOF] %{public}@"'));
      expect(
        resolver,
        contains(
          'case "PUSH_NSE_DECRYPT_OK", "PUSH_NSE_DECRYPT_FAIL", '
          '"PUSH_NSE_TIMEOUT":',
        ),
      );
      expect(resolver, contains('case "PUSH_NSE_ENVELOPE_STAGED":'));
      expect(resolver, contains('case "PUSH_NSE_DID_RECEIVE":'));
      expect(resolver, contains('case "PUSH_NSE_CONTENT_HANDOFF":'));
      expect(
        resolver,
        isNot(contains('"[FLOW_PROOF] %{public}@", json')),
        reason: 'the full diagnostic JSON can contain a push ID',
      );

      final support = File(
        'integration_test/support/ios_notification_payload_campaign.dart',
      ).readAsStringSync();
      expect(support, contains("'dedicatedDisposableReceiver': true"));
      expect(support, contains("'candidateAppRemoved': true"));
      expect(support, contains("'providerCleanupAutomated'"));
      expect(support, contains("'testStateCleared'"));
    },
  );

  test(
    'payload card lookup refreshes SpringBoard without leaking fixture text',
    () {
      final source = File(
        'ios/RunnerUITests/NotificationTapUITests.swift',
      ).readAsStringSync();
      final selector = _between(
        source,
        'func testPayloadFastPathNotificationTap()',
        'func testRestorePayloadFastPathNetwork()',
      );
      final lookup = _between(
        source,
        'private func configuredNotificationIsPresent()',
        'private func setAirplaneMode(',
      );
      final tap = _between(
        source,
        'private func tapExistingNotification(',
        'private func allowNotificationPromptIfPresent(',
      );
      final tapNotification = _between(
        source,
        'private func tapNotification(',
        'private func tapVisibleNotification(',
      );
      final textLookup = _between(
        source,
        'private func notificationTextExists(',
        'private func tapVisibleNotificationChrome(',
      );

      expect(
        selector,
        contains('guard configuredNotificationIsPresent() else'),
      );
      expect(
        selector.indexOf('guard configuredNotificationIsPresent() else'),
        lessThan(selector.indexOf('emitPlan258Marker("APNS_DELIVERED"')),
      );
      expect(lookup, contains('timeout: 4'));
      expect(lookup, contains('for attempt in 2...3'));
      expect(lookup, contains('openNotificationCenter(from: springboard)'));
      expect(lookup, contains('revealNotificationHistory(from: springboard)'));
      expect(lookup, contains('"notification_history"'));
      expect(lookup, contains('"CARD_LOOKUP"'));
      expect(lookup, contains('"title_matched"'));
      expect(lookup, contains('"body_matched"'));
      expect(lookup, isNot(contains('XCTAssert')));
      expect(lookup, isNot(contains('.tap()')));
      expect(lookup, isNot(contains('debugDescription')));
      expect(textLookup, contains('while Date() < deadline'));
      expect(textLookup, contains('if match.exists'));
      expect(textLookup, isNot(contains('waitForExistence')));
      expect(tap, contains('revealNotificationHistory(from: springboard)'));
      expect(tap, contains('bodyMatched = notificationTextExists('));
      expect(tap, contains('expectedBody: expectedBody'));
      expect(
        tapNotification,
        contains('revealNotificationHistory(from: springboard)'),
      );
      expect(
        tapNotification,
        contains('let bodyMatched = expectedBody == nil'),
      );
      expect(tapNotification, contains('timeout: 4'));
      expect(tapNotification, contains('timeout: 10'));
      expect(tap, contains('title_matched=true body_matched=true'));
      expect(tap, isNot(contains('title=%@ body=%@')));
      expect(tap, isNot(contains(r'\(expectedBody)')));
      expect(tap, isNot(contains(r'\(title)')));
      expect(source, contains(r'title_configured=\(!title.isEmpty)'));
      expect(source, isNot(contains(r'mode=\(mode) title=\(title)')));
    },
  );

  test('physical test bundles use the app development team', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final configurations = project
        .split('isa = XCBuildConfiguration;')
        .skip(1)
        .toList(growable: false);
    for (final bundleId in const <String>[
      'com.mknoon.app.RunnerTests',
      'com.mknoon.app.RunnerUITests',
    ]) {
      final matching = configurations
          .where((configuration) => configuration.contains(bundleId))
          .toList(growable: false);
      expect(matching, hasLength(3), reason: '$bundleId must have three modes');
      for (final configuration in matching) {
        expect(
          configuration,
          contains('DEVELOPMENT_TEAM = 397R9Q4WMX;'),
          reason: '$bundleId must sign with the app development team',
        );
      }
    }
  });
}
