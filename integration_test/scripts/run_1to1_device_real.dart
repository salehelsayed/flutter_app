#!/usr/bin/env dart
//
// FDC-16 / CV-07 — 1:1 device-real scenario catalog and typed dispatcher.
//
// Enumerates the Fast-Direct-Connection 1:1 DEVICE-PROOF campaign (FDC-16
// Closure Gate Register, "device-proof" rows). It is the 1:1 sibling of
// integration_test/scripts/run_group_multi_party_device_real.dart and is wired
// into Plan 258 capability reconciliation. Most historical recipes remain
// intentionally BLOCKED. The executable Android scenarios consume centrally
// prepared APKs and never perform a child build; the two-peer campaigns reuse
// the exact same APK on a physical Android and an Android emulator.
//
// `--list-scenarios` prints one bare scenario id per line (the contract the
// discovery expander parses). This path runs under bare `dart` with no Flutter
// binding. A normal catalog invocation prints the historical recipes, emits one
// typed BLOCKED result, and exits 78. Only `--list-scenarios` may exit zero
// without a typed result because listing is metadata rather than proof.
//
// Usage:
//   dart run integration_test/scripts/run_1to1_device_real.dart \
//     --scenario android.voice_recorder_native_smoke|performance.device.critical \
//     --device <physicalAndroidSerial> --artifact <prebuiltApk>
//
// Scenario → CV row → TC → historical proof mode. Ordering is metadata
// only; it is not an executable `--only N` index.
//
//   fdc11_lan_direct_d1                       CV-08 ⭐KEYSTONE  manual-two-phone
//   fdc12_dcutr_relay_to_direct_upgrade       CV-11  TC-12-12   sim (+ proof test)
//   fdc12_dcutr_symmetric_cgnat_negative      CV-12  TC-12-13   sim (+ proof test)
//   fdc07_cold_circuit_reserve_dispatch       CV-23  TC-07-05   sim
//   fdc07_early_mdns_lan_opportunistic        CV-24  TC-07-06   sim
//   fdc04_warm_open_local                      CV-25  TC-04-15   sim
//   fdc04_network_change_rewarm                CV-26  —          device
//   fdc04_cold_notif_tap_noop                  CV-27  TC-04-05   device
//   fdc09_ios_visible_wake                     CV-15  TC-09-20   device + relay
//   fdc09_presence_set_background_pre_suspend  CV-16  TC-09-21   device + relay
//   fdc09_wake_gate_noncontact_blocked         CV-20  TC-09-23   device + relay (gated CV-19)
//   fdc08_presence_get_smoke                   CV-21  LR1        live-relay
//   fdc13_transport_upgraded_badge             CV-30  —          device
//   fdc14_badge_online_direct                  CV-32  —          device
//   fdc15_lan_media_d1                         CV-34  —          manual-two-phone
//   fdc06_pause_flush_open_send                CV-29  T8         device (gated plan 170)
//   android.voice_recorder_native_smoke        Plan 258          automated physical Android
//   performance.device.critical                Plan 258          automated physical Android
//   android.connectivity_restore_inbox_drain   Plan 258          automated Android pair
//   android.keepalive_drop_skip_direct         Plan 258          automated Android pair
//   android.wake_token_directionality          Plan 258          automated Android pair
//   android.voice_message_e2e                   Plan 258          automated Android pair
//   android.direct_media_blob_custody           Plan 347          automated Android pair
//   vc02.dcutr_upgrade                          Future VC-02       inactive/BLOCKED
//   vc02.dcutr_symmetric_cgnat_negative         Future VC-02       inactive/BLOCKED

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_critical_performance_evidence.dart';
import '../support/android_direct_media_blob_custody_evidence.dart';
import '../support/sims_runtime_protocol.dart';
import '_android_app_package.dart';
import 'android_direct_media_blob_custody_campaign.dart';
import 'android_keepalive_drop_campaign.dart';
import 'android_voice_message_device_campaign.dart';
import 'android_wake_token_directionality_campaign.dart';

const _voiceRecorderScenarioId = simsAndroidVoiceRecorderScenarioId;
const _criticalPerformanceScenarioId = simsAndroidCriticalPerformanceScenarioId;
const _keepaliveDropScenarioId = 'android.keepalive_drop_skip_direct';
const _voiceMessageScenarioId = simsAndroidVoiceMessageScenarioId;
const _directMediaBlobCustodyScenarioId =
    androidDirectMediaBlobCustodyScenarioId;
const _wakeTokenDirectionalityScenarioId = 'android.wake_token_directionality';
const _protectedThumbnailSecureWindowScenarioId =
    'protected-thumbnail-secure-window';
const _protectedThumbnailProofTestPath =
    'integration_test/protected_photo_thumbnail_secure_window_proof_test.dart';
const _voiceRecorderPermission = 'android.permission.RECORD_AUDIO';
const _runtimeDispatcherTarget = 'integration_test/sims_dispatcher.dart';
const _integrationTestDriver = 'test_driver/integration_test.dart';
const _voiceRecorderArtifactValidatorId = 'validateVoiceRecorderArtifact';

class _Scenario {
  const _Scenario(this.id, this.cv, this.tc, this.mode, this.summary);

