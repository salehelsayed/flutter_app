#!/usr/bin/env dart

import 'dart:io';

import 'group_reaction_notification_device_criteria.dart';
import 'physical_device_capture_harness.dart';

const String _proofTest =
    'integration_test/group_announcement_reaction_notification_proof_test.dart';
const String _artifactValidator =
    'integration_test/scripts/'
    'validate_group_reaction_notification_artifacts.dart';
const String _captureDriver =
    'integration_test/scripts/'
    'capture_group_reaction_notification_device.dart';

Future<void> main(List<String> args) async {
  try {
    exitCode = await _run(args);
  } on FormatException catch (error) {
    _usageError(error.message);
  } on Object catch (error) {
    stderr.writeln('Plan 257 runner failed closed: ${error.runtimeType}.');
    exitCode = 70;
  }
}

Future<int> _run(List<String> args) async {
  final scenarioId = _valueFor(args, '--scenario') ?? 'all';
  final selected = _selectedScenarios(scenarioId);
  final diagnosticOnlyMessageWindow = args.contains(
    '--diagnostic-only-message-window',
  );
  final traceOnlyExistingState = args.contains('--trace-only-existing-state');
  final manualSendExistingState = args.contains('--manual-send-existing-state');
  final liveDiagnostic = args.contains('--live-diagnostic');
  if (manualSendExistingState && !traceOnlyExistingState) {
    throw const FormatException(
      '--manual-send-existing-state requires --trace-only-existing-state.',
    );
  }
  if (diagnosticOnlyMessageWindow && traceOnlyExistingState) {
    throw const FormatException(
      '--trace-only-existing-state cannot be combined with '
      '--diagnostic-only-message-window.',
    );
  }
  if (liveDiagnostic &&
      (!traceOnlyExistingState ||
          !manualSendExistingState ||
          !args.contains('--no-child-builds'))) {
    throw const FormatException(
      '--live-diagnostic requires --trace-only-existing-state, '
      '--manual-send-existing-state, and --no-child-builds.',
    );
  }
  if (args.contains('--list-scenarios')) {
    if (diagnosticOnlyMessageWindow) {
      throw const FormatException(
        '--diagnostic-only-message-window cannot be combined with scenario listing.',
      );
    }
    if (traceOnlyExistingState) {
      throw const FormatException(
        '--trace-only-existing-state cannot be combined with scenario listing.',
      );
    }
    // `dart run` may print build-hook progress without a trailing newline.
    // Start the machine-readable scenario block on a fresh line.
    stdout.writeln();
    for (final scenario in selected) {
      stdout.writeln(scenario.id);
    }
    return 0;
  }

  final validationDirectory = _valueFor(args, '--validate-artifacts');
  if (validationDirectory != null) {
    if (diagnosticOnlyMessageWindow) {
      throw const FormatException(
        'Standalone validation derives diagnostic mode from the artifact.',
      );
    }
    if (traceOnlyExistingState) {
      throw const FormatException(
        '--trace-only-existing-state cannot be combined with standalone '
        'authoritative artifact validation.',
      );
    }
    return _validateArtifacts(Directory(validationDirectory), selected);
  }

  final groupName = traceOnlyExistingState
      ? _requiredValue(args, '--group-name')
      : '';
  final existingTargetMarker = traceOnlyExistingState
      ? _requiredValue(args, '--existing-target-marker')
      : '';
  final finalTraceAuthorization = manualSendExistingState && !liveDiagnostic
      ? _requiredValue(args, '--plan398-final-attempt-authorization-id')
      : '';
  final finalRunnerProductReceiptSha256 =
      manualSendExistingState && !liveDiagnostic
      ? _requiredValue(args, '--plan398-final-runner-product-receipt-sha256')
      : '';
  final finalRunnerInstallTerminalSha256 =
      manualSendExistingState && !liveDiagnostic
      ? _requiredValue(args, '--plan398-final-runner-install-terminal-sha256')
      : '';
  final attempt02ReceiptSha256 = manualSendExistingState && !liveDiagnostic
      ? _requiredValue(args, '--plan398-attempt-02-receipt-sha256')
      : '';
  final digest = RegExp(r'^[0-9a-f]{64}$');
  if (manualSendExistingState &&
      !liveDiagnostic &&
      (finalTraceAuthorization != plan398ReviewedFinalTraceAuthorization ||
          !digest.hasMatch(finalRunnerProductReceiptSha256) ||
          !digest.hasMatch(finalRunnerInstallTerminalSha256) ||
          !digest.hasMatch(attempt02ReceiptSha256))) {
    throw const FormatException(
      'Final existing-state trace authority is missing or invalid.',
    );
  }
  if (liveDiagnostic &&
      <String>[
        '--plan398-final-attempt-authorization-id',
        '--plan398-final-runner-product-receipt-sha256',
        '--plan398-final-runner-install-terminal-sha256',
        '--plan398-attempt-02-receipt-sha256',
      ].any((option) => _valueFor(args, option) != null)) {
    throw const FormatException(
      '--live-diagnostic does not accept legacy final-attempt authority.',
    );
  }
  if (!traceOnlyExistingState &&
      (_valueFor(args, '--group-name') != null ||
          _valueFor(args, '--existing-target-marker') != null)) {
    throw const FormatException(
      '--group-name and --existing-target-marker require '
      '--trace-only-existing-state.',
    );
  }

  if (selected.length != 1) {
    throw const FormatException(
      'A device proof run requires one explicit --scenario <id>.',
    );
  }
  final scenario = selected.single;
  if (diagnosticOnlyMessageWindow &&
      scenario.id != iosChatGroupMessageAndReactionScenarioId) {
    throw const FormatException(
      '--diagnostic-only-message-window is restricted to the existing iOS chat-group scenario.',
    );
  }
  if (traceOnlyExistingState &&
      scenario.id != iosChatGroupMessageAndReactionScenarioId) {
    throw const FormatException(
      '--trace-only-existing-state is restricted to the existing iOS '
      'chat-group scenario.',
    );
  }
  final sender = _requiredValue(args, '--sender');
  final recipient = _requiredValue(args, '--recipient');
  final artifactDirectory = Directory(_requiredValue(args, '--artifact-dir'));
  final selectionErrors = _validateDeviceSelection(
    scenario,
    sender: sender,
    recipient: recipient,
  );
  if (selectionErrors.isNotEmpty) {
    if (traceOnlyExistingState) {
      await writePlan398ExistingStateTraceFailure(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        status: 'not_executed',
        stage: 'topology',
        detail: selectionErrors.join('; '),
        traceAttemptClaimed: false,
      );
    } else {
      await writeGroupReactionNotificationVerdict(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        ok: false,
        stage: 'topology',
        status: 'not_executed',
        detail: selectionErrors.join('; '),
      );
    }
    stderr.writeln(
      'INVALID TOPOLOGY [${scenario.testCase}/${scenario.id}]: '
      '${selectionErrors.join('; ')}',
    );
    return 64;
  }

  // Authoritative scenario mode always performs a fresh capture. The sibling
  // existing-state trace owns fixed one-attempt files and must fail on their
  // presence inside the capture child, never erase them here.
  if (!traceOnlyExistingState) {
    purgePhysicalDeviceCaptureArtifacts(artifactDirectory, scenario.id);
  }
  final driver = File(_captureDriver);
  if (!driver.existsSync()) {
    final detail = 'capture_driver_missing: ${driver.path}';
    if (traceOnlyExistingState) {
      await writePlan398ExistingStateTraceFailure(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        status: 'environment_blocked',
        stage: 'capture_driver',
        detail: detail,
        traceAttemptClaimed: false,
      );
    } else {
      await writeGroupReactionNotificationVerdict(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        ok: false,
        stage: 'capture_driver',
        status: 'environment_blocked',
        detail: detail,
      );
    }
    return 78;
  }
  final adapter = PhysicalDeviceCaptureAdapter(
    captureDriver: driver,
    scenarioId: scenario.id,
    senderDeviceId: sender,
    recipientDeviceId: recipient,
    artifactDirectory: artifactDirectory,
    additionalArguments: <String>[
      for (final option in const <String>[
        '--relay-target',
        '--relay-key',
        '--service-account',
        '--staging-manifest',
        '--prebuilt-android-apk',
        '--prebuilt-android-build-report',
        '--prebuilt-ios-bundle',
        '--prebuilt-ios-build-report',
        '--prebuilt-ios-setup-app',
        '--prebuilt-ios-setup-app-sha256',
      ]) ...<String>[
        if (_valueFor(args, option) case final value?) ...<String>[
          option,
          value,
        ],
      ],
      if (traceOnlyExistingState || args.contains('--no-child-builds'))
        '--no-child-builds',
      if (diagnosticOnlyMessageWindow) '--diagnostic-only-message-window',
      if (traceOnlyExistingState) '--trace-only-existing-state',
      if (manualSendExistingState) '--manual-send-existing-state',
      if (liveDiagnostic) '--live-diagnostic',
      if (traceOnlyExistingState) ...<String>[
        '--group-name',
        groupName,
        '--existing-target-marker',
        existingTargetMarker,
      ],
      if (manualSendExistingState && !liveDiagnostic) ...<String>[
        '--plan398-final-attempt-authorization-id',
        finalTraceAuthorization,
        '--plan398-final-runner-product-receipt-sha256',
        finalRunnerProductReceiptSha256,
        '--plan398-final-runner-install-terminal-sha256',
        finalRunnerInstallTerminalSha256,
        '--plan398-attempt-02-receipt-sha256',
        attempt02ReceiptSha256,
      ],
      if (args.contains('--android-state-prepared')) '--android-state-prepared',
      if (args.contains('--verbose')) '--verbose',
      if (args.contains('--keep-build-artifacts')) '--keep-build-artifacts',
    ],
  );
  final capture = await runPhysicalDeviceCapture(
    adapter,
    outputMode: PhysicalDeviceCaptureOutputMode.inheritStdio,
  );
  if (capture.launchError case final error?) {
    if (!traceOnlyExistingState) throw error;
    await writePlan398ExistingStateTraceFailure(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      status: 'environment_blocked',
      stage: 'capture_driver',
      detail: 'capture_driver_launch_failed',
      traceAttemptClaimed: false,
      stackType: error.runtimeType.toString(),
    );
    return 78;
  }
  final captureExit = capture.exitCode!;
  if (captureExit != 0) {
    if (traceOnlyExistingState) {
      final failure = File(
        '${artifactDirectory.path}${Platform.pathSeparator}'
        '$plan398ExistingStateTraceFailureFileName',
      );
      if (!failure.existsSync()) {
        final claim = File(
          '${artifactDirectory.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceClaimFileName',
        );
        await writePlan398ExistingStateTraceFailure(
          outputDirectory: artifactDirectory,
          scenario: scenario.id,
          status: 'capture_failed',
          stage: 'capture_driver',
          detail: 'capture_driver_exited_$captureExit',
          traceAttemptClaimed: claim.existsSync(),
        );
      }
    }
    return captureExit;
  }

  if (traceOnlyExistingState) {
    final separator = Platform.pathSeparator;
    final terminalReceipt = File(
      '${artifactDirectory.path}$separator'
      '$plan398ExistingStateTraceTerminalReceiptFileName',
    );
    final terminalValidation =
        await validatePlan398ExistingStateTraceTerminalReceipt(
          receiptFile: terminalReceipt,
          expectedScenario: scenario.id,
          expectedAuthorityMode: liveDiagnostic
              ? plan398LiveDiagnosticAuthorityMode
              : plan398LegacyFinalAttemptAuthorityMode,
          expectedAuthorization: liveDiagnostic
              ? null
              : finalTraceAuthorization,
          expectedFinalRunnerProductReceiptSha256: liveDiagnostic
              ? null
              : finalRunnerProductReceiptSha256,
          expectedFinalRunnerInstallTerminalSha256: liveDiagnostic
              ? null
              : finalRunnerInstallTerminalSha256,
          expectedAttempt02ReceiptSha256: liveDiagnostic
              ? null
              : attempt02ReceiptSha256,
          expectedPixelLogFileName: plan398PixelLogFileName(sender),
          requireSuccessfulTrace: true,
        );
    if (!terminalValidation.ok) {
      stderr.writeln(
        'Existing-state terminal receipt rejected: '
        '${terminalValidation.detail}',
      );
      await writePlan398ExistingStateTraceFailure(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        status: 'capture_failed',
        stage: 'terminal_receipt_validation',
        detail: 'existing_state_terminal_receipt_rejected',
        traceAttemptClaimed: true,
      );
      return 1;
    }
    final validation = await validatePlan398ExistingStateTraceArtifact(
      artifactFile: File(
        '${artifactDirectory.path}${separator}plan398_existing_state_trace.json',
      ),
      traceAttemptMarker: File(
        '${artifactDirectory.path}'
        '${separator}plan398_existing_state_trace_claim.json',
      ),
      expectedSenderDeviceId: sender,
      expectedRecipientDeviceId: recipient,
    );
    if (!validation.ok) {
      stderr.writeln('Existing-state trace rejected: ${validation.detail}');
      await writePlan398ExistingStateTraceFailure(
        outputDirectory: artifactDirectory,
        scenario: scenario.id,
        status: 'capture_failed',
        stage: 'artifact_validation',
        detail: 'existing_state_trace_artifact_rejected',
        traceAttemptClaimed: true,
      );
      return 1;
    }
    stdout.writeln('Plan 398 existing-state trace artifact validated.');
    return 0;
  }

  return _validateArtifacts(
    artifactDirectory,
    <GroupReactionNotificationScenario>[scenario],
    expectedSenderDeviceId: sender,
    expectedRecipientDeviceId: recipient,
  );
}

