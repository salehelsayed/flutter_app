part of 'android_production_audio_call_campaign.dart';

/// Keep only the observed message node and its safe semantic attributes.
/// The log redactor drops Android nodes containing even `password="false"`,
/// which destroys both their message and the hierarchy's XML structure.
String productionCallBackMessageEvidenceXml(
  String xml, {
  required String label,
  required String packageName,
}) {
  if (xml.length > _maximumUiDumpBytes ||
      _exactSemanticNodes(
            xml,
            label: label,
            requireClickable: false,
            allowedPackages: {packageName},
            allowExactText: true,
          ).length !=
          1) {
    throw const FormatException('Exact callback message node missing.');
  }
  final matches = XmlDocument.parse(xml)
      .findAllElements('node')
      .where(
        (node) =>
            node.getAttribute('package') == packageName &&
            node.getAttribute('enabled') == 'true' &&
            node.getAttribute('visible-to-user') != 'false' &&
            (node.getAttribute('text') == label ||
                node.getAttribute('content-desc') == label),
      )
      .toList();
  if (matches.length != 1) {
    throw const FormatException('Exact callback message node is ambiguous.');
  }
  final observed = matches.single;
  final attributes = <XmlAttribute>[
    for (final name in ['package', 'enabled', 'visible-to-user', 'bounds'])
      if (observed.getAttribute(name) case final String value)
        XmlAttribute(XmlName(name), value),
    for (final name in ['text', 'content-desc'])
      if (observed.getAttribute(name) case final String value
          when value == label)
        XmlAttribute(XmlName(name), value),
  ];
  final saved = XmlDocument([
    XmlElement(XmlName('hierarchy'), [], [
      XmlElement(XmlName('node'), attributes),
    ]),
  ]).toXmlString();
  if (_containsForbiddenDiagnosticResidue(saved)) {
    throw const FormatException('Callback message retained private material.');
  }
  return saved;
}

/// Reuses the production audio campaign's guarded install, authenticated pair,
/// native UI driver, media proof and restoration. Only the emulator receives
/// callback fixture data or permission/keyguard changes.
final class _ProductionCallBackRegression {
  _ProductionCallBackRegression(this.driver, this.id);

  final SystemAndroidProductionAudioCallCampaignDriver driver;
  final String id;
  late Directory output;
  late ProductionJourneyPeer peer;
  final invocations = <Map<String, Object?>>[];
  final phases = <Map<String, Object?>>[];
  final proof = <String, Object?>{};
  int? _user;
  bool? _lockDisabled;