  final String id;
  final String cv;
  final String tc;
  final String mode;
  final String summary;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    'fdc11_lan_direct_d1',
    'CV-08',
    'FDC-11 D1',
    'manual-two-phone',
    'two phones same WiFi take a libp2p LAN-direct leg, both OS (KEYSTONE)',
  ),
  _Scenario(
    'fdc12_dcutr_relay_to_direct_upgrade',
    'CV-11',
    'TC-12-12',
    'sim',
    'relay conn upgrades to direct via DCUtR; badge flips to direct',
  ),
  _Scenario(
    'fdc12_dcutr_symmetric_cgnat_negative',
    'CV-12',
    'TC-12-13',
    'sim',
    'symmetric-CGNAT pair stays on relay; no false direct badge',
  ),
  _Scenario(
    'fdc07_cold_circuit_reserve_dispatch',
    'CV-23',
    'TC-07-05',
    'sim',
    'cold T_circuit <= 3s with reserve_dispatch observation',
  ),
  _Scenario(
    'fdc07_early_mdns_lan_opportunistic',
    'CV-24',
    'TC-07-06',
    'sim',
    'early-hoisted mDNS yields an opportunistic LAN leg before drain',
  ),
  _Scenario(
    'fdc04_warm_open_local',
    'CV-25',
    'TC-04-15',
    'sim',
    'eager warmPeer keeps the send on the local leg, not the warmed conn',
  ),
  _Scenario(
    'fdc04_network_change_rewarm',
    'CV-26',
    '-',
    'device',
    'a network change re-fires warmPeer for the active peer',
  ),
  _Scenario(
    'fdc04_cold_notif_tap_noop',
    'CV-27',
    'TC-04-05',
    'device',
    'cold notification-tap warm is a PS-3 no-op (no duplicate dial)',
  ),
  _Scenario(
    'fdc09_ios_visible_wake',
    'CV-15',
    'TC-09-20',
    'device+relay',
    'iOS push wakes visibly (not silent-throttled) for a 1:1 send',
  ),
  _Scenario(
    'fdc09_presence_set_background_pre_suspend',
    'CV-16',
    'TC-09-21',
    'device+relay',
    'presence_set{background} lands before suspend',
  ),
  _Scenario(
    'fdc09_wake_gate_noncontact_blocked',
    'CV-20',
    'TC-09-23',
    'device+relay',
    'a non-contact cannot wake (wake-gate e2e; gated CV-19)',
  ),
  _Scenario(
    'fdc08_presence_get_smoke',
    'CV-21',
    'LR1',
    'live-relay',
    'presence_get smoke against a live relay',
  ),
  _Scenario(
    'fdc13_transport_upgraded_badge',
    'CV-30',
    '-',
    'device',
    'a real-wire transport:upgraded event drives the badge',
  ),
  _Scenario(
    'fdc14_badge_online_direct',
    'CV-32',
    '-',
    'device',
    'the presence badge reaches onlineDirect on a real LAN pair',
  ),
  _Scenario(
    'fdc15_lan_media_d1',
    'CV-34',
    '-',
    'manual-two-phone',
    '1:1 media flows over /mknoon/media-lan/1.0.0 on a real LAN pair',
  ),
  _Scenario(
    'fdc06_pause_flush_open_send',
    'CV-29',
    'T8',
    'device',
    'an open-send-lock survives pause-flush and delivers (gated plan 170)',
  ),
  _Scenario(
    'contact_one_scan_mutual_d1',
    '171',
    'TC-13',
    'manual-two-phone',
    'one QR scan mutually adds both (B auto-adds A tap-free + reciprocal '
        'reaches A); both OS, one contact row each, no duplicate',
  ),
  _Scenario(
    _voiceRecorderScenarioId,
    'Plan 258',
    'Android native recorder',
    'automated-physical-android',
    'pregranted production record plugin writes and cleans up a valid AAC/M4A file',
  ),
  _Scenario(
    _criticalPerformanceScenarioId,
    'Plan 258',
    'Android critical performance',
    'automated-physical-android',
    'shared APK measures real Android frame timing and production Go bridge latency',
  ),
  _Scenario(
    'android.connectivity_restore_inbox_drain',
    'Plan 258',
    'connectivity restore',
    'automated-physical-android-plus-emulator',
    'foreground Android network loss and restore drains exactly three queued messages without resume',
  ),
  _Scenario(
    'android.keepalive_drop_skip_direct',
    'Plan 258',
    'keepalive drop',
    'automated-physical-android-plus-emulator',
    'latched keepalive drop skips a doomed direct dial and recovers through relay custody',
  ),
  _Scenario(
    'android.wake_token_directionality',
    'Plan 258',
    'wake token',
    'automated-physical-android-plus-emulator',
    'registered, stored, and attached wake-token hashes agree without exposing raw tokens',
  ),
  _Scenario(
    _voiceMessageScenarioId,
    'Plan 258',
    'voice message',
    'automated-physical-android-plus-emulator',
    'physical Android records and sends voice through production custody; '
        'an Android emulator receives, downloads, and plays the exact bytes',
  ),
  _Scenario(
    _directMediaBlobCustodyScenarioId,
    'Plan 347',
    'TC-347-09',
    'automated-physical-android-plus-emulator',
    'a physical Android sender restarts after strict blob custody; an Android '
        'emulator reopens the exact bytes and source-pinned ACK retires the '
        'disposable relay authority',
  ),
  _Scenario(
    _protectedThumbnailSecureWindowScenarioId,
    'Plan 301',
    'TC-14',
    'automated-physical-android',
    'protected-photo thumbnail bubble holds real window FLAG_SECURE '
        '(dumpsys SECURE + black screencap) while visible and releases on pop; '
        'the real-transport wire leg rides the registered '
        'android.connectivity_restore_media_outbox campaign (phase 1 sends a '
        'protected photo through the production composer path)',
  ),
  _Scenario(
    'vc02.dcutr_upgrade',
    'Future VC-02',
    'DCUtR upgrade',
    'inactive-blocked',
    'future relay-to-direct call transport upgrade after VC-01/VC-02 implementation',
  ),
  _Scenario(
    'vc02.dcutr_symmetric_cgnat_negative',
    'Future VC-02',
    'DCUtR negative',
    'inactive-blocked',
    'future symmetric-CGNAT call remains on relay without a false direct upgrade',
  ),
];

bool _parseListScenarios(List<String> args) =>
    args.contains('--list-scenarios');

String _parseScenario(List<String> args) {
  var scenario = 'all';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--scenario' && i + 1 < args.length) {
      scenario = args[i + 1].trim().toLowerCase();
      i++;
    } else if (args[i].startsWith('--scenario=')) {
      scenario = args[i].substring('--scenario='.length).trim().toLowerCase();
    }
  }
  return scenario;
}

List<String> _parseDevices(List<String> args) {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    } else if (args[i].startsWith('--device=')) {
      devices.addAll(
        args[i]
            .substring('--device='.length)
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
    }
  }
  return devices;
}

String? _parseArtifact(List<String> args) {
  String? artifact;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--artifact' && i + 1 < args.length) {
      artifact = args[i + 1].trim();
      i++;
    } else if (args[i].startsWith('--artifact=')) {
      artifact = args[i].substring('--artifact='.length).trim();
    }
  }
  return artifact == null || artifact.isEmpty ? null : artifact;
}

List<_Scenario> _scenariosToRun(String scenario) {
  if (scenario == 'all') return _scenarios;
  final match = _scenarios.where((s) => s.id == scenario).toList();
  if (match.isEmpty) {
    throw ArgumentError(
      'Unknown --scenario "$scenario". Expected one of: '
      '${_scenarios.map((s) => s.id).join(', ')}, or all',
    );
  }
  return match;
}

Future<void> main(List<String> args) => runOneToOneDeviceReal(args);

