#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../support/ios_notification_payload_campaign.dart';
import '../support/ios_xctestrun_relocator.dart';

const String _resultPrefix = 'IOS_PAYLOAD_DRIVER_RESULT_JSON=';
const String _bundleId = 'com.mknoon.app';
const String _receiverHandoffSchema =
    'mknoon.sims.ios-provider-receiver-handoff.v2';
const String _providerRecoveryReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-provider-recovery-receipt.v1';
final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
const int _apnsDeliveryWindowSeconds = 120;
const int _nseTerminalMarkerGraceSeconds = 35;
const Duration _nseObservationWindow = Duration(
  seconds: _apnsDeliveryWindowSeconds + _nseTerminalMarkerGraceSeconds,
);
const Set<String> _privateIosApnsPayloadKeys = <String>{
  'fixture_schema',
  'aps',
  'type',
  'sender_id',
  'message_id',
  'gcm.message_id',
  'kem',
  'ciphertext',
  'nonce',
};
const Set<String> _privateIosApsKeys = <String>{
  'alert',
  'mutable-content',
  'content-available',
};
const Set<String> _privateIosAlertKeys = <String>{'title', 'body'};
final RegExp _privateIosPeerPattern = RegExp(
  r'^(?:12D3KooW[1-9A-HJ-NP-Za-km-z]{44}|Qm[1-9A-HJ-NP-Za-km-z]{44})$',
);
final RegExp _privateIosGcmMessageIdPattern = RegExp(
  r'^ios-sims-bg-[0-9a-f]{32}$',
);

bool _hasExactStringKeys(Map<dynamic, dynamic> value, Set<String> expected) {
  final keys = value.keys;
  if (keys.any((key) => key is! String)) return false;
  final actual = keys.cast<String>().toSet();
  return actual.difference(expected).isEmpty &&
      expected.difference(actual).isEmpty;
}

bool _isExactIntegerOne(Object? value) => value is int && value == 1;

bool isExactPrivateIosApnsPayload(
  Map<String, Object?> payload, {
  required String expectedTitle,
  required String expectedBody,
}) {
  if (!_hasExactStringKeys(payload, _privateIosApnsPayloadKeys) ||
      payload['fixture_schema'] !=
          'mknoon.sims.ios-payload-private-fixture.v1' ||
      payload['type'] != 'new_message') {
    return false;
  }
  final sender = payload['sender_id'];
  final gcmMessageId = payload['gcm.message_id'];
  if (sender is! String ||
      !_privateIosPeerPattern.hasMatch(sender) ||
      gcmMessageId is! String ||
      !_privateIosGcmMessageIdPattern.hasMatch(gcmMessageId)) {
    return false;
  }
  for (final key in const <String>[
    'message_id',
    'kem',
    'ciphertext',
    'nonce',
  ]) {
    final value = payload[key];
    if (value is! String || value.isEmpty) return false;
  }
  final aps = payload['aps'];
  if (aps is! Map<dynamic, dynamic> ||
      !_hasExactStringKeys(aps, _privateIosApsKeys) ||
      !_isExactIntegerOne(aps['mutable-content']) ||
      !_isExactIntegerOne(aps['content-available'])) {
    return false;
  }
  final alert = aps['alert'];
  return alert is Map<dynamic, dynamic> &&
      _hasExactStringKeys(alert, _privateIosAlertKeys) &&
      alert['title'] == expectedTitle &&
      alert['body'] == expectedBody;
}

Future<List<Object>> attemptAllCleanupOwners(
  Iterable<FutureOr<void> Function()> cleanupOwners,
) async {
  final failures = <Object>[];
  for (final cleanupOwner in cleanupOwners) {
    try {
      await cleanupOwner();
    } on Object catch (error) {
      failures.add(error);
    }
  }
  return failures;
}

bool shouldAttemptProviderRecoveryAfterCleanup({
  required bool providerCleanupComplete,
  required bool providerRecoveryComplete,
  required bool receiverHandoffExists,
  required bool apnsPayloadExists,
}) =>
    !providerCleanupComplete &&
    !providerRecoveryComplete &&
    receiverHandoffExists &&
    apnsPayloadExists;

bool devicectlResultAppsAreEmpty(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('devicectl result must be a JSON object');
  }
  final result = decoded['result'];
  if (result is! Map<String, dynamic>) {
    throw const FormatException('devicectl result.result must be an object');
  }
  final apps = result['apps'];
  if (apps is! List<dynamic>) {
    throw const FormatException('devicectl result.apps must be a list');
  }
  return apps.isEmpty;
}

Future<List<Object>> attemptDiagnosticCleanupAndPrivateDeletion({
  required void Function() attemptDiagnosticRetention,
  required Iterable<FutureOr<void> Function()> cleanupOwners,
  required Iterable<FutureOr<void> Function()> privateDeletionOwners,
}) async {
  final failures = <Object>[];
  try {
    attemptDiagnosticRetention();
  } on Object catch (error) {
    failures.add(error);
  }
  failures.addAll(await attemptAllCleanupOwners(cleanupOwners));
  for (final privateDeletionOwner in privateDeletionOwners) {
    try {
      await privateDeletionOwner();
    } on Object catch (error) {
      failures.add(error);
    }
  }
  return failures;
}

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run ios_notification_payload_xcui_driver.dart '
      '--receiver <physical-udid> --peer-device <id> '
      '--application-binary <Runner.app> --xctestrun <file> '
      '--provider-driver <executable> --provider-request <json> '
      '--staging-manifest <json> --relay-target <target> '
      '--relay-key <file> --run-id <id> --nonce <nonce> '
      '--phase fast-path|recovery|retry --output <receipt.json> '
      '--capture-directory <directory>',
    );
    return;
  }

  late final _DriverResult result;
  try {
    final options = _DriverOptions.parse(args);
    result = await _IosPayloadDriver(options).run();
  } on _DriverBlocked catch (error) {
    result = _DriverResult.blocked(error.blocker, error.detail);
  } on _DriverFailure catch (error) {
    result = _DriverResult.failed(error.detail, error.assertionsAttempted);
  } on ProcessException catch (error) {
    result = _DriverResult.blocked(
      'missingDriver',
      'A required iOS automation command could not start: ${error.message}',
    );
  } on Object catch (error, stackTrace) {
    if (args.contains('--verbose')) stderr.writeln(stackTrace);
    result = _DriverResult.failed(
      'The iOS physical automation stopped without a typed verdict: '
      '${error.runtimeType}.',
      0,
    );
  }
  stdout.writeln('$_resultPrefix${jsonEncode(result.json)}');
  exitCode = result.exitCode;
}

final class _DriverOptions {
  const _DriverOptions({
    required this.receiverDeviceId,
    required this.peerDeviceId,
    required this.application,
    required this.xctestrun,
    required this.providerDriver,
    required this.providerRequest,
    required this.stagingManifest,
    required this.payloadProducer,
    required this.relayTarget,
    required this.relayKey,
    required this.runId,
    required this.nonce,
    required this.output,
    required this.captureDirectory,
    required this.phase,
    required this.verbose,
  });

  factory _DriverOptions.parse(List<String> args) => _DriverOptions(
    receiverDeviceId: _requiredValue(args, '--receiver'),
    peerDeviceId: _requiredValue(args, '--peer-device'),
    application: Directory(
      _requiredValue(args, '--application-binary'),
    ).absolute,
    xctestrun: File(_requiredValue(args, '--xctestrun')).absolute,
    providerDriver: File(_requiredValue(args, '--provider-driver')).absolute,
    providerRequest: File(_requiredValue(args, '--provider-request')).absolute,
    stagingManifest: File(_requiredValue(args, '--staging-manifest')).absolute,
    payloadProducer: File(
      _requiredEnvironment('SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER'),
    ).absolute,
    relayTarget: _requiredValue(args, '--relay-target'),
    relayKey: File(_requiredValue(args, '--relay-key')).absolute,
    runId: _requiredValue(args, '--run-id'),
    nonce: _requiredValue(args, '--nonce'),
    output: File(_requiredValue(args, '--output')).absolute,
    captureDirectory: Directory(
      _requiredValue(args, '--capture-directory'),
    ).absolute,
    phase: _requiredValue(args, '--phase'),
    verbose: args.contains('--verbose'),
  );

  final String receiverDeviceId;
  final String peerDeviceId;
  final Directory application;
  final File xctestrun;
  final File providerDriver;
  final File providerRequest;
  final File stagingManifest;
  final File payloadProducer;
  final String relayTarget;
  final File relayKey;
  final String runId;
  final String nonce;
  final File output;
  final Directory captureDirectory;
  final String phase;
  final bool verbose;
}

final class _IosPayloadDriver {
  _IosPayloadDriver(this.options);

  final _DriverOptions options;

  late final Map<String, Object?> _request;
  late final Map<String, Object?> _staging;
  late final String _applicationSha256;
  late final String _requestSha256;
  late final File _patchedXctestrun;
  late final File _rawSyslog;
  late final File _providerReceiptFile;
  late final File _providerCleanupReceiptFile;
  late final File _providerRetryReceiptFile;
  late final File _providerRecoveryReceiptFile;
  late final File _payloadReceiverHandoffFile;
  late final File _deliveryReceiverHandoffFile;
  late final String _receiverHandoffNonce;
  late final String _payloadReceiverPeerIdSha256;
  late final String _payloadReceiverMlKemPublicKeySha256;
  late final String _payloadReceiverNotificationAuthorization;
  late final DateTime _payloadReceiverCapturedAt;
  late final File _apnsPayloadFile;
  late final String _apnsPayloadSha256;
  late final String _payloadProducerSha256;
  late final String _senderPeerIdSha256;
  late final File _senderSeedReceiptFile;
  late final File _senderCleanupReceiptFile;
  late final File _notificationRecoveryReceiptFile;
  late final File _notificationRetryFirstReceiptFile;

  Process? _syslogProcess;
  int? _syslogExitCode;
  bool _uiCleanupAttempted = false;
  bool _uiCleanupComplete = false;
  bool _providerSetupComplete = false;
  bool _providerCleanupAttempted = false;
  bool _providerCleanupComplete = false;
  bool _senderProjectionSeeded = false;
  bool _senderProjectionCleanupAttempted = false;
  bool _senderProjectionCleaned = false;
  bool _providerRecoveryAttempted = false;
  bool _providerRecoveryComplete = false;
  bool _directInstallCleanupAttempted = false;
  bool _directInstallCleanupComplete = false;
  bool _applicationInstalled = false;
  int _assertionsAttempted = 0;
  final List<File> _uiLogs = <File>[];
  final List<File> _sensitiveIntermediates = <File>[];
  final List<Directory> _uiResultBundles = <Directory>[];

  Future<_DriverResult> run() async {
    if (options.phase == 'recovery') {
      return _runRecoveryPhase();
    }
    if (options.phase == 'retry') {
      return _runRetryPhase();
    }
    await _preflight();
    _prepareCaptureFiles();

    try {
      await _verifyAndPatchCentralProducts();
      await _installExactApplication();
      await _startSyslog();

      final prepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'prepare',
      );
      _assertionsAttempted += 1;
      if (!_hasMarker(prepare, 'READY')) {
        throw _DriverFailure(
          'The physical XCUITest completed without the automated permission '
          'and background readiness marker.',
          _assertionsAttempted,
        );
      }
      await _captureReceiverHandoff(
        output: _payloadReceiverHandoffFile,
        deliveryBinding: false,
      );
      await _produceApnsPayload();
      await _runSenderProjection(action: 'seed-sender');
      final postSeedPrepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'post-seed-prepare',
      );
      if (!_hasMarker(postSeedPrepare, 'READY')) {
        throw _DriverFailure(
          'The receiver was not returned to background notification readiness '
          'after private sender projection setup.',
          _assertionsAttempted,
        );
      }
      await _captureReceiverHandoff(
        output: _deliveryReceiverHandoffFile,
        deliveryBinding: true,
      );
      await _backgroundFinalRegisteredReceiver('final-registered-background');
      final nseObservationBoundary = _captureSyslogObservationBoundary();
      final providerReceipt = await _runProviderSetup();
      _assertionsAttempted += 1;
      final providerAcceptedAt = _utc(
        providerReceipt['acceptedAt'],
        'provider receipt acceptedAt',
      );
      final nseObservedAt = await _waitForNseSignals(
        providerAcceptedAt,
        nseObservationBoundary,
      );
      _assertionsAttempted += 1;

      _uiCleanupAttempted = true;
      final tap = await _runXcui(
        'testPayloadFastPathNotificationTap',
        'payload-tap',
      );
      _assertionsAttempted += 3;
      final apnsDeliveredAt = _markerTimestamp(tap, 'APNS_DELIVERED');
      final airplaneEnabledAt = _markerTimestamp(tap, 'AIRPLANE_ENABLED');
      final notificationTappedAt = _markerTimestamp(tap, 'TAPPED');
      final messageVisibleAt = _markerTimestamp(tap, 'VISIBLE');
      final networkRestoredAt = _markerTimestamp(tap, 'NETWORK_RESTORED');
      if (apnsDeliveredAt == null ||
          airplaneEnabledAt == null ||
          notificationTappedAt == null ||
          messageVisibleAt == null ||
          networkRestoredAt == null) {
        throw _DriverFailure(
          'The XCUITest omitted one or more APNs, airplane, tap, exact '
          'message-visibility, or inline network-restoration markers.',
          _assertionsAttempted,
        );
      }
      final apnsDeliveredMarkerOffset = _markerOffset(
        tap,
        'APNS_DELIVERED',
        at: apnsDeliveredAt,
      );
      final airplaneEnabledMarkerOffset = _markerOffset(
        tap,
        'AIRPLANE_ENABLED',
        at: airplaneEnabledAt,
      );
      final notificationTappedMarkerOffset = _markerOffset(
        tap,
        'TAPPED',
        at: notificationTappedAt,
      );
      final visibleMarkerOffset = _markerOffset(
        tap,
        'VISIBLE',
        at: messageVisibleAt,
      );
      final networkRestoredMarkerOffset = _markerOffset(
        tap,
        'NETWORK_RESTORED',
        at: networkRestoredAt,
      );
      if (apnsDeliveredMarkerOffset == null ||
          airplaneEnabledMarkerOffset == null ||
          notificationTappedMarkerOffset == null ||
          visibleMarkerOffset == null ||
          networkRestoredMarkerOffset == null ||
          airplaneEnabledMarkerOffset <= apnsDeliveredMarkerOffset ||
          notificationTappedMarkerOffset <= airplaneEnabledMarkerOffset ||
          visibleMarkerOffset <= notificationTappedMarkerOffset ||
          networkRestoredMarkerOffset <= visibleMarkerOffset ||
          airplaneEnabledAt.isBefore(apnsDeliveredAt) ||
          notificationTappedAt.isBefore(airplaneEnabledAt) ||
          messageVisibleAt.isBefore(notificationTappedAt) ||
          networkRestoredAt.isBefore(messageVisibleAt) ||
          !_hasExactLogicalMarker(
            tap,
            'APNS_DELIVERED',
            at: apnsDeliveredAt,
            fields: const <String, String>{'card_observed': 'true'},
          ) ||
          !_hasExactLogicalMarker(
            tap,
            'AIRPLANE_ENABLED',
            at: airplaneEnabledAt,
            fields: const <String, String>{'before_tap': 'true'},
          ) ||
          !_hasExactLogicalMarker(
            tap,
            'TAPPED',
            at: notificationTappedAt,
            fields: const <String, String>{'automated': 'true'},
          ) ||
          !_hasExactLogicalMarker(
            tap,
            'VISIBLE',
            at: messageVisibleAt,
            fields: const <String, String>{
              'relay_drain_before_visibility': '0',
              'staged_envelope': 'true',
            },
          ) ||
          !_hasExactLogicalMarker(
            tap,
            'NETWORK_RESTORED',
            at: networkRestoredAt,
            fields: const <String, String>{
              'airplane': 'false',
              'app_terminated': 'true',
              'inline': 'true',
            },
          )) {
        throw _DriverFailure(
          'The payload selector did not prove ordered inline network '
          'restoration and app termination after exact message visibility.',
          _assertionsAttempted,
        );
      }
      _uiCleanupComplete = true;

