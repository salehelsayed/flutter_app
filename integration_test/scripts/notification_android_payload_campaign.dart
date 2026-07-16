import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_notification_payload_campaign.dart';
import 'reaction_notification_proof_support.dart';
import '_android_app_package.dart';

/// Inputs owned by the Sims executor for the Android notification campaign.
///
/// The adapter never builds. The only accepted application input is the
/// centrally prepared `android.production_fcm` APK.
final class AndroidNotificationCampaignOptions {
  const AndroidNotificationCampaignOptions({
    required this.physicalDeviceId,
    required this.emulatorDeviceId,
    required this.prebuiltApkPath,
    required this.proofDirectory,
    required this.relayTarget,
    required this.relayKeyPath,
    required this.verbose,
    this.serviceAccountPath,
    this.relayAddresses,
  });

  final String? physicalDeviceId;
  final String? emulatorDeviceId;
  final String? prebuiltApkPath;
  final String proofDirectory;
  final String relayTarget;
  final String relayKeyPath;
  final bool verbose;
  final String? serviceAccountPath;
  final String? relayAddresses;
}

final class AndroidNotificationCampaignResult {
  const AndroidNotificationCampaignResult(this.processExitCode, this.json);

  final int processExitCode;
  final Map<String, Object?> json;
}

const List<String> _validatorIds = <String>[
  'integration_test/inbox_replay_before_ack_custody_harness.dart',
  'integration_test/notif_push_payload_persist_harness.dart',
  'integration_test/notification_tap_message_visible_proof_test.dart',
];

const List<String> _a6Checks = <String>[
  'realGoBridgeClient',
  'realRelay',
  'relayInboxSeeded',
  'replayBeforeAckObserved',
  'firstDrainAckPurgedRelay',
  'secondDrainNoDuplicateRender',
];
const List<String> _b11Checks = <String>[
  'realPeerCiphertext',
  'realGoBridgeClient',
  'realRelay',
  'stagedEnvelopeRead',
  'visibleBeforeDrain',
  'noDrainBeforeVisibility',
  'laterDrainNoDuplicate',
];
const List<String> _warmChecks = <String>[
  'androidReceiver',
  'fcmDelivered',
  'backgroundIsolateStaged',
  'airplaneModeBeforeTap',
  'messageVisibleFromStagedEnvelope',
  'noRelayDrainBeforeVisibility',
];
const List<String> _coldChecks = <String>[
  'receiverTerminatedBeforeTap',
  'notificationTapColdLaunchedApp',
  'startupIngestRan',
  'messageVisibleFromStagedEnvelope',
  'noRelayDrainBeforeVisibility',
];

Future<AndroidNotificationCampaignResult> runAndroidNotificationPayloadCampaign(
  AndroidNotificationCampaignOptions options,
) async {
  try {
    return await _AndroidNotificationCampaign(options).run();
  } on _Blocked catch (error) {
    return _blocked(
      blocker: error.blocker,
      detail: error.detail,
      artifactPresent: error.artifactPresent,
    );
  } on _Failure catch (error) {
    return _failed(
      error.detail,
      assertionsAttempted: error.assertionsAttempted,
    );
  } on AndroidAppStateBlocked catch (error) {
    return _blocked(blocker: 'environment', detail: error.detail);
  } on AndroidAppStateFailure catch (error) {
    return _failed(error.detail, assertionsAttempted: 0);
  } on ProcessException catch (error) {
    return _blocked(
      blocker: 'missingDriver',
      detail: 'Android notification command could not start: ${error.message}',
    );
  } on Object catch (error, stackTrace) {
    if (options.verbose) stderr.writeln(stackTrace);
    return _failed(
      'Android notification campaign stopped without a verdict: '
      '${error.runtimeType}.',
      assertionsAttempted: 0,
    );
  }
}

final class _AndroidNotificationCampaign {
  _AndroidNotificationCampaign(this.options)
    : packageName = resolveAndroidAppPackage();

  final AndroidNotificationCampaignOptions options;
  final String packageName;
  final Random _random = Random.secure();

  late final File apk;
  late final String physical;
  late final String emulator;
  late final File relayKey;
  late final File serviceAccount;
  late final Directory proofDirectory;
  late final String apkSha256;
  late final _NetworkState originalReceiverNetwork;
  late final String originalNotificationChannelStateSha256;
  late final _Identity senderIdentity;
  late final _Identity receiverIdentity;
  final Set<String> _campaignNotificationBodies = <String>{};

  bool _networkMutated = false;
  bool _pushTokenUnregistered = false;
  int _assertionsAttempted = 0;

  Future<AndroidNotificationCampaignResult> run() async {
    await _preflight();
    await proofDirectory.create(recursive: true);
    await _removeScenarioArtifacts();

    final captured = <Map<String, Object?>>[];
    AndroidAppStateGuard? appStateGuard;
    var proofCompleted = false;
    try {
      appStateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physical, emulator],
        packageName: packageName,
        backupLabel: 'notification',
      );
      await appStateGuard.prepareFreshInstall(device: physical, artifact: apk);
      await _configureFreshInstall(physical, 'sims-notification-sender');
      await appStateGuard.prepareFreshInstall(device: emulator, artifact: apk);
      await _configureFreshInstall(emulator, 'sims-notification-receiver');
      await _launch(physical);
      await _launch(emulator);
      senderIdentity = await _identity(physical);
      receiverIdentity = await _identity(emulator);
      await _establishContacts();
      await _runAction(
        emulator,
        action: androidNotificationRestorePushAction,
        runId: _token('setup'),
      );
      await _requireNoAppNotification();

      final a6 = await _runA6();
      captured.add(await _writeScenarioArtifact(a6));

      final warm = await _runWarmPayloadLeg();
      captured
        ..add(await _writeScenarioArtifact(warm.b11))
        ..add(await _writeScenarioArtifact(warm.b12));