Future<void> runOneToOneDeviceReal(
  List<String> args, {
  AndroidDirectMediaBlobCustodyDeviceDriver? directMediaBlobCustodyDeviceDriver,
}) async {
  final scenario = _parseScenario(args);
  final listScenarios = _parseListScenarios(args);
  final cliDevices = _parseDevices(args);
  final environmentDevice = Platform.environment['ANDROID_SERIAL']?.trim();
  final devices = cliDevices.isNotEmpty
      ? cliDevices
      : <String>[
          if (environmentDevice != null && environmentDevice.isNotEmpty)
            environmentDevice,
        ];
  final environmentArtifact = switch (scenario) {
    _wakeTokenDirectionalityScenarioId =>
      Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_WAKE_TOKEN']?.trim(),
    _keepaliveDropScenarioId =>
      Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_MAIN']?.trim(),
    _voiceMessageScenarioId =>
      Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_MAIN']?.trim(),
    _directMediaBlobCustodyScenarioId =>
      Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_DIRECT_MEDIA_CUSTODY']
          ?.trim(),
    _ => Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_STANDARD']?.trim(),
  };
  final artifact = _parseArtifact(args) ?? environmentArtifact;
  final usage =
      'Usage: dart run integration_test/scripts/run_1to1_device_real.dart '
      '--scenario ${_scenarios.map((s) => s.id).join('|')}|all '
      '--device <physicalAndroidSerial> --artifact <prebuiltApk> '
      '[--list-scenarios]';

  if (listScenarios) {
    try {
      for (final s in _scenariosToRun(scenario)) {
        stdout.writeln(s.id);
      }
    } on ArgumentError catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(usage);
      exit(64);
    }
    return;
  }

  List<_Scenario> toRun;
  try {
    toRun = _scenariosToRun(scenario);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(usage);
    _emitResult(
      _RunnerResult.fail(
        blocker: 'harness',
        detail: error.message,
        processExitCode: 64,
        artifactPresent: artifact != null && _isFile(artifact),
        assertionsAttempted: 0,
      ),
    );
    exitCode = 64;
    return;
  }

  if (toRun.length == 1 && toRun.single.id == _voiceRecorderScenarioId) {
    final result = await _runVoiceRecorder(
      devices: devices,
      artifactPath: artifact,
    );
    _emitResult(result);
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 && toRun.single.id == _criticalPerformanceScenarioId) {
    final result = await _runCriticalPerformance(
      devices: devices,
      artifactPath: artifact,
    );
    _emitResult(result);
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 && toRun.single.id == _keepaliveDropScenarioId) {
    final pairDevices = cliDevices.isNotEmpty
        ? cliDevices
        : <String>[
            if ((Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']!.trim(),
            if ((Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']!.trim(),
          ];
    final result = await _runKeepaliveDropPrerequisite(
      devices: pairDevices,
      artifactPath: artifact,
    );
    _emitResult(result);
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 && toRun.single.id == _voiceMessageScenarioId) {
    final pairDevices = cliDevices.isNotEmpty
        ? cliDevices
        : <String>[
            if ((Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']!.trim(),
            if ((Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']!.trim(),
          ];
    final result = await runAndroidVoiceMessageDeviceCampaign(
      devices: pairDevices,
      artifactPath: artifact,
    );
    stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 &&
      toRun.single.id == _directMediaBlobCustodyScenarioId) {
    final pairDevices = cliDevices.isNotEmpty
        ? cliDevices
        : <String>[
            if ((Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']!.trim(),
            if ((Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']!.trim(),
          ];
    final result = await runAndroidDirectMediaBlobCustodyCampaign(
      devices: pairDevices,
      artifactPath: artifact,
      deviceDriver: directMediaBlobCustodyDeviceDriver,
    );
    stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 &&
      toRun.single.id == _protectedThumbnailSecureWindowScenarioId) {
    final result = await _runProtectedThumbnailSecureWindow(devices: devices);
    _emitResult(result);
    exitCode = result.processExitCode;
    return;
  }

  if (toRun.length == 1 &&
      toRun.single.id == _wakeTokenDirectionalityScenarioId) {
    final pairDevices = cliDevices.isNotEmpty
        ? cliDevices
        : <String>[
            if ((Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']!.trim(),
            if ((Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'] ?? '')
                .trim()
                .isNotEmpty)
              Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']!.trim(),
          ];
    final result = await _runWakeTokenDirectionalityPrerequisite(
      devices: pairDevices,
      artifactPath: artifact,
    );
    _emitResult(result);
    exitCode = result.processExitCode;
    return;
  }

  stdout.writeln('FDC-16 / CV-07 — 1:1 device-real campaign');
  stdout.writeln(
    'Devices: ${devices.isEmpty ? '(none supplied — pass -d <ios,android>)' : devices.join(', ')}',
  );
  stdout.writeln('');
  for (final s in toRun) {
    stdout.writeln('• ${s.id}  [${s.cv} / ${s.tc} / ${s.mode}]');
    stdout.writeln('    ${s.summary}');
  }
  stdout.writeln('');
  stdout.writeln(
    'BLOCKED: the selected catalog recipe has no automated proof driver. '
    'Plan 258 manifest capabilities own requiredness and target availability.',
  );
  _emitResult(
    _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'Selected scenario set contains no implemented device driver.',
      artifactPresent: artifact != null && _isFile(artifact),
    ),
  );
  exitCode = 78;
}

/// Plan 301 TC-14 — protected-thumbnail secure-window proof on one pinned
/// PHYSICAL Android receiver. Launches the in-app proof
/// ([_protectedThumbnailProofTestPath], built from the current tree, so build
/// provenance is inherent) and, during its marker-framed hold windows, runs
/// the OS-EXTERNAL observations:
///   (b) `dumpsys window` shows the symbolic SECURE token in the app
///       WindowState attrs (modern Android emits no `isSecure=` line);
///   (c) `screencap` EXITS 0 and the captured app region is black — the
///       assertion is pixel-based, never exit-code-based;
///   (d) after the conversation content pops, SECURE is absent again.
/// The in-app leg asserts (a): the thumbnail tile — keyed on the tile widget
/// key — is visible without any Open interaction. The real-transport wire leg
/// is owned by the registered android.connectivity_restore_media_outbox
/// campaign (its phase 1 drives a protected-photo send through the production
/// composer path device-to-device).
Future<_RunnerResult> _runProtectedThumbnailSecureWindow({
  required List<String> devices,
}) async {
  if (devices.isEmpty) {
    return _RunnerResult.blocked(
      blocker: 'targetUnavailable',
      detail:
          'An explicit physical Android --device (receiver first) or '
          'ANDROID_SERIAL is required.',
      artifactPresent: true,
    );
  }
  final device = devices.first;
  ProcessResult adbVersion;
  try {
    adbVersion = await Process.run('adb', const <String>['version']);
  } on ProcessException catch (error) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb is unavailable: ${error.message}',
      artifactPresent: true,
    );
  }
  if (adbVersion.exitCode != 0) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb version exited ${adbVersion.exitCode}.',
      artifactPresent: true,
    );
  }
  final targetCheck = await _verifyPhysicalAndroid(device);
  if (targetCheck != null) return targetCheck;

  late final String packageName;
  try {
    packageName = resolveAndroidAppPackage();
  } on Object catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: 'Unable to resolve the Android application ID: $error',
      artifactPresent: true,
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[device],
      packageName: packageName,
      backupLabel: 'protected-thumbnail-secure-window',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: error.detail,
      artifactPresent: true,
    );
  } on AndroidAppStateFailure catch (error) {
    return _RunnerResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      processExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  }

  _RunnerResult? outcome;
  try {
    outcome = await _executeProtectedThumbnailSecureWindowProof(
      device: device,
      packageName: packageName,
    );
  } on ProcessException catch (error) {
    outcome = _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'Device command could not start: ${error.message}',
      artifactPresent: true,
    );
  } on Object catch (error) {
    outcome = _RunnerResult.fail(
      blocker: 'harness',
      detail: 'Secure-window proof failed unexpectedly: $error',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  } finally {
    try {
      await stateGuard.restoreAll();
    } on AndroidAppStateFailure catch (error) {
      _deleteResultEvidence(outcome);
      outcome = _RunnerResult.fail(
        blocker: 'restoration',
        detail: error.detail,
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
    }
  }
  return outcome ??
      _RunnerResult.fail(
        blocker: 'harness',
        detail: 'Secure-window harness produced no terminal result.',
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
}

Future<_RunnerResult> _executeProtectedThumbnailSecureWindowProof({
  required String device,
  required String packageName,
}) async {
  final process = await Process.start('flutter', <String>[
    'test',
    _protectedThumbnailProofTestPath,
    '-d',
    device,
  ]);

  var secureDuringHold = false;
  var screencapExitZero = false;
  var screencapBlackFraction = -1.0;
  var secureAfterPop = true; // must be observed false in the released hold
  var observedSecureHold = false;
  var observedReleasedHold = false;
  Map<String, Object?>? inAppResult;
  final observationErrors = <String>[];
  final pendingObservations = <Future<void>>[];

  Future<void> observeSecureHold() async {
    try {
      secureDuringHold = await _windowHasSecureFlag(device, packageName);
      final capture = await _captureScreen(device);
      screencapExitZero = capture.exitZero;
      screencapBlackFraction = capture.blackFraction;
    } on Object catch (error) {
      observationErrors.add('secure-hold observation failed: $error');
    }
  }

  Future<void> observeReleasedHold() async {
    try {
      secureAfterPop = await _windowHasSecureFlag(device, packageName);
    } on Object catch (error) {
      observationErrors.add('released-hold observation failed: $error');
    }
  }

  void onLine(String line) {
    if (line.contains('P301_MARKER SECURE_HOLD_START') && !observedSecureHold) {
      observedSecureHold = true;
      pendingObservations.add(observeSecureHold());
      return;
    }
    if (line.contains('P301_MARKER RELEASED_HOLD_START') &&
        !observedReleasedHold) {
      observedReleasedHold = true;
      pendingObservations.add(observeReleasedHold());
      return;
    }
    final resultIndex = line.indexOf('P301_RESULT ');
    if (resultIndex >= 0 && inAppResult == null) {
      try {
        inAppResult =
            (jsonDecode(line.substring(resultIndex + 'P301_RESULT '.length))
                    as Map)
                .map((key, value) => MapEntry('$key', value));
      } on Object {
        observationErrors.add('in-app result marker was malformed');
      }
    }
  }

  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        stdout.writeln('[proof] $line');
        onLine(line);
      })
      .asFuture<void>();
  final stderrDone = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stderr.writeln('[proof] $line'))
      .asFuture<void>();

  final testExit = await process.exitCode.timeout(
    const Duration(minutes: 20),
    onTimeout: () {
      process.kill();
      return -1;
    },
  );
  await stdoutDone;
  await stderrDone;
  await Future.wait(pendingObservations);

  if (testExit != 0) {
    return _RunnerResult.fail(
      blocker: 'harness',
      detail:
          'In-app secure-window proof exited $testExit '
          '(${observationErrors.isEmpty ? 'see [proof] output' : observationErrors.join('; ')}).',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  }

  final failures = <String>[
    if (inAppResult == null) 'the in-app P301_RESULT marker was never observed',
    if (inAppResult?['tileVisibleBeforeOpen'] != true)
      '(a) the thumbnail tile was not visible before any Open interaction',
    if (!observedSecureHold) '(b) the secure hold window never opened',
    if (!secureDuringHold)
      '(b) dumpsys window showed no symbolic SECURE flag for $packageName '
          'while the thumbnail was visible',
    if (!screencapExitZero)
      '(c) screencap did not exit 0 during the secure hold',
    if (screencapExitZero && screencapBlackFraction < 0.80)
      '(c) the captured app region was not black '
          '(black fraction $screencapBlackFraction) — the window leaked pixels',
    if (!observedReleasedHold) '(d) the released hold window never opened',
    if (secureAfterPop)
      '(d) SECURE was still present after popping the conversation route',
    ...observationErrors,
  ];
  if (failures.isNotEmpty) {
    return _RunnerResult.fail(
      blocker: 'assertion',
      detail: failures.join(' | '),
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 4,
    );
  }

  final artifactJson = <String, Object?>{
    'schema': 'mknoon.p301.secure-window-proof-artifact.v1',
    'scenario': _protectedThumbnailSecureWindowScenarioId,
    'status': 'passed',
    'deviceId': device,
    'assertions': <String, Object?>{
      'tileVisibleBeforeOpen': true,
      'dumpsysSecureDuringHold': true,
      'screencapExitZero': true,
      'screencapBlackFraction': screencapBlackFraction,
      'dumpsysSecureAfterPop': false,
      'inApp': inAppResult,
    },
    'wireLeg':
        'delegated:android.connectivity_restore_media_outbox (phase 1 sends a '
        'protected photo through the production composer path device-to-device)',
  };
  final evidence = writeSimsArtifactEvidenceSync(
    directory: _proofDirectory(_protectedThumbnailSecureWindowScenarioId),
    capabilityId: _protectedThumbnailSecureWindowScenarioId,
    validatorIds: const <String>['validateProtectedThumbnailSecureWindowProof'],
    payload: artifactJson,
  );
  return _RunnerResult.pass(
    assertionsAttempted: 4,
    detail:
        'Protected-thumbnail secure window held on $device: tile visible '
        'without Open, symbolic SECURE present in dumpsys, screencap black '
        '(fraction $screencapBlackFraction), and SECURE released after pop.',
    artifactEvidence: evidence,
  );
}

/// True when the app's WindowState attrs carry the symbolic SECURE token.
/// Modern Android emits `mAttrs={... fl=... SECURE ...}` — never `isSecure=`.
Future<bool> _windowHasSecureFlag(String device, String packageName) async {
  final result = await Process.run('adb', <String>[
    '-s',
    device,
    'shell',
    'dumpsys',
    'window',
    'windows',
  ]);
  if (result.exitCode != 0) {
    throw StateError('dumpsys window exited ${result.exitCode}');
  }
  final sections = '${result.stdout}'.split(RegExp(r'Window #\d+'));
  return sections
      .where((section) => section.contains(packageName))
      .any((section) => RegExp(r'\bSECURE\b').hasMatch(section));
}

Future<({bool exitZero, double blackFraction})> _captureScreen(
  String device,
) async {
  final result = await Process.run('adb', <String>[
    '-s',
    device,
    'exec-out',
    'screencap',
    '-p',
  ], stdoutEncoding: null);
  if (result.exitCode != 0) {
    return (exitZero: false, blackFraction: -1.0);
  }
  final bytes = result.stdout as List<int>;
  final decoded = img.decodePng(Uint8List.fromList(bytes));
  if (decoded == null) {
    return (exitZero: true, blackFraction: -1.0);
  }
  // Central app region: exclude status/navigation bars, sample the middle.
  final left = (decoded.width * 0.10).round();
  final right = (decoded.width * 0.90).round();
  final top = (decoded.height * 0.15).round();
  final bottom = (decoded.height * 0.85).round();
  var black = 0;
  var total = 0;
  for (var y = top; y < bottom; y += 4) {
    for (var x = left; x < right; x += 4) {
      final pixel = decoded.getPixel(x, y);
      total++;
      if (pixel.r < 24 && pixel.g < 24 && pixel.b < 24) black++;
    }
  }
  if (total == 0) return (exitZero: true, blackFraction: -1.0);
  return (exitZero: true, blackFraction: black / total);
}

/// Delegates to the build-free main-app keepalive campaign. Its controller
/// drives the physical/emulator pair and observes the production latch, send,
/// receipt, and re-arm boundaries without a child Flutter invocation.
Future<_RunnerResult> _runKeepaliveDropPrerequisite({
  required List<String> devices,
  required String? artifactPath,
}) async {
  final result = await runAndroidKeepaliveDropCampaign(
    devices: devices,
    artifactPath: artifactPath,
  );
  return _RunnerResult._(result.exitCode, result.json);
}

/// Delegates to the build-free two-Android wake-token campaign. The dedicated
/// host controller installs one central APK on both peers and emits only three
/// independently sourced SHA-256 observations.
Future<_RunnerResult> _runWakeTokenDirectionalityPrerequisite({
  required List<String> devices,
  required String? artifactPath,
}) async {
  final result = await runAndroidWakeTokenDirectionalityCampaign(
    devices: devices,
    artifactPath: artifactPath,
  );
  return _RunnerResult._(result.processExitCode, result.json);
}

Future<_RunnerResult> _runVoiceRecorder({
  required List<String> devices,
  required String? artifactPath,
}) async {
  if (devices.length != 1) {
    return _RunnerResult.blocked(
      blocker: 'targetUnavailable',
      detail: devices.isEmpty
          ? 'An explicit physical Android --device or ANDROID_SERIAL is required.'
          : 'Exactly one physical Android target is required; received ${devices.length}.',
      artifactPresent: artifactPath != null && _isFile(artifactPath),
    );
  }

  final device = devices.single;
  if (artifactPath == null || artifactPath.isEmpty || !_isFile(artifactPath)) {
    return _RunnerResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable --artifact or '
          'SIMS_ARTIFACT_ANDROID_E2E_STANDARD APK is required.',
      artifactPresent: false,
    );
  }

  final artifact = artifactPath;
  ProcessResult adbVersion;
  try {
    adbVersion = await Process.run('adb', const <String>['version']);
  } on ProcessException catch (error) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb is unavailable: ${error.message}',
      artifactPresent: true,
    );
  }
  if (adbVersion.exitCode != 0) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb version exited ${adbVersion.exitCode}.',
      artifactPresent: true,
    );
  }

  final targetCheck = await _verifyPhysicalAndroid(device);
  if (targetCheck != null) return targetCheck;

  late final String packageName;
  try {
    packageName = resolveAndroidAppPackage();
  } on Object catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: 'Unable to resolve the Android application ID: $error',
      artifactPresent: true,
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[device],
      packageName: packageName,
      backupLabel: 'voice-recorder',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: error.detail,
      artifactPresent: true,
    );
  } on AndroidAppStateFailure catch (error) {
    return _RunnerResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      processExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  }

  _RunnerResult? outcome;
  try {
    await stateGuard.prepareFreshInstall(
      device: device,
      artifact: File(artifact),
    );
    outcome = await _executeVoiceRecorderProof(
      device: device,
      artifact: artifact,
      packageName: packageName,
    );
  } on AndroidAppStateFailure catch (error) {
    outcome = _RunnerResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      processExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  } on ProcessException catch (error) {
    outcome = _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'Device command could not start: ${error.message}',
      artifactPresent: true,
    );
  } on Object catch (error) {
    outcome = _RunnerResult.fail(
      blocker: 'harness',
      detail: 'Voice recorder proof failed unexpectedly: $error',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  } finally {
    try {
      await stateGuard.restoreAll();
    } on AndroidAppStateFailure catch (error) {
      _deleteResultEvidence(outcome);
      outcome = _RunnerResult.fail(
        blocker: 'restoration',
        detail: error.detail,
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
    }
  }
  return outcome ??
      _RunnerResult.fail(
        blocker: 'harness',
        detail: 'Voice recorder harness produced no terminal result.',
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
}

Future<_RunnerResult> _runCriticalPerformance({
  required List<String> devices,
  required String? artifactPath,
}) async {
  if (devices.length != 1) {
    return _RunnerResult.blocked(
      blocker: 'targetUnavailable',
      detail: devices.isEmpty
          ? 'An explicit physical Android --device or ANDROID_SERIAL is required.'
          : 'Exactly one physical Android target is required; received ${devices.length}.',
      artifactPresent: artifactPath != null && _isFile(artifactPath),
    );
  }

  final device = devices.single;
  if (artifactPath == null || artifactPath.isEmpty || !_isFile(artifactPath)) {
    return _RunnerResult.blocked(
      blocker: 'missingArtifact',
      detail:
          'A readable --artifact or '
          'SIMS_ARTIFACT_ANDROID_E2E_STANDARD APK is required.',
      artifactPresent: false,
    );
  }

  final artifact = artifactPath;
  late final String artifactSha256;
  try {
    artifactSha256 = sha256
        .convert(File(artifact).readAsBytesSync())
        .toString();
  } on FileSystemException catch (error) {
    return _RunnerResult.blocked(
      blocker: 'missingArtifact',
      detail: 'The prepared APK could not be read: ${error.message}',
      artifactPresent: false,
    );
  }

  ProcessResult adbVersion;
  try {
    adbVersion = await Process.run('adb', const <String>['version']);
  } on ProcessException catch (error) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb is unavailable: ${error.message}',
      artifactPresent: true,
    );
  }
  if (adbVersion.exitCode != 0) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb version exited ${adbVersion.exitCode}.',
      artifactPresent: true,
    );
  }

  final targetCheck = await _verifyPhysicalAndroid(device);
  if (targetCheck != null) return targetCheck;

  late final String packageName;
  try {
    packageName = resolveAndroidAppPackage();
  } on Object catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: 'Unable to resolve the Android application ID: $error',
      artifactPresent: true,
    );
  }

  late final AndroidAppStateGuard stateGuard;
  try {
    stateGuard = await AndroidAppStateGuard.capture(
      devices: <String>[device],
      packageName: packageName,
      backupLabel: 'critical-performance',
    );
  } on AndroidAppStateBlocked catch (error) {
    return _RunnerResult.blocked(
      blocker: 'environment',
      detail: error.detail,
      artifactPresent: true,
    );
  } on AndroidAppStateFailure catch (error) {
    return _RunnerResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      processExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  }

  _RunnerResult? outcome;
  try {
    await stateGuard.prepareFreshInstall(
      device: device,
      artifact: File(artifact),
    );
    outcome = await _executeCriticalPerformanceProof(
      device: device,
      artifact: artifact,
      artifactSha256: artifactSha256,
      packageName: packageName,
    );
  } on AndroidAppStateFailure catch (error) {
    outcome = _RunnerResult.fail(
      blocker: 'restoration',
      detail: error.detail,
      processExitCode: 1,
      artifactPresent: false,
      assertionsAttempted: 0,
    );
  } on ProcessException catch (error) {
    outcome = _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'Device command could not start: ${error.message}',
      artifactPresent: true,
    );
  } on Object catch (error) {
    outcome = _RunnerResult.fail(
      blocker: 'harness',
      detail: 'Critical performance proof failed unexpectedly: $error',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  } finally {
    try {
      await stateGuard.restoreAll();
    } on AndroidAppStateFailure catch (error) {
      _deleteResultEvidence(outcome);
      outcome = _RunnerResult.fail(
        blocker: 'restoration',
        detail: error.detail,
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
    }
  }
  return outcome ??
      _RunnerResult.fail(
        blocker: 'harness',
        detail: 'Critical performance proof produced no terminal result.',
        processExitCode: 1,
        artifactPresent: false,
        assertionsAttempted: 0,
      );
}

Future<_RunnerResult> _executeCriticalPerformanceProof({
  required String device,
  required String artifact,
  required String artifactSha256,
  required String packageName,
}) async {
  late final SimsRuntimeInvocation invocation;
  try {
    invocation = _newCriticalPerformanceInvocation(
      device: device,
      artifactSha256: artifactSha256,
    );
    final validation = validateAndroidCriticalPerformanceInvocation(invocation);
    if (!validation.ok) {
      throw FormatException(validation.detail);
    }
  } on Object catch (error) {
    return _RunnerResult.fail(
      blocker: 'harness',
      detail: 'Unable to create a safe performance invocation: $error',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  }

  final remoteConfigPath =
      '/data/local/tmp/mknoon-sims-runtime-${invocation.nonce}.json';
  _RunnerResult? outcome;
  SimsArtifactEvidence? durableEvidence;
  try {
    final stageFailure = await _stageRuntimeInvocation(
      device: device,
      packageName: packageName,
      invocation: invocation,
      remoteConfigPath: remoteConfigPath,
    );
    if (stageFailure != null) {
      outcome = _RunnerResult.blocked(
        blocker: 'environment',
        detail: stageFailure,
        artifactPresent: true,
      );
    } else {
      ProcessResult? drive;
      try {
        drive = await Process.run('flutter', <String>[
          'drive',
          '--device-id',
          device,
          '--driver',
          _integrationTestDriver,
          '--target',
          _runtimeDispatcherTarget,
          '--use-application-binary=$artifact',
          '--keep-app-running',
        ]);
      } on ProcessException catch (error) {
        outcome = _RunnerResult.blocked(
          blocker: 'missingDriver',
          detail: 'flutter drive is unavailable: ${error.message}',
          artifactPresent: true,
        );
      }

      if (drive != null) {
        _relayCommandOutput('flutter drive', drive);
        final acknowledgement = await _readRuntimeAcknowledgement(
          device: device,
          packageName: packageName,
          invocation: invocation,
        );
        if (!acknowledgement.accepted) {
          outcome = _RunnerResult.fail(
            blocker: 'harness',
            detail: acknowledgement.detail,
            processExitCode: drive.exitCode == 0 ? 1 : drive.exitCode,
            artifactPresent: true,
            assertionsAttempted: 0,
          );
        } else if (drive.exitCode != 0) {
          outcome = _RunnerResult.fail(
            blocker: 'test',
            detail:
                'Acknowledged critical performance test exited ${drive.exitCode}.',
            processExitCode: drive.exitCode,
            artifactPresent: true,
            assertionsAttempted: androidCriticalPerformanceAssertionCount,
          );
        } else {
          final proofRead = await _readRuntimeScenarioProof(
            device: device,
            packageName: packageName,
            validate: (artifact) {
              final validation = validateAndroidCriticalPerformanceEvidence(
                artifact,
              );
              return validation.ok ? null : validation.detail;
            },
          );
          if (proofRead.artifact == null) {
            outcome = _RunnerResult.fail(
              blocker: 'harness',
              detail: proofRead.detail,
              processExitCode: 1,
              artifactPresent: false,
              assertionsAttempted: 0,
            );
          } else {
            final proofBindingFailure =
                _criticalPerformanceBindingFailure(
                  proofRead.artifact!,
                  invocation,
                ) ??
                _preparedArtifactDigestFailure(artifact, artifactSha256);
            if (proofBindingFailure != null) {
              outcome = _RunnerResult.fail(
                blocker: 'harness',
                detail: proofBindingFailure,
                processExitCode: 1,
                artifactPresent: false,
                assertionsAttempted: 0,
              );
            } else {
              final evidence = writeSimsArtifactEvidenceSync(
                directory: _proofDirectory(_criticalPerformanceScenarioId),
                capabilityId: _criticalPerformanceScenarioId,
                validatorIds: const <String>[
                  androidCriticalPerformanceArtifactValidatorId,
                ],
                payload: androidCriticalPerformanceDurablePayload(
                  proofRead.artifact!,
                ),
              );
              durableEvidence = evidence;
              final durableFailure = _criticalPerformanceDurableEvidenceFailure(
                evidence,
              );
              if (durableFailure != null) {
                try {
                  File(evidence.path).deleteSync();
                } on FileSystemException {
                  // The result still fails closed; cleanup diagnostics are
                  // already represented by [durableFailure].
                }
                durableEvidence = null;
                outcome = _RunnerResult.fail(
                  blocker: 'harness',
                  detail: durableFailure,
                  processExitCode: 1,
                  artifactPresent: false,
                  assertionsAttempted: 0,
                );
              } else {
                outcome = _RunnerResult.pass(
                  assertionsAttempted: androidCriticalPerformanceAssertionCount,
                  detail:
                      'Physical Android dispatcher acknowledged the exact '
                      'standard-profile runtime tuple and the shared APK digest '
                      'before all critical performance budgets passed.',
                  artifactEvidence: evidence,
                );
              }
            }
          }
        }
      }
    }
  } finally {
    final cleanupFailure = await _cleanupRuntimeInvocation(
      device: device,
      packageName: packageName,
      remoteConfigPath: remoteConfigPath,
    );
    if (cleanupFailure != null) {
      String? evidenceCleanupFailure;
      final evidence = durableEvidence;
      if (evidence != null) {
        try {
          File(evidence.path).deleteSync();
          durableEvidence = null;
        } on FileSystemException catch (error) {
          evidenceCleanupFailure =
              ' Failed-run proof cleanup also failed: ${error.message}.';
        }
      }
      outcome = _RunnerResult.fail(
        blocker: 'harness',
        detail: '$cleanupFailure${evidenceCleanupFailure ?? ''}',
        processExitCode: 1,
        artifactPresent: evidenceCleanupFailure != null,
        assertionsAttempted: 0,
      );
    }
  }

  return outcome ??
      _RunnerResult.fail(
        blocker: 'harness',
        detail: 'Runtime-dispatched performance proof produced no result.',
        processExitCode: 1,
        artifactPresent: true,
        assertionsAttempted: 0,
      );
}

Future<_RunnerResult> _executeVoiceRecorderProof({
  required String device,
  required String artifact,
  required String packageName,
}) async {
  final pregrant = await Process.run('adb', <String>[
    '-s',
    device,
    'shell',
    'pm',
    'grant',
    packageName,
    _voiceRecorderPermission,
  ]);
  _relayCommandOutput('adb permission pregrant', pregrant);
  if (pregrant.exitCode != 0) {
    return _RunnerResult.blocked(
      blocker: 'permissions',
      detail: 'Unable to pregrant RECORD_AUDIO.',
      artifactPresent: true,
    );
  }

  late final SimsRuntimeInvocation invocation;
  try {
    invocation = _newRuntimeInvocation();
  } on Object catch (error) {
    return _RunnerResult.fail(
      blocker: 'harness',
      detail: 'Unable to create a safe runtime invocation: $error',
      processExitCode: 1,
      artifactPresent: true,
      assertionsAttempted: 0,
    );
  }

  final remoteConfigPath =
      '/data/local/tmp/mknoon-sims-runtime-${invocation.nonce}.json';
  _RunnerResult? outcome;
  try {
    final stageFailure = await _stageRuntimeInvocation(
      device: device,
      packageName: packageName,
      invocation: invocation,
      remoteConfigPath: remoteConfigPath,
    );
    if (stageFailure != null) {
      outcome = _RunnerResult.blocked(
        blocker: 'environment',
        detail: stageFailure,
        artifactPresent: true,
      );
    } else {
      ProcessResult? drive;
      try {
        drive = await Process.run('flutter', <String>[
          'drive',
          '--device-id',
          device,
          '--driver',
          _integrationTestDriver,
          '--target',
          _runtimeDispatcherTarget,
          '--use-application-binary=$artifact',
          '--keep-app-running',
        ]);
      } on ProcessException catch (error) {
        outcome = _RunnerResult.blocked(
          blocker: 'missingDriver',
          detail: 'flutter drive is unavailable: ${error.message}',
          artifactPresent: true,
        );
      }

      if (drive != null) {
        _relayCommandOutput('flutter drive', drive);
        final acknowledgement = await _readRuntimeAcknowledgement(
          device: device,
          packageName: packageName,
          invocation: invocation,
        );
        if (!acknowledgement.accepted) {
          outcome = _RunnerResult.fail(
            blocker: 'harness',
            detail: acknowledgement.detail,
            processExitCode: drive.exitCode == 0 ? 1 : drive.exitCode,
            artifactPresent: true,
            assertionsAttempted: 0,
          );
        } else if (drive.exitCode != 0) {
          outcome = _RunnerResult.fail(
            blocker: 'test',
            detail:
                'Acknowledged native recorder test exited ${drive.exitCode}.',
            processExitCode: drive.exitCode,
            artifactPresent: true,
            assertionsAttempted: 1,
          );
        } else {
          final proofRead = await _readRuntimeScenarioProof(
            device: device,
            packageName: packageName,
            validate: (artifact) {
              final validation = validateVoiceRecorderArtifact(artifact);
              return validation.ok ? null : validation.detail;
            },
          );
          if (proofRead.artifact == null) {
            outcome = _RunnerResult.fail(
              blocker: 'harness',
              detail: proofRead.detail,
              processExitCode: 1,
              artifactPresent: false,
              assertionsAttempted: 0,
            );
          } else {
            final evidence = writeSimsArtifactEvidenceSync(
              directory: _proofDirectory(_voiceRecorderScenarioId),
              capabilityId: _voiceRecorderScenarioId,
              validatorIds: const <String>[_voiceRecorderArtifactValidatorId],
              payload: <String, Object?>{
                ...proofRead.artifact!,
                'deviceIds': <String>[device],
                'runtimeInvocation': invocation.toJson(),
              },
            );
            outcome = _RunnerResult.pass(
              assertionsAttempted: 4,
              detail:
                  'Physical Android dispatcher acknowledged the profile, '
                  'scenario, role, run, and nonce before the recorder proof.',
              artifactEvidence: evidence,
            );
          }
        }
      }
    }
  } finally {
    final cleanupFailure = await _cleanupRuntimeInvocation(
      device: device,
      packageName: packageName,
      remoteConfigPath: remoteConfigPath,
    );
    if (cleanupFailure != null) {
      outcome = _RunnerResult.fail(
        blocker: 'harness',
        detail: cleanupFailure,
        processExitCode: 1,
        artifactPresent: true,
        assertionsAttempted: 0,
      );
    }
  }

  return outcome ??
      _RunnerResult.fail(
        blocker: 'harness',
        detail: 'Runtime-dispatched recorder proof produced no result.',
        processExitCode: 1,
        artifactPresent: true,
        assertionsAttempted: 0,
      );
}

SimsRuntimeInvocation _newRuntimeInvocation() {
  final invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: simsAndroidStandardProfileId,
    scenarioId: simsAndroidVoiceRecorderScenarioId,
    role: simsPrimaryRole,
    runId: _runtimeToken('SIMS_RUNTIME_RUN_ID', 'run'),
    nonce: _runtimeToken('SIMS_RUNTIME_NONCE', 'nonce'),
    values: const <String, Object?>{'permissionPregranted': true},
  );
  return SimsRuntimeInvocation.fromJson(invocation.toJson());
}

SimsRuntimeInvocation _newCriticalPerformanceInvocation({
  required String device,
  required String artifactSha256,
}) {
  final invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: simsAndroidStandardProfileId,
    scenarioId: _criticalPerformanceScenarioId,
    role: simsPrimaryRole,
    runId: _runtimeToken('SIMS_RUNTIME_RUN_ID', 'run'),
    nonce: _runtimeToken('SIMS_RUNTIME_NONCE', 'nonce'),
    values: <String, Object?>{
      'targetId': device,
      'targetKind': 'physical',
      'buildArtifactSha256': artifactSha256,
    },
  );
  return SimsRuntimeInvocation.fromJson(invocation.toJson());
}