      // The selector restores connectivity only after VISIBLE. Freeze the log
      // stream after it exits, then cut the no-drain causal window at the same
      // timestamped VISIBLE marker observed in the live device stream. A
      // reconnect drain after visibility is therefore outside this assertion.
      await _stopSyslog(requireLiveCapture: true);
      final rawWindow = _rawSyslog.readAsStringSync();
      final syslogVisibleOffset = _uniqueMarkerOffset(
        rawWindow,
        'VISIBLE',
        at: messageVisibleAt,
        fields: const <String, String>{
          'relay_drain_before_visibility': '0',
          'staged_envelope': 'true',
        },
      );
      if (syslogVisibleOffset == null) {
        throw _DriverFailure(
          'The live device stream omitted the current timestamped visibility '
          'boundary required for causal relay-drain slicing.',
          _assertionsAttempted,
        );
      }
      final preVisibilityWindow = rawWindow.substring(0, syslogVisibleOffset);
      final relayDrainCount = RegExp(
        'P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
      ).allMatches(preVisibilityWindow).length;
      if (relayDrainCount != 0) {
        throw _DriverFailure(
          'The recipient emitted a relay-drain success inside the APNs-to-'
          'visibility airplane-mode window.',
          _assertionsAttempted,
        );
      }

      await _runSenderProjection(action: 'cleanup-sender');
      final providerCleanup = await _runProviderCleanup();
      await _verifyCandidateApplicationRemoved();
      _assertionsAttempted += 1;

      final evidence = _writeRedactedEvidence(
        rawWindow,
        visibilityBoundaryOffset: syslogVisibleOffset,
        relayDrainCountBeforeVisibility: relayDrainCount,
      );
      final providerReceiptSha = _sha256File(_providerReceiptFile);
      final cleanupReceiptSha = _sha256File(_providerCleanupReceiptFile);
      final relayLog = _receiptMember(
        _providerReceiptFile,
        providerReceipt['relayLogPath'],
        'relay log',
      );
      if (_sha256File(relayLog) != providerReceipt['relayLogSha256']) {
        throw _DriverFailure(
          'The redacted relay log does not match the provider receipt digest.',
          _assertionsAttempted,
        );
      }
      _rejectSecretBearingText(relayLog.readAsStringSync(), 'relay log');

