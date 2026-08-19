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
  'b12.warm_audible_channel',
];
const List<String> _coldChecks = <String>[
  'receiverTerminatedBeforeTap',
  'notificationTapColdLaunchedApp',
  'startupIngestRan',
  'messageVisibleFromStagedEnvelope',
  'noRelayDrainBeforeVisibility',
  'b12.cold_audible_channel',
];
const List<String> _b13Checks = <String>[
  'b13.dual_attempt',
  'b13.single_card',
  'b13.single_audible_channel',
  'b13.losing_path_typed_suppression',
];
const List<String> _permissionDeniedChecks = <String>[
  'g7.permission_denied_no_post',
  'g7.permission_denied_typed_health',
  'g7.permission_custody_preserved',
  'g7.permission_regrant_recovery',
];
const List<String> _tokenRefreshChecks = <String>[
  'g7.token_refresh_event_observed',
  'g7.token_refresh_reregistered_same_process',
  'g7.token_refresh_new_token_delivery',
];
const List<String> _channelDisabledChecks = <String>[
  'g7.channel_disabled_no_post',
  'g7.channel_custody_preserved',
  'g7.channel_reenable_recovery',
];
const List<String> _dozeDeliveryChecks = <String>[
  'g7.doze_forced_idle_proven',
  'g7.doze_disposition_typed',
  'g7.doze_no_duplicate_render',
];

const List<String> _androidPayloadCampaignScenarios = <String>[
  'tc_a6_replay_before_ack_custody',
  'tc_b11_payload_persist_pre_drain',
  'payload_fast_path_android_receiver',
  'payload_fast_path_cold_kill',
  'tc_b13_dual_path_single_alert',
  'tc_g7_permission_denied',
  'tc_g7_token_refresh_mid_session',
  'tc_g7_channel_disabled',
  'tc_g7_doze_delivery',
];

/// The audible conversation channel. The silent sibling
/// (`mknoon_messages_silent`) is visible and tappable, so "a card exists" is
/// never evidence of an audible alert.
const String _audibleNotificationChannelId = 'mknoon_messages';
const String _silentNotificationChannelId = 'mknoon_messages_silent';
const String _postNotificationsPermission =
    'android.permission.POST_NOTIFICATIONS';