String? _criticalPerformanceBindingFailure(
  Map<String, Object?> artifact,
  SimsRuntimeInvocation invocation,
) {
  final runtime = _stringKeyedObject(artifact['runtime']);
  final sharedArtifact = _stringKeyedObject(artifact['sharedArtifact']);
  if (artifact['targetId'] != invocation.values['targetId'] ||
      runtime == null ||
      runtime['profileId'] != invocation.profileId ||
      runtime['scenarioId'] != invocation.scenarioId ||
      runtime['role'] != invocation.role ||
      runtime['runId'] != invocation.runId ||
      runtime['nonce'] != invocation.nonce ||
      sharedArtifact == null ||
      sharedArtifact['profileId'] != invocation.profileId ||
      sharedArtifact['sha256'] != invocation.values['buildArtifactSha256']) {
    return 'Runtime performance proof does not match the acknowledged target, '
        'profile, scenario, role, run, nonce, and prepared APK digest.';
  }
  return null;
}

String? _preparedArtifactDigestFailure(
  String artifactPath,
  String expectedSha256,
) {
  try {
    final currentSha256 = sha256
        .convert(File(artifactPath).readAsBytesSync())
        .toString();
    return currentSha256 == expectedSha256
        ? null
        : 'The prepared APK changed after its runtime invocation was staged.';
  } on FileSystemException catch (error) {
    return 'The prepared APK could not be re-read after the device proof: '
        '${error.message}.';
  }
}

