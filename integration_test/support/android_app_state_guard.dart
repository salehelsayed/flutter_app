import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const int _defaultMaximumPrivateBackupBytes = 512 * 1024 * 1024;
const int _maximumPrivateRestoreMemberListBytes = 8 * 1024 * 1024;
const Duration _defaultHostCommandTimeout = Duration(minutes: 2);
const Duration _defaultLargeBackupOperationTimeout = Duration(minutes: 10);
const Duration _defaultProcessTerminationGrace = Duration(seconds: 2);
const int _adbReconnectMaximumAttempts = 12;
const Duration _adbReconnectRetryDelay = Duration(milliseconds: 500);
const String _recoveryManifestName = 'recovery-manifest.json';
const String _recoveryManifestDigestName = 'recovery-manifest.sha256';
const String _recoveryManifestSchema = 'mknoon.android-app-state-recovery.v1';
const Set<String> _restorableRuntimePermissions = <String>{
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.RECORD_AUDIO',
  'android.permission.CAMERA',
  'android.permission.ACCESS_FINE_LOCATION',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.READ_EXTERNAL_STORAGE',
  'android.permission.WRITE_EXTERNAL_STORAGE',
  'android.permission.READ_MEDIA_IMAGES',
  'android.permission.READ_MEDIA_VIDEO',
  'android.permission.READ_MEDIA_AUDIO',
  'android.permission.BLUETOOTH_CONNECT',
  'android.permission.BLUETOOTH_SCAN',
  'android.permission.BLUETOOTH_ADVERTISE',
  'android.permission.NEARBY_WIFI_DEVICES',
};

String _deviceBackupDirectoryName(String device) =>
    device.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

/// Injectable process boundary used by host-side Android campaigns.
abstract interface class AndroidHostProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);
}

/// Optional capability for one host operation that needs a distinct deadline.
///
/// Keeping this separate from [AndroidHostProcessRunner] preserves the default
/// command bound for existing runners and every ordinary state-guard command.
abstract interface class AndroidHostProcessRunnerWithTimeout
    implements AndroidHostProcessRunner {
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  });
}

/// Test seam for the binary `adb exec-out` private-data stream.
///
/// Production campaigns leave this unset and use the bounded streaming
/// implementation. Tests may inject a deterministic archive without requiring
/// a live Android target.
typedef AndroidPrivateArchiveCapturer =
    Future<void> Function(
      String device,
      String packageName,
      List<String> entries,
      File destination,
    );

/// Injectable start seam for the production binary private-archive stream.
///
/// Tests may return a real controlled subprocess. Production leaves this null
/// and starts `adb` directly with shell interpretation disabled.
typedef AndroidPrivateArchiveProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

final class SystemAndroidHostProcessRunner
    implements AndroidHostProcessRunnerWithTimeout {
  const SystemAndroidHostProcessRunner({
    this.commandTimeout = _defaultHostCommandTimeout,
    this.terminationGrace = _defaultProcessTerminationGrace,
  });

  final Duration commandTimeout;
  final Duration terminationGrace;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) =>
      _run(executable, arguments, timeout: commandTimeout);

  @override
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) => _run(executable, arguments, timeout: timeout);

  Future<ProcessResult> _run(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    _requirePositiveDuration(timeout, 'timeout');
    _requirePositiveDuration(terminationGrace, 'terminationGrace');
    final process = await Process.start(
      executable,
      arguments,
      runInShell: false,
    );
    final stdoutCollector = _ProcessOutputCollector.start(process.stdout);
    final stderrCollector = _ProcessOutputCollector.start(process.stderr);
    final stdinClosed = process.stdin.close();
    final exitCodeFuture = process.exitCode;
    final completed = Future.wait<Object?>(<Future<Object?>>[
      exitCodeFuture,
      stdoutCollector.result,
      stderrCollector.result,
      stdinClosed,
    ]);
    final neverAborted = Completer<void>();
    final outcome = await _waitForBoundedProcess(
      completed.then<void>((_) {}),
      neverAborted.future,
      timeout,
    );
    if (outcome != _BoundedProcessOutcome.completed) {
      await _terminateAndReap(
        process,
        exitCodeFuture,
        terminationGrace: terminationGrace,
      );
      try {
        await Future.wait<List<int>>(<Future<List<int>>>[
          stdoutCollector.result,
          stderrCollector.result,
        ]).timeout(terminationGrace);
      } on Object {
        await Future.wait<void>(<Future<void>>[
          stdoutCollector.cancel(terminationGrace),
          stderrCollector.cancel(terminationGrace),
        ]).timeout(terminationGrace, onTimeout: () => const <void>[]);
      }
      throw ProcessException(
        executable,
        const <String>[],
        outcome == _BoundedProcessOutcome.timedOut
            ? 'Host command timed out.'
            : 'Host command stream failed.',
        outcome == _BoundedProcessOutcome.timedOut ? 124 : 74,
      );
    }
    final output = await completed;
    return ProcessResult(
      process.pid,
      output[0]! as int,
      utf8.decode(output[1]! as List<int>, allowMalformed: true),
      utf8.decode(output[2]! as List<int>, allowMalformed: true),
    );
  }
}

void _requirePositiveDuration(Duration value, String name) {
  if (value <= Duration.zero) {
    throw ArgumentError.value(value, name, 'must be positive');
  }
}

final class _ProcessOutputCollector {
  _ProcessOutputCollector._();

  static _ProcessOutputCollector start(Stream<List<int>> stream) {
    final collector = _ProcessOutputCollector._();
    collector._subscription = stream.listen(
      collector._builder.add,
      onError: (Object error, StackTrace stackTrace) {
        if (collector._result.isCompleted) return;
        collector._result.completeError(error, stackTrace);
      },
      onDone: collector._finish,
      cancelOnError: false,
    );
    return collector;
  }

  final BytesBuilder _builder = BytesBuilder(copy: false);
  final Completer<List<int>> _result = Completer<List<int>>();
  late final StreamSubscription<List<int>> _subscription;
  var _streamDone = false;

  Future<List<int>> get result => _result.future;

  void _finish() {
    _streamDone = true;
    if (!_result.isCompleted) _result.complete(_builder.takeBytes());
  }

  Future<void> cancel(Duration timeout) async {
    if (_streamDone) return;
    try {
      await _subscription.cancel().timeout(timeout);
    } on Object {
      // The outer command deadline remains authoritative.
    } finally {
      _streamDone = true;
      _finish();
    }
  }
}

Future<int?> _waitForExitWithin(Future<int> exitCode, Duration timeout) {
  final result = Completer<int?>();
  late final Timer timer;
  timer = Timer(timeout, () => result.complete(null));
  exitCode.then(
    (code) {
      if (result.isCompleted) return;
      timer.cancel();
      result.complete(code);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (result.isCompleted) return;
      timer.cancel();
      result.completeError(error, stackTrace);
    },
  );
  return result.future;
}

Future<int?> _terminateAndReap(
  Process process,
  Future<int> exitCode, {
  required Duration terminationGrace,
  bool termAlreadySent = false,
}) async {
  if (!termAlreadySent) {
    try {
      process.kill(ProcessSignal.sigterm);
    } on Object {
      // Continue to the hard-stop and bounded reap path.
    }
  }
  int? code;
  try {
    code = await _waitForExitWithin(exitCode, terminationGrace);
  } on Object {
    // Continue to SIGKILL; the caller will still report bounded failure.
  }
  if (code != null) return code;
  try {
    process.kill(ProcessSignal.sigkill);
  } on Object {
    // The final bounded reap below remains authoritative.
  }
  try {
    code = await _waitForExitWithin(exitCode, terminationGrace);
  } on Object {
    // A missing exit code is returned as failure, never as success.
  }
  return code;
}

enum _BoundedProcessOutcome { completed, aborted, timedOut }

Future<_BoundedProcessOutcome> _waitForBoundedProcess(
  Future<void> completed,
  Future<void> aborted,
  Duration timeout,
) {
  final result = Completer<_BoundedProcessOutcome>();
  late final Timer timer;
  timer = Timer(timeout, () {
    if (!result.isCompleted) {
      result.complete(_BoundedProcessOutcome.timedOut);
    }
  });
  void finish(_BoundedProcessOutcome outcome) {
    if (result.isCompleted) return;
    timer.cancel();
    result.complete(outcome);
  }

  completed.then(
    (_) => finish(_BoundedProcessOutcome.completed),
    onError: (Object _, StackTrace _) => finish(_BoundedProcessOutcome.aborted),
  );
  aborted.then(
    (_) => finish(_BoundedProcessOutcome.aborted),
    onError: (Object _, StackTrace _) => finish(_BoundedProcessOutcome.aborted),
  );
  return result.future;
}

enum AndroidPackageRestoreAction {
  uninstallTestInstall,
  reinstallOriginalInPlace,
  failKeystoreAlreadyLost,
}

/// Pure policy shared by the implementation and its preservation tests.
AndroidPackageRestoreAction androidPackageRestoreAction({
  required bool originallyInstalled,
  required bool currentlyInstalled,
}) {
  if (!originallyInstalled) {
    return AndroidPackageRestoreAction.uninstallTestInstall;
  }
  if (!currentlyInstalled) {
    return AndroidPackageRestoreAction.failKeystoreAlreadyLost;
  }
  return AndroidPackageRestoreAction.reinstallOriginalInPlace;
}

