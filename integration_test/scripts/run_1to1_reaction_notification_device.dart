#!/usr/bin/env dart

import 'dart:io';

const String _proofTest =
    'integration_test/one_to_one_reaction_notification_proof_test.dart';
const String _headProvenanceCaptureDriver =
    'integration_test/scripts/capture_1to1_reaction_head_provenance.dart';
const String _androidBackgroundCryptoPreflightDriver =
    'integration_test/scripts/capture_android_background_crypto_preflight.dart';
const String _closureCaptureDriver =
    'integration_test/scripts/capture_1to1_reaction_notification_closure.dart';

class _Scenario {
  const _Scenario({
    required this.id,
    required this.testCase,
    required this.requiresSender,
    required this.summary,
  });

  final String id;
  final String testCase;
  final bool requiresSender;
  final String summary;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    id: 'head_provenance',
    testCase: 'TC-00',
    requiresSender: true,
    summary:
        'clean-current-build reaction producer, relay/provider, card, and tap provenance',
  ),
  _Scenario(
    id: 'android_typed_reaction_smoke',
    testCase: 'TC-13-core-smoke',
    requiresSender: true,
    summary:
        'killed-recipient typed reaction card from a working-tree build, '
        'driven by real sender UI',
  ),
  _Scenario(
    id: 'android_durable_reaction_background_connected',
    testCase: 'TC-DURABLE-DIRECT-REACTION',
    requiresSender: true,
    summary:
        'alive-but-backgrounded recipient, durable direct-reaction arm '
        'executed rather than deferred to the non-durable fallback',
  ),
  _Scenario(
    id: 'android_background_crypto_preflight',
    testCase: 'TC-07',
    requiresSender: false,
    summary:
        'real FCM headless-engine crypto-plugin registration and main-callback preservation',
  ),
  _Scenario(
    id: 'android_first_wake_profile_aot',
    testCase: 'TC-393-06',
    requiresSender: true,
    summary:
        'warmed killed profile-AOT receiver, successful policy eligibility, '
        'measured native-entry tail, and one real FCM direct-text alert',
  ),
  _Scenario(
    id: 'android_message_unread_lifecycle',
    testCase: 'TC-16',
    requiresSender: true,
    summary:
        'ordinary-message notification dismissal/tap and unread-orbit lifecycle',
  ),
  _Scenario(
    id: 'android_physical_recipient',
    testCase: 'TC-13',
    requiresSender: true,
    summary:
        'physical Android reaction notification, replacement, tap, and unread-negative proof',
  ),
  _Scenario(
    id: 'ios_physical_recipient',
    testCase: 'TC-14',
    requiresSender: true,
    summary:
        'physical iOS APNs/NSE reaction notification, tap, and unread-negative proof',
  ),
];