      final receipt = <String, Object?>{
        'schema': iosNotificationAutomationReceiptSchema,
        'scenario': iosNotificationPayloadScenario,
        'status': 'passed',
        'platform': 'ios',
        'receiverPhysical': true,
        'runId': options.runId,
        'nonce': options.nonce,
        'receiverDeviceId': options.receiverDeviceId,
        'peerDeviceId': options.peerDeviceId,
        'preparedApplicationSha256': _applicationSha256,
        'providerRequestSha256': _requestSha256,
        'payloadProducerSha256': _payloadProducerSha256,
        'apnsPayloadSha256': _apnsPayloadSha256,
        'childBuildCount': 0,
        'manualActionCount': 0,
        'checks': <String, Object?>{
          'appSetupAutomated': providerReceipt['appSetupAutomated'] == true,
          'notificationPermissionAutomated': true,
          'apnsDelivered': true,
          'nseProcessObserved': true,
          'nseStagingOn': true,
          'nse04P0WithStagingOn': true,
          'airplaneModeBeforeTap': true,
          'notificationTapAutomated': true,
          'messageVisibleFromStagedEnvelope': true,
          'relayDrainCountBeforeVisibility': relayDrainCount,
          'networkRestored': _uiCleanupComplete,
          'appTerminatedAfterCapture': _uiCleanupComplete,
          'providerCleanupAutomated': _providerCleanupComplete,
          'testStateCleared':
              providerCleanup['appTestStateCleared'] == true &&
              providerCleanup['notificationStateCleared'] == true &&
              providerCleanup['relayFixtureCleared'] == true,
        },
        'timestamps': <String, Object?>{
          'providerAcceptedAt': providerAcceptedAt.toIso8601String(),
          'nseStagedAt': nseObservedAt.toIso8601String(),
          'apnsDeliveredAt': apnsDeliveredAt.toIso8601String(),
          'airplaneEnabledAt': airplaneEnabledAt.toIso8601String(),
          'notificationTappedAt': notificationTappedAt.toIso8601String(),
          'messageVisibleAt': messageVisibleAt.toIso8601String(),
          'networkRestoredAt': networkRestoredAt.toIso8601String(),
        },
        'evidenceSha256': <String, String>{
          'preparedApplication': _applicationSha256,
          'payloadProducer': _payloadProducerSha256,
          'apnsPayload': _apnsPayloadSha256,
          'providerReceipt': providerReceiptSha,
          'providerCleanupReceipt': cleanupReceiptSha,
          'relayLog': _sha256File(relayLog),
          'nseLog': _sha256File(evidence.nseLog),
          'recipientLog': _sha256File(evidence.recipientLog),
          'uiAutomationLog': _sha256File(evidence.uiLog),
          'stagedEnvelope': providerReceipt['stagedEnvelopeSha256']! as String,
        },
      };
      final receiptValidation = validateIosNotificationAutomationReceipt(
        receipt,
        runId: options.runId,
        nonce: options.nonce,
        receiverDeviceId: options.receiverDeviceId,
        peerDeviceId: options.peerDeviceId,
        preparedApplicationSha256: _applicationSha256,
        providerRequestSha256: _requestSha256,
        payloadProducerSha256: _payloadProducerSha256,
        apnsPayloadSha256: _apnsPayloadSha256,
      );
      if (!receiptValidation.ok) {
        throw _DriverFailure(
          'The generated automation receipt failed closed: '
          '${receiptValidation.detail}',
          _assertionsAttempted,
        );
      }
      options.output.writeAsStringSync('${jsonEncode(receipt)}\n', flush: true);
      return _DriverResult.passed(_assertionsAttempted);
    } finally {
      final diagnostic = File(
        '${options.captureDirectory.path}/direct-notification-diagnostic.redacted.json',
      );
      final finalizationFailures =
          await attemptDiagnosticCleanupAndPrivateDeletion(
            attemptDiagnosticRetention: () {
              if (!options.output.existsSync() || !diagnostic.existsSync()) {
                _writeCausalDiagnostic(
                  status: options.output.existsSync() ? 'passed' : 'failed',
                );
              }
            },
            cleanupOwners: <FutureOr<void> Function()>[
              _cleanupAllAcquiredState,
              () => _stopSyslog(),
            ],
            privateDeletionOwners: _privateDeletionOwners(),
          );
      _throwFinalizationFailures(finalizationFailures);
    }
  }

  void _prepareCaptureFiles() {
    options.captureDirectory.createSync(recursive: true);
    final captureMode = Process.runSync('chmod', <String>[
      '700',
      options.captureDirectory.path,
    ]);
    if (captureMode.exitCode != 0) {
      throw const _DriverBlocked(
        'environment',
        'The private iOS capture directory could not be made owner-only.',
      );
    }
    options.output.parent.createSync(recursive: true);
    if (options.output.existsSync()) options.output.deleteSync();
    _rawSyslog = File('${options.captureDirectory.path}/recipient.raw.log');
    _providerReceiptFile = File(
      '${options.captureDirectory.path}/provider_receipt.json',
    );
    _providerCleanupReceiptFile = File(
      '${options.captureDirectory.path}/provider_cleanup_receipt.json',
    );
    _providerRetryReceiptFile = File(
      '${options.captureDirectory.path}/provider_retry_receipt.json',
    );
    _providerRecoveryReceiptFile = File(
      '${options.captureDirectory.path}/provider_recovery_receipt.json',
    );
    final handoffBinding = sha256
        .convert(
          utf8.encode(
            '${options.runId}\u0000${options.nonce}\u0000'
            '${options.receiverDeviceId}',
          ),
        )
        .toString();
    _receiverHandoffNonce = 'ios-handoff-${handoffBinding.substring(0, 32)}';
    _payloadReceiverHandoffFile = File(
      '${options.captureDirectory.path}/.ios-provider-payload-handoff-'
      '${handoffBinding.substring(0, 24)}.json',
    );
    _deliveryReceiverHandoffFile = File(
      '${options.captureDirectory.path}/.ios-provider-delivery-handoff-'
      '${handoffBinding.substring(0, 24)}.json',
    );
    _apnsPayloadFile = File(
      '${options.captureDirectory.path}/.ios-provider-payload-'
      '${handoffBinding.substring(0, 24)}.json',
    );
    _senderSeedReceiptFile = File(
      '${options.captureDirectory.path}/sender_projection_seed_receipt.json',
    );
    _senderCleanupReceiptFile = File(
      '${options.captureDirectory.path}/sender_projection_cleanup_receipt.json',
    );
    _notificationRecoveryReceiptFile = File(
      '${options.captureDirectory.path}/notification_recovery_receipt.json',
    );
    _notificationRetryFirstReceiptFile = File(
      '${options.captureDirectory.path}/notification_retry_first_receipt.json',
    );
  }

  Future<_DriverResult> _runRecoveryPhase() async {
    await _preflight();
    _prepareCaptureFiles();
    try {
      await _verifyAndPatchCentralProducts();
      await _installExactApplication();
      await _startSyslog();

      final prepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'recovery-prepare',
      );
      _assertionsAttempted += 1;
      if (!_hasMarker(prepare, 'READY')) {
        throw _DriverFailure(
          'The recovery phase did not reach automated notification readiness.',
          _assertionsAttempted,
        );
      }
      await _captureReceiverHandoff(
        output: _payloadReceiverHandoffFile,
        deliveryBinding: false,
      );
      await _produceApnsPayload();
      await _runSenderProjection(action: 'seed-sender');
      final postSeedPrepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'recovery-post-seed-prepare',
      );
      if (!_hasMarker(postSeedPrepare, 'READY')) {
        throw _DriverFailure(
          'The recovery receiver was not returned to background readiness.',
          _assertionsAttempted,
        );
      }

      await _captureReceiverHandoff(
        output: _deliveryReceiverHandoffFile,
        deliveryBinding: true,
      );
      await _backgroundFinalRegisteredReceiver(
        'recovery-final-registered-background',
      );

      final nseBoundary = _captureSyslogObservationBoundary();
      final providerReceipt = await _runProviderSetup();
      _assertionsAttempted += 1;
      final providerAcceptedAt = _utc(
        providerReceipt['acceptedAt'],
        'provider receipt acceptedAt',
      );
      final nseObservedAt = await _waitForNseSignals(
        providerAcceptedAt,
        nseBoundary,
      );
      _assertionsAttempted += 1;

      final observed = await _runXcui(
        'testObservePayloadNotificationRecovery',
        'recovery-observe',
      );
      _assertionsAttempted += 2;
      final cardObservedAt = _markerTimestamp(observed, 'RECOVERY_CARD_READY');
      final badgeObservedAt = _markerTimestamp(
        observed,
        'RECOVERY_BADGE_READY',
      );
      if (cardObservedAt == null ||
          badgeObservedAt == null ||
          badgeObservedAt.isBefore(cardObservedAt) ||
          !_hasExactLogicalMarker(
            observed,
            'RECOVERY_CARD_READY',
            at: cardObservedAt,
            fields: const <String, String>{'unique': 'true'},
          ) ||
          !_hasExactLogicalMarker(
            observed,
            'RECOVERY_BADGE_READY',
            at: badgeObservedAt,
            fields: const <String, String>{'absolute': '1'},
          )) {
        throw _DriverFailure(
          'The physical recovery observation omitted the real card or absolute '
          'badge marker.',
          _assertionsAttempted,
        );
      }

      final recoveryReceipt = await _runNotificationRecoveryProof();
      _assertionsAttempted += 3;
      final recoveryCompletedAt = _utc(
        recoveryReceipt['completedAt'],
        'notification recovery receipt completedAt',
      );
      _uiCleanupAttempted = true;
      final verified = await _runXcui(
        'testVerifyPayloadNotificationRecoveryRetirement',
        'recovery-verify',
      );
      _assertionsAttempted += 2;
      final retirementObservedAt = _markerTimestamp(
        verified,
        'RECOVERY_RETIREMENT_READY',
      );
      final zeroBadgeObservedAt = _markerTimestamp(
        verified,
        'RECOVERY_ZERO_BADGE_READY',
      );
      if (retirementObservedAt == null ||
          zeroBadgeObservedAt == null ||
          retirementObservedAt.isBefore(recoveryCompletedAt) ||
          zeroBadgeObservedAt.isBefore(retirementObservedAt) ||
          !_hasExactLogicalMarker(
            verified,
            'RECOVERY_RETIREMENT_READY',
            at: retirementObservedAt,
            fields: const <String, String>{
              'owned_absent': 'true',
              'sentinel_present': 'true',
            },
          ) ||
          !_hasExactLogicalMarker(
            verified,
            'RECOVERY_ZERO_BADGE_READY',
            at: zeroBadgeObservedAt,
            fields: const <String, String>{'absolute': '0'},
          )) {
        throw _DriverFailure(
          'The physical recovery verification omitted exact retirement, '
          'sentinel survival, or zero-badge evidence.',
          _assertionsAttempted,
        );
      }
      _uiCleanupComplete = true;

      await _stopSyslog(requireLiveCapture: true);
      final rawWindow = _rawSyslog.readAsStringSync();
      final completeWindowCounts = _directWindowCounts(rawWindow, nseBoundary);
      final causalDiagnostic = _writeCausalDiagnostic(
        status: 'passed',
        counts: completeWindowCounts,
      );
      if (completeWindowCounts.nseEnvelopeStaged != 1 ||
          completeWindowCounts.nseDecryptOk != 1 ||
          completeWindowCounts.nseAuthorizedHandoff != 1 ||
          completeWindowCounts.nseActiveHandoff != 1 ||
          completeWindowCounts.nseTrustedPassiveHandoff != 0 ||
          completeWindowCounts.nseSanitizedHandoff != 0 ||
          completeWindowCounts.backgroundHandler != 1 ||
          completeWindowCounts.recentRemoteSuppression != 1 ||
          completeWindowCounts.matchingNotificationShown != 0) {
        _writeCausalDiagnostic(
          status: 'failed_effect_or_nse_counts',
          counts: completeWindowCounts,
        );
        throw _DriverFailure(
          'The complete direct-notification window did not prove one active '
          'NSE sequence, one background handler, one recent-remote '
          'suppression, and zero matching local shows.',
          _assertionsAttempted,
        );
      }
      await _runSenderProjection(action: 'cleanup-sender');
      final providerCleanup = await _runProviderCleanup();
      await _verifyCandidateApplicationRemoved();
      _assertionsAttempted += 1;

      final evidence = _writeRecoveryRedactedEvidence(rawWindow);
      final relayLog = _receiptMember(
        _providerReceiptFile,
        providerReceipt['relayLogPath'],
        'relay log',
      );
      if (_sha256File(relayLog) != providerReceipt['relayLogSha256']) {
        throw _DriverFailure(
          'The recovery relay log does not match the provider receipt digest.',
          _assertionsAttempted,
        );
      }
      _rejectSecretBearingText(
        relayLog.readAsStringSync(),
        'recovery relay log',
      );
      final receipt = <String, Object?>{
        'schema': iosNotificationRecoveryAutomationReceiptSchema,
        'scenario': iosNotificationPayloadScenario,
        'phase': 'recovery',
        'status': 'passed',
        'platform': 'ios',
        'receiverPhysical': true,
        'runId': options.runId,
        'nonce': options.nonce,
        'receiverDeviceId': options.receiverDeviceId,
        'peerDeviceId': options.peerDeviceId,
        'preparedApplicationSha256': _applicationSha256,
        'providerRequestSha256': _requestSha256,
        'payloadProducerSha256': _payloadProducerSha256,
        'apnsPayloadSha256': _apnsPayloadSha256,
        'childBuildCount': 0,
        'manualActionCount': 0,
        'passDiagnosticRetained': causalDiagnostic.existsSync(),
        'cleanupOwners': _cleanupOwnerEvidence(),
        'checks': <String, Object?>{
          'notificationPermissionAutomated': true,
          'badgePermissionEnabled': true,
          'providerPayloadBadgeAbsent': true,
          'deliveredNotificationBadgeWasNil':
              recoveryReceipt['deliveredNotificationBadgeWasNil'] == true,
          'apnsDelivered': true,
          'nseProcessObserved': true,
          // A fresh reinstall/reset, one accepted provider payload with no
          // badge field, one delivered owned card with badge=nil, absolute
          // badge 1, and exact one-card custody make A the unique claim.
          'recoveryClaimUnique': true,
          'runnerAbsoluteBadgeConverged': recoveryReceipt['badgeAfter'] == 0,
          'exactOwnedNotificationRetired':
              recoveryReceipt['removedExactOwnedNotification'] == true,
          'unrelatedSentinelSurvived':
              recoveryReceipt['sentinelSurvived'] == true,
          'zeroBadgePublished': recoveryReceipt['badgeAfter'] == 0,
          'providerCleanupAutomated': _providerCleanupComplete,
          'testStateCleared':
              providerCleanup['appTestStateCleared'] == true &&
              providerCleanup['notificationStateCleared'] == true &&
              providerCleanup['relayFixtureCleared'] == true,
          'sourceInventoryStable': recoveryReceipt['stableSampleCount'] == 3,
          'directSourceUsefulProviderOnly':
              recoveryReceipt['matchingUsefulProviderCount'] == 1 &&
              recoveryReceipt['matchingSanitizedProviderCount'] == 0 &&
              recoveryReceipt['matchingFlutterLocalCount'] == 0 &&
              recoveryReceipt['matchingUnknownCount'] == 0,
          'backgroundHandlerReached':
              completeWindowCounts.backgroundHandler == 1,
          'backgroundContenderSuppressed':
              completeWindowCounts.recentRemoteSuppression == 1,
          'noMatchingLocalShow':
              completeWindowCounts.matchingNotificationShown == 0,
          'completeWindowNseBound':
              completeWindowCounts.nseAuthorizedHandoff == 1,
        },
        'counts': <String, Object?>{
          'badgeBefore': recoveryReceipt['badgeBefore'],
          'badgeAfter': recoveryReceipt['badgeAfter'],
          'deliveredBefore': recoveryReceipt['deliveredBefore'],
          'deliveredWithSentinel': recoveryReceipt['deliveredWithSentinel'],
          'deliveredAfter': recoveryReceipt['deliveredAfter'],
          'matchingRemoteCount': recoveryReceipt['matchingRemoteCount'],
          'matchingLocalCount': recoveryReceipt['matchingLocalCount'],
          'matchingUsefulProviderCount':
              recoveryReceipt['matchingUsefulProviderCount'],
          'matchingSanitizedProviderCount':
              recoveryReceipt['matchingSanitizedProviderCount'],
          'matchingFlutterLocalCount':
              recoveryReceipt['matchingFlutterLocalCount'],
          'matchingUnknownCount': recoveryReceipt['matchingUnknownCount'],
          'matchingTotalCount': recoveryReceipt['matchingTotalCount'],
          'stableSampleCount': recoveryReceipt['stableSampleCount'],
          'stableSampleIntervalMilliseconds':
              recoveryReceipt['stableSampleIntervalMilliseconds'],
          'settleDelayMilliseconds': recoveryReceipt['settleDelayMilliseconds'],
          'observationDeadlineMilliseconds':
              recoveryReceipt['observationDeadlineMilliseconds'],
          'backgroundHandlerCount': completeWindowCounts.backgroundHandler,
          'recentRemoteSuppressionCount':
              completeWindowCounts.recentRemoteSuppression,
          'matchingNotificationShownCount':
              completeWindowCounts.matchingNotificationShown,
          'nseEnvelopeStagedCount': completeWindowCounts.nseEnvelopeStaged,
          'nseDecryptOkCount': completeWindowCounts.nseDecryptOk,
          'nseAuthorizedHandoffCount':
              completeWindowCounts.nseAuthorizedHandoff,
          'nseActiveHandoffCount': completeWindowCounts.nseActiveHandoff,
          'nseTrustedPassiveHandoffCount':
              completeWindowCounts.nseTrustedPassiveHandoff,
          'nseSanitizedHandoffCount': completeWindowCounts.nseSanitizedHandoff,
        },
        'requestIdentifierSha256': recoveryReceipt['requestIdentifierSha256'],
        'timestamps': <String, Object?>{
          'providerAcceptedAt': providerAcceptedAt.toIso8601String(),
          'nseObservedAt': nseObservedAt.toIso8601String(),
          'cardObservedAt': cardObservedAt.toIso8601String(),
          'badgeObservedAt': badgeObservedAt.toIso8601String(),
          'recoveryCompletedAt': recoveryCompletedAt.toIso8601String(),
          'retirementObservedAt': retirementObservedAt.toIso8601String(),
          'zeroBadgeObservedAt': zeroBadgeObservedAt.toIso8601String(),
        },
        'evidenceSha256': <String, String>{
          'preparedApplication': _applicationSha256,
          'payloadProducer': _payloadProducerSha256,
          'apnsPayload': _apnsPayloadSha256,
          'providerReceipt': _sha256File(_providerReceiptFile),
          'providerCleanupReceipt': _sha256File(_providerCleanupReceiptFile),
          'notificationRecoveryReceipt': _sha256File(
            _notificationRecoveryReceiptFile,
          ),
          'relayLog': _sha256File(relayLog),
          'nseLog': _sha256File(evidence.nseLog),
          'recipientLog': _sha256File(evidence.recipientLog),
          'uiAutomationLog': _sha256File(evidence.uiLog),
          'stagedEnvelope': providerReceipt['stagedEnvelopeSha256']! as String,
          'causalDiagnostic': _sha256File(causalDiagnostic),
        },
      };
      final validation = validateIosNotificationRecoveryAutomationReceipt(
        receipt,
        runId: options.runId,
        nonce: options.nonce,
        receiverDeviceId: options.receiverDeviceId,
        peerDeviceId: options.peerDeviceId,
        preparedApplicationSha256: _applicationSha256,
        providerRequestSha256: _requestSha256,
        payloadProducerSha256: _payloadProducerSha256,
        apnsPayloadSha256: _apnsPayloadSha256,
      );
      if (!validation.ok) {
        throw _DriverFailure(
          'The recovery automation receipt failed closed: ${validation.detail}',
          _assertionsAttempted,
        );
      }
      options.output.writeAsStringSync('${jsonEncode(receipt)}\n', flush: true);
      return _DriverResult.passed(_assertionsAttempted);
    } finally {
      final diagnostic = File(
        '${options.captureDirectory.path}/direct-notification-diagnostic.redacted.json',
      );
      final finalizationFailures =
          await attemptDiagnosticCleanupAndPrivateDeletion(
            attemptDiagnosticRetention: () {
              if (!options.output.existsSync() || !diagnostic.existsSync()) {
                _writeCausalDiagnostic(
                  status: options.output.existsSync() ? 'passed' : 'failed',
                );
              }
            },
            cleanupOwners: <FutureOr<void> Function()>[
              _cleanupAllAcquiredState,
              () => _stopSyslog(),
            ],
            privateDeletionOwners: _privateDeletionOwners(),
          );
      _throwFinalizationFailures(finalizationFailures);
    }
  }

  Future<_DriverResult> _runRetryPhase() async {
    await _preflight();
    _prepareCaptureFiles();
    try {
      await _verifyAndPatchCentralProducts();
      await _installExactApplication();
      await _startSyslog();
      final prepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'retry-prepare',
      );
      _assertionsAttempted += 1;
      if (!_hasMarker(prepare, 'READY')) {
        throw _DriverFailure(
          'The retry phase did not reach automated notification readiness.',
          _assertionsAttempted,
        );
      }
      await _captureReceiverHandoff(
        output: _payloadReceiverHandoffFile,
        deliveryBinding: false,
      );
      await _produceApnsPayload();
      await _runSenderProjection(action: 'seed-sender');
      final postSeedPrepare = await _runXcui(
        'testPreparePayloadFastPathNotificationTap',
        'retry-post-seed-prepare',
      );
      if (!_hasMarker(postSeedPrepare, 'READY')) {
        throw _DriverFailure(
          'The retry receiver was not returned to background readiness.',
          _assertionsAttempted,
        );
      }

      await _captureReceiverHandoff(
        output: _deliveryReceiverHandoffFile,
        deliveryBinding: true,
      );
      await _backgroundFinalRegisteredReceiver(
        'retry-final-registered-background',
      );

      final completeWindowBoundary = _captureSyslogObservationBoundary();
      final firstProviderReceipt = await _runProviderSetup();
      _assertionsAttempted += 1;
      final firstAcceptedAt = _utc(
        firstProviderReceipt['acceptedAt'],
        'first provider receipt acceptedAt',
      );
      final firstNseObservedAt = await _waitForNseSignals(
        firstAcceptedAt,
        completeWindowBoundary,
        requiredPresentation: 'active',
      );
      _assertionsAttempted += 1;
      final firstObserved = await _runXcui(
        'testObservePayloadNotificationRecovery',
        'retry-first-observe',
      );
      final firstCardObservedAt = _markerTimestamp(
        firstObserved,
        'RECOVERY_CARD_READY',
      );
      if (firstCardObservedAt == null ||
          !_hasExactLogicalMarker(
            firstObserved,
            'RECOVERY_CARD_READY',
            at: firstCardObservedAt,
            fields: const <String, String>{'unique': 'true'},
          )) {
        throw _DriverFailure(
          'The first accepted request did not fence on one stable useful card.',
          _assertionsAttempted,
        );
      }
      final firstInventory = await _runNotificationRecoveryProof(
        action: 'observe-direct',
        proofStage: 'retry_first',
      );
      _notificationRecoveryReceiptFile.copySync(
        _notificationRetryFirstReceiptFile.path,
      );
      _makeOwnerOnly(_notificationRetryFirstReceiptFile);
      final firstRequestHashes =
          (firstInventory['requestIdentifierSha256']! as List).cast<String>();
      final collapseIdentitySha256 =
          firstProviderReceipt['collapseIdentitySha256']! as String;
      if (firstRequestHashes.single != collapseIdentitySha256) {
        throw _DriverFailure(
          'The first delivered request identifier is not bound to the collapse identity.',
          _assertionsAttempted,
        );
      }

      final secondNseBoundary = _captureSyslogObservationBoundary();
      final retryReceipt = await _runProviderRetry(firstProviderReceipt);
      _assertionsAttempted += 1;
      final secondAcceptedAt = _utc(
        retryReceipt['secondAcceptedAt'],
        'second provider receipt acceptedAt',
      );
      final secondNseObservedAt = await _waitForNseSignals(
        secondAcceptedAt,
        secondNseBoundary,
        requiredPresentation: 'trusted_passive',
      );
      _assertionsAttempted += 1;
      final secondObserved = await _runXcui(
        'testObservePayloadNotificationRecovery',
        'retry-second-observe',
      );
      final secondCardObservedAt = _markerTimestamp(
        secondObserved,
        'RECOVERY_CARD_READY',
      );
      if (secondCardObservedAt == null ||
          !_hasExactLogicalMarker(
            secondObserved,
            'RECOVERY_CARD_READY',
            at: secondCardObservedAt,
            fields: const <String, String>{'unique': 'true'},
          )) {
        throw _DriverFailure(
          'The second accepted request did not settle at one useful card.',
          _assertionsAttempted,
        );
      }
      final secondInventory = await _runNotificationRecoveryProof(
        action: 'observe-direct',
        proofStage: 'retry_second',
      );
      final secondRequestHashes =
          (secondInventory['requestIdentifierSha256']! as List).cast<String>();
      if (secondRequestHashes.single != collapseIdentitySha256 ||
          secondRequestHashes.single != firstRequestHashes.single) {
        throw _DriverFailure(
          'The final delivered request identity diverged from the bounded retry collapse identity.',
          _assertionsAttempted,
        );
      }

      await _stopSyslog(requireLiveCapture: true);
      final rawWindow = _rawSyslog.readAsStringSync();
      final counts = _directWindowCounts(rawWindow, completeWindowBoundary);
      final diagnostic = _writeCausalDiagnostic(
        status: 'passed',
        counts: counts,
      );
      if (counts.nseEnvelopeStaged != 2 ||
          counts.nseDecryptOk != 2 ||
          counts.nseAuthorizedHandoff != 2 ||
          counts.nseActiveHandoff != 1 ||
          counts.nseTrustedPassiveHandoff != 1 ||
          counts.nseSanitizedHandoff != 0 ||
          counts.backgroundHandler != 2 ||
          counts.recentRemoteSuppression != 2 ||
          counts.matchingNotificationShown != 0) {
        _writeCausalDiagnostic(status: 'failed_retry_counts', counts: counts);
        throw _DriverFailure(
          'The retry window did not prove active then trusted-passive NSE '
          'handoffs, two background callbacks, two recent-remote '
          'suppressions, and zero local shows.',
          _assertionsAttempted,
        );
      }

      await _runUiCleanup();
      if (!_uiCleanupComplete) {
        throw _DriverFailure(
          'The retry cleanup selector did not restore network state and '
          'terminate the candidate application.',
          _assertionsAttempted,
        );
      }
      await _runSenderProjection(action: 'cleanup-sender');
      final providerCleanup = await _runProviderCleanup();
      await _verifyCandidateApplicationRemoved();
      _assertionsAttempted += 1;
      final evidence = _writeRecoveryRedactedEvidence(rawWindow);
      final relayLog = _receiptMember(
        _providerReceiptFile,
        firstProviderReceipt['relayLogPath'],
        'retry relay log',
      );
      final receipt = <String, Object?>{
        'schema': iosNotificationRetryAutomationReceiptSchema,
        'scenario': iosNotificationPayloadScenario,
        'phase': 'retry',
        'status': 'passed',
        'platform': 'ios',
        'receiverPhysical': true,
        'runId': options.runId,
        'nonce': options.nonce,
        'receiverDeviceId': options.receiverDeviceId,
        'peerDeviceId': options.peerDeviceId,
        'preparedApplicationSha256': _applicationSha256,
        'providerRequestSha256': _requestSha256,
        'payloadProducerSha256': _payloadProducerSha256,
        'apnsPayloadSha256': _apnsPayloadSha256,
        'collapseIdentitySha256': collapseIdentitySha256,
        'requestIdentifierSha256': secondRequestHashes.single,
        'childBuildCount': 0,
        'manualActionCount': 0,
        'passDiagnosticRetained': diagnostic.existsSync(),
        'cleanupOwners': _cleanupOwnerEvidence(),
        'checks': <String, Object?>{
          'firstDeliveryFenced': true,
          'secondTrustedPassiveHandoff': true,
          'providerAcceptancesDistinct': retryReceipt['providerIdsDistinct'],
          'payloadBytesIdentical': retryReceipt['payloadBytesIdentical'],
          'collapseIdentityReused': retryReceipt['collapseIdentityReused'],
          'finalRequestIdentifierMatchesCollapse': true,
          'samePayloadRetrySingleUsefulCard': true,
          'noSanitizedProviderCard':
              secondInventory['matchingSanitizedProviderCount'] == 0,
          'noFlutterLocalCard':
              secondInventory['matchingFlutterLocalCount'] == 0,
          'noUnknownCard': secondInventory['matchingUnknownCount'] == 0,
          'noMatchingLocalShow': counts.matchingNotificationShown == 0,
          'completeWindowNseBound': true,
          'providerCleanupAutomated': _providerCleanupComplete,
          'testStateCleared':
              providerCleanup['appTestStateCleared'] == true &&
              providerCleanup['notificationStateCleared'] == true &&
              providerCleanup['relayFixtureCleared'] == true,
        },
        'counts': <String, Object?>{
          'providerAcceptedCount': retryReceipt['providerAcceptedCount'],
          'matchingUsefulProviderCount':
              secondInventory['matchingUsefulProviderCount'],
          'matchingSanitizedProviderCount':
              secondInventory['matchingSanitizedProviderCount'],
          'matchingFlutterLocalCount':
              secondInventory['matchingFlutterLocalCount'],
          'matchingUnknownCount': secondInventory['matchingUnknownCount'],
          'matchingTotalCount': secondInventory['matchingTotalCount'],
          'stableSampleCount': secondInventory['stableSampleCount'],
          ...counts.toJson(),
        },
        'timestamps': <String, Object?>{
          'firstAcceptedAt': firstAcceptedAt.toIso8601String(),
          'firstNseObservedAt': firstNseObservedAt.toIso8601String(),
          'firstCardObservedAt': firstCardObservedAt.toIso8601String(),
          'secondAcceptedAt': secondAcceptedAt.toIso8601String(),
          'secondNseObservedAt': secondNseObservedAt.toIso8601String(),
          'secondCardObservedAt': secondCardObservedAt.toIso8601String(),
        },
        'providerMessageIdSha256': <String>[
          retryReceipt['firstProviderMessageIdSha256']! as String,
          retryReceipt['secondProviderMessageIdSha256']! as String,
        ],
        'evidenceSha256': <String, Object?>{
          'preparedApplication': _applicationSha256,
          'payloadProducer': _payloadProducerSha256,
          'apnsPayload': _apnsPayloadSha256,
          'firstProviderReceipt': _sha256File(_providerReceiptFile),
          'secondProviderReceipt': _sha256File(_providerRetryReceiptFile),
          'providerCleanupReceipt': _sha256File(_providerCleanupReceiptFile),
          'firstInventoryReceipt': _sha256File(
            _notificationRetryFirstReceiptFile,
          ),
          'secondInventoryReceipt': _sha256File(
            _notificationRecoveryReceiptFile,
          ),
          'relayLog': _sha256File(relayLog),
          'nseLog': _sha256File(evidence.nseLog),
          'recipientLog': _sha256File(evidence.recipientLog),
          'uiAutomationLog': _sha256File(evidence.uiLog),
          'causalDiagnostic': _sha256File(diagnostic),
          'stagedEnvelope':
              firstProviderReceipt['stagedEnvelopeSha256']! as String,
        },
      };
      final validation = validateIosNotificationRetryAutomationReceipt(
        receipt,
        runId: options.runId,
        nonce: options.nonce,
        receiverDeviceId: options.receiverDeviceId,
        peerDeviceId: options.peerDeviceId,
        preparedApplicationSha256: _applicationSha256,
        providerRequestSha256: _requestSha256,
        payloadProducerSha256: _payloadProducerSha256,
        apnsPayloadSha256: _apnsPayloadSha256,
      );
      if (!validation.ok) {
        throw _DriverFailure(
          'The retry automation receipt failed closed: ${validation.detail}',
          _assertionsAttempted,
        );
      }
      options.output.writeAsStringSync('${jsonEncode(receipt)}\n', flush: true);
      return _DriverResult.passed(_assertionsAttempted);
    } finally {
      final diagnostic = File(
        '${options.captureDirectory.path}/direct-notification-diagnostic.redacted.json',
      );
      final finalizationFailures =
          await attemptDiagnosticCleanupAndPrivateDeletion(
            attemptDiagnosticRetention: () {
              if (!options.output.existsSync() || !diagnostic.existsSync()) {
                _writeCausalDiagnostic(
                  status: options.output.existsSync() ? 'passed' : 'failed',
                );
              }
            },
            cleanupOwners: <FutureOr<void> Function()>[
              _cleanupAllAcquiredState,
              () => _stopSyslog(),
            ],
            privateDeletionOwners: _privateDeletionOwners(),
          );
      _throwFinalizationFailures(finalizationFailures);
    }
  }

  Future<void> _preflight() async {
    if (!const <String>{
      'fast-path',
      'recovery',
      'retry',
    }.contains(options.phase)) {
      throw const _DriverBlocked(
        'environment',
        '--phase must be exactly fast-path, recovery, or retry.',
      );
    }
    for (final command in const <String>[
      'xcrun',
      'xcodebuild',
      'plutil',
      'codesign',
      'idevicesyslog',
    ]) {
      final found = await Process.run('which', <String>[command]);
      if (found.exitCode != 0) {
        throw _DriverBlocked(
          'missingDriver',
          'The required physical-iOS command $command is unavailable.',
        );
      }
    }
    if (!_directory(options.application) ||
        !options.application.path.endsWith('.app') ||
        !_regularFile(options.xctestrun) ||
        !options.xctestrun.path.endsWith('.xctestrun')) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The central signed Runner.app and prebuilt .xctestrun are required.',
      );
    }
    if (!_regularFile(options.providerDriver) ||
        Process.runSync('test', <String>[
              '-x',
              options.providerDriver.path,
            ]).exitCode !=
            0) {
      throw const _DriverBlocked(
        'missingDriver',
        'The private APNs/relay setup-and-cleanup adapter is unavailable.',
      );
    }
    final receiverBootstrap = _receiverBootstrapDriver();
    if (!_regularFile(receiverBootstrap) ||
        Process.runSync('test', <String>[
              '-x',
              receiverBootstrap.path,
            ]).exitCode !=
            0) {
      throw const _DriverBlocked(
        'missingDriver',
        'The private iOS receiver bootstrap helper is unavailable.',
      );
    }
    if (!_regularFile(options.payloadProducer) ||
        Process.runSync('test', <String>[
              '-x',
              options.payloadProducer.path,
            ]).exitCode !=
            0) {
      throw const _DriverBlocked(
        'missingDriver',
        'SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER must name the prebuilt '
            'attested Go 1.25 payload producer.',
      );
    }
    if (!_regularFile(options.providerRequest) ||
        !_regularFile(options.stagingManifest) ||
        !_regularFile(options.relayKey)) {
      throw const _DriverBlocked(
        'credentials',
        'The private provider request, staging attestation, and relay key are '
            'required before physical automation starts.',
      );
    }
    _request = _readJson(options.providerRequest, 'provider request');
    _staging = _readJson(options.stagingManifest, 'staging manifest');
    final requestValidation = validateIosNotificationProviderRequest(_request);
    final stagingValidation = validateIosNotificationStagingManifest(_staging);
    if (!requestValidation.ok || !stagingValidation.ok) {
      throw _DriverBlocked(
        'credentials',
        !requestValidation.ok
            ? requestValidation.detail
            : stagingValidation.detail,
      );
    }
    final expectedTitle = _request['expectedTitle'];
    if (expectedTitle is! String || expectedTitle.length > 30) {
      throw const _DriverBlocked(
        'credentials',
        'Provider request expectedTitle must fit the 30-character sanitized '
            'username boundary.',
      );
    }
    if (_request['receiverDeviceId'] != options.receiverDeviceId ||
        _staging['receiverDeviceId'] != options.receiverDeviceId ||
        _request['peerDeviceId'] != options.peerDeviceId ||
        _staging['peerDeviceId'] != options.peerDeviceId) {
      throw const _DriverBlocked(
        'credentials',
        'Private iOS fixtures are not bound to the explicit receiver and peer.',
      );
    }
    _payloadProducerSha256 = _sha256File(options.payloadProducer);
    if (_staging['payloadProducerSha256'] != _payloadProducerSha256) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The prebuilt iOS payload producer does not match the staging '
            'manifest fingerprint.',
      );
    }
    if (_staging['dedicatedDisposableReceiver'] != true ||
        _staging['destructiveTestStateResetAuthorized'] != true ||
        _staging['providerCleanupAvailable'] != true) {
      throw const _DriverBlocked(
        'deviceState',
        'Physical iOS payload automation requires an explicitly dedicated '
            'disposable receiver because iOS cannot losslessly export and restore '
            'an arbitrary user app data/notification-permission state.',
      );
    }
    if (!RegExp(
          r'^[A-Za-z0-9._:-]{4,160}$',
        ).hasMatch(options.receiverDeviceId) ||
        options.receiverDeviceId == options.peerDeviceId ||
        options.relayTarget.contains(RegExp(r'[\r\n]'))) {
      throw const _DriverBlocked(
        'environment',
        'The explicit physical target, peer, or relay target is invalid.',
      );
    }
    _applicationSha256 = sha256FileSystemEntity(options.application);
    _requestSha256 = _sha256File(options.providerRequest);
  }

  File _receiverBootstrapDriver() => File.fromUri(
    Platform.script.resolve('ios_receiver_bootstrap.py'),
  ).absolute;

  Future<void> _captureReceiverHandoff({
    required File output,
    required bool deliveryBinding,
  }) async {
    if (output.existsSync()) output.deleteSync();
    final result = await _runCommand(
      _receiverBootstrapDriver().path,
      <String>[
        '--action',
        deliveryBinding ? 'capture-receiver-final' : 'capture-receiver',
        '--timeout-seconds',
        '150',
      ],
      environment: <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
        'SIMS_IOS_PHYSICAL_DEVICE_ID': options.receiverDeviceId,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE': _receiverHandoffNonce,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH': output.path,
      },
      timeout: const Duration(minutes: 3),
    );
    if (result.exitCode == 78) {
      throw const _DriverBlocked(
        'credentials',
        'The installed app could not publish a protected APNs receiver handoff.',
      );
    }
    if (result.exitCode != 0 || !_regularFile(output)) {
      throw _DriverFailure(
        'The private receiver bootstrap did not produce a protected handoff.',
        _assertionsAttempted,
      );
    }
    final metadata = output.statSync();
    if ((metadata.mode & 0x3f) != 0) {
      throw _DriverFailure(
        'The private receiver handoff has group or world permissions.',
        _assertionsAttempted,
      );
    }
    final handoff = _readJson(output, 'receiver handoff');
    const exactKeys = <String>{
      'schema',
      'captureNonce',
      'receiverDeviceId',
      'peerDeviceId',
      'bundleId',
      'apnsEnvironment',
      'apnsDeviceToken',
      'mlKemPublicKey',
      'notificationAuthorization',
      'notificationAlertSetting',
      'notificationBadgeSetting',
      'capturedAt',
    };
    if (handoff.keys.toSet().difference(exactKeys).isNotEmpty ||
        exactKeys.difference(handoff.keys.toSet()).isNotEmpty ||
        handoff['schema'] != _receiverHandoffSchema ||
        handoff['captureNonce'] != _receiverHandoffNonce ||
        handoff['receiverDeviceId'] != options.receiverDeviceId ||
        handoff['peerDeviceId'] != options.peerDeviceId ||
        handoff['bundleId'] != _bundleId ||
        handoff['apnsEnvironment'] != 'development' ||
        !const <String>{
          'authorized',
          'provisional',
          'ephemeral',
        }.contains(handoff['notificationAuthorization']) ||
        handoff['notificationAlertSetting'] != 'enabled' ||
        handoff['notificationBadgeSetting'] != 'enabled') {
      throw _DriverFailure(
        'The private receiver handoff is not bound to the exact receiver, '
        'peer, bundle, nonce, authorized alerts and badges, and development APNs '
        'environment.',
        _assertionsAttempted,
      );
    }
    final peerId = handoff['peerDeviceId'];
    final mlKemPublicKey = handoff['mlKemPublicKey'];
    final authorization = handoff['notificationAuthorization'];
    final capturedAt = _utc(
      handoff['capturedAt'],
      'receiver handoff capturedAt',
    );
    if (peerId is! String ||
        peerId.isEmpty ||
        mlKemPublicKey is! String ||
        mlKemPublicKey.isEmpty ||
        authorization is! String) {
      throw _DriverFailure(
        'The private receiver handoff omitted bounded registration material.',
        _assertionsAttempted,
      );
    }
    final peerIdSha256 = sha256.convert(utf8.encode(peerId)).toString();
    final mlKemPublicKeySha256 = sha256
        .convert(utf8.encode(mlKemPublicKey))
        .toString();
    if (!deliveryBinding) {
      _payloadReceiverPeerIdSha256 = peerIdSha256;
      _payloadReceiverMlKemPublicKeySha256 = mlKemPublicKeySha256;
      _payloadReceiverNotificationAuthorization = authorization;
      _payloadReceiverCapturedAt = capturedAt;
      return;
    }
    if (peerIdSha256 != _payloadReceiverPeerIdSha256 ||
        mlKemPublicKeySha256 != _payloadReceiverMlKemPublicKeySha256 ||
        authorization != _payloadReceiverNotificationAuthorization ||
        !capturedAt.isAfter(_payloadReceiverCapturedAt)) {
      throw _DriverFailure(
        'The final delivery handoff is not a later launch bound to the same '
        'receiver identity, key, and notification settings.',
        _assertionsAttempted,
      );
    }
  }

  Future<void> _backgroundFinalRegisteredReceiver(String label) async {
    final output = await _runXcui(
      'testBackgroundRegisteredPayloadFastPathNotificationTap',
      label,
    );
    _assertionsAttempted += 1;
    if (!_hasMarker(output, 'FINAL_READY') ||
        !output.contains('registration_bound=true')) {
      throw _DriverFailure(
        'The final registered receiver was not backgrounded without relaunch.',
        _assertionsAttempted,
      );
    }
  }

  Future<void> _produceApnsPayload() async {
    if (_apnsPayloadFile.existsSync()) _apnsPayloadFile.deleteSync();
    final result = await _runCommand(
      options.payloadProducer.path,
      <String>[
        '--provider-request',
        options.providerRequest.path,
        '--receiver-handoff',
        _payloadReceiverHandoffFile.path,
        '--run-id',
        options.runId,
        '--nonce',
        options.nonce,
        '--output',
        _apnsPayloadFile.path,
      ],
      environment: const <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
      },
      timeout: const Duration(minutes: 1),
    );
    final type = FileSystemEntity.typeSync(
      _apnsPayloadFile.path,
      followLinks: false,
    );
    if (result.exitCode != 0 || type != FileSystemEntityType.file) {
      throw _DriverFailure(
        'The prebuilt Go 1.25 producer did not create the private APNs payload.',
        _assertionsAttempted,
      );
    }
    final metadata = _apnsPayloadFile.statSync();
    if ((metadata.mode & 0x3f) != 0 ||
        metadata.size <= 0 ||
        metadata.size > 4096) {
      throw _DriverFailure(
        'The generated APNs payload is not owner-only and bounded to 4096 bytes.',
        _assertionsAttempted,
      );
    }
    final bytes = _apnsPayloadFile.readAsBytesSync();
    _apnsPayloadSha256 = sha256.convert(bytes).toString();
    final payloadText = utf8.decode(bytes, allowMalformed: false);
    final payload = _readCapturedJson(
      _apnsPayloadFile,
      'generated APNs payload',
      _assertionsAttempted,
    );
    final sender = payload['sender_id'];
    if (!isExactPrivateIosApnsPayload(
          payload,
          expectedTitle: _request['expectedTitle']! as String,
          expectedBody: _request['expectedBody']! as String,
        ) ||
        payloadText.contains(_request['expectedMessageText']! as String)) {
      throw _DriverFailure(
        'The generated APNs payload failed its encrypted exact-route contract.',
        _assertionsAttempted,
      );
    }
    final handoff = _readJson(
      _payloadReceiverHandoffFile,
      'payload receiver handoff',
    );
    for (final key in const <String>['apnsDeviceToken', 'mlKemPublicKey']) {
      final secret = handoff[key];
      if (secret is String &&
          secret.isNotEmpty &&
          payloadText.contains(secret)) {
        throw _DriverFailure(
          'The generated APNs payload copied protected receiver material.',
          _assertionsAttempted,
        );
      }
    }
    _senderPeerIdSha256 = sha256
        .convert(utf8.encode(sender! as String))
        .toString();
  }

  Future<void> _runSenderProjection({required String action}) async {
    final cleanup = action == 'cleanup-sender';
    if (cleanup) _senderProjectionCleanupAttempted = true;
    if (action != 'seed-sender' && !cleanup) {
      throw _DriverFailure(
        'Unsupported private sender projection action.',
        _assertionsAttempted,
      );
    }
    final receiptFile = cleanup
        ? _senderCleanupReceiptFile
        : _senderSeedReceiptFile;
    if (receiptFile.existsSync()) receiptFile.deleteSync();
    final result = await _runCommand(
      _receiverBootstrapDriver().path,
      <String>['--action', action],
      environment: <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
        'SIMS_IOS_PHYSICAL_DEVICE_ID': options.receiverDeviceId,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE': _receiverHandoffNonce,
        'SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH': _apnsPayloadFile.path,
        'SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH':
            receiptFile.path,
      },
      timeout: const Duration(minutes: 3),
    );
    if (result.exitCode != 0 || !_regularFile(receiptFile)) {
      throw _DriverFailure(
        'The private sender projection $action action failed closed.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      receiptFile,
      'sender projection $action receipt',
      _assertionsAttempted,
    );
    const keys = <String>{
      'schema',
      'action',
      'status',
      'containsSecrets',
      'bundleId',
      'captureNonceSha256',
      'receiverDeviceIdSha256',
      'senderPeerIdSha256',
      'apnsPayloadSha256',
      'fixtureDigest',
      'nativeStatus',
      'resultCode',
      'completedAt',
    };
    final shaPattern = RegExp(r'^[0-9a-f]{64}$');
    final expected = <String, Object?>{
      'schema': 'mknoon.sims.ios-sender-projection-host-receipt.v1',
      'action': action,
      'status': 'PASS',
      'containsSecrets': false,
      'bundleId': _bundleId,
      'captureNonceSha256': sha256
          .convert(utf8.encode(_receiverHandoffNonce))
          .toString(),
      'receiverDeviceIdSha256': sha256
          .convert(utf8.encode(options.receiverDeviceId))
          .toString(),
      'senderPeerIdSha256': _senderPeerIdSha256,
      'apnsPayloadSha256': _apnsPayloadSha256,
      'nativeStatus': cleanup ? 'cleaned' : 'seeded',
    };
    if (receipt.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(receipt.keys.toSet()).isNotEmpty ||
        expected.entries.any((entry) => receipt[entry.key] != entry.value) ||
        !shaPattern.hasMatch('${receipt['fixtureDigest']}') ||
        !const <String>{'ok', 'idempotent'}.contains(receipt['resultCode'])) {
      throw _DriverFailure(
        'The private sender projection receipt is not bound to this payload.',
        _assertionsAttempted,
      );
    }
    _utc(receipt['completedAt'], 'sender projection completedAt');
    if (cleanup) {
      _senderProjectionCleaned = true;
    } else {
      _senderProjectionSeeded = true;
    }
  }

  Future<void> _verifyAndPatchCentralProducts() async {
    final verify = await _runCommand('codesign', <String>[
      '--verify',
      '--deep',
      '--strict',
      options.application.path,
    ], timeout: const Duration(seconds: 45));
    if (verify.exitCode != 0) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The centrally prepared physical Runner.app is not validly signed.',
      );
    }
    final infoPlist = File('${options.application.path}/Info.plist');
    if (!_regularFile(infoPlist)) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The centrally prepared Runner.app has no Info.plist.',
      );
    }
    final bundle = await _runCommand('plutil', <String>[
      '-extract',
      'CFBundleIdentifier',
      'raw',
      infoPlist.path,
    ], timeout: const Duration(seconds: 15));
    if (bundle.exitCode != 0 || bundle.stdout.trim() != _bundleId) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The centrally prepared app is not the production mknoon bundle.',
      );
    }

    final jsonPlist = File('${options.captureDirectory.path}/xctestrun.json');
    final convert = await _runCommand('plutil', <String>[
      '-convert',
      'json',
      '-o',
      jsonPlist.path,
      options.xctestrun.path,
    ], timeout: const Duration(seconds: 20));
    if (convert.exitCode != 0 || !_regularFile(jsonPlist)) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The prebuilt .xctestrun cannot be decoded.',
      );
    }
    _makeOwnerOnly(jsonPlist);
    _sensitiveIntermediates.add(jsonPlist);
    final decoded = _readJson(jsonPlist, 'xctestrun');
    final products = Directory(
      '${options.xctestrun.parent.path}/TestProducts',
    ).absolute;
    if (!_directory(products)) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The central iOS bundle has no TestProducts companion directory.',
      );
    }
    final relocation = relocateIosXctestrun(
      plist: decoded,
      cachedProducts: products,
      cachedApplication: options.application,
      uiEnvironment: <String, String>{
        'MKNOON_APNS_TAP_APP_BUNDLE_ID': _bundleId,
        'MKNOON_APNS_TAP_EXPECTED_TITLE': _request['expectedTitle']! as String,
        'MKNOON_APNS_TAP_EXPECTED_BODY':
            _request['expectedMessageText']! as String,
        'MKNOON_258_EXPECTED_MESSAGE_TEXT':
            _request['expectedMessageText']! as String,
      },
    );
    if (relocation.uiTargetsPatched != 1 ||
        relocation.productPathsPatched == 0) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The prebuilt .xctestrun has no uniquely patchable RunnerUITests target.',
      );
    }
    final patchedJson = File(
      '${options.captureDirectory.path}/patched-xctestrun.json',
    )..writeAsStringSync(jsonEncode(relocation.plist), flush: true);
    _makeOwnerOnly(patchedJson);
    _sensitiveIntermediates.add(patchedJson);
    _patchedXctestrun = File(
      '${options.captureDirectory.path}/RunnerUITests.patched.xctestrun',
    );
    final encode = await _runCommand('plutil', <String>[
      '-convert',
      'xml1',
      '-o',
      _patchedXctestrun.path,
      patchedJson.path,
    ], timeout: const Duration(seconds: 20));
    if (encode.exitCode != 0 || !_regularFile(_patchedXctestrun)) {
      throw const _DriverBlocked(
        'missingArtifact',
        'The patched no-build .xctestrun could not be materialized.',
      );
    }
    _makeOwnerOnly(_patchedXctestrun);
    _sensitiveIntermediates.add(_patchedXctestrun);
  }

  Future<void> _installExactApplication() async {
    final installJson = File(
      '${options.captureDirectory.path}/devicectl-install.json',
    );
    final installLog = File(
      '${options.captureDirectory.path}/devicectl-install.log',
    );
    final install = await _runCommand('xcrun', <String>[
      'devicectl',
      'device',
      'install',
      'app',
      '--device',
      options.receiverDeviceId,
      options.application.path,
      '--json-output',
      installJson.path,
      '--log-output',
      installLog.path,
      '--quiet',
    ], timeout: const Duration(minutes: 2));
    if (install.exitCode != 0 || !_regularFile(installJson)) {
      throw _deviceCommandFailure(
        'The exact centrally prepared Runner.app could not be installed.',
        install,
      );
    }
    final apps = await _installedApplicationsJson('after-install');
    if (!apps.readAsStringSync().contains(_bundleId)) {
      throw const _DriverBlocked(
        'deviceState',
        'devicectl did not confirm the installed production bundle.',
      );
    }
    _applicationInstalled = true;
  }

  Future<void> _startSyslog() async {
    if (_rawSyslog.existsSync()) _rawSyslog.deleteSync();
    final process = await Process.start('idevicesyslog', <String>[
      '-u',
      options.receiverDeviceId,
      '--no-colors',
      '--output',
      _rawSyslog.path,
    ]);
    _syslogProcess = process;
    _syslogExitCode = null;
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((exitCode) {
        _syslogExitCode = exitCode;
      }),
    );
    final earlyExit = await Future.any<Object?>(<Future<Object?>>[
      process.exitCode.then<Object?>((value) => value),
      Future<Object?>.delayed(const Duration(milliseconds: 800)),
    ]);
    if (earlyExit != null) {
      _syslogProcess = null;
      throw const _DriverBlocked(
        'deviceLost',
        'The selected physical iPhone log stream disconnected before capture.',
      );
    }
  }

  _SyslogObservationBoundary _captureSyslogObservationBoundary() {
    if (_syslogProcess == null || _syslogExitCode != null) {
      throw const _DriverBlocked(
        'deviceLost',
        'The selected physical iPhone log stream was unavailable before APNs '
            'provider submission.',
      );
    }
    if (!_rawSyslog.existsSync()) {
      return const _SyslogObservationBoundary(
        byteOffset: 0,
        beginsAtLineBoundary: true,
      );
    }
    final byteOffset = _rawSyslog.lengthSync();
    if (byteOffset == 0) {
      return const _SyslogObservationBoundary(
        byteOffset: 0,
        beginsAtLineBoundary: true,
      );
    }
    final reader = _rawSyslog.openSync(mode: FileMode.read);
    late final int precedingByte;
    try {
      reader.setPositionSync(byteOffset - 1);
      precedingByte = reader.readByteSync();
    } finally {
      reader.closeSync();
    }
    return _SyslogObservationBoundary(
      byteOffset: byteOffset,
      beginsAtLineBoundary: precedingByte == 0x0a,
    );
  }

  Future<void> _stopSyslog({bool requireLiveCapture = false}) async {
    final process = _syslogProcess;
    if (process == null) {
      if (requireLiveCapture) {
        throw const _DriverBlocked(
          'deviceLost',
          'The selected physical iPhone log stream was unavailable at the '
              'causal capture boundary.',
        );
      }
      return;
    }
    await Future<void>.delayed(Duration.zero);
    final preStopExitCode = _syslogExitCode;
    _syslogProcess = null;
    _syslogExitCode = null;
    final terminationRequested = process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    if (requireLiveCapture &&
        (preStopExitCode != null || !terminationRequested)) {
      throw const _DriverBlocked(
        'deviceLost',
        'The selected physical iPhone log stream ended before the causal '
            'capture boundary was frozen.',
      );
    }
  }

  Future<String> _runXcui(String selector, String label) async {
    final resultBundle = Directory(
      '${options.captureDirectory.path}/$label.xcresult',
    );
    if (resultBundle.existsSync()) resultBundle.deleteSync(recursive: true);
    _uiResultBundles.add(resultBundle);
    final result = await _runCommand(
      'xcodebuild',
      iosTestWithoutBuildingArguments(
        xctestrun: _patchedXctestrun,
        receiverDeviceId: options.receiverDeviceId,
        selector: selector,
        resultBundle: resultBundle,
      ),
      environment: const <String, String>{'SIMS_CHILD_BUILDS_FORBIDDEN': '1'},
      timeout: const Duration(minutes: 3),
    );
    final combined = '${result.stdout}\n${result.stderr}';
    final log = File('${options.captureDirectory.path}/$label.xcode.log')
      ..writeAsStringSync(_redactUiText(combined), flush: true);
    _uiLogs.add(log);
    if (result.exitCode != 0) {
      throw _xcodeFailure(
        'Physical XCUITest selector $selector failed.',
        combined,
      );
    }
    return combined;
  }

  Future<Map<String, Object?>> _runProviderSetup() async {
    if (_providerReceiptFile.existsSync()) _providerReceiptFile.deleteSync();
    final result = await _runProvider(
      action: 'setup',
      output: _providerReceiptFile,
    );
    if (result.exitCode == 78) {
      await _runProviderRecovery();
      throw const _DriverBlocked(
        'credentials',
        'The private staging adapter reported unavailable APNs or relay '
            'credentials before accepting the provider message.',
      );
    }
    if (result.exitCode != 0 || !_regularFile(_providerReceiptFile)) {
      await _runProviderRecovery();
      throw _DriverFailure(
        'The private staging adapter did not produce an accepted, redacted '
        'provider receipt.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      _providerReceiptFile,
      'provider receipt',
      _assertionsAttempted,
    );
    final validation = validateIosNotificationProviderReceipt(
      receipt,
      runId: options.runId,
      nonce: options.nonce,
      receiverDeviceId: options.receiverDeviceId,
      requestSha256: _requestSha256,
      apnsPayloadSha256: _apnsPayloadSha256,
      receiverHandoffSha256: _sha256File(_deliveryReceiverHandoffFile),
    );
    if (!validation.ok) {
      await _runProviderRecovery();
      throw _DriverFailure(
        'The private provider receipt failed closed: ${validation.detail}',
        _assertionsAttempted,
      );
    }
    _providerSetupComplete = true;
    return receipt;
  }

  Future<Map<String, Object?>> _runProviderCleanup() async {
    _providerCleanupAttempted = true;
    if (!_providerSetupComplete) {
      throw _DriverFailure(
        'Provider cleanup was requested before setup completed.',
        _assertionsAttempted,
      );
    }
    if (_providerCleanupReceiptFile.existsSync()) {
      _providerCleanupReceiptFile.deleteSync();
    }
    final result = await _runProvider(
      action: 'cleanup',
      output: _providerCleanupReceiptFile,
      setupReceipt: _providerReceiptFile,
    );
    if (result.exitCode != 0 || !_regularFile(_providerCleanupReceiptFile)) {
      await _runProviderRecovery();
      throw _DriverFailure(
        'The dedicated-device staging adapter did not complete automated '
        'relay/app/notification cleanup.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      _providerCleanupReceiptFile,
      'provider cleanup receipt',
      _assertionsAttempted,
    );
    final validation = validateIosNotificationProviderCleanupReceipt(
      receipt,
      runId: options.runId,
      nonce: options.nonce,
      receiverDeviceId: options.receiverDeviceId,
      providerReceiptSha256: _sha256File(_providerReceiptFile),
      apnsPayloadSha256: _apnsPayloadSha256,
      receiverHandoffSha256: _sha256File(_deliveryReceiverHandoffFile),
    );
    if (!validation.ok) {
      await _runProviderRecovery();
      throw _DriverFailure(
        'The provider cleanup receipt failed closed: ${validation.detail}',
        _assertionsAttempted,
      );
    }
    _providerCleanupComplete = true;
    return receipt;
  }

  Future<Map<String, Object?>> _runProviderRetry(
    Map<String, Object?> firstReceipt,
  ) async {
    if (!_providerSetupComplete) {
      throw _DriverFailure(
        'Provider retry was requested before the first acceptance completed.',
        _assertionsAttempted,
      );
    }
    if (_providerRetryReceiptFile.existsSync()) {
      _providerRetryReceiptFile.deleteSync();
    }
    final result = await _runProvider(
      action: 'retry',
      output: _providerRetryReceiptFile,
      setupReceipt: _providerReceiptFile,
    );
    if (result.exitCode != 0 || !_regularFile(_providerRetryReceiptFile)) {
      throw _DriverFailure(
        'The private provider adapter did not publish the bounded second-send receipt.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      _providerRetryReceiptFile,
      'provider retry receipt',
      _assertionsAttempted,
    );
    final validation = validateIosNotificationProviderRetryReceipt(
      receipt,
      runId: options.runId,
      nonce: options.nonce,
      receiverDeviceId: options.receiverDeviceId,
      requestSha256: _requestSha256,
      apnsPayloadSha256: _apnsPayloadSha256,
      receiverHandoffSha256: _sha256File(_deliveryReceiverHandoffFile),
      collapseIdentitySha256: firstReceipt['collapseIdentitySha256']! as String,
      firstProviderReceiptSha256: _sha256File(_providerReceiptFile),
      firstProviderMessageIdSha256:
          firstReceipt['providerMessageIdSha256']! as String,
    );
    if (!validation.ok) {
      throw _DriverFailure(
        'The provider retry receipt failed closed: ${validation.detail}',
        _assertionsAttempted,
      );
    }
    return receipt;
  }

  Future<void> _runProviderRecovery() async {
    _providerRecoveryAttempted = true;
    if (_providerRecoveryReceiptFile.existsSync()) {
      _providerRecoveryReceiptFile.deleteSync();
    }
    final result = await _runProvider(
      action: 'rollback',
      output: _providerRecoveryReceiptFile,
    );
    if (result.exitCode != 0 || !_regularFile(_providerRecoveryReceiptFile)) {
      throw _DriverFailure(
        'The private provider adapter did not complete idempotent recovery.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      _providerRecoveryReceiptFile,
      'provider recovery receipt',
      _assertionsAttempted,
    );
    final expected = <String, Object?>{
      'schema': _providerRecoveryReceiptSchema,
      'status': 'recovered',
      'relayFixtureCleared': true,
      'candidateAppRemoved': true,
      'runId': options.runId,
      'nonce': options.nonce,
      'receiverDeviceIdSha256': sha256
          .convert(utf8.encode(options.receiverDeviceId))
          .toString(),
      'requestSha256': _requestSha256,
      'apnsPayloadSha256': _apnsPayloadSha256,
      'receiverHandoffSha256': _sha256File(_deliveryReceiverHandoffFile),
      'childBuildCount': 0,
      'manualActionCount': 0,
    };
    final expectedKeys = <String>{...expected.keys, 'recoveredAt'};
    if (receipt.keys.toSet().difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(receipt.keys.toSet()).isNotEmpty ||
        expected.entries.any((entry) => receipt[entry.key] != entry.value) ||
        findIosNotificationSecretBearingField(receipt) != null ||
        _utcTimestampOrNull(receipt['recoveredAt']) == null) {
      throw _DriverFailure(
        'The private provider recovery receipt is not bound to this run.',
        _assertionsAttempted,
      );
    }
    _providerRecoveryComplete = true;
  }

  Future<_CommandResult> _runProvider({
    required String action,
    required File output,
    File? setupReceipt,
  }) {
    final timeout = action == 'setup' || action == 'retry'
        ? const Duration(minutes: 6)
        : action == 'cleanup'
        ? const Duration(minutes: 4)
        : const Duration(minutes: 3);
    return _runCommand(
      options.providerDriver.path,
      <String>[
        '--action',
        action,
        '--scenario',
        iosNotificationPayloadScenario,
        '--receiver',
        options.receiverDeviceId,
        '--peer-device',
        options.peerDeviceId,
        '--application-binary',
        options.application.path,
        '--provider-request',
        options.providerRequest.path,
        '--staging-manifest',
        options.stagingManifest.path,
        '--relay-target',
        options.relayTarget,
        '--relay-key',
        options.relayKey.path,
        '--run-id',
        options.runId,
        '--nonce',
        options.nonce,
        if (setupReceipt != null) ...<String>[
          '--provider-receipt',
          setupReceipt.path,
        ],
        '--output',
        output.path,
      ],
      environment: <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
        'SIMS_PREBUILT_APPLICATION_BINARY': options.application.path,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE': _receiverHandoffNonce,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH':
            _deliveryReceiverHandoffFile.path,
        'SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH': _apnsPayloadFile.path,
        'SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER': options.payloadProducer.path,
        'SIMS_IOS_NOTIFICATION_RECEIVER_BOOTSTRAP_DRIVER':
            _receiverBootstrapDriver().path,
        'SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH':
            _senderCleanupReceiptFile.path,
      },
      timeout: timeout,
    );
  }

  Future<DateTime> _waitForNseSignals(
    DateTime providerAcceptedAt,
    _SyslogObservationBoundary boundary, {
    String requiredPresentation = 'active',
  }) async {
    final deadline = providerAcceptedAt.add(_nseObservationWindow);
    var readOffset = boundary.byteOffset;
    var observedBytes = 0;
    var pendingLine = '';
    var discardInitialPartialLine = !boundary.beginsAtLineBoundary;
    var discardedBoundaryFragments = 0;
    var didReceiveMarkers = 0;
    var stagedMarkers = 0;
    var stagedRejectedMarkers = 0;
    var decryptOkMarkers = 0;
    var decryptFailMarkers = 0;
    var timeoutMarkers = 0;
    var contentHandoffOkMarkers = 0;
    var contentHandoffRejectedMarkers = 0;
    var orderedProgress = 0;
    var orderedReadySequences = 0;
    var orderedFailureMarkers = 0;
    var orderedRejectedMarkers = 0;

    void observeLine(String line) {
      if (line.contains('PUSH_NSE_DID_RECEIVE')) {
        didReceiveMarkers += 1;
        if (orderedProgress == 0) orderedProgress = 1;
      }
      if (line.contains('PUSH_NSE_ENVELOPE_STAGED') &&
          line.contains(r'"success":"true"')) {
        stagedMarkers += 1;
        if (orderedProgress == 1) orderedProgress = 2;
      }
      if (line.contains('PUSH_NSE_ENVELOPE_STAGED') &&
          line.contains(r'"success":"false"')) {
        stagedRejectedMarkers += 1;
        orderedRejectedMarkers += 1;
      }
      if (line.contains('PUSH_NSE_DECRYPT_OK')) {
        decryptOkMarkers += 1;
        if (orderedProgress == 2) orderedProgress = 3;
      }
      if (line.contains('PUSH_NSE_DECRYPT_FAIL')) {
        decryptFailMarkers += 1;
        if (orderedProgress > 0 && orderedProgress < 4) {
          orderedFailureMarkers += 1;
        }
      }
      if (line.contains('PUSH_NSE_TIMEOUT')) {
        timeoutMarkers += 1;
        if (orderedProgress > 0 && orderedProgress < 4) {
          orderedFailureMarkers += 1;
        }
      }
      if (line.contains('PUSH_NSE_CONTENT_HANDOFF')) {
        if (line.contains(r'"authorized":"true"')) {
          contentHandoffOkMarkers += 1;
          if (line.contains('"presentation":"$requiredPresentation"') &&
              orderedProgress == 3) {
            orderedProgress = 4;
            orderedReadySequences += 1;
          } else if (!line.contains('"presentation":"$requiredPresentation"')) {
            orderedRejectedMarkers += 1;
          }
        } else {
          contentHandoffRejectedMarkers += 1;
          if (orderedProgress > 0 && orderedProgress < 4) {
            orderedRejectedMarkers += 1;
          }
        }
      }
    }

    bool hasStageRejection() => stagedRejectedMarkers > 0;

    bool hasOrderedFailure() =>
        orderedFailureMarkers > 0 || orderedRejectedMarkers > 0;

    void writeDiagnostic({
      required String status,
      required int? syslogExitCode,
    }) {
      _writeNseObservationDiagnostic(
        status: status,
        observationStartOffset: boundary.byteOffset,
        observedBytes: observedBytes,
        syslogExitCode: syslogExitCode,
        didReceiveMarkers: didReceiveMarkers,
        stagedMarkers: stagedMarkers,
        stagedRejectedMarkers: stagedRejectedMarkers,
        decryptOkMarkers: decryptOkMarkers,
        decryptFailMarkers: decryptFailMarkers,
        timeoutMarkers: timeoutMarkers,
        contentHandoffOkMarkers: contentHandoffOkMarkers,
        contentHandoffRejectedMarkers: contentHandoffRejectedMarkers,
        orderedProgress: orderedProgress,
        orderedReadySequences: orderedReadySequences,
        orderedFailureMarkers: orderedFailureMarkers,
        orderedRejectedMarkers: orderedRejectedMarkers,
        discardedBoundaryFragments: discardedBoundaryFragments,
      );
    }

    Never failForExitedSyslog(int exitCode) {
      writeDiagnostic(status: 'stream-exited', syslogExitCode: exitCode);
      throw _DriverBlocked(
        'deviceLost',
        'The selected physical iPhone log stream exited during the APNs/NSE '
            'observation window (exit $exitCode).',
      );
    }

    while (DateTime.now().isBefore(deadline)) {
      final syslogExitCode = _syslogExitCode;
      if (syslogExitCode != null) failForExitedSyslog(syslogExitCode);
      if (_rawSyslog.existsSync()) {
        final length = _rawSyslog.lengthSync();
        if (length < readOffset) {
          readOffset = 0;
          pendingLine = '';
          discardInitialPartialLine = false;
        }
        if (length > readOffset) {
          final reader = _rawSyslog.openSync(mode: FileMode.read);
          late final List<int> bytes;
          try {
            reader.setPositionSync(readOffset);
            bytes = reader.readSync(length - readOffset);
          } finally {
            reader.closeSync();
          }
          readOffset += bytes.length;
          observedBytes += bytes.length;
          final lines =
              '$pendingLine${utf8.decode(bytes, allowMalformed: true)}'.split(
                '\n',
              );
          pendingLine = lines.removeLast();
          if (discardInitialPartialLine && lines.isNotEmpty) {
            lines.removeAt(0);
            discardInitialPartialLine = false;
            discardedBoundaryFragments += 1;
          }
          for (final line in lines) {
            observeLine(line);
            if (hasStageRejection() ||
                hasOrderedFailure() ||
                orderedReadySequences > 0) {
              break;
            }
          }
        }
        if (hasStageRejection()) {
          writeDiagnostic(
            status: 'nse-envelope-stage-rejected',
            syslogExitCode: _syslogExitCode,
          );
          throw _DriverFailure(
            'The real Notification Service Extension rejected envelope staging.',
            _assertionsAttempted,
          );
        }
        if (hasOrderedFailure()) {
          writeDiagnostic(
            status: 'nse-failure-marker',
            syslogExitCode: _syslogExitCode,
          );
          throw _DriverFailure(
            'The real Notification Service Extension emitted a decrypt-fail, '
            'timeout, or unauthorized content-handoff marker.',
            _assertionsAttempted,
          );
        }
        if (orderedReadySequences > 0) {
          writeDiagnostic(
            status: 'ready-for-card-check',
            syslogExitCode: _syslogExitCode,
          );
          return DateTime.now().toUtc();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!discardInitialPartialLine && pendingLine.isNotEmpty) {
      observeLine(pendingLine);
    }
    final syslogExitCode = _syslogExitCode;
    if (syslogExitCode != null) failForExitedSyslog(syslogExitCode);
    if (hasStageRejection()) {
      writeDiagnostic(
        status: 'nse-envelope-stage-rejected',
        syslogExitCode: null,
      );
      throw _DriverFailure(
        'The real Notification Service Extension rejected envelope staging.',
        _assertionsAttempted,
      );
    }
    if (hasOrderedFailure()) {
      writeDiagnostic(status: 'nse-failure-marker', syslogExitCode: null);
      throw _DriverFailure(
        'The real Notification Service Extension emitted a decrypt-fail, '
        'timeout, or unauthorized content-handoff marker.',
        _assertionsAttempted,
      );
    }
    if (orderedReadySequences > 0) {
      writeDiagnostic(status: 'ready-for-card-check', syslogExitCode: null);
      return DateTime.now().toUtc();
    }
    writeDiagnostic(status: 'timed-out', syslogExitCode: null);
    throw _DriverFailure(
      'Timed out waiting for real NSE did-receive, envelope-staged, '
      'decrypt-success, and authorized content-handoff markers after APNs '
      'provider acceptance.',
      _assertionsAttempted,
    );
  }

  void _writeNseObservationDiagnostic({
    required String status,
    required int observationStartOffset,
    required int observedBytes,
    required int? syslogExitCode,
    required int didReceiveMarkers,
    required int stagedMarkers,
    required int stagedRejectedMarkers,
    required int decryptOkMarkers,
    required int decryptFailMarkers,
    required int timeoutMarkers,
    required int contentHandoffOkMarkers,
    required int contentHandoffRejectedMarkers,
    required int orderedProgress,
    required int orderedReadySequences,
    required int orderedFailureMarkers,
    required int orderedRejectedMarkers,
    required int discardedBoundaryFragments,
  }) {
    final diagnostic = File(
      '${options.captureDirectory.path}/nse-observation.redacted.json',
    );
    final encoded =
        '${jsonEncode(<String, Object?>{
          'schema': 'mknoon.sims.ios-nse-observation-diagnostic.v2',
          'status': status,
          'observationWindowSeconds': _nseObservationWindow.inSeconds,
          'observationStartOffset': observationStartOffset,
          'observedBytes': observedBytes,
          'syslogExitCode': syslogExitCode,
          'markerCounts': <String, int>{'didReceive': didReceiveMarkers, 'envelopeStaged': stagedMarkers, 'envelopeStagedRejected': stagedRejectedMarkers, 'decryptOk': decryptOkMarkers, 'decryptFail': decryptFailMarkers, 'timeout': timeoutMarkers, 'contentHandoffOk': contentHandoffOkMarkers, 'contentHandoffRejected': contentHandoffRejectedMarkers, 'orderedProgress': orderedProgress, 'orderedReadySequences': orderedReadySequences, 'orderedFailure': orderedFailureMarkers, 'orderedRejected': orderedRejectedMarkers, 'discardedBoundaryFragments': discardedBoundaryFragments},
        })}\n';
    _rejectSecretBearingText(encoded, 'NSE observation diagnostic');
    diagnostic.writeAsStringSync(encoded, flush: true);
    _makeOwnerOnly(diagnostic);
  }

  Future<String> _runUiCleanup() async {
    _uiCleanupAttempted = true;
    final output = await _runXcui(
      'testRestorePayloadFastPathNetwork',
      'cleanup-${_uiLogs.length}',
    );
    if (_hasMarker(output, 'NETWORK_RESTORED') &&
        output.contains('app_terminated=true')) {
      _uiCleanupComplete = true;
    }
    return output;
  }

  Future<void> _cleanupAllAcquiredState() async {
    final cleanupFailures =
        await attemptAllCleanupOwners(<FutureOr<void> Function()>[
          () async {
            if (_applicationInstalled && !_uiCleanupComplete) {
              await _runUiCleanup();
            }
          },
          () async {
            if (_senderProjectionSeeded && !_senderProjectionCleaned) {
              await _runSenderProjection(action: 'cleanup-sender');
            }
          },
          () async {
            if (!_providerCleanupComplete) {
              if (_providerSetupComplete) {
                await _runProviderCleanup();
              }
            }
          },
          () async {
            if (shouldAttemptProviderRecoveryAfterCleanup(
              providerCleanupComplete: _providerCleanupComplete,
              providerRecoveryComplete: _providerRecoveryComplete,
              receiverHandoffExists: _deliveryReceiverHandoffFile.existsSync(),
              apnsPayloadExists: _apnsPayloadFile.existsSync(),
            )) {
              await _runProviderRecovery();
            }
          },
          () async {
            if (_applicationInstalled) {
              await _removeCandidateApplicationDirectly();
            }
          },
        ]);
    if (cleanupFailures.isNotEmpty) {
      throw _DriverFailure(
        'Cleanup retained ${cleanupFailures.length} bounded owner failure(s) '
        'after every acquired-state owner was attempted.',
        _assertionsAttempted,
      );
    }
  }

  Map<String, Object?> _cleanupOwnerEvidence() => <String, Object?>{
    'ui': <String, bool>{
      'required': true,
      'attempted': _uiCleanupAttempted,
      'completed': _uiCleanupComplete,
    },
    'sender': <String, bool>{
      'required': true,
      'attempted': _senderProjectionCleanupAttempted,
      'completed': _senderProjectionCleaned,
    },
    'providerCleanup': <String, bool>{
      'required': true,
      'attempted': _providerCleanupAttempted,
      'completed': _providerCleanupComplete,
    },
    'providerRecovery': <String, bool>{
      'required': false,
      'attempted': _providerRecoveryAttempted,
      'completed': _providerRecoveryComplete,
    },
    'directInstall': <String, bool>{
      'required': false,
      'attempted': _directInstallCleanupAttempted,
      'completed': _directInstallCleanupComplete,
    },
  };

  Iterable<FutureOr<void> Function()> _privateDeletionOwners() sync* {
    for (final privateFile in <File>[
      _rawSyslog,
      _payloadReceiverHandoffFile,
      _deliveryReceiverHandoffFile,
      _apnsPayloadFile,
      _senderSeedReceiptFile,
      _senderCleanupReceiptFile,
      ..._sensitiveIntermediates,
    ]) {
      yield () {
        if (privateFile.existsSync()) privateFile.deleteSync();
      };
    }
    for (final resultBundle in _uiResultBundles) {
      yield () {
        if (resultBundle.existsSync()) {
          resultBundle.deleteSync(recursive: true);
        }
      };
    }
  }

  void _throwFinalizationFailures(List<Object> failures) {
    if (failures.isEmpty) return;
    throw _DriverFailure(
      'Phase finalization retained ${failures.length} bounded diagnostic, '
      'cleanup, or private-deletion failure(s) after all owners were attempted.',
      _assertionsAttempted,
    );
  }

  Future<void> _removeCandidateApplicationDirectly() async {
    _directInstallCleanupAttempted = true;
    final resultJson = File(
      '${options.captureDirectory.path}/devicectl-uninstall-final.json',
    );
    final commandLog = File(
      '${options.captureDirectory.path}/devicectl-uninstall-final.log',
    );
    final result = await _runCommand('xcrun', <String>[
      'devicectl',
      'device',
      'uninstall',
      'app',
      '--device',
      options.receiverDeviceId,
      _bundleId,
      '--json-output',
      resultJson.path,
      '--log-output',
      commandLog.path,
      '--quiet',
    ], timeout: const Duration(minutes: 1));
    final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
    final absent =
        combined.contains('not installed') ||
        combined.contains('application not found') ||
        combined.contains('no matching application');
    if (result.exitCode != 0 && !absent) {
      throw _DriverFailure(
        'Final state-aware candidate-app removal failed.',
        _assertionsAttempted,
      );
    }
    _applicationInstalled = false;
    _directInstallCleanupComplete = true;
  }

  Future<Map<String, Object?>> _runNotificationRecoveryProof({
    String action = 'prove-recovery',
    String proofStage = 'single_submission',
  }) async {
    if (_notificationRecoveryReceiptFile.existsSync()) {
      _notificationRecoveryReceiptFile.deleteSync();
    }
    final result = await _runCommand(
      _receiverBootstrapDriver().path,
      <String>['--action', action, '--proof-stage', proofStage],
      environment: <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
        'SIMS_IOS_PHYSICAL_DEVICE_ID': options.receiverDeviceId,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE': _receiverHandoffNonce,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH':
            _deliveryReceiverHandoffFile.path,
        'SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH': _apnsPayloadFile.path,
        'SIMS_IOS_NOTIFICATION_RECOVERY_RECEIPT_PATH':
            _notificationRecoveryReceiptFile.path,
      },
      timeout: const Duration(minutes: 3),
    );
    if (result.exitCode != 0 ||
        !_regularFile(_notificationRecoveryReceiptFile)) {
      throw _DriverFailure(
        'The protected native notification-recovery proof failed closed.',
        _assertionsAttempted,
      );
    }
    final receipt = _readCapturedJson(
      _notificationRecoveryReceiptFile,
      'notification recovery receipt',
      _assertionsAttempted,
    );
    const exactKeys = <String>{
      'schema',
      'action',
      'proofStage',
      'status',
      'containsSecrets',
      'bundleId',
      'captureNonceSha256',
      'receiverDeviceIdSha256',
      'apnsPayloadSha256',
      'badgeBefore',
      'badgeAfter',
      'deliveredBefore',
      'deliveredWithSentinel',
      'deliveredAfter',
      'deliveredNotificationBadgeWasNil',
      'sentinelSurvived',
      'removedExactOwnedNotification',
      'matchingRemoteCount',
      'matchingLocalCount',
      'matchingUsefulProviderCount',
      'matchingSanitizedProviderCount',
      'matchingFlutterLocalCount',
      'matchingUnknownCount',
      'matchingTotalCount',
      'stableSampleCount',
      'stableSampleIntervalMilliseconds',
      'settleDelayMilliseconds',
      'observationDeadlineMilliseconds',
      'requestIdentifierSha256',
      'childBuildCount',
      'manualActionCount',
      'resultCode',
      'completedAt',
    };
    final expected = <String, Object?>{
      'schema': 'mknoon.sims.ios-notification-recovery-host-receipt.v2',
      'action': action,
      'proofStage': proofStage,
      'status': 'PASS',
      'containsSecrets': false,
      'bundleId': _bundleId,
      'captureNonceSha256': sha256
          .convert(utf8.encode(_receiverHandoffNonce))
          .toString(),
      'receiverDeviceIdSha256': sha256
          .convert(utf8.encode(options.receiverDeviceId))
          .toString(),
      'apnsPayloadSha256': _apnsPayloadSha256,
      if (action == 'prove-recovery') 'badgeBefore': 1,
      if (action == 'prove-recovery') 'badgeAfter': 0,
      'deliveredBefore': 1,
      'deliveredWithSentinel': action == 'prove-recovery' ? 2 : 1,
      'deliveredAfter': 1,
      'deliveredNotificationBadgeWasNil': true,
      'sentinelSurvived': action == 'prove-recovery',
      'removedExactOwnedNotification': action == 'prove-recovery',
      'matchingRemoteCount': 1,
      'matchingLocalCount': 0,
      'matchingUsefulProviderCount': 1,
      'matchingSanitizedProviderCount': 0,
      'matchingFlutterLocalCount': 0,
      'matchingUnknownCount': 0,
      'matchingTotalCount': 1,
      'stableSampleCount': 3,
      'stableSampleIntervalMilliseconds': 500,
      'settleDelayMilliseconds': 3000,
      'observationDeadlineMilliseconds': 8000,
      'childBuildCount': 0,
      'manualActionCount': 0,
      'resultCode': 'ok',
    };
    if (receipt.keys.toSet().difference(exactKeys).isNotEmpty ||
        exactKeys.difference(receipt.keys.toSet()).isNotEmpty ||
        expected.entries.any((entry) => receipt[entry.key] != entry.value) ||
        receipt['requestIdentifierSha256'] is! List ||
        (receipt['requestIdentifierSha256']! as List).length != 1 ||
        !_sha256Pattern.hasMatch(
          '${(receipt['requestIdentifierSha256']! as List).single}',
        ) ||
        findIosNotificationSecretBearingField(receipt) != null ||
        _utcTimestampOrNull(receipt['completedAt']) == null) {
      throw _DriverFailure(
        'The native recovery receipt is not the exact fresh-install A/C '
        'retirement proof for this payload.',
        _assertionsAttempted,
      );
    }
    _makeOwnerOnly(_notificationRecoveryReceiptFile);
    return receipt;
  }

  Future<void> _verifyCandidateApplicationRemoved() async {
    final apps = await _installedApplicationsJson('after-cleanup');
    late final bool removed;
    try {
      removed = devicectlResultAppsAreEmpty(apps.readAsStringSync());
    } on FormatException catch (error) {
      throw _DriverFailure(
        'The cleanup application inventory was malformed: ${error.message}.',
        _assertionsAttempted,
      );
    }
    if (!removed) {
      throw _DriverFailure(
        'The cleanup adapter claimed success but the dedicated receiver still '
        'has the candidate application installed.',
        _assertionsAttempted,
      );
    }
    _applicationInstalled = false;
  }

  Future<File> _installedApplicationsJson(String label) async {
    final output = File(
      '${options.captureDirectory.path}/devicectl-apps-$label.json',
    );
    final log = File(
      '${options.captureDirectory.path}/devicectl-apps-$label.log',
    );
    final result = await _runCommand('xcrun', <String>[
      'devicectl',
      'device',
      'info',
      'apps',
      '--device',
      options.receiverDeviceId,
      '--bundle-id',
      _bundleId,
      '--json-output',
      output.path,
      '--log-output',
      log.path,
      '--quiet',
    ], timeout: const Duration(seconds: 45));
    if (result.exitCode != 0 || !_regularFile(output)) {
      throw _deviceCommandFailure(
        'devicectl could not inspect dedicated-receiver app state.',
        result,
      );
    }
    return output;
  }

  _RedactedEvidence _writeRedactedEvidence(
    String rawWindow, {
    required int visibilityBoundaryOffset,
    required int relayDrainCountBeforeVisibility,
  }) {
    final nseLines = rawWindow
        .split('\n')
        .where((line) => line.contains('PUSH_NSE_'))
        .map(_redactUiText)
        .join('\n');
    Iterable<String> retainedRecipientLines(String window, String phase) =>
        window
            .split('\n')
            .where(
              (line) =>
                  line.contains('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS') ||
                  line.contains('MKNOON_258_IOS_PAYLOAD_'),
            )
            .map((line) => 'PHASE=$phase ${_redactUiText(line)}');
    final recipientLines = <String>[
      ...retainedRecipientLines(
        rawWindow.substring(0, visibilityBoundaryOffset),
        'pre_visibility',
      ),
      ...retainedRecipientLines(
        rawWindow.substring(visibilityBoundaryOffset),
        'at_or_after_visibility',
      ),
      'HOST_OBSERVATION boundary=timestamped_visible_marker '
          'relayDrainCountBeforeVisibility=$relayDrainCountBeforeVisibility',
    ];
    final nseLog = File('${options.captureDirectory.path}/nse.redacted.log')
      ..writeAsStringSync('$nseLines\n', flush: true);
    final recipientLog = File(
      '${options.captureDirectory.path}/recipient.redacted.log',
    )..writeAsStringSync('${recipientLines.join('\n')}\n', flush: true);
    final uiLog =
        File('${options.captureDirectory.path}/ui-automation.redacted.log')
          ..writeAsStringSync(
            '${_uiLogs.map((file) => file.readAsStringSync()).join('\n')}\n',
            flush: true,
          );
    for (final entry in <MapEntry<String, File>>[
      MapEntry<String, File>('NSE log', nseLog),
      MapEntry<String, File>('recipient log', recipientLog),
      MapEntry<String, File>('UI automation log', uiLog),
    ]) {
      _rejectSecretBearingText(entry.value.readAsStringSync(), entry.key);
    }
    return _RedactedEvidence(nseLog, recipientLog, uiLog);
  }

  _RedactedEvidence _writeRecoveryRedactedEvidence(String rawWindow) {
    final nseLines = rawWindow
        .split('\n')
        .where((line) => line.contains('PUSH_NSE_'))
        .map(_redactUiText)
        .join('\n');
    final recipientLines = rawWindow
        .split('\n')
        .where(
          (line) =>
              line.contains('MKNOON_258_IOS_PAYLOAD_') ||
              line.contains('IOS_NOTIFICATION_RECOVERY'),
        )
        .map(_redactUiText)
        .join('\n');
    final nseLog = File('${options.captureDirectory.path}/nse.redacted.log')
      ..writeAsStringSync('$nseLines\n', flush: true);
    final recipientLog = File(
      '${options.captureDirectory.path}/recipient.redacted.log',
    )..writeAsStringSync('$recipientLines\n', flush: true);
    final uiLog =
        File('${options.captureDirectory.path}/ui-automation.redacted.log')
          ..writeAsStringSync(
            '${_uiLogs.map((file) => file.readAsStringSync()).join('\n')}\n',
            flush: true,
          );
    for (final entry in <MapEntry<String, File>>[
      MapEntry<String, File>('recovery NSE log', nseLog),
      MapEntry<String, File>('recovery recipient log', recipientLog),
      MapEntry<String, File>('recovery UI automation log', uiLog),
    ]) {
      _rejectSecretBearingText(entry.value.readAsStringSync(), entry.key);
      _makeOwnerOnly(entry.value);
    }
    return _RedactedEvidence(nseLog, recipientLog, uiLog);
  }

  _DirectWindowCounts _directWindowCounts(
    String rawWindow,
    _SyslogObservationBoundary boundary,
  ) {
    final window = boundary.byteOffset >= rawWindow.length
        ? ''
        : rawWindow.substring(boundary.byteOffset);
    final lines = const LineSplitter().convert(window);
    int count(bool Function(String line) predicate) =>
        lines.where(predicate).length;
    return _DirectWindowCounts(
      nseEnvelopeStaged: count(
        (line) =>
            line.contains('PUSH_NSE_ENVELOPE_STAGED') &&
            line.contains(r'"success":"true"'),
      ),
      nseDecryptOk: count((line) => line.contains('PUSH_NSE_DECRYPT_OK')),
      nseAuthorizedHandoff: count(
        (line) =>
            line.contains('PUSH_NSE_CONTENT_HANDOFF') &&
            line.contains(r'"authorized":"true"'),
      ),
      nseActiveHandoff: count(
        (line) =>
            line.contains('PUSH_NSE_CONTENT_HANDOFF') &&
            line.contains(r'"presentation":"active"'),
      ),
      nseTrustedPassiveHandoff: count(
        (line) =>
            line.contains('PUSH_NSE_CONTENT_HANDOFF') &&
            line.contains(r'"presentation":"trusted_passive"'),
      ),
      nseSanitizedHandoff: count(
        (line) =>
            line.contains('PUSH_NSE_CONTENT_HANDOFF') &&
            line.contains(r'"presentation":"sanitized"'),
      ),
      backgroundHandler: count(
        (line) => line.contains(r'"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED"'),
      ),
      recentRemoteSuppression: count(
        (line) =>
            line.contains(r'"event":"NOTIFICATION_SUPPRESSED"') &&
            line.contains(r'"reason":"recent_remote_push"'),
      ),
      matchingNotificationShown: count(
        (line) => line.contains(r'"event":"NOTIFICATION_SHOWN"'),
      ),
    );
  }

  File _writeCausalDiagnostic({
    required String status,
    _DirectWindowCounts? counts,
  }) {
    final diagnostic = File(
      '${options.captureDirectory.path}/direct-notification-diagnostic.redacted.json',
    );
    final value = <String, Object?>{
      'schema': 'mknoon.sims.ios-direct-notification-diagnostic.v1',
      'status': status,
      'phase': options.phase,
      'containsSecrets': false,
      'runIdSha256': sha256.convert(utf8.encode(options.runId)).toString(),
      'nonceSha256': sha256.convert(utf8.encode(options.nonce)).toString(),
      'receiverDeviceIdSha256': sha256
          .convert(utf8.encode(options.receiverDeviceId))
          .toString(),
      'assertionsAttempted': _assertionsAttempted,
      'providerSetupComplete': _providerSetupComplete,
      'providerCleanupComplete': _providerCleanupComplete,
      'senderProjectionSeeded': _senderProjectionSeeded,
      'senderProjectionCleaned': _senderProjectionCleaned,
      'uiCleanupComplete': _uiCleanupComplete,
      if (counts != null) 'completeWindowCounts': counts.toJson(),
      'recordedAt': DateTime.now().toUtc().toIso8601String(),
    };
    final encoded = '${jsonEncode(value)}\n';
    _rejectSecretBearingText(encoded, 'direct notification diagnostic');
    diagnostic.writeAsStringSync(encoded, flush: true);
    _makeOwnerOnly(diagnostic);
    return diagnostic;
  }

  String _redactUiText(String value) {
    var redacted = value;
    for (final key in const <String>[
      'expectedTitle',
      'expectedBody',
      'expectedMessageText',
    ]) {
      final secret = _request[key];
      if (secret is String && secret.isNotEmpty) {
        redacted = redacted.replaceAll(secret, '<redacted-fixture>');
      }
    }
    return redacted;
  }
}