/// A pre-mutation environment limitation that leaves the original app intact.
final class AndroidAppStateBlocked implements Exception {
  const AndroidAppStateBlocked(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

/// A short-lived failure of the binary `adb exec-out` archive transport.
///
/// Policy failures such as the byte bound and process timeout remain ordinary
/// [AndroidAppStateBlocked] results and are never replayed. This private type
/// marks only a stream that may safely be recaptured from the still-untouched
/// package tree after adbd replaces its host transport.
final class _RetryablePrivateArchiveStreamFailure implements Exception {
  const _RetryablePrivateArchiveStreamFailure(this.detail);

  final String detail;
}

bool _isTransientAdbTransportFailure(ProcessResult result) {
  if (result.exitCode == 0) return false;
  final diagnostic = '${result.stderr}\n${result.stdout}'.toLowerCase();
  return const <String>[
    'device offline',
    'device not found',
    'no devices/emulators found',
    'transport is closing',
    'transport error',
    'error: closed',
    'connection reset',
    'protocol fault',
  ].any(diagnostic.contains);
}

/// A mutation/restoration failure. The backup path is retained for recovery.
final class AndroidAppStateFailure implements Exception {
  const AndroidAppStateFailure(this.detail, {this.backupDirectory});

  final String detail;
  final Directory? backupDirectory;

  @override
  String toString() => detail;
}

/// Exact Android package-state guard for host-orchestrated device campaigns.
///
/// Capture stops the app only after recording whether it was running and
/// foreground. For an installed app it backs up every installed APK, a bounded
/// private-data archive, and restorable runtime permissions. A campaign may
/// then repeatedly ensure the same centrally prepared APK is installed and
/// clear its private filesystem through `run-as`. An exact already-installed
/// artifact is reused so low-space targets do not stage a redundant update.
///
/// Restoration never runs `pm clear` and never uninstalls an app that existed
/// at capture time, because either operation destroys app-scoped Android
/// Keystore material. Only a package that was originally absent is uninstalled.
final class AndroidAppStateGuard {
  AndroidAppStateGuard._({
    required this.devices,
    required this.packageName,
    required this.backupDirectory,
    required AndroidHostProcessRunner runner,
    required AndroidPrivateArchiveCapturer? privateArchiveCapturer,
    required AndroidPrivateArchiveProcessStarter? privateArchiveProcessStarter,
    required int maximumPrivateBackupBytes,
    required Duration privateArchiveTimeout,
    required Duration processTerminationGrace,
  }) : _runner = runner,
       _privateArchiveCapturer = privateArchiveCapturer,
       _privateArchiveProcessStarter = privateArchiveProcessStarter,
       _maximumPrivateBackupBytes = maximumPrivateBackupBytes,
       _privateArchiveTimeout = privateArchiveTimeout,
       _processTerminationGrace = processTerminationGrace;

  static Future<AndroidAppStateGuard> capture({
    required List<String> devices,
    required String packageName,
    String backupLabel = 'campaign',
    File? preparedArtifact,
    String? expectedArtifactSha256,
    AndroidHostProcessRunner runner = const SystemAndroidHostProcessRunner(),
    AndroidPrivateArchiveCapturer? privateArchiveCapturer,
    AndroidPrivateArchiveProcessStarter? privateArchiveProcessStarter,
    int maximumPrivateBackupBytes = _defaultMaximumPrivateBackupBytes,
    Duration privateArchiveTimeout = _defaultLargeBackupOperationTimeout,
    Duration processTerminationGrace = _defaultProcessTerminationGrace,
  }) async {
    final safeDevice = RegExp(r'^[A-Za-z0-9._:-]{1,160}$');
    final safePackage = RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$');
    if (devices.isEmpty ||
        devices.toSet().length != devices.length ||
        devices.map(_deviceBackupDirectoryName).toSet().length !=
            devices.length ||
        devices.any((device) => !safeDevice.hasMatch(device)) ||
        !safePackage.hasMatch(packageName) ||
        maximumPrivateBackupBytes <= 0 ||
        privateArchiveTimeout <= Duration.zero ||
        processTerminationGrace <= Duration.zero) {
      throw const AndroidAppStateBlocked(
        'Android app-state guard received an unsafe target or package.',
      );
    }
    final safeLabel = backupLabel.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final backupDirectory = await Directory.systemTemp.createTemp(
      'mknoon-$safeLabel-state-',
    );
    final guard = AndroidAppStateGuard._(
      devices: List<String>.unmodifiable(devices),
      packageName: packageName,
      backupDirectory: backupDirectory,
      runner: runner,
      privateArchiveCapturer: privateArchiveCapturer,
      privateArchiveProcessStarter: privateArchiveProcessStarter,
      maximumPrivateBackupBytes: maximumPrivateBackupBytes,
      privateArchiveTimeout: privateArchiveTimeout,
      processTerminationGrace: processTerminationGrace,
    );
    if (preparedArtifact == null && expectedArtifactSha256 != null) {
      backupDirectory.deleteSync(recursive: true);
      throw const AndroidAppStateBlocked(
        'Android artifact custody requires the prepared APK.',
      );
    }
    if (preparedArtifact != null) {
      try {
        await guard._validatePreparedArtifact(
          preparedArtifact.absolute,
          expectedArtifactSha256: expectedArtifactSha256,
        );
      } on Object {
        if (backupDirectory.existsSync()) {
          backupDirectory.deleteSync(recursive: true);
        }
        rethrow;
      }
    }
    try {
      await guard._captureAll();
      return guard;
    } on AndroidAppStateFailure {
      rethrow;
    } on AndroidAppStateBlocked {
      rethrow;
    } on Object {
      throw AndroidAppStateBlocked(
        'Exact Android app state could not be captured. Recovery data remains '
        'at ${backupDirectory.path}.',
      );
    }
  }

  /// Loads a retained recovery snapshot without recapturing the live device.
  ///
  /// This is the process-loss path: callers may create a new host process,
  /// load the redacted manifest, and call [restoreAll]. Every retained APK and
  /// private archive is hash-verified before the guard is returned.
  static Future<AndroidAppStateGuard> loadRecovery({
    required Directory backupDirectory,
    AndroidHostProcessRunner runner = const SystemAndroidHostProcessRunner(),
    int maximumPrivateBackupBytes = _defaultMaximumPrivateBackupBytes,
    AndroidPrivateArchiveCapturer? privateArchiveCapturer,
    AndroidPrivateArchiveProcessStarter? privateArchiveProcessStarter,
  }) async {
    final absoluteBackup = backupDirectory.absolute;
    if (maximumPrivateBackupBytes <= 0) {
      throw AndroidAppStateFailure(
        'Android recovery policy is invalid.',
        backupDirectory: absoluteBackup,
      );
    }
    try {
      final recovered = await _RecoveryManifestCodec.read(
        backupDirectory: absoluteBackup,
        maximumPrivateBackupBytes: maximumPrivateBackupBytes,
      );
      final guard = AndroidAppStateGuard._(
        devices: recovered.devices,
        packageName: recovered.packageName,
        backupDirectory: absoluteBackup,
        runner: runner,
        privateArchiveCapturer: privateArchiveCapturer,
        privateArchiveProcessStarter: privateArchiveProcessStarter,
        maximumPrivateBackupBytes: maximumPrivateBackupBytes,
        privateArchiveTimeout: _defaultLargeBackupOperationTimeout,
        processTerminationGrace: _defaultProcessTerminationGrace,
      );
      guard._snapshots.addAll(recovered.snapshots);
      return guard;
    } on AndroidAppStateFailure {
      rethrow;
    } on Object {
      throw AndroidAppStateFailure(
        'Retained Android recovery manifest or artifacts are invalid at '
        '${absoluteBackup.path}.',
        backupDirectory: absoluteBackup,
      );
    }
  }

  final List<String> devices;
  final String packageName;
  final Directory backupDirectory;
  final AndroidHostProcessRunner _runner;
  final AndroidPrivateArchiveCapturer? _privateArchiveCapturer;
  final AndroidPrivateArchiveProcessStarter? _privateArchiveProcessStarter;
  final int _maximumPrivateBackupBytes;
  final Duration _privateArchiveTimeout;
  final Duration _processTerminationGrace;
  final Random _random = Random.secure();
  final Map<String, _PackageSnapshot> _snapshots = <String, _PackageSnapshot>{};
  final Map<String, Set<String>> _unexpectedPackages = <String, Set<String>>{};
  var _restored = false;

  bool get restored => _restored;

  /// Installs one prebuilt artifact and creates a logically fresh private tree.
  ///
  /// This is safe to call between scenarios. It preserves the system Keystore
  /// record for an originally installed app and invokes no build tool.
  Future<void> prepareFreshInstall({
    required String device,
    required File artifact,
    String? expectedArtifactSha256,
  }) async {
    try {
      await _prepareFreshInstallUnchecked(
        device: device,
        artifact: artifact,
        expectedArtifactSha256: expectedArtifactSha256,
      );
    } on AndroidAppStateFailure {
      rethrow;
    } on Object catch (error) {
      throw AndroidAppStateFailure(
        'Preparing the central APK on $device failed: $error',
        backupDirectory: backupDirectory,
      );
    }
  }

  Future<void> _prepareFreshInstallUnchecked({
    required String device,
    required File artifact,
    required String? expectedArtifactSha256,
  }) async {
    _requireCapturedDevice(device);
    if (_restored) {
      throw AndroidAppStateFailure(
        'Android app-state guard was already restored.',
        backupDirectory: backupDirectory,
      );
    }
    if (FileSystemEntity.typeSync(artifact.absolute.path, followLinks: true) !=
        FileSystemEntityType.file) {
      throw AndroidAppStateFailure(
        'The centrally prepared Android artifact is unavailable.',
        backupDirectory: backupDirectory,
      );
    }
    final expectedSha256 = await _validatePreparedArtifact(
      artifact.absolute,
      expectedArtifactSha256: expectedArtifactSha256,
    );
    var paths = await _installedPackagePaths(device);
    final installedBase = _requireSingleBaseApkPath(paths, allowAbsent: true);
    var exactArtifactInstalled = false;
    if (paths.length == 1 && installedBase != null) {
      try {
        exactArtifactInstalled =
            await _deviceFileSha256(device, installedBase) == expectedSha256;
      } on Object {
        // Digest probing is an optimization boundary. Fall back to the
        // established in-place install when the device cannot prove equality.
      }
    }
    Set<String>? packagesBeforeInstall;
    if (!exactArtifactInstalled) {
      // The package inventory is read before the first device mutation. If an
      // installer ever introduces anything other than the attested package,
      // restoration owns and removes that exact delta.
      packagesBeforeInstall = await _installedThirdPartyPackages(device);
    }
    await _requirePreparedArtifactDigest(
      artifact.absolute,
      expectedSha256,
      phase: 'before device mutation',
    );
    await _forceStop(device);
    if (!exactArtifactInstalled) {
      await _requirePreparedArtifactDigest(
        artifact.absolute,
        expectedSha256,
        phase: 'immediately before install',
      );
      final install = await _adb(device, <String>[
        'install',
        '-r',
        '-d',
        '-t',
        artifact.absolute.path,
      ], allowFailure: true);
      final packagesAfterInstall = await _installedThirdPartyPackages(device);
      final introduced = packagesAfterInstall.difference(packagesBeforeInstall!)
        ..remove(packageName);
      if (introduced.isNotEmpty) {
        _unexpectedPackages
            .putIfAbsent(device, () => <String>{})
            .addAll(introduced);
      }
      if (install.exitCode != 0) {
        throw AndroidAppStateFailure(
          'The central APK could not be installed in place on $device.',
          backupDirectory: backupDirectory,
        );
      }
      await _requirePreparedArtifactDigest(
        artifact.absolute,
        expectedSha256,
        phase: 'immediately after install',
      );
      paths = await _installedPackagePaths(device);
    }
    final installedBaseAfterPreparation = _requireSingleBaseApkPath(
      paths,
      allowAbsent: false,
    );
    if (paths.length != 1 ||
        installedBaseAfterPreparation == null ||
        await _deviceFileSha256(device, installedBaseAfterPreparation) !=
            expectedSha256 ||
        (_unexpectedPackages[device]?.isNotEmpty ?? false)) {
      throw AndroidAppStateFailure(
        'The installed Android package did not match the central APK on '
        '$device.',
        backupDirectory: backupDirectory,
      );
    }
    await _clearPrivateEntries(device);
  }

  Future<void> prepareFreshInstalls(File artifact) async {
    for (final device in devices) {
      await prepareFreshInstall(device: device, artifact: artifact);
    }
  }

  /// Restores every target in reverse order and verifies before returning.
  ///
  /// On any error all other targets are still attempted. The recovery
  /// directory is retained and the caller must emit typed FAIL, never PASS.
  Future<void> restoreAll() async {
    if (_restored) return;
    final failures = <String>[];
    for (final device in devices.reversed) {
      final snapshot = _snapshots[device];
      if (snapshot == null) {
        failures.add('$device: snapshot missing');
        continue;
      }
      try {
        await _restoreOne(device, snapshot);
      } on Object catch (error) {
        failures.add('$device: $error');
      }
      try {
        await _removeUnexpectedPackages(device);
      } on Object catch (error) {
        failures.add('$device: unexpected package cleanup failed: $error');
      }
    }
    if (failures.isNotEmpty) {
      throw AndroidAppStateFailure(
        'Exact APK/private-data/permission/process restoration failed '
        '(${failures.join('; ')}). Recovery backups remain at '
        '${backupDirectory.path}.',
        backupDirectory: backupDirectory,
      );
    }
    try {
      if (backupDirectory.existsSync()) {
        backupDirectory.deleteSync(recursive: true);
      }
    } on FileSystemException {
      throw AndroidAppStateFailure(
        'Android recovery state was restored but its host backup could not be '
        'removed at ${backupDirectory.path}.',
        backupDirectory: backupDirectory,
      );
    }
    if (backupDirectory.existsSync()) {
      throw AndroidAppStateFailure(
        'Android recovery backup survived successful restoration at '
        '${backupDirectory.path}.',
        backupDirectory: backupDirectory,
      );
    }
    _restored = true;
  }

  Future<void> _captureAll() async {
    final preliminaries = <String, _PreliminarySnapshot>{};
    var processMutationStarted = false;
    try {
      // Read-only/debuggability checks happen before the first force-stop.
      for (final device in devices) {
        final paths = await _installedPackagePaths(device);
        if (paths.isNotEmpty) {
          final runAs = await _adb(device, <String>[
            'shell',
            'run-as',
            packageName,
            'id',
          ], allowFailure: true);
          if (runAs.exitCode != 0) {
            throw AndroidAppStateBlocked(
              'The installed app on $device is not debuggable, so exact '
              'private-state restoration is unavailable. No app mutation '
              'was attempted.',
            );
          }
        }
        preliminaries[device] = _PreliminarySnapshot(
          packagePaths: paths,
          process: await _captureProcessState(device),
          runtimePermissions: paths.isEmpty
              ? const <String, bool>{}
              : await _runtimePermissionSnapshot(device),
        );
      }

      // Mark before the loop so a partial force-stop sequence still restores
      // every process snapshot captured above.
      processMutationStarted = true;
      for (final device in devices) {
        await _forceStop(device);
      }
      for (final device in devices) {
        _snapshots[device] = await _captureStoppedPackage(
          device,
          preliminaries[device]!,
        );
      }
      // capture() does not return until this process-loss recovery record and
      // its digest are durable. Campaign mutation therefore cannot begin with
      // an APK/data-only backup that lacks permissions or process state.
      await _persistRecoveryManifest();
    } on Object catch (error) {
      final restoreFailures = <String>[];
      if (processMutationStarted) {
        for (final device in devices.reversed) {
          final process = preliminaries[device]?.process;
          if (process == null) continue;
          try {
            await _restoreProcessState(device, process);
          } on Object catch (restoreError) {
            restoreFailures.add('$device: $restoreError');
          }
        }
      }
      if (restoreFailures.isNotEmpty) {
        throw AndroidAppStateFailure(
          'Android state capture failed and original process state could not '
          'be restored (${restoreFailures.join('; ')}). Recovery data remains '
          'at ${backupDirectory.path}.',
          backupDirectory: backupDirectory,
        );
      }
      try {
        if (backupDirectory.existsSync()) {
          backupDirectory.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // The reported capture error remains authoritative; retaining a
        // read-only partial backup is safer than hiding it.
      }
      if (error is AndroidAppStateBlocked) rethrow;
      if (error is AndroidAppStateFailure) rethrow;
      throw AndroidAppStateBlocked('Exact Android app-state capture failed.');
    }
  }

  Future<void> _persistRecoveryManifest() async {
    final manifest = File(
      '${backupDirectory.path}${Platform.pathSeparator}$_recoveryManifestName',
    );
    final manifestTemporary = File('${manifest.path}.tmp');
    final digest = File(
      '${backupDirectory.path}${Platform.pathSeparator}'
      '$_recoveryManifestDigestName',
    );
    final digestTemporary = File('${digest.path}.tmp');
    final encoded =
        '${jsonEncode(_RecoveryManifestCodec.encode(packageName: packageName, devices: devices, snapshots: _snapshots))}\n';
    await manifestTemporary.writeAsString(encoded, flush: true);
    await manifestTemporary.rename(manifest.path);
    final manifestSha256 = await _hostFileSha256(manifest);
    await digestTemporary.writeAsString('$manifestSha256\n', flush: true);
    await digestTemporary.rename(digest.path);
  }

  Future<_PackageSnapshot> _captureStoppedPackage(
    String device,
    _PreliminarySnapshot preliminary,
  ) async {
    if (preliminary.packagePaths.isEmpty) {
      return _PackageSnapshot.absent(preliminary.process);
    }
    final deviceDirectory = Directory(
      '${backupDirectory.path}${Platform.pathSeparator}'
      '${_deviceBackupDirectoryName(device)}',
    )..createSync(recursive: true);
    final apkFiles = <File>[];
    final apkDigests = <String>[];
    for (var index = 0; index < preliminary.packagePaths.length; index += 1) {
      final source = preliminary.packagePaths[index];
      final destination = File(
        '${deviceDirectory.path}${Platform.pathSeparator}installed-$index.apk',
      );
      final deviceDigest = await _deviceFileSha256(device, source);
      final pull = await _adb(
        device,
        <String>['pull', source, destination.path],
        allowFailure: true,
        commandTimeout: _defaultLargeBackupOperationTimeout,
      );
      if (pull.exitCode != 0 ||
          !destination.existsSync() ||
          destination.lengthSync() == 0) {
        throw AndroidAppStateBlocked('Original APK backup failed on $device.');
      }
      final hostDigest = await _hostFileSha256(destination);
      if (hostDigest != deviceDigest) {
        throw AndroidAppStateBlocked(
          'Original APK backup hash drifted on $device.',
        );
      }
      apkFiles.add(destination);
      apkDigests.add(hostDigest);
    }

    final entries = await _privateEntries(device);
    final sizeOutput = await _shellText(device, <String>[
      'run-as',
      packageName,
      'du',
      '-sk',
      '.',
    ]);
    final sizeKb = int.tryParse(sizeOutput.trim().split(RegExp(r'\s+')).first);
    if (sizeKb == null ||
        sizeKb < 0 ||
        sizeKb * 1024 > _maximumPrivateBackupBytes) {
      throw AndroidAppStateBlocked(
        'Private app data on $device exceeds the bounded '
        '${_maximumPrivateBackupBytes ~/ (1024 * 1024)} MiB backup policy.',
      );
    }
    File? archive;
    String? archiveDigest;
    if (entries.isNotEmpty) {
      archive = File(
        '${deviceDirectory.path}${Platform.pathSeparator}private-data.tar',
      );
      archiveDigest = await _capturePrivateArchive(device, entries, archive);
    }
    return _PackageSnapshot(
      installed: true,
      process: preliminary.process,
      apkFiles: List<File>.unmodifiable(apkFiles),
      apkDigests: List<String>.unmodifiable(apkDigests),
      privateEntries: List<String>.unmodifiable(entries),
      privateArchive: archive,
      privateArchiveSha256: archiveDigest,
      runtimePermissions: Map<String, bool>.unmodifiable(
        preliminary.runtimePermissions,
      ),
    );
  }

  Future<String> _capturePrivateArchive(
    String device,
    List<String> entries,
    File destination,
  ) async {
    var structuralAttempts = 0;
    var transportAttempts = 0;
    while (true) {
      try {
        final digest = await _capturePrivateArchiveOnce(
          device,
          entries,
          destination,
        );
        // A host ADB transport can occasionally exit successfully after
        // yielding only a prefix of the device tar stream. Hashing that prefix
        // proves only that the prefix stayed stable. Parse every member before
        // accepting the backup so capture and post-restore verification both
        // retry the exact observed partial-member failure while the source
        // private tree is still available.
        await canonicalPrivateArchiveDigest(destination);
        return digest;
      } on FormatException {
        structuralAttempts += 1;
        if (destination.existsSync()) destination.deleteSync();
        if (structuralAttempts == 3) {
          throw AndroidAppStateBlocked(
            'Private app-data backup remained structurally incomplete on '
            '$device after three bounded attempts.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } on _RetryablePrivateArchiveStreamFailure catch (error) {
        transportAttempts += 1;
        if (destination.existsSync()) destination.deleteSync();
        if (transportAttempts == _adbReconnectMaximumAttempts) {
          throw AndroidAppStateBlocked(
            '${error.detail} on $device after bounded ADB reconnect retries.',
          );
        }
        await Future<void>.delayed(_adbReconnectRetryDelay);
      }
    }
  }

  Future<String> _capturePrivateArchiveOnce(
    String device,
    List<String> entries,
    File destination,
  ) async {
    final injectedCapturer = _privateArchiveCapturer;
    if (injectedCapturer != null) {
      try {
        await injectedCapturer(
          device,
          packageName,
          List<String>.unmodifiable(entries),
          destination,
        );
      } on Object {
        if (destination.existsSync()) destination.deleteSync();
        throw const _RetryablePrivateArchiveStreamFailure(
          'Private app-data backup stream failed',
        );
      }
      if (!destination.existsSync() ||
          destination.lengthSync() == 0 ||
          destination.lengthSync() > _maximumPrivateBackupBytes) {
        if (destination.existsSync()) destination.deleteSync();
        throw AndroidAppStateBlocked(
          'Private app-data backup failed on $device.',
        );
      }
      return _hostFileSha256(destination);
    }
    final arguments = <String>[
      '-s',
      device,
      'exec-out',
      'run-as',
      packageName,
      'tar',
      '-cf',
      '-',
      '--',
      ...entries,
    ];
    late final Process process;
    try {
      final starter = _privateArchiveProcessStarter;
      process = starter == null
          ? await Process.start('adb', arguments, runInShell: false)
          : await starter('adb', List<String>.unmodifiable(arguments));
    } on Object {
      throw const _RetryablePrivateArchiveStreamFailure(
        'ADB could not start the private app-data backup stream',
      );
    }

    late final IOSink sink;
    try {
      sink = destination.openWrite();
    } on Object {
      await _terminateAndReap(
        process,
        process.exitCode,
        terminationGrace: _processTerminationGrace,
      );
      if (destination.existsSync()) destination.deleteSync();
      throw AndroidAppStateBlocked(
        'Private app-data backup failed on $device.',
      );
    }
    final stdinClosed = process.stdin.close();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    final aborted = Completer<void>();
    var byteCount = 0;
    var overflow = false;
    var streamFailed = false;
    var termAlreadySent = false;

    void markAborted() {
      if (!aborted.isCompleted) aborted.complete();
    }

    late final StreamSubscription<List<int>> stdoutSubscription;
    late final StreamSubscription<List<int>> stderrSubscription;
    stdoutSubscription = process.stdout.listen(
      (chunk) {
        if (overflow || streamFailed) return;
        byteCount += chunk.length;
        if (byteCount > _maximumPrivateBackupBytes) {
          overflow = true;
          termAlreadySent = process.kill(ProcessSignal.sigterm);
          markAborted();
          return;
        }
        try {
          sink.add(chunk);
        } on Object {
          streamFailed = true;
          markAborted();
        }
      },
      onError: (Object _) {
        streamFailed = true;
        markAborted();
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      onDone: () {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
      },
      cancelOnError: false,
    );
    stderrSubscription = process.stderr.listen(
      (_) {},
      onError: (Object _) {
        streamFailed = true;
        markAborted();
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      onDone: () {
        if (!stderrDone.isCompleted) stderrDone.complete();
      },
      cancelOnError: false,
    );

    final exitCodeFuture = process.exitCode;
    int? exitCode;
    final exitObserved = exitCodeFuture.then<void>(
      (value) => exitCode = value,
      onError: (Object _, StackTrace _) {
        streamFailed = true;
        markAborted();
      },
    );
    final completed = Future.wait<void>(<Future<void>>[
      exitObserved,
      stdoutDone.future,
      stderrDone.future,
      stdinClosed,
    ]);
    final outcome = await _waitForBoundedProcess(
      completed,
      aborted.future,
      _privateArchiveTimeout,
    );

    if (outcome != _BoundedProcessOutcome.completed) {
      exitCode = await _terminateAndReap(
        process,
        exitCodeFuture,
        terminationGrace: _processTerminationGrace,
        termAlreadySent: termAlreadySent,
      );
    }

    var drainsClosed = true;
    try {
      await Future.wait<void>(<Future<void>>[
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(_processTerminationGrace);
    } on Object {
      drainsClosed = false;
      try {
        await Future.wait<void>(<Future<void>>[
          stdoutSubscription.cancel(),
          stderrSubscription.cancel(),
        ]).timeout(_processTerminationGrace, onTimeout: () => const <void>[]);
      } on Object {
        // Cleanup continues with sink closure and partial-file deletion.
      } finally {
        if (!stdoutDone.isCompleted) stdoutDone.complete();
        if (!stderrDone.isCompleted) stderrDone.complete();
      }
    }

    var sinkClosed = true;
    try {
      await sink.close().timeout(_processTerminationGrace);
    } on Object {
      sinkClosed = false;
    }

    if (outcome != _BoundedProcessOutcome.completed ||
        overflow ||
        streamFailed ||
        !drainsClosed ||
        !sinkClosed ||
        exitCode != 0 ||
        !destination.existsSync() ||
        destination.lengthSync() == 0) {
      if (destination.existsSync()) destination.deleteSync();
      if (outcome == _BoundedProcessOutcome.timedOut) {
        throw AndroidAppStateBlocked(
          'Private app-data backup timed out on $device.',
        );
      }
      if (overflow) {
        throw AndroidAppStateBlocked(
          'Private app data on $device exceeds the bounded '
          '${_maximumPrivateBackupBytes ~/ (1024 * 1024)} MiB backup policy.',
        );
      }
      throw const _RetryablePrivateArchiveStreamFailure(
        'Private app-data backup stream failed',
      );
    }
    return _hostFileSha256(destination);
  }

  Future<void> _restoreOne(String device, _PackageSnapshot snapshot) async {
    await _forceStop(device);
    final currentInstalled = (await _installedPackagePaths(device)).isNotEmpty;
    switch (androidPackageRestoreAction(
      originallyInstalled: snapshot.installed,
      currentlyInstalled: currentInstalled,
    )) {
      case AndroidPackageRestoreAction.uninstallTestInstall:
        if (currentInstalled) {
          final uninstall = await _adb(device, <String>[
            'uninstall',
            packageName,
          ], allowFailure: true);
          if (uninstall.exitCode != 0) {
            throw StateError('initially absent package could not be removed');
          }
        }
        if ((await _installedPackagePaths(device)).isNotEmpty) {
          throw StateError('initially absent package is still installed');
        }
        await _verifyProcessState(device, snapshot.process);
        return;
      case AndroidPackageRestoreAction.failKeystoreAlreadyLost:
        throw StateError(
          'originally installed package disappeared; Android Keystore state '
          'cannot be restored exactly',
        );
      case AndroidPackageRestoreAction.reinstallOriginalInPlace:
        break;
    }

    final privateRestorePlan = _PrivateArchiveRestorePlan.fromSnapshot(
      snapshot,
    );
    await _installOriginalApks(device, snapshot);
    await _clearPrivateEntriesForRestore(
      device,
      preservedRoots: privateRestorePlan.preservedRoots,
    );
    await _restorePrivateArchive(device, snapshot, privateRestorePlan);
    final restoredEntries = await _privateEntries(device);
    final expectedEntries = List<String>.from(snapshot.privateEntries)..sort();
    final actualEntries = List<String>.from(restoredEntries)..sort();
    if (jsonEncode(actualEntries) != jsonEncode(expectedEntries)) {
      throw StateError('private app-data inventory did not restore');
    }
    await _restoreRuntimePermissions(device, snapshot.runtimePermissions);
    await _verifyInstalledApks(device, snapshot);
    await _restoreProcessState(device, snapshot.process);
    await _verifyProcessState(device, snapshot.process);
  }

  Future<void> _installOriginalApks(
    String device,
    _PackageSnapshot snapshot,
  ) async {
    final arguments = snapshot.apkFiles.length == 1
        ? <String>[
            'install',
            '--no-streaming',
            '-r',
            '-d',
            '-t',
            snapshot.apkFiles.single.path,
          ]
        : <String>[
            'install-multiple',
            '--no-streaming',
            '-r',
            '-d',
            '-t',
            ...snapshot.apkFiles.map((file) => file.path),
          ];
    final install = await _adb(device, arguments, allowFailure: true);
    if (install.exitCode != 0) {
      // An uninstall/reinstall fallback would destroy Android Keystore state.
      throw StateError('original APK restore failed without an uninstall');
    }
  }

  Future<void> _restorePrivateArchive(
    String device,
    _PackageSnapshot snapshot,
    _PrivateArchiveRestorePlan restorePlan,
  ) async {
    if (snapshot.privateEntries.isEmpty) return;
    final archive = snapshot.privateArchive;
    final expected = snapshot.privateArchiveSha256;
    if (archive == null || expected == null || !archive.existsSync()) {
      throw StateError('private app-data recovery archive is unavailable');
    }
    final token = _token('restore');
    final remote = '/data/local/tmp/sims-state-$token.tar';
    final remoteMembers = '/data/local/tmp/sims-state-$token.members';
    final privateArchive = '.sims_state_$token.tar';
    final privateMembers = '.sims_state_$token.members';
    final expectedCanonical = await canonicalPrivateArchiveDigest(archive);
    File? hostMembers;
    String? expectedMemberListSha256;

    Future<void> stagePrivateInputs(String phase) async {
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'cp',
        remote,
        privateArchive,
      ]);
      if (await _runAsFileSha256(device, privateArchive) != expected) {
        throw StateError('private recovery archive changed during $phase');
      }
      if (hostMembers != null) {
        await _adb(device, <String>[
          'shell',
          'run-as',
          packageName,
          'cp',
          remoteMembers,
          privateMembers,
        ]);
        if (await _runAsFileSha256(device, privateMembers) !=
            expectedMemberListSha256) {
          throw StateError(
            'private recovery member list changed during $phase',
          );
        }
      }
    }

    try {
      await _adb(device, <String>['push', archive.path, remote]);
      if (restorePlan.privilegedFilePaths.isNotEmpty) {
        hostMembers = File(
          '${backupDirectory.path}${Platform.pathSeparator}'
          '.sims-state-$token.members',
        );
        await hostMembers.writeAsBytes(
          restorePlan.privilegedMemberListBytes(),
          flush: true,
        );
        expectedMemberListSha256 = await _hostFileSha256(hostMembers);
        await _adb(device, <String>['push', hostMembers.path, remoteMembers]);
      }
      await stagePrivateInputs('staging');
      await _extractPrivateArchive(
        device,
        privateArchive,
        restorePlan,
        privateMemberList: hostMembers == null ? null : privateMembers,
      );
      if (await _privateArchiveMatches(device, snapshot, expectedCanonical)) {
        return;
      }
      // Some Android installs expose cache/code_cache with an installd-owned
      // cache gid and setgid bits that run-as tar cannot recreate. Repair the
      // package-owned roots in place, then replay the retained archive so the
      // repair cannot discard nonempty cache contents. The second full archive
      // digest remains the authoritative restoration check.
      await _repairPackageMetadataAfterPrivateRestore(device, snapshot);
      await _clearPrivateEntriesForRestore(
        device,
        preservedRoots: restorePlan.preservedRoots,
      );
      await stagePrivateInputs('restaging');
      await _extractPrivateArchive(
        device,
        privateArchive,
        restorePlan,
        privateMemberList: hostMembers == null ? null : privateMembers,
      );
      if (!await _privateArchiveMatches(device, snapshot, expectedCanonical)) {
        throw StateError('private app-data archive did not restore exactly');
      }
    } finally {
      final privateCleanup = await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'rm',
        '-f',
        privateArchive,
        privateMembers,
      ], allowFailure: true);
      final remoteCleanup = await _adb(device, <String>[
        'shell',
        'rm',
        '-f',
        remote,
        remoteMembers,
      ], allowFailure: true);
      if (hostMembers?.existsSync() ?? false) {
        hostMembers!.deleteSync();
      }
      if (privateCleanup.exitCode != 0 || remoteCleanup.exitCode != 0) {
        throw StateError('private recovery staging cleanup failed on $device');
      }
    }
  }

  Future<void> _extractPrivateArchive(
    String device,
    String privateArchive,
    _PrivateArchiveRestorePlan restorePlan, {
    required String? privateMemberList,
  }) async {
    await _preparePrivilegedCacheDirectories(device, restorePlan);
    await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'tar',
      '-xf',
      privateArchive,
      '-C',
      '.',
      for (final path in restorePlan.excludedDirectoryPaths) ...<String>[
        '--exclude',
        path,
      ],
    ]);
    if (privateMemberList != null) {
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'tar',
        '-xf',
        privateArchive,
        '-C',
        '.',
        '--null',
        '-T',
        privateMemberList,
      ]);
    }
    await _restorePrivilegedCacheDirectoryMtimes(device, restorePlan);
  }

  Future<bool> _privateArchiveMatches(
    String device,
    _PackageSnapshot snapshot,
    String expectedCanonicalDigest,
  ) async {
    // The in-place reinstall clears Android's package-stopped state, so a
    // push can have woken the app since the last stop; a fresh stop shrinks
    // (but cannot close) that window before the verify cut.
    await _forceStop(device);
    final verifyTemp = File(
      '${backupDirectory.path}${Platform.pathSeparator}'
      '${_deviceBackupDirectoryName(device)}'
      '${Platform.pathSeparator}.verify-${_token('verify')}.tar',
    );
    try {
      try {
        await _capturePrivateArchive(
          device,
          snapshot.privateEntries,
          verifyTemp,
        );
      } on AndroidAppStateBlocked {
        // A failed verify stream is fatal, not a mismatch: it must not
        // consume the repair/replay, matching the old on-device cut whose
        // adb call ran without allowFailure.
        throw StateError('private verification stream failed');
      }
      return await canonicalPrivateArchiveDigest(verifyTemp) ==
          expectedCanonicalDigest;
    } finally {
      if (verifyTemp.existsSync()) verifyTemp.deleteSync();
    }
  }

  Future<void> _preparePrivilegedCacheDirectories(
    String device,
    _PrivateArchiveRestorePlan plan,
  ) async {
    for (final directory in plan.nestedDirectories) {
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'mkdir',
        '-m',
        directory.mode.toRadixString(8),
        directory.pathWithoutTrailingSlash,
      ]);
    }
  }

  Future<void> _restorePrivilegedCacheDirectoryMtimes(
    String device,
    _PrivateArchiveRestorePlan plan,
  ) async {
    for (final directory in plan.directoriesDeepestFirst) {
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'touch',
        '-m',
        '-d',
        '@${directory.mtimeSeconds}',
        directory.pathWithoutTrailingSlash,
      ]);
    }
  }

  Future<void> _repairPackageMetadataAfterPrivateRestore(
    String device,
    _PackageSnapshot snapshot,
  ) async {
    // A run-as process cannot recreate the per-app cache gid or setgid bits
    // recorded for cache/code_cache. Reinstalling the exact retained APK asks
    // installd to repair those package-owned roots in place. This preserves the
    // package UID and Android Keystore because there is no uninstall/pm clear.
    await _installOriginalApks(device, snapshot);
    await _forceStop(device);
  }

  Future<void> _verifyInstalledApks(
    String device,
    _PackageSnapshot snapshot,
  ) async {
    final actual = <String>[
      for (final path in await _installedPackagePaths(device))
        await _deviceFileSha256(device, path),
    ]..sort();
    final expected = List<String>.from(snapshot.apkDigests)..sort();
    if (jsonEncode(actual) != jsonEncode(expected)) {
      throw StateError('original APK bytes did not restore');
    }
  }

  Future<_ProcessSnapshot> _captureProcessState(String device) async {
    final pid = await _shellText(device, <String>[
      'pidof',
      packageName,
    ], allowFailure: true);
    return _ProcessSnapshot(
      running: pid.trim().isNotEmpty,
      foreground: await _isForeground(device),
    );
  }

  Future<void> _restoreProcessState(
    String device,
    _ProcessSnapshot snapshot,
  ) async {
    if (!snapshot.running) {
      await _forceStop(device);
      return;
    }
    final launch = await _adb(device, <String>[
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$packageName/.MainActivity',
    ], allowFailure: true);
    if (launch.exitCode != 0 || '${launch.stdout}'.contains('Error:')) {
      throw StateError('original app process could not be relaunched');
    }
    await _waitFor(
      const Duration(seconds: 20),
      () async => (await _shellText(device, <String>[
        'pidof',
        packageName,
      ], allowFailure: true)).trim().isNotEmpty,
    );
    if (!snapshot.foreground) {
      await _adb(device, const <String>[
        'shell',
        'input',
        'keyevent',
        'KEYCODE_HOME',
      ]);
    }
  }

  Future<void> _verifyProcessState(
    String device,
    _ProcessSnapshot expected,
  ) async {
    final actual = await _captureProcessState(device);
    if (actual.running != expected.running ||
        (expected.running && actual.foreground != expected.foreground)) {
      throw StateError('original app process state did not restore');
    }
  }

  Future<bool> _isForeground(String device) async {
    final activities = await _shellText(device, const <String>[
      'dumpsys',
      'activity',
      'activities',
    ]);
    return activities
        .split('\n')
        .where(
          (line) =>
              line.contains('ResumedActivity') ||
              line.contains('topResumedActivity'),
        )
        .any((line) => line.contains(packageName));
  }

  Future<List<String>> _installedPackagePaths(String device) async {
    final output = await _shellText(device, <String>[
      'pm',
      'path',
      packageName,
    ], allowFailure: true);
    return output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('package:'))
        .map((line) => line.substring('package:'.length))
        .where((path) => path.startsWith('/') && !path.contains('\n'))
        .toList(growable: false);
  }

  String? _requireSingleBaseApkPath(
    List<String> paths, {
    required bool allowAbsent,
  }) {
    if (paths.isEmpty && allowAbsent) return null;
    final basePaths = paths
        .where((path) => path.split('/').last == 'base.apk')
        .toList(growable: false);
    if (basePaths.length != 1) {
      throw AndroidAppStateFailure(
        'The expected Android base APK path was not unambiguous.',
        backupDirectory: backupDirectory,
      );
    }
    return basePaths.single;
  }

  Future<Set<String>> _installedThirdPartyPackages(String device) async {
    final result = await _adb(device, const <String>[
      'shell',
      'pm',
      'list',
      'packages',
      '-3',
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw AndroidAppStateFailure(
        'The Android package inventory was unavailable on $device.',
        backupDirectory: backupDirectory,
      );
    }
    final packages = <String>{};
    for (final rawLine in '${result.stdout}'.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('package:')) {
        throw AndroidAppStateFailure(
          'The Android package inventory was malformed on $device.',
          backupDirectory: backupDirectory,
        );
      }
      final value = line.substring('package:'.length);
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(value) ||
          !packages.add(value)) {
        throw AndroidAppStateFailure(
          'The Android package inventory was malformed on $device.',
          backupDirectory: backupDirectory,
        );
      }
    }
    return packages;
  }

  Future<void> _removeUnexpectedPackages(String device) async {
    final pending = _unexpectedPackages[device];
    if (pending == null || pending.isEmpty) return;
    for (final unexpected in pending.toList()..sort()) {
      final uninstall = await _adb(device, <String>[
        'uninstall',
        unexpected,
      ], allowFailure: true);
      if (uninstall.exitCode != 0) {
        throw StateError('introduced package could not be removed');
      }
    }
    final remaining = await _installedThirdPartyPackages(device);
    if (pending.any(remaining.contains)) {
      throw StateError('introduced package is still installed');
    }
    _unexpectedPackages.remove(device);
  }

  Future<List<String>> _privateEntries(String device) async {
    final result = await _adb(device, <String>[
      'shell',
      'run-as',
      packageName,
      'ls',
      '-1',
      '-A',
      '.',
    ], allowFailure: true);
    if (result.exitCode != 0) {
      throw StateError('private app-data inventory is unavailable');
    }
    final entries = '${result.stdout}'
        .split('\n')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (entries.any(
      (entry) =>
          !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(entry) ||
          entry == '.' ||
          entry == '..',
    )) {
      throw StateError('private app-data inventory is unsafe');
    }
    return entries;
  }

  Future<void> _clearPrivateEntries(String device) async {
    for (final entry in await _privateEntries(device)) {
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'rm',
        '-rf',
        '--',
        entry,
      ]);
    }
  }

  Future<void> _clearPrivateEntriesForRestore(
    String device, {
    required Set<String> preservedRoots,
  }) async {
    for (final entry in await _privateEntries(device)) {
      if (preservedRoots.contains(entry)) {
        final root = await _adb(device, <String>[
          'shell',
          'run-as',
          packageName,
          'test',
          '-d',
          entry,
        ], allowFailure: true);
        if (root.exitCode == 0) {
          // Package Installer owns the cache roots' cache GID and setgid mode.
          // Keep those roots intact and remove only their children so run-as
          // tar can restore a nonempty code_cache without losing metadata.
          await _adb(device, <String>[
            'shell',
            'run-as',
            packageName,
            'find',
            entry,
            '-mindepth',
            '1',
            '-maxdepth',
            '1',
            '-exec',
            'rm',
            '-rf',
            '--',
            '{}',
            r'\;',
          ]);
          continue;
        }
      }
      await _adb(device, <String>[
        'shell',
        'run-as',
        packageName,
        'rm',
        '-rf',
        '--',
        entry,
      ]);
    }
  }

  Future<Map<String, bool>> _runtimePermissionSnapshot(String device) async {
    final dump = await _shellText(device, <String>[
      'dumpsys',
      'package',
      packageName,
    ]);
    final values = <String, bool>{};
    for (final match in RegExp(
      r'(android\.permission\.[A-Z0-9_]+):\s+granted=(true|false)',
    ).allMatches(dump)) {
      final permission = match.group(1)!;
      if (_restorableRuntimePermissions.contains(permission)) {
        values[permission] = match.group(2) == 'true';
      }
    }
    return values;
  }

  Future<void> _restoreRuntimePermissions(
    String device,
    Map<String, bool> expected,
  ) async {
    for (final entry in expected.entries) {
      final result = await _adb(device, <String>[
        'shell',
        'pm',
        entry.value ? 'grant' : 'revoke',
        packageName,
        entry.key,
      ], allowFailure: true);
      if (result.exitCode != 0) {
        throw StateError('runtime permission restore failed');
      }
    }
    final actual = await _runtimePermissionSnapshot(device);
    for (final entry in expected.entries) {
      if (actual[entry.key] != entry.value) {
        throw StateError('runtime permission state did not restore');
      }
    }
  }

  Future<String> _deviceFileSha256(String device, String path) async {
    final output = await _shellText(device, <String>['sha256sum', path]);
    return _parseSha256(output, 'device file');
  }

  Future<String> _runAsFileSha256(String device, String path) async {
    final output = await _shellText(device, <String>[
      'run-as',
      packageName,
      'sha256sum',
      path,
    ]);
    return _parseSha256(output, 'private archive');
  }

  String _parseSha256(String output, String label) {
    final value = output.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw StateError('$label SHA-256 is unavailable');
    }
    return value;
  }

  Future<String> _hostFileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<String> _validatePreparedArtifact(
    File artifact, {
    required String? expectedArtifactSha256,
  }) async {
    if (expectedArtifactSha256 != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedArtifactSha256)) {
      throw AndroidAppStateFailure(
        'The expected Android artifact digest was invalid.',
        backupDirectory: backupDirectory,
      );
    }
    final digest = await _hostFileSha256(artifact);
    if (expectedArtifactSha256 != null && digest != expectedArtifactSha256) {
      throw AndroidAppStateFailure(
        'The central Android artifact changed before device mutation.',
        backupDirectory: backupDirectory,
      );
    }
    final artifactPackage = await _preparedArtifactPackageName(artifact);
    if (artifactPackage != packageName) {
      throw AndroidAppStateFailure(
        'The central Android artifact application ID did not match the '
        'captured package.',
        backupDirectory: backupDirectory,
      );
    }
    await _requirePreparedArtifactDigest(
      artifact,
      digest,
      phase: 'after application ID validation',
    );
    return digest;
  }

  Future<String> _preparedArtifactPackageName(File artifact) async {
    for (final executable in _apkAnalyzerCandidates()) {
      late final ProcessResult result;
      try {
        result = await _runner.run(executable, <String>[
          'manifest',
          'application-id',
          artifact.path,
        ]);
      } on ProcessException {
        continue;
      }
      final values = '${result.stdout}'
          .split('\n')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      if (result.exitCode == 0 &&
          values.length == 1 &&
          RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(values.single)) {
        return values.single;
      }
    }
    throw AndroidAppStateFailure(
      'The central Android artifact application ID could not be proven.',
      backupDirectory: backupDirectory,
    );
  }

  List<String> _apkAnalyzerCandidates() {
    final candidates = <String>[];
    final roots = <String>{
      for (final name in const <String>['ANDROID_HOME', 'ANDROID_SDK_ROOT'])
        if ((Platform.environment[name] ?? '').trim().isNotEmpty)
          Platform.environment[name]!.trim(),
    };
    for (final root in roots) {
      final commandLineTools = Directory(
        '$root${Platform.pathSeparator}cmdline-tools',
      );
      if (!commandLineTools.existsSync()) continue;
      final versions =
          commandLineTools
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort((left, right) => right.path.compareTo(left.path));
      for (final version in versions) {
        final executable = File(
          '${version.path}${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}apkanalyzer',
        );
        if (executable.existsSync()) candidates.add(executable.path);
      }
    }
    candidates.add('apkanalyzer');
    return candidates.toSet().toList(growable: false);
  }

  Future<void> _requirePreparedArtifactDigest(
    File artifact,
    String expected, {
    required String phase,
  }) async {
    if (FileSystemEntity.typeSync(artifact.path, followLinks: true) !=
            FileSystemEntityType.file ||
        await _hostFileSha256(artifact) != expected) {
      throw AndroidAppStateFailure(
        'The central Android artifact changed $phase.',
        backupDirectory: backupDirectory,
      );
    }
  }

  Future<void> _forceStop(String device) async {
    final result = await _adb(
      device,
      <String>['shell', 'am', 'force-stop', packageName],
      allowFailure: true,
      retryAnyNonzero: true,
    );
    if (result.exitCode != 0) {
      throw StateError('app process could not be stopped on $device');
    }
  }

  Future<String> _shellText(
    String device,
    List<String> command, {
    bool allowFailure = false,
  }) async {
    final result = await _adb(device, <String>[
      'shell',
      ...command,
    ], allowFailure: allowFailure);
    return '${result.stdout}';
  }

  Future<ProcessResult> _adb(
    String device,
    List<String> arguments, {
    bool allowFailure = false,
    bool retryAnyNonzero = false,
    Duration? commandTimeout,
  }) async {
    for (var attempt = 1; attempt <= _adbReconnectMaximumAttempts; attempt++) {
      late final ProcessResult result;
      try {
        final command = <String>['-s', device, ...arguments];
        final timeoutRunner = _runner;
        result =
            commandTimeout != null &&
                timeoutRunner is AndroidHostProcessRunnerWithTimeout
            ? await timeoutRunner.runWithTimeout(
                'adb',
                command,
                timeout: commandTimeout,
              )
            : await _runner.run('adb', command);
      } on ProcessException {
        if (allowFailure) return ProcessResult(0, 127, '', '');
        throw const AndroidAppStateBlocked('ADB could not start.');
      }
      if (result.exitCode != 0 &&
          (retryAnyNonzero || _isTransientAdbTransportFailure(result)) &&
          attempt < _adbReconnectMaximumAttempts) {
        await Future<void>.delayed(_adbReconnectRetryDelay);
        continue;
      }
      if (!allowFailure && result.exitCode != 0) {
        throw StateError('ADB state-guard operation failed');
      }
      return result;
    }
    throw StateError('unreachable ADB reconnect retry state');
  }

  Future<void> _waitFor(Duration timeout, Future<bool> Function() check) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await check()) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('timed out restoring Android app process');
  }

  void _requireCapturedDevice(String device) {
    if (!devices.contains(device) || !_snapshots.containsKey(device)) {
      throw AndroidAppStateFailure(
        'Android target was not captured by this state guard.',
        backupDirectory: backupDirectory,
      );
    }
  }

  String _token(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    return '$prefix-${base64Url.encode(bytes).replaceAll('=', '')}';
  }
}

