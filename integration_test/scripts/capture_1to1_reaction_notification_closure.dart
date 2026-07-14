#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'reaction_notification_proof_support.dart';

const _stagingSchema = 'mknoon.plan256.staging-prerequisites.v1';
const _defaultRelayTarget = 'ubuntu@mknoun.xyz';
const _defaultRelayKey = 'se.pem';
const _defaultServiceAccount =
    'mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json';

Future<void> main(List<String> args) async {
  final scenario = _valueFor(args, '--scenario');
  final sender = _valueFor(args, '--sender');
  final recipient = _valueFor(args, '--recipient');
  final artifactPath = _valueFor(args, '--artifact-dir');
  if (scenario == null ||
      sender == null ||
      recipient == null ||
      artifactPath == null ||
      !_closureScenarios.contains(scenario)) {
    _usage();
  }

  final stagingPath =
      _valueFor(args, '--staging-manifest') ??
      Platform.environment['MKNOON_256_STAGING_MANIFEST'];
  final capturePath =
      _valueFor(args, '--capture-manifest') ??
      Platform.environment['MKNOON_256_CAPTURE_MANIFEST'];
  if (stagingPath == null || stagingPath.trim().isEmpty) {
    stderr.writeln(
      'ENVIRONMENT BLOCKED [$scenario]: a redacted --staging-manifest is '
      'required; this driver never assumes a production relay/provider.',
    );
    exit(78);
  }
  if (capturePath == null || capturePath.trim().isEmpty) {
    stderr.writeln(
      'ENVIRONMENT BLOCKED [$scenario]: --capture-manifest from the bounded '
      'staging automation is required; success evidence is never synthesized.',
    );
    exit(78);
  }

  final campaign = _ClosureCapture(
    scenario: scenario,
    sender: sender,
    recipient: recipient,
    artifactDirectory: Directory(artifactPath).absolute,
    stagingManifest: File(stagingPath).absolute,
    captureManifest: File(capturePath).absolute,
    relayTarget: _valueFor(args, '--relay-target') ?? _defaultRelayTarget,
    relayKey: File(_valueFor(args, '--relay-key') ?? _defaultRelayKey).absolute,
    serviceAccount: File(
      _valueFor(args, '--service-account') ??
          Platform.environment['FIREBASE_SERVICE_ACCOUNT'] ??
          _defaultServiceAccount,
    ).absolute,
    verbose: args.contains('--verbose'),
  );

  try {
    await campaign.run();
  } on _CaptureFailure catch (failure, stackTrace) {
    campaign.writeFailure(failure, stackTrace);
    stderr.writeln(
      '${failure.environmentBlocked ? 'ENVIRONMENT BLOCKED' : 'CAPTURE FAILED'} '
      '[$scenario/${failure.stage}]: ${failure.message}',
    );
    exit(failure.environmentBlocked ? 78 : 1);
  }
}

const _closureScenarios = <String>{
  'android_physical_recipient',
  'ios_physical_recipient',
  'android_message_unread_lifecycle',
};

class _CaptureFailure implements Exception {
  const _CaptureFailure(
    this.stage,
    this.message, {
    this.environmentBlocked = false,
  });

  final String stage;
  final String message;
  final bool environmentBlocked;
}