/// The per-channel master toggle on the Settings channel screen. Measured on
/// `emulator-5554` (Android 17 / SDK 37): every secondary row on that screen uses
/// `com.android.settings:id/switchWidget`, so the ids cannot be confused.
const String _channelMasterSwitchResourceId = 'android:id/switch_widget';

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
  bool _permissionRevoked = false;
  bool _channelToggledOff = false;
  bool _dozeForced = false;
  bool _tokenRotationInFlight = false;
  DateTime? _lastCardObservedAt;
  int _assertionsAttempted = 0;
  Process? _deviceLogProcess;
  File? _deviceLogFile;
  String? _deviceLogFailure;

  Future<AndroidNotificationCampaignResult> run() async {
    await _preflight();
    await proofDirectory.create(recursive: true);
    await _removeScenarioArtifacts();
    await _startDeviceLogStream();

    final captured = <Map<String, Object?>>[];
    AndroidAppStateGuard? appStateGuard;
    var proofCompleted = false;
    // A throw from the finally REPLACES an in-flight exception, so a leg
    // failure followed by a restoration failure used to surface only the
    // restoration message and the real defect was invisible. Keep the primary
    // failure so both are reported.
    Object? legFailure;
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

      final dualPath = await _runB13DualPathLeg();
      captured.add(await _writeScenarioArtifact(dualPath));

      final permissionDenied = await _runPermissionDeniedLeg();
      captured.add(await _writeScenarioArtifact(permissionDenied));

      final tokenRefresh = await _runTokenRefreshLeg();
      captured.add(await _writeScenarioArtifact(tokenRefresh));

      final channelDisabled = await _runChannelDisabledLeg();
      captured.add(await _writeScenarioArtifact(channelDisabled));

      final dozeDelivery = await _runDozeDeliveryLeg();
      captured.add(await _writeScenarioArtifact(dozeDelivery));
      proofCompleted = true;
    } catch (error) {
      legFailure = error;
      rethrow;
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
        if (_pushTokenUnregistered || _tokenRotationInFlight) {
          await attempt('push-registration', _restorePushRegistration);
        }
        if (_dozeForced) {
          await attempt('deep-idle', _releaseDoze);
        }
        if (_channelToggledOff) {
          await attempt('notification-channel', () async {
            await _setChannelEnabled(_audibleNotificationChannelId, true);
            await _setChannelEnabled(_silentNotificationChannelId, true);
            _channelToggledOff = false;
          });
        }
        if (_permissionRevoked) {
          await attempt('post-notifications-permission', _restorePostNotifications);
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
      // Outside the appStateGuard branch on purpose: the log stream is started
      // before the guard is captured, so a blocker in between would leak the
      // `adb logcat` child if this only ran on the guarded path.
      await attempt('receiver-log-stream', _stopDeviceLogStream);
      if (!proofCompleted || restorationFailures.isNotEmpty) {
        await attempt('partial-artifacts', _removeScenarioArtifacts);
      }
      if (restorationFailures.isNotEmpty) {
        throw _Failure(
          'Exact Android campaign restoration failed at '
          '${restorationFailures.join(', ')}'
          '${legFailure == null ? '' : '; the leg had ALREADY failed: '
                '${_describeFailure(legFailure)}'}'
          '; no passing evidence was retained.',
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
        assertionsAttempted: 9,
      );
    }
    return AndroidNotificationCampaignResult(0, <String, Object?>{
      'status': 'PASS',
      'assertionsAttempted': 9,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail':
          'A6, B11, Android B12 warm/cold with measured audible-channel '
          'evidence, B13 dual-path single alert, and the PRD 13 Android '
          'matrix legs (permission denied, mid-session token refresh, '
          'channel disabled, Doze) passed with one centrally '
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
    // The A6 message is delivered for real, so the live listener posts a real
    // card (observed: NOTIFICATION_SHOWN durable/osPosted, silent=false). Own
    // it, or the next leg's empty-slate precondition and the run() finally's
    // cleanup both fail on a card this leg created.
    _campaignNotificationBodies.add(marker);

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
    // Hand the next leg an empty slate and start the tone window ticking from
    // this card, so the warm leg's audible assertion is not measured inside a
    // window A6 already consumed.
    await _cleanupCampaignNotifications();

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

    final toneGap = await _awaitToneWindow();
    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);
    final staged = await _waitForStagedEnvelope(sent: sent, notBefore: sentAt);
    final warmObservation = await _waitForNotificationObservation(marker);
    final warmAlertChannel = _requireAudibleChannel(
      warmObservation.channels,
      'B12 warm',
    );

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
          'warmAlertChannel': warmAlertChannel,
          'toneWindowGapMs': toneGap.inMilliseconds,
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

    final toneGap = await _awaitToneWindow();
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
    // Read the surviving card's channel here, not next to the kill: the T1
    // observe-then-kill adjacency is frozen, and the card demonstrably
    // survives both the kill and airplane mode.
    //
    // This is the one site where the fresh-dump wrapper is still sound. The
    // silent same-ID reconcile that makes a later dump unsafe elsewhere
    // (`_waitForNotificationObservation`) needs a live receiver to perform
    // it, and the process is already proven dead two statements above.
    final coldAlertChannel = await _observeAudibleChannel(marker, 'B12 cold');
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
        'coldAlertChannel': coldAlertChannel,
        'toneWindowGapMs': toneGap.inMilliseconds,
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

  /// TC-B13 — dual-path single alert.
  ///
  /// The receiver is BACKGROUNDED BUT CONNECTED: HOME only, no kill and no
  /// stop-node, so the live bridge and the real FCM wake race for the same
  /// message. A foreground receiver would not work — the foreground FCM drain
  /// never reaches a notification decision
  /// (`handle_foreground_remote_message_use_case.dart:13-20` drains with
  /// `needsNotification: false` and emits no suppression event).
  Future<Map<String, Object?>> _runB13DualPathLeg() async {
    _assertionsAttempted = 5;
    final runId = _token('dual');
    final marker = 'Sims B13 dual path $runId';
    _campaignNotificationBodies.add(marker);
    await _requireNoAppNotification();

    await _adb(emulator, const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ]);
    final logcatCursor = await _deviceLogcatCursor();

    final toneGap = await _awaitToneWindow();
    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);
    await _waitForNotification(marker);

    // The ALERT is read from the cursor-scoped LOG, never from dumpsys.
    //
    // The winning path here is the FCM background isolate, and the loser
    // reconciles the claim and publishes a silent SAME-ID update ~2.6 s later,
    // which moves the record onto `mknoon_messages_silent`. Device-measured
    // twice, 2026-08-19: `PUSH_BACKGROUND_NOTIFICATION_SHOWN` -> 2.5 s ->
    // `NOTIFICATION_LEGACY_CLAIM_RECONCILE` -> 140 ms ->
    // `NOTIFICATION_SHOWN {"silent":true}`. That is B13 PASSING — one alert,
    // one card — but no dumpsys poll is fast enough to see the audible window,
    // so a channel read reports the correct behaviour as a silent alert.
    bool? alertSilent;
    final alertDeadline = DateTime.now().add(const Duration(minutes: 1));
    while (DateTime.now().isBefore(alertDeadline)) {
      alertSilent = androidNotificationFirstPostAttemptSilent(
        await _logcatSince(logcatCursor),
      );
      if (alertSilent != null) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (alertSilent != false) {
      throw _Failure(
        'B13 first post attempt reported silent=$alertSilent; the winning '
        'delivery path must ALERT. A dual-path collapse that silences the '
        'winner is as wrong as a double alert. A null reading means the '
        'window recorded no post attempt carrying the flag at all.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    // Bounded wait for BOTH legs' attempt markers. Without this a run in which
    // only one path ever fired would satisfy "exactly one card" and pass as a
    // dual-path proof, so a missing marker is an inconclusive RED — never a
    // silent pass.
    String? dualPathLog;
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final window = await _logcatSince(logcatCursor);
      if (notificationWindowProvesDualPathAttempt(window)) {
        dualPathLog = window;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (dualPathLog == null) {
      throw _Failure(
        'B13 inconclusive: the cursor-scoped window did not record BOTH a '
        'live-listener arrival and an FCM receipt, so this run cannot be '
        'accepted as dual-path evidence.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    // Exactly ONE card survives the race. The alert itself was already
    // asserted audible above, from the log.
    //
    // The surviving record's channel is recorded but NOT required to be the
    // audible one: when the losing path reconciles it publishes a silent
    // same-ID in-place update, which moves the record to
    // `mknoon_messages_silent` (device-measured 2026-08-19). Requiring the
    // audible channel here made B13 fail on runs where the product did
    // exactly what B13 exists to prove — one alert, one card — and pass only
    // when the losing path happened to stand down without reconciling.
    // `survivingCardChannel` is value-bounded by the criteria instead, and the
    // typed losing-path stand-down asserted below is what attributes the
    // single card to the dedupe seam.
    final dump = await _notificationDump();
    final channels = androidNotificationChannelsForBody(
      dump,
      packageName: packageName,
      body: marker,
    );
    if (channels.length != 1) {
      throw _Failure(
        'B13 dual-path delivery produced ${channels.length} cards for one '
        'message; exactly one was required.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    // The losing path must say WHY it stood down. Either path may win, so the
    // discriminator is a union over both events' reason sets.
    //
    // Re-read the window rather than reusing `dualPathLog`: that snapshot is
    // frozen the instant BOTH attempt markers appear, and the losing path
    // emits its stand-down afterwards. Searching the stale snapshot made this
    // assertion fail on device even when the typed record was present
    // (observed 2026-08-18: NOTIFICATION_LEGACY_CLAIM_RECONCILE x4 in the log,
    // zero in the snapshot). The predicate is unchanged — only the window it
    // reads is now allowed to catch up.
    String? losingSuppression;
    final suppressionDeadline = DateTime.now().add(const Duration(minutes: 1));
    while (DateTime.now().isBefore(suppressionDeadline)) {
      losingSuppression = androidNotificationLosingPathSuppression(
        await _logcatSince(logcatCursor),
      );
      if (losingSuppression != null) break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (losingSuppression == null) {
      throw _Failure(
        'B13 recorded no typed suppression from the losing delivery path; the '
        'single card cannot be attributed to the dedupe seam.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    return androidNotificationScenarioArtifact(
      testCase: 'TC-B13',
      scenario: 'tc_b13_dual_path_single_alert',
      devices: <String>[physical, emulator],
      passedChecks: _b13Checks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(sent.messageId),
        'senderTransport': sent.transport,
        'receiverBackgroundedButConnected': true,
        'livePathAttemptEvent': androidNotificationLivePathAttemptEvent,
        'fcmPathAttemptEvent': androidNotificationFcmPathAttemptEvent,
        'losingPathSuppression': losingSuppression,
        'activeCardCount': channels.length,
        'alertSilent': alertSilent,
        'survivingCardChannel': channels.single,
        'toneWindowGapMs': toneGap.inMilliseconds,
        'childBuildCount': 0,
      },
    );
  }

  // ---------------------------------------------------------------------
  // Shared audible-alert discipline (G12).
  //
  // The durable tone lease keys on the CONVERSATION and every campaign send
  // shares one, so a second audible-asserting send inside the 30 s window
  // (`durable_notification_tone_lease.dart:349`, committed at `:1190-1204`)
  // lands silently BY DESIGN. Spacing every such send is what makes a silent
  // card a real defect rather than a timing artefact.
  // ---------------------------------------------------------------------

  static const Duration _toneWindowSpacing = Duration(seconds: 31);
  static const Duration _toneCommitGrace = Duration(seconds: 3);

  /// Blocks until the conversation's tone window has expired, and returns the
  /// measured gap since the previous card observation.
  Future<Duration> _awaitToneWindow() async {
    final observed = _lastCardObservedAt;
    if (observed == null) return Duration.zero;
    final remaining = observed
        .add(_toneWindowSpacing)
        .difference(DateTime.now());
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    return DateTime.now().difference(observed);
  }

  /// The alert channel of the single active card whose body is [marker], read
  /// from a FRESH dump.
  ///
  /// `ActiveNotificationCard` carries no channel field and plan 378
  /// deliberately does not add one to that shared parser, so the channel is
  /// read from the marker's own `NotificationRecord` block.
  Future<String> _observeAudibleChannel(String marker, String leg) async =>
      _requireAudibleChannel(
        androidNotificationChannelsForBody(
          await _notificationDump(),
          packageName: packageName,
          body: marker,
        ),
        leg,
      );

  /// Asserts an already-measured channel list is a single audible card.
  ///
  /// Callers that can bind the reading to the card's FIRST observation should
  /// pass those channels (see `_waitForNotificationObservation`); the
  /// fresh-dump wrapper above is only sound where no further publication can
  /// touch the record.
  String _requireAudibleChannel(List<String> channels, String leg) {
    if (channels.length != 1) {
      throw _Failure(
        '$leg produced ${channels.length} cards for one message; exactly one '
        'was required.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    if (channels.single != _audibleNotificationChannelId) {
      throw _Failure(
        '$leg card landed on channel "${channels.single}" instead of the '
        'audible $_audibleNotificationChannelId channel. If an interrupted '
        'publication left a repaired tone lease this run is INCONCLUSIVE, not '
        'a product failure: re-run the campaign once before treating it as '
        'one.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return channels.single;
  }

  Future<void> _backgroundReceiver() async {
    await _adb(emulator, const <String>[
      'shell',
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ]);
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  /// Sends [marker] to a backgrounded receiver and returns once the provider
  /// accepted it, having first paid the tone-window debt.
  Future<
    ({_SentMessage sent, Duration toneGap, String cursor, DateTime sentAt})
  >
  _sendSpacedMarker(String marker, {required String runId}) async {
    // Pay the tone debt BEFORE opening the log window: a 31 s window would
    // otherwise sweep in the previous leg's background-receipt marker and let
    // a push that never arrived read as one that did.
    final toneGap = await _awaitToneWindow();
    final cursor = await _deviceLogcatCursor();
    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);
    return (sent: sent, toneGap: toneGap, cursor: cursor, sentAt: sentAt);
  }

  /// Proves the wake ARRIVED and that a delivery path then actually CALLED the
  /// native show, returning both measurements.
  ///
  /// The receipt alone is not enough: `PUSH_BACKGROUND_MESSAGE_RECEIVED` is the
  /// handler's first statement, upstream of staging, the display-eligibility
  /// gate and every suppression return, so a wake that stood down (for example
  /// `message_event_already_claimed`, which is likely here because the
  /// backgrounded receiver is still P2P-connected) satisfies it while posting
  /// nothing. Gating the zero-card census on a post ATTEMPT is what stops
  /// `g7.*_no_post` from being vacuously true. Both values are returned so the
  /// leg's evidence cannot exist without this call.
  Future<({int receipts, String postAttemptEvent})> _requirePostAttempt(
    String cursor,
    String leg,
  ) async {
    final pattern = RegExp(
      RegExp.escape(androidNotificationFcmPathAttemptEvent),
    );
    var receipts = 0;
    await _waitFor('$leg background FCM receipt', const Duration(minutes: 2), () async {
      receipts = pattern.allMatches(await _logcatSince(cursor)).length;
      return receipts > 0;
    });
    String? attempt;
    await _waitFor('$leg native post attempt', const Duration(minutes: 2), () async {
      attempt = androidNotificationPostAttemptEvent(
        await _logcatSince(cursor),
      );
      return attempt != null;
    });
    return (receipts: receipts, postAttemptEvent: attempt!);
  }

  /// Returns the MEASURED count of active cards bearing [marker], which is
  /// always zero when this returns because a non-empty census throws.
  ///
  /// Returning the measurement is what binds the artifact to the observation:
  /// with a literal `0` in the evidence map, deleting this call would still
  /// produce an artifact that validates. A parser regression that matched
  /// nothing cannot hide here either — every leg that calls this also runs a
  /// positive control through the SAME parser afterwards
  /// (`_observeAudibleChannel` on the recovery card).
  Future<int> _requireNoCardForMarker(String marker, String leg) async {
    // Custody confirmation proves the handler ran, not that it finished its
    // post decision, so a single sample could read "no card" microseconds
    // before one appears. The census must hold for a sustained window.
    var cardCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    do {
      final dump = await _notificationDump();
      // Channel-agnostic: within the tone window an audible post is downgraded
      // to `mknoon_messages_silent`, which a channel-scoped census would miss.
      final channels = androidNotificationChannelsForBody(
        dump,
        packageName: packageName,
        body: marker,
      );
      final cards = extractActiveNotificationCards(
        dump,
        packageName: packageName,
      ).where((card) => card.body == marker).toList(growable: false);
      cardCount = channels.length > cards.length
          ? channels.length
          : cards.length;
      if (cardCount != 0) {
        throw _Failure(
          '$leg posted $cardCount card(s) on '
          '${channels.join(', ')} when no card may be posted.',
          assertionsAttempted: _assertionsAttempted,
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    } while (DateTime.now().isBefore(deadline));
    // A dropped post can still have RESERVED and committed the conversation's
    // tone before the OS refused it, so the recovery control owes the same
    // 31 s spacing an observed card would have created.
    _lastCardObservedAt = DateTime.now();
    return cardCount;
  }

  Future<void> _requireReceiverAlive(String leg) async {
    if ((await _pidof(emulator)).isEmpty) {
      throw _Failure(
        '$leg killed the receiver process instead of dropping the post.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
  }

  Future<List<AndroidFlowRecord>> _flowRecordsSince(String cursor) async =>
      androidNotificationFlowRecords(await _logcatSince(cursor));

  // ---------------------------------------------------------------------
  // TC-380-07 — PRD 13 permission denied.
  // ---------------------------------------------------------------------
  Future<Map<String, Object?>> _runPermissionDeniedLeg() async {
    _assertionsAttempted = 6;
    final runId = _token('permdenied');
    final marker = 'Sims G7 permission denied $runId';
    final controlMarker = 'Sims G7 permission regrant $runId';
    await _cleanupCampaignNotifications();
    _campaignNotificationBodies
      ..add(marker)
      ..add(controlMarker);

    // Mutations happen AFTER the app-state guard's one-shot capture and are
    // undone before its restore runs. The flag is set BEFORE the mutation so a
    // throw mid-revoke cannot strand the receiver denied.
    _permissionRevoked = true;
    await _adb(emulator, <String>[
      'shell',
      'pm',
      'revoke',
      packageName,
      _postNotificationsPermission,
    ]);
    // Without `user-fixed` the relaunched app can raise a live OS permission
    // dialog on an unattended device and re-grant itself.
    await _adb(emulator, <String>[
      'shell',
      'pm',
      'set-permission-flags',
      packageName,
      _postNotificationsPermission,
      'user-fixed',
    ]);
    if (await _notificationPermissionGranted()) {
      throw _Failure(
        'POST_NOTIFICATIONS was still granted after the revoke.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    // Measured on `emulator-5554` (Android 17 / SDK 37): revoking
    // POST_NOTIFICATIONS does
    // NOT kill the app process (pid unchanged across the revoke and for 5 s
    // after). The relaunch is still required — it is what makes the
    // coordinator re-evaluate permission and emit its typed denied health
    // record — so the leg terminates the receiver itself instead of waiting
    // for an OS kill that never arrives.
    await _terminateReceiver();

    final coordinatorCursor = await _deviceLogcatCursor();
    await _launch(emulator);
    await _identity(emulator);

    // Environment precondition, re-checked AFTER the relaunch.
    //
    // If the OS handed POST_NOTIFICATIONS back across the restart, the app is
    // CORRECTLY reporting granted and the absence of a denied health record is
    // an environment outcome, not a regression. Plan 385's F3 recorded that
    // this SDK-37 image does not behave identically run to run, so the leg
    // states which side failed instead of blaming the product.
    if (await _notificationPermissionGranted()) {
      throw const _Blocked(
        'deviceOsState',
        'POST_NOTIFICATIONS was granted again across the relaunch, so the '
            'permission-denied precondition never held; the app was never '
            'asked the question this leg exists to ask.',
      );
    }

    // Assert the typed health record HERE, seconds after the coordinator emits
    // it during startup — not after the send/census, which is minutes later.
    // The live stream makes a late read sound, but a prompt read also binds
    // the failure to the moment it happened.
    final denied = await _awaitFlowRecords(
      coordinatorCursor,
      'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED',
      const Duration(minutes: 2),
    );
    if (denied.isEmpty) {
      throw _Failure(
        'G7 permission denied recorded no typed '
        'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED health event within 2 '
        'minutes of a relaunch whose OS precondition was verified denied.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    // A foreground receiver would make the zero-card census vacuous: the
    // foreground FCM drain never reaches a notification decision.
    await _backgroundReceiver();

    final send = await _sendSpacedMarker(marker, runId: runId);
    final attempt = await _requirePostAttempt(
      send.cursor,
      'G7 permission denied',
    );
    // Custody is also confirmed before the census: the leg must prove the
    // message survived the dropped post, not just that no card exists.
    final staged = await _waitForStagedEnvelope(
      sent: send.sent,
      notBefore: send.sentAt,
    );
    final deniedCardCount = await _requireNoCardForMarker(
      marker,
      'G7 permission denied',
    );
    await _requireReceiverAlive('G7 permission denied');

    final drain = await _restartAndDrain(
      runId: runId,
      nonce: _token('nonce'),
      marker: marker,
      messageId: send.sent.messageId,
    );
    if (drain['messageCount'] != 1 || drain['pendingRelayEntries'] != 0) {
      throw _Failure(
        'G7 permission denied lost or duplicated custody of the dropped '
        'notification message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    await _restorePostNotifications();
    final recoveryCursor = await _deviceLogcatCursor();
    await _terminateReceiver();
    await _launch(emulator);
    await _identity(emulator);
    await _waitFor(
      'push registration success after re-grant',
      const Duration(minutes: 3),
      () async => (await _flowRecordsSince(recoveryCursor)).any(
        (record) => record.event == 'PUSH_REGISTER_COORDINATOR_SUCCESS',
      ),
    );
    await _backgroundReceiver();
    final control = await _sendSpacedMarker(controlMarker, runId: '$runId-ctl');
    final controlObservation = await _waitForNotificationObservation(
      controlMarker,
    );
    final controlChannel = _requireAudibleChannel(
      controlObservation.channels,
      'G7 permission regrant control',
    );

    return androidNotificationScenarioArtifact(
      testCase: 'TC-380-07',
      scenario: 'tc_g7_permission_denied',
      devices: <String>[physical, emulator],
      passedChecks: _permissionDeniedChecks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(send.sent.messageId),
        'senderTransport': send.sent.transport,
        'stagedEnvelope': staged.toJson(),
        'permissionDeniedBackgroundReceiptCount': attempt.receipts,
        'permissionDeniedPostAttemptEvent': attempt.postAttemptEvent,
        'permissionDeniedHealthEvent': denied.first.event,
        'permissionDeniedHealthEventCount': denied.length,
        'permissionDeniedCardCount': deniedCardCount,
        'permissionDeniedMessageCount': drain['messageCount'],
        'permissionRegrantAlertChannel': controlChannel,
        'toneWindowGapMs': control.toneGap.inMilliseconds,
        'childBuildCount': 0,
      },
    );
  }

  Future<bool> _notificationPermissionGranted() async {
    final dump = await _shellText(emulator, <String>[
      'dumpsys',
      'package',
      packageName,
    ]);
    final match = RegExp(
      '${RegExp.escape(_postNotificationsPermission)}'
      r':\s*granted=(true|false)',
    ).firstMatch(dump);
    if (match == null) {
      throw _Failure(
        'POST_NOTIFICATIONS grant state is not observable on the receiver.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return match.group(1) == 'true';
  }

  /// Symmetric with the revoke: the flag is cleared as well as the grant
  /// restored, so the receiver ends the run re-promptable exactly as it began.
  Future<void> _restorePostNotifications() async {
    await _adb(emulator, <String>[
      'shell',
      'pm',
      'clear-permission-flags',
      packageName,
      _postNotificationsPermission,
      'user-fixed',
    ], allowFailure: true);
    await _adb(emulator, <String>[
      'shell',
      'pm',
      'grant',
      packageName,
      _postNotificationsPermission,
    ]);
    if (!await _notificationPermissionGranted()) {
      throw _Failure(
        'POST_NOTIFICATIONS could not be restored on the receiver.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    _permissionRevoked = false;
  }

  // ---------------------------------------------------------------------
  // TC-380-06 — PRD 13 mid-session token refresh.
  // ---------------------------------------------------------------------
  Future<Map<String, Object?>> _runTokenRefreshLeg() async {
    _assertionsAttempted = 7;
    final runId = _token('tokenrefresh');
    final marker = 'Sims G7 token refresh $runId';
    await _cleanupCampaignNotifications();
    _campaignNotificationBodies.add(marker);

    // The coordinator subscribes to onTokenRefresh inside ensureStarted(), so
    // the startup attempt must be inside this window before staging anything.
    await _terminateReceiver();
    final startupCursor = await _deviceLogcatCursor();
    await _launch(emulator);
    await _identity(emulator);
    await _waitFor(
      'startup push registration attempt',
      const Duration(minutes: 3),
      () async => (await _flowRecordsSince(startupCursor)).any(
        (record) =>
            record.event == 'PUSH_REGISTER_COORDINATOR_ATTEMPT' &&
            record.hasDetails(const <String, Object?>{'trigger': 'startup'}),
      ),
    );
    final pidBeforeRotation = await _pidof(emulator);
    if (pidBeforeRotation.isEmpty) {
      throw _Failure(
        'G7 token refresh could not observe the pre-rotation receiver PID.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    final rotationCursor = await _deviceLogcatCursor();
    _tokenRotationInFlight = true;
    final rotation = await _runAction(
      emulator,
      action: androidNotificationDeletePushTokenAction,
      runId: runId,
      timeout: const Duration(seconds: 90),
    );

    await _waitFor(
      'mid-session token-refresh re-registration',
      const Duration(minutes: 3),
      () async {
        final records = await _flowRecordsSince(rotationCursor);
        final refresh = records.indexWhere(
          (record) => record.event == 'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
        );
        if (refresh < 0) return false;
        return records
            .skip(refresh)
            .any(
              (record) =>
                  record.event == 'PUSH_REGISTER_COORDINATOR_SUCCESS' &&
                  record.hasDetails(const <String, Object?>{
                    'trigger': 'token_refresh',
                  }),
            );
      },
    );

    // A crash/relaunch between deleteToken and success ALSO traverses the
    // stream path in the new process, so same-process is proven by both the
    // PID identity and the absence of a second startup attempt.
    final rotationWindow = await _flowRecordsSince(rotationCursor);
    final extraStartupAttempts = rotationWindow
        .where(
          (record) =>
              record.event == 'PUSH_REGISTER_COORDINATOR_ATTEMPT' &&
              record.hasDetails(const <String, Object?>{'trigger': 'startup'}),
        )
        .length;
    final refreshRecord = rotationWindow
        .where(
          (record) => record.event == 'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
        )
        .toList(growable: false);
    final successRecord = rotationWindow
        .where(
          (record) =>
              record.event == 'PUSH_REGISTER_COORDINATOR_SUCCESS' &&
              record.hasDetails(const <String, Object?>{
                'trigger': 'token_refresh',
              }),
        )
        .toList(growable: false);
    if (refreshRecord.isEmpty || successRecord.isEmpty) {
      throw _Failure(
        'G7 token refresh lost its stream-path records between the wait and '
        'the evidence read.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final pidAfterRotation = await _pidof(emulator);
    if (extraStartupAttempts != 0 || pidAfterRotation != pidBeforeRotation) {
      throw _Failure(
        'G7 token refresh re-registered through a relaunch '
        '($extraStartupAttempts startup attempts in window), not in the '
        'running process.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    _tokenRotationInFlight = false;

    await _backgroundReceiver();
    final send = await _sendSpacedMarker(marker, runId: '$runId-deliver');
    final deliveryObservation = await _waitForNotificationObservation(marker);
    final alertChannel = _requireAudibleChannel(
      deliveryObservation.channels,
      'G7 token refresh delivery',
    );

    return androidNotificationScenarioArtifact(
      testCase: 'TC-380-06',
      scenario: 'tc_g7_token_refresh_mid_session',
      devices: <String>[physical, emulator],
      passedChecks: _tokenRefreshChecks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(send.sent.messageId),
        'senderTransport': send.sent.transport,
        'tokenRefreshEvent': refreshRecord.first.event,
        'tokenRefreshSuccessTrigger':
            successRecord.first.details['trigger'],
        'tokenRefreshPidBefore': pidBeforeRotation,
        'tokenRefreshPidAfter': pidAfterRotation,
        'tokenRefreshStartupAttemptsInWindow': extraStartupAttempts,
        'tokenHashPrefixBefore': rotation['tokenHashPrefixBefore'],
        'tokenHashPrefixAfter': rotation['tokenHashPrefixAfter'],
        'tokenRefreshAlertChannel': alertChannel,
        'toneWindowGapMs': send.toneGap.inMilliseconds,
        'childBuildCount': 0,
      },
    );
  }

  // ---------------------------------------------------------------------
  // TC-380-08 — PRD 13 channel disabled.
  // ---------------------------------------------------------------------
  Future<Map<String, Object?>> _runChannelDisabledLeg() async {
    _assertionsAttempted = 8;
    final runId = _token('channeloff');
    final marker = 'Sims G7 channel disabled $runId';
    final controlMarker = 'Sims G7 channel reenabled $runId';
    await _cleanupCampaignNotifications();
    _campaignNotificationBodies
      ..add(marker)
      ..add(controlMarker);

    // ONLY the user-facing `mknoon_messages` channel is blocked. That is the
    // row's declared contract — "user-blocked mknoon_messages channel posts no
    // card on any channel" (`run_notification_tap_device_real.dart:147`) — and
    // it is the only configuration a real user can produce from the "Messages"
    // toggle in Settings.
    //
    // `mknoon_messages_silent` is deliberately LEFT ON. It is not an
    // independent subscription: it exists so the tone debounce and the
    // same-ID reconcile can update a card without re-alerting
    // (`local_notification_support.dart:85`), so it is a continuation of the
    // very channel the user just switched off. Leaving it on is what keeps
    // the leak route OPEN, which is the whole point of the census below —
    // blocking it too would let the OS enforce the assertion for us and the
    // row would pass without the app ever making the decision.
    //
    // Flag set before the mutation: `_setChannelEnabled` is a non-atomic UI
    // drive that can throw AFTER the switch has already flipped, and
    // re-enable is idempotent when a channel is already on.
    _channelToggledOff = true;
    await _setChannelEnabled(_audibleNotificationChannelId, false);
    // Importance probe BEFORE the send. Two failure modes are covered: a
    // Settings selector that silently missed the toggle (audible != 0), and a
    // silent channel that some earlier leg left blocked, which would make the
    // zero-card census pass vacuously (silent != 2).
    final blockedImportance = await _channelImportance(
      _audibleNotificationChannelId,
    );
    final blockedSilentImportance = await _channelImportance(
      _silentNotificationChannelId,
    );
    if (blockedImportance != 0 || blockedSilentImportance != 2) {
      throw _Failure(
        'G7 channel disabled needed $_audibleNotificationChannelId blocked and '
        '$_silentNotificationChannelId still open to keep the leak route '
        'observable, but measured importance $blockedImportance and '
        '$blockedSilentImportance.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    await _backgroundReceiver();
    final send = await _sendSpacedMarker(marker, runId: runId);
    final attempt = await _requirePostAttempt(
      send.cursor,
      'G7 channel disabled',
    );
    final staged = await _waitForStagedEnvelope(
      sent: send.sent,
      notBefore: send.sentAt,
    );
    final blockedCardCount = await _requireNoCardForMarker(
      marker,
      'G7 channel disabled',
    );
    await _requireReceiverAlive('G7 channel disabled');

    final drain = await _restartAndDrain(
      runId: runId,
      nonce: _token('nonce'),
      marker: marker,
      messageId: send.sent.messageId,
    );
    if (drain['messageCount'] != 1 || drain['pendingRelayEntries'] != 0) {
      throw _Failure(
        'G7 channel disabled lost or duplicated custody of the blocked '
        'notification message.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    await _setChannelEnabled(_audibleNotificationChannelId, true);
    final restoredImportance = await _channelImportance(
      _audibleNotificationChannelId,
    );
    final restoredSilentImportance = await _channelImportance(
      _silentNotificationChannelId,
    );
    // 4 = IMPORTANCE_HIGH, 2 = IMPORTANCE_LOW — the declared importances of
    // the two channels (`local_notification_support.dart:16-30`).
    if (restoredImportance != 4 || restoredSilentImportance != 2) {
      throw _Failure(
        'G7 channel re-enable left $_audibleNotificationChannelId at '
        'importance $restoredImportance and $_silentNotificationChannelId at '
        '$restoredSilentImportance instead of 4 and 2.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    _channelToggledOff = false;

    await _backgroundReceiver();
    final control = await _sendSpacedMarker(controlMarker, runId: '$runId-ctl');
    final controlObservation = await _waitForNotificationObservation(
      controlMarker,
    );
    final controlChannel = _requireAudibleChannel(
      controlObservation.channels,
      'G7 channel re-enable control',
    );

    return androidNotificationScenarioArtifact(
      testCase: 'TC-380-08',
      scenario: 'tc_g7_channel_disabled',
      devices: <String>[physical, emulator],
      passedChecks: _channelDisabledChecks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(send.sent.messageId),
        'senderTransport': send.sent.transport,
        'stagedEnvelope': staged.toJson(),
        'channelDisabledBackgroundReceiptCount': attempt.receipts,
        'channelDisabledPostAttemptEvent': attempt.postAttemptEvent,
        'channelDisabledImportance': blockedImportance,
        'channelDisabledSilentImportance': blockedSilentImportance,
        'channelDisabledCardCount': blockedCardCount,
        'channelDisabledMessageCount': drain['messageCount'],
        'channelReenabledImportance': restoredImportance,
        'channelReenabledSilentImportance': restoredSilentImportance,
        'channelReenabledAlertChannel': controlChannel,
        'toneWindowGapMs': control.toneGap.inMilliseconds,
        'childBuildCount': 0,
      },
    );
  }

  Future<int?> _channelImportance(String channelId) async =>
      androidNotificationChannelImportance(
        await _notificationDump(),
        packageName: packageName,
        channelId: channelId,
      );

  /// Drives the per-channel master toggle on the real Settings screen.
  ///
  /// There is no production read-back and no adb setter for channel
  /// importance, and a programmatic downgrade is a one-way door, so the
  /// Settings UI is the only non-destructive lever.
  Future<void> _setChannelEnabled(String channelId, bool enabled) async {
    await _adb(emulator, <String>[
      'shell',
      'am',
      'start',
      '-a',
      'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
      '--es',
      'android.provider.extra.APP_PACKAGE',
      packageName,
      '--es',
      'android.provider.extra.CHANNEL_ID',
      channelId,
    ]);
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final node = androidUiSwitchNodeByResourceId(
        await _uiDump(),
        resourceId: _channelMasterSwitchResourceId,
      );
      if (node == null) continue;
      if (node.checked == enabled) {
        await _adb(emulator, const <String>[
          'shell',
          'input',
          'keyevent',
          'KEYCODE_BACK',
        ], allowFailure: true);
        await _backgroundReceiver();
        return;
      }
      await _adb(emulator, <String>[
        'shell',
        'input',
        'tap',
        '${node.x}',
        '${node.y}',
      ]);
    }
    throw _Failure(
      'The Settings channel toggle for $channelId could not be driven '
      '${enabled ? 'on' : 'off'} through its exact switch node; refusing a '
      'fixed-coordinate tap.',
      assertionsAttempted: _assertionsAttempted,
    );
  }

  // ---------------------------------------------------------------------
  // TC-380-09 — PRD 13 Doze delivery.
  //
  // Sound is deliberately NOT asserted here: a deferred wake surfaces through
  // the fixed-wake recovery card, which is silent by design.
  // ---------------------------------------------------------------------
  Future<Map<String, Object?>> _runDozeDeliveryLeg() async {
    _assertionsAttempted = 9;
    final runId = _token('doze');
    final marker = 'Sims G7 doze delivery $runId';
    await _cleanupCampaignNotifications();
    _campaignNotificationBodies.add(marker);

    await _terminateReceiver();
    await _adb(emulator, const <String>['shell', 'dumpsys', 'battery', 'unplug']);
    _dozeForced = true;
    await _adb(emulator, const <String>[
      'shell',
      'dumpsys',
      'deviceidle',
      'force-idle',
      'deep',
    ]);
    final stateBeforeSend = await _deepIdleState();
    if (stateBeforeSend != 'IDLE') {
      throw _Failure(
        'G7 Doze could not force deep idle (state=$stateBeforeSend).',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    final sentAt = DateTime.now().toUtc();
    final sent = await _sendText(
      marker,
      runId: runId,
      receiverPeerId: receiverIdentity.peerId,
    );
    await _waitForProviderSend(sentAt);

    // Idle state is sampled at BOTH boundaries: a single pre-send check would
    // let "delivered during idle" be claimed for a device that had already
    // woken up.
    var stateAtObservation = stateBeforeSend;
    var deliveredWhileForced = false;
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final state = await _deepIdleState();
      final cards = extractActiveNotificationCards(
        await _notificationDump(),
        packageName: packageName,
      ).where((card) => card.body == marker).toList(growable: false);
      stateAtObservation = state;
      if (cards.isNotEmpty) {
        deliveredWhileForced = true;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    // Neither arm may be claimed for a device that left forced idle: an
    // ACTIVE observation means the force-idle broke, so the run proves nothing
    // about Doze and must be an inconclusive red rather than a silent
    // "deferred" pass.
    if (stateAtObservation != 'IDLE' &&
        stateAtObservation != 'IDLE_MAINTENANCE') {
      throw _Failure(
        'G7 Doze left forced idle before the delivery boundary '
        '(state=$stateAtObservation); neither delivery arm can be attributed '
        'to Doze. Re-run the leg.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final disposition = deliveredWhileForced && stateAtObservation == 'IDLE'
        ? 'delivered_during_idle'
        : 'deferred_until_maintenance';

    await _releaseDoze();
    // Convergence is load-bearing only in the deferred arm; in the delivered
    // arm the card already exists and this is a no-op observation.
    final card = await _waitForNotification(marker);
    final cardsAfterRelease = extractActiveNotificationCards(
      await _notificationDump(),
      packageName: packageName,
    ).where((entry) => entry.body == marker).toList(growable: false);
    if (cardsAfterRelease.length != 1) {
      throw _Failure(
        'G7 Doze converged to ${cardsAfterRelease.length} cards for one '
        'message; AC-04/AC-10 require exactly one.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    final drain = await _restartAndDrain(
      runId: runId,
      nonce: _token('nonce'),
      marker: marker,
      messageId: sent.messageId,
    );
    if (drain['messageCount'] != 1 || drain['pendingRelayEntries'] != 0) {
      throw _Failure(
        'G7 Doze duplicated or lost the deferred message after convergence.',
        assertionsAttempted: _assertionsAttempted,
      );
    }

    return androidNotificationScenarioArtifact(
      testCase: 'TC-380-09',
      scenario: 'tc_g7_doze_delivery',
      devices: <String>[physical, emulator],
      passedChecks: _dozeDeliveryChecks,
      capturedAt: DateTime.now(),
      evidence: <String, Object?>{
        'messageIdPrefix': safeNotificationIdPrefix(sent.messageId),
        'senderTransport': sent.transport,
        'dozeStateBeforeSend': stateBeforeSend,
        'dozeStateAtObservation': stateAtObservation,
        'dozeDisposition': disposition,
        'dozeConvergedCardCount': cardsAfterRelease.length,
        'dozeConvergedCardTitlePresent': card.title.isNotEmpty,
        'dozeConvergedMessageCount': drain['messageCount'],
        'childBuildCount': 0,
      },
    );
  }

  Future<String> _deepIdleState() async {
    final raw = (await _shellText(emulator, const <String>[
      'dumpsys',
      'deviceidle',
      'get',
      'deep',
    ])).trim();
    if (!RegExp(r'^[A-Z_]{3,32}$').hasMatch(raw)) {
      throw _Failure(
        'Android deep-idle state is not observable on the receiver.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    return raw;
  }

  Future<void> _releaseDoze() async {
    await _adb(emulator, const <String>[
      'shell',
      'dumpsys',
      'deviceidle',
      'unforce',
    ]);
    await _adb(emulator, const <String>['shell', 'dumpsys', 'battery', 'reset']);
    await _waitFor(
      'deep idle release',
      const Duration(seconds: 60),
      () async => await _deepIdleState() == 'ACTIVE',
    );
    _dozeForced = false;
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

  Future<ActiveNotificationCard> _waitForNotification(String marker) async =>
      (await _waitForNotificationObservation(marker)).card;

  /// Waits for the run-bound card and returns the channel(s) it occupied in
  /// the SAME dumpsys read that first saw it.
  ///
  /// Reading the alert channel from a LATER dump is unsound. When both
  /// delivery paths reach the same message, the losing path reconciles the
  /// claim and then performs a silent same-ID in-place update
  /// (`local_notification_support.dart:47-49`,
  /// `flutter_notification_service.dart:406-415`), which moves the record onto
  /// `mknoon_messages_silent`. That is the designed single-alert behaviour —
  /// the alert already happened — but a later dump reports it as a silent
  /// alert. Device-measured 2026-08-19: `PUSH_BACKGROUND_NOTIFICATION_SHOWN`
  /// at T, `NOTIFICATION_LEGACY_CLAIM_RECONCILE` at T+2.5s, then
  /// `NOTIFICATION_SHOWN {"silent":true}` 140 ms after that — which failed B13
  /// as a product defect on a correct delivery.
  Future<({ActiveNotificationCard card, List<String> channels})>
  _waitForNotificationObservation(String marker) async {
    final observation =
        await _waitForValue<({ActiveNotificationCard card, List<String> channels})>(
          'run-bound Android FCM notification card',
          const Duration(minutes: 2),
          () async {
            final dump = await _notificationDump();
            final matching = extractActiveNotificationCards(
              dump,
              packageName: packageName,
            ).where((card) => card.body == marker).toList(growable: false);
            if (matching.length != 1) return null;
            return (
              card: matching.single,
              channels: androidNotificationChannelsForBody(
                dump,
                packageName: packageName,
                body: marker,
              ),
            );
          },
        );
    // Every publication consumes the conversation's tone reservation, so the
    // spacing owed to the NEXT audible-asserting send is keyed here.
    _lastCardObservedAt = DateTime.now();
    return observation;
  }

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
        // Observing a card here counts against the conversation's tone
        // reservation exactly as `_waitForNotification` does: A6's card is a
        // real audible publication (NOTIFICATION_SHOWN silent=false), so the
        // next audible-asserting send owes it the full window.
        _lastCardObservedAt = DateTime.now();
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

  /// Starts a LIVE `adb logcat` reader and appends it to a run-local file.
  ///
  /// A post-hoc `logcat -d -t <cursor>` window is UNSOUND on this receiver and
  /// fails silently. Measured 2026-08-19 on `emulator-5554`: the `main` ring is
  /// **2 MiB** (`logcat -g`) while a busy campaign minute emits **~1.6 MB**, and
  /// legs read events 60-120 s after they are logged. A rotated-out event
  /// returns an EMPTY window, which is indistinguishable from "the app never
  /// emitted it" — so the campaign reported a product defect for a log line
  /// that had simply aged out. A live reader cannot rotate: bytes are captured
  /// as they are produced.
  ///
  /// It also means a FAILING run leaves its log behind. The campaign uninstalls
  /// the app on exit, so a post-mortem `logcat -d` is empty by then; that is
  /// exactly why a 2026-08-19 failure of `tc_g7_permission_denied` could not be
  /// diagnosed after the fact.
  ///
  /// Deliberately NEVER `logcat -c`: the device log is shared with whatever
  /// else is attached, and the adapter contract fails the campaign for clearing
  /// it (`notification_tap_campaign_adapter_contract_test.sh:237`). `-T 1`
  /// starts the tail at the newest line instead, so no historical backlog is
  /// dumped into the file — a backlog would put early cursors inside old text
  /// and let a stale line satisfy a predicate.
  Future<void> _startDeviceLogStream() async {
    final file = File('${proofDirectory.path}/device-logcat.txt');
    // `adb` writes the file itself through a shell redirect; Dart never
    // touches the bytes.
    //
    // The obvious implementation — pipe `process.stdout` into an IOSink from
    // `File.openWrite` — is WRONG here and fails under load: `IOSink.flush`
    // sets `_isBound`, so every cursor read (which flushed to make the tail
    // visible) raced the stdout listener and threw
    // `Bad state: StreamSink is bound to a stream`. Measured: it killed a run
    // at assertion 1. Letting the OS own the write removes the sink, the flush
    // and the race together, and the log lands on disk incrementally so it
    // survives even a hard crash.
    final process = await Process.start('/bin/sh', <String>[
      '-c',
      // Positional parameters, never interpolation: the device id and path go
      // in as argv, so nothing here is shell-quoted or injectable.
      'exec adb -s "\$1" logcat -T 1 -v brief >"\$2"',
      'sims-device-log',
      emulator,
      file.path,
    ]);
    _deviceLogFile = file;
    _deviceLogProcess = process;
    unawaited(process.stderr.drain<void>());
    unawaited(
      process.exitCode.then((code) {
        // Only an exit we did not ask for is a failure; `_stopDeviceLogStream`
        // clears the handle before killing.
        if (_deviceLogProcess != null) {
          _deviceLogFailure = 'adb logcat exited with code $code';
        }
      }),
    );
    // `-T 1` emits immediately and the emulator is never silent for long, so a
    // stream that produces nothing is broken rather than merely quiet.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await file.exists() && await file.length() > 0) return;
      if (_deviceLogFailure != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw _Blocked(
      'deviceLogStream',
      'The receiver log stream produced no output '
          '${_deviceLogFailure == null ? 'within 30s' : '($_deviceLogFailure)'}; '
          'every leg assertion that reads a log window would be vacuous.',
    );
  }

  Future<void> _stopDeviceLogStream() async {
    final process = _deviceLogProcess;
    _deviceLogProcess = null;
    process?.kill();
  }

  Future<File> _requireDeviceLogStream() async {
    final failure = _deviceLogFailure;
    if (failure != null) {
      throw _Blocked(
        'deviceLogStream',
        'The receiver log stream stopped mid-run ($failure), so every log '
            'window from here on would be silently truncated.',
      );
    }
    final file = _deviceLogFile;
    if (file == null) {
      throw const _Blocked(
        'deviceLogStream',
        'The receiver log stream was never started.',
      );
    }
    return file;
  }

  /// A cursor is a BYTE OFFSET into the live stream, not a device timestamp.
  ///
  /// The name is contract-pinned
  /// (`notification_tap_campaign_adapter_contract_test.sh:239` requires a
  /// non-destructive log window); the mechanism underneath it is what changed.
  Future<String> _deviceLogcatCursor() async =>
      '${await (await _requireDeviceLogStream()).length()}';

  Future<String> _logcatSince(String cursor) async {
    final file = await _requireDeviceLogStream();
    final start = int.tryParse(cursor);
    if (start == null) {
      throw _Failure(
        'Android log cursor "$cursor" is not a stream offset.',
        assertionsAttempted: _assertionsAttempted,
      );
    }
    final length = await file.length();
    if (start >= length) return '';
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      return utf8.decode(await handle.read(length - start), allowMalformed: true);
    } finally {
      await handle.close();
    }
  }

  /// Waits for [event] to appear in the window opened at [cursor].
  Future<List<AndroidFlowRecord>> _awaitFlowRecords(
    String cursor,
    String event,
    Duration timeout,
  ) async {
    final deadline = DateTime.now().add(timeout);
    var records = const <AndroidFlowRecord>[];
    while (DateTime.now().isBefore(deadline)) {
      records = (await _flowRecordsSince(
        cursor,
      )).where((record) => record.event == event).toList(growable: false);
      if (records.isNotEmpty) return records;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return records;
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
    // Post-observation grace. A kill landing between the native show and the
    // tone lease's publication commit leaves a `publishing` residue whose
    // repair restarts a fresh SILENT window at the next reservation
    // (`durable_notification_tone_lease.dart:994-1005`, `:1364-1385`), which
    // would silence a later audible-asserting card no matter how the sends
    // are spaced. Applied to every kill because every kill in this campaign
    // can follow a card observation.
    await Future<void>.delayed(_toneCommitGrace);
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
    // A cold first launch on a freshly installed build can outrun `am start
    // -W`'s idle wait and report `Status: timeout` while the activity is in
    // fact up and top-resumed (measured 10.4 s on 21071FDF600CSC: pid alive,
    // topResumedActivity == com.mknoon.app/.MainActivity). Retry instead of
    // relaxing the predicate — an exact `Status: ok` is still required, and a
    // device that never gets there still fails.
    for (var attempt = 0; attempt < 4; attempt++) {
      final result = await _adb(device, <String>[
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        '$packageName/.MainActivity',
      ], allowFailure: true);
      final output = '${result.stdout}\n${result.stderr}';
      final rejected =
          result.exitCode != 0 ||
          !RegExp(
            r'^Status:[ \t]+ok[ \t]*\r?$',
            multiLine: true,
          ).hasMatch(output);
      if (!rejected) return;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw _Failure(
      'The installed app could not launch on $device.',
      assertionsAttempted: _assertionsAttempted,
    );
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
    for (final scenario in _androidPayloadCampaignScenarios) {
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
    _tokenRotationInFlight = false;
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

/// The typed detail of a campaign failure, without leaking arbitrary error
/// text into the sims verdict.
String _describeFailure(Object error) => switch (error) {
  _Failure(:final detail) => detail,
  _Blocked(:final detail) => detail,
  AndroidAppStateFailure(:final detail) => detail,
  _ => error.runtimeType.toString(),
};

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