final class _PreliminarySnapshot {
  const _PreliminarySnapshot({
    required this.packagePaths,
    required this.process,
    required this.runtimePermissions,
  });

  final List<String> packagePaths;
  final _ProcessSnapshot process;
  final Map<String, bool> runtimePermissions;
}

final class _PrivateArchiveRestorePlan {
  const _PrivateArchiveRestorePlan._(
    this.directories,
    this.privilegedFilePaths,
  );

  factory _PrivateArchiveRestorePlan.fromSnapshot(_PackageSnapshot snapshot) {
    final archive = snapshot.privateArchive;
    if (archive == null || snapshot.privateEntries.isEmpty) {
      return const _PrivateArchiveRestorePlan._(
        <_TarDirectoryMetadata>[],
        <String>[],
      );
    }
    final metadata = _readCacheArchiveMetadata(archive);
    final cacheDirectories = metadata.directories;
    final byPath = <String, _TarDirectoryMetadata>{
      for (final directory in cacheDirectories) directory.path: directory,
    };
    final privileged = <_TarDirectoryMetadata>[];
    for (final root in const <String>['cache/', 'code_cache/']) {
      final rootMetadata = byPath[root];
      if (rootMetadata == null || !rootMetadata.requiresInstallerMetadata) {
        continue;
      }
      final descendants = cacheDirectories
          .where((directory) => directory.path.startsWith(root))
          .toList(growable: false);
      if (descendants.any(
        (directory) =>
            directory.uid != rootMetadata.uid ||
            directory.gid != rootMetadata.gid ||
            !directory.requiresInstallerMetadata,
      )) {
        throw const FormatException(
          'private cache archive has unsupported mixed directory metadata',
        );
      }
      privileged.addAll(descendants);
    }
    privileged.sort((left, right) => left.archiveIndex - right.archiveIndex);
    final privilegedRoots = <String>{
      for (final directory in privileged)
        if (directory.depth == 1) directory.path,
    };
    final privilegedFiles = <String>[];
    for (final member in metadata.nonDirectoryMembers) {
      if (!privilegedRoots.any(member.path.startsWith)) continue;
      if (!member.isRegularFile) {
        throw const FormatException(
          'private cache archive has an unsupported non-regular member',
        );
      }
      privilegedFiles.add(member.path);
    }
    return _PrivateArchiveRestorePlan._(
      List<_TarDirectoryMetadata>.unmodifiable(privileged),
      List<String>.unmodifiable(privilegedFiles),
    );
  }