final class _SyslogObservationBoundary {
  const _SyslogObservationBoundary({
    required this.byteOffset,
    required this.beginsAtLineBoundary,
  });

  final int byteOffset;
  final bool beginsAtLineBoundary;
}

final class _DirectWindowCounts {
  const _DirectWindowCounts({
    required this.nseEnvelopeStaged,
    required this.nseDecryptOk,
    required this.nseAuthorizedHandoff,
    required this.nseActiveHandoff,
    required this.nseTrustedPassiveHandoff,
    required this.nseSanitizedHandoff,
    required this.backgroundHandler,
    required this.recentRemoteSuppression,
    required this.matchingNotificationShown,
  });

  final int nseEnvelopeStaged;
  final int nseDecryptOk;
  final int nseAuthorizedHandoff;
  final int nseActiveHandoff;
  final int nseTrustedPassiveHandoff;
  final int nseSanitizedHandoff;
  final int backgroundHandler;
  final int recentRemoteSuppression;
  final int matchingNotificationShown;

  Map<String, int> toJson() => <String, int>{
    'nseEnvelopeStagedCount': nseEnvelopeStaged,
    'nseDecryptOkCount': nseDecryptOk,
    'nseAuthorizedHandoffCount': nseAuthorizedHandoff,
    'nseActiveHandoffCount': nseActiveHandoff,
    'nseTrustedPassiveHandoffCount': nseTrustedPassiveHandoff,
    'nseSanitizedHandoffCount': nseSanitizedHandoff,
    'backgroundHandlerCount': backgroundHandler,
    'recentRemoteSuppressionCount': recentRemoteSuppression,
    'matchingNotificationShownCount': matchingNotificationShown,
  };
}

