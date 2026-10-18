part of 'android_production_audio_call_campaign.dart';

final class _ProductionCallSurfaceRegression {
  _ProductionCallSurfaceRegression(this.driver, this.id);
  final SystemAndroidProductionAudioCallCampaignDriver driver;
  final String id;
  late Directory output;
  Future<Directory>? _preparingOutput;
  late final String runId = driver._token('call-surface');
  final peers = <String, ProductionJourneyPeer>{};
  final observations = <String, Object?>{};
  final proof = <String, Object?>{};
  final uids = <String, int>{};
  final sdks = <String, int>{};
  final titles = <String, String>{};
  List<String>? _incomingCursor;
  late String otherPeer;
  bool routePickerOpen = false;

  String get actor => {'kx0001', 'kx0002', 'kx0029', 'kx0030'}.contains(id)
      ? 'caller'
      : 'callee';
  ProductionJourneyPeer get subject => peers[actor]!;
  ProductionJourneyPeer get other =>
      peers[actor == 'caller' ? 'callee' : 'caller']!;

  Future<Directory> _prepareOutput() async {
    await driver.proofDirectory.create(recursive: true);
    output = await driver.proofDirectory.createTemp('call-surface-$id-');
    proof.addAll({
      'caseId': id,
      'attemptDirectory': output.path,
      'runId': runId,
      'actor': actor,
      'observations': observations,
      'scope':
          'Actual current call and OS notification state; sampled heads-up state, no acoustic claim',
    });
    return output;
  }

