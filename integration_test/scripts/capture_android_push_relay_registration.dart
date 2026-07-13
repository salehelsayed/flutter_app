#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '_android_app_package.dart';
import 'reaction_notification_proof_support.dart';

const String _debugApkPath = 'build/app/outputs/flutter-apk/app-debug.apk';
const String _postNotificationsPermission =
    'android.permission.POST_NOTIFICATIONS';

Future<void> main(List<String> args) async {
  if (args.contains('--dry-run')) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'schema': backgroundCryptoPushRelayRegistrationArtifactSchema,
        'mode': 'dry-run',
        'productionMain': true,
        'e2eTestMode': false,
        'compileGated': true,
        'contactsDevice': false,
        'contactsRelay': false,
        'containsSecrets': false,
      }),
    );
    return;
  }
  final recipient = _valueFor(args, '--recipient');
  final artifactDir = _valueFor(args, '--artifact-dir');
  final refreshArtifactPath = _valueFor(args, '--refresh-artifact');
  final currentTokenDiagnosticPath = _valueFor(
    args,
    '--current-token-diagnostic',
  );
  final authorizationPaths = <String?>[
    refreshArtifactPath,
    currentTokenDiagnosticPath,
  ].whereType<String>().toList(growable: false);
  if (recipient == null ||
      artifactDir == null ||
      authorizationPaths.length != 1) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/'
      'capture_android_push_relay_registration.dart '
      '--recipient <android-id> --artifact-dir <dir> '
      '(--refresh-artifact <accepted-refresh-artifact> | '
      '--current-token-diagnostic <accepted-current-token-artifact>)',
    );
    exit(64);
  }
  final usesCurrentTokenDiagnostic = currentTokenDiagnosticPath != null;
  final authorizationFile = File(authorizationPaths.single).absolute;
  late final List<int> authorizationBytes;
  late final Map<String, Object?> authorization;
  try {
    final stat = authorizationFile.statSync();
    if (stat.type != FileSystemEntityType.file ||
        stat.size <= 0 ||
        stat.size > 64 * 1024) {
      throw const FormatException('authorization artifact size rejected');
    }
    authorizationBytes = List<int>.unmodifiable(
      authorizationFile.readAsBytesSync(),
    );
    authorization = usesCurrentTokenDiagnostic
        ? parseBackgroundCryptoCurrentTokenDiagnosticAuthorization(
            authorizationBytes,
            now: DateTime.now().toUtc(),
          )
        : parseBackgroundCryptoRelayRegistrationAuthorization(
            authorizationBytes,
            now: DateTime.now().toUtc(),
          );
  } on Object {
    stderr.writeln('Accepted token authorization contract rejected.');
    exit(64);
  }

  final campaign = _RelayRegistrationCampaign(
    recipient: recipient,
    artifactDir: Directory(artifactDir)..createSync(recursive: true),
    authorizationArtifactBytes: authorizationBytes,
    authorization: authorization,
    usesCurrentTokenDiagnostic: usesCurrentTokenDiagnostic,
  );
  final result = await campaign.run();
  if (!result) exit(1);
}

class _RelayRegistrationFailure implements Exception {
  const _RelayRegistrationFailure(this.stage, this.reason);

  final String stage;
  final String reason;
}

