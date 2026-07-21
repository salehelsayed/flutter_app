import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/_support/invite_reliability_runner_contract.dart';

void main() {
  group('invite reliability role supervision', () {
    test('terminates the sibling as soon as the primary fails', () async {
      final primaryExit = Completer<int>();
      final siblingExit = Completer<int>();
      var primaryTerminations = 0;
      var siblingTerminations = 0;

      final supervision = superviseInviteReliabilityRoleExits(
        primaryExitCode: primaryExit.future,
        siblingExitCode: siblingExit.future,
        terminatePrimary: () async {
          primaryTerminations += 1;
          primaryExit.complete(-15);
        },
        terminateSibling: () async {
          siblingTerminations += 1;
          siblingExit.complete(-15);
        },
      );

      primaryExit.complete(1);
      final result = await supervision;

      expect(result.primary, 1);
      expect(result.sibling, -15);
      expect(primaryTerminations, 0);
      expect(siblingTerminations, 1);
    });

    test('terminates the primary as soon as the sibling fails', () async {
      final primaryExit = Completer<int>();
      final siblingExit = Completer<int>();
      var primaryTerminations = 0;
      var siblingTerminations = 0;

      final supervision = superviseInviteReliabilityRoleExits(
        primaryExitCode: primaryExit.future,
        siblingExitCode: siblingExit.future,
        terminatePrimary: () async {
          primaryTerminations += 1;
          primaryExit.complete(-15);
        },
        terminateSibling: () async {
          siblingTerminations += 1;
          siblingExit.complete(-15);
        },
      );

      siblingExit.complete(2);
      final result = await supervision;

      expect(result.primary, -15);
      expect(result.sibling, 2);
      expect(primaryTerminations, 1);
      expect(siblingTerminations, 0);
    });

    test(
      'waits for both successful roles without terminating either',
      () async {
        final primaryExit = Completer<int>();
        final siblingExit = Completer<int>();
        var primaryTerminations = 0;
        var siblingTerminations = 0;

        var supervisionCompleted = false;
        final supervision = superviseInviteReliabilityRoleExits(
          primaryExitCode: primaryExit.future,
          siblingExitCode: siblingExit.future,
          terminatePrimary: () async {
            primaryTerminations += 1;
          },
          terminateSibling: () async {
            siblingTerminations += 1;
          },
        ).whenComplete(() => supervisionCompleted = true);

        primaryExit.complete(0);
        await Future<void>.delayed(Duration.zero);
        expect(supervisionCompleted, isFalse);
        expect(primaryTerminations, 0);
        expect(siblingTerminations, 0);

        siblingExit.complete(0);
        final result = await supervision;

        expect(result.primary, 0);
        expect(result.sibling, 0);
        expect(primaryTerminations, 0);
        expect(siblingTerminations, 0);
      },
    );
  });

  group('invite reliability primary readiness supervision', () {
    test('does not launch the sibling when primary exits nonzero', () async {
      final primaryExit = Completer<int>();
      var siblingLaunches = 0;

      final launch = launchInviteReliabilitySiblingWhenPrimaryReady<int>(
        isPrimaryReady: () => false,
        primaryExitCode: primaryExit.future,
        timeout: const Duration(minutes: 1),
        pollInterval: const Duration(minutes: 1),
        readinessDescription: 'primary-ready.json',
        launchSibling: () async {
          siblingLaunches += 1;
          return 1;
        },
      );

      primaryExit.complete(17);

      await expectLater(
        launch,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exitCode=17'),
          ),
        ),
      );
      expect(siblingLaunches, 0);
    });

    test('treats a zero exit before readiness as premature', () async {
      final primaryExit = Completer<int>();
      var siblingLaunches = 0;

      final launch = launchInviteReliabilitySiblingWhenPrimaryReady<int>(
        isPrimaryReady: () => false,
        primaryExitCode: primaryExit.future,
        timeout: const Duration(minutes: 1),
        pollInterval: const Duration(minutes: 1),
        readinessDescription: 'primary-ready.json',
        launchSibling: () async {
          siblingLaunches += 1;
          return 1;
        },
      );

      primaryExit.complete(0);

      await expectLater(
        launch,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('exitCode=0'),
          ),
        ),
      );
      expect(siblingLaunches, 0);
    });

    test('launches the sibling after delayed primary readiness', () async {
      final primaryExit = Completer<int>();
      var primaryReady = false;
      var siblingLaunches = 0;

      final launch = launchInviteReliabilitySiblingWhenPrimaryReady<int>(
        isPrimaryReady: () => primaryReady,
        primaryExitCode: primaryExit.future,
        timeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
        readinessDescription: 'primary-ready.json',
        launchSibling: () async {
          siblingLaunches += 1;
          return 267;
        },
      );
      Timer.run(() => primaryReady = true);

      expect(await launch, 267);
      expect(siblingLaunches, 1);
    });
  });

  group('invite-send-latency host artifact capture receipt', () {
    const runId = 'tc267-receipt-run';
    const primarySha =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const siblingSha =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('does not expose a receipt before both stable owner artifacts', () {
      final barrier = InviteSendLatencyHostCaptureBarrier(
        runId: runId,
        mode: 'baseline',
      );

      expect(barrier.receipt, isNull);
      barrier.recordStableRoleArtifact(
        role: 'primary',
        artifactSha256: primarySha,
      );
      expect(barrier.receipt, isNull);

      barrier.recordStableRoleArtifact(
        role: 'sibling',
        artifactSha256: siblingSha,
      );
      expect(barrier.receipt, <String, Object?>{
        'schema': inviteSendLatencyHostCaptureReceiptSchema,
        'schemaVersion': inviteSendLatencyHostCaptureReceiptSchemaVersion,
        'scenario': inviteSendLatencyScenario,
        'mode': 'baseline',
        'runId': runId,
        'primaryArtifactSha256': primarySha,
        'siblingArtifactSha256': siblingSha,
      });

      barrier.recordStableRoleArtifact(
        role: 'primary',
        artifactSha256: primarySha,
      );
      expect(
        () => barrier.recordStableRoleArtifact(
          role: 'primary',
          artifactSha256: siblingSha,
        ),
        throwsStateError,
      );
    });

    test('persists the exact receipt atomically and idempotently', () async {
      final directory = await Directory.systemTemp.createTemp(
        'tc267_host_capture_receipt_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final barrier = InviteSendLatencyHostCaptureBarrier(
        runId: runId,
        mode: 'baseline',
      )..recordStableRoleArtifact(role: 'primary', artifactSha256: primarySha);
      final target = File(
        '${directory.path}/'
        '${inviteSendLatencyHostCaptureReceiptFileName(runId)}',
      );
      expect(target.existsSync(), isFalse);
      expect(barrier.receipt, isNull);

      barrier.recordStableRoleArtifact(
        role: 'sibling',
        artifactSha256: siblingSha,
      );
      final receipt = barrier.receipt!;
      final persisted =
          await persistInviteSendLatencyHostCaptureReceiptAtomically(
            directory: directory,
            receipt: receipt,
          );
      final firstBytes = await persisted.readAsBytes();
      expect(jsonDecode(utf8.decode(firstBytes)), receipt);
      expect(File('${persisted.path}.pending').existsSync(), isFalse);

      final repeated =
          await persistInviteSendLatencyHostCaptureReceiptAtomically(
            directory: directory,
            receipt: receipt,
          );
      expect(repeated.path, persisted.path);
      expect(await repeated.readAsBytes(), firstBytes);
      expect(File('${persisted.path}.pending').existsSync(), isFalse);

      final conflicting = Map<String, Object?>.from(receipt)
        ..['mode'] = 'closure';
      await expectLater(
        persistInviteSendLatencyHostCaptureReceiptAtomically(
          directory: directory,
          receipt: conflicting,
        ),
        throwsStateError,
      );
      expect(await persisted.readAsBytes(), firstBytes);
    });

    test('each role rejects stale or wrong-hash receipts', () {
      final barrier =
          InviteSendLatencyHostCaptureBarrier(runId: runId, mode: 'baseline')
            ..recordStableRoleArtifact(
              role: 'primary',
              artifactSha256: primarySha,
            )
            ..recordStableRoleArtifact(
              role: 'sibling',
              artifactSha256: siblingSha,
            );
      final receipt = barrier.receipt!;

      expect(
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: receipt,
          expectedRunId: runId,
          expectedMode: 'baseline',
          role: 'primary',
          expectedOwnArtifactSha256: primarySha,
        ).ok,
        isTrue,
      );
      expect(
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: receipt,
          expectedRunId: runId,
          expectedMode: 'baseline',
          role: 'sibling',
          expectedOwnArtifactSha256: siblingSha,
        ).ok,
        isTrue,
      );

      final stale = Map<String, Object?>.from(receipt)..['runId'] = 'stale-run';
      expect(
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: stale,
          expectedRunId: runId,
          expectedMode: 'baseline',
          role: 'primary',
          expectedOwnArtifactSha256: primarySha,
        ).ok,
        isFalse,
      );
      expect(
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: receipt,
          expectedRunId: runId,
          expectedMode: 'baseline',
          role: 'primary',
          expectedOwnArtifactSha256: siblingSha,
        ).ok,
        isFalse,
      );
      expect(
        validateInviteSendLatencyHostCaptureReceiptForRole(
          receipt: receipt,
          expectedRunId: runId,
          expectedMode: 'closure',
          role: 'sibling',
          expectedOwnArtifactSha256: siblingSha,
        ).ok,
        isFalse,
      );
    });

    test('both harness roles validate host custody before returning', () {
      final source = File(
        'integration_test/group_multi_device_real_harness.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(contains("_signalName('latency_primary_complete')")),
      );
      expect(
        source,
        isNot(contains("_signalName('latency_sibling_complete')")),
      );

      final primaryStart = source.indexOf(
        'Future<void> _runInviteSendLatencyPrimary',
      );
      final siblingStart = source.indexOf(
        'Future<void> _runInviteSendLatencySibling',
      );
      final primaryArtifact = source.indexOf(
        "_latencyArtifactName('primary'),",
        primaryStart,
      );
      final primaryHash = source.indexOf(
        "_latencyArtifactSha256('primary')",
        primaryArtifact,
      );
      final primaryReceipt = source.indexOf(
        'await _waitForLatencyHostCaptureReceipt(',
        primaryHash,
      );
      final siblingArtifact = source.indexOf(
        "_latencyArtifactName('sibling'),",
        siblingStart,
      );
      final siblingHash = source.indexOf(
        "_latencyArtifactSha256('sibling')",
        siblingArtifact,
      );
      final siblingReceipt = source.indexOf(
        'await _waitForLatencyHostCaptureReceipt(',
        siblingHash,
      );

      expect(primaryStart, greaterThanOrEqualTo(0));
      expect(primaryStart, lessThan(primaryArtifact));
      expect(primaryArtifact, lessThan(primaryHash));
      expect(primaryHash, lessThan(primaryReceipt));
      expect(primaryReceipt, lessThan(siblingStart));
      expect(siblingStart, lessThan(siblingArtifact));
      expect(siblingArtifact, lessThan(siblingHash));
      expect(siblingHash, lessThan(siblingReceipt));
    });

    test('Android broker receipts only owner-stable sink artifacts', () {
      final source = File(
        'integration_test/scripts/run_invite_reliability_multi_device.dart',
      ).readAsStringSync();
      final hostOnlyReceipt = source.indexOf(
        '_isLatencyHostCaptureReceipt(name)',
      );
      final ownerLookup = source.indexOf(
        'final ownedRole = _ownedLatencyRole(deviceId, name);',
        hostOnlyReceipt,
      );
      final wrongOwnerSkip = source.indexOf(
        '_isLatencyRoleArtifact(name) && ownedRole == null',
        ownerLookup,
      );
      final stableRead = source.indexOf(
        'requireStableDeviceRead: ownedRole != null',
        wrongOwnerSkip,
      );
      final recordStable = source.indexOf(
        '_latencyCaptureBarrier!.recordStableRoleArtifact(',
        stableRead,
      );
      final receipt = source.indexOf(
        'final captureReceipt = _latencyCaptureBarrier?.receipt;',
        recordStable,
      );
      final persist = source.indexOf(
        'persistInviteSendLatencyHostCaptureReceiptAtomically(',
        receipt,
      );
      final sinkOnly = source.indexOf(
        '_latencyCaptureBarrier != null &&',
        persist,
      );

      expect(hostOnlyReceipt, greaterThanOrEqualTo(0));
      expect(hostOnlyReceipt, lessThan(ownerLookup));
      expect(ownerLookup, lessThan(wrongOwnerSkip));
      expect(wrongOwnerSkip, lessThan(stableRead));
      expect(stableRead, lessThan(recordStable));
      expect(recordStable, lessThan(receipt));
      expect(receipt, lessThan(persist));
      expect(persist, lessThan(sinkOnly));
    });

    test(
      'Android receipt delivery atomically replaces partial target files',
      () {
        final source = File(
          'integration_test/scripts/run_invite_reliability_multi_device.dart',
        ).readAsStringSync();
        final push = source.indexOf('Future<bool> _push(');
        final hiddenPending = source.indexOf('.host_pending', push);
        final teePending = source.indexOf("'tee',", hiddenPending);
        final promote = source.indexOf("'mv',", teePending);
        final exactReread = source.indexOf(
          'exactReceiptAlreadyPresent',
          promote,
        );
        final retryMismatch = source.indexOf(
          '!exactReceiptAlreadyPresent',
          exactReread,
        );

        expect(push, greaterThanOrEqualTo(0));
        expect(push, lessThan(hiddenPending));
        expect(hiddenPending, lessThan(teePending));
        expect(teePending, lessThan(promote));
        expect(promote, lessThan(exactReread));
        expect(exactReread, lessThan(retryMismatch));
      },
    );
  });

  test('INV-267-R1 rejects unknown flags and validates the latency artifact', () {
    const defaults = <String>['ios-primary', 'ios-sibling'];
    final legacy = InviteReliabilityRunnerArguments.parse(
      const <String>[],
      defaultDeviceIds: defaults,
    );
    expect(legacy.scenario, inviteReliabilityScenario);
    expect(legacy.mode, isNull);
    expect(legacy.deviceIds, defaults);

    final latency = InviteReliabilityRunnerArguments.parse(const <String>[
      '--scenario',
      'invite_send_latency',
      '--mode',
      'baseline',
      '-d',
      'physical-1,emulator-5554',
    ], defaultDeviceIds: defaults);
    expect(latency.scenario, inviteSendLatencyScenario);
    expect(latency.mode, 'baseline');
    expect(latency.deviceIds, <String>['physical-1', 'emulator-5554']);

    expect(
      () => InviteReliabilityRunnerArguments.parse(const <String>[
        '--unknown',
      ], defaultDeviceIds: defaults),
      throwsArgumentError,
    );
    expect(
      () => InviteReliabilityRunnerArguments.parse(const <String>[
        '--scenario',
        'invite_send_latency',
        '-d',
        'physical-1,emulator-5554',
      ], defaultDeviceIds: defaults),
      throwsArgumentError,
      reason: 'latency runs require an explicit compatible mode',
    );
    expect(
      () => InviteReliabilityRunnerArguments.parse(const <String>[
        '--mode',
        'baseline',
      ], defaultDeviceIds: defaults),
      throwsArgumentError,
      reason: 'the legacy scenario must remain mode-free',
    );
    expect(
      () => InviteReliabilityRunnerArguments.parse(const <String>[
        '--scenario',
        'invite_send_latency',
        '--mode',
        'baseline',
        '-d',
        'same,same',
      ], defaultDeviceIds: defaults),
      throwsArgumentError,
    );

    expect(
      validateInviteSendLatencyTopology(
        selectedDeviceIds: latency.deviceIds,
        liveDevices: const <InviteReliabilityDeviceTarget>[
          InviteReliabilityDeviceTarget(
            id: 'physical-1',
            targetPlatform: 'android-arm64',
            isEmulator: false,
          ),
          InviteReliabilityDeviceTarget(
            id: 'emulator-5554',
            targetPlatform: 'android-x64',
            isEmulator: true,
          ),
        ],
      ),
      isNull,
    );
    expect(
      validateInviteSendLatencyTopology(
        selectedDeviceIds: latency.deviceIds.reversed.toList(),
        liveDevices: const <InviteReliabilityDeviceTarget>[
          InviteReliabilityDeviceTarget(
            id: 'physical-1',
            targetPlatform: 'android-arm64',
            isEmulator: false,
          ),
          InviteReliabilityDeviceTarget(
            id: 'emulator-5554',
            targetPlatform: 'android-x64',
            isEmulator: true,
          ),
        ],
      ),
      contains('primary=physical Android'),
    );

    final artifacts = _validArtifacts();
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: artifacts.primary,
        siblingArtifact: artifacts.sibling,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).failures,
      isEmpty,
    );

    final duplicateObserved = _copy(artifacts.sibling);
    (((duplicateObserved['samples']! as List<Object?>).first)
            as Map<String, dynamic>)['eventCount'] =
        2;
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: artifacts.primary,
        siblingArtifact: duplicateObserved,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).failures,
      isEmpty,
      reason: 'Wave 0 must record unresolved duplicates instead of hiding them',
    );

    final validClosurePrimary = _copy(artifacts.primary)..['mode'] = 'closure';
    final validClosureSibling = _copy(artifacts.sibling)..['mode'] = 'closure';
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: validClosurePrimary,
        siblingArtifact: validClosureSibling,
        expectedRunId: 'run-267',
        expectedMode: 'closure',
      ).failures,
      isEmpty,
      reason: 'closure admits only exact one-event confirmed samples',
    );

    final afterCompletionClosureSibling = _copy(validClosureSibling);
    final afterCompletionSample =
        (afterCompletionClosureSibling['samples']! as List<Object?>).first!
            as Map<String, dynamic>;
    final afterCompletion = DateTime.parse(
      afterCompletionSample['observationCompletedAt'] as String,
    ).add(const Duration(milliseconds: 1));
    afterCompletionSample['observedAt'] = afterCompletion.toIso8601String();
    afterCompletionSample['observedLate'] = false;
    afterCompletionSample['finalReconciledAt'] = afterCompletion
        .add(const Duration(milliseconds: 1))
        .toIso8601String();
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: validClosurePrimary,
        siblingArtifact: afterCompletionClosureSibling,
        expectedRunId: 'run-267',
        expectedMode: 'closure',
      ).failures,
      isEmpty,
      reason: 'late is measured against the fixed deadline, not early exit',
    );

    final afterDeadlineClosureSibling = _copy(validClosureSibling);
    final afterDeadlineSample =
        (afterDeadlineClosureSibling['samples']! as List<Object?>).first!
            as Map<String, dynamic>;
    final afterDeadline = DateTime.parse(
      afterDeadlineSample['observationDeadlineAt'] as String,
    ).add(const Duration(milliseconds: 1));
    afterDeadlineSample['observedAt'] = afterDeadline.toIso8601String();
    afterDeadlineSample['observedLate'] = true;
    afterDeadlineSample['observationCompletedAt'] = afterDeadline
        .add(const Duration(milliseconds: 1))
        .toIso8601String();
    afterDeadlineSample['finalReconciledAt'] = afterDeadline
        .add(const Duration(milliseconds: 2))
        .toIso8601String();
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: validClosurePrimary,
        siblingArtifact: afterDeadlineClosureSibling,
        expectedRunId: 'run-267',
        expectedMode: 'closure',
      ).detail,
      contains(
        'closure requires one exact-ID recipient event within its window',
      ),
      reason: 'TC-267-07 cannot count an event first observed after deadline',
    );

    final afterFreezeSibling = _copy(artifacts.sibling);
    final afterFreezeSample =
        (afterFreezeSibling['samples']! as List<Object?>).first!
            as Map<String, dynamic>;
    afterFreezeSample['observedAt'] = DateTime.parse(
      afterFreezeSample['finalReconciledAt'] as String,
    ).add(const Duration(milliseconds: 1)).toIso8601String();
    expect(
      _validate(artifacts.primary, afterFreezeSibling).detail,
      contains('first observation cannot follow final reconciliation'),
      reason: 'the immutable final artifact cannot claim a future event',
    );

    final outcomeUnknownPrimary = _copy(artifacts.primary);
    final outcomeUnknownSibling = _copy(artifacts.sibling);
    _makeOutcomeUnknownSample(
      outcomeUnknownPrimary,
      outcomeUnknownSibling,
      sampleIndex: 10,
    );
    expect(
      _validate(outcomeUnknownPrimary, outcomeUnknownSibling).failures,
      isEmpty,
      reason:
          'baseline must retain a settled caller with no delivery confirmation',
    );
    final incompleteZeroEventSibling = _copy(outcomeUnknownSibling);
    final incompleteZeroEventSample =
        (incompleteZeroEventSibling['samples']! as List<Object?>)[10]!
            as Map<String, dynamic>;
    final incompleteDeadline = DateTime.parse(
      incompleteZeroEventSample['observationDeadlineAt'] as String,
    );
    incompleteZeroEventSample['observationCompletedAt'] = incompleteDeadline
        .subtract(const Duration(milliseconds: 1))
        .toIso8601String();
    expect(
      _validate(outcomeUnknownPrimary, incompleteZeroEventSibling).detail,
      contains('zero-event observation must reach its deadline'),
      reason: 'non-observation is evidence only after the full fixed window',
    );
    expect(
      jsonEncode(outcomeUnknownPrimary),
      isNot(contains('not_delivered')),
      reason: 'a timeout is no-confirmation evidence, never non-delivery',
    );

    final closurePrimary = _copy(outcomeUnknownPrimary)..['mode'] = 'closure';
    final closureSibling = _copy(outcomeUnknownSibling)..['mode'] = 'closure';
    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: closurePrimary,
        siblingArtifact: closureSibling,
        expectedRunId: 'run-267',
        expectedMode: 'closure',
      ).detail,
      allOf(
        contains('closure mode forbids outcome_unknown'),
        contains('closure requires one exact-ID recipient event'),
      ),
      reason: 'TC-267-07 closure cannot inherit baseline uncertainty',
    );

    final rejectedCanary = _copy(artifacts.primary);
    (rejectedCanary['admissionCanary']!
            as Map<String, dynamic>)['storeAccepted'] =
        false;
    expect(
      _validate(rejectedCanary, artifacts.sibling).detail,
      contains('storeAccepted must equal true'),
      reason: 'the once-per-run relay admission canary is mandatory',
    );

    final hostSummary = buildInviteSendLatencyHostSummary(
      primaryArtifact: outcomeUnknownPrimary,
      siblingArtifact: outcomeUnknownSibling,
      expectedRunId: 'run-267',
      expectedMode: 'baseline',
      primaryArtifactPath:
          '/tmp/${inviteSendLatencyArtifactFileName('run-267', 'primary')}',
      primaryArtifactSha256: List<String>.filled(64, 'b').join(),
      siblingArtifactPath:
          '/tmp/${inviteSendLatencyArtifactFileName('run-267', 'sibling')}',
      siblingArtifactSha256: List<String>.filled(64, 'c').join(),
      provenance: InviteSendLatencyProvenance(
        appGitRevision: List<String>.filled(40, 'd').join(),
        appGitDirty: true,
        appSourceFingerprintSha256: List<String>.filled(64, 'e').join(),
        nativeGitRevision: List<String>.filled(40, 'f').join(),
        relayAddressCount: 2,
        relayAddressesSha256: List<String>.filled(64, 'a').join(),
      ),
      generatedAt: DateTime.utc(2026, 7, 21),
    );
    expect(
      validateInviteSendLatencyHostSummary(
        summary: hostSummary,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
        expectedPrimaryArtifactPath:
            '/tmp/${inviteSendLatencyArtifactFileName('run-267', 'primary')}',
        expectedPrimaryArtifactSha256: List<String>.filled(64, 'b').join(),
        expectedSiblingArtifactPath:
            '/tmp/${inviteSendLatencyArtifactFileName('run-267', 'sibling')}',
        expectedSiblingArtifactSha256: List<String>.filled(64, 'c').join(),
      ).failures,
      isEmpty,
    );
    expect(
      (hostSummary['disposition']! as Map)['productionAuthorized'],
      isFalse,
    );
    expect(
      ((hostSummary['cells']! as List<Object?>).first
          as Map<String, Object?>)['recipientEventCountMax'],
      1,
    );
    final offlineCell = (hostSummary['cells']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .singleWhere(
          (cell) => cell['path'] == 'create' && cell['condition'] == 'offline',
        );
    expect(offlineCell['outcomeUnknownCount'], 1);
    expect(offlineCell['recipientNotObservedCount'], 1);
    expect(offlineCell['custodyConfirmedCount'], 4);
    final missingSourceFingerprint = _copy(hostSummary);
    (missingSourceFingerprint['provenance']! as Map<String, dynamic>).remove(
      'appSourceFingerprintSha256',
    );
    expect(
      validateInviteSendLatencyHostSummary(
        summary: missingSourceFingerprint,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).detail,
      contains('missing keys: appSourceFingerprintSha256'),
    );
    final tamperedRoleDigest = _copy(hostSummary);
    (((tamperedRoleDigest['roleArtifacts']! as Map<String, dynamic>)['primary']
        as Map<String, dynamic>))['sha256'] = List<String>.filled(
      64,
      '9',
    ).join();
    expect(
      validateInviteSendLatencyHostSummary(
        summary: tamperedRoleDigest,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
        expectedPrimaryArtifactSha256: List<String>.filled(64, 'b').join(),
      ).detail,
      contains('sha256 must match the validated primary artifact'),
    );
    final authorizedProduction = _copy(hostSummary);
    (authorizedProduction['disposition']!
            as Map<String, dynamic>)['productionAuthorized'] =
        true;
    expect(
      validateInviteSendLatencyHostSummary(
        summary: authorizedProduction,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).detail,
      contains('productionAuthorized must equal false'),
    );
    final negativePhaseMedian = _copy(hostSummary);
    (((negativePhaseMedian['cells']! as List<Object?>).first
                as Map<String, dynamic>)['phaseMedianMs']
            as Map<String, dynamic>)['live'] =
        -1;
    expect(
      validateInviteSendLatencyHostSummary(
        summary: negativePhaseMedian,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).detail,
      contains('live must be a finite non-negative number'),
    );

    final tiedPrimary = _copy(artifacts.primary);
    final tiedSibling = _copy(artifacts.sibling);
    _makeLiveInboxTie(tiedPrimary, tiedSibling);
    expect(_validate(tiedPrimary, tiedSibling).failures, isEmpty);
    final tiedSummary = buildInviteSendLatencyHostSummary(
      primaryArtifact: tiedPrimary,
      siblingArtifact: tiedSibling,
      expectedRunId: 'run-267',
      expectedMode: 'baseline',
      primaryArtifactPath: '/tmp/primary-tied.json',
      primaryArtifactSha256: List<String>.filled(64, '1').join(),
      siblingArtifactPath: '/tmp/sibling-tied.json',
      siblingArtifactSha256: List<String>.filled(64, '2').join(),
      provenance: InviteSendLatencyProvenance(
        appGitRevision: List<String>.filled(40, '3').join(),
        appGitDirty: true,
        appSourceFingerprintSha256: List<String>.filled(64, '4').join(),
        nativeGitRevision: List<String>.filled(40, '5').join(),
        relayAddressCount: 2,
        relayAddressesSha256: List<String>.filled(64, '6').join(),
      ),
      generatedAt: DateTime.utc(2026, 7, 21),
    );
    expect(
      (tiedSummary['disposition']! as Map)['decision'],
      'h1_threshold_not_met',
      reason: 'a live/inbox tie is not exclusive live dominance',
    );

    final missingDelimiter = _copy(artifacts.primary);
    final missingPhases =
        (missingDelimiter['samples']! as List<Object?>).first
            as Map<String, dynamic>;
    ((missingPhases['phases']! as List<Object?>).first as Map<String, dynamic>)
        .remove('endAt');
    expect(
      _validate(missingDelimiter, artifacts.sibling).detail,
      contains('missing keys: endAt'),
      reason: 'omitting either phase delimiter must re-red the contract',
    );

    final swappedPhases = _copy(artifacts.primary);
    final phases =
        (((swappedPhases['samples']! as List<Object?>).first
                as Map<String, dynamic>)['phases']!
            as List<Object?>);
    final firstPhase = phases[0];
    phases[0] = phases[1];
    phases[1] = firstPhase;
    expect(
      _validate(swappedPhases, artifacts.sibling).detail,
      contains('name must equal pre_fanout'),
      reason: 'swapping phase order must re-red the contract',
    );

    final reusedOperation = _copy(artifacts.primary);
    final reusedSamples = reusedOperation['samples']! as List<Object?>;
    (reusedSamples[1] as Map<String, dynamic>)['operationId'] =
        (reusedSamples[0] as Map<String, dynamic>)['operationId'];
    expect(
      _validate(reusedOperation, artifacts.sibling).detail,
      contains('reuses operationId'),
      reason: 'an operation from another sample cannot satisfy correlation',
    );

    final unboundAttempt = _copy(artifacts.primary);
    (((unboundAttempt['samples']! as List<Object?>).first)
            as Map<String, dynamic>)['attemptId'] =
        'another-group:another-recipient';
    expect(
      _validate(unboundAttempt, artifacts.sibling).detail,
      contains('attemptId must bind groupId and recipientPeerId'),
    );
    final harnessSource = File(
      'integration_test/group_multi_device_real_harness.dart',
    ).readAsStringSync();
    expect(
      harnessSource,
      matches(RegExp(r'expect\(\s*attempt\.groupId,\s*groupId,')),
    );
    expect(
      harnessSource,
      matches(RegExp(r'expect\(\s*attempt\.peerId,\s*recipientPeerId,')),
    );
    expect(
      harnessSource,
      contains(r"'attemptId': '${attempt.groupId}:${attempt.peerId}'"),
      reason: 'attempt identity must come from the persisted repository row',
    );

    final contradictedAttemptError = _copy(artifacts.primary);
    (((contradictedAttemptError['samples']! as List<Object?>).first)
            as Map<String, dynamic>)['attemptLastError'] =
        'send_failed';
    expect(
      _validate(contradictedAttemptError, artifacts.sibling).detail,
      contains('sent/queued attempt requires attemptLastError=null'),
      reason: 'persisted result status and error must remain correlated',
    );

    final mislabeledOffline = _copy(artifacts.sibling);
    final offlineSibling =
        (mislabeledOffline['samples']! as List<Object?>)[10]!
            as Map<String, dynamic>;
    offlineSibling['preparedNodeStarted'] = true;
    offlineSibling['preparedRelayReady'] = true;
    expect(
      _validate(artifacts.primary, mislabeledOffline).detail,
      contains('offline condition requires a stopped, non-ready recipient'),
    );

    final staleConnectedOffline = _copy(artifacts.primary);
    ((staleConnectedOffline['samples']! as List<Object?>)[10]!
            as Map<String, dynamic>)['connectionState'] =
        'connected';
    expect(
      _validate(staleConnectedOffline, artifacts.sibling).failures,
      isEmpty,
      reason: 'sender connection state is evidence, not recipient liveness',
    );

    final unknownConnectionState = _copy(artifacts.primary);
    ((unknownConnectionState['samples']! as List<Object?>).first!
            as Map<String, dynamic>)['connectionState'] =
        'unknown';
    expect(
      _validate(unknownConnectionState, artifacts.sibling).failures,
      isEmpty,
      reason: 'a failed diagnostic read must not fabricate connection state',
    );

    final contradictedDirectAck = _copy(artifacts.primary);
    final directPhases =
        (((contradictedDirectAck['samples']! as List<Object?>).first!
                as Map<String, dynamic>)['phases']!
            as List<Object?>);
    (directPhases[_livePhaseIndex]! as Map<String, dynamic>)['outcome'] =
        'error';
    expect(
      _validate(contradictedDirectAck, artifacts.sibling).detail,
      contains('liveOutcome must match the live phase outcome'),
      reason: 'top-level direct ACK cannot contradict live phase evidence',
    );

    final contradictedInboxStore = _copy(artifacts.primary);
    final offlinePhases =
        (((contradictedInboxStore['samples']! as List<Object?>)[10]!
                as Map<String, dynamic>)['phases']!
            as List<Object?>);
    (offlinePhases[_inboxPhaseIndex]! as Map<String, dynamic>)['outcome'] =
        'not_stored';
    expect(
      _validate(contradictedInboxStore, artifacts.sibling).detail,
      contains('inboxOutcome must match the inbox phase outcome'),
      reason: 'confirmed custody cannot contradict inbox phase evidence',
    );

    final contradictedSignature = _copy(artifacts.primary);
    final signaturePhases =
        (((contradictedSignature['samples']! as List<Object?>).first!
                as Map<String, dynamic>)['phases']!
            as List<Object?>);
    (signaturePhases[_signPhaseIndex]! as Map<String, dynamic>)['outcome'] =
        'error';
    expect(
      _validate(contradictedSignature, artifacts.sibling).detail,
      contains('sign phase requires outcome=signed'),
      reason: 'a passing role cannot contradict its signing await evidence',
    );

    final missingCallerPath = _copy(artifacts.primary);
    (missingCallerPath['samples']! as List<Object?>).removeWhere(
      (sample) => (sample! as Map<String, dynamic>)['path'] == 'add',
    );
    expect(
      _validate(missingCallerPath, artifacts.sibling).detail,
      allOf(contains('exactly 30 samples'), contains('missing cell add|')),
      reason: 'both create and add callers are mandatory',
    );

    expect(
      validateInviteSendLatencyArtifacts(
        primaryArtifact: artifacts.primary,
        siblingArtifact: null,
        expectedRunId: 'run-267',
        expectedMode: 'baseline',
      ).detail,
      contains(r'$.sibling must be a JSON object'),
      reason: 'two successful role artifacts are mandatory',
    );
  });
}