final class _CommandResult {
  const _CommandResult(this.exitCode, this.stdout, this.stderr, this.timedOut);

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
}

Future<_CommandResult> _runCommand(
  String executable,
  List<String> arguments, {
  Map<String, String> environment = const <String, String>{},
  required Duration timeout,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: <String, String>{...Platform.environment, ...environment},
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  var timedOut = false;
  late final int code;
  try {
    code = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigterm);
    code = await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return 124;
      },
    );
  }
  return _CommandResult(
    timedOut ? 124 : code,
    await stdoutFuture,
    await stderrFuture,
    timedOut,
  );
}

final class _RedactedEvidence {
  const _RedactedEvidence(this.nseLog, this.recipientLog, this.uiLog);

  final File nseLog;
  final File recipientLog;
  final File uiLog;
}

final class _DriverResult {
  const _DriverResult(this.exitCode, this.json);

  factory _DriverResult.passed(int assertionsAttempted) =>
      _DriverResult(0, <String, Object?>{
        'status': 'PASS',
        'assertionsAttempted': assertionsAttempted,
        'artifactPresent': true,
        'printOnly': false,
        'exitCode': 0,
        'detail':
            'Real APNs/NSE payload fast-path automation and dedicated-device '
            'cleanup completed without a child build or manual action.',
      });

