import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';

import 'android_app_state_guard.dart';

final RegExp _safeTarget = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
final RegExp _safeRunId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
final RegExp _digest = RegExp(r'^[0-9a-f]{64}$');
final RegExp _productionAndroidPackageArgument = RegExp(
  r'(^|[/=:])com\.mknoon\.app(?=$|[/=:])',
);
const int groupMediaAndroidMaximumAuditedCommands = 16384;
const String groupMediaAndroidCommandAuditSchema =
    'mknoon.group-media-android-command-audit.v1';

final class GroupMediaAndroidDisposableFailure implements Exception {
  const GroupMediaAndroidDisposableFailure(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

/// Matches the production package only at an Android argument boundary.
///
/// The dedicated proof package still uses the Flutter activity class
/// `com.mknoon.app.MainActivity`; that class namespace is not itself a
/// production-package target.
bool groupMediaAndroidCommandTargetsProductionPackage(
  Iterable<String> arguments,
) => arguments.any(_productionAndroidPackageArgument.hasMatch);

final class GroupMediaAndroidDisposableResetReceipt {
  const GroupMediaAndroidDisposableResetReceipt({
    required this.phase,
    required this.processId,
    required this.sha256Digest,
  });

  final String phase;
  final int processId;
  final String sha256Digest;
}

final class GroupMediaAndroidCommandAuditSnapshot {
  const GroupMediaAndroidCommandAuditSnapshot({
    required this.adbCommandCount,
    required this.journalSha256,
    required this.productionPackageCommands,
    required this.uninstallCommands,
    required this.pmClearCommands,
    required this.broadDeleteCommands,
  });

  final int adbCommandCount;
  final String journalSha256;
  final int productionPackageCommands;
  final int uninstallCommands;
  final int pmClearCommands;
  final int broadDeleteCommands;

  bool get isBounded =>
      adbCommandCount >= 0 &&
      adbCommandCount <= groupMediaAndroidMaximumAuditedCommands &&
      _digest.hasMatch(journalSha256);

  bool get isSafe =>
      isBounded &&
      productionPackageCommands == 0 &&
      uninstallCommands == 0 &&
      pmClearCommands == 0 &&
      broadDeleteCommands == 0;
}

/// Observes the exact ADB command stream without publishing raw arguments.
///
/// A chained digest binds command order while the bounded counters make every
/// destructive class fail closed before the delegate can execute it.
final class GroupMediaAndroidCommandAudit {
  var _adbCommandCount = 0;
  var _journalSha256 = _sha256('p269-android-command-audit-empty-v1');
  var _productionPackageCommands = 0;
  var _uninstallCommands = 0;
  var _pmClearCommands = 0;
  var _broadDeleteCommands = 0;

  GroupMediaAndroidCommandAuditSnapshot get snapshot =>
      GroupMediaAndroidCommandAuditSnapshot(
        adbCommandCount: _adbCommandCount,
        journalSha256: _journalSha256,
        productionPackageCommands: _productionPackageCommands,
        uninstallCommands: _uninstallCommands,
        pmClearCommands: _pmClearCommands,
        broadDeleteCommands: _broadDeleteCommands,
      );

  void observe(String executable, List<String> arguments) {
    if (executable != 'adb') return;
    if (_adbCommandCount >= groupMediaAndroidMaximumAuditedCommands) {
      throw const GroupMediaAndroidDisposableFailure(
        'The P269 Android command audit exceeded its bounded journal.',
      );
    }
    _adbCommandCount += 1;
    final commandDigest = _sha256(
      jsonEncode(<Object?>[executable, ...arguments]),
    );
    _journalSha256 = _sha256('$_journalSha256:$commandDigest');

    final command = arguments.length >= 2 && arguments.first == '-s'
        ? arguments.sublist(2)
        : arguments;
    if (groupMediaAndroidCommandTargetsProductionPackage(command)) {
      _productionPackageCommands += 1;
    }
    if (command.contains('uninstall')) {
      _uninstallCommands += 1;
    }
    if (_containsSequence(command, const <String>['shell', 'pm', 'clear']) ||
        _containsSequence(command, const <String>[
          'shell',
          'cmd',
          'package',
          'clear',
        ])) {
      _pmClearCommands += 1;
    }
    if (_isBroadDelete(command)) {
      _broadDeleteCommands += 1;
    }
    if (!snapshot.isSafe) {
      throw const GroupMediaAndroidDisposableFailure(
        'The P269 Android command audit rejected a destructive or production-package command.',
      );
    }
  }

  bool _containsSequence(List<String> values, List<String> sequence) {
    if (values.length < sequence.length) return false;
    for (var start = 0; start <= values.length - sequence.length; start += 1) {
      var matches = true;
      for (var offset = 0; offset < sequence.length; offset += 1) {
        if (values[start + offset] != sequence[offset]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  bool _isBroadDelete(List<String> command) {
    final rmIndex = command.indexOf('rm');
    if (rmIndex < 0) return false;
    final operands = command.sublist(rmIndex + 1);
    if (operands.any(
      (value) =>
          value.startsWith('--recursive') ||
          (value.startsWith('-') &&
              !value.startsWith('--') &&
              (value.contains('r') || value.contains('R'))),
    )) {
      return true;
    }
    return operands.any(
      (value) =>
          value == '/' ||
          value == '.' ||
          value == 'app_flutter' ||
          value.endsWith('/app_flutter'),
    );
  }
}

final class GroupMediaAndroidCommandAuditingRunner
    implements AndroidHostProcessRunner {
  const GroupMediaAndroidCommandAuditingRunner({
    required this.delegate,
    required this.audit,
  });

  final AndroidHostProcessRunner delegate;
  final GroupMediaAndroidCommandAudit audit;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    audit.observe(executable, arguments);
    return delegate.run(executable, arguments);
  }
}

/// Owns the dedicated P269 Android package without uninstalling or clearing an
/// arbitrary app-data tree. Freshness is requested inside the app so secure
/// storage, SQLCipher, and the fixed file allow-list share one pre-open reset.
final class GroupMediaAndroidDisposableApp {
  GroupMediaAndroidDisposableApp({
    required this.deviceId,
    required this.artifact,
    required this.expectedArtifactSha256,
    required this.runId,
    required this.workDirectory,
    this.runner = const SystemAndroidHostProcessRunner(),
    this.pollInterval = const Duration(milliseconds: 100),
    this.maximumPollsPerLaunch = 200,
    this.onMutationStarted,
  }) {
    if (!_safeTarget.hasMatch(deviceId) ||
        !_safeRunId.hasMatch(runId) ||
        !_digest.hasMatch(expectedArtifactSha256) ||
        maximumPollsPerLaunch <= 0 ||
        pollInterval.isNegative) {
      throw const FormatException('unsafe P269 Android disposable target');
    }
  }

  final String deviceId;
  final File artifact;
  final String expectedArtifactSha256;
  final String runId;
  final Directory workDirectory;
  final AndroidHostProcessRunner runner;
  final Duration pollInterval;
  final int maximumPollsPerLaunch;
  final void Function()? onMutationStarted;

  String get packageName => groupMediaAndroidDisposablePackageId;

  Future<void> installPreparedArtifact() async {
    await _requireHostArtifact();
    await _requirePreparedPackageIdentity();
    await _requireHostArtifact();
    onMutationStarted?.call();
    await _adb(<String>[
      'shell',
      'am',
      'force-stop',
      packageName,
    ], allowFailure: true);
    await _requireHostArtifact();
    final installed = await _adb(<String>[
      'install',
      '-r',
      '-d',
      '-t',
      artifact.absolute.path,
    ]);
    if (!'${installed.stdout}\n${installed.stderr}'.contains('Success')) {
      throw const GroupMediaAndroidDisposableFailure(
        'The dedicated P269 Android package was not installed.',
      );
    }
    await _requireHostArtifact();
    await requireInstalledArtifact();
  }

  Future<void> requireInstalledArtifact() async {
    final paths = await _adb(<String>[
      'shell',
      'pm',
      'path',
      packageName,
    ], allowFailure: true);
    final matches = const LineSplitter()
        .convert('${paths.stdout}')
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length).trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (paths.exitCode != 0 ||
        matches.length != 1 ||
        !RegExp(
          r'^/[A-Za-z0-9_./+~=\-]+/base\.apk$',
        ).hasMatch(matches.single)) {
      throw const GroupMediaAndroidDisposableFailure(
        'The dedicated P269 Android package is not uniquely installed.',
      );
    }
    final deviceDigest = await _adb(<String>[
      'shell',
      'sha256sum',
      matches.single,
    ]);
    final observed = '${deviceDigest.stdout}'
        .trim()
        .split(RegExp(r'\s+'))
        .first;
    if (observed != expectedArtifactSha256) {
      throw const GroupMediaAndroidDisposableFailure(
        'The installed P269 Android artifact failed custody.',
      );
    }
  }

  Future<GroupMediaAndroidDisposableResetReceipt> reset(String phase) async {
    if (!groupMediaIosDisposableResetPhases.contains(phase)) {
      throw const FormatException('unsafe P269 Android reset phase');
    }
    await requireInstalledArtifact();
    final nonce = _sha256(
      '$runId:$deviceId:$phase:$expectedArtifactSha256:${_secureNonceSeed()}',
    );
    final deviceToken = _sha256(deviceId).substring(0, 16);
    workDirectory.createSync(recursive: true);
    final request = File(
      '${workDirectory.absolute.path}${Platform.pathSeparator}'
      'android-reset-$deviceToken-$phase.json',
    );
    final remote = '/data/local/tmp/p269-reset-$deviceToken-$phase.json';
    final pending = '$groupMediaIosDisposableResetRequestFile.pending';
    try {
      request.writeAsStringSync(
        '${jsonEncode(<String, Object?>{'schema': groupMediaIosDisposableResetRequestSchema, 'run_id': runId, 'nonce': nonce, 'phase': phase, 'contains_secrets': false})}\n',
        flush: true,
      );
      await _adb(<String>[
        'shell',
        'am',
        'force-stop',
        packageName,
      ], allowFailure: true);
      await _deleteResetFiles();
      await _adb(<String>['push', request.path, remote]);
      await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'mkdir',
        '-p',
        'app_flutter',
      ]);
      await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'cp',
        remote,
        'app_flutter/$pending',
      ]);
      final stagedDigest = await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'sha256sum',
        'app_flutter/$pending',
      ]);
      final expectedRequestDigest = sha256
          .convert(request.readAsBytesSync())
          .toString();
      if ('${stagedDigest.stdout}'.trim().split(RegExp(r'\s+')).first !=
          expectedRequestDigest) {
        throw const GroupMediaAndroidDisposableFailure(
          'The P269 Android reset request failed staging custody.',
        );
      }
      await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'mv',
        'app_flutter/$pending',
        'app_flutter/$groupMediaIosDisposableResetRequestFile',
      ]);

      for (var launch = 0; launch < 2; launch += 1) {
        await _launchRoot();
        final receipt = await _pollReceipt(
          expectedNonce: nonce,
          expectedPhase: phase,
        );
        if (receipt != null) {
          await _adb(<String>['shell', 'am', 'force-stop', packageName]);
          await _requireStopped();
          await _deleteResetFiles();
          await requireInstalledArtifact();
          return receipt;
        }
        await _adb(<String>[
          'shell',
          'am',
          'force-stop',
          packageName,
        ], allowFailure: true);
      }
      throw const GroupMediaAndroidDisposableFailure(
        'The P269 Android reset receipt did not arrive.',
      );
    } finally {
      await _adb(<String>['shell', 'rm', '-f', remote], allowFailure: true);
      await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'rm',
        '-f',
        'app_flutter/$pending',
      ], allowFailure: true);
      if (request.existsSync()) request.deleteSync();
    }
  }

  Future<GroupMediaAndroidDisposableResetReceipt?> _pollReceipt({
    required String expectedNonce,
    required String expectedPhase,
  }) async {
    for (var attempt = 0; attempt < maximumPollsPerLaunch; attempt += 1) {
      final result = await _adb(<String>[
        'shell',
        'run-as',
        packageName,
        'cat',
        'app_flutter/$groupMediaIosDisposableResetReceiptFile',
      ], allowFailure: true);
      if (result.exitCode == 0 && '${result.stdout}'.trim().isNotEmpty) {
        try {
          final rawReceiptBytes = utf8.encode('${result.stdout}');
          final decodedReceipt = utf8.decode(rawReceiptBytes).trim();
          final value = (jsonDecode(decodedReceipt) as Map)
              .cast<String, Object?>();
          const keys = <String>{
            'schema',
            'run_id',
            'nonce',
            'phase',
            'process_id',
            'bundle_id',
            'profile',
            'keychain_empty',
            'database_absent',
            'allowlisted_files_absent',
            'contains_secrets',
          };
          final processId = value['process_id'];
          if (value.keys.toSet().length == keys.length &&
              value.keys.toSet().containsAll(keys) &&
              value['schema'] == groupMediaIosDisposableResetReceiptSchema &&
              value['run_id'] == runId &&
              value['nonce'] == expectedNonce &&
              value['phase'] == expectedPhase &&
              processId is int &&
              processId > 0 &&
              value['bundle_id'] == groupMediaAndroidDisposablePackageId &&
              value['profile'] == groupMediaAndroidDisposableBuildProfile &&
              value['keychain_empty'] == true &&
              value['database_absent'] == true &&
              value['allowlisted_files_absent'] == true &&
              value['contains_secrets'] == false) {
            return GroupMediaAndroidDisposableResetReceipt(
              phase: expectedPhase,
              processId: processId,
              sha256Digest: sha256.convert(rawReceiptBytes).toString(),
            );
          }
        } on Object {
          // A stale or partially copied receipt is retried within the bound.
        }
      }
      if (attempt + 1 < maximumPollsPerLaunch && pollInterval > Duration.zero) {
        await Future<void>.delayed(pollInterval);
      }
    }
    return null;
  }

  Future<void> _launchRoot() async {
    final resolved = await _adb(<String>[
      'shell',
      'cmd',
      'package',
      'resolve-activity',
      '--brief',
      '--user',
      '0',
      packageName,
    ]);
    final component = '${resolved.stdout}'.trim().split(RegExp(r'\s+')).last;
    final expectedComponent = RegExp(
      '^${RegExp.escape(packageName)}'
      r'/[A-Za-z0-9_.$]+$',
    );
    if (!expectedComponent.hasMatch(component)) {
      throw const GroupMediaAndroidDisposableFailure(
        'The P269 Android launcher was ambiguous.',
      );
    }
    final launched = await _adb(<String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      component,
    ]);
    final output = '${launched.stdout}\n${launched.stderr}';
    final acceptedStatus =
        output.contains('Status: ok') || output.contains('Status: timeout');
    if (launched.exitCode != 0 ||
        !acceptedStatus ||
        !output.contains(component)) {
      throw const GroupMediaAndroidDisposableFailure(
        'The P269 Android reset launcher failed.',
      );
    }
  }

  Future<void> _deleteResetFiles() => _adb(<String>[
    'shell',
    'run-as',
    packageName,
    'rm',
    '-f',
    'app_flutter/$groupMediaIosDisposableResetRequestFile',
    'app_flutter/$groupMediaIosDisposableResetActiveRequestFile',
    'app_flutter/$groupMediaIosDisposableResetReceiptFile',
    'app_flutter/$groupMediaIosDisposableResetReceiptFile.tmp',
  ], allowFailure: true).then((_) {});

  Future<void> _requireStopped() async {
    for (var attempt = 0; attempt < 50; attempt += 1) {
      final result = await _adb(<String>[
        'shell',
        'pidof',
        packageName,
      ], allowFailure: true);
      if (result.exitCode == 1 && '${result.stdout}'.trim().isEmpty) return;
      if (attempt + 1 < 50) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw const GroupMediaAndroidDisposableFailure(
      'The P269 Android reset process did not stop.',
    );
  }

  Future<void> _requireHostArtifact() async {
    if (FileSystemEntity.typeSync(artifact.absolute.path, followLinks: true) !=
            FileSystemEntityType.file ||
        (await sha256.bind(artifact.openRead()).first).toString() !=
            expectedArtifactSha256) {
      throw const GroupMediaAndroidDisposableFailure(
        'The prepared P269 Android artifact changed.',
      );
    }
  }

  Future<void> _requirePreparedPackageIdentity() async {
    for (final executable in _apkAnalyzerCandidates()) {
      late final ProcessResult result;
      try {
        result = await runner.run(executable, <String>[
          'manifest',
          'application-id',
          artifact.absolute.path,
        ]);
      } on ProcessException {
        continue;
      }
      final values = const LineSplitter()
          .convert('${result.stdout}')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (result.exitCode == 0 &&
          values.length == 1 &&
          values.single == groupMediaAndroidDisposablePackageId) {
        return;
      }
    }
    throw const GroupMediaAndroidDisposableFailure(
      'The P269 APK application ID was not the dedicated package.',
    );
  }

  List<String> _apkAnalyzerCandidates() {
    final candidates = <String>[];
    for (final name in const <String>['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
      final root = (Platform.environment[name] ?? '').trim();
      if (root.isEmpty) continue;
      final tools = Directory('$root${Platform.pathSeparator}cmdline-tools');
      if (!tools.existsSync()) continue;
      final ordered =
          tools
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort((left, right) => right.path.compareTo(left.path));
      for (final version in ordered) {
        final candidate = File(
          '${version.path}${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}apkanalyzer',
        );
        if (candidate.existsSync()) candidates.add(candidate.path);
      }
    }
    candidates.add('apkanalyzer');
    return candidates.toSet().toList(growable: false);
  }

  Future<ProcessResult> _adb(
    List<String> arguments, {
    bool allowFailure = false,
  }) async {
    final result = await runner.run('adb', <String>[
      '-s',
      deviceId,
      ...arguments,
    ]);
    if (!allowFailure && result.exitCode != 0) {
      throw const GroupMediaAndroidDisposableFailure(
        'A bounded P269 Android device command failed.',
      );
    }
    return result;
  }
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

String _secureNonceSeed() {
  final random = Random.secure();
  return List<int>.generate(
    32,
    (_) => random.nextInt(256),
    growable: false,
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}