  final List<_TarDirectoryMetadata> directories;
  final List<String> privilegedFilePaths;

  Set<String> get preservedRoots => <String>{
    for (final directory in directories)
      if (directory.depth == 1) directory.pathWithoutTrailingSlash,
  };

  Iterable<_TarDirectoryMetadata> get nestedDirectories =>
      directories.where((directory) => directory.depth > 1);

  Iterable<String> get excludedDirectoryPaths =>
      directories.map((directory) => directory.path);

  List<int> privilegedMemberListBytes() {
    final result = <int>[];
    for (final path in privilegedFilePaths) {
      result
        ..addAll(utf8.encode(path))
        ..add(0);
      if (result.length > _maximumPrivateRestoreMemberListBytes) {
        throw const FormatException(
          'private cache archive member list exceeds the restore limit',
        );
      }
    }
    return result;
  }

  List<_TarDirectoryMetadata> get directoriesDeepestFirst {
    final result = List<_TarDirectoryMetadata>.from(directories)
      ..sort((left, right) {
        final depth = right.depth.compareTo(left.depth);
        return depth != 0
            ? depth
            : right.archiveIndex.compareTo(left.archiveIndex);
      });
    return result;
  }
}

final class _TarArchiveMetadata {
  const _TarArchiveMetadata(this.directories, this.nonDirectoryMembers);

