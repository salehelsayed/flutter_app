part of 'android_production_audio_call_campaign.dart';

const androidProductionKilledCalleeScenarioId =
    'android.production_call_killed_callee_rings';
const androidProductionKilledCalleeProfileId =
    'android.e2e.production_call_killed_callee';
const androidProductionKilledCalleeAppPackage = 'com.mknoon.sims.notifications';
const androidProductionKilledCalleeArtifactValidatorId =
    'validateAndroidProductionCallKilledCalleeArtifact';

const _killedCalleeProofSchema = 'mknoon.sims.killed-callee.v1';
const _killedCalleeLogTag = 'MknoonVC059';
const _killedCalleeCommands = Duration(seconds: 3);
const _killedCalleeCallerLabels = <String>[
  'Start voice call',
  'Voice call / Video call',
];
const _killedCalleeCancelLabel = 'Cancel call';
const _killedCalleeRequiredFacts = <String>{
  'calleeFcmPublished',
  'initialOwnedProcessGone',
  'directPreDispatchProcessAbsent',
  'directV2EligibleVoiceChoice',
  'directCallerRemoteRinging',
  'directCalleeTelecomRinging',
  'beforeACalleeProcessAbsent',
  'aPreDispatchProcessAbsent',
  'aInvitedBeforeCancel',
  'bCallerRemoteRinging',
  'bCalleeTelecomRinging',
  'bOwnedProcessGoneWhileRinging',
  'cCallerRemoteRinging',
  'cCalleeFreshTelecomRinging',
  'stateRestored',
};

AndroidCampaignEvidenceValidation
validateAndroidProductionCallKilledCalleeArtifact(
  Map<String, Object?> artifact,
) => validateDurableAndroidCampaignArtifact(
  artifact: artifact,
  capabilityId: androidProductionKilledCalleeScenarioId,
  validatorId: androidProductionKilledCalleeArtifactValidatorId,
  validateRuntimeProof: _validateKilledCalleeProof,
);

AndroidCampaignEvidenceValidation _validateKilledCalleeProof(
  Map<String, Object?> proof,
) {
  final cancelMs = proof['aCancelElapsedMs'];
  if (proof['schema'] != _killedCalleeProofSchema ||
      proof['profileId'] != androidProductionKilledCalleeProfileId ||
      proof['packageName'] != androidProductionKilledCalleeAppPackage ||
      proof['topology'] != 'physical-caller-emulator-callee' ||
      !const <String>{
        'apkSha256',
        'artifactInputDigest',
        'relayFixtureIdentitySha256',
      }.every(
        (key) => proof[key] is String && _isSha256(proof[key]! as String),
      ) ||
      !_killedCalleeRequiredFacts.every((key) => proof[key] == true) ||
      cancelMs is! int ||
      cancelMs < 3000 ||
      cancelMs > 6000) {
    return const AndroidCampaignEvidenceValidation.fail(
      'killed-callee proof lacks an exact artifact, deadline, or ringing stage',
    );
  }
  return const AndroidCampaignEvidenceValidation.pass();
}