      final cold = await _runColdPayloadLeg();
      captured.add(await _writeScenarioArtifact(cold));
      proofCompleted = true;
    } finally {
      final restorationFailures = <String>[];
      Future<void> attempt(String label, Future<void> Function() action) async {
        try {
          await action();
        } on Object catch (error) {
          restorationFailures.add(
            error is AndroidAppStateFailure ? '$label: ${error.detail}' : label,
          );
        }
      }

      if (appStateGuard != null) {
        if (_networkMutated) {
          await attempt('network', () async {
            await originalReceiverNetwork.restore(this);
            _networkMutated = false;
          });
        }
        if (_pushTokenUnregistered) {
          await attempt('push-registration', _restorePushRegistration);
        }
        await attempt('receiver-config', () async {
          await _removeAppFile(emulator, 'intro_e2e_config.json');
          await _removeAppFile(emulator, 'intro_e2e_result.json');
        });
        await attempt('sender-config', () async {
          await _removeAppFile(physical, 'intro_e2e_config.json');
          await _removeAppFile(physical, 'intro_e2e_result.json');
        });
        await attempt('campaign-notifications', _cleanupCampaignNotifications);
        await attempt('app-state', appStateGuard.restoreAll);
        await attempt('notification-state', _verifyExactNotificationOsState);
      }
      if (!proofCompleted || restorationFailures.isNotEmpty) {
        await attempt('partial-artifacts', _removeScenarioArtifacts);
      }
      if (restorationFailures.isNotEmpty) {
        throw _Failure(
          'Exact Android campaign restoration failed at '
          '${restorationFailures.join(', ')}; no passing evidence was retained.',
          assertionsAttempted: _assertionsAttempted,
        );
      }
    }

    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: androidNotificationCapabilityId,
      validatorIds: _validatorIds,
      payload: <String, Object?>{
        'status': 'passed',
        'scenarioIds': captured
            .map((item) => item['scenario'])
            .toList(growable: false),
        'targetIds': <String>[physical, emulator],
        'targetKinds': const <String>['physical', 'emulator'],
        'preparedArtifactPath': apk.resolveSymbolicLinksSync(),
        'preparedArtifactSha256': apkSha256,
        'buildProfile': androidNotificationBuildProfileId,
        'captureArtifacts': captured,
        'childBuildCount': 0,
        'networkStateRestored': !_networkMutated,
        'pushRegistrationRestored': !_pushTokenUnregistered,
        'appStateRestored': appStateGuard.restored,
        'notificationStateRestored': true,
      },
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: _validatorIds,
    );
    if (!audit.isValid) {
      final aggregate = File(evidence.path);
      if (aggregate.existsSync()) aggregate.deleteSync();
      await _removeScenarioArtifacts();
      throw _Failure(
        'Aggregate notification evidence failed: ${audit.detail}',
        assertionsAttempted: 4,
      );
    }
    return AndroidNotificationCampaignResult(0, <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': 4,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'A6, B11, and Android B12 warm/cold passed with one centrally '
          'prepared production-FCM APK, zero child builds, and exact target '
          'state restoration.',
      'artifactEvidence': evidence.toJson(),
    });
  }

  Future<void> _preflight() async {
    final apkPath = options.prebuiltApkPath?.trim() ?? '';
    if (apkPath.isEmpty) {
      throw const _Blocked(
        'missingArtifact',
        'SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM is required; child builds are '
            'forbidden.',
      );
    }
    apk = File(apkPath).absolute;
    if (!_isRegularFile(apk) || apk.lengthSync() <= 0) {
      throw _Blocked(
        'missingArtifact',
        'The central android.production_fcm APK is missing or empty at '
            '${apk.path}.',
      );
    }
    final profile = Platform.environment['SIMS_ARTIFACT_PROFILE_ID']?.trim();
    if (profile != null &&
        profile.isNotEmpty &&
        profile != androidNotificationBuildProfileId) {
      throw _Blocked(
        'missingArtifact',
        'Build profile "$profile" is not $androidNotificationBuildProfileId.',
        artifactPresent: true,
      );
    }
    apkSha256 = sha256.convert(apk.readAsBytesSync()).toString();

    physical = options.physicalDeviceId?.trim() ?? '';
    emulator = options.emulatorDeviceId?.trim() ?? '';
    final safe = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    if (!safe.hasMatch(physical) ||
        !safe.hasMatch(emulator) ||
        physical == emulator ||
        !emulator.startsWith('emulator-')) {
      throw const _Blocked(
        'targetUnavailable',
        'The campaign requires one explicit physical Android and one distinct '
            'Android emulator.',
      );
    }

    relayKey = File(options.relayKeyPath).absolute;
    if (options.relayTarget.trim().isEmpty || !_isRegularFile(relayKey)) {
      throw const _Blocked(
        'environment',
        'SIMS_NOTIFICATION_RELAY_TARGET and a readable relay SSH key are '
            'required.',
      );
    }
    final credentialPath = options.serviceAccountPath?.trim().isNotEmpty == true
        ? options.serviceAccountPath!.trim()
        : Platform.environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']
                  ?.trim()
                  .isNotEmpty ==
              true
        ? Platform.environment['SIMS_PROVIDER_FCM_CREDENTIAL_PATH']!.trim()
        : Platform.environment['FIREBASE_SERVICE_ACCOUNT']?.trim() ?? '';
    serviceAccount = File(credentialPath).absolute;
    if (!_isUsableServiceAccount(serviceAccount)) {
      throw const _Blocked(
        'credentials',
        'A readable FCM service-account JSON containing project_id is '
            'required.',
      );
    }
    final relayAddresses = options.relayAddresses?.trim().isNotEmpty == true
        ? options.relayAddresses!.trim()
        : Platform.environment['MKNOON_RELAY_ADDRESSES']?.trim() ?? '';
    if (relayAddresses.isEmpty || relayAddresses.contains(RegExp(r'[\r\n]'))) {
      throw const _Blocked(
        'environment',
        'MKNOON_RELAY_ADDRESSES must bind the prepared app to the staging '
            'relay.',
      );
    }

    final version = await _adb(null, const <String>[
      'version',
    ], allowFailure: true);
    if (version.exitCode != 0) {
      throw const _Blocked('missingDriver', 'ADB is unavailable.');
    }
    for (final device in <String>[physical, emulator]) {
      final state = await _adb(device, const <String>[
        'get-state',
      ], allowFailure: true);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw _Blocked(
          'targetUnavailable',
          'Android target $device is not attached in device state.',
        );
      }
    }
    final physicalQemu = await _shellText(physical, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    final emulatorQemu = await _shellText(emulator, const <String>[
      'getprop',
      'ro.kernel.qemu',
    ]);
    if (physicalQemu.trim() == '1' || emulatorQemu.trim() != '1') {
      throw const _Blocked(
        'targetUnavailable',
        'Assigned Android target roles are not physical-sender and '
            'emulator-receiver.',
      );
    }
    final relay = await _ssh(const <String>[
      'systemctl',
      'is-active',
      'relay-server',
    ], allowFailure: true);
    if (relay.exitCode != 0 || '${relay.stdout}'.trim() != 'active') {
      throw const _Blocked(
        'environment',
        'The staging relay is unreachable or relay-server is not active.',
      );
    }
    if (!await _networkAvailable(physical) ||
        !await _networkAvailable(emulator)) {
      throw const _Blocked(
        'targetUnavailable',
        'Both Android targets must begin with usable connectivity.',
      );
    }
    originalReceiverNetwork = await _NetworkState.capture(this);
    final notificationDump = await _notificationDump();
    final baselineCards = extractActiveNotificationCards(
      notificationDump,
      packageName: packageName,
    );
    if (baselineCards.isNotEmpty) {
      throw const _Blocked(
        'environment',
        'The receiver has pre-existing app notification cards. The campaign '
            'will not force-stop or cancel cards whose PendingIntents it cannot '
            'restore exactly.',
      );
    }
    originalNotificationChannelStateSha256 =
        androidNotificationChannelStateSha256(
          notificationDump,
          packageName: packageName,
        );
    proofDirectory = Directory(options.proofDirectory).absolute;
  }

  Future<Map<String, Object?>> _runA6() async {
    _assertionsAttempted = 1;
    final runId = _token('a6');
    final nonce = _token('nonce');
    final marker = 'Sims A6 replay $runId';

    await _runAction(
      emulator,
      action: androidNotificationUnregisterPushAction,
      runId: runId,
      nonce: nonce,
    );
    _pushTokenUnregistered = true;
    await _setNetworkAvailable(false);
    _networkMutated = true;
    await _waitFor(
      'receiver offline for A6',
      const Duration(seconds: 30),
      () async => !await _networkAvailable(emulator),
    );

    final observer = _actionConfig(
      action: androidNotificationA6ObserveAction,
      runId: runId,
      nonce: nonce,
      contactPeerId: senderIdentity.peerId,
      expectedText: marker,
    );
    await _stageConfig(emulator, observer);
    await _waitForActionResult(
      emulator,
      observer,
      status: 'armed',
      timeout: const Duration(seconds: 20),
    );
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _setNetworkAvailable(true);
    await _waitFor(
      'receiver network restored for A6 drain',
      const Duration(seconds: 45),
      () => _networkAvailable(emulator),
    );
    final observed = await _waitForActionResult(
      emulator,
      observer,
      status: 'complete',
      timeout: const Duration(minutes: 3),
    );
    await originalReceiverNetwork.restore(this);
    _networkMutated = false;
    if (observed['messageIdPrefix'] !=
            safeNotificationIdPrefix(sent.messageId) ||
        observed['messageCountAfterFirstDrain'] != 1 ||
        observed['messageCountAfterSecondDrain'] != 1 ||
        observed['pendingRelayEntries'] != 0 ||
        (observed['ackedEntries'] as num? ?? 0) < 1) {
      throw _Failure(
        'A6 replay/ack evidence did not bind to the sent message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final events =
        (observed['events'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final replay = events.indexOf('P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED');
    final ack = events.indexOf('P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS');
    if (replay < 0 || ack <= replay) {
      throw _Failure(
        'A6 did not prove replay-before-ack ordering.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    await _runAction(
      emulator,
      action: androidNotificationRestorePushAction,
      runId: _token('restore'),
    );
    _pushTokenUnregistered = false;

    return androidNotificationScenarioArtifact(
      testCase: 'TC-A6',
      scenario: 'tc_a6_replay_before_ack_custody',
      devices: <String>[physical, emulator],
      passedChecks: _a6Checks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(sent.messageId),
        'senderTransport': sent.transport,
        'eventOrder': <String>[
          'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
          'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS',
        ],
        'ackedEntries': observed['ackedEntries'],
        'pendingAfterSecondDrain': observed['pendingRelayEntries'],
      },
    );
  }

  Future<({Map<String, Object?> b11, Map<String, Object?> b12})>
  _runWarmPayloadLeg() async {
    _assertionsAttempted = 3;
    final runId = _token('warm');
    final nonce = _token('nonce');
    final marker = 'Sims B11 warm payload $runId';
    _campaignNotificationBodies.add(marker);
    await _requireNoAppNotification();
    await _runAction(
      emulator,
      action: androidNotificationStopNodeAndClearStagingAction,
      runId: runId,
      nonce: nonce,
    );
    await _adb(emulator, const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ]);
    final logcatCursor = await _deviceLogcatCursor();

    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);
    final staged = await _waitForStagedEnvelope(sent: sent, notBefore: sentAt);
    await _waitForNotification(marker);

    await _setNetworkAvailable(false);
    _networkMutated = true;
    await _waitFor(
      'warm receiver airplane mode',
      const Duration(seconds: 30),
      () async => !await _networkAvailable(emulator),
    );
    final observer = _actionConfig(
      action: androidNotificationPostTapObserveAction,
      runId: runId,
      nonce: nonce,
      contactPeerId: senderIdentity.peerId,
      expectedText: marker,
      expectedMessageId: sent.messageId,
      requireStagedBeforeTap: true,
    );
    await _stageConfig(emulator, observer);
    final armed = await _waitForActionResult(
      emulator,
      observer,
      status: 'armed',
      timeout: const Duration(seconds: 30),
    );
    if (armed['stagedEnvelopeObserved'] != true) {
      throw _Failure(
        'Warm FCM staging was not observed before the tap.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    await _tapNotification(marker);
    final observed = await _waitForActionResult(
      emulator,
      observer,
      status: 'complete',
      timeout: const Duration(minutes: 2),
    );
    await _waitForUiText(marker);
    final preRestoreLog = await _logcatSince(logcatCursor);
    if (notificationWindowContainsRelayDrain(preRestoreLog) ||
        observed['messageCount'] != 1 ||
        observed['stagedEnvelopeCleared'] != true) {
      throw _Failure(
        'Warm tap did not render once from staging before any relay drain.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    await originalReceiverNetwork.restore(this);
    _networkMutated = false;
    final drain = await _restartAndDrain(
      runId: runId,
      nonce: nonce,
      marker: marker,
      messageId: sent.messageId,
    );
    if (drain['messageCount'] != 1 || drain['pendingRelayEntries'] != 0) {
      throw _Failure(
        'Warm later relay drain duplicated or retained the message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    final commonEvidence = <String, Object?>{
      'messageIdPrefix': safeNotificationIdPrefix(sent.messageId),
      'senderTransport': sent.transport,
      'stagedEnvelope': staged.toJson(),
      'providerAccepted': true,
      'networkUnavailableAtTap': true,
      'messageCountBeforeDrain': observed['messageCount'],
      'messageCountAfterDrain': drain['messageCount'],
      'childBuildCount': 0,
    };
    return (
      b11: androidNotificationScenarioArtifact(
        testCase: 'TC-B11',
        scenario: 'tc_b11_payload_persist_pre_drain',
        devices: <String>[physical, emulator],
        passedChecks: _b11Checks,
        capturedAt: DateTime.now(),
        evidence: commonEvidence,
      ),
      b12: androidNotificationScenarioArtifact(
        testCase: 'TC-B12',
        scenario: 'payload_fast_path_android_receiver',
        devices: <String>[physical, emulator],
        passedChecks: _warmChecks,
        capturedAt: DateTime.now(),
        evidence: <String, Object?>{
          ...commonEvidence,
          'warmProcessAliveBeforeTap': true,
          'boundedNotificationTap': true,
        },
      ),
    );
  }

  Future<Map<String, Object?>> _runColdPayloadLeg() async {
    _assertionsAttempted = 4;
    final runId = _token('cold');
    final nonce = _token('nonce');
    final marker = 'Sims B12 cold payload $runId';
    _campaignNotificationBodies.add(marker);
    await _requireNoAppNotification();
    await _runAction(
      emulator,
      action: androidNotificationClearStagingAction,
      runId: runId,
      nonce: nonce,
    );
    await _terminateReceiver();
    final logcatCursor = await _deviceLogcatCursor();

    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);
    final staged = await _waitForStagedEnvelope(sent: sent, notBefore: sentAt);
    await _waitForNotification(marker);
    await _terminateReceiver();

    await _setNetworkAvailable(false);
    _networkMutated = true;
    await _waitFor(
      'cold receiver airplane mode',
      const Duration(seconds: 30),
      () async => !await _networkAvailable(emulator),
    );
    if ((await _pidof(emulator)).isNotEmpty) {
      throw _Failure(
        'Cold receiver process restarted before notification tap.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final observer = _actionConfig(
      action: androidNotificationPostTapObserveAction,
      runId: runId,
      nonce: nonce,
      contactPeerId: senderIdentity.peerId,
      expectedText: marker,
      expectedMessageId: sent.messageId,
      requireStagedBeforeTap: false,
    );
    await _stageConfig(emulator, observer);
    await _tapNotification(marker);
    await _waitFor(
      'cold notification launch PID',
      const Duration(seconds: 30),
      () async => (await _pidof(emulator)).isNotEmpty,
    );
    final observed = await _waitForActionResult(
      emulator,
      observer,
      status: 'complete',
      timeout: const Duration(minutes: 3),
    );
    await _waitForUiText(marker);
    final preRestoreLog = await _logcatSince(logcatCursor);
    if (notificationWindowContainsRelayDrain(preRestoreLog) ||
        observed['messageCount'] != 1 ||
        observed['stagedEnvelopeCleared'] != true) {
      throw _Failure(
        'Cold tap did not startup-ingest exactly once before relay drain.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    await originalReceiverNetwork.restore(this);
    _networkMutated = false;
    final drain = await _restartAndDrain(
      runId: runId,
      nonce: nonce,
      marker: marker,
      messageId: sent.messageId,
    );
    if (drain['messageCount'] != 1 || drain['pendingRelayEntries'] != 0) {
      throw _Failure(
        'Cold later relay drain duplicated or retained the message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    return androidNotificationScenarioArtifact(
      testCase: 'TC-B12',
      scenario: 'payload_fast_path_cold_kill',
      devices: <String>[physical, emulator],
      passedChecks: _coldChecks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(sent.messageId),
        'senderTransport': sent.transport,
        'stagedEnvelope': staged.toJson(),
        'providerAccepted': true,
        'receiverPidEmptyBeforeTap': true,
        'newPidObservedAfterTap': true,
        'networkUnavailableAtTap': true,
        'messageCountBeforeDrain': observed['messageCount'],
        'messageCountAfterDrain': drain['messageCount'],
        'childBuildCount': 0,
      },
    );
  }

  Future<Map<String, Object?>> _restartAndDrain({
    required String runId,
    required String nonce,
    required String marker,
    required String messageId,
  }) async {
    await _terminateReceiver();
    await _launch(emulator);
    await _identity(emulator);
    return _runAction(
      emulator,
      action: androidNotificationDrainObserveAction,
      runId: '$runId-drain',
      nonce: nonce,
      contactPeerId: senderIdentity.peerId,
      expectedText: marker,
      expectedMessageId: messageId,
      timeout: const Duration(minutes: 3),
    );
  }

  Future<void> _establishContacts() async {
    await _runGenericConfig(physical, <String, Object?>{
      'stepId': 'notification-contacts-${_token('step')}',
      'add_contacts': <Object?>[
        <String, Object?>{
          'qrPayload': receiverIdentity.qrPayload,
          if (receiverIdentity.mlKemPublicKey != null)
            'mlKemPublicKey': receiverIdentity.mlKemPublicKey,
        },
      ],
      'send_contact_requests_for_added_contacts': true,
      'contact_settle_delay_ms': 1500,
    });
    final accepted = await _runGenericConfig(emulator, <String, Object?>{
      'stepId': 'notification-accept-${_token('step')}',
      'contact_request_action': 'accept_all',
      'contact_settle_delay_ms': 1500,
    });
    final snapshot = accepted['snapshot'];
    if (snapshot is! Map ||
        (snapshot['contacts'] as List?)?.whereType<Map>().any(
              (contact) => contact['peerId'] == senderIdentity.peerId,
            ) !=
            true) {
      throw const _Failure(
        'Production Android contacts did not converge.',
        assertionsAttempted: 0,
      );
    }
  }

  Future<_SentMessage> _sendText(
    String text, {
    required String runId,
    required String receiverPeerId,
  }) async {
    final result = await _runGenericConfig(physical, <String, Object?>{
      'stepId': 'notification-send-$runId',
      'send_chat_messages': <Object?>[
        <String, Object?>{'targetPeerId': receiverPeerId, 'text': text},
      ],
    });
    final chatAction = result['chatAction'];
    final sent = chatAction is Map ? chatAction['sent'] : null;
    if (sent is! List || sent.length != 1 || sent.single is! Map) {
      throw _Failure(
        'Production sender did not return one exact message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final value = Map<String, Object?>.from(sent.single as Map);
    final messageId = value['messageId'];
    final transport = value['transport'];
    final status = value['status'];
    if (messageId is! String ||
        messageId.isEmpty ||
        value['targetPeerId'] != receiverPeerId ||
        value['text'] != text ||
        transport is! String ||
        status is! String ||
        !<String>{'delivered', 'inboxed', 'sent'}.contains(status)) {
      throw _Failure(
        'Production sender result was not accepted/inboxed.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return _SentMessage(messageId: messageId, transport: transport);
  }

  Future<Map<String, Object?>> _runGenericConfig(
    String device,
    Map<String, Object?> config,
  ) async {
    await _stageConfig(device, config);
    final raw = await _waitForValue<String>(
      '${config['stepId']} completion',
      const Duration(minutes: 3),
      () => _readAppFile(device, 'intro_e2e_result.json'),
      accept: (raw) {
        try {
          final result = _object(jsonDecode(raw));
          return result['stepId'] == config['stepId'] &&
              <String>{'complete', 'failed'}.contains(result['status']);
        } on Object {
          return false;
        }
      },
    );
    final result = _object(jsonDecode(raw));
    if (result['status'] != 'complete' || result['success'] != true) {
      throw _Failure(
        'Installed main-app step ${config['stepId']} failed.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return result;
  }

  Map<String, Object?> _actionConfig({
    required String action,
    required String runId,
    String? nonce,
    String? contactPeerId,
    String? expectedText,
    String? expectedMessageId,
    bool requireStagedBeforeTap = false,
    Duration timeout = const Duration(minutes: 2),
  }) => <String, Object?>{
    'schema': androidNotificationPayloadE2ERequestSchema,
    'transport_action': action,
    'scenario': androidNotificationPayloadE2EScenario,
    'stepId': 'notification-$action-$runId',
    'runId': runId,
    'nonce': nonce ?? _token('nonce'),
    'contactPeerId': ?contactPeerId,
    'expectedText': ?expectedText,
    'expectedMessageId': ?expectedMessageId,
    if (requireStagedBeforeTap) 'requireStagedBeforeTap': true,
    'timeoutMs': timeout.inMilliseconds,
  };

  Future<Map<String, Object?>> _runAction(
    String device, {
    required String action,
    required String runId,
    String? nonce,
    String? contactPeerId,
    String? expectedText,
    String? expectedMessageId,
    bool requireStagedBeforeTap = false,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final config = _actionConfig(
      action: action,
      runId: runId,
      nonce: nonce,
      contactPeerId: contactPeerId,
      expectedText: expectedText,
      expectedMessageId: expectedMessageId,
      requireStagedBeforeTap: requireStagedBeforeTap,
      timeout: timeout,
    );
    await _stageConfig(device, config);
    return _waitForActionResult(
      device,
      config,
      status: 'complete',
      timeout: timeout + const Duration(seconds: 15),
    );
  }

  Future<Map<String, Object?>> _waitForActionResult(
    String device,
    Map<String, Object?> config, {
    required String status,
    required Duration timeout,
  }) async {
    final raw = await _waitForValue<String>(
      '${config['stepId']}/$status',
      timeout,
      () => _readAppFile(device, 'intro_e2e_result.json'),
      accept: (raw) {
        try {
          final result = _object(jsonDecode(raw));
          return result['stepId'] == config['stepId'] &&
              (result['status'] == status || result['status'] == 'failed');
        } on Object {
          return false;
        }
      },
    );
    final result = _object(jsonDecode(raw));
    switch (classifyAndroidNotificationActionResult(
      result: result,
      config: config,
      expectedStatus: status,
    )) {
      case AndroidNotificationActionResultDisposition.bindingMismatch:
        throw _Failure(
          'Installed notification action ${config['transport_action']} '
          'returned a receipt with the wrong schema/action/scenario/step/'
          'run/nonce binding.',
          assertionsAttempted: _assertionsAttempted,
        );
      case AndroidNotificationActionResultDisposition.boundFailure:
        final errorType = safeAndroidNotificationActionErrorType(
          result['errorType'],
        );
        throw _Failure(
          'Installed notification action ${config['transport_action']} '
          'returned a bound failure receipt (errorType=$errorType).',
          assertionsAttempted: _assertionsAttempted,
        );
      case AndroidNotificationActionResultDisposition.invalidCompletion:
        throw _Failure(
          'Installed notification action ${config['transport_action']} '
          'returned an invalid bound status/success tuple.',
          assertionsAttempted: _assertionsAttempted,
        );
      case AndroidNotificationActionResultDisposition.accepted:
        break;
    }
    return result;
  }

  Future<AndroidStagedEnvelopeObservation> _waitForStagedEnvelope({
    required _SentMessage sent,
    required DateTime notBefore,
  }) => _waitForValue<AndroidStagedEnvelopeObservation>(
    'run-bound Android FCM staged ciphertext',
    const Duration(minutes: 2),
    () async {
      final encoded = await _stagedEnvelopeJson(sent.messageId);
      if (encoded == null) return null;
      try {
        return parseAndroidStagedEnvelopeObservation(
          encoded,
          expectedMessageId: sent.messageId,
          expectedSenderPeerId: senderIdentity.peerId,
          notBefore: notBefore,
        );
      } on FormatException {
        return null;
      }
    },
  );

  Future<String?> _stagedEnvelopeJson(String messageId) async {
    final listed = await _adb(emulator, <String>[
      'shell',
      'run-as',
      packageName,
      'ls',
      'files/PushEnvelopeStaging',
    ], allowFailure: true);
    if (listed.exitCode != 0) return null;
    for (final name in '${listed.stdout}'.split(RegExp(r'\s+'))) {
      if (!RegExp(r'^nonce-v1-[0-9a-f]+\.json$').hasMatch(name)) continue;
      final read = await _adb(emulator, <String>[
        'shell',
        'run-as',
        packageName,
        'cat',
        'files/PushEnvelopeStaging/$name',
      ], allowFailure: true);
      if (read.exitCode != 0) continue;
      final encoded = '${read.stdout}'.trim();
      try {
        final decoded = _object(jsonDecode(encoded));
        if (decoded['messageId'] == messageId) return encoded;
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<void> _waitForProviderSend(DateTime since) async {
    await _waitFor(
      'relay provider acceptance for ${receiverIdentity.peerPrefix}',
      const Duration(minutes: 2),
      () async => relayJournalContainsAndroidProviderSend(
        await _relayJournalSince(since),
        recipientPeerId: receiverIdentity.peerId,
      ),
    );
  }

  Future<String> _relayJournalSince(DateTime since) async {
    final result = await _ssh(<String>[
      'journalctl',
      '-u',
      'relay-server',
      '--since',
      '@${since.toUtc().millisecondsSinceEpoch ~/ 1000}',
      '--no-pager',
      '-o',
      'cat',
    ]);
    return '${result.stdout}';
  }

  Future<ActiveNotificationCard> _waitForNotification(String marker) =>
      _waitForValue<ActiveNotificationCard>(
        'run-bound Android FCM notification card',
        const Duration(minutes: 2),
        () async {
          final cards = extractActiveNotificationCards(
            await _notificationDump(),
            packageName: packageName,
          );
          final matching = cards
              .where((card) => card.body == marker)
              .toList(growable: false);
          return matching.length == 1 ? matching.single : null;
        },
      );

  Future<void> _requireNoAppNotification() async {
    final cards = extractActiveNotificationCards(
      await _notificationDump(),
      packageName: packageName,
    );
    if (cards.isNotEmpty) {
      throw _Failure(
        'The receiver notification slate contains unrelated app cards.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
  }

  Future<void> _cleanupCampaignNotifications() async {
    for (final marker in _campaignNotificationBodies) {
      for (var attempt = 0; attempt < 3; attempt++) {
        final matching = extractActiveNotificationCards(
          await _notificationDump(),
          packageName: packageName,
        ).where((card) => card.body == marker).toList(growable: false);
        if (matching.isEmpty) break;
        await _tapNotification(marker);
        await _waitFor(
          'campaign notification dismissal',
          const Duration(seconds: 15),
          () async => !extractActiveNotificationCards(
            await _notificationDump(),
            packageName: packageName,
          ).any((card) => card.body == marker),
        );
      }
    }
    await _requireNoAppNotification();
  }

  Future<void> _verifyExactNotificationOsState() async {
    final dump = await _notificationDump();
    final cards = extractActiveNotificationCards(
      dump,
      packageName: packageName,
    );
    final channelState = androidNotificationChannelStateSha256(
      dump,
      packageName: packageName,
    );
    if (cards.isNotEmpty ||
        channelState != originalNotificationChannelStateSha256) {
      throw StateError(
        'notification cards/channels did not return to their exact baseline',
      );
    }
  }

  Future<String> _notificationDump() async => _shellText(
    emulator,
    const <String>['dumpsys', 'notification', '--noredact'],
  );

  Future<String> _deviceLogcatCursor() async {
    final value = (await _shellText(emulator, const <String>[
      'date',
      '+%s.%3N',
    ])).trim();
    if (!RegExp(r'^\d{10,}\.\d{3}$').hasMatch(value)) {
      throw _Failure(
        'Android logcat cursor is unavailable without clearing device logs.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return value;
  }

  Future<String> _logcatSince(String cursor) async {
    final result = await _adb(emulator, <String>[
      'logcat',
      '-d',
      '-t',
      cursor,
      '-v',
      'brief',
    ]);
    return '${result.stdout}';
  }

  Future<void> _tapNotification(String marker) async {
    await _adb(emulator, const <String>[
      'shell',
      'cmd',
      'statusbar',
      'expand-notifications',
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    for (var attempt = 0; attempt < 6; attempt++) {
      final center = findSemanticNodeCenter(await _uiDump(), marker);
      if (center != null) {
        await _adb(emulator, <String>[
          'shell',
          'input',
          'tap',
          '${center.$1}',
          '${center.$2}',
        ]);
        return;
      }
      if (attempt < 5) {
        await _adb(emulator, const <String>[
          'shell',
          'input',
          'swipe',
          '540',
          '1900',
          '540',
          '700',
          '500',
        ], allowFailure: true);
      }
    }
    throw _Failure(
      'UIAutomator could not find the exact notification body; refusing a '
      'fixed-coordinate tap.',
      assertionsAttempted: _assertionsAttempted,
    );
  }

  Future<void> _waitForUiText(String marker) async {
    await _waitFor(
      'message visible in the tapped conversation',
      const Duration(seconds: 60),
      () async => findSemanticNodeCenter(await _uiDump(), marker) != null,
    );
  }

  Future<String> _uiDump() async {
    const remote = '/data/local/tmp/sims_notification_payload.xml';
    await _adb(emulator, const <String>[
      'shell',
      'uiautomator',
      'dump',
      remote,
    ], allowFailure: true);
    final result = await _adb(emulator, const <String>[
      'shell',
      'cat',
      remote,
    ], allowFailure: true);
    await _adb(emulator, const <String>[
      'shell',
      'rm',
      '-f',
      remote,
    ], allowFailure: true);
    return '${result.stdout}';
  }

  Future<void> _terminateReceiver() async {
    await _adb(emulator, const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ], allowFailure: true);
    await Future<void>.delayed(const Duration(milliseconds: 750));
    await _adb(emulator, <String>['shell', 'am', 'kill', packageName]);
    if (!await _receiverProcessAbsentWithin(const Duration(seconds: 5))) {
      // `stop-app` preserves push wake eligibility. Never use `force-stop`
      // here because it sets Android's stopped-package bit.
      await _adb(emulator, <String>[
        'shell',
        'cmd',
        'activity',
        'stop-app',
        packageName,
      ]);
    }
    await _waitFor(
      'receiver process termination',
      const Duration(seconds: 30),
      () async => (await _pidof(emulator)).isEmpty,
    );
  }

  Future<bool> _receiverProcessAbsentWithin(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if ((await _pidof(emulator)).isEmpty) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<String> _pidof(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'pidof',
      packageName,
    ], allowFailure: true);
    return '${result.stdout}'.trim();
  }

  Future<void> _configureFreshInstall(String device, String username) async {
    await _writeAppFile(
      device,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': username}),
    );
    await _adb(device, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      'android.permission.POST_NOTIFICATIONS',
    ], allowFailure: true);
  }

  Future<void> _launch(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/.MainActivity',
    ], allowFailure: true);
    final output = '${result.stdout}\n${result.stderr}';
    if (result.exitCode != 0 ||
        !RegExp(
          r'^Status:[ \t]+ok[ \t]*\r?$',
          multiLine: true,
        ).hasMatch(output)) {
      throw _Failure(
        'The installed app could not launch on $device.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
  }

  Future<_Identity> _identity(String device) async {
    final raw = await _waitForValue<String>(
      'installed main-app identity on $device',
      const Duration(minutes: 2),
      () => _readAppFile(device, 'intro_e2e_identity.json'),
    );
    try {
      final decoded = _object(jsonDecode(raw));
      final qrPayload = decoded['qrPayload'] as String;
      final qr = _object(jsonDecode(qrPayload));
      final peerId = qr['ns'] as String;
      if (peerId.isEmpty) throw const FormatException();
      return _Identity(
        peerId: peerId,
        qrPayload: qrPayload,
        mlKemPublicKey: decoded['mlKemPublicKey'] as String?,
      );
    } on Object {
      throw _Failure(
        'Installed main-app identity export was malformed.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
  }

  Future<void> _stageConfig(String device, Map<String, Object?> config) async {
    await _removeAppFile(device, 'intro_e2e_result.json');
    await _removeAppFile(device, 'intro_e2e_config.json');
    await _writeAppFile(device, 'intro_e2e_config.json', jsonEncode(config));
  }

  Future<String?> _readAppFile(String device, String name) async {
    final result = await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'cat',
      'app_flutter/$name',
    ], allowFailure: true);
    if (result.exitCode != 0 || '${result.stdout}'.trim().isEmpty) return null;
    return '${result.stdout}'.trim();
  }

  Future<void> _writeAppFile(
    String device,
    String name,
    String contents,
  ) async {
    final local = File(
      '${Directory.systemTemp.path}/sims-${_token('file')}-$name',
    );
    await local.writeAsString(contents, flush: true);
    final remote = '/data/local/tmp/sims-notification-$name';
    try {
      await _adb(device, <String>['push', local.path, remote]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$name',
      ]);
    } finally {
      if (await local.exists()) await local.delete();
      await _adb(device, <String>[
        'shell',
        'rm',
        '-f',
        remote,
      ], allowFailure: true);
    }
  }

  Future<void> _removeAppFile(String device, String name) async {
    await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'rm',
      '-f',
      'app_flutter/$name',
    ], allowFailure: true);
  }

  Future<void> _setNetworkAvailable(bool available) async {
    await _adb(emulator, <String>[
      'shell',
      'cmd',
      'connectivity',
      'airplane-mode',
      available ? 'disable' : 'enable',
    ]);
    await _adb(emulator, <String>[
      'shell',
      'svc',
      'wifi',
      available ? 'enable' : 'disable',
    ], allowFailure: true);
    await _adb(emulator, <String>[
      'shell',
      'svc',
      'data',
      available ? 'enable' : 'disable',
    ], allowFailure: true);
  }

  Future<bool> _networkAvailable(String device) async {
    final dump = await _shellText(device, const <String>[
      'dumpsys',
      'connectivity',
    ]);
    final match = RegExp(
      r'Active default network:\s*([^\r\n]+)',
      caseSensitive: false,
    ).firstMatch(dump);
    if (match == null) {
      throw const _Blocked(
        'environment',
        'Android connectivity state is not observable.',
      );
    }
    final value = match.group(1)!.trim().toLowerCase();
    return value != 'none' && value != 'null' && value != '-1';
  }

  Future<Map<String, Object?>> _writeScenarioArtifact(
    Map<String, Object?> artifact,
  ) async {
    final validation = validateNotificationArtifact(artifact);
    if (!validation.ok) {
      throw _Failure(
        'Notification artifact rejected: ${validation.detail}',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final scenario = artifact['scenario'] as String;
    final file = File(
      '${proofDirectory.path}${Platform.pathSeparator}$scenario.json',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(artifact), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return <String, Object?>{
      'scenario': scenario,
      'path': file.resolveSymbolicLinksSync(),
      'sha256': sha256.convert(file.readAsBytesSync()).toString(),
    };
  }

  Future<void> _removeScenarioArtifacts() async {
    for (final scenario in const <String>[
      'tc_a6_replay_before_ack_custody',
      'tc_b11_payload_persist_pre_drain',
      'payload_fast_path_android_receiver',
      'payload_fast_path_cold_kill',
    ]) {
      for (final suffix in const <String>['.json', '.json.tmp']) {
        final file = File(
          '${proofDirectory.path}${Platform.pathSeparator}$scenario$suffix',
        );
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _restorePushRegistration() async {
    await originalReceiverNetwork.restore(this);
    await _launch(emulator);
    await _runAction(
      emulator,
      action: androidNotificationRestorePushAction,
      runId: _token('finally-restore'),
      timeout: const Duration(seconds: 45),
    );
    _pushTokenUnregistered = false;
  }

  Future<ProcessResult> _ssh(
    List<String> remoteArguments, {
    bool allowFailure = false,
  }) => _run('ssh', <String>[
    '-o',
    'BatchMode=yes',
    '-o',
    'ConnectTimeout=15',
    '-i',
    relayKey.path,
    options.relayTarget,
    _shellJoin(remoteArguments),
  ], allowFailure: allowFailure);

  Future<String> _shellText(String device, List<String> command) async {
    final result = await _adb(device, <String>['shell', ...command]);
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(
    String? device,
    List<String> arguments, {
    bool allowFailure = false,
  }) => _run('adb', <String>[
    if (device != null) ...<String>['-s', device],
    ...arguments,
  ], allowFailure: allowFailure);

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    if (options.verbose) {
      stderr.writeln('RUN: $executable ${arguments.join(' ')}');
    }
    final result = await Process.run(executable, arguments);
    if (!allowFailure && result.exitCode != 0) {
      throw _Failure(
        '$executable command failed with exit ${result.exitCode}.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return result;
  }

  Future<void> _waitFor(
    String label,
    Duration timeout,
    Future<bool> Function() check,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _Failure(
      'Timed out waiting for $label.',
      assertionsAttempted: _assertionsAttempted,
    );
  }

  Future<T> _waitForValue<T>(
    String label,
    Duration timeout,
    Future<T?> Function() read, {
    bool Function(T value)? accept,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await read();
      if (value != null && (accept == null || accept(value))) return value;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _Failure(
      'Timed out waiting for $label.',
      assertionsAttempted: _assertionsAttempted,
    );
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}

final class _NetworkState {
  const _NetworkState({
    required this.airplaneEnabled,
    required this.wifiEnabled,
    required this.dataEnabled,
  });

  final bool airplaneEnabled;
  final bool wifiEnabled;
  final bool dataEnabled;

  static Future<_NetworkState> capture(
    _AndroidNotificationCampaign campaign,
  ) async {
    final airplane = await campaign._shellText(
      campaign.emulator,
      const <String>['cmd', 'connectivity', 'airplane-mode'],
    );
    final wifi = await campaign._shellText(campaign.emulator, const <String>[
      'settings',
      'get',
      'global',
      'wifi_on',
    ]);
    final data = await campaign._shellText(campaign.emulator, const <String>[
      'settings',
      'get',
      'global',
      'mobile_data',
    ]);
    return _NetworkState(
      airplaneEnabled: airplane.trim().toLowerCase().contains('enabled'),
      wifiEnabled: wifi.trim() == '1',
      dataEnabled: data.trim() == '1',
    );
  }

  Future<void> restore(_AndroidNotificationCampaign campaign) async {
    await campaign._adb(campaign.emulator, <String>[
      'shell',
      'cmd',
      'connectivity',
      'airplane-mode',
      airplaneEnabled ? 'enable' : 'disable',
    ]);
    await campaign._adb(campaign.emulator, <String>[
      'shell',
      'svc',
      'wifi',
      wifiEnabled ? 'enable' : 'disable',
    ]);
    await campaign._adb(campaign.emulator, <String>[
      'shell',
      'svc',
      'data',
      dataEnabled ? 'enable' : 'disable',
    ]);
    for (var attempt = 0; attempt < 40; attempt++) {
      final current = await _NetworkState.capture(campaign);
      if (current.airplaneEnabled == airplaneEnabled &&
          current.wifiEnabled == wifiEnabled &&
          current.dataEnabled == dataEnabled) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw _Failure(
      'Receiver airplane/Wi-Fi/data state did not restore exactly.',
      assertionsAttempted: campaign._assertionsAttempted,
    );
  }
}

final class _Identity {
  const _Identity({
    required this.peerId,
    required this.qrPayload,
    required this.mlKemPublicKey,
  });

  final String peerId;
  final String qrPayload;
  final String? mlKemPublicKey;

  String get peerPrefix =>
      peerId.length <= 20 ? peerId : peerId.substring(0, 20);
}

final class _SentMessage {
  const _SentMessage({required this.messageId, required this.transport});

  final String messageId;
  final String transport;
}

final class _Blocked implements Exception {
  const _Blocked(this.blocker, this.detail, {this.artifactPresent = false});

  final String blocker;
  final String detail;
  final bool artifactPresent;
}

final class _Failure implements Exception {
  const _Failure(this.detail, {required this.assertionsAttempted});

  final String detail;
  final int assertionsAttempted;
}

AndroidNotificationCampaignResult _blocked({
  required String blocker,
  required String detail,
  bool artifactPresent = false,
}) => AndroidNotificationCampaignResult(78, <String, Object?>{
  'status': 'BLOCKED',
  'assertionsAttempted': 0,
  'artifactPresent': artifactPresent,
  'printOnly': false,
  'blocker': blocker,
  'exitCode': 78,
  'detail': detail,
});

AndroidNotificationCampaignResult _failed(
  String detail, {
  required int assertionsAttempted,
}) => AndroidNotificationCampaignResult(1, <String, Object?>{
  'status': 'FAIL',
  'assertionsAttempted': assertionsAttempted,
  'artifactPresent': false,
  'printOnly': false,
  'blocker': 'test',
  'exitCode': 1,
  'detail': detail,
});

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

bool _isUsableServiceAccount(File file) {
  if (!_isRegularFile(file)) return false;
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map && '${decoded['project_id'] ?? ''}'.trim().isNotEmpty;
  } on Object {
    return false;
  }
}

String _shellJoin(List<String> arguments) =>
    arguments.map(_shellQuote).join(' ');

String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";