String? _criticalPerformanceDurableEvidenceFailure(
  SimsArtifactEvidence evidence,
) {
  final audit = auditSimsArtifactEvidence(
    evidence: evidence,
    expectedValidatorIds: const <String>[
      androidCriticalPerformanceArtifactValidatorId,
    ],
  );
  if (!audit.isValid) {
    return 'Written performance evidence failed its content-addressed audit: '
        '${audit.detail}.';
  }
  try {
    final decoded = jsonDecode(File(evidence.path).readAsStringSync());
    if (decoded is! Map) {
      return 'Written performance evidence root is not an object.';
    }
    final artifact = decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final validation = validateAndroidCriticalPerformanceDurableArtifact(
      artifact,
    );
    return validation.ok
        ? null
        : 'Written performance evidence failed validation: '
              '${validation.detail}.';
  } on Object catch (error) {
    return 'Written performance evidence could not be re-read: $error';
  }
}

Map<String, Object?>? _stringKeyedObject(Object? value) {
  if (value is! Map) return null;
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

String _runtimeToken(String environmentKey, String prefix) {
  final configured = Platform.environment[environmentKey]?.trim();
  if (configured != null && configured.isNotEmpty) return configured;
  final random = Random.secure();
  final entropy = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid-$entropy';
}

Future<String?> _stageRuntimeInvocation({
  required String device,
  required String packageName,
  required SimsRuntimeInvocation invocation,
  required String remoteConfigPath,
}) async {
  final hostConfig = File(
    '${Directory.systemTemp.path}/mknoon-sims-$pid-${invocation.nonce}.json',
  );
  try {
    hostConfig.writeAsStringSync(
      '${jsonEncode(invocation.toJson())}\n',
      flush: true,
    );
    final commands = <(String, List<String>, String)>[
      (
        'adb',
        <String>[
          '-s',
          device,
          'shell',
          'run-as',
          packageName,
          'mkdir',
          '-p',
          'files/$simsRuntimeDirectory',
        ],
        'create private runtime directory',
      ),
      (
        'adb',
        <String>[
          '-s',
          device,
          'shell',
          'run-as',
          packageName,
          'rm',
          '-f',
          simsRuntimeConfigRelativePath,
          simsRuntimeAckRelativePath,
          simsRuntimeResultRelativePath,
        ],
        'remove stale runtime config and acknowledgement',
      ),
      (
        'adb',
        <String>['-s', device, 'push', hostConfig.path, remoteConfigPath],
        'push runtime config',
      ),
      (
        'adb',
        <String>[
          '-s',
          device,
          'shell',
          'run-as',
          packageName,
          'cp',
          remoteConfigPath,
          simsRuntimeConfigRelativePath,
        ],
        'stage private runtime config',
      ),
      (
        'adb',
        <String>['-s', device, 'shell', 'rm', '-f', remoteConfigPath],
        'remove transport runtime config',
      ),
    ];
    for (final command in commands) {
      final result = await Process.run(command.$1, command.$2);
      _relayCommandOutput(command.$3, result);
      if (result.exitCode != 0) {
        return '${command.$3} exited ${result.exitCode}';
      }
    }
    return null;
  } finally {
    if (hostConfig.existsSync()) hostConfig.deleteSync();
  }
}

Future<SimsRuntimeProtocolValidation> _readRuntimeAcknowledgement({
  required String device,
  required String packageName,
  required SimsRuntimeInvocation invocation,
}) async {
  final result = await Process.run('adb', <String>[
    '-s',
    device,
    'shell',
    'run-as',
    packageName,
    'cat',
    simsRuntimeAckRelativePath,
  ]);
  if (result.exitCode != 0) {
    return const SimsRuntimeProtocolValidation.reject(
      'Runtime acknowledgement is missing after flutter drive.',
    );
  }
  try {
    final decoded = jsonDecode('${result.stdout}');
    if (decoded is! Map) {
      return const SimsRuntimeProtocolValidation.reject(
        'Runtime acknowledgement root is not an object.',
      );
    }
    return validateSimsRuntimeAck(
      decoded.map<String, Object?>((key, value) => MapEntry('$key', value)),
      invocation,
    );
  } on Object catch (error) {
    return SimsRuntimeProtocolValidation.reject(
      'Runtime acknowledgement is corrupt: $error',
    );
  }
}

Future<_RuntimeProofRead> _readRuntimeScenarioProof({
  required String device,
  required String packageName,
  required String? Function(Map<String, Object?> artifact) validate,
}) async {
  final result = await Process.run('adb', <String>[
    '-s',
    device,
    'shell',
    'run-as',
    packageName,
    'cat',
    simsRuntimeResultRelativePath,
  ]);
  if (result.exitCode != 0) {
    return const _RuntimeProofRead.reject(
      'Runtime scenario proof is missing after flutter drive.',
    );
  }
  try {
    final decoded = jsonDecode('${result.stdout}');
    if (decoded is! Map) {
      return const _RuntimeProofRead.reject(
        'Runtime scenario proof root is not an object.',
      );
    }
    final artifact = decoded.map<String, Object?>(
      (key, value) => MapEntry('$key', value),
    );
    final validationFailure = validate(artifact);
    if (validationFailure != null) {
      return _RuntimeProofRead.reject(
        'Runtime scenario proof failed validation: $validationFailure',
      );
    }
    return _RuntimeProofRead.accept(artifact);
  } on Object catch (error) {
    return _RuntimeProofRead.reject(
      'Runtime scenario proof is corrupt: $error',
    );
  }
}

Future<String?> _cleanupRuntimeInvocation({
  required String device,
  required String packageName,
  required String remoteConfigPath,
}) async {
  try {
    final stop = await Process.run('adb', <String>[
      '-s',
      device,
      'shell',
      'am',
      'force-stop',
      packageName,
    ]);
    _relayCommandOutput('runtime app stop', stop);
    final privateCleanup = await Process.run('adb', <String>[
      '-s',
      device,
      'shell',
      'run-as',
      packageName,
      'rm',
      '-f',
      simsRuntimeConfigRelativePath,
      simsRuntimeAckRelativePath,
      simsRuntimeResultRelativePath,
    ]);
    _relayCommandOutput('runtime private cleanup', privateCleanup);
    final transportCleanup = await Process.run('adb', <String>[
      '-s',
      device,
      'shell',
      'rm',
      '-f',
      remoteConfigPath,
    ]);
    _relayCommandOutput('runtime transport cleanup', transportCleanup);
    if (stop.exitCode != 0 ||
        privateCleanup.exitCode != 0 ||
        transportCleanup.exitCode != 0) {
      return 'Runtime config cleanup failed '
          '(stop=${stop.exitCode}, private=${privateCleanup.exitCode}, '
          'transport=${transportCleanup.exitCode}).';
    }
    return null;
  } on Object catch (error) {
    return 'Runtime config cleanup failed: $error';
  }
}

Future<_RunnerResult?> _verifyPhysicalAndroid(String device) async {
  try {
    final devices = await Process.run('adb', const <String>['devices', '-l']);
    if (devices.exitCode != 0) {
      return _RunnerResult.blocked(
        blocker: 'missingDriver',
        detail: 'adb devices exited ${devices.exitCode}.',
        artifactPresent: true,
      );
    }
    final targetLine = '${devices.stdout}'
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => line.split(RegExp(r'\s+')).first == device)
        .firstOrNull;
    if (targetLine == null ||
        targetLine.split(RegExp(r'\s+')).elementAtOrNull(1) != 'device') {
      return _RunnerResult.blocked(
        blocker: 'targetUnavailable',
        detail: 'Android target "$device" is not attached and ready.',
        artifactPresent: true,
      );
    }

    final state = await Process.run('adb', <String>['-s', device, 'get-state']);
    if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
      return _RunnerResult.blocked(
        blocker: 'targetUnavailable',
        detail: 'Android target "$device" is not in device state.',
        artifactPresent: true,
      );
    }

    if (device.startsWith('emulator-')) {
      return _RunnerResult.blocked(
        blocker: 'targetUnavailable',
        detail: 'Scenario requires a physical Android; "$device" is virtual.',
        artifactPresent: true,
      );
    }

    final qemu = await Process.run('adb', <String>[
      '-s',
      device,
      'shell',
      'getprop',
      'ro.kernel.qemu',
    ]);
    if (qemu.exitCode != 0) {
      return _RunnerResult.blocked(
        blocker: 'environment',
        detail: 'Unable to verify whether "$device" is physical.',
        artifactPresent: true,
      );
    }
    if ('${qemu.stdout}'.trim() == '1') {
      return _RunnerResult.blocked(
        blocker: 'targetUnavailable',
        detail: 'Scenario requires a physical Android; "$device" is virtual.',
        artifactPresent: true,
      );
    }
    return null;
  } on ProcessException catch (error) {
    return _RunnerResult.blocked(
      blocker: 'missingDriver',
      detail: 'adb target verification could not start: ${error.message}',
      artifactPresent: true,
    );
  }
}