Future<AndroidProductionAudioCallCampaignResult>
runAndroidProductionKilledCalleeCampaign({
  required List<String> devices,
  required String? artifactPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final package = (env['ANDROID_APP_PACKAGE'] ?? env['SIMS_APP_ID'])?.trim();
  if (env['PLAN399_CALL_FCM_ENABLED'] != '1' ||
      env[_profileEnvironment] != androidProductionKilledCalleeProfileId ||
      package != androidProductionKilledCalleeAppPackage ||
      usesDisposableAndroidPair(env) ||
      devices.length != 2 ||
      devices.toSet().length != 2 ||
      devices.first.isEmpty ||
      devices.first.startsWith('emulator-') ||
      !RegExp(r'^emulator-[0-9]+$').hasMatch(devices.last)) {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail:
          'VC-059 requires the exact disposable APK profile, attested real '
          'FCM, one pinned physical caller and one pinned emulator callee.',
      artifactPresent:
          artifactPath != null && _isRegularFile(File(artifactPath)),
    );
  }

  final ProductionAndroidArtifact artifact;
  final _LocalRelayBinding relay;
  try {
    artifact = ProductionAndroidArtifact.fromEnvironment(
      androidProductionKilledCalleeProfileId,
      env,
      primary: true,
    );
    if ((artifactPath != null &&
            File(artifactPath).absolute.path != artifact.file.path) ||
        (env['B14_EXPECTED_ARTIFACT_RELAY_ADDRESSES'] ?? '').trim() !=
            (env['MKNOON_RELAY_ADDRESSES'] ?? '').trim()) {
      throw const FormatException(
        'Fixture input does not match the prepared artifact.',
      );
    }
    relay = _LocalRelayBinding.fromEnvironment(env);
    final oracle = decodeAndroidProductionAudioCallPionOracleAttestation(
      env[androidProductionAudioCallPionOracleEnvironment] ?? '',
    );
    if (oracle.fixtureInstanceSha256 != relay.coturnInstanceIdentitySha256) {
      throw const FormatException(
        'Fixture authority did not match its attestation.',
      );
    }
  } on Object {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: 'VC-059 needs the centrally prepared APK and matching local Plan399 attestation.',
      artifactPresent:
          artifactPath != null && _isRegularFile(File(artifactPath)),
    );
  }

  final output = env['SIMS_PROOF_DIRECTORY']?.trim();
  final directory = Directory(
    output == null || output.isEmpty
        ? 'build/sims/proofs/$androidProductionKilledCalleeScenarioId'
        : output,
  ).absolute;
  final driver = SystemAndroidProductionAudioCallCampaignDriver(
    physicalDeviceId: devices.last,
    emulatorDeviceId: devices.first,
    artifact: artifact.file,
    artifactSha256: artifact.artifactDigest,
    packageName: androidProductionKilledCalleeAppPackage,
    relayHost: relay.host,
    relayPort: relay.port,
    proofDirectory: directory,
    killedCallee: true,
  );
  final scenario = _ProductionKilledCalleeScenario(driver);
  try {
    validateAndroidProductionAudioCallTopology([
      for (final device in devices)
        AndroidProductionAudioCallTarget(
          deviceId: device,
          kind: await driver.classifyTarget(device),
        ),
    ]);
    await Future.wait(devices.map(driver.verifyRelayReachable));
    await driver.captureState();
  } on FormatException {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'targetUnavailable',
      detail: 'VC-059 targets or the private relay probe failed preflight.',
      artifactPresent: true,
    );
  } on AndroidAppStateBlocked {
    return AndroidProductionAudioCallCampaignResult.blocked(
      blocker: 'environment',
      detail: 'VC-059 was refused by the Android app-state guard.',
      artifactPresent: true,
    );
  } on AndroidAppStateFailure {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'restoration',
      detail: 'VC-059 app-state capture or rollback failed.',
      artifactPresent: true,
    );
  }

  Object? firstFailure;
  String? failedStage;
  try {
    await scenario.run();
  } on Object catch (error) {
    firstFailure = error;
    failedStage = scenario.stage;
  } finally {
    try {
      await driver.restoreState();
      scenario.facts['stateRestored'] = true;
    } on Object catch (error) {
      firstFailure ??= error;
      failedStage ??= 'restore';
    }
  }
  final proof = <String, Object?>{
    'schema': _killedCalleeProofSchema,
    'profileId': androidProductionKilledCalleeProfileId,
    'packageName': androidProductionKilledCalleeAppPackage,
    'topology': 'physical-caller-emulator-callee',
    'apkSha256': artifact.artifactDigest,
    'artifactInputDigest': artifact.inputDigest,
    'relayFixtureIdentitySha256': relay.fixtureIdentitySha256,
    ...scenario.facts,
  };
  if (firstFailure != null) {
    var failureProofSaved = false;
    try {
      directory.createSync(recursive: true);
      File('${directory.path}/${scenario.runId}-failure.json')
          .writeAsStringSync(
            jsonEncode({
              'firstFailedStage': failedStage,
              'failureKind': firstFailure.runtimeType.toString(),
              ...proof,
            }),
            flush: true,
          );
      failureProofSaved = true;
    } on FileSystemException {
      // Keep the original scenario failure when its evidence cannot be saved.
    }
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: failedStage == 'restore' ? 'restoration' : 'test',
      detail:
          'VC-059 stopped at $failedStage (${firstFailure.runtimeType}).'
          '${failureProofSaved ? '' : ' The failure proof could not be saved.'}',
      artifactPresent: true,
    );
  }
  if (!_validateKilledCalleeProof(proof).ok) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'harness',
      detail: 'VC-059 runtime proof is incomplete.',
      artifactPresent: true,
    );
  }
  final durable = writeSimsArtifactEvidenceSync(
    directory: directory,
    capabilityId: androidProductionKilledCalleeScenarioId,
    validatorIds: const [androidProductionKilledCalleeArtifactValidatorId],
    payload: {'runtimeProof': proof},
  );
  final audited = auditSimsArtifactEvidence(
    evidence: durable,
    expectedValidatorIds: const [
      androidProductionKilledCalleeArtifactValidatorId,
    ],
  );
  final artifactJson = jsonDecode(File(durable.path).readAsStringSync());
  if (!audited.isValid ||
      artifactJson is! Map<String, Object?> ||
      !validateAndroidProductionCallKilledCalleeArtifact(artifactJson).ok) {
    return AndroidProductionAudioCallCampaignResult.fail(
      blocker: 'harness',
      detail: 'VC-059 durable proof did not validate.',
      artifactPresent: true,
    );
  }
  return AndroidProductionAudioCallCampaignResult._(
    processExitCode: 0,
    json: {
      'status': 'PASS',
      'assertionsAttempted': _killedCalleeRequiredFacts.length,
      'artifactPresent': true,
      'printOnly': false,
      'exitCode': 0,
      'detail': 'VC-059 completed the ordered killed-callee replacement calls.',
      'artifactEvidence': durable.toJson(),
    },
  );
}

