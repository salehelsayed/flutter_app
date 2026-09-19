import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/android_notification_payload_e2e_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_notification_payload_campaign.dart';

void main() {
  group('controlled token rotation startup barrier', () {
    AndroidFlowRecord attempt(String trigger) => AndroidFlowRecord(
      event: 'PUSH_REGISTER_COORDINATOR_ATTEMPT',
      details: <String, Object?>{'trigger': trigger},
    );
    AndroidFlowRecord success(String trigger) => AndroidFlowRecord(
      event: 'PUSH_REGISTER_COORDINATOR_SUCCESS',
      details: <String, Object?>{'trigger': trigger},
    );

    test('unfinished startup and queued resume never release rotation', () {
      final gate = AndroidNotificationRegistrationQuiescence();
      final records = <AndroidFlowRecord>[attempt('startup')];
      expect(gate.observe(records, elapsedMs: 0), isFalse);
      expect(gate.observe(records, elapsedMs: 9000), isFalse);
      records.addAll(<AndroidFlowRecord>[
        success('startup'),
        attempt('resume'),
      ]);
      expect(gate.observe(records, elapsedMs: 10000), isFalse);
      expect(gate.observe(records, elapsedMs: 15000), isFalse);
      records.add(success('resume'));
      expect(gate.observe(records, elapsedMs: 15001), isFalse);
      expect(gate.observe(records, elapsedMs: 15500), isFalse);
      expect(gate.observe(records, elapsedMs: 15501), isTrue);
    });

    test('a queued attempt resets the settled observation window', () {
      final gate = AndroidNotificationRegistrationQuiescence();
      final records = <AndroidFlowRecord>[
        attempt('startup'),
        success('startup'),
      ];
      expect(gate.observe(records, elapsedMs: 0), isFalse);
      records.add(attempt('resume'));
      expect(gate.observe(records, elapsedMs: 500), isFalse);
      records.add(success('resume'));
      expect(gate.observe(records, elapsedMs: 501), isFalse);
      expect(gate.observe(records, elapsedMs: 1000), isFalse);
      expect(gate.observe(records, elapsedMs: 1001), isTrue);
    });

    test('missing startup, unmatched success and failed outcomes refuse', () {
      for (final records in <List<AndroidFlowRecord>>[
        <AndroidFlowRecord>[attempt('resume'), success('resume')],
        <AndroidFlowRecord>[success('startup')],
        <AndroidFlowRecord>[
          attempt('startup'),
          success('startup'),
          success('resume'),
        ],
        <AndroidFlowRecord>[
          attempt('startup'),
          success('startup'),
          AndroidFlowRecord(
            event: 'PUSH_REGISTER_COORDINATOR_EXCEPTION',
            details: const <String, Object?>{'trigger': 'resume'},
          ),
        ],
        <AndroidFlowRecord>[
          attempt('startup'),
          success('startup'),
          AndroidFlowRecord(
            event: 'PUSH_REGISTER_COORDINATOR_UNKNOWN',
            details: const <String, Object?>{'trigger': 'resume'},
          ),
        ],
        <AndroidFlowRecord>[
          attempt('startup'),
          success('startup'),
          attempt('startup'),
          success('startup'),
        ],
      ]) {
        final gate = AndroidNotificationRegistrationQuiescence();
        expect(gate.observe(records, elapsedMs: 0), isFalse);
        expect(gate.observe(records, elapsedMs: 10000), isFalse);
      }
    });

    test('clock reversal cannot reuse an old settled interval', () {
      final gate = AndroidNotificationRegistrationQuiescence();
      final records = <AndroidFlowRecord>[
        attempt('startup'),
        success('startup'),
      ];
      expect(gate.observe(records, elapsedMs: 1000), isFalse);
      expect(gate.observe(records, elapsedMs: 1500), isTrue);
      expect(gate.observe(records, elapsedMs: 900), isFalse);
      expect(gate.observe(records, elapsedMs: 1399), isFalse);
      expect(gate.observe(records, elapsedMs: 1400), isTrue);
    });

    test(
      'a held observation cannot complete after the original startup bound',
      () {
        final gate = AndroidNotificationRegistrationQuiescence();
        final records = <AndroidFlowRecord>[
          attempt('startup'),
          success('startup'),
        ];
        expect(gate.observe(records, elapsedMs: 179500), isFalse);
        expect(gate.observe(records, elapsedMs: 180001), isFalse);
        expect(gate.observe(records, elapsedMs: 180501), isFalse);
      },
    );
  });

  group('scoped cold and B13 repetition', () {
    test(
      'diagnostic evidence uses the ordinary artifact validator before writing',
      () {
        final source = File(
          'integration_test/scripts/notification_android_payload_campaign.dart',
        ).readAsStringSync();
        final start = source.indexOf('record: (pair, leg, evidence) async {');
        final end = source.indexOf('diagnosticCaptures.add(', start);
        final record = source.substring(start, end);
        expect(record, contains('validateNotificationArtifact(evidence)'));
        expect(record, contains('if (!validation.ok)'));
        expect(
          record.indexOf('Scoped B13 artifact rejected:'),
          lessThan(record.indexOf('await file.writeAsString(')),
        );
      },
    );

    test(
      'three fresh cold-first pairs keep six separate evidence records',
      () async {
        final calls = <String>[];
        final evidence = <Map<String, Object?>>[];
        await runAndroidNotificationColdB13Probe(
          cleanup: () async => calls.add('cleanup'),
          cold: (pair) async {
            calls.add('cold$pair');
            return <String, Object?>{'pair': pair, 'leg': 'cold'};
          },
          dualPath: (pair) async {
            calls.add('b13$pair');
            return <String, Object?>{'pair': pair, 'leg': 'b13'};
          },
          record: (pair, leg, value) async {
            expect(value, <String, Object?>{'pair': pair, 'leg': leg});
            evidence.add(value);
            calls.add('record$pair$leg');
          },
        );
        expect(calls, <String>[
          for (var pair = 1; pair <= 3; pair++) ...<String>[
            'cleanup',
            'cold$pair',
            'record${pair}cold',
            'b13$pair',
            'record${pair}b13',
          ],
        ]);
        expect(evidence, hasLength(6));
        expect(
          evidence.map((value) => '${value['pair']}:${value['leg']}').toSet(),
          hasLength(6),
        );
      },
    );

    test('held cold proof cannot start the live B13 contender', () async {
      final held = Completer<Map<String, Object?>>();
      var dualCalls = 0;
      final running = runAndroidNotificationColdB13Probe(
        cleanup: () async {},
        cold: (pair) =>
            pair == 1 ? held.future : Future.value(<String, Object?>{}),
        dualPath: (_) async {
          dualCalls++;
          return <String, Object?>{};
        },
        record: (_, _, _) async {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(dualCalls, 0);
      held.complete(<String, Object?>{});
      await running;
      expect(dualCalls, 3);
    });

    test('a failed second B13 pair stops without a third input', () async {
      final calls = <String>[];
      final error = StateError('stable card failed');
      await expectLater(
        runAndroidNotificationColdB13Probe(
          cleanup: () async => calls.add('cleanup'),
          cold: (pair) async {
            calls.add('cold$pair');
            return <String, Object?>{};
          },
          dualPath: (pair) async {
            calls.add('b13$pair');
            if (pair == 2) throw error;
            return <String, Object?>{};
          },
          record: (pair, leg, _) async => calls.add('record$pair$leg'),
        ),
        throwsA(same(error)),
      );
      expect(calls, isNot(contains('cold3')));
      expect(calls, isNot(contains('record2b13')));
      expect(calls.where((value) => value == 'cleanup'), hasLength(2));
    });

    test(
      'failed cleanup or evidence storage never permits later input',
      () async {
        for (final failCleanup in <bool>[true, false]) {
          var coldCalls = 0;
          var dualCalls = 0;
          final error = StateError('retention or cleanup failed');
          await expectLater(
            runAndroidNotificationColdB13Probe(
              cleanup: () async {
                if (failCleanup) throw error;
              },
              cold: (_) async {
                coldCalls++;
                return <String, Object?>{};
              },
              dualPath: (_) async {
                dualCalls++;
                return <String, Object?>{};
              },
              record: (_, _, _) async => throw error,
            ),
            throwsA(same(error)),
          );
          expect(coldCalls, failCleanup ? 0 : 1);
          expect(dualCalls, 0);
        }
      },
    );
  });

  test('diagnostic mode retains ordinary defaults and common restoration', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final cli = File(
      'integration_test/scripts/run_notification_tap_device_real.dart',
    ).readAsStringSync();
    expect(source, contains('this.diagnosticB13Reconciliation = false'));
    expect(source, contains("'diagnosticIterationsCompleted': 3"));
    expect(source, contains("'status': 'DIAGNOSTIC_PASS'"));
    expect(source, contains("'wholeCampaignPass': false"));
    expect(source, contains("'b13-probe-pair-\$pair-\$leg.json'"));
    expect(source, contains('_coldWakeLogcatCursor = null;'));
    expect(source, contains('_coldWakeWindowScannedClean = false;'));
    final branch = source.indexOf('await runAndroidNotificationColdB13Probe(');
    final ordinary = source.indexOf(
      "_phase = 'tc_a6_replay_before_ack_custody';",
      branch,
    );
    final restoration = source.indexOf('appStateGuard.restoreAll', ordinary);
    final result = source.indexOf("'status': 'DIAGNOSTIC_PASS'", restoration);
    expect(branch, greaterThan(0));
    expect(ordinary, greaterThan(branch));
    expect(restoration, greaterThan(ordinary));
    expect(result, greaterThan(restoration));
    expect(cli, contains('diagnosticB13Reconciliation: diagnostic'));
    expect(cli, contains('The scoped B13 diagnostic requires --artifact-dir.'));
  });

  group('closed notification card diagnostics', () {
    const own = 'com.mknoon.sims.notifications';
    const body = 'private exact fixture body';
    String record({
      String package = own,
      String text = body,
      int id = 42,
      String channel = 'mknoon_messages',
    }) =>
        'NotificationRecord(0x1: pkg=$package user=UserHandle{0} '
        'id=$id tag=null key=0|$package|$id|null|10256: '
        'Notification(channel=$channel shortcut=null))\n'
        '  android.title=String (private sender)\n'
        '  android.text=String ($text)\n'
        '  payload=private-route';
    Map<String, Object?> snapshot(String dump) =>
        androidNotificationCardDiagnosticSnapshot(
          dump,
          packageName: own,
          body: body,
          oracleCardIds: const <int?>[42],
          oracleChannels: const <String>['mknoon_messages'],
        );

    test('same-key duplicate views and channel conflicts remain distinct', () {
      final same = snapshot('${record()}\n${record()}');
      final records = same['ownedMatchingRecords']! as List;
      expect(same['oracleCardCount'], 1);
      expect(same['ownedMatchingRecordCount'], 2);
      expect(records[0], records[1]);
      final changed = snapshot(
        '${record()}\n${record(channel: 'mknoon_messages_silent')}',
      );
      final tuples = changed['ownedMatchingRecords']! as List;
      expect(tuples[0]['nativeKeySha256'], tuples[1]['nativeKeySha256']);
      expect(tuples[0]['channelSha256'], isNot(tuples[1]['channelSha256']));
      expect(tuples[1]['channelKind'], 'silent');
    });

    test('exact package and body ownership excludes adjacent records', () {
      final result = snapshot(
        '${record(package: '$own.visibilityproof')}\n'
        '${record(text: '$body other')}\n${record()}',
      );
      expect(result['ownedMatchingRecordCount'], 1);
      final serialized = jsonEncode(result);
      for (final privateValue in <String>[
        own,
        body,
        'private sender',
        'private-route',
        '10256',
      ]) {
        expect(serialized, isNot(contains(privateValue)));
      }
    });

    test(
      'missing cards and changed native IDs are observable without copy',
      () {
        final absent = snapshot(
          'Current Notification Manager state:\nRanking Config:',
        );
        expect(absent['ownedMatchingRecordCount'], 0);
        expect(absent['managerHeaderPresent'], isTrue);
        expect(absent['rankingSectionPresent'], isTrue);
        final a = snapshot(record());
        final b = snapshot(record(id: 43));
        expect(
          (a['ownedMatchingRecords']! as List).single['idSha256'],
          isNot((b['ownedMatchingRecords']! as List).single['idSha256']),
        );
      },
    );

    test('internal errors and unknown channels have closed projections', () {
      final result = snapshot(
        '${record(channel: 'private-unknown-channel')}\nDUMP TIMEOUT',
      );
      expect(result['internalDumpError'], isTrue);
      expect(result['managerHeaderPresent'], isFalse);
      expect(result['rankingSectionPresent'], isFalse);
      expect(
        (result['ownedMatchingRecords']! as List).single['channelKind'],
        'other',
      );
      expect(jsonEncode(result), isNot(contains('private-unknown-channel')));
    });

    test('record and oracle arrays are bounded without hiding truncation', () {
      final result = androidNotificationCardDiagnosticSnapshot(
        List.generate(40, (i) => record(id: i)).join('\n'),
        packageName: own,
        body: body,
        oracleCardIds: List<int>.generate(40, (i) => i),
        oracleChannels: List<String>.filled(40, 'mknoon_messages'),
      );
      expect(result['ownedMatchingRecordCount'], 40);
      expect(result['ownedMatchingRecords'], hasLength(16));
      expect(result['ownedMatchingRecordsTruncated'], isTrue);
      expect(result['oracleTuplesTruncated'], isTrue);
      expect(result['oracleCardIdSha256'], hasLength(16));
      expect(result['oracleChannelSha256'], hasLength(16));
      expect(jsonEncode(result).length, lessThan(12000));
    });
  });

  test('card instability retains both already-read samples before failing', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      '_waitForNotificationObservation(String marker)',
    );
    final end = source.indexOf(
      'Future<void> _requireNoAppNotification()',
      start,
    );
    final gate = source.substring(start, end);
    expect(gate, contains('firstDump = dump;'));
    expect(gate, contains('_writeNotificationCardStabilityFailure('));
    expect(gate, contains('firstDump: firstDump'));
    expect(gate, contains('failedDump: dump'));
    expect(gate, contains('const Duration(seconds: 4)'));
    expect(gate, contains('matching.length != 1'));
    expect(gate, contains('matching.single.id != firstObservation.card.id'));
    expect(
      gate,
      contains('channels.single != firstObservation.channels.single'),
    );
    expect(
      RegExp(r'await _notificationDump\(\)').allMatches(gate),
      hasLength(2),
    );
    final writer = gate.substring(
      gate.indexOf('_writeNotificationCardStabilityFailure({'),
    );
    expect(writer, isNot(contains('_adb(')));
    expect(writer, isNot(contains('_notificationDump(')));
    expect(
      gate.indexOf('_writeNotificationCardStabilityFailure('),
      lessThan(gate.indexOf("'Run-bound notification did not preserve")),
    );
  });

  test('isolated package launch uses the fully qualified native activity', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _launch(String device) async {');
    final end = source.indexOf('Future<_Identity> _identity(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final launch = source.substring(start, end);

    // applicationId selects the installed package; the native activity class
    // stays in com.mknoon.app for disposable builds with a different ID.
    expect(launch, contains(r"'$packageName/com.mknoon.app.MainActivity'"));
    expect(launch, isNot(contains(r"'$packageName/.MainActivity'")));
  });

  test('channel-disabled leg keeps the silent channel OPEN so a leak shows', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runChannelDisabledLeg()',
    );
    final end = source.indexOf('Future<int?> _channelImportance', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // Only the AUDIBLE channel is blocked. The app picks between its two
    // message channels from tone state and has no channel read-back, so
    // leaving `mknoon_messages_silent` open is what keeps the leak route
    // observable — device-measured 2026-08-18, a card survived there while
    // `mknoon_messages` was IMPORTANCE_NONE. Blocking BOTH channels would make
    // the zero-card census pass without the app changing anything, masking
    // exactly the defect this leg is here to catch.
    expect(
      leg,
      contains('_setChannelEnabled(_audibleNotificationChannelId, false)'),
    );
    expect(
      leg,
      isNot(
        contains('_setChannelEnabled(_silentNotificationChannelId, false)'),
      ),
    );
    expect(leg, contains('blockedSilentImportance != 2'));
  });

  test(
    'both channel sends require provider delivery before live ACK custody',
    () {
      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      final start = source.indexOf(
        'Future<Map<String, Object?>> _runChannelDisabledLeg()',
      );
      final end = source.indexOf('Future<int?> _channelImportance', start);
      final leg = source.substring(start, end);

      // Actual notification04 stored the blocked message through the live path
      // before the relay recorded custody-only history, so waiting for a push
      // afterward did not exercise the OS channel. Both sends need the same
      // real provider/staged-frame barrier; the control cannot race it either.
      expect(
        RegExp(r'_sendSpacedProviderMarker\(').allMatches(leg),
        hasLength(2),
      );
      expect(leg, isNot(contains('_sendSpacedMarker(')));
      for (final gate in <String>[
        '_requirePostAttempt(',
        '_waitForStagedEnvelope(',
        '_requireNoCardForMarker(',
        '_requireReceiverAlive(',
        '_restartAndDrain(',
        "drain['messageCount'] != 1",
        "drain['pendingRelayEntries'] != 0",
        'restoredImportance != 4',
        'restoredSilentImportance != 2',
        '_requireAudibleChannel(',
      ]) {
        expect(leg, contains(gate), reason: gate);
      }
    },
  );

  test('channel provider barrier keeps spacing and exact background PID', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('_sendSpacedProviderMarker(String marker,');
    final end = source.indexOf('/// Proves the wake ARRIVED', start);
    final send = source.substring(start, end);
    final tone = send.indexOf('await _awaitToneWindow()');
    final cursor = send.indexOf('await _deviceLogcatCursor()');
    final pid = send.indexOf('await _pidof(emulator)');
    final background = send.indexOf(
      'await _requireB13ReceiverBackground(receiverPid)',
    );
    final barrier = send.indexOf('await _sendB13ProviderBeforeLive(');
    expect(tone, greaterThanOrEqualTo(0));
    expect(cursor, greaterThan(tone));
    expect(pid, greaterThan(cursor));
    expect(background, greaterThan(pid));
    expect(barrier, greaterThan(background));
    expect(send, contains('receiverPid: receiverPid'));
    expect(send, contains('initialCursor: cursor'));
    expect(send, contains('sentAt: sentAt'));
    expect(send, isNot(contains('_sendText(')));
    expect(send, isNot(contains('_waitForProviderSend(')));
  });

  test('B13 proves the alert from the log and the settled primary card', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runB13DualPathLeg()',
    );
    final end = source.indexOf('_toneWindowSpacing = ', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // The log proves that the winning publication alerted. A later dump has a
    // different job: it proves the losing-path reconcile preserved the active
    // primary-channel card instead of demoting it.
    expect(
      leg,
      contains(
        'androidNotificationFirstPostAttemptSilent(\n        await _logcatSince(logcatCursor),\n      )',
      ),
    );
    expect(leg, contains('alertSilent != false'));
    expect(leg, contains('channels.single != _audibleNotificationChannelId'));
    expect(leg, isNot(contains('_requireAudibleChannel(')));

    final readiness = leg.indexOf(
      'action: androidNotificationTransportReadyAction',
    );
    final background = leg.indexOf("'KEYCODE_HOME'");
    final cursor = leg.indexOf(
      'final logcatCursor = await _deviceLogcatCursor',
    );
    final toneGap = leg.indexOf('final toneGap = await _awaitToneWindow()');
    expect(readiness, greaterThanOrEqualTo(0));
    expect(background, greaterThan(readiness));
    expect(toneGap, greaterThan(background));
    expect(cursor, greaterThan(toneGap));
    expect(leg, contains('messageId: sent.messageId'));
    expect(leg, contains('_sendB13ProviderBeforeLive('));
    expect(leg, isNot(contains('await _sendText(')));
    expect(leg, contains('androidNotificationReleasedLivePathObserved('));
  });

  test('log windows come from a live stream, never a post-hoc dump', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();

    // The emulator's main ring is 2 MiB and a busy campaign minute emits
    // ~1.6 MB, so an event read 60-120s after it was logged can have rotated
    // out — and an aged-out window is EMPTY, which reads as "the app never
    // emitted it". The reader must therefore be live and started up front.
    expect(source, contains('_startDeviceLogStream()'));
    expect(source, contains('logcat -T 1 -v brief'));
    expect(source, contains('_stopDeviceLogStream'));
    // Cursors are byte offsets into that stream, and the window is a file
    // slice — no adb round trip, nothing that can rotate.
    expect(source, contains('handle.setPosition(start)'));
    // `adb` owns the write. Piping stdout into `file.openWrite()` races the
    // cursor reads: `IOSink.flush()` sets `_isBound`, so a flush concurrent
    // with the stdout listener throws `StreamSink is bound to a stream` — it
    // killed a real run at assertion 1.
    final streamStart = source.indexOf(
      'Future<void> _startDeviceLogStream() async {',
    );
    final streamEnd = source.indexOf(
      'Future<void> _stopDeviceLogStream()',
      streamStart,
    );
    expect(streamStart, greaterThanOrEqualTo(0));
    expect(streamEnd, greaterThan(streamStart));
    final starter = source.substring(streamStart, streamEnd);
    expect(starter, isNot(contains('openWrite()')));
    expect(starter, isNot(contains('.listen(')));
    expect(source, isNot(contains("'-d',")));
    // Clearing the shared device log is banned by the adapter contract.
    expect(source, isNot(contains("'logcat', '-c'")));
    expect(source, isNot(contains("'-c',\n      '-t',")));
  });

  test('unexpected campaign failures retain bounded causal diagnostics', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('final campaign = _AndroidNotificationCampaign(options);'),
    );
    expect(source, contains(r'${error.runtimeType} during ${campaign.phase}'));
    expect(source, contains(r'${_firstStackFrame(stackTrace)}.'));
    expect(
      source,
      contains('assertionsAttempted: campaign.assertionsAttempted'),
    );
    expect(source, contains('const maximumLength = 240;'));
    expect(source, isNot(contains(r'${error.toString()}')));
  });

  test(
    'notification taps bind the exact card and recover grouped shade UI',
    () {
      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<void> _tapNotification(ActiveNotificationCard card)',
      );
      final methodEnd = source.indexOf(
        'Future<void> _waitForUiText(',
        methodStart,
      );

      expect(methodStart, isNonNegative);
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);
      expect(method, contains('findAndroidNotificationCardTapTarget('));
      expect(method, contains('title: card.title'));
      expect(method, contains('body: card.body'));
      expect(method, contains('target.collapsedGroupExpandCenter'));
      expect(method, contains('target.cardCenter'));
      expect(method, contains('findAndroidCollapsedNotificationExpandCenter('));
      expect(method, contains('title: card.title'));
      expect(method, contains('collapsedExpand'));
      expect(method, contains('findAndroidAnrWaitCenter(xml)'));
      expect(method, contains('anrWait'));
      expect(
        method.indexOf('target.collapsedGroupExpandCenter'),
        lessThan(method.indexOf('target.cardCenter')),
      );
      expect(
        method.indexOf('findAndroidCollapsedNotificationExpandCenter('),
        greaterThan(method.indexOf('target.cardCenter')),
      );
      expect(method, contains('package="com.android.systemui"'));
      expect(method, contains('attemptDumps.add(xml)'));
      expect(method, contains('_writeNotificationTapFailureDiagnostics('));
      expect(method, contains('diagnostic.path'));
      expect(
        RegExp(r"'expand-notifications'").allMatches(method).length,
        greaterThanOrEqualTo(2),
        reason: 'a lost shade must be reopened before any retry scroll',
      );

      expect(source, contains('_tapNotification(warmObservation.card)'));
      expect(source, contains('_tapNotification(coldObservation.card)'));
      expect(source, contains('_tapNotification(matching.single)'));
    },
  );

  test('permission-denied leg separates an OS precondition from a defect', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runPermissionDeniedLeg()',
    );
    final end = source.indexOf(
      'Future<Map<String, Object?>> _runTokenRefreshLeg()',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final leg = source.substring(start, end);

    // A re-granted permission means the app was never asked the question, so
    // it is BLOCKED (environment), never a product failure.
    expect(leg, contains("'deviceOsState'"));
    final blockedAt = leg.indexOf("'deviceOsState'");
    final assertedAt = leg.indexOf('_awaitFlowRecords(');
    expect(blockedAt, greaterThanOrEqualTo(0));
    expect(assertedAt, greaterThan(blockedAt));
    // ...and the typed record is awaited right after the relaunch, not after
    // the send/census minutes later.
    expect(leg.indexOf('_sendSpacedMarker('), greaterThan(assertedAt));
  });

  test('pm path package census accepts API 37 silent absence', () {
    expect(
      androidPackagePresentFromPmPath(exitCode: 1, stdout: '', stderr: ''),
      isFalse,
    );
    expect(
      androidPackagePresentFromPmPath(
        exitCode: 1,
        stdout: '',
        stderr: 'Unknown package: com.mknoon.app',
      ),
      isFalse,
    );
    expect(
      androidPackagePresentFromPmPath(
        exitCode: 0,
        stdout: 'package:/data/app/com.mknoon.app/base.apk\n',
        stderr: '',
      ),
      isTrue,
    );
    expect(
      () => androidPackagePresentFromPmPath(
        exitCode: 23,
        stdout: '',
        stderr: 'error: transport failure',
      ),
      throwsFormatException,
    );
  });

  test(
    'G24 app-op divergence is probe-derived and restores both baselines',
    () {
      expect(
        parseAndroidNotificationAppOpMode(
          'POST_NOTIFICATION: allow; time=+4m12s ago',
        ),
        'allow',
      );
      expect(
        parseAndroidNotificationAppOpMode(
          'Uid mode: POST_NOTIFICATION: ignore\nPOST_NOTIFICATION: ignore',
        ),
        'ignore',
      );
      expect(
        parseAndroidNotificationUidAppOpMode(
          'Uid mode: POST_NOTIFICATION: ignore\nPOST_NOTIFICATION: allow',
        ),
        'ignore',
      );
      expect(
        parseAndroidNotificationUidAppOpMode(
          'POST_NOTIFICATION: allow; time=+4m12s ago',
        ),
        'default',
      );
      expect(androidNotificationUidAppOpShellMode('default'), 'allow');
      expect(androidNotificationUidAppOpShellMode('ignore'), 'ignore');
      expect(
        () => androidNotificationUidAppOpShellMode('future-mode'),
        throwsFormatException,
      );
      expect(
        androidNotificationUidAppOpMutationBlocked(
          'Blocked setUidMode call for runtime permission app op: '
          'uid = 10252, code = POST_NOTIFICATION, mode = ignore',
        ),
        isTrue,
      );
      expect(
        androidNotificationUidAppOpMutationBlocked(
          'setUidMode accepted: code = POST_NOTIFICATION, mode = ignore',
        ),
        isFalse,
      );
      expect(
        () => parseAndroidNotificationAppOpMode(
          'POST_NOTIFICATION: mode-from-a-future-android',
        ),
        throwsFormatException,
      );

      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      expect(source, contains('androidPackagePresentFromPmPath('));
      final runStart = source.indexOf(
        'Future<AndroidNotificationCampaignResult> run() async',
      );
      final runEnd = source.indexOf('Future<void> _preflight()', runStart);
      expect(runStart, greaterThanOrEqualTo(0));
      expect(runEnd, greaterThan(runStart));
      final run = source.substring(runStart, runEnd);
      expect(run, contains('on _G24NotApplicable catch (error)'));
      expect(
        run,
        contains('permissionAppOpDivergenceNotApplicableReason = error.reason'),
      );
      expect(run, contains("'notApplicableScenarioIds'"));
      expect(run, contains("'notApplicableReasons'"));

      final guardCapture = run.indexOf('AndroidAppStateGuard.capture(');
      final entryCapture = run.indexOf(
        '_captureCampaignEntryNotificationAppOp()',
        guardCapture,
      );
      final firstInstall = run.indexOf('prepareFreshInstall(', entryCapture);
      final outerRestore = run.indexOf(
        'appStateGuard.restoreAll',
        firstInstall,
      );
      final entryRestore = run.indexOf(
        '_restoreCampaignEntryNotificationAppOp',
        outerRestore,
      );
      expect(guardCapture, greaterThanOrEqualTo(0));
      expect(entryCapture, greaterThan(guardCapture));
      expect(firstInstall, greaterThan(entryCapture));
      expect(outerRestore, greaterThan(firstInstall));
      expect(entryRestore, greaterThan(outerRestore));

      final legStart = source.indexOf(
        'Future<Map<String, Object?>> _runPermissionAppOpDivergenceLeg()',
      );
      final legEnd = source.indexOf(
        'Future<Map<String, Object?>> _runTokenRefreshLeg()',
        legStart,
      );
      expect(legStart, greaterThanOrEqualTo(0));
      expect(legEnd, greaterThan(legStart));
      final leg = source.substring(legStart, legEnd);
      expect(leg, contains('_notificationPermissionGranted()'));
      expect(leg, contains("_readNotificationAppOpMode()"));
      expect(leg, contains("_setNotificationAppOpMode('ignore')"));
      expect(leg, contains('_G24NotApplicable('));
      expect(leg, isNot(contains("'pm',\n      'revoke'")));

      final appOpReadStart = source.indexOf(
        'Future<String> _readNotificationAppOpMode()',
      );
      final appOpSetStart = source.indexOf(
        'Future<void> _setNotificationAppOpMode',
        appOpReadStart,
      );
      final appOpRestoreStart = source.indexOf(
        'Future<void> _restoreLegLocalNotificationAppOp()',
        appOpSetStart,
      );
      expect(appOpReadStart, greaterThanOrEqualTo(0));
      expect(appOpSetStart, greaterThan(appOpReadStart));
      expect(appOpRestoreStart, greaterThan(appOpSetStart));
      final appOpRead = source.substring(appOpReadStart, appOpSetStart);
      final appOpSet = source.substring(appOpSetStart, appOpRestoreStart);
      expect(appOpRead, contains("'get',\n      '--uid',"));
      expect(appOpRead, contains('parseAndroidNotificationUidAppOpMode'));
      expect(appOpSet, contains("'set',\n      '--uid',"));

      final mutationFlag = leg.indexOf('_g24AppOpMutated = true;');
      final mutation = leg.indexOf("_setNotificationAppOpMode('ignore')");
      final duringRead = leg.indexOf('_readNotificationAppOpMode()', mutation);
      final cursor = leg.indexOf('_deviceLogcatCursor()', duringRead);
      final relaunch = leg.indexOf('_launch(emulator)', cursor);
      final boundedRead = leg.indexOf('_flowRecordsSince(', relaunch);
      final localRestore = leg.indexOf(
        '_restoreLegLocalNotificationAppOp()',
        boundedRead,
      );
      final recovery = leg.indexOf(
        '_sendSpacedMarker(controlMarker',
        localRestore,
      );
      expect(mutationFlag, greaterThanOrEqualTo(0));
      expect(mutation, greaterThan(mutationFlag));
      expect(duringRead, greaterThan(mutation));
      expect(cursor, greaterThan(duringRead));
      expect(relaunch, greaterThan(cursor));
      expect(boundedRead, greaterThan(relaunch));
      expect(localRestore, greaterThan(boundedRead));
      expect(recovery, greaterThan(localRestore));

      for (final event in <String>[
        'PUSH_PERMISSION_OS_STATE_OVERRIDE',
        'PUSH_PERMISSION_REQUEST_RESULT',
        'PUSH_PERMISSION_OS_CHECK_FAILED',
        'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED',
      ]) {
        expect(leg, contains(event));
      }
      for (final field in <String>[
        'runtimePermissionGrantedBeforeOverride',
        'appOpModeAtCampaignEntry',
        'appOpModeBeforeOverride',
        'appOpModeDuringOverride',
        'appOpModeAfterRecovery',
        'appOpModeAfterCampaignRestore',
        'permissionOverrideRequestStatus',
        'permissionOverrideOsEnabled',
        'permissionResultStatus',
        'permissionResultGranted',
        'permissionResultOsEnabled',
        'permissionOsCheckFailedCount',
        'permissionDeniedHealthEvent',
        'disabledCardCount',
        'disabledMessageCount',
        'recoveryAlertChannel',
      ]) {
        expect(source, contains("'$field'"));
      }
    },
  );

  test('cold notification leg explicitly kills the headless FCM process', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf(
      'Future<Map<String, Object?>> _runColdPayloadLeg()',
    );
    final end = source.indexOf(
      'Future<Map<String, Object?>> _restartAndDrain',
      start,
    );
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final coldLeg = source.substring(start, end);

    expect(
      RegExp(
        r'await _waitForNotification\(marker\);\s*'
        r'await _terminateReceiver\(\);\s*'
        r'await _setNetworkAvailable\(false\);',
      ).hasMatch(coldLeg),
      isTrue,
    );
    expect(
      coldLeg,
      isNot(contains('headless FCM process exit before cold tap')),
    );
  });

  test(
    'receiver termination uses bounded stop-app fallback without force-stop',
    () {
      final source = File(
        'integration_test/scripts/notification_android_payload_campaign.dart',
      ).readAsStringSync();
      final start = source.indexOf('Future<void> _terminateReceiver()');
      final end = source.indexOf(
        'Future<bool> _receiverProcessAbsentWithin',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final method = source.substring(start, end);

      final home = method.indexOf("'KEYCODE_HOME'");
      final settle = method.indexOf('Duration(milliseconds: 750)', home);
      final kill = method.indexOf("'kill'", settle);
      final boundedProbe = method.indexOf(
        '_receiverProcessAbsentWithin(const Duration(seconds: 5))',
        kill,
      );
      final stopApp = method.indexOf("'stop-app'", boundedProbe);
      final finalWait = method.indexOf(
        "'receiver process termination'",
        stopApp,
      );
      final emptyPid = method.indexOf(
        '(await _pidof(emulator)).isEmpty',
        finalWait,
      );
      expect(home, greaterThan(0));
      expect(settle, greaterThan(home));
      expect(kill, greaterThan(settle));
      expect(boundedProbe, greaterThan(kill));
      expect(stopApp, greaterThan(boundedProbe));
      expect(finalWait, greaterThan(stopApp));
      expect(emptyPid, greaterThan(finalWait));
      expect(method, contains("'cmd'"));
      expect(method, contains("'activity'"));
      expect(method, isNot(contains("'force-stop'")));
    },
  );

  test('bounded receiver termination probe polls pidof for five seconds', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<bool> _receiverProcessAbsentWithin');
    final end = source.indexOf('Future<String> _pidof', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    expect(helper, contains('DateTime.now().add(timeout)'));
    expect(helper, contains('(await _pidof(emulator)).isEmpty'));
    expect(helper, contains('Duration(milliseconds: 500)'));
    expect(helper, contains('return false'));
  });

  test('installed action results distinguish binding and action failures', () {
    final config = <String, Object?>{
      'transport_action': androidNotificationDrainObserveAction,
      'stepId': 'notification-notification_drain_observe-run-1',
      'runId': 'run-1',
      'nonce': 'nonce-1',
    };
    final result = <String, Object?>{
      'schema': androidNotificationPayloadE2EResultSchema,
      'transport_action': androidNotificationDrainObserveAction,
      'scenario': androidNotificationPayloadE2EScenario,
      'stepId': config['stepId'],
      'runId': config['runId'],
      'nonce': config['nonce'],
      'status': 'complete',
      'success': true,
    };

    expect(
      classifyAndroidNotificationActionResult(
        result: result,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.accepted,
    );

    for (final bindingKey in <String>[
      'schema',
      'transport_action',
      'scenario',
      'stepId',
      'runId',
      'nonce',
    ]) {
      final mismatched = Map<String, Object?>.from(result)
        ..[bindingKey] = 'wrong-$bindingKey';
      expect(
        classifyAndroidNotificationActionResult(
          result: mismatched,
          config: config,
          expectedStatus: 'complete',
        ),
        AndroidNotificationActionResultDisposition.bindingMismatch,
        reason: bindingKey,
      );
    }

    final failed = Map<String, Object?>.from(result)
      ..['status'] = 'failed'
      ..['success'] = false
      ..['errorType'] = 'StateError';
    expect(
      classifyAndroidNotificationActionResult(
        result: failed,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.boundFailure,
    );

    final mismatchedFailure = Map<String, Object?>.from(failed)
      ..['nonce'] = 'wrong-nonce';
    expect(
      classifyAndroidNotificationActionResult(
        result: mismatchedFailure,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.bindingMismatch,
    );

    final invalid = Map<String, Object?>.from(result)..['success'] = false;
    expect(
      classifyAndroidNotificationActionResult(
        result: invalid,
        config: config,
        expectedStatus: 'complete',
      ),
      AndroidNotificationActionResultDisposition.invalidCompletion,
    );
  });

  test('installed action failure diagnostics allowlist error type only', () {
    expect(safeAndroidNotificationActionErrorType('StateError'), 'StateError');
    expect(
      safeAndroidNotificationActionErrorType('TimeoutException'),
      'TimeoutException',
    );
    expect(
      safeAndroidNotificationActionErrorType(
        'StateError: secret peer and plaintext marker',
      ),
      'unavailable',
    );
    expect(
      safeAndroidNotificationActionErrorType(<String, Object?>{
        'message': 'secret peer and plaintext marker',
      }),
      'unavailable',
    );
  });

  test('accepts one exact production FCM staged ciphertext tuple', () {
    final observation = parseAndroidStagedEnvelopeObservation(
      jsonEncode(<String, Object?>{
        'kind': 'chat',
        'kem': 'raw-kem',
        'ciphertext': 'raw-ciphertext',
        'nonce': 'raw-nonce',
        'senderPeerId': 'peer-sender',
        'messageId': 'message-123456789',
        'receivedAtMs': 2000,
      }),
      expectedMessageId: 'message-123456789',
      expectedSenderPeerId: 'peer-sender',
      notBefore: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );

    expect(observation.messageId, 'message-123456789');
    expect(observation.toJson()['messageIdPrefix'], 'message-');
    expect(observation.ciphertextSha256, hasLength(64));
    expect(observation.nonceSha256, hasLength(64));
    expect(observation.toJson().toString(), isNot(contains('raw-ciphertext')));
    expect(observation.toJson().toString(), isNot(contains('raw-nonce')));
  });

  test(
    'rejects wrong sender, message, kind, stale time, and missing crypto',
    () {
      final base = <String, Object?>{
        'kind': 'chat',
        'kem': 'kem',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
        'senderPeerId': 'peer-sender',
        'messageId': 'message-1',
        'receivedAtMs': 2000,
      };
      for (final mutate in <void Function(Map<String, Object?>)>[
        (value) => value['kind'] = 'reaction',
        (value) => value['kem'] = '',
        (value) => value['ciphertext'] = '',
        (value) => value['nonce'] = '',
        (value) => value['senderPeerId'] = 'peer-other',
        (value) => value['messageId'] = 'message-other',
        (value) => value['receivedAtMs'] = 999,
      ]) {
        final value = Map<String, Object?>.from(base);
        mutate(value);
        expect(
          () => parseAndroidStagedEnvelopeObservation(
            jsonEncode(value),
            expectedMessageId: 'message-1',
            expectedSenderPeerId: 'peer-sender',
            notBefore: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('provider send helper accepts the v1.8.0 outcome journal', () {
    expect(
      relayJournalContainsAndroidProviderSend(
        'Aug 17 10:00:00 relay relay-server[1]: [PUSH] outcome=success '
        'attempt=1 total_attempts=3',
      ),
      isTrue,
      reason: 'inbox.go:626 is the ordinary provider-acceptance line',
    );
    expect(
      relayJournalContainsAndroidProviderSend(
        '[PUSH] outcome=success fallback=strict',
      ),
      isTrue,
      reason: 'inbox.go:664 is provider acceptance on the strict fallback',
    );
  });

  test('provider send helper rejects journals without an accepted send', () {
    for (final journal in const <String>[
      '',
      '[PUSH] outcome=failed attempts=3',
      '[PUSH] outcome=retrying attempt=1 total_attempts=3',
      '[PUSH] outcome=invalid_token reason=typed_unregistered',
      '[PUSH] provider unavailable outcome=provider_unavailable',
      '[PUSH] outcome=success_but_not_really',
      // The pre-v1.8.0 recipient-bearing line `8d86501e4` deleted. Accepting
      // it would let a rolled-back relay pass a grammar this plan re-derived.
      '[PUSH] Notification sent to 12D3KooWRecipientPee (attempt 1/3)',
    ]) {
      expect(
        relayJournalContainsAndroidProviderSend(journal),
        isFalse,
        reason: journal,
      );
    }
  });

  test(
    'Plan 398 provider evidence requires one first-attempt acceptance without retry or fallback',
    () {
      expect(
        relayJournalProvesSingleFirstAttemptProviderAcceptance(
          'relay: [PUSH] outcome=success attempt=1 total_attempts=3',
        ),
        isTrue,
        reason: 'TC-398-06 provider attempt',
      );
      for (final journal in const <String>[
        '',
        '[PUSH] outcome=success attempt=2 total_attempts=3',
        '[PUSH] outcome=retrying attempt=1 total_attempts=3\n'
            '[PUSH] outcome=success attempt=2 total_attempts=3',
        '[PUSH] outcome=success fallback=strict',
        '[PUSH] outcome=success attempt=1 total_attempts=3\n'
            '[PUSH] outcome=success attempt=1 total_attempts=3',
        '[PUSH] outcome=failed attempts=3',
      ]) {
        expect(
          relayJournalProvesSingleFirstAttemptProviderAcceptance(journal),
          isFalse,
          reason: journal,
        );
      }
    },
  );

  test('Plan 398 provider journal parser returns only the pinned hashes', () {
    const dispatch =
        '1111111111111111111111111111111111111111111111111111111111111111';
    const collapse =
        '2222222222222222222222222222222222222222222222222222222222222222';
    const providerMessage =
        '4444444444444444444444444444444444444444444444444444444444444444';
    Map<String, Object?> acceptedRecord({
      bool includeProviderMessage = true,
    }) => <String, Object?>{
      'schema': 'mknoon.relay.group-message-provider-attempt.v1',
      'source': 'group_content',
      'provenance': 'complete',
      'dispatchCorrelationSha256': dispatch,
      'claimedCollapseIdentifierSha256': collapse,
      'providerAttempt': 1,
      'attemptKind': 'primary',
      'outcome': 'accepted',
      'firebaseResponseNameSha256':
          '3333333333333333333333333333333333333333333333333333333333333333',
      if (includeProviderMessage) 'providerMessageIdSha256': providerMessage,
    };

    final complete = parseRelayAcceptedGroupMessageProviderAttempt(
      'relay[1]: [GROUP_MESSAGE_PROVIDER_ATTEMPT] '
      '${jsonEncode(acceptedRecord())}',
    );
    expect(complete?.dispatchCorrelationSha256, dispatch);
    expect(complete?.source, 'group_content');
    expect(complete?.claimedCollapseIdentifierSha256, collapse);
    expect(complete?.providerMessageIdSha256, providerMessage);
    final joined = bindRelayAcceptedGroupMessageProviderAttempt(
      attempt: complete,
      relayGroupMessageDispatchSource: 'groupContent',
      expectedCollapseIdentifierSha256: collapse,
    );
    expect(joined?.dispatchCorrelationSha256, dispatch);
    expect(joined?.providerMessageIdSha256, providerMessage);

    expect(
      bindRelayAcceptedGroupMessageProviderAttempt(
        attempt: complete,
        relayGroupMessageDispatchSource: 'groupInbox',
        expectedCollapseIdentifierSha256: collapse,
      ),
      isNull,
      reason: 'a group_content journal row cannot join groupInbox metrics',
    );
    expect(
      bindRelayAcceptedGroupMessageProviderAttempt(
        attempt: complete,
        relayGroupMessageDispatchSource: 'groupContent',
        expectedCollapseIdentifierSha256:
            '5555555555555555555555555555555555555555555555555555555555555555',
      ),
      isNull,
      reason: 'the claimed collapse hash must match the run-owned card hash',
    );

    final withoutNormalizedProvider =
        parseRelayAcceptedGroupMessageProviderAttempt(
          '[GROUP_MESSAGE_PROVIDER_ATTEMPT] '
          '${jsonEncode(acceptedRecord(includeProviderMessage: false))}',
        );
    final joinedWithoutNormalizedProvider =
        bindRelayAcceptedGroupMessageProviderAttempt(
          attempt: withoutNormalizedProvider,
          relayGroupMessageDispatchSource: 'groupContent',
          expectedCollapseIdentifierSha256: collapse,
        );
    expect(
      joinedWithoutNormalizedProvider?.dispatchCorrelationSha256,
      dispatch,
    );
    expect(joinedWithoutNormalizedProvider?.providerMessageIdSha256, isNull);
  });

  test(
    'Plan 398 provider journal parser rejects malformed open or ambiguous rows',
    () {
      const hash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      Map<String, Object?> acceptedRecord() => <String, Object?>{
        'schema': 'mknoon.relay.group-message-provider-attempt.v1',
        'source': 'group_inbox',
        'provenance': 'complete',
        'dispatchCorrelationSha256': hash,
        'claimedCollapseIdentifierSha256': hash,
        'providerAttempt': 1,
        'attemptKind': 'primary',
        'outcome': 'accepted',
        'firebaseResponseNameSha256': hash,
        'providerMessageIdSha256': hash,
      };

      final valid =
          '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(acceptedRecord())}';
      final uppercase = acceptedRecord()
        ..['dispatchCorrelationSha256'] = hash.toUpperCase();
      final raw = acceptedRecord()
        ..['dispatchCorrelationSha256'] = 'raw-dispatch-correlation';
      final invalidCollapse = acceptedRecord()
        ..['claimedCollapseIdentifierSha256'] = 'raw-collapse-identifier';
      final invalidFirebaseResponse = acceptedRecord()
        ..['firebaseResponseNameSha256'] = hash.toUpperCase();
      final open = acceptedRecord()..['rawProviderResponseName'] = 'projects/p';
      final retry = acceptedRecord()
        ..['providerAttempt'] = 2
        ..['outcome'] = 'accepted';
      final fallback = acceptedRecord()..['attemptKind'] = 'strict_fallback';
      final nullProvider = acceptedRecord()..['providerMessageIdSha256'] = null;
      for (final journal in <String>[
        '',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] {',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(uppercase)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(raw)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(invalidCollapse)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(invalidFirebaseResponse)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(open)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(retry)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(fallback)}',
        '[GROUP_MESSAGE_PROVIDER_ATTEMPT] ${jsonEncode(nullProvider)}',
        '$valid\n$valid',
        // Duplicate JSON members are ambiguous even when their values agree.
        valid.replaceFirst(
          '"dispatchCorrelationSha256":"$hash"',
          '"dispatchCorrelationSha256":"$hash",'
              '"dispatchCorrelationSha256":"$hash"',
        ),
      ]) {
        expect(
          parseRelayAcceptedGroupMessageProviderAttempt(journal),
          isNull,
          reason: journal,
        );
      }
    },
  );

  test('campaign provider wait passes a since-scoped journal slice', () {
    final source = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _waitForProviderSend(');
    final end = source.indexOf('Future<String> _relayJournalSince(', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    // Recipient binding lives in the journal SCOPE, not in the matched line;
    // dropping the scoping would widen the match to unrelated relay traffic.
    expect(source.substring(start, end), contains('_relayJournalSince(since)'));
    final slice = source.substring(
      end,
      source.indexOf(
        'Future<ActiveNotificationCard> _waitForNotification',
        end,
      ),
    );
    expect(slice, contains("'--since'"));
    expect(slice, contains('since.toUtc().millisecondsSinceEpoch'));
  });

  test('relay drain discriminator accepts only the production event name', () {
    expect(
      notificationWindowContainsRelayDrain(
        '[FLOW] P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS',
      ),
      isTrue,
    );
    expect(
      notificationWindowContainsRelayDrain('P2P_SERVICE_STAGED_DRAIN_SUCCESS'),
      isFalse,
    );
  });

  test('notification channel fingerprint masks only volatile provenance', () {
    const before = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mLastNotificationUpdateTimeMs=10}
      AppSettings: another.package (10124)
''';
    const afterPost = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const changedPolicy = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=2, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    // Measured on emulator-5554 (SDK 36): a Settings toggle OFF then ON
    // restores mImportance exactly but leaves mUserLockedFields=4 behind.
    const afterChannelToggleCycle = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const stillBlocked = '''
Ranking Config:
      AppSettings: com.mknoon.app (10999) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=0, mUserLockedFields=4, mLastNotificationUpdateTimeMs=99}
      AppSettings: another.package (10124)
''';
    const beforeWithLockField = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=true
        Delegate: com.google.android.gms (10001) enabled=true
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=0, mLastNotificationUpdateTimeMs=10}
      AppSettings: another.package (10124)
''';

    expect(
      androidNotificationChannelStateSha256(
        before,
        packageName: 'com.mknoon.app',
      ),
      androidNotificationChannelStateSha256(
        afterPost,
        packageName: 'com.mknoon.app',
      ),
    );
    expect(
      androidNotificationChannelStateSha256(
        changedPolicy,
        packageName: 'com.mknoon.app',
      ),
      isNot(
        androidNotificationChannelStateSha256(
          before,
          packageName: 'com.mknoon.app',
        ),
      ),
    );
    expect(
      androidNotificationChannelStateSha256(
        afterChannelToggleCycle,
        packageName: 'com.mknoon.app',
      ),
      androidNotificationChannelStateSha256(
        beforeWithLockField,
        packageName: 'com.mknoon.app',
      ),
      reason: 'user-lock provenance is not channel policy',
    );
    expect(
      androidNotificationChannelStateSha256(
        stillBlocked,
        packageName: 'com.mknoon.app',
      ),
      isNot(
        androidNotificationChannelStateSha256(
          beforeWithLockField,
          packageName: 'com.mknoon.app',
        ),
      ),
      reason: 'a channel left blocked must still red the restoration verify',
    );
  });

  test('flow records survive shared-log noise and keep emission order', () {
    final logcat = <String>[
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_COORDINATOR_ATTEMPT","details":{"trigger":"startup"}}',
      'D/SomethingElse: unrelated device traffic',
      'I/flutter: [FLOW] not-json-at-all',
      'I/flutter: [FLOW] "a bare string payload"',
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_TOKEN_REFRESH_EVENT","details":{}}',
      'I/flutter: [FLOW] {"layer":"FL","details":{"trigger":"resume"}}',
      'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_REGISTER_COORDINATOR_SUCCESS","details":{"trigger":"token_refresh","tokenSha256":"deadbeef"}}',
    ].join('\n');

    final records = androidNotificationFlowRecords(logcat);
    expect(
      records.map((record) => record.event).toList(growable: false),
      <String>[
        'PUSH_REGISTER_COORDINATOR_ATTEMPT',
        'PUSH_REGISTER_TOKEN_REFRESH_EVENT',
        'PUSH_REGISTER_COORDINATOR_SUCCESS',
      ],
    );
    expect(
      records.first.hasDetails(<String, Object?>{'trigger': 'startup'}),
      isTrue,
    );
    expect(records[1].details, isEmpty);
    // Extra proof digests must not defeat a trigger assertion.
    expect(
      records.last.hasDetails(<String, Object?>{'trigger': 'token_refresh'}),
      isTrue,
    );
    expect(
      records.last.hasDetails(<String, Object?>{'trigger': 'startup'}),
      isFalse,
    );
  });

  test('losing-path discriminator accepts the reconcile events too', () {
    String? sup(String event, String reason) =>
        androidNotificationLosingPathSuppression(
          'I/flutter: [FLOW] {"layer":"FL","event":"$event",'
          '"details":{"reason":"$reason","type":"new_message"}}',
        );

    // Measured on device: this is what the 1:1 live path actually emits when
    // it loses the race. Excluding it made tc_b13 unsatisfiable.
    expect(
      sup(
        'NOTIFICATION_LEGACY_CLAIM_RECONCILE',
        'message_event_already_claimed',
      ),
      'NOTIFICATION_LEGACY_CLAIM_RECONCILE:message_event_already_claimed',
    );
    expect(
      sup('NOTIFICATION_SUPPRESSED', 'recent_remote_push'),
      'NOTIFICATION_SUPPRESSED:recent_remote_push',
    );
    expect(
      sup('NOTIFICATION_DEFERRED', 'message_event_claim_pending'),
      'NOTIFICATION_DEFERRED:message_event_claim_pending',
      reason:
          'the background-owner-first ordering retains the live SQL row while '
          'the background isolate posts',
    );
    expect(
      sup(
        'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED',
        'recent_duplicate_background_push',
      ),
      'PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED:recent_duplicate_background_push',
    );

    // The REASON allow-list is unchanged: a novel stand-down still fails.
    expect(
      sup('NOTIFICATION_LEGACY_CLAIM_RECONCILE', 'some_new_reason'),
      isNull,
    );
    expect(sup('NOTIFICATION_SHOWN', 'message_event_already_claimed'), isNull);
    expect(
      sup('PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED', 'recent_remote_push'),
      isNull,
      reason: 'the FCM path has its own reason set',
    );
  });

  test('dual-path proof binds both attempts to the exact sent message', () {
    const messageId = 'd797dac5-0000-4000-8000-000000000001';
    const targetLive =
        'I/flutter: [FLOW] {"event":"CHAT_LISTENER_NEW_MESSAGE",'
        '"details":{"id":"d797dac5"}}';
    const staleFcm =
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
        '"details":{"messageIdPrefix":"e313b556"}}';
    const targetFcm =
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED",'
        '"details":{"messageIdPrefix":"d797dac5"}}';

    expect(
      notificationWindowProvesDualPathAttempt(
        '$staleFcm\n$targetLive',
        messageId: messageId,
      ),
      isFalse,
      reason: 'a late receipt from the preceding leg cannot prove this race',
    );
    expect(
      notificationWindowProvesDualPathAttempt(
        '$staleFcm\n$targetLive\n$targetFcm',
        messageId: messageId,
      ),
      isTrue,
    );
    expect(
      notificationWindowProvesDualPathAttempt(
        '$targetLive\n$targetFcm',
        messageId: '',
      ),
      isFalse,
    );
  });

  test('notification channel census counts distinct native keys only', () {
    String record({required int id, required String channel}) =>
        'NotificationRecord(0x1: pkg=com.mknoon.app user=UserHandle{0} '
        'id=$id tag=null importance=4 '
        'key=0|com.mknoon.app|$id|null|10256: '
        'Notification(channel=$channel shortcut=null))\n'
        '  extras={\n'
        '    android.text=String (target body)\n'
        '  }';
    String dump(Iterable<String> records) =>
        'Current Notification Manager state:\n'
        '  Notification List:\n'
        '${records.join('\n    ')}\n'
        '  Ranking Config:';

    expect(
      androidNotificationChannelsForBody(
        dump(<String>[
          record(id: 42, channel: 'mknoon_messages'),
          record(id: 42, channel: 'mknoon_messages'),
        ]),
        packageName: 'com.mknoon.app',
        body: 'target body',
      ),
      <String>['mknoon_messages'],
      reason: 'repeated dumpsys views of one native key are one active card',
    );
    expect(
      androidNotificationChannelsForBody(
        dump(<String>[
          record(id: 42, channel: 'mknoon_messages'),
          record(id: 43, channel: 'mknoon_messages'),
        ]),
        packageName: 'com.mknoon.app',
        body: 'target body',
      ),
      <String>['mknoon_messages', 'mknoon_messages'],
      reason: 'two native IDs remain a real duplicate-card failure',
    );
    expect(
      androidNotificationChannelsForBody(
        dump(<String>[
          record(id: 42, channel: 'mknoon_messages'),
          record(id: 42, channel: 'mknoon_messages_silent'),
        ]),
        packageName: 'com.mknoon.app',
        body: 'target body',
      ),
      <String>['mknoon_messages', 'mknoon_messages_silent'],
      reason: 'a conflicting representation cannot be silently collapsed',
    );
  });

  test('post-attempt union accepts either delivery path, receipt alone no', () {
    const receiptOnly =
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{}}\n'
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_NOTIFICATION_SUPPRESSED","details":{"reason":"message_event_already_claimed"}}';
    // The wake arrived and then stood down: no post was ever attempted.
    expect(androidNotificationPostAttemptEvent(receiptOnly), isNull);

    expect(
      androidNotificationPostAttemptEvent(
        '$receiptOnly\n'
        'I/flutter: [FLOW] {"layer":"FL","event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1"}}',
      ),
      'PUSH_BACKGROUND_NOTIFICATION_SHOWN',
    );
    expect(
      androidNotificationPostAttemptEvent(
        'I/flutter: [FLOW] {"layer":"FL","event":"NOTIFICATION_SHOWN","details":{"silent":false}}',
      ),
      'NOTIFICATION_SHOWN',
      reason: 'either path may win the race',
    );
    expect(androidNotificationPostAttemptEvent(''), isNull);
  });

  test('first post attempt silent flag is read from the winning path', () {
    const window = '''
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{"messageId":"m1"}}
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1","silent":false}}
I/flutter: [FLOW] {"event":"NOTIFICATION_LEGACY_CLAIM_RECONCILE","details":{"reason":"message_event_already_claimed"}}
I/flutter: [FLOW] {"event":"NOTIFICATION_SHOWN","details":{"silent":true}}
''';
    // The FIRST attempt is the alert; the later silent same-ID reconcile must
    // not be able to overwrite the verdict.
    expect(androidNotificationFirstPostAttemptSilent(window), isFalse);

    const silentWinner = '''
I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1","silent":true}}
''';
    expect(androidNotificationFirstPostAttemptSilent(silentWinner), isTrue);

    // A wake receipt is not a post attempt, and a post that made no native
    // show carries no flag — both must read null rather than "audible".
    expect(
      androidNotificationFirstPostAttemptSilent(
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_MESSAGE_RECEIVED","details":{"messageId":"m1"}}',
      ),
      isNull,
    );
    expect(
      androidNotificationFirstPostAttemptSilent(
        'I/flutter: [FLOW] {"event":"PUSH_BACKGROUND_NOTIFICATION_SHOWN","details":{"messageId":"m1"}}',
      ),
      isNull,
    );
  });

  test('settings switch node is addressed by its exact resource id', () {
    const dump =
        '<hierarchy>'
        '<node index="0" text="Show notifications" resource-id="com.android.settings:id/switch_text" bounds="[126,746][472,803]" />'
        '<node index="1" text="" resource-id="android:id/switch_widget" class="android.widget.Switch" checkable="true" checked="true" bounds="[848,711][985,837]" />'
        '<node index="2" text="" resource-id="com.android.settings:id/switchWidget" class="android.widget.Switch" checked="false" bounds="[859,1395][996,1521]" />'
        '</hierarchy>';

    final master = androidUiSwitchNodeByResourceId(
      dump,
      resourceId: 'android:id/switch_widget',
    );
    expect(master, isNotNull);
    expect(master!.x, (848 + 985) ~/ 2);
    expect(master.y, (711 + 837) ~/ 2);
    expect(master.checked, isTrue);

    final secondary = androidUiSwitchNodeByResourceId(
      dump,
      resourceId: 'com.android.settings:id/switchWidget',
    );
    expect(secondary!.checked, isFalse);

    expect(
      androidUiSwitchNodeByResourceId(dump, resourceId: 'android:id/absent'),
      isNull,
    );
  });

  test('channel importance is read from the package own dumpsys block', () {
    const dump = '''
Ranking Config:
      AppSettings: com.mknoon.app (10123) importance=DEFAULT userSet=false
        NotificationChannel{mId='mknoon_messages', mImportance=4, mUserLockedFields=0}
        NotificationChannel{mId='mknoon_messages_silent', mImportance=2, mUserLockedFields=0}
      AppSettings: other.package (10124)
        NotificationChannel{mId='mknoon_messages', mImportance=0, mUserLockedFields=4}
''';

    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'mknoon_messages',
      ),
      4,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'mknoon_messages_silent',
      ),
      2,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'other.package',
        channelId: 'mknoon_messages',
      ),
      0,
    );
    expect(
      androidNotificationChannelImportance(
        dump,
        packageName: 'com.mknoon.app',
        channelId: 'absent_channel',
      ),
      isNull,
    );
  });
}