  final List<_TarDirectoryMetadata> directories;
  final List<_TarMemberMetadata> nonDirectoryMembers;
}

final class _TarMemberMetadata {
  const _TarMemberMetadata({required this.path, required this.type});

  final String path;
  final int type;

  bool get isRegularFile => type == 0 || type == 48;
}

final class _TarDirectoryMetadata {
  const _TarDirectoryMetadata({
    required this.path,
    required this.mode,
    required this.uid,
    required this.gid,
    required this.mtimeSeconds,
    required this.archiveIndex,
  });

  final String path;
  final int mode;
  final int uid;
  final int gid;
  final int mtimeSeconds;
  final int archiveIndex;

  bool get requiresInstallerMetadata => gid != uid || (mode & 0x400) != 0;
  String get pathWithoutTrailingSlash => path.substring(0, path.length - 1);
  int get depth => '/'.allMatches(pathWithoutTrailingSlash).length + 1;
}

_TarArchiveMetadata _readCacheArchiveMetadata(File archive) {
  final input = archive.openSync();
  final directories = <_TarDirectoryMetadata>[];
  final members = <_TarMemberMetadata>[];
  var archiveIndex = 0;
  String? pendingPath;
  try {
    while (true) {
      final header = input.readSync(512);
      if (header.isEmpty) break;
      if (header.length != 512) {
        throw const FormatException('private archive has a partial header');
      }
      if (header.every((byte) => byte == 0)) break;
      final name = _tarString(header, 0, 100);
      final prefix = _tarString(header, 345, 155);
      final size = _tarOctal(header, 124, 12);
      final type = header[156];
      final paddedSize = ((size + 511) ~/ 512) * 512;
      if (type == 76 || type == 120) {
        final payload = input.readSync(paddedSize);
        if (payload.length != paddedSize) {
          throw const FormatException(
            'private archive has a partial metadata record',
          );
        }
        final value = payload.sublist(0, size);
        pendingPath = type == 76
            ? _tarLongPath(value)
            : _tarPaxPath(value) ?? pendingPath;
        archiveIndex += 1;
        continue;
      }
      final path = pendingPath ?? (prefix.isEmpty ? name : '$prefix/$name');
      pendingPath = null;
      final directoryPath = path.endsWith('/') ? path : '$path/';
      if ((type == 53 || path.endsWith('/')) &&
          (directoryPath == 'cache/' ||
              directoryPath.startsWith('cache/') ||
              directoryPath == 'code_cache/' ||
              directoryPath.startsWith('code_cache/'))) {
        if (!_safeTarDirectoryPath(directoryPath)) {
          throw const FormatException('private cache archive path is unsafe');
        }
        directories.add(
          _TarDirectoryMetadata(
            path: directoryPath,
            mode: _tarOctal(header, 100, 8),
            uid: _tarOctal(header, 108, 8),
            gid: _tarOctal(header, 116, 8),
            mtimeSeconds: _tarOctal(header, 136, 12),
            archiveIndex: archiveIndex,
          ),
        );
      } else if (path == 'cache' ||
          path.startsWith('cache/') ||
          path == 'code_cache' ||
          path.startsWith('code_cache/')) {
        if (!_safeTarMemberPath(path)) {
          throw const FormatException('private cache archive path is unsafe');
        }
        members.add(_TarMemberMetadata(path: path, type: type));
      }
      input.setPositionSync(input.positionSync() + paddedSize);
      archiveIndex += 1;
    }
  } finally {
    input.closeSync();
  }
  return _TarArchiveMetadata(
    List<_TarDirectoryMetadata>.unmodifiable(directories),
    List<_TarMemberMetadata>.unmodifiable(members),
  );
}

