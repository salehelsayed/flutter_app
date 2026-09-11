#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/connectivity_restore_e2e_contract.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/device_criteria.dart';
import '../support/android_app_state_guard.dart';
import '../support/android_connectivity_restore_campaign.dart';
import '../support/sims_runtime_protocol.dart';
import '_android_app_package.dart';

const _capabilityId = connectivityRestoreScenarioId;
const _profileId = simsAndroidMainProfileId;
const _validatorId = 'validateConnectivityRestoreArtifact';
const _artifactEnvironment = 'SIMS_ARTIFACT_ANDROID_E2E_MAIN';
const _physicalEnvironment = 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';
const _emulatorEnvironment = 'SIMS_ANDROID_EMULATOR_DEVICE_ID';

/// Launches the prepared application; identity readiness is checked separately
/// by the campaign's existing bounded identity-export wait.
Future<bool> launchConnectivityRestoreApp({
  required String packageName,
  required Future<ProcessResult> Function(List<String>) runAdb,
}) async {
  final component = '$packageName/com.mknoon.app.MainActivity';
  final result = await runAdb(<String>[
    'shell',
    'am',
    'start',
    '-W',
    '-n',
    component,
  ]);
  final output = '${result.stdout}\n${result.stderr}';
  // `am start -W` can time out waiting for the first frame while Flutter is
  // still initializing. Require the requested component and a live process;
  // the campaign still waits up to 120 seconds for its actual identity export.
  if (result.exitCode != 0 ||
      output.contains('Error:') ||
      !RegExp(
        r'^Status:[ \t]+(?:ok|timeout)[ \t]*\r?$',
        multiLine: true,
      ).hasMatch(output) ||
      !RegExp(
        r'(?:\bcmp=|^Activity:[ \t]+)' +
            RegExp.escape(component) +
            r'(?=[\s}]|$)',
        multiLine: true,
      ).hasMatch(output)) {
    return false;
  }
  final process = await runAdb(<String>['shell', 'pidof', packageName]);
  return process.exitCode == 0 &&
      RegExp(
        r'^[1-9][0-9]*(?:[ \t]+[1-9][0-9]*)*$',
      ).hasMatch('${process.stdout}'.trim());
}

Future<void> main() async {
  _Result result;
  try {
    result = await _Campaign.fromEnvironment().run();
  } on _Blocked catch (error) {
    result = _Result.blocked(error.detail);
  } on _Failure catch (error) {
    result = _Result.fail(error.detail);
  } on Object {
    result = _Result.fail('Connectivity campaign failed in the host harness.');
  }
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.exitCode;
}

final class _Campaign {
  _Campaign({
    required this.artifact,
    required this.physical,
    required this.emulator,
    required this.packageName,
    required this.proofDirectory,
  });

