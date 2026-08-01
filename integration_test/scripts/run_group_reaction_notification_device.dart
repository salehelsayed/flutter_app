#!/usr/bin/env dart

import 'dart:io';

import 'group_reaction_notification_device_criteria.dart';

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
  if (args.contains('--list-scenarios')) {
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
    return _validateArtifacts(Directory(validationDirectory), selected);
  }

  if (selected.length != 1) {
    throw const FormatException(
      'A device proof run requires one explicit --scenario <id>.',
    );
  }
  final scenario = selected.single;
  final sender = _requiredValue(args, '--sender');
  final recipient = _requiredValue(args, '--recipient');
  final artifactDirectory = Directory(_requiredValue(args, '--artifact-dir'));
  final selectionErrors = _validateDeviceSelection(
    scenario,
    sender: sender,
    recipient: recipient,
  );
  if (selectionErrors.isNotEmpty) {
    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: false,
      stage: 'topology',
      status: 'not_executed',
      detail: selectionErrors.join('; '),
    );
    stderr.writeln(
      'INVALID TOPOLOGY [${scenario.testCase}/${scenario.id}]: '
      '${selectionErrors.join('; ')}',
    );
    return 64;
  }

  // Scenario mode always performs a fresh capture. Pre-existing JSON is never
  // treated as proof because that would let a marker-only artifact bypass the
  // explicit device/provider/relay boundary. Historical evidence is accepted
  // only through the separate --validate-artifacts mode.
  for (final staleArtifact in <File>[
    File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}.json',
    ),
    File(
      '${artifactDirectory.path}${Platform.pathSeparator}${scenario.id}'
      '${Platform.pathSeparator}${scenario.id}.json',
    ),
  ]) {
    if (staleArtifact.existsSync()) staleArtifact.deleteSync();
  }
  final driver = File(_captureDriver);
  if (!driver.existsSync()) {
    await writeGroupReactionNotificationVerdict(
      outputDirectory: artifactDirectory,
      scenario: scenario.id,
      ok: false,
      stage: 'capture_driver',
      status: 'environment_blocked',
      detail: 'capture_driver_missing: ${driver.path}',
    );
    return 78;
  }
  final captureArgs = <String>[
    'run',
    driver.path,
    '--scenario',
    scenario.id,
    '--sender',
    sender,
    '--recipient',
    recipient,
    '--artifact-dir',
    artifactDirectory.path,
    for (final option in const <String>[
      '--relay-target',
      '--relay-key',
      '--service-account',
      '--staging-manifest',
      '--prebuilt-android-apk',
    ]) ...<String>[
      if (_valueFor(args, option) case final value?) ...<String>[option, value],
    ],
    if (args.contains('--no-child-builds')) '--no-child-builds',
    if (args.contains('--android-state-prepared')) '--android-state-prepared',
    if (args.contains('--verbose')) '--verbose',
    if (args.contains('--keep-build-artifacts')) '--keep-build-artifacts',
  ];
  final capture = await Process.start(
    Platform.resolvedExecutable,
    captureArgs,
    mode: ProcessStartMode.inheritStdio,
  );
  final captureExit = await capture.exitCode;
  if (captureExit != 0) return captureExit;

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
    final artifact = _artifactFor(root, scenario.id);
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

File _artifactFor(Directory directory, String scenario) {
  final direct = File(
    '${directory.path}${Platform.pathSeparator}$scenario.json',
  );
  if (direct.existsSync()) return direct;
  return File(
    '${directory.path}${Platform.pathSeparator}$scenario'
    '${Platform.pathSeparator}$scenario.json',
  );
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
    '[--relay-key <file>] [--service-account <file>] | '
    '--list-scenarios | --validate-artifacts <dir>',
  );
  exitCode = 64;
}