bool _isFile(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: true);
  return type == FileSystemEntityType.file;
}

void _relayCommandOutput(String label, ProcessResult result) {
  final commandStdout = '${result.stdout}'.trim();
  final commandStderr = '${result.stderr}'.trim();
  if (commandStdout.isNotEmpty) {
    stderr.writeln('[$label stdout] $commandStdout');
  }
  if (commandStderr.isNotEmpty) {
    stderr.writeln('[$label stderr] $commandStderr');
  }
}

void _emitResult(_RunnerResult result) {
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
}

void _deleteResultEvidence(_RunnerResult? result) {
  final envelope = result?.json['artifactEvidence'];
  if (envelope is! Map) return;
  final path = envelope['path'];
  if (path is! String || path.trim().isEmpty) return;
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // Restoration still fails closed. The retained evidence cannot be used
    // because no PASS sentinel containing its content binding is emitted.
  }
}

final class _RunnerResult {
  const _RunnerResult._(this.processExitCode, this.json);

  factory _RunnerResult.pass({
    required int assertionsAttempted,
    required String detail,
    required SimsArtifactEvidence artifactEvidence,
  }) => _RunnerResult._(0, <String, Object?>{
    'status': 'PASS',
    'assertionsAttempted': assertionsAttempted,
    'artifactPresent': true,
    'printOnly': false,
    'exitCode': 0,
    'detail': detail,
    'artifactEvidence': artifactEvidence.toJson(),
  });