typedef _KilledCalleeCall = ({int callerPid, String marker, Stopwatch elapsed});

final class _ProductionKilledCalleeScenario {
  _ProductionKilledCalleeScenario(this.driver);

  final SystemAndroidProductionAudioCallCampaignDriver driver;
  final runId = _SecureTokens().next('vc059');
  final facts = <String, Object?>{};
  String stage = 'prepare';

  // The shared driver's two slots are roles. VC-059 binds the physical
  // Android to its caller slot and the emulator to its callee slot.
  String get caller => driver.emulatorDeviceId;
  String get callee => driver.physicalDeviceId;

  Future<void> run() async {
    await Future.wait(
      [caller, callee].map(
        (device) => driver.prepareTarget(
          deviceId: device,
          expectedApkSha256: driver.artifactSha256,
        ),
      ),
    );
    final identities = await Future.wait([
      driver.bootstrapIdentity(
        deviceId: caller,
        role: androidProductionAudioCallCallerRole,
      ),
      driver.bootstrapIdentity(
        deviceId: callee,
        role: androidProductionAudioCallCalleeRole,
      ),
    ]);
    for (final identity in identities) {
      _validateIdentity(identity);
    }
    await Future.wait([
      driver.awaitLiveSetupReady(
        deviceId: caller,
        role: androidProductionAudioCallCallerRole,
      ),
      driver.awaitLiveSetupReady(
        deviceId: callee,
        role: androidProductionAudioCallCalleeRole,
      ),
    ]);
    await driver.establishContact(
      ownerDeviceId: callee,
      ownerRole: androidProductionAudioCallCalleeRole,
      contact: identities.first,
    );
    await driver.establishContact(
      ownerDeviceId: caller,
      ownerRole: androidProductionAudioCallCallerRole,
      contact: identities.last,
    );
    await _waitForAction(caller, _killedCalleeCallerLabels);
    await _waitForAction(callee, _killedCalleeCallerLabels);

    stage = 'ready';
    final readyPid = await _appPid(callee);
    if (readyPid == null) throw StateError('Callee setup process is absent.');
    await waitForProductionObservation(
      'callee FCM publication',
      const Duration(seconds: 20),
      () async {
        return (await _flow(callee, readyPid)).any(
              (row) =>
                  row['event'] == 'CALL_ANDROID_TOKEN_PUBLISH_RESULT' &&
                  _details(row)?['outcome'] == 'published',
            )
            ? true
            : null;
      },
    );
    facts['calleeFcmPublished'] = true;
    if ((await _telecom(caller)).isNotEmpty ||
        (await _telecom(callee)).isNotEmpty) {
      throw StateError('A live fixture call existed before the first kill.');
    }

    stage = 'initial-kill';
    await _shell(callee, ['input', 'keyevent', 'KEYCODE_HOME']);
    await _killOwnedProcess();
    facts['initialOwnedProcessGone'] = true;

    stage = 'direct-cold-ringing';
    final direct = await _start('direct', mustBeCold: true);
    final directId = await _awaitRinging(direct, 'direct');
    facts['directCalleeTelecomRinging'] = true;
    final directPid = await _appPid(callee);
    if (directPid != null) {
      facts['directHeadlessAdmissionObserved'] =
          (await _flow(callee, directPid)).any(
            (row) =>
                row['event'] == 'CALL_HEADLESS_ADMISSION_RESULT' &&
                _details(row)?['mode'] == 'admission' &&
                _details(row)?['disposition'] == 'admitted',
          );
    }
    await _tap(
      caller,
      await _waitForAction(caller, const [_killedCalleeCancelLabel]),
    );
    await _awaitRelease();

    stage = 'kill-before-rapid-a';
    await _killOwnedProcess(allowAbsent: true);
    facts['beforeACalleeProcessAbsent'] = true;

    stage = 'cold-a-cancel';
    final a = await _start('a', mustBeCold: true);
    final cancelButton = await _waitForAction(caller, const [
      _killedCalleeCancelLabel,
    ], timeout: const Duration(seconds: 5));
    final delay = 3000 - a.elapsed.elapsedMilliseconds;
    if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
    final aCancelMarker = '$runId-a-cancel';
    await _markCallerLog(aCancelMarker);
    if (a.elapsed.elapsedMilliseconds > 6000) {
      throw TimeoutException('Caller missed the early cancel window.');
    }
    await _tap(caller, cancelButton);
    facts['aCancelElapsedMs'] = a.elapsed.elapsedMilliseconds;
    if ((facts['aCancelElapsedMs']! as int) > 6000) {
      throw TimeoutException('Caller cancel exceeded the early window.');
    }

    stage = 'replacement-b-ringing';
    // The next start only waits for the caller's action. It does not wait
    // for the callee to drain A or wait for another quiet interval.
    final b = await _start('b');
    final aRows = await _flow(
      caller,
      a.callerPid,
      window: a.marker,
      before: aCancelMarker,
    );
    if (!_inviteObserved(aRows)) {
      throw StateError('A was canceled before an outgoing invite existed.');
    }
    facts['aInvitedBeforeCancel'] = true;
    final bId = await _awaitRinging(b, 'b', excludedTelecomIds: {directId});
    facts['bCalleeTelecomRinging'] = true;

    stage = 'b-kill-while-ringing';
    await _killOwnedProcess(ringingId: bId);
    facts['bOwnedProcessGoneWhileRinging'] = true;
    final afterBKill = await _waitForAction(caller, const [
      _killedCalleeCancelLabel,
      ..._killedCalleeCallerLabels,
    ]);
    if (afterBKill.$1 == _killedCalleeCancelLabel) {
      await _tap(caller, afterBKill);
    }

    stage = 'replacement-c-ringing';
    final c = await _start('c');
    await _awaitRinging(c, 'c', excludedTelecomIds: {directId, bId});
    facts['cCalleeFreshTelecomRinging'] = true;
    final cPid = await _appPid(callee);
    if (facts['cPreDispatchProcessAbsent'] == true && cPid != null) {
      facts['cHeadlessAdmissionObserved'] = (await _flow(callee, cPid)).any(
        (row) =>
            row['event'] == 'CALL_HEADLESS_ADMISSION_RESULT' &&
            _details(row)?['mode'] == 'admission' &&
            _details(row)?['disposition'] == 'admitted',
      );
    }

    stage = 'cleanup-call';
    await _tap(
      caller,
      await _waitForAction(caller, const [_killedCalleeCancelLabel]),
    );
    await _awaitRelease();
  }