  factory _Campaign.fromEnvironment() {
    String requiredValue(String name) {
      final value = Platform.environment[name]?.trim();
      if (value == null || value.isEmpty) {
        throw _Blocked('Required sims binding $name is unavailable.');
      }
      return value;
    }

    final artifact = File(requiredValue(_artifactEnvironment)).absolute;
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
        FileSystemEntityType.file) {
      throw const _Blocked('The centrally prepared main-app APK is missing.');
    }
    final physical = requiredValue(_physicalEnvironment);
    final emulator = requiredValue(_emulatorEnvironment);
    final safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    if (!safeTarget.hasMatch(physical) ||
        !safeTarget.hasMatch(emulator) ||
        physical == emulator ||
        !emulator.startsWith('emulator-')) {
      throw const _Blocked(
        'Connectivity requires one explicit physical Android and one distinct '
        'Android emulator target.',
      );
    }
    final proofPath = Platform.environment['SIMS_PROOF_DIRECTORY']?.trim();
    return _Campaign(
      artifact: artifact,
      physical: physical,
      emulator: emulator,
      packageName: resolveAndroidAppPackage(),
      proofDirectory: Directory(
        proofPath == null || proofPath.isEmpty
            ? 'build/sims/proofs/$_capabilityId'
            : proofPath,
      ).absolute,
    );
  }

  final File artifact;
  final String physical;
  final String emulator;
  final String packageName;
  final Directory proofDirectory;
  final Random _random = Random.secure();

  Future<_Result> run() async {
    await _preflight();
    final apkSha256 = sha256.convert(artifact.readAsBytesSync()).toString();
    final runId = _token('run');
    final nonce = _token('nonce');
    final senderInvocation = _invocation(
      role: 'sender',
      targetId: physical,
      targetKind: 'physical',
      runId: runId,
      nonce: nonce,
      apkSha256: apkSha256,
    );
    final receiverInvocation = _invocation(
      role: 'receiver',
      targetId: emulator,
      targetKind: 'emulator',
      runId: runId,
      nonce: nonce,
      apkSha256: apkSha256,
    );
    for (final invocation in <SimsRuntimeInvocation>[
      senderInvocation,
      receiverInvocation,
    ]) {
      final failure = validateConnectivityRestoreInvocation(invocation);
      if (failure != null) throw _Failure(failure);
    }

    final originalNetwork = await _NetworkState.capture(this, emulator);
    var networkMutated = false;
    late final AndroidAppStateGuard stateGuard;
    try {
      stateGuard = await AndroidAppStateGuard.capture(
        devices: <String>[physical, emulator],
        packageName: packageName,
        backupLabel: 'connectivity',
      );
    } on AndroidAppStateBlocked catch (error) {
      throw _Blocked(error.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _Failure(error.detail);
    }
    late Map<String, Object?> acceptedPayload;
    try {
      await _installFresh(physical, 'sims-connectivity-sender', stateGuard);
      await _installFresh(emulator, 'sims-connectivity-receiver', stateGuard);
      await _launch(physical);
      await _launch(emulator);

      final senderIdentity = await _identity(physical);
      final receiverIdentity = await _identity(emulator);
      await _runConfig(physical, <String, Object?>{
        'stepId': 'connectivity-contacts-$runId',
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
      await _runConfig(emulator, <String, Object?>{
        'stepId': 'connectivity-accept-$runId',
        'contact_request_action': 'accept_all',
        'contact_settle_delay_ms': 1500,
      });
      await _runConfig(emulator, <String, Object?>{
        'stepId': 'connectivity-open-$runId',
        'open_conversation_with_peer_id': senderIdentity.peerId,
        'open_conversation_retry_cycles': 16,
        'post_navigation_delay_ms': 1000,
      });
      await _requireForeground(emulator);

      await _setNetworkAvailable(emulator, false);
      networkMutated = true;
      await _waitFor(
        'Android disconnected state',
        const Duration(seconds: 30),
        () => _networkAvailable(emulator).then((available) => !available),
      );
      await _requireForeground(emulator);

      final observeStep = 'connectivity-observe-$runId';
      final observeRequest = <String, Object?>{
        'schema': connectivityRestoreWindowRequestSchema,
        'transport_action': connectivityRestoreObserveAction,
        'scenario': _capabilityId,
        'role': 'receiver',
        'runId': runId,
        'nonce': nonce,
        'stepId': observeStep,
        'contactPeerId': senderIdentity.peerId,
        'receiverNetwork': 'disconnected',
        'appForeground': true,
        'timeoutMs': 120000,
      };
      final requestFailure = validateConnectivityRestoreWindowRequest(
        observeRequest,
        invocation: receiverInvocation,
      );
      if (requestFailure != null) throw _Failure(requestFailure);
      await _stageConfig(emulator, observeRequest);
      await _waitForResult(
        emulator,
        stepId: observeStep,
        expectedStatus: 'armed',
        runId: runId,
        nonce: nonce,
        timeout: const Duration(seconds: 20),
      );

      final texts = connectivityRestoreMessageTexts(runId);
      final senderResult = await _runConfig(physical, <String, Object?>{
        'stepId': connectivityRestoreSenderStepId(runId),
        'send_chat_messages': <Object?>[
          for (final text in texts)
            <String, Object?>{
              'targetPeerId': receiverIdentity.peerId,
              'text': text,
            },
        ],
      });
      final sendFailure = validateConnectivityRestoreSendResult(
        senderResult,
        invocation: senderInvocation,
      );
      if (sendFailure != null) throw _Failure(sendFailure);

      await _setNetworkAvailable(emulator, true);
      await _waitFor(
        'Android restored state',
        const Duration(seconds: 45),
        () => _networkAvailable(emulator),
      );
      await _requireForeground(emulator);
      final receiverResult = await _waitForResult(
        emulator,
        stepId: observeStep,
        expectedStatus: 'complete',
        runId: runId,
        nonce: nonce,
        timeout: const Duration(seconds: 120),
      );
      await originalNetwork.restore(this, emulator);
      networkMutated = false;

      final events = _strings(receiverResult['events']);
      if (receiverResult['success'] != true ||
          receiverResult['observedMessageCount'] != 3 ||
          receiverResult['resumeEventsDuringWindow'] != 0) {
        throw const _Failure(
          'The production receiver did not complete the no-resume restore proof.',
        );
      }
      final rendered = await _proveRenderedTexts(texts);
      final coreArtifact = <String, Object?>{
        'scenario': _capabilityId,
        'status': 'passed',
        'deviceIds': <String>[physical, emulator],
        'messagesQueued': 3,
        'messagesRendered': rendered,
        'events': events,
        'resumeEventsDuringWindow': events
            .where((event) => event.startsWith('APP_LIFECYCLE_RESUME_'))
            .length,
      };
      acceptedPayload = <String, Object?>{
        ...coreArtifact,
        'targetKinds': const <String>['physical', 'emulator'],
        'preparedBuild': <String, Object?>{
          'profileId': _profileId,
          'sha256': apkSha256,
        },
        'runBinding': <String, Object?>{
          'runIdSha256': sha256.convert(utf8.encode(runId)).toString(),
          'nonceSha256': sha256.convert(utf8.encode(nonce)).toString(),
        },
        'childFlutterBuilds': 0,
      };
      final validation = validateConnectivityRestoreArtifact(acceptedPayload);
      if (!validation.ok) throw _Failure(validation.detail);
    } on AndroidAppStateFailure catch (error) {
      throw _Failure(error.detail);
    } finally {
      if (networkMutated) {
        await originalNetwork.restore(this, emulator, allowFailure: true);
      }
      try {
        await stateGuard.restoreAll();
      } on AndroidAppStateFailure catch (error) {
        throw _Failure(error.detail);
      }
    }
    final evidence = writeSimsArtifactEvidenceSync(
      directory: proofDirectory,
      capabilityId: _capabilityId,
      validatorIds: const <String>[_validatorId],
      payload: acceptedPayload,
    );
    final audit = auditSimsArtifactEvidence(
      evidence: evidence,
      expectedValidatorIds: const <String>[_validatorId],
    );
    if (!audit.isValid) throw _Failure(audit.detail);
    return _Result.pass(evidence);
  }

  SimsRuntimeInvocation _invocation({
    required String role,
    required String targetId,
    required String targetKind,
    required String runId,
    required String nonce,
    required String apkSha256,
  }) => SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: _profileId,
    scenarioId: _capabilityId,
    role: role,
    runId: runId,
    nonce: nonce,
    values: <String, Object?>{
      'targetId': targetId,
      'targetKind': targetKind,
      'buildArtifactSha256': apkSha256,
    },
  );

  Future<void> _preflight() async {
    final version = await _adb(null, const <String>[
      'version',
    ], allowFailure: true);
    if (version.exitCode != 0) {
      throw const _Blocked('ADB is unavailable for the connectivity campaign.');
    }
    for (final device in <String>[physical, emulator]) {
      final state = await _adb(device, const <String>[
        'get-state',
      ], allowFailure: true);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw _Blocked('Android target $device is not ready.');
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
        'Live Android targets do not match physical-sender/emulator-receiver.',
      );
    }
    if (!await _networkAvailable(physical) ||
        !await _networkAvailable(emulator)) {
      throw const _Blocked(
        'Both selected Android targets must begin with a usable network.',
      );
    }
  }

  Future<void> _installFresh(
    String device,
    String username,
    AndroidAppStateGuard stateGuard,
  ) async {
    await stateGuard.prepareFreshInstall(device: device, artifact: artifact);
    await _writeAppFile(
      device,
      'auto_setup.json',
      jsonEncode(<String, Object?>{'username': username}),
    );
  }

  Future<void> _launch(String device) async {
    if (!await launchConnectivityRestoreApp(
      packageName: packageName,
      runAdb: (arguments) => _adb(device, arguments, allowFailure: true),
    )) {
      throw _Failure('App launch failed on $device.');
    }
  }

  Future<_Identity> _identity(String device) async {
    final raw = await _waitForValue<String>(
      'main-app identity export',
      const Duration(seconds: 120),
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
      throw const _Failure('Main-app identity export was malformed.');
    }
  }

  Future<Map<String, Object?>> _runConfig(
    String device,
    Map<String, Object?> config,
  ) async {
    final stepId = config['stepId'] as String;
    await _stageConfig(device, config);
    return _waitForResult(
      device,
      stepId: stepId,
      expectedStatus: 'complete',
      timeout: const Duration(seconds: 180),
    );
  }

  Future<void> _stageConfig(String device, Map<String, Object?> config) async {
    await _removeAppFile(device, 'intro_e2e_result.json');
    await _removeAppFile(device, 'intro_e2e_config.json');
    await _writeAppFile(device, 'intro_e2e_config.json', jsonEncode(config));
  }

  Future<Map<String, Object?>> _waitForResult(
    String device, {
    required String stepId,
    required String expectedStatus,
    String? runId,
    String? nonce,
    required Duration timeout,
  }) async {
    final raw = await _waitForValue<String>(
      '$stepId/$expectedStatus',
      timeout,
      () async {
        final value = await _readAppFile(device, 'intro_e2e_result.json');
        if (value == null) return null;
        try {
          final result = _object(jsonDecode(value));
          if (result['stepId'] != stepId ||
              result['status'] != expectedStatus ||
              (runId != null &&
                  result['schema'] != connectivityRestoreObserveResultSchema) ||
              (runId != null && result['runId'] != runId) ||
              (nonce != null && result['nonce'] != nonce)) {
            return null;
          }
          return value;
        } on Object {
          return null;
        }
      },
    );
    final result = _object(jsonDecode(raw));
    if (result['success'] != true) {
      throw _Failure('Production step $stepId did not succeed.');
    }
    return result;
  }

  Future<int> _proveRenderedTexts(List<String> texts) async {
    final found = <String>{};
    for (
      var attempt = 0;
      attempt < 10 && found.length < texts.length;
      attempt++
    ) {
      await _requireForeground(emulator);
      const remote = '/sdcard/sims-connectivity-window.xml';
      await _adb(emulator, const <String>[
        'shell',
        'uiautomator',
        'dump',
        remote,
      ]);
      final xmlResult = await _adb(emulator, const <String>[
        'shell',
        'cat',
        remote,
      ]);
      final xml = '${xmlResult.stdout}';
      for (final text in texts) {
        if (xml.contains(
              const HtmlEscape(HtmlEscapeMode.attribute).convert(text),
            ) ||
            xml.contains(text)) {
          found.add(text);
        }
      }
      if (found.length < texts.length) {
        await _adb(emulator, const <String>[
          'shell',
          'input',
          'swipe',
          '540',
          '1450',
          '540',
          '450',
          '350',
        ], allowFailure: true);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    if (found.length != 3) {
      throw const _Failure(
        'UIAutomator did not render all three run-bound receiver messages.',
      );
    }
    return found.length;
  }

  Future<void> _requireForeground(String device) async {
    final dump = await _shellText(device, const <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    final foregroundLines = dump
        .split('\n')
        .where(
          (line) =>
              line.contains('ResumedActivity') ||
              line.contains('topResumedActivity'),
        )
        .join('\n');
    if (!foregroundLines.contains(packageName)) {
      throw const _Failure(
        'Receiver was not foreground during the connectivity window.',
      );
    }
  }

  Future<void> _setNetworkAvailable(String device, bool available) async {
    await _adb(device, <String>[
      'shell',
      'cmd',
      'connectivity',
      'airplane-mode',
      available ? 'disable' : 'enable',
    ]);
    await _adb(device, <String>[
      'shell',
      'svc',
      'wifi',
      available ? 'enable' : 'disable',
    ], allowFailure: true);
    await _adb(device, <String>[
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
        'Android connectivity service did not expose active-network state.',
      );
    }
    final value = match.group(1)!.trim().toLowerCase();
    return value != 'none' && value != 'null' && value != '-1';
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
    local.writeAsStringSync(contents, flush: true);
    final remote = '/data/local/tmp/sims-connectivity-$name';
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
      if (local.existsSync()) local.deleteSync();
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

  Future<String> _shellText(String device, List<String> command) async {
    final result = await _adb(device, <String>['shell', ...command]);
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(
    String? device,
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final result = await Process.run('adb', <String>[
      if (device != null) ...<String>['-s', device],
      ...arguments,
    ]);
    if (!allowFailure && result.exitCode != 0) {
      throw const _Failure('An ADB campaign operation failed.');
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
    throw _Failure('Timed out waiting for $label.');
  }

  Future<T> _waitForValue<T>(
    String label,
    Duration timeout,
    Future<T?> Function() read,
  ) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final value = await read();
      if (value != null) return value;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _Failure('Timed out waiting for $label.');
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
    _Campaign campaign,
    String device,
  ) async {
    final airplane = await campaign._shellText(device, const <String>[
      'cmd',
      'connectivity',
      'airplane-mode',
    ]);
    final wifi = await campaign._shellText(device, const <String>[
      'settings',
      'get',
      'global',
      'wifi_on',
    ]);
    final data = await campaign._shellText(device, const <String>[
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

  Future<void> restore(
    _Campaign campaign,
    String device, {
    bool allowFailure = false,
  }) async {
    Future<void> run(List<String> command) async {
      await campaign._adb(device, <String>[
        'shell',
        ...command,
      ], allowFailure: allowFailure);
    }

    await run(<String>[
      'cmd',
      'connectivity',
      'airplane-mode',
      airplaneEnabled ? 'enable' : 'disable',
    ]);
    await run(<String>['svc', 'wifi', wifiEnabled ? 'enable' : 'disable']);
    await run(<String>['svc', 'data', dataEnabled ? 'enable' : 'disable']);
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
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

List<String> _strings(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const _Failure('Production receiver flow events were malformed.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

final class _Result {
  const _Result(this.exitCode, this.json);

  factory _Result.pass(SimsArtifactEvidence evidence) =>
      _Result(0, <String, Object?>{
        'status': 'PASS',
        'assertionsAttempted': 3,
        'artifactPresent': true,
        'printOnly': false,
        'exitCode': 0,
        'detail':
            'Foreground network restore drained three messages and rewarmed.',
        'artifactEvidence': evidence.toJson(),
      });

  factory _Result.fail(String detail) => _Result(1, <String, Object?>{
    'status': 'FAIL',
    'assertionsAttempted': 3,
    'artifactPresent': false,
    'printOnly': false,
    'blocker': 'test',
    'exitCode': 1,
    'detail': detail,
  });

  factory _Result.blocked(String detail) => _Result(78, <String, Object?>{
    'status': 'BLOCKED',
    'assertionsAttempted': 0,
    'artifactPresent': false,
    'printOnly': false,
    'blocker': 'environment',
    'exitCode': 78,
    'detail': detail,
  });

  final int exitCode;
  final Map<String, Object?> json;
}

final class _Blocked implements Exception {
  const _Blocked(this.detail);
  final String detail;
}

final class _Failure implements Exception {
  const _Failure(this.detail);
  final String detail;
}