InviteSendLatencyArtifactValidation _validate(
  Object? primary,
  Object? sibling,
) => validateInviteSendLatencyArtifacts(
  primaryArtifact: primary,
  siblingArtifact: sibling,
  expectedRunId: 'run-267',
  expectedMode: 'baseline',
);

({Map<String, dynamic> primary, Map<String, dynamic> sibling})
_validArtifacts() {
  final primarySamples = <Map<String, dynamic>>[];
  final siblingSamples = <Map<String, dynamic>>[];
  var sampleIndex = 0;
  for (final path in const <String>['create', 'add']) {
    for (final condition in const <String>[
      'online-warm',
      'online-cold',
      'offline',
    ]) {
      for (var repetition = 1; repetition <= 5; repetition += 1) {
        final operationId = 'operation-$sampleIndex';
        final groupId = 'group-$sampleIndex';
        final inviteId = 'invite-$sampleIndex';
        final base = DateTime.utc(
          2026,
          7,
          21,
        ).add(Duration(seconds: sampleIndex * 30));
        final usedInbox = condition == 'offline';
        final phases = <Map<String, dynamic>>[];
        for (
          var phaseIndex = 0;
          phaseIndex < inviteSendLatencyPhaseNames.length;
          phaseIndex += 1
        ) {
          final begin = base.add(Duration(milliseconds: phaseIndex * 2));
          final phaseName = inviteSendLatencyPhaseNames[phaseIndex];
          final end = phaseName == 'inbox' && condition != 'offline'
              ? begin
              : begin.add(const Duration(milliseconds: 1));
          phases.add(<String, dynamic>{
            'name': phaseName,
            'beginAt': begin.toIso8601String(),
            'endAt': end.toIso8601String(),
            'outcome': switch (phaseName) {
              'pre_fanout' => 'ready',
              'sign' => 'signed',
              'encrypt' => 'encrypted',
              'live' => usedInbox ? 'unacknowledged' : 'acknowledged',
              'inbox' => usedInbox ? 'stored' : 'skipped',
              'persistence' => 'persisted',
              'navigation_settlement' => 'settled',
              _ => throw StateError('unexpected latency phase $phaseName'),
            },
          });
        }
        primarySamples.add(<String, dynamic>{
          'operationId': operationId,
          'path': path,
          'condition': condition,
          'repetition': repetition,
          'groupId': groupId,
          'inviteId': inviteId,
          'recipientPeerId': 'peer-bob',
          'connectionState': usedInbox ? 'not_connected' : 'connected',
          'envelopeSha256': List<String>.filled(64, 'a').join(),
          'transport': usedInbox ? 'inbox' : 'direct',
          'applicationResult': usedInbox ? 'queued' : 'success',
          'attemptStatus': usedInbox ? 'queued' : 'sent',
          'attemptLastError': null,
          'deliveryKnowledge': usedInbox
              ? 'relay_custody_confirmed'
              : 'wire_ack_confirmed',
          'liveAcknowledged': !usedInbox,
          'liveOutcome': usedInbox ? 'unacknowledged' : 'acknowledged',
          'inboxAttemptCount': usedInbox ? 1 : 0,
          'confirmedInboxStoreCount': usedInbox ? 1 : 0,
          'inboxOutcome': usedInbox ? 'stored' : 'skipped',
          'attemptId': '$groupId:peer-bob',
          'caller': <String, dynamic>{
            'beginAt': base.toIso8601String(),
            'endAt': base
                .add(const Duration(milliseconds: 11))
                .toIso8601String(),
            'settledAt': base
                .add(const Duration(milliseconds: 13))
                .toIso8601String(),
          },
          'phases': phases,
        });
        siblingSamples.add(<String, dynamic>{
          'operationId': operationId,
          'path': path,
          'condition': condition,
          'repetition': repetition,
          'groupId': groupId,
          'inviteId': inviteId,
          'recipientPeerId': 'peer-bob',
          'pendingInviteId': inviteId,
          'eventCount': 1,
          'observationStatus': 'exact_event_observed',
          'observedLate': false,
          'observationWindowVersion': inviteSendLatencyObservationWindowVersion,
          'observationWindowMs': inviteSendLatencyObservationWindowMs,
          'observationStartedAt': base
              .add(const Duration(milliseconds: 14))
              .toIso8601String(),
          'observationDeadlineAt': base
              .add(
                Duration(
                  milliseconds: 14 + inviteSendLatencyObservationWindowMs,
                ),
              )
              .toIso8601String(),
          'observationCompletedAt': base
              .add(const Duration(milliseconds: 16))
              .toIso8601String(),
          'finalReconciledAt': base
              .add(const Duration(milliseconds: 20))
              .toIso8601String(),
          'drainAttemptCount': 1,
          'drainErrorCount': 0,
          'preparedNodeStarted': !usedInbox,
          'preparedRelayReady': !usedInbox,
          'preparedTransportPeerId': 'transport-peer-bob',
          'preparedStopCompleted': condition != 'online-warm',
          'preparedRestartCompleted': condition == 'online-cold',
          'observedAt': base
              .add(const Duration(milliseconds: 15))
              .toIso8601String(),
        });
        sampleIndex += 1;
      }
    }
  }

  Map<String, dynamic> roleArtifact(
    String role,
    String peerId,
    List<Map<String, dynamic>> samples,
  ) => <String, dynamic>{
    'schema': inviteSendLatencyArtifactSchema,
    'schemaVersion': inviteSendLatencyArtifactSchemaVersion,
    'scenario': inviteSendLatencyScenario,
    'mode': 'baseline',
    'runId': 'run-267',
    'role': role,
    'roleVerdict': 'pass',
    'identity': <String, dynamic>{
      'peerId': peerId,
      'transportPeerId': 'transport-$peerId',
    },
    'admissionCanary': <String, dynamic>{
      'kind': 'self_inbox_custody',
      'attemptCount': 1,
      'startedAt': DateTime.utc(2026, 7, 21).toIso8601String(),
      'stateObservedAt': DateTime.utc(
        2026,
        7,
        21,
        0,
        0,
        0,
        3,
      ).toIso8601String(),
      'storeCompletedAt': DateTime.utc(
        2026,
        7,
        21,
        0,
        0,
        0,
        1,
      ).toIso8601String(),
      'drainCompletedAt': DateTime.utc(
        2026,
        7,
        21,
        0,
        0,
        0,
        2,
      ).toIso8601String(),
      'completedAt': DateTime.utc(2026, 7, 21, 0, 0, 0, 4).toIso8601String(),
      'storeAccepted': true,
      'drainCompleted': true,
      'nodeStarted': true,
      'usabilityReady': true,
      'relayReady': true,
      'transportPeerId': 'transport-$peerId',
      'status': 'accepted',
    },
    'samples': samples,
  };

  return (
    primary: roleArtifact('primary', 'peer-alice', primarySamples),
    sibling: roleArtifact('sibling', 'peer-bob', siblingSamples),
  );
}