  factory _DriverResult.blocked(String blocker, String detail) =>
      _DriverResult(78, <String, Object?>{
        'status': 'BLOCKED',
        'assertionsAttempted': 0,
        'artifactPresent': false,
        'printOnly': false,
        'blocker': blocker,
        'exitCode': 78,
        'detail': detail,
      });

  factory _DriverResult.failed(String detail, int assertionsAttempted) =>
      _DriverResult(1, <String, Object?>{
        'status': 'FAIL',
        'assertionsAttempted': assertionsAttempted,
        'artifactPresent': false,
        'printOnly': false,
        'blocker': 'test',
        'exitCode': 1,
        'detail': detail,
      });

  final int exitCode;
  final Map<String, Object?> json;
}

final class _DriverBlocked implements Exception {
  const _DriverBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;
}

final class _DriverFailure implements Exception {
  const _DriverFailure(this.detail, this.assertionsAttempted);

  final String detail;
  final int assertionsAttempted;
}

String _requiredValue(List<String> args, String name) {
  for (var index = 0; index < args.length; index += 1) {
    final argument = args[index];
    if (argument == name && index + 1 < args.length) return args[index + 1];
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  throw _DriverBlocked('environment', 'Missing required argument $name.');
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name]?.trim() ?? '';
  if (value.isEmpty) {
    throw _DriverBlocked('environment', 'Missing required environment $name.');
  }
  return value;
}