  Future<bool> _awaitRelease() => waitForProductionObservation(
    'owned call release',
    const Duration(seconds: 15),
    () async {
      return (await _telecom(caller)).isEmpty &&
              (await _telecom(callee)).isEmpty
          ? true
          : null;
    },
  );

  Future<_KilledCalleeCall> _start(
    String step, {
    bool mustBeCold = false,
  }) async {
    var (label, node) = await _waitForAction(caller, _killedCalleeCallerLabels);
    if (step == 'direct' && label != 'Voice call / Video call') {
      throw StateError('Direct cold call lacks the V2-eligible chooser.');
    }
    if (label == 'Voice call / Video call') {
      await _tap(caller, (label, node));
      (label, node) = await _waitForAction(caller, const [
        'Voice call',
      ], allowExactText: true);
      if (step == 'direct') facts['directV2EligibleVoiceChoice'] = true;
    }
    final callerPid = await _appPid(caller);
    if (callerPid == null) throw StateError('Caller app process is absent.');
    final marker = '$runId-$step';
    await _markCallerLog(marker);
    if (mustBeCold || step == 'c') {
      final absent = await _appPid(callee) == null;
      if (mustBeCold && !absent) {
        throw StateError('Callee restarted before cold dispatch.');
      }
      facts['${step}PreDispatchProcessAbsent'] = absent;
    }
    final elapsed = Stopwatch()..start();
    await _tap(caller, (label, node));
    return (callerPid: callerPid, marker: marker, elapsed: elapsed);
  }