class _CommandOutput {
  const _CommandOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ClosureCapture {
  _ClosureCapture({
    required this.scenario,
    required this.sender,
    required this.recipient,
    required this.artifactDirectory,
    required this.stagingManifest,
    required this.captureManifest,
    required this.relayTarget,
    required this.relayKey,
    required this.serviceAccount,
    required this.verbose,
  });

  final String scenario;
  final String sender;
  final String recipient;
  final Directory artifactDirectory;
  final File stagingManifest;
  final File captureManifest;
  final String relayTarget;
  final File relayKey;
  final File serviceAccount;
  final bool verbose;

  String stage = 'preflight';

  Future<void> run() async {
    stage = 'preflight';
    if (sender == recipient) {
      throw const _CaptureFailure(
        'preflight',
        'sender and recipient must be distinct explicit device ids',
      );
    }
    await _verifyLiveDevices();
    final staging = await _readJson(stagingManifest, environmentBlocked: true);
    _verifyStagingPrerequisites(staging);
    await _verifyRelayReadOnly(staging);
    if (scenario != 'ios_physical_recipient' && !serviceAccount.existsSync()) {
      throw const _CaptureFailure(
        'preflight',
        'FCM service-account prerequisite is unavailable',
        environmentBlocked: true,
      );
    }

    stage = 'capture_evidence';
    if (!captureManifest.existsSync()) {
      throw const _CaptureFailure(
        'capture_evidence',
        'bounded staging automation capture manifest is unavailable',
        environmentBlocked: true,
      );
    }
    final raw = await captureManifest.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const _CaptureFailure(
        'capture_evidence',
        'capture manifest root must be an object',
      );
    }
    final artifact = Map<String, dynamic>.from(decoded);
    final validation = validatePlan256ArtifactContract(
      scenario: scenario,
      artifact: artifact,
      rawJson: raw,
    );
    if (!validation.isValid) {
      throw _CaptureFailure(
        'capture_evidence',
        'capture contract rejected: ${validation.errors.join('; ')}',
      );
    }
    _verifyCaptureMatchesRun(artifact, staging);
    await _verifyFreshCapture(artifact);

    stage = 'redacted_artifact';
    await artifactDirectory.create(recursive: true);
    final evidence = artifact['evidence'] as List<dynamic>;
    final copiedEvidence = <Map<String, dynamic>>[];
    final usedNames = <String>{};
    for (final value in evidence) {
      final record = Map<String, dynamic>.from(value as Map);
      final source = _evidenceFile(record['path'] as String);
      if (!await source.exists()) {
        throw _CaptureFailure(
          stage,
          'missing source evidence kind=${record['kind']}',
        );
      }
      final bytes = await source.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      if (digest != record['sha256'] || bytes.length != record['bytes']) {
        throw _CaptureFailure(
          stage,
          'source evidence digest/length mismatch kind=${record['kind']}',
        );
      }
      _rejectSecrets(utf8.decode(bytes), 'evidence kind=${record['kind']}');
      final kind = record['kind'] as String;
      final extension = source.path.endsWith('.json') ? '.json' : '.log';
      var outputName = '$kind$extension';
      var suffix = 2;
      while (!usedNames.add(outputName)) {
        outputName = '${kind}_${suffix++}$extension';
      }
      await source.copy('${artifactDirectory.path}/$outputName');
      copiedEvidence.add(<String, dynamic>{...record, 'path': outputName});
    }

    final outputArtifact = <String, dynamic>{
      ...artifact,
      'evidence': copiedEvidence,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(outputArtifact);
    _rejectSecrets(encoded, 'output artifact');
    final output = File('${artifactDirectory.path}/$scenario.json');
    final pending = File('${output.path}.pending');
    await pending.writeAsString(encoded, flush: true);
    await pending.rename(output.path);
    stdout.writeln('PASS: $scenario captured at ${output.path}');
  }

  void writeFailure(_CaptureFailure failure, StackTrace stackTrace) {
    artifactDirectory.createSync(recursive: true);
    File(
      '${artifactDirectory.path}/${scenario}_failure.json',
    ).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'scenario': scenario,
        'status': 'failed',
        'stage': failure.stage,
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'environmentBlocked': failure.environmentBlocked,
        'errorType': failure.runtimeType.toString(),
        'stackType': stackTrace.runtimeType.toString(),
      }),
    );
  }

  Future<void> _verifyLiveDevices() async {
    final flutterDevices = await _runChecked('flutter', const <String>[
      'devices',
      '--machine',
    ], environmentBlocked: true);
    final decoded = jsonDecode(flutterDevices.stdout);
    if (decoded is! List) {
      throw const _CaptureFailure(
        'preflight',
        'flutter devices --machine returned an invalid inventory',
        environmentBlocked: true,
      );
    }
    final inventory = decoded
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(growable: false);
    Map<String, dynamic>? find(String id) {
      for (final device in inventory) {
        if (device['id'] == id) return device;
      }
      return null;
    }

    final senderDevice = find(sender);
    final recipientDevice = find(recipient);
    if (senderDevice == null || recipientDevice == null) {
      throw const _CaptureFailure(
        'preflight',
        'one or more explicit targets are absent from live Flutter discovery',
        environmentBlocked: true,
      );
    }
    if (senderDevice['targetPlatform']?.toString().contains('android') !=
        true) {
      throw const _CaptureFailure(
        'preflight',
        'sender must be a live Android target',
        environmentBlocked: true,
      );
    }
    final needsIos = scenario == 'ios_physical_recipient';
    final expectedFragment = needsIos ? 'ios' : 'android';
    if (recipientDevice['targetPlatform']?.toString().contains(
          expectedFragment,
        ) !=
        true) {
      throw _CaptureFailure(
        'preflight',
        'recipient is not a live $expectedFragment target',
        environmentBlocked: true,
      );
    }

    final adb = await _runChecked('adb', const <String>[
      'devices',
    ], environmentBlocked: true);
    if (!adb.stdout.contains('$sender\tdevice')) {
      throw const _CaptureFailure(
        'preflight',
        'sender is absent from adb devices',
        environmentBlocked: true,
      );
    }
    if (!needsIos && !adb.stdout.contains('$recipient\tdevice')) {
      throw const _CaptureFailure(
        'preflight',
        'recipient is absent from adb devices',
        environmentBlocked: true,
      );
    }
    if (needsIos) {
      final ios = await _runChecked('xcrun', const <String>[
        'xctrace',
        'list',
        'devices',
      ], environmentBlocked: true);
      final physicalLine = ios.stdout
          .split('\n')
          .where((line) => line.contains(recipient))
          .where((line) => !line.toLowerCase().contains('simulator'))
          .toList(growable: false);
      if (physicalLine.isEmpty) {
        throw const _CaptureFailure(
          'preflight',
          'recipient is not a live physical iOS target',
          environmentBlocked: true,
        );
      }
    }
  }

  void _verifyStagingPrerequisites(Map<String, dynamic> staging) {
    void requireEqual(String key, Object? expected) {
      if (staging[key] != expected) {
        throw _CaptureFailure(
          'preflight',
          'staging prerequisite $key must equal $expected',
          environmentBlocked: true,
        );
      }
    }

    requireEqual('schema', _stagingSchema);
    requireEqual('environment', 'staging');
    requireEqual('relayActive', true);
    requireEqual('providerConfigured', true);
    requireEqual('providerProbeSucceeded', true);
    requireEqual('candidateBuildInstalled', true);
    requireEqual('productionDeploymentPerformed', false);
    requireEqual(
      'provider',
      scenario == 'ios_physical_recipient' ? 'apns' : 'fcm',
    );
    if (scenario != 'android_message_unread_lifecycle') {
      requireEqual('typedReactionEnabled', true);
    }
    for (final key in const <String>[
      'candidateAppRevision',
      'candidateRelayRevision',
    ]) {
      final value = staging[key];
      if (value is! String || value.trim().isEmpty) {
        throw _CaptureFailure(
          'preflight',
          'staging prerequisite $key is missing',
          environmentBlocked: true,
        );
      }
    }
    final relaySha = staging['candidateRelaySha256'];
    if (relaySha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(relaySha)) {
      throw const _CaptureFailure(
        'preflight',
        'staging candidateRelaySha256 is invalid',
        environmentBlocked: true,
      );
    }
  }

  Future<void> _verifyRelayReadOnly(Map<String, dynamic> staging) async {
    if (!relayKey.existsSync()) {
      throw const _CaptureFailure(
        'preflight',
        'relay read-only SSH key is unavailable',
        environmentBlocked: true,
      );
    }
    final active = await _ssh(const <String>[
      'systemctl',
      'is-active',
      'relay-server',
    ]);
    if (active.stdout.trim() != 'active') {
      throw const _CaptureFailure(
        'preflight',
        'staging relay is not active',
        environmentBlocked: true,
      );
    }
    final version = await _ssh(const <String>[
      '/usr/local/bin/relay-server',
      'version',
    ]);
    final digest = await _ssh(const <String>[
      'sha256sum',
      '/usr/local/bin/relay-server',
    ]);
    final actualSha = digest.stdout.trim().split(RegExp(r'\s+')).first;
    if (!version.stdout.contains(
          staging['candidateRelayRevision'].toString(),
        ) ||
        actualSha != staging['candidateRelaySha256']) {
      throw const _CaptureFailure(
        'preflight',
        'live relay revision/digest does not match staging prerequisites',
        environmentBlocked: true,
      );
    }
  }

  void _verifyCaptureMatchesRun(
    Map<String, dynamic> artifact,
    Map<String, dynamic> staging,
  ) {
    final topology = Map<String, dynamic>.from(artifact['topology'] as Map);
    final capturedSender = Map<String, dynamic>.from(topology['sender'] as Map);
    final capturedRecipient = Map<String, dynamic>.from(
      topology['recipient'] as Map,
    );
    if (capturedSender['deviceId'] != sender ||
        capturedRecipient['deviceId'] != recipient) {
      throw const _CaptureFailure(
        'capture_evidence',
        'capture device ids do not match the explicit live run ids',
      );
    }
    final environment = Map<String, dynamic>.from(
      artifact['environment'] as Map,
    );
    for (final key in const <String>[
      'candidateAppRevision',
      'candidateRelayRevision',
      'candidateRelaySha256',
      'provider',
      'providerConfigured',
      'candidateBuildInstalled',
    ]) {
      if (environment[key] != staging[key]) {
        throw _CaptureFailure(
          'capture_evidence',
          'capture environment $key does not match staging prerequisites',
        );
      }
    }
  }

  Future<void> _verifyFreshCapture(Map<String, dynamic> artifact) async {
    final capturedAt = DateTime.parse(artifact['capturedAt'] as String).toUtc();
    final now = DateTime.now().toUtc();
    if (capturedAt.isAfter(now.add(const Duration(minutes: 5))) ||
        capturedAt.isBefore(now.subtract(const Duration(hours: 24)))) {
      throw const _CaptureFailure(
        'capture_evidence',
        'capture timestamp is outside the bounded 24-hour proof window',
      );
    }
  }

  File _evidenceFile(String path) {
    final file = File(path);
    if (file.isAbsolute) return file;
    return File('${captureManifest.parent.path}/$path');
  }

  void _rejectSecrets(String text, String source) {
    for (final forbidden in const <String>[
      '"fcmToken":',
      '"apnsToken":',
      '"secretKey":',
      '"ciphertext":',
      '"senderPeerId":',
      '"recipientPeerId":',
    ]) {
      if (text.contains(forbidden)) {
        throw _CaptureFailure(stage, '$source contains forbidden $forbidden');
      }
    }
  }

  Future<Map<String, dynamic>> _readJson(
    File file, {
    required bool environmentBlocked,
  }) async {
    if (!file.existsSync()) {
      throw _CaptureFailure(
        stage,
        '${file.path} is unavailable',
        environmentBlocked: environmentBlocked,
      );
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      return Map<String, dynamic>.from(decoded as Map);
    } on Object {
      throw _CaptureFailure(
        stage,
        '${file.path} is not a valid JSON object',
        environmentBlocked: environmentBlocked,
      );
    }
  }

  Future<_CommandOutput> _ssh(List<String> remoteArgs) =>
      _runChecked('ssh', <String>[
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=15',
        '-i',
        relayKey.path,
        relayTarget,
        _shellJoin(remoteArgs),
      ], environmentBlocked: true);

  Future<_CommandOutput> _runChecked(
    String executable,
    List<String> args, {
    required bool environmentBlocked,
  }) async {
    final result = await Process.run(executable, args);
    final output = _CommandOutput(
      result.exitCode,
      result.stdout.toString(),
      result.stderr.toString(),
    );
    if (verbose) {
      stdout.write(output.stdout);
      stderr.write(output.stderr);
    }
    if (output.exitCode != 0) {
      throw _CaptureFailure(
        stage,
        '$executable prerequisite command exited ${output.exitCode}',
        environmentBlocked: environmentBlocked,
      );
    }
    return output;
  }
}

String _shellJoin(List<String> values) => values
    .map((value) {
      if (RegExp(r'^[A-Za-z0-9_./:@+-]+$').hasMatch(value)) return value;
      return "'${value.replaceAll("'", "'\\''")}'";
    })
    .join(' ');

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1);
    }
  }
  return null;
}

Never _usage() {
  stderr.writeln(
    'Usage: dart run integration_test/scripts/'
    'capture_1to1_reaction_notification_closure.dart '
    '--scenario <android_physical_recipient|ios_physical_recipient|'
    'android_message_unread_lifecycle> --sender <live-id> '
    '--recipient <live-id> --artifact-dir <dir> '
    '--staging-manifest <redacted-json> '
    '--capture-manifest <automation-json> [--relay-target <ssh-target>] '
    '[--relay-key <file>] [--service-account <file>]',
  );
  exit(64);
}