String _tarLongPath(List<int> payload) {
  var end = payload.indexOf(0);
  if (end < 0) end = payload.length;
  return utf8.decode(payload.sublist(0, end), allowMalformed: false);
}

String? _tarPaxPath(List<int> payload) {
  final text = utf8.decode(payload, allowMalformed: false);
  return RegExp(r'(?:^|\n)[0-9]+ path=([^\n]+)').firstMatch(text)?.group(1);
}

String _tarString(List<int> header, int offset, int length) {
  final end = offset + length;
  var stop = offset;
  while (stop < end && header[stop] != 0) {
    stop += 1;
  }
  return ascii.decode(header.sublist(offset, stop), allowInvalid: false).trim();
}

int _tarOctal(List<int> header, int offset, int length) {
  final value = _tarString(header, offset, length).trim();
  if (value.isEmpty || !RegExp(r'^[0-7]+$').hasMatch(value)) {
    throw const FormatException('private archive numeric field is invalid');
  }
  return int.parse(value, radix: 8);
}

bool _safeTarDirectoryPath(String path) {
  if (!path.endsWith('/') || path.startsWith('/')) return false;
  final segments = path
      .substring(0, path.length - 1)
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  return segments.isNotEmpty &&
      segments.every(
        (segment) =>
            segment != '.' &&
            segment != '..' &&
            RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(segment),
      );
}