  Future<void> preparePeer(String device) async {
    if (device != driver.emulatorDeviceId) return;
    await driver.proofDirectory.create(recursive: true);
    output = await driver.proofDirectory.createTemp('callback-$id-');
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: androidProductionAudioCallProfileId,
      scenarioId: id,
      role: 'alice',
      runId: driver._token('callback'),
      nonce: driver._token('callback-invocation'),
      values: const {},
    );
    peer = ProductionJourneyPeer(
      device,
      invocation,
      output,
      driver._runner,
      packageName: driver.packageName,
    );
    invocations.add(invocation.toJson());
    proof.addAll({
      'caseId': id,
      'attemptDirectory': output.path,
      'invocations': invocations,
      'phases': phases,
      'scope':
          'Actual notification action and admission; no physical acoustic claim',
    });
    await peer.writeAppFile(
      'production-journey/runtime-config.json',
      invocation.toJson(),
    );
  }

  Future<void> _save() => File(
    '${output.path}/callback-observations.json',
  ).writeAsString(jsonEncode(proof));

  Future<Map<String, Object?>> _snapshot(String label) async {
    final value = await peer.command('call_back.snapshot');
    phases.add({'label': label, 'snapshot': value});
    await _save();
    return value;
  }

  Future<void> onStage(
    AndroidProductionAudioCallStage stage,
    AndroidProductionAudioCallIdentity caller,
    AndroidProductionAudioCallIdentity callee,
  ) async {
    if (stage == AndroidProductionAudioCallStage.ready) {
      await peer.awaitReady();
      await _snapshot('ready');
    } else if (stage == AndroidProductionAudioCallStage.mediaReady) {
      await _snapshot('baseline-active');
      if (id == 'kx0008') proof['positiveCapture'] = await _captureState();
      if (id == 'kx0007') await _busy(callee);
    } else if (stage == AndroidProductionAudioCallStage.terminal &&
        id != 'kx0007') {
      if (id == 'kx0008') {
        await _microphoneDenied(callee);
      } else {
        await _superseded(callee);
      }
    }
  }

  Future<Map<String, Object?>> _seed(
    AndroidProductionAudioCallIdentity target,
  ) async {
    final value = await peer.command('call_back.seed', {
      'peerB': target.peerId,
    });
    proof['seed'] = value;
    await _save();
    return value;
  }

  Future<void> _nativeAction(String title) async {
    final allowed = await driver._allowedSemanticPackages(
      peer.device,
      'Answer',
    );
    await driver._adbShell(peer.device, [
      'cmd',
      'statusbar',
      'expand-notifications',
    ]);
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      String xml;
      try {
        xml = await driver._uiDump(peer.device);
      } on _UiHierarchyUnavailable {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        continue;
      }
      final target = findAndroidNotificationActionTapTarget(
        xml,
        title: title,
        body: 'Missed call',
        action: 'Call back',
        allowedPackages: allowed,
      );
      final expand =
          target?.expandCenter ??
          (target == null
              ? findAndroidCollapsedNotificationExpandCenter(xml, title: title)
              : null);
      if (expand != null) {
        await driver._adbShell(peer.device, [
          'input',
          'tap',
          '${expand.$1}',
          '${expand.$2}',
        ]);
      } else if (target?.actionCenter case final center?) {
        await driver._adbShell(peer.device, [
          'input',
          'tap',
          '${center.$1}',
          '${center.$2}',
        ]);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException(
      'The unique fixture notification action was unavailable.',
    );
  }

  Future<Map<String, Object?>> _completed(String expected) =>
      waitForProductionObservation(
        'actual callback result',
        const Duration(seconds: 45),
        () async {
          final value = await peer.command('call_back.snapshot');
          final events = value['events'] as List;
          return events.any(
                (event) =>
                    event is Map &&
                    event['stage'] == 'completed' &&
                    event['result'] == expected,
              )
              ? value
              : null;
        },
      );

  Future<Map<String, Object?>> _message(String label) =>
      waitForProductionObservation(
        'actual callback message',
        const Duration(seconds: 45),
        () async {
          String xml;
          try {
            xml = await driver._uiDump(peer.device);
          } on _UiHierarchyUnavailable {
            return null;
          }
          final nodes = _exactSemanticNodes(
            xml,
            label: label,
            requireClickable: false,
            allowedPackages: {driver.packageName},
            allowExactText: true,
          );
          if (nodes.length != 1) return null;
          final redacted = productionCallBackMessageEvidenceXml(
            xml,
            label: label,
            packageName: driver.packageName,
          );
          if (utf8.encode(redacted).length > _maximumSavedTextBytes) {
            throw StateError('Callback UI evidence capacity exceeded.');
          }
          final file = File('${output.path}/callback-message.xml');
          await file.writeAsString(redacted);
          return {
            'path': file.path,
            'sha256': sha256.convert(await file.readAsBytes()).toString(),
            'label': label,
            'packageName': driver.packageName,
          };
        },
      );

  Future<void> _busy(AndroidProductionAudioCallIdentity target) async {
    final seed = await _seed(target);
    await _nativeAction((seed['posted'] as Map)['title'] as String);
    final results = await Future.wait<Map<String, Object?>>([
      _completed('unavailable'),
      _message('Voice calling is unavailable.'),
    ]);
    proof['resultSnapshot'] = results.first;
    proof['messageReceipt'] = results.last;
    await _snapshot('after-busy');
    await _save();
  }

  Future<void> _freshInvocation() async {
    final next = peer.invocation.copyWith(
      nonce: driver._token('callback-invocation'),
    );
    for (final name in [
      'runtime-ack.json',
      'command.json',
      'command-result.json',
    ]) {
      await driver._deleteAppFile(peer.device, 'production-journey/$name');
    }
    peer = ProductionJourneyPeer(
      peer.device,
      next,
      output,
      driver._runner,
      packageName: driver.packageName,
    );
    invocations.add(next.toJson());
    await peer.writeAppFile(
      'production-journey/runtime-config.json',
      next.toJson(),
    );
  }

  Future<void> _killOwnedProcess() async {
    await driver._adbShell(peer.device, ['input', 'keyevent', 'KEYCODE_HOME']);
    final found = await peer.adb(['shell', 'pidof', peer.packageName]);
    final pid = '${found.stdout}'.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(pid)) {
      throw StateError('Ambiguous fixture process.');
    }
    final command = await peer.adb([
      'exec-out',
      'run-as',
      peer.packageName,
      'cat',
      '/proc/$pid/cmdline',
    ]);
    if ('${command.stdout}'.split('\u0000').first != peer.packageName) {
      throw StateError('Fixture process ownership changed.');
    }
    await peer.adb(['shell', 'run-as', peer.packageName, 'kill', '-9', pid]);
    await waitForProductionObservation(
      'owned process death',
      const Duration(seconds: 10),
      () async {
        final result = await peer.adb([
          'shell',
          'pidof',
          peer.packageName,
        ], allowFailure: true);
        return result.exitCode == 1 && '${result.stdout}'.trim().isEmpty
            ? true
            : null;
      },
    );
    proof['verifiedOwnedProcessDeath'] = true;
    await _save();
  }

  Future<void> _superseded(AndroidProductionAudioCallIdentity target) async {
    final seed = await _seed(target);
    await _killOwnedProcess();
    await _freshInvocation();
    await _nativeAction((seed['posted'] as Map)['title'] as String);
    await peer.awaitReady();
    await _snapshot('a-held');
    final posted = await peer.command('call_back.post_b');
    await _nativeAction(posted['title'] as String);
    await _snapshot('b-held');
    Object? primary;
    StackTrace? primaryStack;
    try {
      if (id == 'kx0006') {
        await _enableUnsecuredKeyguard();
        await driver._adbShell(peer.device, [
          'input',
          'keyevent',
          'KEYCODE_SLEEP',
        ]);
        await waitForProductionObservation(
          'actual locked keyguard',
          const Duration(seconds: 15),
          () async {
            final value = await peer.command('call_back.snapshot');
            return value['deviceUnlocked'] == false ? value : null;
          },
        );
      }
      await peer.command('call_back.release_readiness');
      if (id == 'kx0006') {
        await _snapshot('released-while-locked');
        // A second independent command allows the released wait to drain while
        // the native predicate is still false; it must retain B for resume.
        await _snapshot('still-locked');
        await driver._adbShell(peer.device, [
          'input',
          'keyevent',
          'KEYCODE_WAKEUP',
        ]);
        await driver._adbShell(peer.device, ['wm', 'dismiss-keyguard']);
        await driver._launch(peer.device);
      }
      proof['resultSnapshot'] = await _completed('started');
      await _snapshot('b-started');
      // The redialed B call is still inviting (nobody answers), so the outgoing
      // screen's Cancel owns the hang-up; the connected-call End is absent.
      await driver.tapSemantic(peer.device, 'Cancel call');
      await driver.waitForSemanticAbsent(peer.device, 'Cancel call');
    } catch (error, stack) {
      primary = error;
      primaryStack = stack;
      rethrow;
    } finally {
      try {
        await _restoreKeyguard();
      } catch (error, stack) {
        if (primary != null) {
          throw AndroidProductionAudioCallPrimaryFailure(
            primaryError: primary,
            primaryStackTrace: primaryStack!,
            restorationError: error,
            restorationStackTrace: stack,
          );
        }
        rethrow;
      }
    }
    await _save();
  }

  Future<void> _enableUnsecuredKeyguard() async {
    if (await driver.classifyTarget(peer.device) !=
        AndroidProductionAudioCallTargetKind.emulator) {
      throw const FormatException(
        'The unlock fixture requires its available Android emulator.',
      );
    }
    final user = await peer.adb(['shell', 'am', 'get-current-user']);
    final currentUser = int.parse('${user.stdout}'.trim());
    final disabled = await peer.adb([
      'shell',
      'locksettings',
      'get-disabled',
      '--user',
      '$currentUser',
    ]);
    final value = '${disabled.stdout}'.trim();
    if (value != 'true' && value != 'false') {
      throw StateError('Unreadable keyguard setting.');
    }
    final policy = await peer.adb(['shell', 'dumpsys', 'window', 'policy']);
    if (!productionCallbackKeyguardIsUnsecured(
      '${policy.stdout}',
      lockscreenDisabled: value == 'true',
    )) {
      throw const FormatException(
        'The emulator keyguard is secure or unreadable; no credentials are changed.',
      );
    }
    _user = currentUser;
    _lockDisabled = value == 'true';
    await peer.adb([
      'shell',
      'locksettings',
      'set-disabled',
      '--user',
      '$_user',
      'false',
    ]);
    proof['unsecuredEmulatorKeyguard'] = true;
    await _save();
  }

  Future<void> _restoreKeyguard() async {
    final disabled = _lockDisabled;
    if (disabled == null) return;
    await peer.adb(['shell', 'input', 'keyevent', 'KEYCODE_WAKEUP']);
    await peer.adb(['shell', 'wm', 'dismiss-keyguard']);
    await peer.adb([
      'shell',
      'locksettings',
      'set-disabled',
      '--user',
      '$_user',
      '$disabled',
    ]);
    final readback = await peer.adb([
      'shell',
      'locksettings',
      'get-disabled',
      '--user',
      '$_user',
    ]);
    if ('${readback.stdout}'.trim() != '$disabled') {
      throw StateError('Keyguard restoration failed.');
    }
    proof['keyguardRestored'] = true;
    _lockDisabled = null;
    await _save();
  }

  Future<Map<String, Object?>> _captureState() async {
    final owner = await peer.adb([
      'shell',
      'cmd',
      'package',
      'list',
      'packages',
      '-U',
      peer.packageName,
    ]);
    final rows = RegExp(
      r'^package:' + RegExp.escape(peer.packageName) + r' uid:(\d+)\s*$',
      multiLine: true,
    ).allMatches('${owner.stdout}').toList();
    if (rows.length != 1) throw StateError('Actual fixture UID unavailable.');
    final audio = await peer.adb(['shell', 'dumpsys', 'media.audio_policy']);
    return productionCallbackAudioCaptureSnapshot(
      '${audio.stdout}',
      uid: int.parse(rows.single.group(1)!),
    );
  }

  Future<void> _microphoneDenied(
    AndroidProductionAudioCallIdentity target,
  ) async {
    await _seed(target);
    await peer.adb([
      'shell',
      'pm',
      'revoke',
      peer.packageName,
      'android.permission.RECORD_AUDIO',
    ]);
    // Revocation may kill the process. A fresh invocation prevents an old
    // command acknowledgement from substituting for the restarted handler.
    final running = await peer.adb([
      'shell',
      'pidof',
      peer.packageName,
    ], allowFailure: true);
    if (running.exitCode == 0 && '${running.stdout}'.trim().isNotEmpty) {
      await _killOwnedProcess();
    }
    await _freshInvocation();
    await driver._launch(peer.device);
    await peer.awaitReady();
    // Re-post the owned card after the permission setup and restart.
    final reposted = await peer.command('call_back.post_b');
    proof['repostedAfterRevoke'] = reposted;
    await _nativeAction(reposted['title'] as String);
    final receipt = await ProductionJourneyFlowRunner(output, driver._runner)
        .run(
          peer.device,
          'production_call_microphone_denial',
          'microphone-denied',
          {},
          packageName: driver.packageName,
        );
    proof['denialFlowReceipt'] = receipt;
    // The Maestro flow asserts the actual message before it disappears. It is
    // the sole UI automation owner until that receipt has completed.
    proof['resultSnapshot'] = await _completed('microphoneDenied');
    proof['negativeCapture'] = await _captureState();
    await _snapshot('after-microphone-denial');
    await _save();
  }

  AndroidProductionAudioCallCampaignResult result(
    SimsArtifactEvidence baseline, {
    required bool emulatorPair,
  }) {
    proof.addAll({
      'baselineEvidence': baseline.toJson(),
      'emulatorPair': emulatorPair,
    });
    final failures = validateProductionCallBack(proof);
    File(
      '${output.path}/callback-oracle.json',
    ).writeAsStringSync(jsonEncode({'failures': failures}));
    if (failures.isNotEmpty) {
      return AndroidProductionAudioCallCampaignResult.fail(
        blocker: 'harness',
        detail: 'Callback evidence failed: ${failures.join('; ')}',
        artifactPresent: false,
      );
    }
    final evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: id,
      validatorIds: ['validateProductionCallBack'],
      payload: {...proof, 'status': 'PASS'},
    );
    return AndroidProductionAudioCallCampaignResult._(
      processExitCode: 0,
      json: {
        'status': 'PASS',
        'assertionsAttempted': 5,
        'artifactPresent': true,
        'printOnly': false,
        'exitCode': 0,
        'artifactEvidence': evidence.toJson(),
        'detail':
            'Actual callback action/result with authenticated production audio control and restoration',
      },
    );
  }
}