Map<String, dynamic> _copy(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

final int _livePhaseIndex = inviteSendLatencyPhaseNames.indexOf('live');
final int _inboxPhaseIndex = inviteSendLatencyPhaseNames.indexOf('inbox');
final int _signPhaseIndex = inviteSendLatencyPhaseNames.indexOf('sign');

void _makeOutcomeUnknownSample(
  Map<String, dynamic> primary,
  Map<String, dynamic> sibling, {
  required int sampleIndex,
}) {
  final primarySample =
      (primary['samples']! as List<Object?>)[sampleIndex]!
          as Map<String, dynamic>;
  primarySample['transport'] = 'none';
  primarySample['applicationResult'] = 'send_failed';
  primarySample['attemptStatus'] = 'needs_resend';
  primarySample['attemptLastError'] = 'send_failed';
  primarySample['deliveryKnowledge'] = 'outcome_unknown';
  primarySample['liveAcknowledged'] = false;
  primarySample['liveOutcome'] = 'unacknowledged';
  primarySample['inboxAttemptCount'] = 1;
  primarySample['confirmedInboxStoreCount'] = 0;
  primarySample['inboxOutcome'] = 'error';
  final phases = primarySample['phases']! as List<Object?>;
  (phases[_inboxPhaseIndex]! as Map<String, dynamic>)['outcome'] = 'error';

  final siblingSample =
      (sibling['samples']! as List<Object?>)[sampleIndex]!
          as Map<String, dynamic>;
  siblingSample['pendingInviteId'] = null;
  siblingSample['eventCount'] = 0;
  siblingSample['observationStatus'] = 'not_observed_within_window';
  siblingSample['observedLate'] = false;
  siblingSample['observedAt'] = null;
  final deadline = DateTime.parse(
    siblingSample['observationDeadlineAt'] as String,
  );
  siblingSample['observationCompletedAt'] = deadline
      .add(const Duration(milliseconds: 1))
      .toIso8601String();
  siblingSample['finalReconciledAt'] = deadline
      .add(const Duration(milliseconds: 2))
      .toIso8601String();
}

void _makeLiveInboxTie(
  Map<String, dynamic> primary,
  Map<String, dynamic> sibling,
) {
  final primarySamples = primary['samples']! as List<Object?>;
  final siblingSamples = sibling['samples']! as List<Object?>;
  for (final index in const <int>[10, 11, 12, 13]) {
    final sample = primarySamples[index]! as Map<String, dynamic>;
    final phases = sample['phases']! as List<Object?>;
    var cursor = DateTime.parse(
      (sample['caller']! as Map<String, dynamic>)['beginAt']! as String,
    );
    DateTime? persistenceEnd;
    DateTime? navigationEnd;
    for (final rawPhase in phases) {
      final phase = rawPhase! as Map<String, dynamic>;
      final phaseName = phase['name']! as String;
      final duration = phaseName == 'live' || phaseName == 'inbox'
          ? const Duration(milliseconds: 3101)
          : const Duration(milliseconds: 1);
      final end = cursor.add(duration);
      phase['beginAt'] = cursor.toUtc().toIso8601String();
      phase['endAt'] = end.toUtc().toIso8601String();
      if (phaseName == 'persistence') persistenceEnd = end;
      if (phaseName == 'navigation_settlement') navigationEnd = end;
      cursor = end.add(const Duration(milliseconds: 1));
    }
    final caller = sample['caller']! as Map<String, dynamic>;
    caller['beginAt'] =
        (phases.first! as Map<String, dynamic>)['beginAt']! as String;
    caller['endAt'] = persistenceEnd!.toUtc().toIso8601String();
    caller['settledAt'] = navigationEnd!.toUtc().toIso8601String();
    final sibling = siblingSamples[index]! as Map<String, dynamic>;
    final observationStartedAt = navigationEnd.add(
      const Duration(milliseconds: 1),
    );
    sibling['observationStartedAt'] = observationStartedAt
        .toUtc()
        .toIso8601String();
    sibling['observationDeadlineAt'] = observationStartedAt
        .add(Duration(milliseconds: inviteSendLatencyObservationWindowMs))
        .toUtc()
        .toIso8601String();
    sibling['observedAt'] = observationStartedAt
        .add(const Duration(milliseconds: 1))
        .toUtc()
        .toIso8601String();
    sibling['observationCompletedAt'] = observationStartedAt
        .add(const Duration(milliseconds: 2))
        .toUtc()
        .toIso8601String();
    sibling['finalReconciledAt'] = observationStartedAt
        .add(const Duration(milliseconds: 3))
        .toUtc()
        .toIso8601String();
  }
}