bool _safeTarMemberPath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.endsWith('/')) return false;
  if (path.codeUnits.any((codeUnit) => codeUnit < 0x20 || codeUnit == 0x7f)) {
    return false;
  }
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

const int _maximumCanonicalPreludeBytes = 1024 * 1024;
const int _canonicalPayloadChunkBytes = 256 * 1024;

final class _SingleDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

final class _ChunkedSha256 {
  _ChunkedSha256() {
    _conversion = sha256.startChunkedConversion(_sink);
  }

  final _SingleDigestSink _sink = _SingleDigestSink();
  late final Sink<List<int>> _conversion;

  void add(List<int> bytes) => _conversion.add(bytes);

  Digest close() {
    _conversion.close();
    return _sink.value!;
  }
}

final class _CanonicalMemberRecord {
  _CanonicalMemberRecord(this.path, Digest digest)
    : digestHex = digest.toString(),
      digestBytes = digest.bytes;

  final String path;
  final String digestHex;
  final List<int> digestBytes;
}

/// Order-insensitive canonical digest of a private-data tar archive.
///
/// Digests each member's full byte span (GNU long-name prelude records, the
/// 512-byte header, and the zero-padded payload) and hashes the records
/// sorted by (logical path, record digest), so two cuts of the same tree
/// state compare equal regardless of on-device directory enumeration order —
/// re-created directories enumerate differently on some /data filesystems,
/// which is exactly the false negative a whole-archive digest produces.
/// Everything after the first all-zero trailer block is ignored. Throws
/// [FormatException] on malformed input instead of returning a digest.
Future<String> canonicalPrivateArchiveDigest(File archive) async {
  final input = archive.openSync();
  try {
    final records = <_CanonicalMemberRecord>[];
    String? pendingPath;
    _ChunkedSha256? preludeSpan;
    while (true) {
      final header = input.readSync(512);
      if (header.isEmpty || header.every((byte) => byte == 0)) {
        if (pendingPath != null || preludeSpan != null) {
          throw const FormatException(
            'private archive has a dangling long-name record',
          );
        }
        break;
      }
      if (header.length != 512) {
        throw const FormatException('private archive has a partial header');
      }
      final size = _tarOctal(header, 124, 12);
      final type = header[156];
      final paddedSize = ((size + 511) ~/ 512) * 512;
      if (type == 76 || type == 120) {
        if (size > _maximumCanonicalPreludeBytes) {
          throw const FormatException(
            'private archive long-name record is oversized',
          );
        }
        final payload = input.readSync(paddedSize);
        if (payload.length != paddedSize) {
          throw const FormatException(
            'private archive has a partial metadata record',
          );
        }
        final value = payload.sublist(0, size);
        pendingPath = type == 76
            ? _tarLongPath(value)
            : (_tarPaxPath(value) ?? pendingPath);
        (preludeSpan ??= _ChunkedSha256())
          ..add(header)
          ..add(payload);
        continue;
      }
      final name = _tarString(header, 0, 100);
      final prefix = _tarString(header, 345, 155);
      final path = pendingPath ?? (prefix.isEmpty ? name : '$prefix/$name');
      pendingPath = null;
      final span = (preludeSpan ?? _ChunkedSha256())..add(header);
      preludeSpan = null;
      var remaining = paddedSize;
      while (remaining > 0) {
        final chunk = input.readSync(
          min(remaining, _canonicalPayloadChunkBytes),
        );
        if (chunk.isEmpty) {
          throw const FormatException('private archive has a partial member');
        }
        span.add(chunk);
        remaining -= chunk.length;
      }
      records.add(_CanonicalMemberRecord(path, span.close()));
    }
    records.sort((left, right) {
      final byPath = left.path.compareTo(right.path);
      return byPath != 0 ? byPath : left.digestHex.compareTo(right.digestHex);
    });
    final whole = _ChunkedSha256();
    for (final record in records) {
      whole
        ..add(utf8.encode(record.path))
        ..add(const <int>[0])
        ..add(record.digestBytes);
    }
    return whole.close().toString();
  } finally {
    input.closeSync();
  }
}

final class _PackageSnapshot {
  const _PackageSnapshot({
    required this.installed,
    required this.process,
    required this.apkFiles,
    required this.apkDigests,
    required this.privateEntries,
    required this.privateArchive,
    required this.privateArchiveSha256,
    required this.runtimePermissions,
  });

  const _PackageSnapshot.absent(this.process)
    : installed = false,
      apkFiles = const <File>[],
      apkDigests = const <String>[],
      privateEntries = const <String>[],
      privateArchive = null,
      privateArchiveSha256 = null,
      runtimePermissions = const <String, bool>{};

  final bool installed;
  final _ProcessSnapshot process;
  final List<File> apkFiles;
  final List<String> apkDigests;
  final List<String> privateEntries;
  final File? privateArchive;
  final String? privateArchiveSha256;
  final Map<String, bool> runtimePermissions;
}

final class _ProcessSnapshot {
  const _ProcessSnapshot({required this.running, required this.foreground});

  final bool running;
  final bool foreground;
}

final class _RecoveredGuardData {
  const _RecoveredGuardData({
    required this.packageName,
    required this.devices,
    required this.snapshots,
  });

  final String packageName;
  final List<String> devices;
  final Map<String, _PackageSnapshot> snapshots;
}