  Future<String> _awaitRinging(
    _KilledCalleeCall call,
    String step, {
    Set<String> excludedTelecomIds = const {},
  }) => waitForProductionObservation(
    'call $step on both endpoints',
    const Duration(seconds: 25),
    () async {
      if (await _appPid(caller) != call.callerPid) {
        throw StateError('Caller app process changed during an invite.');
      }
      final rows = await _flow(caller, call.callerPid, window: call.marker);
      final observed = androidProductionKilledCalleeCallerState(rows);
      if (observed == 'terminal') {
        throw StateError(
          'The caller reached terminal state before ringing proof.',
        );
      }
      if (observed != 'ringing') return null;
      facts['${step}CallerRemoteRinging'] = true;
      final active = await _telecom(callee);
      return active.length == 1 &&
              active.values.single == 'RINGING' &&
              !excludedTelecomIds.contains(active.keys.single)
          ? active.keys.single
          : null;
    },
  );

  Future<(String, AndroidProductionAudioCallSemanticNode)> _waitForAction(
    String device,
    List<String> labels, {
    bool allowExactText = false,
    Duration timeout = const Duration(seconds: 9),
  }) => waitForProductionObservation(
    'exact fixture call action',
    timeout,
    () async {
      final String xml;
      try {
        xml = await driver._readUiDump(
          device,
          commandTimeout: _killedCalleeCommands,
        );
      } on _UiHierarchyUnavailable {
        return null;
      }
      final matches = [
        for (final label in labels)
          for (final node in _exactSemanticNodes(
            xml,
            label: label,
            requireClickable: true,
            allowExactText: allowExactText,
            allowedPackages: {androidProductionKilledCalleeAppPackage},
          ))
            (label, node),
      ];
      if (matches.length > 1) {
        throw StateError('Fixture call action is ambiguous.');
      }
      return matches.isEmpty ? null : matches.single;
    },
  );

  Future<void> _tap(
    String device,
    (String, AndroidProductionAudioCallSemanticNode) action,
  ) async {
    final (_, node) = action;
    await _shell(device, [
      'input',
      'tap',
      '${node.centerX}',
      '${node.centerY}',
    ]);
  }