Map<String, Object?> _readJson(File file, String label) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) throw const FormatException('root is not an object');
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on Object catch (error) {
    throw _DriverBlocked('environment', '$label is invalid JSON: $error');
  }
}

Map<String, Object?> _readCapturedJson(
  File file,
  String label,
  int assertionsAttempted,
) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) throw const FormatException('root is not an object');
    return decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
  } on Object catch (error) {
    throw _DriverFailure(
      'The captured $label is invalid JSON: $error',
      assertionsAttempted,
    );
  }
}

DateTime _utc(Object? value, String label) {
  final parsed = _utcTimestampOrNull(value);
  if (parsed == null || !parsed.isUtc) {
    throw _DriverFailure('$label is not a UTC timestamp.', 1);
  }
  return parsed;
}

DateTime? _utcTimestampOrNull(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return parsed != null && parsed.isUtc ? parsed : null;
}

DateTime? _markerTimestamp(String output, String marker) {
  final timestamps = _markerMatches(output, marker)
      .map((match) => DateTime.tryParse(match.group(1)!))
      .whereType<DateTime>()
      .map((timestamp) => timestamp.toUtc())
      .toSet();
  return timestamps.length == 1 ? timestamps.single : null;
}

Iterable<RegExpMatch> _markerMatches(String output, String marker) => RegExp(
  'MKNOON_258_IOS_PAYLOAD_${RegExp.escape(marker)} '
  r'at=([^\s]+)([^\r\n]*)',
).allMatches(output);