Future<int> _validateArtifacts(
  Directory root,
  List<GroupReactionNotificationScenario> selected, {
  String? expectedSenderDeviceId,
  String? expectedRecipientDeviceId,
}) async {
  var failed = false;
  for (final scenario in selected) {
    final artifact = physicalDeviceCaptureArtifact(root, scenario.id);
    final verdictDirectory = artifact.parent;
    if (!artifact.existsSync()) {
      failed = true;
      await writeGroupReactionNotificationVerdict(
        outputDirectory: verdictDirectory,
        scenario: scenario.id,
        ok: false,
        stage: 'artifact_validation',
        status: 'failed',
        detail: 'missing authoritative artifact ${artifact.path}',
      );
      stderr.writeln('Missing artifact: ${artifact.path}');
      continue;
    }

    final validator = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      _artifactValidator,
      '--scenario',
      scenario.id,
      '--artifact',
      artifact.path,
      if (expectedSenderDeviceId != null) ...<String>[
        '--sender',
        expectedSenderDeviceId,
      ],
      if (expectedRecipientDeviceId != null) ...<String>[
        '--recipient',
        expectedRecipientDeviceId,
      ],
    ]);
    _forwardProcessResult(validator);
    if (validator.exitCode != 0) {
      failed = true;
      await writeGroupReactionNotificationVerdict(
        outputDirectory: verdictDirectory,
        scenario: scenario.id,
        ok: false,
        stage: 'artifact_validation',
        status: 'failed',
        detail: 'standalone artifact validator exited ${validator.exitCode}',
      );
      continue;
    }

    final proof = await Process.run('flutter', <String>[
      'test',
      '-d',
      'flutter-tester',
      _proofTest,
      // Anchored regex, not --plain-name: substring selection also runs any
      // scenario whose name nests this id (android_group_reaction_recipient is
      // a prefix of the TC-12 background_connected scenario) against the wrong
      // artifact.
      '--name',
      '^${RegExp.escape(scenario.id)}\$',
      '--dart-define=MKNOON_257_PROOF_ARTIFACT=${artifact.path}',
    ]);
    _forwardProcessResult(proof);
    if (proof.exitCode != 0) {
      failed = true;
      await writeGroupReactionNotificationVerdict(
        outputDirectory: verdictDirectory,
        scenario: scenario.id,
        ok: false,
        stage: 'proof_binding',
        status: 'failed',
        detail: 'named proof test exited ${proof.exitCode}',
      );
      continue;
    }

    await writeGroupReactionNotificationVerdict(
      outputDirectory: verdictDirectory,
      scenario: scenario.id,
      ok: true,
      stage: 'artifact_validation',
      status: 'passed',
      detail:
          'standalone validator and named proof accepted authoritative '
          'evidence',
    );
    stdout.writeln('Plan 257 proof artifact validated for ${scenario.id}.');
  }
  return failed ? 1 : 0;
}