  Future<void> _killOwnedProcess({
    String? ringingId,
    bool allowAbsent = false,
  }) async {
    final pid = await _appPid(callee);
    if (pid == null) {
      if (allowAbsent) return;
      throw StateError('Callee lacks a unique process to kill.');
    }
    const package = androidProductionKilledCalleeAppPackage;
    final uid = (await _shell(callee, ['run-as', package, 'id', '-u'])).trim();
    final cmdline = await _adb(callee, [
      'exec-out',
      'run-as',
      package,
      'cat',
      '/proc/$pid/cmdline',
    ]);
    final stat = await _adb(callee, [
      'exec-out',
      'run-as',
      package,
      'cat',
      '/proc/$pid/status',
    ]);
    final observedUid = RegExp(
      r'^Uid:\s+([0-9]+)\s',
      multiLine: true,
    ).firstMatch('${stat.stdout}')?.group(1);
    if (!RegExp(r'^[1-9][0-9]+$').hasMatch(uid) ||
        uid != observedUid ||
        '${cmdline.stdout}'.split('\u0000').first != package) {
      throw StateError('Callee PID ownership changed.');
    }
    if (ringingId != null) {
      final active = await _telecom(callee);
      if (active.length != 1 || active[ringingId] != 'RINGING') {
        throw StateError('The exact B call was no longer ringing before kill.');
      }
    }
    if (await _appPid(callee) != pid) {
      throw StateError('Callee PID changed before kill.');
    }
    await _shell(callee, ['run-as', package, 'kill', '-9', '$pid']);
    await waitForProductionObservation(
      'owned callee PID terminated',
      const Duration(seconds: 5),
      () async {
        final current = await _appPid(callee);
        if (current == pid) return null;
        if (ringingId != null) return true;
        if (current != null) {
          throw StateError(
            'Callee restarted before its process absence was observed.',
          );
        }
        return true;
      },
    );
  }

  Future<int?> _appPid(String device) async {
    final result = await _adb(device, [
      'shell',
      'pidof',
      androidProductionKilledCalleeAppPackage,
    ], allowFailure: true);
    final text = '${result.stdout}'.trim();
    if (result.exitCode == 1 && text.isEmpty) return null;
    if (result.exitCode != 0 || !RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(text)) {
      throw StateError('Fixture process lookup is ambiguous.');
    }
    return int.parse(text);
  }

  Future<Map<String, String>> _telecom(String device) async {
    final parsed = androidProductionKilledCalleeTelecomCalls(
      await _shell(device, ['dumpsys', 'telecom']),
    );
    if (parsed == null) {
      throw StateError('Current Telecom section is unavailable.');
    }
    return parsed;
  }

  Future<void> _markCallerLog(String marker) async {
    await _shell(caller, ['log', '-p', 'i', '-t', _killedCalleeLogTag, marker]);
  }

  Future<List<Map<String, Object?>>> _flow(
    String device,
    int pid, {
    String? window,
    String? before,
  }) async {
    final result = await _adb(device, [
      'logcat',
      '-d',
      '-t',
      '3000',
      '-v',
      'threadtime',
      'flutter:I',
      '$_killedCalleeLogTag:I',
      '*:S',
    ]);
    return androidProductionKilledCalleeFlowRows(
      '${result.stdout}',
      pid,
      window: window,
      before: before,
    );
  }

  Future<String> _shell(String device, List<String> command) async =>
      '${(await _adb(device, ['shell', ...command])).stdout}';

  Future<ProcessResult> _adb(
    String device,
    List<String> command, {
    bool allowFailure = false,
  }) {
    driver._requireExpectedDevice(device);
    return driver._runWithTimeout(
      'adb',
      ['-s', device, ...command],
      timeout: _killedCalleeCommands,
      allowFailure: allowFailure,
    );
  }
}

Map? _details(Map<String, Object?> row) =>
    row['details'] is Map ? row['details']! as Map : null;

bool _inviteObserved(List<Map<String, Object?>> rows) =>
    rows.any(_isInvitingTransition);

bool _isInvitingTransition(Map<String, Object?> row) =>
    row['event'] == 'CALL_STATE_TRANSITION' &&
    _details(row)?['trigger'] == 'outgoingInviteReady' &&
    _details(row)?['state'] == 'inviting';

/// The authenticated remote event must follow the current local invite and
/// remain live through the observation.
String androidProductionKilledCalleeCallerState(
  List<Map<String, Object?>> rows,
) {
  final invite = rows.indexWhere(_isInvitingTransition);
  if (invite < 0) return 'unobserved';
  var ringing = false;
  for (final row in rows.skip(invite + 1)) {
    if (row['event'] != 'CALL_STATE_TRANSITION') continue;
    if (_isInvitingTransition(row)) return 'terminal';
    final details = _details(row);
    if (const {'ending', 'ended'}.contains(details?['state'])) {
      return 'terminal';
    }
    if (details?['trigger'] == 'remoteRinging' &&
        details?['state'] == 'ringing') {
      ringing = true;
    }
  }
  return ringing ? 'ringing' : 'inviting';
}