final class _RecoveryManifestCodec {
  static Map<String, Object?> encode({
    required String packageName,
    required List<String> devices,
    required Map<String, _PackageSnapshot> snapshots,
  }) {
    return <String, Object?>{
      'schema': _recoveryManifestSchema,
      'redacted': true,
      'packageName': packageName,
      'devices': <Object?>[
        for (final device in devices)
          _encodeSnapshot(device, snapshots[device]!),
      ],
    };
  }

  static Map<String, Object?> _encodeSnapshot(
    String device,
    _PackageSnapshot snapshot,
  ) {
    final permissions = snapshot.runtimePermissions.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return <String, Object?>{
      'device': device,
      'installed': snapshot.installed,
      'process': <String, Object?>{
        'running': snapshot.process.running,
        'foreground': snapshot.process.foreground,
      },
      'runtimePermissions': <String, Object?>{
        for (final permission in permissions) permission.key: permission.value,
      },
      'apks': <Object?>[
        for (var index = 0; index < snapshot.apkFiles.length; index += 1)
          <String, Object?>{
            'file': 'installed-$index.apk',
            'bytes': snapshot.apkFiles[index].lengthSync(),
            'sha256': snapshot.apkDigests[index],
          },
      ],
      'privateData': <String, Object?>{
        'entries': snapshot.privateEntries,
        'file': snapshot.privateArchive == null ? null : 'private-data.tar',
        'bytes': snapshot.privateArchive?.lengthSync(),
        'sha256': snapshot.privateArchiveSha256,
      },
    };
  }

  static Future<_RecoveredGuardData> read({
    required Directory backupDirectory,
    required int maximumPrivateBackupBytes,
  }) async {
    if (FileSystemEntity.typeSync(backupDirectory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FormatException('recovery directory is unavailable');
    }
    final manifest = File(
      '${backupDirectory.path}${Platform.pathSeparator}$_recoveryManifestName',
    );
    final digestFile = File(
      '${backupDirectory.path}${Platform.pathSeparator}'
      '$_recoveryManifestDigestName',
    );
    _requireRegularFile(manifest);
    _requireRegularFile(digestFile);
    final manifestBytes = await manifest.length();
    if (manifestBytes <= 0 || manifestBytes > 1024 * 1024) {
      throw const FormatException('recovery manifest size is invalid');
    }
    if (await digestFile.length() > 256) {
      throw const FormatException('recovery manifest digest is invalid');
    }
    final expectedManifestDigest = (await digestFile.readAsString()).trim();
    _requireSha256(expectedManifestDigest);
    if (await _fileSha256(manifest) != expectedManifestDigest) {
      throw const FormatException('recovery manifest digest drifted');
    }

    final root = _asMap(jsonDecode(await manifest.readAsString()));
    _requireExactKeys(root, const <String>{
      'schema',
      'redacted',
      'packageName',
      'devices',
    });
    if (root['schema'] != _recoveryManifestSchema || root['redacted'] != true) {
      throw const FormatException('recovery manifest schema is invalid');
    }
    final packageName = _asString(root['packageName']);
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName)) {
      throw const FormatException('recovery package is invalid');
    }
    final encodedDevices = _asList(root['devices']);
    if (encodedDevices.isEmpty || encodedDevices.length > 32) {
      throw const FormatException('recovery device inventory is invalid');
    }
    final devices = <String>[];
    final snapshots = <String, _PackageSnapshot>{};
    final directoryNames = <String>{};
    for (final encodedDevice in encodedDevices) {
      final snapshotMap = _asMap(encodedDevice);
      _requireExactKeys(snapshotMap, const <String>{
        'device',
        'installed',
        'process',
        'runtimePermissions',
        'apks',
        'privateData',
      });
      final device = _asString(snapshotMap['device']);
      if (!RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(device) ||
          snapshots.containsKey(device) ||
          !directoryNames.add(_deviceBackupDirectoryName(device))) {
        throw const FormatException('recovery target is invalid');
      }
      final deviceDirectory = Directory(
        '${backupDirectory.path}${Platform.pathSeparator}'
        '${_deviceBackupDirectoryName(device)}',
      );
      if (_asBool(snapshotMap['installed']) &&
          FileSystemEntity.typeSync(deviceDirectory.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const FormatException('recovery target directory is invalid');
      }
      final snapshot = await _decodeSnapshot(
        snapshotMap,
        deviceDirectory: deviceDirectory,
        maximumPrivateBackupBytes: maximumPrivateBackupBytes,
      );
      devices.add(device);
      snapshots[device] = snapshot;
    }
    return _RecoveredGuardData(
      packageName: packageName,
      devices: List<String>.unmodifiable(devices),
      snapshots: Map<String, _PackageSnapshot>.unmodifiable(snapshots),
    );
  }

  static Future<_PackageSnapshot> _decodeSnapshot(
    Map<String, Object?> encoded, {
    required Directory deviceDirectory,
    required int maximumPrivateBackupBytes,
  }) async {
    final installed = _asBool(encoded['installed']);
    final processMap = _asMap(encoded['process']);
    _requireExactKeys(processMap, const <String>{'running', 'foreground'});
    final process = _ProcessSnapshot(
      running: _asBool(processMap['running']),
      foreground: _asBool(processMap['foreground']),
    );
    if (process.foreground && !process.running) {
      throw const FormatException('recovery process state is invalid');
    }

    final permissionsMap = _asMap(encoded['runtimePermissions']);
    if (permissionsMap.length > _restorableRuntimePermissions.length) {
      throw const FormatException('recovery permission inventory is invalid');
    }
    final permissions = <String, bool>{};
    for (final permission in permissionsMap.entries) {
      if (!_restorableRuntimePermissions.contains(permission.key)) {
        throw const FormatException('recovery permission is invalid');
      }
      permissions[permission.key] = _asBool(permission.value);
    }

    final encodedApks = _asList(encoded['apks']);
    if (encodedApks.length > 256) {
      throw const FormatException('recovery APK inventory is invalid');
    }
    final apkFiles = <File>[];
    final apkDigests = <String>[];
    for (var index = 0; index < encodedApks.length; index += 1) {
      final apk = _asMap(encodedApks[index]);
      _requireExactKeys(apk, const <String>{'file', 'bytes', 'sha256'});
      final fileName = _asString(apk['file']);
      if (fileName != 'installed-$index.apk') {
        throw const FormatException('recovery APK path is invalid');
      }
      final digest = _asString(apk['sha256']);
      final file = File(
        '${deviceDirectory.path}${Platform.pathSeparator}$fileName',
      );
      await _verifyAttestedFile(
        file,
        expectedBytes: _asInt(apk['bytes']),
        expectedSha256: digest,
      );
      apkFiles.add(file);
      apkDigests.add(digest);
    }

    final privateData = _asMap(encoded['privateData']);
    _requireExactKeys(privateData, const <String>{
      'entries',
      'file',
      'bytes',
      'sha256',
    });
    final privateEntries = <String>[];
    for (final value in _asList(privateData['entries'])) {
      final entry = _asString(value);
      if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(entry) ||
          entry == '.' ||
          entry == '..' ||
          privateEntries.contains(entry) ||
          privateEntries.length >= 1024) {
        throw const FormatException('recovery private inventory is invalid');
      }
      privateEntries.add(entry);
    }
    File? privateArchive;
    String? privateArchiveDigest;
    if (privateEntries.isEmpty) {
      if (privateData['file'] != null ||
          privateData['bytes'] != null ||
          privateData['sha256'] != null) {
        throw const FormatException('empty recovery archive is invalid');
      }
    } else {
      if (_asString(privateData['file']) != 'private-data.tar') {
        throw const FormatException('recovery private path is invalid');
      }
      privateArchiveDigest = _asString(privateData['sha256']);
      privateArchive = File(
        '${deviceDirectory.path}${Platform.pathSeparator}private-data.tar',
      );
      final archiveBytes = _asInt(privateData['bytes']);
      if (archiveBytes > maximumPrivateBackupBytes) {
        throw const FormatException('recovery private archive is too large');
      }
      await _verifyAttestedFile(
        privateArchive,
        expectedBytes: archiveBytes,
        expectedSha256: privateArchiveDigest,
      );
    }

    if (!installed) {
      if (apkFiles.isNotEmpty ||
          permissions.isNotEmpty ||
          privateEntries.isNotEmpty ||
          process.running ||
          process.foreground) {
        throw const FormatException('absent recovery package is inconsistent');
      }
      return _PackageSnapshot.absent(process);
    }
    if (apkFiles.isEmpty) {
      throw const FormatException('installed recovery package lacks an APK');
    }
    return _PackageSnapshot(
      installed: true,
      process: process,
      apkFiles: List<File>.unmodifiable(apkFiles),
      apkDigests: List<String>.unmodifiable(apkDigests),
      privateEntries: List<String>.unmodifiable(privateEntries),
      privateArchive: privateArchive,
      privateArchiveSha256: privateArchiveDigest,
      runtimePermissions: Map<String, bool>.unmodifiable(permissions),
    );
  }

  static Future<void> _verifyAttestedFile(
    File file, {
    required int expectedBytes,
    required String expectedSha256,
  }) async {
    _requireSha256(expectedSha256);
    _requireRegularFile(file);
    if (expectedBytes <= 0 || await file.length() != expectedBytes) {
      throw const FormatException('recovery artifact size drifted');
    }
    if (await _fileSha256(file) != expectedSha256) {
      throw const FormatException('recovery artifact digest drifted');
    }
  }

  static void _requireRegularFile(File file) {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FormatException('recovery artifact is unavailable');
    }
  }

  static Future<String> _fileSha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) throw const FormatException('expected object');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) throw const FormatException('invalid key');
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static List<Object?> _asList(Object? value) {
    if (value is! List) throw const FormatException('expected list');
    return List<Object?>.from(value);
  }

  static String _asString(Object? value) {
    if (value is! String) throw const FormatException('expected string');
    return value;
  }

  static bool _asBool(Object? value) {
    if (value is! bool) throw const FormatException('expected boolean');
    return value;
  }

  static int _asInt(Object? value) {
    if (value is! int) throw const FormatException('expected integer');
    return value;
  }

  static void _requireSha256(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const FormatException('expected SHA-256');
    }
  }

  static void _requireExactKeys(
    Map<String, Object?> value,
    Set<String> expected,
  ) {
    if (value.length != expected.length ||
        value.keys.any((key) => !expected.contains(key))) {
      throw const FormatException('unexpected recovery field');
    }
  }
}