void _forwardProcessResult(ProcessResult result) {
  final processOut = '${result.stdout}'.trim();
  final processError = '${result.stderr}'.trim();
  if (processOut.isNotEmpty) stdout.writeln(processOut);
  if (processError.isNotEmpty) stderr.writeln(processError);
}

List<String> _validateDeviceSelection(
  GroupReactionNotificationScenario scenario, {
  required String sender,
  required String recipient,
}) {
  final failures = <String>[];
  if (sender == recipient) {
    failures.add('sender and recipient device IDs must differ');
  }
  for (final entry in <(String, String)>[
    ('sender', sender),
    ('recipient', recipient),
  ]) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{4,128}$').hasMatch(entry.$2)) {
      failures.add('${entry.$1} is not a safe explicit device ID');
    }
  }
  final senderIsEmulator = RegExp(r'^emulator-[0-9]+$').hasMatch(sender);
  final recipientIsEmulator = RegExp(r'^emulator-[0-9]+$').hasMatch(recipient);
  final senderIsIos = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$',
  ).hasMatch(sender);
  final recipientIsIos = RegExp(
    r'^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}$',
  ).hasMatch(recipient);
  if (scenario.senderDeviceKind == 'emulator' && !senderIsEmulator) {
    failures.add('sender must be an Android emulator for ${scenario.id}');
  }
  if (scenario.senderDeviceKind == 'physical' && senderIsEmulator) {
    failures.add('sender must be physical for ${scenario.id}');
  }
  if (scenario.senderPlatform == 'android' && senderIsIos) {
    failures.add('sender must be Android for ${scenario.id}');
  }
  if (scenario.recipientDeviceKind == 'physical' && recipientIsEmulator) {
    failures.add('recipient must be physical for ${scenario.id}');
  }
  if (scenario.recipientPlatform == 'ios' && !recipientIsIos) {
    failures.add('recipient must be a physical iOS device for ${scenario.id}');
  }
  if (scenario.recipientPlatform == 'android' && recipientIsIos) {
    failures.add('recipient must be Android for ${scenario.id}');
  }
  return failures;
}