class _CommandOutput {
  const _CommandOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _RelayRegistrationCampaign {
  _RelayRegistrationCampaign({
    required this.recipient,
    required this.artifactDir,
    required List<int> authorizationArtifactBytes,
    required this.authorization,
    required this.usesCurrentTokenDiagnostic,
  }) : authorizationArtifactBytes = List<int>.unmodifiable(
         authorizationArtifactBytes,
       ),
       authorizationArtifactSha256 = sha256
           .convert(authorizationArtifactBytes)
           .toString(),
       appPackage = resolveAndroidAppPackage();

  final String recipient;
  final Directory artifactDir;
  final List<int> authorizationArtifactBytes;
  final String authorizationArtifactSha256;
  final Map<String, Object?> authorization;
  final bool usesCurrentTokenDiagnostic;
  final String appPackage;

  String stage = 'preflight';
  late String _targetPlatform;
  late int _androidSdk;
  Directory? _backupDirectory;
  final List<File> _installedAppApks = <File>[];
  final List<String> _restoredInstalledHashes = <String>[];
  File? _localApkBackup;
  bool _localApkExisted = false;
  bool _backupCaptured = false;
  bool _replacementAttempted = false;
  bool _permissionCaptured = false;
  bool _permissionInitiallyGranted = false;
  String? _commandId;
  String? _commandSha256;
  String? _gateACommandGenerationId;
  Map<String, Object?>? _flowEvidence;
  Map<String, Object?>? _receiptEvidence;
  bool _privateReceiptModeVerified = false;
  bool _privateReceiptRead = false;
  int? _privateReceiptBytes;
  String? _privateReceiptSha256;
  String? _baselineNotificationHash;
  String? _finalNotificationHash;

  String get _passArtifactPath =>
      '${artifactDir.path}/android_push_relay_registration.json';
  String get _failureArtifactPath =>
      '${artifactDir.path}/android_push_relay_registration_failure.json';

  Future<bool> run() async {
    _RelayRegistrationFailure? primary;
    _RelayRegistrationFailure? cleanup;
    _RelayRegistrationFailure? restoration;
    try {
      await _runPrimary();
    } on _RelayRegistrationFailure catch (failure) {
      primary = failure;
    } on Object {
      primary = _RelayRegistrationFailure(stage, 'unexpected_primary_failure');
    }
    try {
      await _cleanupProofState();
    } on _RelayRegistrationFailure catch (failure) {
      cleanup = failure;
    } on Object {
      cleanup = const _RelayRegistrationFailure(
        'cleanup',
        'unexpected_cleanup_failure',
      );
    }
    try {
      await _restoreExactHostAndCandidateState();
    } on _RelayRegistrationFailure catch (failure) {
      restoration = failure;
    } on Object {
      restoration = const _RelayRegistrationFailure(
        'restoration',
        'unexpected_restoration_failure',
      );
    }
    if (primary == null && cleanup == null && restoration == null) {
      try {
        _revalidateAuthorization('authorization_before_pass');
      } on _RelayRegistrationFailure catch (failure) {
        primary = failure;
      }
    }
    if (primary != null || cleanup != null || restoration != null) {
      await _deletePassArtifact();
      await _writeFailure(primary, cleanup, restoration);
      stderr.writeln('PUSH RELAY REGISTRATION PROOF FAILED');
      return false;
    }
    stage = 'artifact_write';
    await _writePassArtifact();
    final failure = File(_failureArtifactPath);
    if (await failure.exists()) await failure.delete();
    stdout.writeln('PASS: push relay registration at $_passArtifactPath');
    return true;
  }

  Future<void> _runPrimary() async {
    stage = 'device_preflight';
    await _requireDevice();
    if (!await _processAndTaskAbsent()) {
      throw const _RelayRegistrationFailure(
        'device_preflight',
        'initial_app_not_idle',
      );
    }
    _baselineNotificationHash = await _notificationSnapshotHash();

    stage = 'backup';
    await _backupInstalledAndLocalApks();

    stage = 'build';
    await _runChecked('flutter', <String>[
      'build',
      'apk',
      '--debug',
      '--target',
      'lib/main.dart',
      '--dart-define=MKNOON_PUSH_RELAY_REGISTRATION_PROOF=true',
      '--dart-define=FDC_FLOW_LOG=1',
      '--target-platform',
      _targetPlatform,
    ]);
    final apk = File(_debugApkPath);
    if (!await apk.exists() || await apk.length() == 0) {
      throw const _RelayRegistrationFailure('build', 'apk_missing');
    }

    stage = 'candidate_install';
    _replacementAttempted = true;
    await _adb(<String>['install', '-r', '-t', '-d', apk.absolute.path]);
    await _forceStopAndRequireAbsent();
    await _removeAndVerifyProofFiles();
    _revalidateAuthorization('authorization_before_command_staging');
    stage = 'command_staging';
    await _stageProofCommand();

    stage = 'production_cold_launch';
    await _adb(<String>['logcat', '-c']);
    await _adbShell(<String>[
      'am',
      'start',
      '-W',
      '-n',
      '$appPackage/.MainActivity',
    ]);
    final log = await _waitForProofLog();
    _flowEvidence = _parseProofLog(log);

    stage = 'receipt_validation';
    await _requirePrivateFileMode(
      backgroundCryptoAppPrivatePushRelayReceiptPath,
      '600',
    );
    _privateReceiptModeVerified = true;
    final receipt = await _runAs(<String>[
      'cat',
      backgroundCryptoAppPrivatePushRelayReceiptPath,
    ], suppressVerbose: true);
    final receiptBytes = utf8.encode(receipt.stdout);
    _privateReceiptRead = true;
    _privateReceiptBytes = receiptBytes.length;
    _privateReceiptSha256 = sha256.convert(receiptBytes).toString();
    _revalidateAuthorization('authorization_before_receipt');
    try {
      _receiptEvidence = _parseProofReceipt(
        receiptBytes,
        now: DateTime.now().toUtc(),
      );
    } on FormatException catch (error) {
      throw _RelayRegistrationFailure(
        'receipt_validation',
        _receiptFailureReason(error),
      );
    }
    await _runAs(<String>[
      'test',
      '!',
      '-e',
      backgroundCryptoAppPrivatePushRelayCommandPath,
    ]);
    if (_flowEvidence!['accountIdentitySha256'] !=
            _receiptEvidence!['accountIdentitySha256'] ||
        _flowEvidence!['transportIdentitySha256'] !=
            _receiptEvidence!['transportIdentitySha256']) {
      throw const _RelayRegistrationFailure(
        'receipt_validation',
        'identity_binding_mismatch',
      );
    }
  }

  Future<void> _requireDevice() async {
    final devices = await _runChecked('adb', <String>['devices']);
    if (!devices.stdout.contains('$recipient\tdevice')) {
      throw const _RelayRegistrationFailure(
        'device_preflight',
        'target_unavailable',
      );
    }
    final abi = (await _adbShell(<String>[
      'getprop',
      'ro.product.cpu.abi',
    ])).stdout.trim();
    _targetPlatform = switch (abi) {
      'arm64-v8a' => 'android-arm64',
      'armeabi-v7a' => 'android-arm',
      'x86_64' => 'android-x64',
      _ => throw const _RelayRegistrationFailure(
        'device_preflight',
        'unsupported_abi',
      ),
    };
    _androidSdk =
        int.tryParse(
          (await _adbShell(<String>[
            'getprop',
            'ro.build.version.sdk',
          ])).stdout.trim(),
        ) ??
        0;
    if (_androidSdk <= 0) {
      throw const _RelayRegistrationFailure(
        'device_preflight',
        'sdk_unavailable',
      );
    }
  }

  Future<void> _backupInstalledAndLocalApks() async {
    final packagePaths = (await _adbShell(<String>['pm', 'path', appPackage]))
        .stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length))
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (packagePaths.isEmpty) {
      throw const _RelayRegistrationFailure('backup', 'candidate_missing');
    }
    await _captureNotificationPermission();
    final backup = await Directory.systemTemp.createTemp(
      'mknoon-push-relay-proof-',
    );
    _backupDirectory = backup;
    final localApk = File(_debugApkPath);
    _localApkExisted = await localApk.exists();
    if (_localApkExisted) {
      _localApkBackup = await localApk.copy('${backup.path}/local.apk');
    }
    for (var index = 0; index < packagePaths.length; index++) {
      final file = File('${backup.path}/installed-$index.apk');
      await _adb(<String>['pull', packagePaths[index], file.path]);
      if (!await file.exists() || await file.length() == 0) {
        throw const _RelayRegistrationFailure('backup', 'apk_pull_failed');
      }
      _installedAppApks.add(file);
    }
    _backupCaptured = true;
  }

  Future<void> _captureNotificationPermission() async {
    _permissionInitiallyGranted = _androidSdk < 33
        ? true
        : await _isNotificationPermissionGranted();
    _permissionCaptured = true;
    if (_androidSdk >= 33 && !_permissionInitiallyGranted) {
      throw const _RelayRegistrationFailure(
        'backup',
        'notification_permission_not_pregranted',
      );
    }
  }

  Future<bool> _isNotificationPermissionGranted() async {
    final dump = await _adbShell(<String>[
      'dumpsys',
      'package',
      appPackage,
    ], suppressVerbose: true);
    final match = RegExp(
      r'android\.permission\.POST_NOTIFICATIONS:\s+granted=(true|false)',
    ).firstMatch(dump.stdout);
    if (match == null) {
      throw const _RelayRegistrationFailure(
        'permission',
        'permission_state_unavailable',
      );
    }
    return match.group(1) == 'true';
  }

  Future<void> _stageProofCommand() async {
    final now = DateTime.now().toUtc();
    final commandId =
        'tc256-relay-registration-${now.microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(0x7fffffff)}';
    final gateACommandGenerationId = usesCurrentTokenDiagnostic
        ? 'tc256-gate-a-command-${now.microsecondsSinceEpoch}-'
              '${Random.secure().nextInt(0x7fffffff)}'
        : null;
    final bytes = utf8.encode(
      jsonEncode(
        usesCurrentTokenDiagnostic
            ? <String, Object?>{
                'schema': backgroundCryptoPushRelayRegistrationCommandSchemaV2,
                'commandId': commandId,
                'issuedAt': now.toIso8601String(),
                'maxAgeSeconds': 300,
                'tokenSha256': authorization['tokenSha256'],
                'authorizationKind': authorization['authorizationKind'],
                'authorizationArtifactSha256':
                    authorization['authorizationArtifactSha256'],
                'gateACommandGenerationId': gateACommandGenerationId,
              }
            : <String, Object?>{
                'schema': backgroundCryptoPushRelayRegistrationCommandSchema,
                'commandId': commandId,
                'issuedAt': now.toIso8601String(),
                'maxAgeSeconds': 300,
                'tokenSha256': authorization['tokenSha256'],
                'tokenGenerationId': authorization['tokenGenerationId'],
                'refreshArtifactSha256': authorization['refreshArtifactSha256'],
              },
      ),
    );
    if (bytes.isEmpty || bytes.length > 16 * 1024) {
      throw const _RelayRegistrationFailure(
        'command_staging',
        'command_size_rejected',
      );
    }
    final receipt = await copyBackgroundCryptoCommandBytesToAppPrivateFile(
      bytes: bytes,
      run: _runPrivateFileTransport,
      appPrivatePath: backgroundCryptoAppPrivatePushRelayCommandPath,
    );
    await _runAs(<String>[
      'chmod',
      '0600',
      backgroundCryptoAppPrivatePushRelayCommandPath,
    ]);
    await _requirePrivateFileMode(
      backgroundCryptoAppPrivatePushRelayCommandPath,
      '600',
    );
    _commandId = commandId;
    _commandSha256 = receipt.sha256;
    _gateACommandGenerationId = gateACommandGenerationId;
  }

  void _revalidateAuthorization(String checkStage) {
    try {
      if (usesCurrentTokenDiagnostic) {
        revalidateBackgroundCryptoCurrentTokenDiagnosticAuthorization(
          authorizationArtifactBytes,
          now: DateTime.now().toUtc(),
          expectedArtifactSha256: authorizationArtifactSha256,
          expectedAuthorization: authorization,
        );
      } else {
        revalidateBackgroundCryptoRelayRegistrationAuthorization(
          authorizationArtifactBytes,
          now: DateTime.now().toUtc(),
          expectedArtifactSha256: authorizationArtifactSha256,
          expectedAuthorization: authorization,
        );
      }
    } on FormatException {
      throw _RelayRegistrationFailure(
        checkStage,
        'token_authorization_expired_or_changed',
      );
    }
  }

  Map<String, Object?> _parseProofLog(String log) {
    if (usesCurrentTokenDiagnostic) {
      return backgroundCryptoPushRelayProofEvidenceFromLogV2(
        log,
        commandId: _commandId!,
        commandSha256: _commandSha256!,
        tokenSha256: authorization['tokenSha256']! as String,
        authorizationArtifactSha256:
            authorization['authorizationArtifactSha256']! as String,
        gateACommandGenerationId: _gateACommandGenerationId!,
      );
    }
    return backgroundCryptoPushRelayProofEvidenceFromLog(
      log,
      commandId: _commandId!,
      commandSha256: _commandSha256!,
      tokenSha256: authorization['tokenSha256']! as String,
      tokenGenerationId: authorization['tokenGenerationId']! as String,
      refreshArtifactSha256: authorization['refreshArtifactSha256']! as String,
    );
  }

  Map<String, Object?> _parseProofReceipt(
    List<int> receiptBytes, {
    required DateTime now,
  }) {
    if (usesCurrentTokenDiagnostic) {
      return parseBackgroundCryptoPushRelayRegistrationReceiptV2(
        receiptBytes,
        now: now,
        commandId: _commandId!,
        commandSha256: _commandSha256!,
        tokenSha256: authorization['tokenSha256']! as String,
        authorizationArtifactSha256:
            authorization['authorizationArtifactSha256']! as String,
        gateACommandGenerationId: _gateACommandGenerationId!,
      );
    }
    return parseBackgroundCryptoPushRelayRegistrationReceipt(
      receiptBytes,
      now: now,
      commandId: _commandId!,
      commandSha256: _commandSha256!,
      tokenSha256: authorization['tokenSha256']! as String,
      tokenGenerationId: authorization['tokenGenerationId']! as String,
      refreshArtifactSha256: authorization['refreshArtifactSha256']! as String,
    );
  }

  Future<BackgroundCryptoTransportResult> _runPrivateFileTransport(
    BackgroundCryptoTransportInvocation invocation,
  ) async {
    final result = switch (invocation.channel) {
      BackgroundCryptoTransportChannel.adb => await _adb(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
      BackgroundCryptoTransportChannel.shell => await _adbShell(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
      BackgroundCryptoTransportChannel.runAs => await _runAs(
        invocation.arguments,
        allowFailure: true,
        suppressVerbose: true,
      ),
    };
    return BackgroundCryptoTransportResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  Future<void> _requirePrivateFileMode(String path, String expected) async {
    final result = await _runAs(<String>[
      'stat',
      '-c',
      '%a',
      path,
    ], suppressVerbose: true);
    if (result.stdout.trim() != expected) {
      throw const _RelayRegistrationFailure(
        'private_file_mode',
        'private_file_mode_rejected',
      );
    }
  }

  Future<String> _waitForProofLog() async {
    final deadline = DateTime.now().add(const Duration(minutes: 3));
    while (DateTime.now().isBefore(deadline)) {
      final log = (await _adb(<String>[
        'logcat',
        '-d',
      ], suppressVerbose: true)).stdout;
      if (log.contains('PUSH_REGISTER_RELAY_PROOF_COMPLETE') &&
          log.contains('PUSH_REGISTER_COORDINATOR_SUCCESS')) {
        try {
          _parseProofLog(log);
          return log;
        } on FormatException {
          // The exact finite sequence is the only successful terminal state.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const _RelayRegistrationFailure(
      'production_cold_launch',
      'typed_success_timeout',
    );
  }

  Future<void> _cleanupProofState() async {
    if (!_replacementAttempted) return;
    stage = 'cleanup';
    await _forceStopAndRequireAbsent();
    _finalNotificationHash = await _notificationSnapshotHash();
    if (_baselineNotificationHash != _finalNotificationHash) {
      throw const _RelayRegistrationFailure(
        'cleanup',
        'notification_state_changed',
      );
    }
    await _removeAndVerifyProofFiles();
  }

  Future<void> _removeAndVerifyProofFiles() async {
    const paths = <String>[
      backgroundCryptoAppPrivatePushRelayCommandPath,
      backgroundCryptoAppPrivatePushRelayReceiptPath,
      backgroundCryptoAppPrivatePushRelayReceiptTempPath,
    ];
    await _runAs(<String>['rm', '-f', ...paths]);
    for (final path in paths) {
      await _runAs(<String>['test', '!', '-e', path]);
    }
  }

  Future<void> _restoreExactHostAndCandidateState() async {
    stage = 'restoration';
    if (_replacementAttempted && _installedAppApks.isNotEmpty) {
      final args = _installedAppApks.length == 1
          ? <String>['install', '-r', '-t', '-d', _installedAppApks.single.path]
          : <String>[
              'install-multiple',
              '-r',
              '-t',
              '-d',
              ..._installedAppApks.map((file) => file.path),
            ];
      await _adb(args);
      await _forceStopAndRequireAbsent();
      final restoredPaths =
          (await _adbShell(<String>['pm', 'path', appPackage])).stdout
              .split('\n')
              .map((line) => line.trim())
              .where((line) => line.startsWith('package:'))
              .map((line) => line.substring('package:'.length))
              .where((path) => path.isNotEmpty)
              .toList(growable: false);
      if (restoredPaths.length != _installedAppApks.length) {
        throw const _RelayRegistrationFailure(
          'restoration',
          'restored_apk_count_mismatch',
        );
      }
      final expected = <String>[];
      for (final file in _installedAppApks) {
        expected.add(await _sha256File(file));
      }
      final actual = <String>[];
      for (final path in restoredPaths) {
        final output = await _adbShell(<String>['sha256sum', path]);
        final value = output.stdout.trim().split(RegExp(r'\s+')).first;
        if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
          throw const _RelayRegistrationFailure(
            'restoration',
            'restored_apk_hash_unavailable',
          );
        }
        actual.add(value.toLowerCase());
      }
      expected.sort();
      actual.sort();
      if (jsonEncode(expected) != jsonEncode(actual)) {
        throw const _RelayRegistrationFailure(
          'restoration',
          'restored_apk_hash_mismatch',
        );
      }
      _restoredInstalledHashes.addAll(actual);
    }
    if (_permissionCaptured && _androidSdk >= 33) {
      final current = await _isNotificationPermissionGranted();
      if (current != _permissionInitiallyGranted) {
        await _adbShell(<String>[
          'pm',
          _permissionInitiallyGranted ? 'grant' : 'revoke',
          appPackage,
          _postNotificationsPermission,
        ]);
      }
      if (await _isNotificationPermissionGranted() !=
          _permissionInitiallyGranted) {
        throw const _RelayRegistrationFailure(
          'restoration',
          'permission_restore_failed',
        );
      }
    }
    if (_backupCaptured) {
      final localApk = File(_debugApkPath);
      final backup = _localApkBackup;
      if (backup != null && await backup.exists()) {
        await localApk.parent.create(recursive: true);
        await backup.copy(localApk.path);
        if (await _sha256File(backup) != await _sha256File(localApk)) {
          throw const _RelayRegistrationFailure(
            'restoration',
            'local_apk_hash_mismatch',
          );
        }
      } else if (!_localApkExisted && await localApk.exists()) {
        await localApk.delete();
      }
    }
    await _removeAndVerifyProofFiles();
    final backupDirectory = _backupDirectory;
    if (backupDirectory != null && await backupDirectory.exists()) {
      await backupDirectory.delete(recursive: true);
      if (await backupDirectory.exists()) {
        throw const _RelayRegistrationFailure(
          'restoration',
          'backup_directory_survived',
        );
      }
    }
  }

  Future<void> _forceStopAndRequireAbsent() async {
    await _adbShell(<String>['am', 'force-stop', appPackage]);
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (await _processAndTaskAbsent()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw const _RelayRegistrationFailure(
      'quiescence',
      'process_or_task_survived',
    );
  }

  Future<bool> _processAndTaskAbsent() async {
    final pid = await _adbShell(
      <String>['pidof', appPackage],
      allowFailure: true,
      suppressVerbose: true,
    );
    final activities = await _adbShell(<String>[
      'dumpsys',
      'activity',
      'activities',
    ], suppressVerbose: true);
    return androidProcessAndTaskAreAbsent(
      pidExitCode: pid.exitCode,
      pidOutput: pid.stdout,
      pidStderr: pid.stderr,
      activityDump: activities.stdout,
      packageName: appPackage,
    );
  }

  Future<String> _notificationSnapshotHash() async {
    final dump = await _adbShell(<String>[
      'dumpsys',
      'notification',
      '--noredact',
    ], suppressVerbose: true);
    final cards = extractActiveNotificationCards(
      dump.stdout,
      packageName: appPackage,
    );
    final safe =
        cards
            .map(
              (card) => <String, Object?>{
                'id': card.id,
                'category': card.category,
                'routeSha256': sha256
                    .convert(utf8.encode(card.routePayload ?? ''))
                    .toString(),
                'titleSha256': sha256
                    .convert(utf8.encode(card.title))
                    .toString(),
                'bodySha256': sha256.convert(utf8.encode(card.body)).toString(),
              },
            )
            .toList(growable: false)
          ..sort(
            (left, right) => jsonEncode(left).compareTo(jsonEncode(right)),
          );
    return sha256.convert(utf8.encode(jsonEncode(safe))).toString();
  }

  Future<void> _writePassArtifact() async {
    final capturedAt = DateTime.now().toUtc();
    final artifact = <String, Object?>{
      'schema': usesCurrentTokenDiagnostic
          ? backgroundCryptoPushRelayRegistrationArtifactSchemaV2
          : backgroundCryptoPushRelayRegistrationArtifactSchema,
      'status': 'passed',
      'capturedAt': capturedAt.toIso8601String(),
      'mode': 'instrumented-production-main',
      'recipient': <String, Object?>{
        'deviceId': recipient,
        'platform': 'android',
        'targetPlatform': _targetPlatform,
      },
      if (usesCurrentTokenDiagnostic)
        'currentTokenAuthorization': authorization
      else
        'refreshAuthorization': authorization,
      'command': <String, Object?>{
        'commandId': _commandId,
        if (usesCurrentTokenDiagnostic)
          'gateACommandGenerationId': _gateACommandGenerationId,
        'commandSha256': _commandSha256,
        'mode': '0600',
        'deleted': true,
      },
      'flowEvidence': _flowEvidence,
      'receipt': _receiptEvidence,
      'relayClaim': 'relay_frame_status_ok',
      'relayPersistenceProvenByThisGate': false,
      'downstreamDeliveryStillRequired': true,
      'productionPath': <String, Object?>{
        'entrypoint': 'lib/main.dart',
        'kE2ETestMode': false,
        'compileGate': 'MKNOON_PUSH_RELAY_REGISTRATION_PROOF',
        'byteIdenticalToRestoredCandidate': false,
      },
      'notificationState': <String, Object?>{
        'baselineSha256': _baselineNotificationHash,
        'finalSha256': _finalNotificationHash,
        'unchanged': _baselineNotificationHash == _finalNotificationHash,
      },
      'cleanup': <String, Object?>{
        'appIdle': true,
        'commandDeleted': true,
        'receiptDeleted': true,
        'receiptTempDeleted': true,
        'notificationStateUnchanged': true,
        'installedCandidateRestored': true,
        'installedCandidateBytesVerified': true,
        'installedCandidateApkSha256': _restoredInstalledHashes,
        'localBuildArtifactRestoredToPriorState': true,
        'localBuildArtifactBytesVerified': true,
        'notificationPermissionRestored': true,
        'notificationPermissionInitiallyGranted': _permissionInitiallyGranted,
        'backupDirectoryDeleted': true,
      },
      'intentionalPersistentEffects': const <String>[
        'relay_registration_frame_accepted',
        'push_token_store_updated',
      ],
      'redaction': const <String, Object?>{
        'rawTokenPersisted': false,
        'peerIdPersisted': false,
        'commandPayloadPersisted': false,
        'rawLogPersisted': false,
      },
      'containsSecrets': false,
    };
    await File(_passArtifactPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(artifact),
      flush: true,
    );
  }

  Future<void> _writeFailure(
    _RelayRegistrationFailure? primary,
    _RelayRegistrationFailure? cleanup,
    _RelayRegistrationFailure? restoration,
  ) => File(_failureArtifactPath).writeAsString(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'schema': usesCurrentTokenDiagnostic
          ? backgroundCryptoPushRelayRegistrationArtifactSchemaV2
          : backgroundCryptoPushRelayRegistrationArtifactSchema,
      'status': 'failed',
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'primary': _failureJson(primary),
      'cleanup': _failureJson(cleanup),
      'restoration': _failureJson(restoration),
      'proofMilestones': <String, Object?>{
        'orderedFlowAccepted': _flowEvidence != null,
        'relayFrameAccepted': _flowEvidence?['relayFrameAccepted'] == true,
        'tokenPersisted': _flowEvidence?['tokenPersisted'] == true,
        'coordinatorSuccess': _flowEvidence?['coordinatorSuccess'] == true,
        'privateReceiptMode0600': _privateReceiptModeVerified,
        'privateReceiptRead': _privateReceiptRead,
        'privateReceiptBytes': _privateReceiptBytes,
        'privateReceiptSha256': _privateReceiptSha256,
      },
      'containsSecrets': false,
    }),
    flush: true,
  );

  Map<String, Object?>? _failureJson(_RelayRegistrationFailure? failure) =>
      failure == null
      ? null
      : <String, Object?>{'stage': failure.stage, 'reason': failure.reason};

  String _receiptFailureReason(FormatException error) {
    const reasons = <String, String>{
      'push relay receipt size rejected': 'receipt_size_rejected',
      'push relay receipt JSON rejected': 'receipt_json_rejected',
      'push relay receipt is not an object': 'receipt_root_rejected',
      'push relay receipt contract rejected': 'receipt_contract_rejected',
      'push relay receipt is stale': 'receipt_time_rejected',
      'push relay v2 receipt size rejected': 'receipt_size_rejected',
      'push relay v2 receipt JSON rejected': 'receipt_json_rejected',
      'push relay v2 receipt is not an object': 'receipt_root_rejected',
      'push relay v2 receipt contract rejected': 'receipt_contract_rejected',
      'push relay v2 receipt is stale': 'receipt_time_rejected',
    };
    return reasons[error.message.toString()] ?? 'receipt_format_rejected';
  }

  Future<void> _deletePassArtifact() async {
    final file = File(_passArtifactPath);
    if (await file.exists()) await file.delete();
  }

  Future<String> _sha256File(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<_CommandOutput> _adb(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _runChecked(
    'adb',
    <String>['-s', recipient, ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _adbShell(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _adb(
    <String>['shell', ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _runAs(
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) => _adbShell(
    <String>['run-as', appPackage, ...args],
    allowFailure: allowFailure,
    suppressVerbose: suppressVerbose,
  );

  Future<_CommandOutput> _runChecked(
    String executable,
    List<String> args, {
    bool allowFailure = false,
    bool suppressVerbose = false,
  }) async {
    final result = await Process.run(executable, args);
    final output = _CommandOutput(
      result.exitCode,
      result.stdout.toString(),
      result.stderr.toString(),
    );
    if (!suppressVerbose) {
      stdout.write(output.stdout);
      stderr.write(output.stderr);
    }
    if (!allowFailure && output.exitCode != 0) {
      throw _RelayRegistrationFailure(stage, 'command_failed');
    }
    return output;
  }
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    if (args[index] == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (args[index].startsWith('$name=')) {
      return args[index].substring(name.length + 1);
    }
  }
  return null;
}