Future<void> main(List<String> args) async {
  final scenarioId = _valueFor(args, '--scenario') ?? 'all';
  final selected = _selectedScenarios(scenarioId);

  if (args.contains('--list-scenarios')) {
    for (final scenario in selected) {
      stdout.writeln(scenario.id);
    }
    return;
  }

  final validationDir = _valueFor(args, '--validate-artifacts');
  if (validationDir != null) {
    await _validateArtifacts(Directory(validationDir), selected);
    return;
  }

  if (selected.length != 1) {
    _usageError('A device proof run requires one explicit --scenario <id>.');
  }

  final scenario = selected.single;
  final measurementOnly = args.contains('--measurement-only');
  final requireAlert = args.contains('--require-alert');
  if (scenario.id == 'android_first_wake_profile_aot') {
    if (measurementOnly == requireAlert) {
      _usageError(
        'android_first_wake_profile_aot requires exactly one of '
        '--measurement-only or --require-alert.',
      );
    }
  } else if (measurementOnly || requireAlert) {
    _usageError(
      '--measurement-only/--require-alert are owned by '
      'android_first_wake_profile_aot.',
    );
  }
  final sender = _valueFor(args, '--sender');
  final recipient = _valueFor(args, '--recipient');
  final artifactDir = _valueFor(args, '--artifact-dir');
  if (scenario.requiresSender && (sender == null || sender.trim().isEmpty)) {
    _usageError('${scenario.id} requires --sender <device-id>.');
  }
  if (recipient == null || recipient.trim().isEmpty) {
    _usageError('${scenario.id} requires --recipient <device-id>.');
  }
  if (artifactDir == null || artifactDir.trim().isEmpty) {
    _usageError('${scenario.id} requires --artifact-dir <dir>.');
  }

  final artifactDirectory = Directory(artifactDir);
  final artifact = _artifactFor(artifactDirectory, scenario.id);

  if (!artifact.existsSync()) {
    final captureDriverPath = switch (scenario.id) {
      'head_provenance' => _headProvenanceCaptureDriver,
      'android_typed_reaction_smoke' => _headProvenanceCaptureDriver,
      'android_durable_reaction_background_connected' =>
        _headProvenanceCaptureDriver,
      'android_first_wake_profile_aot' => _headProvenanceCaptureDriver,
      'android_background_crypto_preflight' =>
        _androidBackgroundCryptoPreflightDriver,
      'android_message_unread_lifecycle' ||
      'android_physical_recipient' ||
      'ios_physical_recipient' => _closureCaptureDriver,
      _ => null,
    };
    if (captureDriverPath == null) {
      stderr.writeln(
        'ENVIRONMENT BLOCKED [${scenario.testCase}/${scenario.id}]: '
        'missing redacted device-proof artifact ${artifact.path}.',
      );
      stderr.writeln(
        'Artifact capture for ${scenario.id} remains fail-closed until its '
        'named proof driver is implemented.',
      );
      exit(78);
    }

    final captureDriver = File(captureDriverPath);
    if (!captureDriver.existsSync()) {
      stderr.writeln(
        'ENVIRONMENT BLOCKED [${scenario.testCase}/${scenario.id}]: '
        'missing capture driver '
        '${captureDriver.path}.',
      );
      exit(78);
    }
    final captureArgs = <String>[
      'run',
      captureDriver.path,
      '--scenario',
      scenario.id,
      if (scenario.requiresSender) ...['--sender', sender!],
      '--recipient',
      recipient,
      '--artifact-dir',
      artifactDirectory.path,
      for (final option in const [
        '--relay-target',
        '--relay-key',
        '--head-source-root',
        '--service-account',
        '--staging-manifest',
        '--capture-manifest',
        '--prebuilt-android-apk',
      ]) ...[
        if (_valueFor(args, option) case final value?) ...[option, value],
      ],
      if (args.contains('--no-child-builds')) '--no-child-builds',
      if (args.contains('--android-state-prepared')) '--android-state-prepared',
      if (scenario.id == 'android_typed_reaction_smoke') '--live-typed-smoke',
      if (scenario.id == 'android_durable_reaction_background_connected')
        '--durable-background-connected',
      if (scenario.id == 'android_first_wake_profile_aot')
        '--first-wake-profile-aot',
      if (args.contains('--measurement-only')) '--measurement-only',
      if (args.contains('--require-alert')) '--require-alert',
      if (args.contains('--verbose')) '--verbose',
      if (args.contains('--keep-build-artifacts')) '--keep-build-artifacts',
    ];
    final capture = await Process.start(
      'dart',
      captureArgs,
      mode: ProcessStartMode.inheritStdio,
    );
    final captureExit = await capture.exitCode;
    if (captureExit != 0) {
      exit(captureExit);
    }
  }

  await _validateArtifacts(artifactDirectory, selected);
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        _usageError('Missing value for $name.');
      }
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      final value = argument.substring(name.length + 1);
      if (value.isEmpty) {
        _usageError('Missing value for $name.');
      }
      return value;
    }
  }
  return null;
}

List<_Scenario> _selectedScenarios(String id) {
  if (id == 'all') {
    return _scenarios;
  }
  final selected = _scenarios.where((scenario) => scenario.id == id).toList();
  if (selected.isEmpty) {
    _usageError(
      'Unknown --scenario "$id". Expected all or one of: '
      '${_scenarios.map((scenario) => scenario.id).join(', ')}.',
    );
  }
  return selected;
}

Future<void> _validateArtifacts(
  Directory artifactDir,
  List<_Scenario> selected,
) async {
  for (final scenario in selected) {
    final artifact = _artifactFor(artifactDir, scenario.id);
    if (!artifact.existsSync()) {
      stderr.writeln('Missing artifact: ${artifact.path}');
      exit(66);
    }
    final result = await Process.start('flutter', <String>[
      'test',
      '-d',
      'flutter-tester',
      _proofTest,
      '--plain-name',
      scenario.id,
      '--dart-define=MKNOON_256_PROOF_ARTIFACT=${artifact.path}',
    ], mode: ProcessStartMode.inheritStdio);
    final exitCode = await result.exitCode;
    if (exitCode != 0) {
      exit(exitCode);
    }
    stdout.writeln('Plan-256 proof artifact validated for ${scenario.id}.');
  }
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

Never _usageError(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run integration_test/scripts/'
    'run_1to1_reaction_notification_device.dart '
    '--scenario <id> [--sender <device-id>] --recipient <device-id> '
    '--artifact-dir <dir> [--staging-manifest <json>] '
    '[--measurement-only | --require-alert] '
    '[--capture-manifest <json>] | --list-scenarios | '
    '--validate-artifacts <dir>',
  );
  exit(64);
}