String _requiredValue(List<String> args, String name) {
  final value = _valueFor(args, name);
  if (value == null) throw FormatException('$name is required.');
  return value;
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw FormatException('Missing value for $name.');
      }
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      final value = argument.substring(name.length + 1);
      if (value.isEmpty) throw FormatException('Missing value for $name.');
      return value;
    }
  }
  return null;
}

List<GroupReactionNotificationScenario> _selectedScenarios(String id) {
  if (id == 'all') return groupReactionNotificationScenarios;
  final scenario = groupReactionNotificationScenario(id);
  if (scenario == null) {
    throw FormatException(
      'Unknown --scenario "$id". Expected all or one of: '
      '${groupReactionNotificationScenarios.map((value) => value.id).join(', ')}.',
    );
  }
  return <GroupReactionNotificationScenario>[scenario];
}

void _usageError(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run integration_test/scripts/'
    'run_group_reaction_notification_device.dart --scenario <id> '
    '--sender <device-id> --recipient <device-id> --artifact-dir <dir> '
    '--staging-manifest <redacted-json> [--relay-target <ssh-target>] '
    '[--relay-key <file>] [--service-account <file>] '
    '[--trace-only-existing-state [--manual-send-existing-state '
    '[--live-diagnostic]] '
    '--group-name <name> '
    '--existing-target-marker <marker>] | '
    '--list-scenarios | --validate-artifacts <dir>',
  );
  exitCode = 64;
}