  factory _RunnerResult.fail({
    required String blocker,
    required String detail,
    required int processExitCode,
    required bool artifactPresent,
    required int assertionsAttempted,
  }) => _RunnerResult._(processExitCode, <String, Object?>{
    'status': 'FAIL',
    'assertionsAttempted': assertionsAttempted,
    'artifactPresent': artifactPresent,
    'printOnly': false,
    'blocker': blocker,
    'exitCode': processExitCode,
    'detail': detail,
  });

  factory _RunnerResult.blocked({
    required String blocker,
    required String detail,
    required bool artifactPresent,
  }) => _RunnerResult._(78, <String, Object?>{
    'status': 'BLOCKED',
    'assertionsAttempted': 0,
    'artifactPresent': artifactPresent,
    'printOnly': false,
    'blocker': blocker,
    'exitCode': 78,
    'detail': detail,
  });

  final int processExitCode;
  final Map<String, Object?> json;
}

final class _RuntimeProofRead {
  const _RuntimeProofRead._(this.artifact, this.detail);

  const _RuntimeProofRead.accept(Map<String, Object?> artifact)
    : this._(artifact, 'runtime scenario proof accepted');

  const _RuntimeProofRead.reject(String detail) : this._(null, detail);

  final Map<String, Object?>? artifact;
  final String detail;
}

Directory _proofDirectory(String capabilityId) {
  final configured = Platform.environment['SIMS_PROOF_DIRECTORY']?.trim();
  if (configured != null && configured.isNotEmpty) {
    return Directory(configured).absolute;
  }
  return Directory('build/sims/proofs/$capabilityId').absolute;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? elementAtOrNull(int index) =>
      index < 0 || index >= length ? null : elementAt(index);
}