  Future<void> preparePeer(String device) async {
    await (_preparingOutput ??= _prepareOutput());
    final role = device == driver.emulatorDeviceId ? 'caller' : 'callee';
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: androidProductionAudioCallProfileId,
      scenarioId: id,
      role: 'alice',
      runId: runId,
      nonce: driver._token('surface-invocation'),
      values: {'actor': role},
    );
    final peer = ProductionJourneyPeer(
      device,
      invocation,
      output,
      driver._runner,
      packageName: driver.packageName,
    );
    peers[role] = peer;
    await peer.writeAppFile(
      'production-journey/runtime-config.json',
      invocation.toJson(),
    );
  }

  Future<void> _save() =>
      File('${output.path}/observations.json').writeAsString(jsonEncode(proof));

  Future<Map<String, Object?>> _native() async {
    final device = subject.device;
    if (!uids.containsKey(actor)) {
      final raw = await driver._adbShell(device, [
        'cmd',
        'package',
        'list',
        'packages',
        '-U',
        driver.packageName,
      ]);
      final owners = RegExp(
        r'^package:' + RegExp.escape(driver.packageName) + r' uid:(\d+)\s*$',
        multiLine: true,
      ).allMatches(raw).toList();
      if (owners.length != 1) {
        throw StateError('Actual call package UID unavailable.');
      }
      uids[actor] = int.parse(owners.single.group(1)!);
      sdks[actor] = int.parse(
        (await driver._adbShell(device, [
          'getprop',
          'ro.build.version.sdk',
        ])).trim(),
      );
    }
    final dump = await driver._adbShell(device, [
      'dumpsys',
      'notification',
      '--noredact',
    ]);
    final cards = productionCallNotificationSnapshot(
      dump: dump,
      packageName: driver.packageName,
      uid: uids[actor]!,
      sdk: sdks[actor]!,
      peerId: otherPeer,
    );
    final ongoing = cards
        .where((c) => c['id'] == productionCallOngoingNotificationId)
        .toList();
    if (ongoing.length == 1) {
      final actual =
          extractActiveNotificationCards(dump, packageName: driver.packageName)
              .where(
                (card) =>
                    card.id == productionCallOngoingNotificationId &&
                    _sha256Text(card.title) == ongoing.single['titleSha256'],
              )
              .toList();
      if (actual.length != 1) {
        throw StateError('Native call content target is ambiguous.');
      }
      titles[actor] = actual.single.title;
    }
    return {'cards': cards};
  }

  Future<Map<String, Object?>> _take(String label, int expectedId) =>
      waitForProductionObservation(
        'current call and native card $label',
        const Duration(seconds: 45),
        () async {
          final values = await Future.wait<Map<String, Object?>>([
            subject.command('call.snapshot'),
            other.command('call.snapshot'),
            _native(),
          ]);
          final value = {
            'current': values[0],
            'otherCurrent': values[1],
            ...values[2],
          };
          observations[label] = value;
          await _save();
          final cards = values[2]['cards'] as List;
          return values[0]['inCall'] == true &&
                  cards.where((c) => c['id'] == expectedId).length == 1
              ? value
              : null;
        },
      );

  Future<Map<String, Object?>> _eventLog({
    List<String> cursor = const [],
  }) async {
    final dump = await driver._adbShell(subject.device, [
      'logcat',
      '-b',
      'events',
      '-d',
      '-v',
      'epoch',
      '-t',
      '2000',
      'notification_enqueue:I',
      'notification_canceled:I',
      '*:S',
    ]);
    return productionCallNotificationEvents(
      dump,
      packageName: driver.packageName,
      uid: uids[actor]!,
      afterCursor: cursor,
    );
  }

  Future<Map<String, Object?>> _headsUp() async {
    // Reuse OS diagnostics, without creating another UI automation session.
    for (final arguments in [
      <String>['dumpables'],
      <String>[],
    ]) {
      final dump = await driver._adbShell(subject.device, [
        'dumpsys',
        'activity',
        'service',
        'com.android.systemui/.SystemUIService',
        ...arguments,
      ]);
      if (RegExp(r'HeadsUpManager(?:Phone)? state:').hasMatch(dump)) {
        return productionCallHeadsUpSnapshot(
          dump,
          packageName: driver.packageName,
          uid: uids[actor]!,
        );
      }
    }
    throw const FormatException(
      'Actual SystemUI heads-up manager state is unavailable.',
    );
  }

  Future<bool> _ownedCallSurface() => waitForProductionObservation<bool>(
    'notification tap foregrounded the owned call surface',
    const Duration(seconds: 45),
    () async {
      String xml;
      try {
        xml = await driver._uiDump(subject.device);
      } on _UiHierarchyUnavailable {
        return null;
      }
      final visible = RegExp(r'<node\b[^>]*>').allMatches(xml).any((m) {
        final node = m.group(0)!;
        final label = _xmlDecode(_attribute(node, 'content-desc'));
        return _xmlDecode(_attribute(node, 'package')) == driver.packageName &&
            _attribute(node, 'enabled') == 'true' &&
            _attribute(node, 'visible-to-user') != 'false' &&
            (label == 'Call controls' || label.startsWith('Return to call, '));
      });
      if (!visible) return null;
      proof['notificationForegroundReceipt'] = {
        'ownedCallSurface': true,
        'sourceUiSha256': _sha256Text(xml),
      };
      await _save();
      return true;
    },
  );

  Future<void> _tapOngoing() async {
    final title = titles[actor];
    if (title == null) {
      throw StateError(
        'The owned ongoing card has no verified content target.',
      );
    }
    final packages = await driver._allowedSemanticPackages(
      subject.device,
      'Answer',
    );
    await driver._adbShell(subject.device, [
      'cmd',
      'statusbar',
      'expand-notifications',
    ]);
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(deadline)) {
      String xml;
      try {
        xml = await driver._uiDump(subject.device);
      } on _UiHierarchyUnavailable {
        continue;
      }
      final target = findAndroidNotificationCardTapTarget(
        xml,
        title: title,
        body: 'Call in progress',
        allowedPackages: packages,
        requireUnique: true,
      );
      final expand =
          target?.collapsedGroupExpandCenter ??
          (target == null
              ? findAndroidCollapsedNotificationExpandCenter(xml, title: title)
              : null);
      if (expand != null) {
        await driver._adbShell(subject.device, [
          'input',
          'tap',
          '${expand.$1}',
          '${expand.$2}',
        ]);
      } else if (target != null) {
        await driver._adbShell(subject.device, [
          'input',
          'tap',
          '${target.cardCenter.$1}',
          '${target.cardCenter.$2}',
        ]);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw TimeoutException(
      'The exact owned ongoing notification could not be tapped.',
    );
  }

  Future<void> _minimizeAndReturn() async {
    final flows = ProductionJourneyFlowRunner(output, driver._runner);
    proof['minimizeReceipt'] = await flows.run(
      subject.device,
      'production_call_minimize',
      'first-minimize',
      {},
      packageName: driver.packageName,
    );
    await _take('after-minimize', productionCallOngoingNotificationId);
    final hun = <Map<String, Object?>>[];
    proof['headsUpSamples'] = hun;
    hun.add(await _headsUp());
    await _save();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    hun.add(await _headsUp());
    await driver._adbShell(subject.device, [
      'input',
      'keyevent',
      'KEYCODE_HOME',
    ]);
    await _take('after-home', productionCallOngoingNotificationId);
    hun.add(await _headsUp());
    await _save();
    await _tapOngoing();
    // This check never launches or foregrounds an app on its own.
    await _ownedCallSurface();
    proof['returnReceipt'] = await flows.run(
      subject.device,
      'production_call_return',
      'return-exact-call',
      {},
      packageName: driver.packageName,
    );
    await _take('after-return', productionCallOngoingNotificationId);
  }

  Future<Map<String, Object?>> _outputsWhere(
    bool Function(Map<String, Object?>) accepts,
  ) => waitForProductionObservation<Map<String, Object?>>(
    'actual selected audio output',
    const Duration(seconds: 45),
    () async {
      final value = await subject.command('call.outputs');
      return accepts(value) ? value : null;
    },
  );

  Future<void> _routes() async {
    proof['scope'] =
        'Actual available coarse output kinds and selection; no endpoint names, acoustic or absent-hardware claim';
    routePickerOpen = true;
    try {
      await driver.tapSemantic(subject.device, 'Choose audio output');
      final observed = await waitForProductionObservation<Map<String, Object?>>(
        'picker rows equal actual available output inventory',
        const Duration(seconds: 45),
        () async {
          final before = await subject.command('call.outputs');
          String xml;
          try {
            xml = await driver._uiDump(subject.device);
          } on _UiHierarchyUnavailable {
            return null;
          }
          final rows = productionCallOutputPickerRows(
            xml,
            packageName: driver.packageName,
          );
          final after = await subject.command('call.outputs');
          final coarse = rows
              .map(
                (r) => {
                  for (final key in ['index', 'route', 'selected']) key: r[key],
                },
              )
              .toList();
          if (rows.isEmpty ||
              jsonEncode(before['outputs']) != jsonEncode(after['outputs']) ||
              jsonEncode(coarse) != jsonEncode(after['outputs'])) {
            return null;
          }
          return {
            'provider': after,
            'rows': coarse,
            'targets': rows,
            'sourceUiSha256': _sha256Text(xml),
          };
        },
      );
      final rows = List<Map<String, Object?>>.from(
        observed.remove('targets') as List,
      );
      proof['pickerInventory'] = observed;
      final speaker = rows.where((r) => r['route'] == 'speaker').toList();
      if (speaker.length != 1) {
        throw StateError('An exact observed speaker output is required.');
      }
      await driver._adbShell(subject.device, [
        'input',
        'tap',
        '${speaker.single['centerX']}',
        '${speaker.single['centerY']}',
      ]);
      proof['speakerSelected'] = await _outputsWhere(
        (value) => value['selectedRoute'] == 'speaker',
      );
      await _save();
    } finally {
      await driver.tapSemantic(subject.device, 'Close');
      await driver.waitForSemantic(subject.device, 'Call controls');
      final xml = await driver._uiDump(subject.device);
      if (xml.contains('call-output-choice-')) {
        throw StateError('The output picker did not close.');
      }
      routePickerOpen = false;
    }
    final supported =
        (proof['speakerSelected'] as Map)['supportedRoutes'] as List;
    final expected = [
      'systemDefault',
      'wiredHeadset',
      'bluetooth',
      'earpiece',
    ].where(supported.contains).firstOrNull;
    if (expected == null) {
      throw StateError('No observed non-speaker fallback is available.');
    }
    proof['expectedSpeakerRelease'] = expected;
    await driver.tapSemantic(subject.device, 'Speaker');
    proof['speakerReleased'] = await _outputsWhere(
      (value) => value['selectedRoute'] == expected,
    );
    proof['unavailableHardware'] = [
      for (final route in ['wiredHeadset', 'bluetooth'])
        if (!((proof['pickerInventory'] as Map)['rows'] as List).any(
          (r) => r['route'] == route,
        ))
          route,
    ];
    await _save();
  }

  Future<bool> _readPreference() async {
    final value = (await subject.command(
      'call.always_relay_preference',
    ))['alwaysRelay'];
    if (value is! bool) {
      throw StateError('Actual saved relay preference unreadable.');
    }
    return value;
  }

  Future<bool> _waitPreference(bool expected) =>
      waitForProductionObservation<bool>(
        'actual relay preference readback',
        const Duration(seconds: 30),
        () async {
          final value = await _readPreference();
          return value == expected ? value : null;
        },
      );

  Future<void> _privacy() async {
    proof['scope'] =
        'Saved audio-relay preference and truthful signaling-address copy only; forced-relay build, no network-route claim';
    await driver.waitForSemantic(subject.device, 'Start voice call');
    final flows = ProductionJourneyFlowRunner(output, driver._runner);
    final initial = await _readPreference();
    final privacy = <String, Object?>{'before': initial};
    proof['privacy'] = privacy;
    privacy['copyReceipt'] = await flows.run(
      subject.device,
      'production_call_privacy_open',
      'privacy-open',
      {},
      packageName: driver.packageName,
    );
    try {
      privacy['toggleReceipt'] = await flows.run(
        subject.device,
        'production_call_privacy_toggle',
        'privacy-toggle',
        {},
        packageName: driver.packageName,
      );
      privacy['afterToggle'] = await _waitPreference(!initial);
      await _save();
    } finally {
      if (await _readPreference() != initial) {
        privacy['restoreReceipt'] = await flows.run(
          subject.device,
          'production_call_privacy_toggle',
          'privacy-restore',
          {},
          packageName: driver.packageName,
        );
      }
      privacy['restored'] = await _waitPreference(initial);
      await _save();
    }
  }

  Future<void> onStage(
    AndroidProductionAudioCallStage stage,
    AndroidProductionAudioCallIdentity caller,
    AndroidProductionAudioCallIdentity callee,
  ) async {
    if (stage == AndroidProductionAudioCallStage.ready) {
      otherPeer = actor == 'caller' ? callee.peerId : caller.peerId;
      proof.addAll({
        'otherPeerSha256': _sha256Text(otherPeer),
        'invocations': peers.values.map((p) => p.invocation.toJson()).toList(),
      });
      await Future.wait(peers.values.map((p) => p.awaitReady()));
      if (!productionCallNotificationJourneys.contains(id)) {
        await _save();
        return;
      }
      if (id == 'kx0017') {
        proof['peerIdUsernameFixture'] = await subject.command(
          'call_name.peer_id_username',
          {'peerId': caller.peerId},
        );
      }
      final name = await subject.command('call.peer_name', {
        'peerId': otherPeer,
      });
      proof['contactName'] = name;
      proof['expectedNameSha256'] = id == 'kx0017'
          ? _sha256Text('MKnoon caller')
          : name['displayNameSha256'];
      await _save();
    } else if (stage == AndroidProductionAudioCallStage.incoming &&
        id == 'kx0001') {
      proof['scope'] =
          'Actual signed TTL and scheduled deadlines with their measured gap; no delayed/OS-offline admission proof';
      final evidence = await subject.command('call.wire_deadlines');
      proof['wireDeadlines'] = evidence;
      final wires = List<Map<String, Object?>>.from(
        evidence['encodedInvites'] as List,
      );
      final timers = List<Map<String, Object?>>.from(
        evidence['timers'] as List,
      );
      final expiry = timers.where((t) => t['kind'] == 'inviteExpiry').toList();
      if (wires.length != 1 || expiry.length != 1) {
        throw StateError(
          'Exact current signed invite and scheduled delivery deadline unavailable.',
        );
      }
      final gap =
          (expiry.single['deadlineMs'] as int) -
          (wires.single['wireExpiresAtMs'] as int);
      proof['wireDeliveryGapMs'] = gap;
      proof['wireOutlivesDeliveryDeadline'] = gap < 0;
      await _save();
    } else if (stage == AndroidProductionAudioCallStage.incoming &&
        productionCallNotificationJourneys.contains(id) &&
        id != 'kx0002') {
      await _take('incoming', productionCallIncomingNotificationId);
      if (id == 'kx0003') {
        final marker = await _eventLog();
        final events = marker['events'] as List;
        if (!events.any(
          (e) =>
              e['kind'] == 'posted' &&
              e['id'] == productionCallIncomingNotificationId,
        )) {
          throw const FormatException(
            'The actual incoming publication is missing from the OS event log.',
          );
        }
        _incomingCursor = List<String>.from(marker['cursor'] as List);
        proof['incomingEventMarker'] = marker;
        await _save();
      }
    } else if (stage == AndroidProductionAudioCallStage.connected) {
      if (id == 'kx0030') return;
      if (id == 'kx0001') {
        observations['connected'] = {
          'current': await subject.command('call.snapshot'),
          'otherCurrent': await other.command('call.snapshot'),
        };
        await _save();
        return;
      }
      if (id == 'kx0029') {
        observations['connected'] = {
          'current': await subject.command('call.snapshot'),
          'otherCurrent': await other.command('call.snapshot'),
        };
        await _routes();
        return;
      }
      await _take('connected', productionCallOngoingNotificationId);
      if (id == 'kx0003') {
        proof['handoverEvents'] = await _eventLog(cursor: _incomingCursor!);
        await _save();
      }
      if (id == 'kx0002' || id == 'kx0003') await _minimizeAndReturn();
    } else if (stage == AndroidProductionAudioCallStage.terminal &&
        id == 'kx0030') {
      await _privacy();
    }
  }

  AndroidProductionAudioCallCampaignResult result(
    SimsArtifactEvidence baseline, {
    required bool emulatorPair,
  }) {
    proof.addAll({
      'baselineEvidence': baseline.toJson(),
      'emulatorPair': emulatorPair,
    });
    final failures = validateProductionCallRegression(proof);
    File(
      '${output.path}/oracle.json',
    ).writeAsStringSync(jsonEncode({'failures': failures}));
    if (failures.isNotEmpty) {
      return AndroidProductionAudioCallCampaignResult.fail(
        blocker: 'harness',
        detail: 'Call regression evidence failed: ${failures.join('; ')}',
        artifactPresent: false,
      );
    }
    final evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: id,
      validatorIds: ['validateProductionCallRegression'],
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
            'Actual current call and native notification regression with authenticated audio control and restoration',
      },
    );
  }
}