List<RegExpMatch> _markerMatchesAt(String output, String marker, DateTime at) =>
    _markerMatches(output, marker)
        .where((match) {
          final parsed = DateTime.tryParse(match.group(1)!);
          return parsed != null && parsed.toUtc().isAtSameMomentAs(at.toUtc());
        })
        .toList(growable: false);

int? _markerOffset(String output, String marker, {required DateTime at}) =>
    _markerMatchesAt(output, marker, at).firstOrNull?.start;

bool _hasExactMarkerFields(RegExpMatch match, Map<String, String> fields) {
  final rawFields = match.group(2)!.trim();
  final actual = rawFields.isEmpty
      ? const <String>{}
      : rawFields.split(RegExp(r'\s+')).toSet();
  final expected = fields.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .toSet();
  return actual.length == expected.length && actual.containsAll(expected);
}

bool _hasExactLogicalMarker(
  String output,
  String marker, {
  required DateTime at,
  required Map<String, String> fields,
}) {
  final allMatches = _markerMatches(output, marker).toList(growable: false);
  final matchesAt = _markerMatchesAt(output, marker, at);
  return allMatches.isNotEmpty &&
      matchesAt.length == allMatches.length &&
      matchesAt.every((match) => _hasExactMarkerFields(match, fields));
}

int? _uniqueMarkerOffset(
  String output,
  String marker, {
  required DateTime at,
  required Map<String, String> fields,
}) {
  final matches = _markerMatches(output, marker).toList(growable: false);
  if (matches.length != 1 ||
      _markerMatchesAt(output, marker, at).length != 1 ||
      !_hasExactMarkerFields(matches.single, fields)) {
    return null;
  }
  return matches.single.start;
}

bool _hasMarker(String output, String marker) =>
    output.contains('MKNOON_258_IOS_PAYLOAD_$marker');

String _sha256File(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

File _receiptMember(File receipt, Object? relative, String label) {
  if (relative is! String ||
      relative.isEmpty ||
      relative.startsWith('/') ||
      relative.contains('..') ||
      relative.contains(RegExp(r'[\r\n]'))) {
    throw _DriverFailure('The provider $label path is unsafe.', 1);
  }
  final file = File('${receipt.parent.path}/$relative').absolute;
  if (!_regularFile(file)) {
    throw _DriverFailure('The provider $label is missing.', 1);
  }
  return file;
}

void _rejectSecretBearingText(String value, String label) {
  final patterns = <RegExp>[
    RegExp(r'BEGIN (?:EC )?PRIVATE KEY'),
    RegExp(r'authorization\s*[:=]\s*bearer\s+\S+', caseSensitive: false),
    RegExp(
      r'"(?:ciphertext|apns[_-]?token|fcm[_-]?token|secret|password)"\s*:',
      caseSensitive: false,
    ),
  ];
  if (patterns.any((pattern) => pattern.hasMatch(value))) {
    throw _DriverFailure(
      'The redacted $label contains forbidden credential or ciphertext data.',
      1,
    );
  }
}

_DriverBlocked _deviceCommandFailure(String detail, _CommandResult result) {
  final combined = '${result.stdout}\n${result.stderr}'.toLowerCase();
  final blocker =
      combined.contains('locked') ||
          combined.contains('developer mode') ||
          combined.contains('not connected') ||
          combined.contains('timed out') ||
          result.timedOut
      ? 'deviceState'
      : 'environment';
  return _DriverBlocked(blocker, detail);
}

Object _xcodeFailure(String detail, String output) {
  final lower = output.toLowerCase();
  if (lower.contains('device is locked') ||
      lower.contains('developer mode') ||
      lower.contains('not connected') ||
      lower.contains('failed to prepare device')) {
    return _DriverBlocked('deviceState', detail);
  }
  return _DriverFailure(detail, 1);
}

bool _regularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
        FileSystemEntityType.file &&
    file.lengthSync() > 0;

void _makeOwnerOnly(File file) {
  final result = Process.runSync('chmod', <String>['600', file.path]);
  if (result.exitCode != 0) {
    throw const _DriverBlocked(
      'environment',
      'A private iOS automation intermediate could not be made owner-only.',
    );
  }
}

bool _directory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: true) ==
    FileSystemEntityType.directory;
