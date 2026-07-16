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
    'mknoon.sims.ios-provider-receiver-handoff.v1';
const String _providerRecoveryReceiptSchema =
    'mknoon.sims.ios-payload-fast-path-provider-recovery-receipt.v1';
const int _apnsDeliveryWindowSeconds = 120;
const int _nseTerminalMarkerGraceSeconds = 35;
const Duration _nseObservationWindow = Duration(
  seconds: _apnsDeliveryWindowSeconds + _nseTerminalMarkerGraceSeconds,
);

Future<void> main(List<String> args) async {
  if (args.contains('--help')) {
    stdout.writeln(
      'Usage: dart run ios_notification_payload_xcui_driver.dart '
      '--receiver <physical-udid> --peer-device <id> '
      '--application-binary <Runner.app> --xctestrun <file> '
      '--provider-driver <executable> --provider-request <json> '
      '--staging-manifest <json> --relay-target <target> '
      '--relay-key <file> --run-id <id> --nonce <nonce> '
      '--output <receipt.json> --capture-directory <directory>',
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
  late final File _providerRecoveryReceiptFile;
  late final File _receiverHandoffFile;
  late final String _receiverHandoffNonce;
  late final File _apnsPayloadFile;
  late final String _apnsPayloadSha256;
  late final String _payloadProducerSha256;
  late final String _senderPeerIdSha256;
  late final File _senderSeedReceiptFile;
  late final File _senderCleanupReceiptFile;

  Process? _syslogProcess;
  int? _syslogExitCode;
  bool _uiCleanupComplete = false;
  bool _providerSetupComplete = false;
  bool _providerCleanupComplete = false;
  bool _senderProjectionSeeded = false;
  bool _senderProjectionCleaned = false;
  int _assertionsAttempted = 0;
  final List<File> _uiLogs = <File>[];
  final List<File> _sensitiveIntermediates = <File>[];
  final List<Directory> _uiResultBundles = <Directory>[];

  Future<_DriverResult> run() async {
    await _preflight();
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
    _receiverHandoffFile = File(
      '${options.captureDirectory.path}/.ios-provider-handoff-'
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
      await _captureReceiverHandoff();
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
      if (!_uiCleanupComplete) {
        try {
          await _runUiCleanup();
        } on Object {
          // The primary typed verdict is retained. A PASS path cannot reach
          // this branch because cleanup is checked before receipt creation.
        }
      }
      if (_providerSetupComplete && !_providerCleanupComplete) {
        if (_senderProjectionSeeded && !_senderProjectionCleaned) {
          try {
            await _runSenderProjection(action: 'cleanup-sender');
          } on Object {
            // Provider recovery also owns an idempotent cleanup attempt before
            // candidate-app removal.
          }
        }
        try {
          await _runProviderCleanup();
        } on Object {
          // Same rule as above: cleanup failure prevents PASS but never hides
          // the earlier causal failure.
        }
      }
      if (_senderProjectionSeeded && !_senderProjectionCleaned) {
        try {
          await _runSenderProjection(action: 'cleanup-sender');
        } on Object {
          // A typed primary failure is retained; provider rollback has the
          // same cleanup seam before it removes the candidate app.
        }
      }
      await _stopSyslog();
      if (_rawSyslog.existsSync()) {
        // Raw device logs are never durable proof; only the filtered,
        // secret-scanned extracts survive a successful run.
        _rawSyslog.deleteSync();
      }
      if (_receiverHandoffFile.existsSync()) {
        _receiverHandoffFile.deleteSync();
      }
      for (final privateFile in <File>[
        _apnsPayloadFile,
        _senderSeedReceiptFile,
        _senderCleanupReceiptFile,
        ..._sensitiveIntermediates,
      ]) {
        if (privateFile.existsSync()) privateFile.deleteSync();
      }
      for (final resultBundle in _uiResultBundles) {
        if (resultBundle.existsSync()) resultBundle.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _preflight() async {
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

  Future<void> _captureReceiverHandoff() async {
    if (_receiverHandoffFile.existsSync()) _receiverHandoffFile.deleteSync();
    final result = await _runCommand(
      _receiverBootstrapDriver().path,
      const <String>[],
      environment: <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_MANUAL_ACTIONS_FORBIDDEN': '1',
        'SIMS_IOS_PHYSICAL_DEVICE_ID': options.receiverDeviceId,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE': _receiverHandoffNonce,
        'SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH':
            _receiverHandoffFile.path,
      },
      timeout: const Duration(minutes: 3),
    );
    if (result.exitCode == 78) {
      throw const _DriverBlocked(
        'credentials',
        'The installed app could not publish a protected APNs receiver handoff.',
      );
    }
    if (result.exitCode != 0 || !_regularFile(_receiverHandoffFile)) {
      throw _DriverFailure(
        'The private receiver bootstrap did not produce a protected handoff.',
        _assertionsAttempted,
      );
    }
    final metadata = _receiverHandoffFile.statSync();
    if ((metadata.mode & 0x3f) != 0) {
      throw _DriverFailure(
        'The private receiver handoff has group or world permissions.',
        _assertionsAttempted,
      );
    }
    final handoff = _readJson(_receiverHandoffFile, 'receiver handoff');
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
        handoff['notificationAlertSetting'] != 'enabled') {
      throw _DriverFailure(
        'The private receiver handoff is not bound to the exact receiver, '
        'peer, bundle, nonce, authorized alerts, and development APNs '
        'environment.',
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
        _receiverHandoffFile.path,
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
    final payloadText = utf8.decode(bytes, allowMalformed: false);
    final payload = _readCapturedJson(
      _apnsPayloadFile,
      'generated APNs payload',
      _assertionsAttempted,
    );
    final aps = payload['aps'];
    final alert = aps is Map ? aps['alert'] : null;
    const payloadKeys = <String>{
      'fixture_schema',
      'aps',
      'type',
      'sender_id',
      'message_id',
      'kem',
      'ciphertext',
      'nonce',
    };
    final sender = payload['sender_id'];
    final encryptedFieldsValid =
        <String>['message_id', 'kem', 'ciphertext', 'nonce'].every(
          (key) =>
              payload[key] is String && (payload[key]! as String).isNotEmpty,
        );
    final peerPattern = RegExp(
      r'^(?:12D3KooW[1-9A-HJ-NP-Za-km-z]{44}|Qm[1-9A-HJ-NP-Za-km-z]{44})$',
    );
    if (payload.keys.toSet().difference(payloadKeys).isNotEmpty ||
        payloadKeys.difference(payload.keys.toSet()).isNotEmpty ||
        payload['fixture_schema'] !=
            'mknoon.sims.ios-payload-private-fixture.v1' ||
        payload['type'] != 'new_message' ||
        sender is! String ||
        !peerPattern.hasMatch(sender) ||
        aps is! Map ||
        aps['mutable-content'] != 1 ||
        alert is! Map ||
        alert['title'] != _request['expectedTitle'] ||
        alert['body'] != _request['expectedBody'] ||
        !encryptedFieldsValid ||
        payloadText.contains(_request['expectedMessageText']! as String)) {
      throw _DriverFailure(
        'The generated APNs payload failed its encrypted exact-route contract.',
        _assertionsAttempted,
      );
    }
    final handoff = _readJson(_receiverHandoffFile, 'receiver handoff');
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
    _apnsPayloadSha256 = sha256.convert(bytes).toString();
    _senderPeerIdSha256 = sha256.convert(utf8.encode(sender)).toString();
  }

  Future<void> _runSenderProjection({required String action}) async {
    final cleanup = action == 'cleanup-sender';
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
      receiverHandoffSha256: _sha256File(_receiverHandoffFile),
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
      receiverHandoffSha256: _sha256File(_receiverHandoffFile),
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

  Future<void> _runProviderRecovery() async {
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
      'receiverHandoffSha256': _sha256File(_receiverHandoffFile),
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
  }

  Future<_CommandResult> _runProvider({
    required String action,
    required File output,
    File? setupReceipt,
  }) {
    final timeout = action == 'setup'
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
            _receiverHandoffFile.path,
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
    _SyslogObservationBoundary boundary,
  ) async {
    final deadline = providerAcceptedAt.add(_nseObservationWindow);
    var readOffset = boundary.byteOffset;
    var observedBytes = 0;
    var pendingLine = '';
    var discardInitialPartialLine = !boundary.beginsAtLineBoundary;
    var discardedBoundaryFragments = 0;
    var stagedMarkers = 0;
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
      if (line.contains('PUSH_NSE_ENVELOPE_STAGED') &&
          line.contains(r'"success":"true"')) {
        stagedMarkers += 1;
        orderedProgress = 1;
      }
      if (line.contains('PUSH_NSE_DECRYPT_OK')) {
        decryptOkMarkers += 1;
        if (orderedProgress == 1) orderedProgress = 2;
      }
      if (line.contains('PUSH_NSE_DECRYPT_FAIL')) {
        decryptFailMarkers += 1;
        if (orderedProgress > 0 && orderedProgress < 3) {
          orderedFailureMarkers += 1;
        }
      }
      if (line.contains('PUSH_NSE_TIMEOUT')) {
        timeoutMarkers += 1;
        if (orderedProgress > 0 && orderedProgress < 3) {
          orderedFailureMarkers += 1;
        }
      }
      if (line.contains('PUSH_NSE_CONTENT_HANDOFF')) {
        if (line.contains(r'"authorized":"true"')) {
          contentHandoffOkMarkers += 1;
          if (orderedProgress == 2) {
            orderedProgress = 3;
            orderedReadySequences += 1;
          }
        } else {
          contentHandoffRejectedMarkers += 1;
          if (orderedProgress > 0 && orderedProgress < 3) {
            orderedRejectedMarkers += 1;
          }
        }
      }
    }

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
        stagedMarkers: stagedMarkers,
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
            if (hasOrderedFailure() || orderedReadySequences > 0) break;
          }
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
      'Timed out waiting for real NSE envelope-staged, decrypt-success, and '
      'authorized content-handoff markers after APNs provider acceptance.',
      _assertionsAttempted,
    );
  }

  void _writeNseObservationDiagnostic({
    required String status,
    required int observationStartOffset,
    required int observedBytes,
    required int? syslogExitCode,
    required int stagedMarkers,
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
          'schema': 'mknoon.sims.ios-nse-observation-diagnostic.v1',
          'status': status,
          'observationWindowSeconds': _nseObservationWindow.inSeconds,
          'observationStartOffset': observationStartOffset,
          'observedBytes': observedBytes,
          'syslogExitCode': syslogExitCode,
          'markerCounts': <String, int>{'envelopeStaged': stagedMarkers, 'decryptOk': decryptOkMarkers, 'decryptFail': decryptFailMarkers, 'timeout': timeoutMarkers, 'contentHandoffOk': contentHandoffOkMarkers, 'contentHandoffRejected': contentHandoffRejectedMarkers, 'orderedProgress': orderedProgress, 'orderedReadySequences': orderedReadySequences, 'orderedFailure': orderedFailureMarkers, 'orderedRejected': orderedRejectedMarkers, 'discardedBoundaryFragments': discardedBoundaryFragments},
        })}\n';
    _rejectSecretBearingText(encoded, 'NSE observation diagnostic');
    diagnostic.writeAsStringSync(encoded, flush: true);
    _makeOwnerOnly(diagnostic);
  }

  Future<String> _runUiCleanup() async {
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

  Future<void> _verifyCandidateApplicationRemoved() async {
    final apps = await _installedApplicationsJson('after-cleanup');
    if (apps.readAsStringSync().contains(_bundleId)) {
      throw _DriverFailure(
        'The cleanup adapter claimed success but the dedicated receiver still '
        'has the candidate application installed.',
        _assertionsAttempted,
      );
    }
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