/// Reads only the current Telecom call collection; event history and the
/// package's registered phone accounts are not live call proof.
Map<String, String>? androidProductionKilledCalleeTelecomCalls(String dump) {
  if (utf8.encode(dump).length > _maximumTelecomDumpBytes) return null;
  final lines = const LineSplitter().convert(dump);
  final section = RegExp(r'^([ \t]*)mCalls:[ \t]*$');
  final headings = [
    for (var index = 0; index < lines.length; index++)
      if (section.firstMatch(lines[index]) case final heading?)
        (index: index, indent: heading.group(1)!.length),
  ];
  if (headings.length != 1) return null;
  final heading = headings.single;
  final inline = RegExp(
    r'^\[Call id=([A-Za-z0-9@#._-]+), state=(?:STATE_)?([A-Z_]+), tpac=(.*?), cmgr=',
  );
  final accountOwner = RegExp(
    r'(?:^|[{\s(])' +
        RegExp.escape(androidProductionKilledCalleeAppPackage) +
        r'/',
  );
  final ids = <String>{};
  final owned = <String, String>{};
  for (var index = heading.index + 1; index < lines.length; index++) {
    final line = lines[index];
    final text = line.trimLeft();
    if (text.isEmpty) continue;
    if (line.length - text.length <= heading.indent) break;
    if (index - heading.index > _maximumTelecomCallBlockLines) return null;
    final match = inline.firstMatch(text);
    if (match == null || !ids.add(match.group(1)!)) return null;
    final state = match.group(2)!;
    if (accountOwner.hasMatch(match.group(3)!) &&
        !const {'DISCONNECTED', 'ABORTED'}.contains(state)) {
      owned[match.group(1)!] = state;
    }
  }
  return owned;
}

/// Projects one process and one marked log interval. No Android log lines
/// leave the driver or enter evidence files.
List<Map<String, Object?>> androidProductionKilledCalleeFlowRows(
  String logcat,
  int pid, {
  String? window,
  String? before,
}) {
  if (utf8.encode(logcat).length > _maximumSavedTextBytes) {
    throw const FormatException('Fixture logcat exceeded the capture bound.');
  }
  final lines = const LineSplitter().convert(logcat);
  final markerLine = RegExp(
    r'^[0-9-]+\s+\S+\s+[0-9]+\s+[0-9]+\s+I\s+MknoonVC059\s*:\s*(\S+)\s*$',
  );
  final flowLine = RegExp(
    r'^[0-9-]+\s+\S+\s+([0-9]+)\s+[0-9]+\s+I\s+flutter\s*:\s*\[FLOW\]\s*(\{.*\})\s*$',
  );
  final start = window == null
      ? -1
      : lines.lastIndexWhere(
          (line) => markerLine.firstMatch(line)?.group(1) == window,
        );
  if (window != null && start < 0) return const [];
  final end = before == null
      ? lines.length
      : lines.indexWhere(
          (line) => markerLine.firstMatch(line)?.group(1) == before,
          start + 1,
        );
  if (end < 0) return const [];
  return [
    for (var i = start + 1; i < end; i++)
      if (flowLine.firstMatch(lines[i]) case final line?
          when line.group(1) == '$pid')
        if (_projectKilledCalleeFlow(line.group(2)!) case final row?) row,
  ];
}

Map<String, Object?>? _projectKilledCalleeFlow(String json) {
  final Object? value;
  try {
    value = jsonDecode(json);
  } on FormatException {
    return null;
  }
  if (value is! Map || value['details'] is! Map) return null;
  final details = value['details']! as Map;
  final keys = switch (value['event']) {
    'CALL_STATE_TRANSITION' => const ['trigger', 'state'],
    'CALL_ANDROID_TOKEN_PUBLISH_RESULT' => const ['outcome'],
    'CALL_HEADLESS_ADMISSION_RESULT' => const ['mode', 'disposition'],
    _ => const <String>[],
  };
  if (keys.isEmpty) return null;
  return {
    'event': value['event'],
    'details': {for (final key in keys) key: details[key]},
  };
}
