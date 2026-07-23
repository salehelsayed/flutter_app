import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';

import '../support/android_app_state_guard.dart';
import '../support/group_media_android_disposable_app.dart';
import '../support/ios_xctestrun_relocator.dart';
import 'group_media_ios_background_recovery_evidence.dart';
import 'group_media_prepared_artifact_custody.dart';
import 'group_media_reliability_criteria.dart';

const String _bundleId = groupMediaIosDisposableBundleId;
const String _developmentTeamId = '397R9Q4WMX';
const String groupMediaIosFixtureDriverEnvironment =
    'SIMS_GROUP_MEDIA_IOS_FIXTURE_DRIVER';
const String groupMediaIosFixtureDriverRepositoryPath =
    'integration_test/scripts/group_media_ios_fixture_driver.dart';

/// Must be supplied externally with the exact receiver UDID. The harness must
/// never infer this authorization merely because a physical device is present.
const String groupMediaIosDedicatedDisposableDeviceEnvironment =
    'SIMS_GROUP_MEDIA_IOS_DEDICATED_DISPOSABLE_DEVICE';

const String _bundleSchema = 'mknoon.sims.ios-device-group-media-269-bundle.v1';
const String _uiMarkerPrefix = 'MKNOON_269_IOS_EVENT ';
const List<String> _requiredUiMarkers = <String>[
  'local_network_permission_ready',
  'phase_a_ready',
  'phase_a_home',
  'phase_a_effect_once',
  'phase_b_ready',
  'phase_b_home',
  'phase_b_relaunch_root_without_group',
  'phase_b_effect_once',
];
const List<String> _androidResetActions = <String>[
  'phase-a-background-success',
  'phase-b-stop-at-post-claim',
];

final Random _secureRandom = Random.secure();

final RegExp _safeRunId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$');
final RegExp _safeAndroidTarget = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$',
);
final RegExp _physicalIosTarget = RegExp(r'^[A-Fa-f0-9-]{24,64}$');
final RegExp _digestPattern = RegExp(r'^[0-9a-f]{64}$');
const Set<String> _forbiddenIphone13ProductTypes = <String>{
  'iPhone14,2',
  'iPhone14,3',
  'iPhone14,4',
  'iPhone14,5',
};

bool groupMediaIosReceiverProductTypeAllowed(String productType) =>
    productType.startsWith('iPhone') &&
    !_forbiddenIphone13ProductTypes.contains(productType);

final class GroupMediaIosBackgroundRecoveryOptions {
  const GroupMediaIosBackgroundRecoveryOptions({
    required this.runId,
    required this.preparedBundle,
    required this.proofDirectory,
    required this.fixtureDriver,
    required this.senderDeviceId,
    required this.receiverDeviceId,
    required this.inheritedEnvironment,
    required this.androidCompanionArtifact,
    required this.androidCompanionArtifactSha256,
    this.buildGuardLog,
  });

  final String runId;
  final Directory preparedBundle;
  final Directory proofDirectory;
  final File fixtureDriver;
  final String senderDeviceId;
  final String receiverDeviceId;
  final Map<String, String> inheritedEnvironment;
  final File androidCompanionArtifact;
  final String androidCompanionArtifactSha256;
  final File? buildGuardLog;

  GroupMediaIosBackgroundRecoveryOptions copyWith({
    String? runId,
    Directory? preparedBundle,
    Directory? proofDirectory,
    File? fixtureDriver,
    String? senderDeviceId,
    String? receiverDeviceId,
    Map<String, String>? inheritedEnvironment,
    File? androidCompanionArtifact,
    String? androidCompanionArtifactSha256,
    File? buildGuardLog,
  }) => GroupMediaIosBackgroundRecoveryOptions(
    runId: runId ?? this.runId,
    preparedBundle: preparedBundle ?? this.preparedBundle,
    proofDirectory: proofDirectory ?? this.proofDirectory,
    fixtureDriver: fixtureDriver ?? this.fixtureDriver,
    senderDeviceId: senderDeviceId ?? this.senderDeviceId,
    receiverDeviceId: receiverDeviceId ?? this.receiverDeviceId,
    inheritedEnvironment: inheritedEnvironment ?? this.inheritedEnvironment,
    androidCompanionArtifact:
        androidCompanionArtifact ?? this.androidCompanionArtifact,
    androidCompanionArtifactSha256:
        androidCompanionArtifactSha256 ?? this.androidCompanionArtifactSha256,
    buildGuardLog: buildGuardLog ?? this.buildGuardLog,
  );
}

final class GroupMediaIosCommand {
  const GroupMediaIosCommand({
    required this.label,
    required this.executable,
    required this.arguments,
    this.environment = const <String, String>{},
    this.timeout = const Duration(minutes: 2),
  });

  final String label;
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final Duration timeout;
}

final class GroupMediaIosCommandResult {
  const GroupMediaIosCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  factory GroupMediaIosCommandResult.success(String stdout) =>
      GroupMediaIosCommandResult(exitCode: 0, stdout: stdout, stderr: '');

  final int exitCode;
  final String stdout;
  final String stderr;
}

abstract interface class GroupMediaIosCommandRunner {
  Future<GroupMediaIosCommandResult> run(GroupMediaIosCommand command);

  Future<GroupMediaIosCommandResult> runStreaming(
    GroupMediaIosCommand command, {
    required Future<void> Function(String line) onLine,
  });
}

abstract interface class GroupMediaIosCoreDeviceRecovery {
  Future<bool> recover();
}

final class SystemGroupMediaIosCoreDeviceRecovery
    implements GroupMediaIosCoreDeviceRecovery {
  const SystemGroupMediaIosCoreDeviceRecovery({
    this.restartDelay = const Duration(seconds: 2),
  });

  final Duration restartDelay;

  @override
  Future<bool> recover() async {
    if (!Platform.isMacOS) return false;
    late final ProcessResult result;
    try {
      result = await Process.run('/usr/bin/killall', const <String>[
        '-TERM',
        'CoreDeviceService',
      ], runInShell: false).timeout(const Duration(seconds: 5));
    } on Object {
      return false;
    }
    if (result.exitCode != 0 && result.exitCode != 1) return false;
    await Future<void>.delayed(restartDelay);
    return true;
  }
}

/// Performs one bounded CoreDevice daemon recovery only for idempotent device
/// inventory and file-copy operations. Process launch/termination, install,
/// XCTest, and every non-CoreDevice command fail without replay.
final class RecoveringGroupMediaIosCommandRunner
    implements GroupMediaIosCommandRunner {
  RecoveringGroupMediaIosCommandRunner({
    required this.delegate,
    required this.recovery,
    this.maxRecoveries = 4,
  }) : assert(maxRecoveries >= 0);

  final GroupMediaIosCommandRunner delegate;
  final GroupMediaIosCoreDeviceRecovery recovery;
  final int maxRecoveries;

  var _recoveries = 0;

  @override
  Future<GroupMediaIosCommandResult> run(GroupMediaIosCommand command) =>
      _run(command);

  @override
  Future<GroupMediaIosCommandResult> runStreaming(
    GroupMediaIosCommand command, {
    required Future<void> Function(String line) onLine,
  }) => _run(command, onLine: onLine);

  Future<GroupMediaIosCommandResult> _run(
    GroupMediaIosCommand command, {
    Future<void> Function(String line)? onLine,
  }) async {
    final result = onLine == null
        ? await delegate.run(command)
        : await delegate.runStreaming(command, onLine: onLine);
    if (result.exitCode != 124 ||
        !_isRecoverableCoreDeviceCommand(command) ||
        _recoveries >= maxRecoveries) {
      return result;
    }
    _recoveries += 1;
    if (!await recovery.recover()) return result;
    return onLine == null
        ? delegate.run(command)
        : delegate.runStreaming(command, onLine: onLine);
  }

  bool _isRecoverableCoreDeviceCommand(GroupMediaIosCommand command) {
    final executable = command.executable.replaceAll('\\', '/').split('/').last;
    final arguments = command.arguments;
    if (executable != 'xcrun' ||
        arguments.length < 4 ||
        arguments[0] != 'devicectl' ||
        arguments[1] != 'device') {
      return false;
    }
    if (arguments[2] == 'info') return true;
    return arguments[2] == 'copy' &&
        (arguments[3] == 'to' || arguments[3] == 'from');
  }
}

final class SystemGroupMediaIosCommandRunner
    implements GroupMediaIosCommandRunner {
  const SystemGroupMediaIosCommandRunner();

  @override
  Future<GroupMediaIosCommandResult> run(GroupMediaIosCommand command) =>
      _execute(command);

  @override
  Future<GroupMediaIosCommandResult> runStreaming(
    GroupMediaIosCommand command, {
    required Future<void> Function(String line) onLine,
  }) => _execute(command, onLine: onLine);

  Future<GroupMediaIosCommandResult> _execute(
    GroupMediaIosCommand command, {
    Future<void> Function(String line)? onLine,
  }) async {
    final xcodebuildViolation = _xcodebuildNoBuildViolation(command);
    if (xcodebuildViolation != null) {
      _recordNestedBuildViolation(command, xcodebuildViolation);
      return GroupMediaIosCommandResult(
        exitCode: 91,
        stdout: '',
        stderr: xcodebuildViolation,
      );
    }
    late final Process process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        environment: <String, String>{
          ...Platform.environment,
          ...command.environment,
        },
        runInShell: false,
      );
    } on ProcessException catch (error) {
      return GroupMediaIosCommandResult(
        exitCode: 127,
        stdout: '',
        stderr: error.message,
      );
    }

    final output = StringBuffer();
    final errors = StringBuffer();
    final lines = StreamController<String>();
    var openStreams = 2;
    void closeOne() {
      openStreams -= 1;
      if (openStreams == 0) unawaited(lines.close());
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (output.length < 200000) output.writeln(line);
          lines.add(line);
        }, onDone: closeOne);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (errors.length < 200000) errors.writeln(line);
          lines.add(line);
        }, onDone: closeOne);

    final consume = () async {
      await for (final line in lines.stream) {
        if (onLine != null) await onLine(line);
      }
    }();
    try {
      final values = await Future.wait<Object?>(<Future<Object?>>[
        process.exitCode,
        consume,
      ]).timeout(command.timeout);
      return GroupMediaIosCommandResult(
        exitCode: values.first! as int,
        stdout: output.toString(),
        stderr: errors.toString(),
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      return GroupMediaIosCommandResult(
        exitCode: 124,
        stdout: output.toString(),
        stderr: 'Timed out while running ${command.label}.',
      );
    } on Object {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      rethrow;
    }
  }

  String? _xcodebuildNoBuildViolation(GroupMediaIosCommand command) {
    final normalized = command.executable.replaceAll('\\', '/');
    if (normalized.split('/').last != 'xcodebuild') return null;
    final arguments = command.arguments;
    final exactShape =
        arguments.length == 10 &&
        arguments[0] == 'test-without-building' &&
        arguments[1] == '-xctestrun' &&
        _safeAbsoluteCommandPath(arguments[2], suffix: '.xctestrun') &&
        arguments[3] == '-destination' &&
        RegExp(
          r'^platform=iOS,id=[A-Za-z0-9][A-Za-z0-9._:-]{0,159}$',
        ).hasMatch(arguments[4]) &&
        arguments[5] == '-parallel-testing-enabled' &&
        arguments[6] == 'NO' &&
        RegExp(
          r'^-only-testing:RunnerUITests/[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*$',
        ).hasMatch(arguments[7]) &&
        arguments[8] == '-resultBundlePath' &&
        _safeAbsoluteCommandPath(arguments[9], suffix: '.xcresult') &&
        command.environment['SIMS_CHILD_BUILDS_FORBIDDEN'] == '1';
    return exactShape
        ? null
        : 'Nested xcodebuild rejected: only the exact prebuilt '
              'test-without-building selector is allowed.';
  }

  bool _safeAbsoluteCommandPath(String value, {required String suffix}) =>
      value.startsWith(Platform.pathSeparator) &&
      value.endsWith(suffix) &&
      !value.contains(RegExp(r'[\r\n\x00]'));

  void _recordNestedBuildViolation(
    GroupMediaIosCommand command,
    String violation,
  ) {
    final path =
        command.environment['SIMS_BUILD_GUARD_LOG'] ??
        Platform.environment['SIMS_BUILD_GUARD_LOG'];
    if (path == null || path.trim().isEmpty) return;
    try {
      File(path).writeAsStringSync(
        'xcodebuild ${command.arguments.join(' ')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // The command still fails closed even when the outer evidence log is
      // unavailable; the controller will surface [violation] through stderr.
    }
  }
}

abstract interface class GroupMediaIosSystemLogCapture {
  Future<void> start({required String deviceId, required File output});

  Future<void> stop();
}

/// Captures the physical receiver's native log without relaying its contents
/// through stdout or the structured proof artifact.
final class PhysicalIdeviceSyslogCapture
    implements GroupMediaIosSystemLogCapture {
  PhysicalIdeviceSyslogCapture({
    this.executable = 'idevicesyslog',
    this.startupProbe = const Duration(milliseconds: 250),
  });

  final String executable;
  final Duration startupProbe;

  Process? _process;
  Future<int>? _exitCode;
  Future<void>? _stdoutDrain;
  Future<void>? _stderrDrain;
  int? _observedExitCode;
  File? _output;
  bool _stopRequested = false;

  @override
  Future<void> start({required String deviceId, required File output}) async {
    if (_process != null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The physical iOS system-log capture was started more than once.',
      );
    }
    if (!_fileEntity(output) || (output.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'The physical iOS system-log destination is not a protected file.',
      );
    }

    late final Process process;
    try {
      process = await Process.start(executable, <String>[
        '--udid',
        deviceId,
        '--no-colors',
        '--output',
        output.absolute.path,
      ], runInShell: false);
    } on ProcessException {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'environment',
        'The physical idevicesyslog capture is unavailable.',
      );
    }
    _process = process;
    _output = output;
    _stdoutDrain = process.stdout.drain<void>();
    _stderrDrain = process.stderr.drain<void>();
    _exitCode = process.exitCode.then((exitCode) {
      _observedExitCode = exitCode;
      return exitCode;
    });

    final startup = await Future.any<Object>(<Future<Object>>[
      _exitCode!.then<Object>((exitCode) => exitCode),
      Future<void>.delayed(startupProbe).then<Object>((_) => const Object()),
    ]);
    if (startup is int) {
      await Future.wait<void>(<Future<void>>[_stdoutDrain!, _stderrDrain!]);
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'environment',
        'The physical idevicesyslog capture exited before XCTest.',
      );
    }
  }

  @override
  Future<void> stop() async {
    final process = _process;
    final exit = _exitCode;
    final output = _output;
    if (process == null || exit == null || output == null || _stopRequested) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The physical iOS system-log capture did not have one live owner.',
      );
    }
    _stopRequested = true;
    final exitedBeforeStop = _observedExitCode != null;
    var stopSignalSent = false;
    if (!exitedBeforeStop) {
      stopSignalSent = process.kill(ProcessSignal.sigint);
    }
    int exitCode;
    try {
      exitCode = await exit.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      exitCode = await exit.timeout(
        const Duration(seconds: 5),
        onTimeout: () => 124,
      );
    }
    await Future.wait<void>(<Future<void>>[_stdoutDrain!, _stderrDrain!]);
    const expectedStops = <int>{0, -2, -15, 130, 143};
    if (exitedBeforeStop ||
        !stopSignalSent ||
        !expectedStops.contains(exitCode) ||
        !_regularFile(output) ||
        (output.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The physical idevicesyslog capture did not close cleanly.',
      );
    }
  }
}

final class GroupMediaIosBackgroundRecoveryBlocked implements Exception {
  const GroupMediaIosBackgroundRecoveryBlocked(this.blocker, this.detail);

  final String blocker;
  final String detail;

  @override
  String toString() => detail;
}

final class GroupMediaIosBackgroundRecoveryFailure implements Exception {
  const GroupMediaIosBackgroundRecoveryFailure(this.detail);

  final String detail;

  @override
  String toString() => detail;
}

abstract interface class GroupMediaIosAndroidDisposableBoundary {
  Future<GroupMediaAndroidDisposableResetReceipt> prepare(String action);

  Future<GroupMediaAndroidDisposableResetReceipt?> cleanup(String action);

  GroupMediaAndroidCommandAuditSnapshot commandAudit(String action);
}

final class _SystemGroupMediaIosAndroidDisposableBoundary
    implements GroupMediaIosAndroidDisposableBoundary {
  _SystemGroupMediaIosAndroidDisposableBoundary({
    required this.options,
    required this.runDirectory,
    required GroupMediaIosCommandRunner commandRunner,
  }) : _baseRunner = _GroupMediaIosAndroidProcessRunner(commandRunner);

  final GroupMediaIosBackgroundRecoveryOptions options;
  final Directory runDirectory;
  final AndroidHostProcessRunner _baseRunner;
  final Map<String, GroupMediaAndroidDisposableApp> _apps =
      <String, GroupMediaAndroidDisposableApp>{};
  final Map<String, GroupMediaAndroidCommandAudit> _commandAudits =
      <String, GroupMediaAndroidCommandAudit>{};
  final Set<String> _completed = <String>{};
  final Set<String> _touched = <String>{};

  @override
  Future<GroupMediaAndroidDisposableResetReceipt> prepare(String action) async {
    if (_apps.containsKey(action)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The Android sender boundary was prepared more than once.',
      );
    }
    final scopedRunId =
        'p269-${_sha256('${options.runId}:$action').substring(0, 32)}';
    final commandAudit = GroupMediaAndroidCommandAudit();
    _commandAudits[action] = commandAudit;
    late final GroupMediaAndroidDisposableApp app;
    app = GroupMediaAndroidDisposableApp(
      deviceId: options.senderDeviceId,
      artifact: options.androidCompanionArtifact,
      expectedArtifactSha256: options.androidCompanionArtifactSha256,
      runId: scopedRunId,
      workDirectory: runDirectory,
      runner: GroupMediaAndroidCommandAuditingRunner(
        delegate: _baseRunner,
        audit: commandAudit,
      ),
      onMutationStarted: () => _touched.add(action),
    );
    _apps[action] = app;
    await app.installPreparedArtifact();
    return app.reset('pre');
  }

  @override
  Future<GroupMediaAndroidDisposableResetReceipt?> cleanup(
    String action,
  ) async {
    final app = _apps.remove(action);
    if (app == null || !_touched.remove(action)) return null;
    final receipt = await app.reset('post');
    _completed.add(action);
    return receipt;
  }

  @override
  GroupMediaAndroidCommandAuditSnapshot commandAudit(String action) {
    final snapshot = _commandAudits[action]?.snapshot;
    if (!_completed.contains(action) ||
        snapshot == null ||
        snapshot.adbCommandCount == 0 ||
        !snapshot.isSafe) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The default Android sender boundary lacks a safe command audit.',
      );
    }
    return snapshot;
  }
}

final class _GroupMediaIosAndroidProcessRunner
    implements AndroidHostProcessRunner {
  _GroupMediaIosAndroidProcessRunner(this._delegate);

  final GroupMediaIosCommandRunner _delegate;
  var _sequence = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final result = await _delegate.run(
      GroupMediaIosCommand(
        label: 'android-disposable-${_sequence++}',
        executable: executable,
        arguments: arguments,
        timeout: const Duration(minutes: 2),
      ),
    );
    return ProcessResult(0, result.exitCode, result.stdout, result.stderr);
  }
}

/// Run-scoped custody for the only fixture executable trusted to publish the
/// physical-iOS proof's relay, SQLCipher, and Android-command observations.
///
/// The production capture always resolves [candidate] against the repo-owned
/// driver. [trustedDriver] exists solely so focused custody tests can mutate an
/// isolated file instead of the checked-in executable.
final class GroupMediaIosFixtureDriverCustody {
  const GroupMediaIosFixtureDriverCustody._({
    required this.canonicalDriver,
    required this.sha256Digest,
  });

  final File canonicalDriver;
  final String sha256Digest;

  static GroupMediaIosFixtureDriverCustody capture({
    required File candidate,
    File? trustedDriver,
  }) {
    final trusted =
        trustedDriver ??
        File(groupMediaIosFixtureDriverRepositoryPath).absolute;
    try {
      if (FileSystemEntity.typeSync(trusted.path, followLinks: false) !=
              FileSystemEntityType.file ||
          FileSystemEntity.typeSync(candidate.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw const GroupMediaIosBackgroundRecoveryBlocked(
          'missingDriver',
          'The iOS fixture driver must be the non-symlink repo-owned executable.',
        );
      }
      final canonicalTrusted = File(trusted.resolveSymbolicLinksSync());
      final canonicalCandidate = File(candidate.resolveSymbolicLinksSync());
      if (canonicalCandidate.path != canonicalTrusted.path ||
          (canonicalTrusted.statSync().mode & 0x49) == 0) {
        throw const GroupMediaIosBackgroundRecoveryBlocked(
          'missingDriver',
          'The iOS fixture driver must be the non-symlink repo-owned executable.',
        );
      }
      final digest = sha256
          .convert(canonicalTrusted.readAsBytesSync())
          .toString();
      if (!_digestPattern.hasMatch(digest)) {
        throw const GroupMediaIosBackgroundRecoveryBlocked(
          'missingDriver',
          'The repo-owned iOS fixture driver could not be attested.',
        );
      }
      return GroupMediaIosFixtureDriverCustody._(
        canonicalDriver: canonicalTrusted,
        sha256Digest: digest,
      );
    } on GroupMediaIosBackgroundRecoveryBlocked {
      rethrow;
    } on FileSystemException {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingDriver',
        'The repo-owned iOS fixture driver could not be resolved and attested.',
      );
    }
  }

  void verifyUnchanged() {
    try {
      if (FileSystemEntity.typeSync(canonicalDriver.path, followLinks: false) !=
              FileSystemEntityType.file ||
          canonicalDriver.resolveSymbolicLinksSync() != canonicalDriver.path ||
          (canonicalDriver.statSync().mode & 0x49) == 0 ||
          sha256.convert(canonicalDriver.readAsBytesSync()).toString() !=
              sha256Digest) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The repo-owned iOS fixture driver changed after preflight custody.',
        );
      }
    } on GroupMediaIosBackgroundRecoveryFailure {
      rethrow;
    } on FileSystemException {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The repo-owned iOS fixture driver changed after preflight custody.',
      );
    }
  }
}

/// Runs the physical-iOS portion of Plan 269 without compiling a child app or
/// test bundle.
///
/// The private fixture driver owns real relay/SQLCipher inspection and emits
/// exact, run-bound receipts. XCTest owns both Home actions and the route-free
/// relaunch. This host controller reacts to those XCTest markers, waits for the
/// durable post-claim barrier, and kills the exact receipt-bound process ID.
/// The driver has three bounded actions: `phase-a-background-success`,
/// `phase-b-stop-at-post-claim`, and `phase-b-observe-recovery`. Each must write
/// its receipt plus the requested physical-idevicesyslog and reopened-SQLCipher
/// observation files; exit 78 means the external boundary is unavailable.
final class GroupMediaIosBackgroundRecoveryController {
  GroupMediaIosBackgroundRecoveryController({
    required this.options,
    GroupMediaIosCommandRunner commandRunner =
        const SystemGroupMediaIosCommandRunner(),
    GroupMediaIosCoreDeviceRecovery coreDeviceRecovery =
        const SystemGroupMediaIosCoreDeviceRecovery(),
    GroupMediaIosSystemLogCapture? systemLogCapture,
    GroupMediaIosAndroidDisposableBoundary? androidDisposableBoundary,
  }) : commandRunner = RecoveringGroupMediaIosCommandRunner(
         delegate: commandRunner,
         recovery: coreDeviceRecovery,
       ),
       systemLogCapture = systemLogCapture ?? PhysicalIdeviceSyslogCapture(),
       _androidDisposableBoundary = androidDisposableBoundary;

  final GroupMediaIosBackgroundRecoveryOptions options;
  final GroupMediaIosCommandRunner commandRunner;
  final GroupMediaIosSystemLogCapture systemLogCapture;
  GroupMediaIosAndroidDisposableBoundary? _androidDisposableBoundary;

  late final Directory _runDirectory;
  late final _PreparedIosBundle _bundle;
  late final GroupMediaIosFixtureDriverCustody _fixtureDriverCustody;
  late final String _senderDigest;
  late final String _receiverDigest;
  late final String _phaseAMessage;
  late final String _phaseBMessage;
  late final String _phaseAReady;
  late final String _phaseBReady;
  late final String _phaseAMessageDigest;
  late final String _phaseBMessageDigest;
  late final File _systemLog;
  String? _installedApplicationExecutablePath;
  var _deviceMutationStarted = false;
  var _systemLogStarted = false;
  _FixtureReceipt? _phaseAReceipt;
  _FixtureReceipt? _phaseBClaimReceipt;
  _FixtureReceipt? _phaseBRecoveryReceipt;
  _DisposableResetReceipt? _preResetReceipt;
  _DisposableResetReceipt? _postResetReceipt;
  final Map<String, GroupMediaAndroidDisposableResetReceipt>
  _androidPreResetReceipts =
      <String, GroupMediaAndroidDisposableResetReceipt>{};
  final Map<String, GroupMediaAndroidDisposableResetReceipt>
  _androidPostResetReceipts =
      <String, GroupMediaAndroidDisposableResetReceipt>{};
  final Map<String, GroupMediaAndroidCommandAuditSnapshot>
  _androidBoundaryCommandAudits =
      <String, GroupMediaAndroidCommandAuditSnapshot>{};
  final Map<String, GroupMediaAndroidCommandAuditSnapshot>
  _androidFixtureCommandAudits =
      <String, GroupMediaAndroidCommandAuditSnapshot>{};

  GroupMediaIosAndroidDisposableBoundary get _androidBoundary =>
      _androidDisposableBoundary ??=
          _SystemGroupMediaIosAndroidDisposableBoundary(
            options: options,
            runDirectory: _runDirectory,
            commandRunner: commandRunner,
          );

  Future<Map<String, Object?>> run() async {
    _preflightLocalInputs();
    await _protectRunDirectory();
    _requireEmptyBuildGuard();
    await _verifyLiveTargets();
    await _verifyPreparedApplication();
    final patchedXctestrun = await _materializePatchedXctestrun();

    Map<String, Object?>? acceptedArtifact;
    Object? primaryError;
    StackTrace? primaryStack;
    try {
      await _installPreparedApplication();
      await _requireApplicationInstalled('after-install');
      _preResetReceipt = await _runDisposableReset('pre');
      await _stageAutoSetup();
      await _startSystemLogCapture();
      await _launchRoot('launch-root-before-proof');
      acceptedArtifact = await _executeProof(patchedXctestrun);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStack = stackTrace;
    }

    final cleanupFailure = _deviceMutationStarted
        ? await _cleanupPreparedApplication()
        : null;
    if (cleanupFailure != null) {
      throw GroupMediaIosBackgroundRecoveryFailure(
        primaryError == null
            ? 'The iOS proof completed but mandatory dedicated-namespace '
                  'reset failed.'
            : 'The iOS proof failed and mandatory dedicated-namespace reset '
                  'also failed.',
      );
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStack!);
    }
    if (acceptedArtifact == null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The iOS proof produced no validated artifact.',
      );
    }
    if (_postResetReceipt == null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The iOS proof produced no validated post-reset receipt.',
      );
    }
    final androidCleanup = _androidCleanupArtifact();
    final androidUninstallCommands = _androidResetActions.fold<int>(
      0,
      (total, action) =>
          total + _combinedAndroidCommandAudit(action).uninstallCommands,
    );
    acceptedArtifact['cleanup'] = <String, Object?>{
      'pre_reset': _preResetReceipt!.artifactFacts,
      'post_reset': _postResetReceipt!.artifactFacts,
      'android_senders': androidCleanup,
      'uninstall_commands': androidUninstallCommands,
      'app_left_installed': true,
    };
    final validation = validateGroupMediaIosBackgroundRecoveryArtifact(
      acceptedArtifact,
    );
    if (!validation.ok) {
      throw GroupMediaIosBackgroundRecoveryFailure(
        'The iOS proof artifact failed validation: ${validation.detail}',
      );
    }
    _requirePreparedArtifactCustody('artifact-publication');
    return acceptedArtifact;
  }

  void _requirePreparedArtifactCustody(String checkpoint) {
    late final String currentDigest;
    try {
      currentDigest = groupMediaPreparedDirectorySha256(_bundle.root);
    } on FileSystemException {
      throw GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared iOS bundle failed custody re-attestation at '
            '$checkpoint.',
      );
    }
    if (currentDigest != _bundle.contractDigest) {
      throw GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared iOS bundle changed after initial attestation at '
            '$checkpoint.',
      );
    }
  }

  Map<String, Object?> _androidCleanupArtifact() {
    if (_androidPreResetReceipts.keys.toSet().length !=
            _androidResetActions.length ||
        !_androidPreResetReceipts.keys.toSet().containsAll(
          _androidResetActions,
        ) ||
        _androidPostResetReceipts.keys.toSet().length !=
            _androidResetActions.length ||
        !_androidPostResetReceipts.keys.toSet().containsAll(
          _androidResetActions,
        ) ||
        _androidBoundaryCommandAudits.keys.toSet().length !=
            _androidResetActions.length ||
        !_androidBoundaryCommandAudits.keys.toSet().containsAll(
          _androidResetActions,
        ) ||
        _androidFixtureCommandAudits.keys.toSet().length !=
            _androidResetActions.length ||
        !_androidFixtureCommandAudits.keys.toSet().containsAll(
          _androidResetActions,
        )) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The dedicated Android sender cleanup evidence is incomplete.',
      );
    }
    return <String, Object?>{
      for (final action in _androidResetActions)
        action: <String, Object?>{
          'pre_reset': _androidResetFacts(_androidPreResetReceipts[action]!),
          'post_reset': _androidResetFacts(_androidPostResetReceipts[action]!),
          'uninstall_commands': _combinedAndroidCommandAudit(
            action,
          ).uninstallCommands,
          'pm_clear_commands': _combinedAndroidCommandAudit(
            action,
          ).pmClearCommands,
          'broad_delete_commands': _combinedAndroidCommandAudit(
            action,
          ).broadDeleteCommands,
          'app_left_installed': true,
        },
    };
  }

  GroupMediaAndroidCommandAuditSnapshot _combinedAndroidCommandAudit(
    String action,
  ) {
    final boundary = _androidBoundaryCommandAudits[action];
    final fixture = _androidFixtureCommandAudits[action];
    if (boundary == null ||
        fixture == null ||
        boundary.adbCommandCount == 0 ||
        fixture.adbCommandCount == 0 ||
        boundary.adbCommandCount + fixture.adbCommandCount >
            groupMediaAndroidMaximumAuditedCommands ||
        !boundary.isSafe ||
        !fixture.isSafe) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The Android sender command audit is missing, empty, or unsafe.',
      );
    }
    return GroupMediaAndroidCommandAuditSnapshot(
      adbCommandCount: boundary.adbCommandCount + fixture.adbCommandCount,
      journalSha256: _sha256(
        '${boundary.journalSha256}:${fixture.journalSha256}',
      ),
      productionPackageCommands:
          boundary.productionPackageCommands +
          fixture.productionPackageCommands,
      uninstallCommands: boundary.uninstallCommands + fixture.uninstallCommands,
      pmClearCommands: boundary.pmClearCommands + fixture.pmClearCommands,
      broadDeleteCommands:
          boundary.broadDeleteCommands + fixture.broadDeleteCommands,
    );
  }

  Map<String, Object?> _androidResetFacts(
    GroupMediaAndroidDisposableResetReceipt receipt,
  ) => <String, Object?>{
    'phase': receipt.phase,
    'receipt_sha256': receipt.sha256Digest,
    'keychain_empty': true,
    'database_absent': true,
    'allowlisted_files_absent': true,
  };

  GroupMediaAndroidCommandAuditSnapshot _readAndroidFixtureCommandAudit(
    File file, {
    required String action,
  }) {
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file ||
        file.lengthSync() == 0 ||
        (file.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The Android fixture command audit is absent or unprotected.',
      );
    }
    final value = _readObject(file, 'Android fixture command audit');
    const keys = <String>{
      'schema',
      'run_id',
      'action',
      'adb_command_count',
      'journal_sha256',
      'production_package_commands',
      'uninstall_commands',
      'pm_clear_commands',
      'broad_delete_commands',
      'contains_secrets',
    };
    int counter(String key) {
      final count = value[key];
      if (count is! int || count < 0) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The Android fixture command audit contains an invalid counter.',
        );
      }
      return count;
    }

    if (!_sameSet(value.keys.toSet(), keys) ||
        value['schema'] != groupMediaAndroidCommandAuditSchema ||
        value['run_id'] != options.runId ||
        value['action'] != action ||
        value['contains_secrets'] != false) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The Android fixture command audit is not run/action bound.',
      );
    }
    final snapshot = GroupMediaAndroidCommandAuditSnapshot(
      adbCommandCount: counter('adb_command_count'),
      journalSha256: '${value['journal_sha256']}',
      productionPackageCommands: counter('production_package_commands'),
      uninstallCommands: counter('uninstall_commands'),
      pmClearCommands: counter('pm_clear_commands'),
      broadDeleteCommands: counter('broad_delete_commands'),
    );
    final ownsAndroidSender = _androidResetActions.contains(action);
    if (!snapshot.isSafe ||
        (ownsAndroidSender && snapshot.adbCommandCount == 0) ||
        (!ownsAndroidSender && snapshot.adbCommandCount != 0)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The Android fixture command audit is empty, unsafe, or out of scope.',
      );
    }
    return snapshot;
  }

  Future<Map<String, Object?>> _executeProof(File patchedXctestrun) async {
    final observedMarkers = <String>[];
    final resultBundle = Directory('${_runDirectory.path}/p269-ios.xcresult');
    final fixtureCancel = File('${_runDirectory.path}/fixture-cancel.json');
    final phaseAReady = File('${_runDirectory.path}/phase-a-ready.json');
    _PendingFixture? phaseAPending;
    _PendingFixture? phaseBPending;
    late final GroupMediaIosCommandResult xctest;
    try {
      xctest = await commandRunner.runStreaming(
        GroupMediaIosCommand(
          label: 'xctest-without-building',
          executable: 'xcodebuild',
          arguments: iosTestWithoutBuildingArguments(
            xctestrun: patchedXctestrun,
            receiverDeviceId: options.receiverDeviceId,
            selector: groupMediaIosBackgroundRecoveryXctestSelector,
            resultBundle: resultBundle,
          ),
          environment: const <String, String>{
            'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
          },
          timeout: const Duration(minutes: 8),
        ),
        onLine: (line) async {
          final marker = _uiMarker(line);
          if (marker == null) return;
          final expectedIndex = observedMarkers.length;
          if (expectedIndex >= _requiredUiMarkers.length ||
              marker != _requiredUiMarkers[expectedIndex]) {
            throw GroupMediaIosBackgroundRecoveryFailure(
              'The iOS UI controller emitted an out-of-order or duplicate '
              'boundary marker.',
            );
          }
          observedMarkers.add(marker);
          if (marker == 'local_network_permission_ready') {
            if (phaseAPending != null) {
              throw const GroupMediaIosBackgroundRecoveryFailure(
                'The phase-A fixture was started more than once.',
              );
            }
            phaseAPending = _PendingFixture(
              _runFixture(
                label: 'fixture-phase-a',
                action: 'phase-a-background-success',
                outputName: 'phase-a-receipt.json',
                expectedPhase: 'a',
                expectedEffectDigest: _phaseAMessageDigest,
                ready: phaseAReady,
                cancel: fixtureCancel,
              ),
            );
            await _waitForFixtureReady(
              pending: phaseAPending!,
              ready: phaseAReady,
              action: 'phase-a-background-success',
              mediaPhase: 'a',
              expectedLabel: _phaseAReady,
            );
          } else if (marker == 'phase_a_home') {
            final pending = phaseAPending;
            if (pending == null) {
              throw const GroupMediaIosBackgroundRecoveryFailure(
                'Phase A reached Home before permission-owned fixture start.',
              );
            }
            _phaseAReceipt = await pending.future;
            _validatePhaseAReceipt(_phaseAReceipt!);
            await _launchRoot(
              'launch-root-after-phase-a',
              terminateExisting: false,
            );
          } else if (marker == 'phase_a_effect_once') {
            final phaseBReady = File(
              '${_runDirectory.path}/phase-b-ready.json',
            );
            phaseBPending = _PendingFixture(
              _runFixture(
                label: 'fixture-phase-b-claim',
                action: 'phase-b-stop-at-post-claim',
                outputName: 'phase-b-claim-receipt.json',
                expectedPhase: 'b_claim',
                expectedEffectDigest: _phaseBMessageDigest,
                ready: phaseBReady,
                cancel: fixtureCancel,
              ),
            );
            await _waitForFixtureReady(
              pending: phaseBPending!,
              ready: phaseBReady,
              action: 'phase-b-stop-at-post-claim',
              mediaPhase: 'b',
              expectedLabel: _phaseBReady,
            );
          } else if (marker == 'phase_b_home') {
            final pending = phaseBPending;
            if (pending == null) {
              throw const GroupMediaIosBackgroundRecoveryFailure(
                'Phase B reached Home before its foreground arm.',
              );
            }
            _phaseBClaimReceipt = await pending.future;
            _validatePhaseBClaimReceipt(_phaseBClaimReceipt!);
            await _terminatePhaseB(_phaseBClaimReceipt!.receiverPid);
          } else if (marker == 'phase_b_relaunch_root_without_group') {
            final claim = _phaseBClaimReceipt;
            if (claim == null) {
              throw const GroupMediaIosBackgroundRecoveryFailure(
                'Phase B relaunched without an interrupted claim.',
              );
            }
            _phaseBRecoveryReceipt = await _runFixture(
              label: 'fixture-phase-b-observe',
              action: 'phase-b-observe-recovery',
              outputName: 'phase-b-recovery-receipt.json',
              expectedPhase: 'b_recovery',
              expectedEffectDigest: _phaseBMessageDigest,
              interruptedPid: claim.receiverPid,
            );
            _validatePhaseBRecoveryReceipt(
              _phaseBRecoveryReceipt!,
              interruptedPid: claim.receiverPid,
            );
          }
        },
      );
    } on Object {
      await _cancelAndSettleFixtures(
        cancel: fixtureCancel,
        pendings: <_PendingFixture>[
          if (phaseAPending != null) phaseAPending!,
          if (phaseBPending != null) phaseBPending!,
        ],
      );
      rethrow;
    }
    if (xctest.exitCode != 0) {
      await _cancelAndSettleFixtures(
        cancel: fixtureCancel,
        pendings: <_PendingFixture>[
          if (phaseAPending != null) phaseAPending!,
          if (phaseBPending != null) phaseBPending!,
        ],
      );
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The exact physical-iOS XCTest selector failed.',
      );
    }
    if (!_sameStrings(observedMarkers, _requiredUiMarkers) ||
        _phaseAReceipt == null ||
        _phaseBClaimReceipt == null ||
        _phaseBRecoveryReceipt == null) {
      await _cancelAndSettleFixtures(
        cancel: fixtureCancel,
        pendings: <_PendingFixture>[
          if (phaseAPending != null) phaseAPending!,
          if (phaseBPending != null) phaseBPending!,
        ],
      );
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The XCTest run omitted a required Home, relaunch, or UI-effect marker.',
      );
    }

    final phaseBRecovery = _phaseBRecoveryReceipt!;
    _requireEmptyBuildGuard();
    final databasePathDigest = _databasePathDigest(_phaseAReceipt!);
    if (_databasePathDigest(_phaseBClaimReceipt!) != databasePathDigest ||
        _databasePathDigest(phaseBRecovery) != databasePathDigest) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The three SQLCipher observations did not reopen the same database.',
      );
    }

    final artifact = <String, Object?>{
      'schema': groupMediaIosBackgroundRecoveryArtifactSchema,
      'run_id': options.runId,
      'scenario': groupMediaIosReceiverBackgroundRecoveryScenario,
      'prepared_artifact': <String, Object?>{
        'profile': groupMediaReliabilityIosBuildProfile,
        'bundle_sha256': _bundle.contractDigest,
        'android_profile': groupMediaReliabilityAndroidBuildProfile,
        'android_sha256': options.androidCompanionArtifactSha256,
        'android_package': groupMediaReliabilityAndroidPackageName,
        'child_builds': 0,
      },
      'device_roles': <String, Object?>{
        'sender': <String, Object?>{
          'platform': 'android',
          'kind': 'physical',
          'device_sha256': _senderDigest,
        },
        'receiver': <String, Object?>{
          'platform': 'ios',
          'kind': 'physical',
          'device_sha256': _receiverDigest,
        },
      },
      'xctest': <String, Object?>{
        'selector': groupMediaIosBackgroundRecoveryXctestSelector,
        'invocations': 1,
        'home_presses': 2,
        'manual_steps': 0,
        'sleep_only_waits': 0,
        'local_network_permission': 'automated_or_pregranted',
        'result': 'passed',
      },
      'phase_a': <String, Object?>{
        'critical_task_granted': true,
        'terminal_path': _phaseAReceipt!.terminalPath,
        'native_end_count': _phaseAReceipt!.nativeEndCount,
        'durable_status': _phaseAReceipt!.durableStatus,
        'download_attempts': _phaseAReceipt!.downloadAttempts,
        'ui_effects': 1,
      },
      'phase_b': <String, Object?>{
        'critical_task_granted': true,
        'barrier': _phaseBClaimReceipt!.barrier,
        'pre_interrupt_status': _phaseBClaimReceipt!.durableStatus,
        'host_terminations': 1,
        'terminal_path': phaseBRecovery.terminalPath,
        'native_end_count': phaseBRecovery.nativeEndCount,
        'relaunch_route': 'root_without_group',
        'resume_after_drain_attempts': phaseBRecovery.resumeAttempts,
        'durable_status': phaseBRecovery.durableStatus,
        'download_attempts': phaseBRecovery.downloadAttempts,
        'ui_effects': 1,
        'fresh_pid':
            phaseBRecovery.relaunchPid != _phaseBClaimReceipt!.receiverPid,
      },
      'boundary_observations': <String, Object?>{
        'database_path_sha256': databasePathDigest,
        'phase_a': _phaseAReceipt!.observationPair,
        'phase_b_claim': _phaseBClaimReceipt!.observationPair,
        'phase_b_recovery': phaseBRecovery.observationPair,
      },
      'flow_events': List<String>.from(
        groupMediaIosBackgroundRecoveryFlowEvents,
      ),
    };
    return artifact;
  }

  void _preflightLocalInputs() {
    if (!_safeRunId.hasMatch(options.runId)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'The iOS proof requires a safe run identifier.',
      );
    }
    if (!_safeAndroidTarget.hasMatch(options.senderDeviceId) ||
        options.senderDeviceId.startsWith('emulator-') ||
        !_physicalIosTarget.hasMatch(options.receiverDeviceId) ||
        options.senderDeviceId == options.receiverDeviceId) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'targetUnavailable',
        'The iOS proof requires an explicit physical Android sender and '
            'distinct physical iPhone receiver.',
      );
    }
    final relay = options.inheritedEnvironment['MKNOON_RELAY_ADDRESSES']
        ?.trim();
    if (relay == null || relay.isEmpty || relay.contains(RegExp(r'[\r\n]'))) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'environment',
        'The real-relay iOS proof requires MKNOON_RELAY_ADDRESSES.',
      );
    }
    final dedicatedDevice = options
        .inheritedEnvironment[groupMediaIosDedicatedDisposableDeviceEnvironment]
        ?.trim();
    if (dedicatedDevice != options.receiverDeviceId) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The iOS proof requires an explicit target-bound receiver before the '
            'dedicated test app can be installed or reset.',
      );
    }
    if (!_regularFile(options.androidCompanionArtifact) ||
        !_digestPattern.hasMatch(options.androidCompanionArtifactSha256) ||
        sha256
                .convert(options.androidCompanionArtifact.readAsBytesSync())
                .toString() !=
            options.androidCompanionArtifactSha256) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The dedicated Android companion APK failed runner custody.',
      );
    }
    _bundle = _PreparedIosBundle.resolve(options.preparedBundle);
    _fixtureDriverCustody = GroupMediaIosFixtureDriverCustody.capture(
      candidate: options.fixtureDriver,
    );
    _runDirectory = Directory(
      '${options.proofDirectory.absolute.path}${Platform.pathSeparator}'
      'ios-${options.runId}',
    );
    if (_runDirectory.existsSync()) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'The run-scoped iOS proof directory already exists.',
      );
    }
    _runDirectory.createSync(recursive: true);
    _systemLog = File(
      '${_runDirectory.path}${Platform.pathSeparator}'
      'physical-idevicesyslog.log',
    );
    _senderDigest = _sha256(
      '${options.runId}:sender:${options.senderDeviceId}',
    );
    _receiverDigest = _sha256(
      '${options.runId}:receiver:${options.receiverDeviceId}',
    );
    _phaseAMessage = 'P269-A-${options.runId}';
    _phaseBMessage = 'P269-B-${options.runId}';
    _phaseAReady = 'P269-READY-A-${options.runId}';
    _phaseBReady = 'P269-READY-B-${options.runId}';
    _phaseAMessageDigest = _sha256(_phaseAMessage);
    _phaseBMessageDigest = _sha256(_phaseBMessage);
  }

  Future<void> _protectRunDirectory() async {
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'protect-run-directory',
        executable: 'chmod',
        arguments: <String>['700', _runDirectory.path],
        timeout: const Duration(seconds: 10),
      ),
      blocker: 'harness',
    );
    if ((_runDirectory.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'The iOS proof directory could not be protected.',
      );
    }
  }

  Future<void> _verifyLiveTargets() async {
    final android = await _requiredCommand(
      const GroupMediaIosCommand(
        label: 'adb-live-targets',
        executable: 'adb',
        arguments: <String>['devices', '-l'],
        timeout: Duration(seconds: 20),
      ),
      blocker: 'targetUnavailable',
    );
    final senderLines = const LineSplitter()
        .convert(android.stdout)
        .where(
          (line) => RegExp(
            '^${RegExp.escape(options.senderDeviceId)}\\s+device(?:\\s|\$)',
          ).hasMatch(line),
        )
        .toList(growable: false);
    if (senderLines.length != 1 ||
        !RegExp(r'(?:^|\s)usb:[^\s]+(?:\s|$)').hasMatch(senderLines.single)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'targetUnavailable',
        'The explicit Android sender is not one USB-connected physical target.',
      );
    }
    final qemu = await _requiredCommand(
      GroupMediaIosCommand(
        label: 'adb-sender-hardware',
        executable: 'adb',
        arguments: <String>[
          '-s',
          options.senderDeviceId,
          'shell',
          'getprop',
          'ro.kernel.qemu',
        ],
        timeout: const Duration(seconds: 20),
      ),
      blocker: 'targetUnavailable',
    );
    if (!const <String>{'', '0'}.contains(qemu.stdout.trim())) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'targetUnavailable',
        'The explicit Android sender reports an emulator kernel.',
      );
    }

    final ios = await _requiredCommand(
      const GroupMediaIosCommand(
        label: 'ios-live-targets',
        executable: 'flutter',
        arguments: <String>['devices', '--machine'],
        timeout: Duration(seconds: 45),
      ),
      blocker: 'targetUnavailable',
    );
    final matrix = _decodeList(ios.stdout, 'Flutter live-device matrix');
    final matches = matrix.whereType<Map>().where(
      (device) =>
          device['id'] == options.receiverDeviceId &&
          device['isSupported'] == true &&
          device['targetPlatform'] == 'ios' &&
          device['emulator'] == false,
    );
    if (matches.length != 1) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'targetUnavailable',
        'The explicit iOS receiver is not one connected physical iPhone.',
      );
    }

    final detailsFile = File('${_runDirectory.path}/coredevice-details.json');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'ios-coredevice-details',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'info',
          'details',
          '--device',
          options.receiverDeviceId,
          '--json-output',
          detailsFile.path,
          '--quiet',
        ],
        timeout: const Duration(seconds: 30),
      ),
      blocker: 'targetUnavailable',
    );
    final details = _readObject(detailsFile, 'CoreDevice target details');
    final info = details['info'];
    final result = details['result'];
    final infoMap = info is Map ? info : const <Object?, Object?>{};
    final resultMap = result is Map ? result : const <Object?, Object?>{};
    final hardware = resultMap['hardwareProperties'];
    final device = resultMap['deviceProperties'];
    final connection = resultMap['connectionProperties'];
    final hardwareMap = hardware is Map ? hardware : const <Object?, Object?>{};
    final deviceMap = device is Map ? device : const <Object?, Object?>{};
    final connectionMap = connection is Map
        ? connection
        : const <Object?, Object?>{};
    final coreDeviceReady =
        infoMap['outcome'] == 'success' &&
        hardwareMap['udid'] == options.receiverDeviceId &&
        hardwareMap['platform'] == 'iOS' &&
        groupMediaIosReceiverProductTypeAllowed(
          '${hardwareMap['productType']}',
        ) &&
        deviceMap['bootState'] == 'booted' &&
        deviceMap['ddiServicesAvailable'] == true &&
        connectionMap['pairingState'] == 'paired' &&
        connectionMap['transportType'] == 'wired' &&
        connectionMap['tunnelState'] == 'connected';
    if (!coreDeviceReady) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'targetUnavailable',
        'CoreDevice cannot run the prepared XCTest bundle on the explicit '
            'USB iPhone.',
      );
    }
  }

  Future<void> _verifyPreparedApplication() async {
    await _verifyPreparedCodeSignature(
      label: 'runner',
      bundle: _bundle.application,
      deep: true,
    );
    await _verifyPreparedBundleIdentity(
      label: 'runner',
      bundle: _bundle.application,
      expectedBundleId: _bundleId,
    );
    final shareExtension = Directory(
      '${_bundle.application.path}/PlugIns/Share Extension.appex',
    );
    await _verifyPreparedCodeSignature(
      label: 'share-extension',
      bundle: shareExtension,
    );
    await _verifyPreparedBundleIdentity(
      label: 'share-extension',
      bundle: shareExtension,
      expectedBundleId: '$_bundleId.ShareExtension',
    );
    final notificationService = Directory(
      '${_bundle.application.path}/PlugIns/NotificationService.appex',
    );
    await _verifyPreparedCodeSignature(
      label: 'notification-service',
      bundle: notificationService,
    );
    await _verifyPreparedBundleIdentity(
      label: 'notification-service',
      bundle: notificationService,
      expectedBundleId: '$_bundleId.NotificationService',
    );
    await _verifyPreparedCodeSignature(
      label: 'ui-test-host',
      bundle: _bundle.uiTestHost,
    );
    await _verifyPreparedBundleIdentity(
      label: 'ui-test-host',
      bundle: _bundle.uiTestHost,
      expectedBundleId: '$_bundleId.RunnerUITests.xctrunner',
    );
    await _verifyPreparedCodeSignature(
      label: 'ui-test-bundle',
      bundle: _bundle.uiTestBundle,
    );
    await _verifyPreparedBundleIdentity(
      label: 'ui-test-bundle',
      bundle: _bundle.uiTestBundle,
      expectedBundleId: '$_bundleId.RunnerUITests',
      allowAbsentSignedEntitlements: true,
    );
  }

  Future<void> _verifyPreparedCodeSignature({
    required String label,
    required Directory bundle,
    bool deep = false,
  }) async {
    await _requiredCommand(
      GroupMediaIosCommand(
        label: label == 'runner' ? 'codesign' : 'codesign-verify-$label',
        executable: 'codesign',
        arguments: <String>[
          '--verify',
          if (deep) '--deep',
          '--strict',
          bundle.path,
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'missingArtifact',
    );
  }

  Future<void> _verifyPreparedBundleIdentity({
    required String label,
    required Directory bundle,
    required String expectedBundleId,
    bool allowAbsentSignedEntitlements = false,
  }) async {
    final bundleIdCommandLabel = label == 'runner'
        ? 'bundle-id'
        : 'bundle-id-$label';
    final entitlementCommandLabel = label == 'runner'
        ? 'codesign-entitlements'
        : 'codesign-entitlements-$label';
    final bundleId = await _requiredCommand(
      GroupMediaIosCommand(
        label: bundleIdCommandLabel,
        executable: 'plutil',
        arguments: <String>[
          '-extract',
          'CFBundleIdentifier',
          'raw',
          '${bundle.path}/Info.plist',
        ],
        timeout: const Duration(seconds: 15),
      ),
      blocker: 'missingArtifact',
    );
    if (bundleId.stdout.trim() != expectedBundleId) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'A prepared physical iOS target does not use its dedicated Plan 269 '
            'bundle identifier.',
      );
    }
    final entitlementPlist = File(
      '${_runDirectory.path}/codesign-entitlements-$label.plist',
    );
    final signature = await _requiredCommand(
      GroupMediaIosCommand(
        label: entitlementCommandLabel,
        executable: 'codesign',
        arguments: <String>[
          '--display',
          '--verbose=4',
          '--entitlements',
          entitlementPlist.path,
          '--xml',
          bundle.path,
        ],
        timeout: const Duration(seconds: 30),
      ),
      blocker: 'missingArtifact',
    );
    if (_exactCodesignField(signature, 'Identifier') != expectedBundleId ||
        _exactCodesignField(signature, 'TeamIdentifier') !=
            _developmentTeamId) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'A prepared Plan 269 code object is not signed for its exact '
            'dedicated bundle and development team.',
      );
    }
    if (!_regularFile(entitlementPlist)) {
      // A physical-device UI-test bundle is nested test code, not a
      // provisioned application. With the dedicated P269 entitlement file
      // intentionally empty, Xcode signs the exact bundle identifier/team but
      // legitimately omits an entitlement blob. Absence is therefore the
      // strongest no-capability receipt for this one already-verified xctest.
      // Every executable application/extension above must still carry and
      // pass the explicit entitlement allowlist below.
      final entitlementEntity = FileSystemEntity.typeSync(
        entitlementPlist.path,
        followLinks: false,
      );
      if (allowAbsentSignedEntitlements &&
          entitlementEntity == FileSystemEntityType.notFound) {
        return;
      }
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'A prepared Plan 269 code object omitted its signed entitlements.',
      );
    }
    await _protectFile(entitlementPlist, 'codesign-entitlements-$label');
    final entitlementJson = File(
      '${_runDirectory.path}/codesign-entitlements-$label.json',
    );
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'decode-entitlements-$label',
        executable: 'plutil',
        arguments: <String>[
          '-convert',
          'json',
          '-o',
          entitlementJson.path,
          entitlementPlist.path,
        ],
        timeout: const Duration(seconds: 15),
      ),
      blocker: 'missingArtifact',
    );
    await _protectFile(entitlementJson, 'codesign-entitlements-$label-json');
    final value = _readObject(entitlementJson, 'dedicated $label entitlements');
    const allowedKeys = <String>{
      'application-identifier',
      'com.apple.developer.team-identifier',
      'keychain-access-groups',
      'get-task-allow',
    };
    final expectedApplicationIdentifier =
        '$_developmentTeamId.$expectedBundleId';
    final keys = value.keys.toSet();
    final keychainGroups = value['keychain-access-groups'];
    final getTaskAllow = value['get-task-allow'];
    final exactBaseIdentity =
        value['application-identifier'] == expectedApplicationIdentifier &&
        value['com.apple.developer.team-identifier'] == _developmentTeamId;
    final exactKeychain =
        keychainGroups == null ||
        (keychainGroups is List &&
            keychainGroups.length == 1 &&
            keychainGroups.single == expectedApplicationIdentifier);
    final exactDebugFlag = getTaskAllow == null || getTaskAllow is bool;
    if (!keys.every(allowedKeys.contains) ||
        !exactBaseIdentity ||
        !exactKeychain ||
        !exactDebugFlag) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'A prepared Plan 269 code object has entitlements outside the exact '
            'dedicated allowlist.',
      );
    }
  }

  String? _exactCodesignField(GroupMediaIosCommandResult result, String field) {
    final prefix = '$field=';
    final values = const LineSplitter()
        .convert('${result.stdout}\n${result.stderr}')
        .map((line) => line.trim())
        .where((line) => line.startsWith(prefix))
        .map((line) => line.substring(prefix.length))
        .toList(growable: false);
    return values.length == 1 && values.single.isNotEmpty
        ? values.single
        : null;
  }

  Future<File> _materializePatchedXctestrun() async {
    final decodedFile = File('${_runDirectory.path}/xctestrun.json');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'decode-xctestrun',
        executable: 'plutil',
        arguments: <String>[
          '-convert',
          'json',
          '-o',
          decodedFile.path,
          _bundle.xctestrun.path,
        ],
        timeout: const Duration(seconds: 20),
      ),
      blocker: 'missingArtifact',
    );
    final decoded = _readObject(decodedFile, 'prepared .xctestrun');
    final relocation = relocateIosXctestrun(
      plist: decoded,
      cachedProducts: _bundle.products,
      cachedApplication: _bundle.application,
      uiTargetBundleIdentifier: _bundleId,
      uiEnvironment: <String, String>{
        'MKNOON_269_APP_BUNDLE_ID': _bundleId,
        'MKNOON_269_RUN_ID': options.runId,
        'MKNOON_269_PHASE_A_READY_TEXT': _phaseAReady,
        'MKNOON_269_PHASE_B_READY_TEXT': _phaseBReady,
        'MKNOON_269_PHASE_A_EFFECT_TEXT': _phaseAMessage,
        'MKNOON_269_PHASE_B_EFFECT_TEXT': _phaseBMessage,
      },
    );
    if (relocation.uiTargetsPatched != 1 ||
        relocation.productPathsPatched == 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared bundle has no uniquely relocatable RunnerUITests target.',
      );
    }
    final patchedJson = File('${_runDirectory.path}/patched-xctestrun.json')
      ..writeAsStringSync(jsonEncode(relocation.plist), flush: true);
    final patched = File(
      '${_runDirectory.path}/RunnerUITests.patched.xctestrun',
    );
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'encode-xctestrun',
        executable: 'plutil',
        arguments: <String>[
          '-convert',
          'xml1',
          '-o',
          patched.path,
          patchedJson.path,
        ],
        timeout: const Duration(seconds: 20),
      ),
      blocker: 'missingArtifact',
    );
    if (!_regularFile(patched)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The relocated no-build .xctestrun could not be materialized.',
      );
    }
    return patched;
  }

  Future<void> _installPreparedApplication() async {
    _requirePreparedArtifactCustody('pre-install');
    _deviceMutationStarted = true;
    final installJson = File('${_runDirectory.path}/install.json');
    final installLog = File('${_runDirectory.path}/install.log');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'install-prepared-app',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'install',
          'app',
          '--device',
          options.receiverDeviceId,
          _bundle.application.path,
          '--json-output',
          installJson.path,
          '--log-output',
          installLog.path,
          '--quiet',
        ],
        timeout: const Duration(minutes: 2),
      ),
      blocker: 'deviceState',
    );
    if (!_regularFile(installJson)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'devicectl did not produce an installation receipt.',
      );
    }
  }

  Future<_DisposableResetReceipt> _runDisposableReset(String phase) async {
    if (!groupMediaIosDisposableResetPhases.contains(phase)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The dedicated iOS reset phase is not allowlisted.',
      );
    }
    final nonce = _freshResetNonce(phase);
    final request = File('${_runDirectory.path}/reset-$phase-request.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': groupMediaIosDisposableResetRequestSchema,
          'run_id': options.runId,
          'nonce': nonce,
          'phase': phase,
          'contains_secrets': false,
        }),
        flush: true,
      );
    await _protectFile(request, 'reset-$phase-request');
    final copyReceipt = File('${_runDirectory.path}/reset-$phase-copy.json');
    final copyLog = File('${_runDirectory.path}/reset-$phase-copy.log');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'stage-reset-$phase',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'copy',
          'to',
          '--device',
          options.receiverDeviceId,
          '--source',
          request.path,
          '--destination',
          'Documents/$groupMediaIosDisposableResetRequestFile',
          '--domain-type',
          'appDataContainer',
          '--domain-identifier',
          _bundleId,
          '--json-output',
          copyReceipt.path,
          '--log-output',
          copyLog.path,
          '--quiet',
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'deviceState',
    );
    if (!_regularFile(copyReceipt)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The dedicated iOS reset request was not staged.',
      );
    }

    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'launch-reset-$phase',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'process',
          'launch',
          '--device',
          options.receiverDeviceId,
          '--terminate-existing',
          _bundleId,
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'deviceState',
    );

    final deadline = DateTime.now().add(const Duration(seconds: 45));
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      // CoreDevice/Xcode 26.6 requires a non-existent destination *file* for
      // a single-file receive. Passing a pre-created directory can hang until
      // timeout and then report that the destination cannot be opened.
      final destination = File(
        '${_runDirectory.path}/reset-$phase-pull-$attempt-'
        '$groupMediaIosDisposableResetReceiptFile',
      );
      final output = File(
        '${_runDirectory.path}/reset-$phase-pull-$attempt.json',
      );
      final log = File('${_runDirectory.path}/reset-$phase-pull-$attempt.log');
      final result = await commandRunner.run(
        GroupMediaIosCommand(
          label: 'pull-reset-$phase',
          executable: 'xcrun',
          arguments: <String>[
            'devicectl',
            'device',
            'copy',
            'from',
            '--device',
            options.receiverDeviceId,
            '--source',
            'Documents/$groupMediaIosDisposableResetReceiptFile',
            '--destination',
            destination.path,
            '--domain-type',
            'appDataContainer',
            '--domain-identifier',
            _bundleId,
            '--json-output',
            output.path,
            '--log-output',
            log.path,
            '--quiet',
          ],
          timeout: const Duration(seconds: 15),
        ),
      );
      if (result.exitCode == 0) {
        if (!_regularFile(destination)) {
          throw const GroupMediaIosBackgroundRecoveryFailure(
            'The dedicated iOS reset receipt copy was absent.',
          );
        }
        late final _DisposableResetReceipt receipt;
        try {
          final receiptDigest = sha256
              .convert(destination.readAsBytesSync())
              .toString();
          receipt = _DisposableResetReceipt.parse(
            _readObject(destination, 'dedicated iOS reset receipt'),
            expectedRunId: options.runId,
            expectedNonce: nonce,
            expectedPhase: phase,
            receiptDigest: receiptDigest,
          );
        } on GroupMediaIosBackgroundRecoveryFailure {
          attempt += 1;
          await Future<void>.delayed(const Duration(milliseconds: 100));
          continue;
        }
        await _terminateReceiptProcess(
          receipt.processId,
          'terminate-reset-$phase',
        );
        await _requireApplicationInstalled('after-$phase-reset');
        return receipt;
      }
      attempt += 1;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const GroupMediaIosBackgroundRecoveryFailure(
      'The dedicated iOS reset receipt did not arrive before its deadline.',
    );
  }

  String _freshResetNonce(String phase) {
    final entropy = List<int>.generate(
      32,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    return sha256.convert(<int>[
      ...utf8.encode(
        '${options.runId}:disposable-reset:$phase:'
        '${_bundle.contractDigest}:',
      ),
      ...entropy,
    ]).toString();
  }

  Future<void> _requireApplicationInstalled(String label) async {
    if (!await _isPreparedApplicationInstalled(label)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The freshly installed physical iOS app is not discoverable.',
      );
    }
  }

  Future<bool> _isPreparedApplicationInstalled(String label) async {
    final output = File('${_runDirectory.path}/apps-$label.json');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'inspect-app-$label',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'info',
          'apps',
          '--device',
          options.receiverDeviceId,
          '--bundle-id',
          _bundleId,
          '--json-output',
          output.path,
          '--quiet',
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'deviceState',
    );
    final decoded = _readObject(output, 'physical iOS app inventory');
    final result = decoded['result'];
    final apps = result is Map ? result['apps'] : null;
    if (apps is! List || apps.any((item) => item is! Map)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The physical iOS app inventory is ambiguous.',
      );
    }
    final matches = apps
        .where((item) => (item! as Map)['bundleIdentifier'] == _bundleId)
        .toList(growable: false);
    if (matches.length > 1 || apps.length != matches.length) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The physical iOS app inventory is not exact.',
      );
    }
    if (matches.isEmpty) return false;
    final app = matches.single! as Map;
    final urlValue = app['url'];
    if (urlValue is! String) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The physical iOS app inventory omitted its installed URL.',
      );
    }
    late final Uri url;
    try {
      url = Uri.parse(urlValue);
    } on FormatException {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The physical iOS app inventory URL is malformed.',
      );
    }
    if (url.scheme != 'file' ||
        url.hasQuery ||
        url.hasFragment ||
        !(url.path.endsWith('/Runner.app') ||
            url.path.endsWith('/Runner.app/'))) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The physical iOS app inventory URL is not the dedicated Runner app.',
      );
    }
    final applicationPath = File.fromUri(
      url,
    ).path.replaceFirst(RegExp(r'/$'), '');
    final executablePath = '$applicationPath/Runner';
    final boundPath = _installedApplicationExecutablePath;
    if (boundPath != null && boundPath != executablePath) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The installed dedicated Runner container changed during proof.',
      );
    }
    _installedApplicationExecutablePath = executablePath;
    return true;
  }

  Future<void> _terminateReceiptProcess(int processId, String label) async {
    await _requireDedicatedProcessOwnership(processId, label);
    await _requiredCommand(
      GroupMediaIosCommand(
        label: label,
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'process',
          'terminate',
          '--device',
          options.receiverDeviceId,
          '--pid',
          '$processId',
          '--kill',
        ],
        timeout: const Duration(minutes: 1),
      ),
      blocker: 'deviceState',
    );
  }

  Future<void> _requireDedicatedProcessOwnership(
    int processId,
    String label,
  ) async {
    if (processId <= 1) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'A receipt named an unsafe process identifier.',
      );
    }
    final output = File('${_runDirectory.path}/process-owner-$label.json');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'inspect-process-$label',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'info',
          'processes',
          '--device',
          options.receiverDeviceId,
          '--filter',
          'processIdentifier == $processId',
          '--json-output',
          output.path,
          '--quiet',
        ],
        timeout: const Duration(seconds: 30),
      ),
      blocker: 'deviceState',
    );
    final decoded = _readObject(output, 'physical iOS process ownership');
    final result = decoded['result'];
    final processes = result is Map ? result['runningProcesses'] : null;
    if (processes is! List || processes.length != 1) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The receipt-bound physical iOS process is no longer unique.',
      );
    }
    final process = processes.single;
    final executable = process is Map ? process['executable'] : null;
    final installedExecutable = _installedApplicationExecutablePath;
    final executablePath = _physicalIosExecutablePath(executable);
    if (process is! Map ||
        process['processIdentifier'] != processId ||
        executablePath == null ||
        installedExecutable == null ||
        executablePath != installedExecutable) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The receipt-bound process is not the dedicated Runner executable.',
      );
    }
  }

  String? _physicalIosExecutablePath(Object? value) {
    if (value is! String || value.isEmpty) return null;
    late final Uri uri;
    try {
      uri = Uri.parse(value);
    } on FormatException {
      return null;
    }
    if (uri.hasQuery || uri.hasFragment) return null;
    if (uri.scheme.isEmpty) {
      return value.startsWith('/') && uri.path == value ? value : null;
    }
    if (uri.scheme != 'file' ||
        uri.host.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    try {
      return File.fromUri(uri).path;
    } on Object {
      return null;
    }
  }

  Future<void> _stageAutoSetup() async {
    final config = File('${_runDirectory.path}/auto_setup.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'username': 'P269Ios${_sha256(options.runId).substring(0, 12)}',
        }),
        flush: true,
      );
    await _protectFile(config, 'auto-setup');
    final receipt = File('${_runDirectory.path}/auto-setup-copy.json');
    final log = File('${_runDirectory.path}/auto-setup-copy.log');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'stage-auto-setup',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'copy',
          'to',
          '--device',
          options.receiverDeviceId,
          '--source',
          config.path,
          '--destination',
          'Documents/auto_setup.json',
          '--domain-type',
          'appDataContainer',
          '--domain-identifier',
          _bundleId,
          '--json-output',
          receipt.path,
          '--log-output',
          log.path,
          '--quiet',
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'deviceState',
    );
    if (!_regularFile(receipt)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'deviceState',
        'The fresh iOS auto-setup file was not staged.',
      );
    }
  }

  Future<void> _startSystemLogCapture() async {
    _systemLog.writeAsStringSync('', flush: true);
    await _protectFile(_systemLog, 'system-log');
    await systemLogCapture.start(
      deviceId: options.receiverDeviceId,
      output: _systemLog,
    );
    _systemLogStarted = true;
  }

  Future<void> _protectFile(File file, String label) async {
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'protect-$label',
        executable: 'chmod',
        arguments: <String>['600', file.path],
        timeout: const Duration(seconds: 10),
      ),
      blocker: 'harness',
    );
    if (!_fileEntity(file) || (file.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'A protected iOS proof file has unsafe permissions.',
      );
    }
  }

  Future<GroupMediaIosBackgroundRecoveryFailure?>
  _cleanupPreparedApplication() async {
    var failed = false;
    if (_systemLogStarted) {
      try {
        await systemLogCapture.stop();
      } on Object {
        failed = true;
      } finally {
        _systemLogStarted = false;
      }
    }
    try {
      _postResetReceipt = await _runDisposableReset('post');
    } on Object {
      failed = true;
    }
    try {
      if (!await _isPreparedApplicationInstalled('after-cleanup')) {
        failed = true;
      }
    } on Object {
      failed = true;
    }
    if (!await _purgeProtectedTransientProofFiles()) failed = true;
    return failed
        ? const GroupMediaIosBackgroundRecoveryFailure(
            'Mandatory dedicated iOS namespace reset did not converge.',
          )
        : null;
  }

  Future<bool> _purgeProtectedTransientProofFiles() async {
    var converged = true;
    final files = <File>[
      _systemLog,
      File('${_runDirectory.path}/fixture-state.json'),
      File('${_runDirectory.path}/auto_setup.json'),
      File('${_runDirectory.path}/phase-a-ready.json'),
      File('${_runDirectory.path}/phase-b-ready.json'),
      File('${_runDirectory.path}/fixture-cancel.json'),
      File('${_runDirectory.path}/reset-pre-request.json'),
      File('${_runDirectory.path}/reset-post-request.json'),
      for (final stem in const <String>[
        'phase-a',
        'phase-b-claim',
        'phase-b-recovery',
      ])
        File('${_runDirectory.path}/$stem-android-command-audit.json'),
    ];
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
        if (await file.exists()) converged = false;
      } on Object {
        converged = false;
      }
    }
    for (final entity in _runDirectory.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((value) => value.isNotEmpty)
          .last;
      if (!name.startsWith('reset-pre-') && !name.startsWith('reset-post-')) {
        continue;
      }
      try {
        await entity.delete(recursive: true);
        if (await entity.exists()) converged = false;
      } on Object {
        converged = false;
      }
    }
    return converged;
  }

  Future<void> _launchRoot(
    String label, {
    bool terminateExisting = true,
  }) async {
    await _requiredCommand(
      GroupMediaIosCommand(
        label: label,
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'process',
          'launch',
          '--device',
          options.receiverDeviceId,
          if (terminateExisting) '--terminate-existing',
          '--activate',
          _bundleId,
        ],
        timeout: const Duration(seconds: 45),
      ),
      blocker: 'deviceState',
    );
  }

  Future<void> _terminatePhaseB(int pid) async {
    await _requireDedicatedProcessOwnership(pid, 'host-terminate-phase-b');
    await _requiredCommand(
      GroupMediaIosCommand(
        label: 'host-terminate-phase-b',
        executable: 'xcrun',
        arguments: <String>[
          'devicectl',
          'device',
          'process',
          'terminate',
          '--device',
          options.receiverDeviceId,
          '--pid',
          '$pid',
          '--kill',
        ],
        timeout: const Duration(seconds: 30),
      ),
      blocker: 'deviceState',
    );
  }

  Future<void> _waitForFixtureReady({
    required _PendingFixture pending,
    required File ready,
    required String action,
    required String mediaPhase,
    required String expectedLabel,
  }) async {
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (DateTime.now().isBefore(deadline)) {
      final failure = pending.error;
      if (failure != null) {
        Error.throwWithStackTrace(failure, pending.stackTrace!);
      }
      if (_regularFile(ready)) {
        if ((ready.statSync().mode & 0x3f) != 0) {
          throw const GroupMediaIosBackgroundRecoveryFailure(
            'The foreground-arm readiness sidecar is not protected.',
          );
        }
        final value = _readObject(ready, 'foreground-arm readiness sidecar');
        const keys = <String>{
          'schema',
          'run_id',
          'action',
          'media_phase',
          'ready_label_sha256',
          'foreground_arm_complete',
        };
        if (!_sameSet(value.keys.toSet(), keys) ||
            value['schema'] != 'mknoon.group-media-ios-fixture-ready.v1' ||
            value['run_id'] != options.runId ||
            value['action'] != action ||
            value['media_phase'] != mediaPhase ||
            value['ready_label_sha256'] != _sha256(expectedLabel) ||
            value['foreground_arm_complete'] != true) {
          throw const GroupMediaIosBackgroundRecoveryFailure(
            'The foreground-arm readiness sidecar is not run-bound.',
          );
        }
        return;
      }
      if (pending.completed) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The fixture completed before publishing foreground-arm readiness.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw const GroupMediaIosBackgroundRecoveryFailure(
      'The foreground receiver arm did not become ready.',
    );
  }

  Future<void> _cancelAndSettleFixtures({
    required File cancel,
    required List<_PendingFixture> pendings,
  }) async {
    final active = pendings.where((pending) => !pending.completed).toList();
    if (active.isEmpty) return;
    cancel.writeAsStringSync(
      '${jsonEncode(<String, Object?>{'schema': 'mknoon.group-media-ios-fixture-cancel.v1', 'run_id': options.runId, 'cancel': true, 'contains_secrets': false})}\n',
      flush: true,
    );
    await _protectFile(cancel, 'fixture-cancel');
    for (final pending in active) {
      try {
        await pending.future.timeout(const Duration(seconds: 90));
      } on TimeoutException {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'A cancelled fixture did not restore the Android sender in time.',
        );
      } on Object {
        // The driver must fail its cancelled action after restoring the exact
        // Android app state; settlement, not success, is required here.
      }
    }
  }

  Future<_FixtureReceipt> _runFixture({
    required String label,
    required String action,
    required String outputName,
    required String expectedPhase,
    required String expectedEffectDigest,
    int? interruptedPid,
    File? ready,
    File? cancel,
  }) async {
    final output = File('${_runDirectory.path}/$outputName');
    final observationStem = outputName.replaceAll('-receipt.json', '');
    final nativeObservation = File(
      '${_runDirectory.path}/$observationStem-native.json',
    );
    final databaseObservation = File(
      '${_runDirectory.path}/$observationStem-database.json',
    );
    final androidCommandAudit = File(
      '${_runDirectory.path}/$observationStem-android-command-audit.json',
    );
    if (output.existsSync() ||
        androidCommandAudit.existsSync() ||
        ready?.existsSync() == true) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'A run-scoped iOS fixture receipt already exists.',
      );
    }
    if (!_regularFile(_systemLog) || (_systemLog.statSync().mode & 0x3f) != 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'The physical iOS fixture requires one protected system-log capture.',
      );
    }
    final command = GroupMediaIosCommand(
      label: label,
      executable: _fixtureDriverCustody.canonicalDriver.path,
      arguments: <String>[
        '--action',
        action,
        '--run-id',
        options.runId,
        '--sender-device',
        options.senderDeviceId,
        '--receiver-device',
        options.receiverDeviceId,
        '--phase-a-message',
        _phaseAMessage,
        '--phase-b-message',
        _phaseBMessage,
        '--phase-a-ready',
        _phaseAReady,
        '--phase-b-ready',
        _phaseBReady,
        '--system-log',
        _systemLog.absolute.path,
        if (ready != null) ...<String>['--ready', ready.absolute.path],
        if (cancel != null) ...<String>['--cancel', cancel.absolute.path],
        if (interruptedPid != null) ...<String>[
          '--interrupted-pid',
          '$interruptedPid',
        ],
        '--native-observation',
        nativeObservation.path,
        '--database-observation',
        databaseObservation.path,
        '--android-artifact',
        options.androidCompanionArtifact.absolute.path,
        '--android-artifact-sha256',
        options.androidCompanionArtifactSha256,
        '--android-command-audit',
        androidCommandAudit.path,
        '--output',
        output.path,
      ],
      environment: <String, String>{
        for (final entry in options.inheritedEnvironment.entries)
          if (entry.key != groupMediaAndroidDisposableArtifactEnvironment &&
              entry.key != groupMediaAndroidDisposableArtifactSha256Environment)
            entry.key: entry.value,
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
      },
      timeout: const Duration(minutes: 8),
    );
    _fixtureDriverCustody.verifyUnchanged();
    late final GroupMediaIosCommandResult result;
    try {
      result = await _runFixtureCommand(action: action, command: command);
    } finally {
      _fixtureDriverCustody.verifyUnchanged();
    }
    final fixtureAudit = _readAndroidFixtureCommandAudit(
      androidCommandAudit,
      action: action,
    );
    if (_androidResetActions.contains(action)) {
      if (_androidFixtureCommandAudits.containsKey(action)) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The Android fixture command audit was published more than once.',
        );
      }
      _androidFixtureCommandAudits[action] = fixtureAudit;
    }
    if (result.exitCode == 78) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'environment',
        'The real relay/SQLCipher iOS fixture boundary is unavailable.',
      );
    }
    if (result.exitCode != 0 ||
        !_regularFile(output) ||
        !_regularFile(nativeObservation) ||
        !_regularFile(databaseObservation)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The real relay/SQLCipher iOS fixture boundary did not produce a '
        'receipt.',
      );
    }
    final parsedReceipt = _FixtureReceipt.parse(
      _readObject(output, '$expectedPhase fixture receipt'),
    );
    final native = _readObject(
      nativeObservation,
      '$expectedPhase physical native observation',
    );
    final database = _readObject(
      databaseObservation,
      '$expectedPhase production SQLCipher observation',
    );
    final section = switch (expectedPhase) {
      'a' => 'phase_a',
      'b_claim' => 'phase_b_claim',
      _ => 'phase_b_recovery',
    };
    final nativeDigest = groupMediaIosObservationDigest(native);
    final databaseDigest = groupMediaIosObservationDigest(database);
    final observationPair = <String, Object?>{
      'native': native,
      'database': database,
      'native_sha256': nativeDigest,
      'database_sha256': databaseDigest,
    };
    final observationValidation = validateGroupMediaIosBoundaryObservation(
      value: observationPair,
      section: section,
      runId: options.runId,
      receiverDigest: _receiverDigest,
    );
    if (!observationValidation.ok ||
        parsedReceipt.nativeObservationDigest != nativeDigest ||
        parsedReceipt.databaseObservationDigest != databaseDigest) {
      throw GroupMediaIosBackgroundRecoveryFailure(
        'The iOS fixture receipt lacks independent physical-native and '
        'production-SQLCipher custody: ${observationValidation.detail}',
      );
    }
    final receipt = parsedReceipt.withObservationPair(observationPair);
    if (receipt.runId != options.runId ||
        receipt.phase != expectedPhase ||
        receipt.senderDigest != _senderDigest ||
        receipt.receiverDigest != _receiverDigest ||
        receipt.uiEffectDigest != expectedEffectDigest ||
        receipt.parentMessageDigest !=
            _sha256(
              'P269-PARENT-${expectedPhase == 'a' ? 'A' : 'B'}-${options.runId}',
            )) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The iOS fixture receipt is not bound to this run, phase, message, '
        'and explicit device pair.',
      );
    }
    return receipt;
  }

  Future<GroupMediaIosCommandResult> _runFixtureCommand({
    required String action,
    required GroupMediaIosCommand command,
  }) async {
    if (action == 'phase-b-observe-recovery') {
      return commandRunner.run(command);
    }
    GroupMediaAndroidDisposableResetReceipt? preReceipt;
    GroupMediaIosCommandResult? result;
    Object? primaryError;
    StackTrace? primaryStackTrace;
    try {
      preReceipt = await _androidBoundary.prepare(action);
      result = await commandRunner.run(command);
    } on Object catch (error, stackTrace) {
      primaryError = error;
      primaryStackTrace = stackTrace;
    }
    GroupMediaAndroidDisposableResetReceipt? postReceipt;
    try {
      postReceipt = await _androidBoundary.cleanup(action);
    } on Object {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The dedicated Android sender post-reset failed.',
      );
    }
    if (preReceipt != null && postReceipt != null) {
      if (preReceipt.phase != 'pre' ||
          postReceipt.phase != 'post' ||
          preReceipt.sha256Digest == postReceipt.sha256Digest) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The dedicated Android reset receipts were not phase-distinct.',
        );
      }
      final boundaryAudit = _androidBoundary.commandAudit(action);
      if (boundaryAudit.adbCommandCount == 0 ||
          !boundaryAudit.isSafe ||
          _androidBoundaryCommandAudits.containsKey(action)) {
        throw const GroupMediaIosBackgroundRecoveryFailure(
          'The dedicated Android boundary command audit was incomplete.',
        );
      }
      _androidPreResetReceipts[action] = preReceipt;
      _androidPostResetReceipts[action] = postReceipt;
      _androidBoundaryCommandAudits[action] = boundaryAudit;
    }
    if (primaryError != null) {
      Error.throwWithStackTrace(primaryError, primaryStackTrace!);
    }
    if (result == null || preReceipt == null || postReceipt == null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The dedicated Android sender reset boundary was incomplete.',
      );
    }
    return result;
  }

  void _validatePhaseAReceipt(_FixtureReceipt receipt) {
    if (receipt.barrier != 'background_receive_started' ||
        !receipt.criticalTaskGranted ||
        receipt.terminalPath != 'normal' ||
        receipt.nativeEndCount != 1 ||
        receipt.durableStatus != 'done' ||
        receipt.downloadAttempts != 1 ||
        receipt.resumeAttempts != 0 ||
        receipt.relaunchPid != null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'Phase A did not prove one granted task, normal end, and durable '
        'background completion.',
      );
    }
  }

  void _validatePhaseBClaimReceipt(_FixtureReceipt receipt) {
    if (receipt.barrier != 'durable_post_claim_pre_commit' ||
        !receipt.criticalTaskGranted ||
        receipt.terminalPath != 'none' ||
        receipt.nativeEndCount != 0 ||
        receipt.durableStatus != 'downloading' ||
        receipt.downloadAttempts != 1 ||
        receipt.resumeAttempts != 0 ||
        receipt.relaunchPid != null) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'Phase B did not stop at the durable post-claim/pre-commit barrier.',
      );
    }
  }

  void _validatePhaseBRecoveryReceipt(
    _FixtureReceipt receipt, {
    required int interruptedPid,
  }) {
    if (receipt.barrier != 'resume_after_first_group_inbox_drain' ||
        !receipt.criticalTaskGranted ||
        receipt.terminalPath != 'interrupted' ||
        receipt.nativeEndCount != 0 ||
        receipt.durableStatus != 'done' ||
        receipt.downloadAttempts != 2 ||
        receipt.resumeAttempts != 1 ||
        receipt.receiverPid != interruptedPid ||
        receipt.relaunchPid == null ||
        receipt.relaunchPid == interruptedPid) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'Phase B did not prove one interrupted terminal path followed by one '
        'fresh-process resume-after-drain convergence.',
      );
    }
  }

  String _databasePathDigest(_FixtureReceipt receipt) {
    final database = receipt.observationPair['database'];
    final digest = database is Map ? database['database_path_sha256'] : null;
    if (digest is! String || !_digestPattern.hasMatch(digest)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The production SQLCipher observation omitted its database path.',
      );
    }
    return digest;
  }

  Future<GroupMediaIosCommandResult> _requiredCommand(
    GroupMediaIosCommand command, {
    required String blocker,
  }) async {
    final result = await commandRunner.run(command);
    if (result.exitCode != 0) {
      throw GroupMediaIosBackgroundRecoveryBlocked(
        blocker,
        'Required iOS proof command failed: ${command.label}.',
      );
    }
    return result;
  }

  void _requireEmptyBuildGuard() {
    final guard = options.buildGuardLog;
    if (guard != null &&
        guard.existsSync() &&
        guard.readAsStringSync().trim().isNotEmpty) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'harness',
        'A forbidden child build reached the group-media build guard.',
      );
    }
  }
}

final class _DisposableResetReceipt {
  const _DisposableResetReceipt({
    required this.phase,
    required this.processId,
    required this.receiptDigest,
  });

  final String phase;
  final int processId;
  final String receiptDigest;

  Map<String, Object?> get artifactFacts => <String, Object?>{
    'phase': phase,
    'receipt_sha256': receiptDigest,
    'keychain_empty': true,
    'database_absent': true,
    'allowlisted_files_absent': true,
  };

  factory _DisposableResetReceipt.parse(
    Map<String, Object?> value, {
    required String expectedRunId,
    required String expectedNonce,
    required String expectedPhase,
    required String receiptDigest,
  }) {
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
    if (value.keys.toSet().length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['schema'] != groupMediaIosDisposableResetReceiptSchema ||
        value['run_id'] != expectedRunId ||
        value['nonce'] != expectedNonce ||
        value['phase'] != expectedPhase ||
        processId is! int ||
        processId <= 1 ||
        value['bundle_id'] != groupMediaIosDisposableBundleId ||
        value['profile'] != groupMediaIosDisposableBuildProfile ||
        value['keychain_empty'] != true ||
        value['database_absent'] != true ||
        value['allowlisted_files_absent'] != true ||
        value['contains_secrets'] != false ||
        !_digestPattern.hasMatch(receiptDigest)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The dedicated iOS reset receipt was not exact or run-bound.',
      );
    }
    return _DisposableResetReceipt(
      phase: expectedPhase,
      processId: processId,
      receiptDigest: receiptDigest,
    );
  }
}

final class _PreparedIosBundle {
  const _PreparedIosBundle({
    required this.root,
    required this.application,
    required this.xctestrun,
    required this.products,
    required this.uiTestHost,
    required this.uiTestBundle,
    required this.contractDigest,
  });

  final Directory root;
  final Directory application;
  final File xctestrun;
  final Directory products;
  final Directory uiTestHost;
  final Directory uiTestBundle;
  final String contractDigest;

  static _PreparedIosBundle resolve(Directory candidate) {
    if (!_directory(candidate)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The centrally prepared physical app/XCTest bundle is missing.',
      );
    }
    final root = Directory(candidate.resolveSymbolicLinksSync());
    final manifest = File('${root.path}/bundle_manifest.json');
    if (!_regularFile(manifest)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared iOS bundle has no member manifest.',
      );
    }
    final decoded = _readObject(manifest, 'prepared iOS bundle manifest');
    const keys = <String>{
      'schema',
      'profileId',
      'applicationApp',
      'xctestrun',
      'testProducts',
      'centralCompileCommands',
      'logicalBuildCount',
      'childBuildCount',
    };
    if (decoded.keys.toSet().length != keys.length ||
        !decoded.keys.toSet().containsAll(keys) ||
        decoded['schema'] != _bundleSchema ||
        decoded['profileId'] != groupMediaReliabilityIosBuildProfile ||
        decoded['centralCompileCommands'] != 1 ||
        decoded['logicalBuildCount'] != 1 ||
        decoded['childBuildCount'] != 0) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared iOS companion bundle manifest is not exact.',
      );
    }
    final application = _safeDirectoryMember(
      root,
      decoded['applicationApp'],
      suffix: '.app',
    );
    final xctestrun = _safeFileMember(
      root,
      decoded['xctestrun'],
      suffix: '.xctestrun',
    );
    final products = _safeDirectoryMember(root, decoded['testProducts']);
    final applicationExecutable = File('${application.path}/Runner');
    final uiTestHost = Directory(
      '${products.path}/Release-iphoneos/RunnerUITests-Runner.app',
    );
    final uiTestBundle = Directory(
      '${uiTestHost.path}/PlugIns/RunnerUITests.xctest',
    );
    final uiTestHostExecutable = File(
      '${uiTestHost.path}/RunnerUITests-Runner',
    );
    final uiTestHostInfo = File('${uiTestHost.path}/Info.plist');
    final uiExecutable = File('${uiTestBundle.path}/RunnerUITests');
    final uiTestInfo = File('${uiTestBundle.path}/Info.plist');
    final infoPlist = File('${application.path}/Info.plist');
    final shareExtensionExecutable = File(
      '${application.path}/PlugIns/Share Extension.appex/Share Extension',
    );
    final shareExtensionInfo = File(
      '${application.path}/PlugIns/Share Extension.appex/Info.plist',
    );
    final notificationServiceExecutable = File(
      '${application.path}/PlugIns/NotificationService.appex/'
      'NotificationService',
    );
    final notificationServiceInfo = File(
      '${application.path}/PlugIns/NotificationService.appex/Info.plist',
    );
    if (!_regularFile(applicationExecutable) ||
        !_regularFile(uiTestHostExecutable) ||
        !_regularFile(uiTestHostInfo) ||
        !_regularFile(uiExecutable) ||
        !_regularFile(uiTestInfo) ||
        !_regularFile(infoPlist) ||
        !_regularFile(shareExtensionExecutable) ||
        !_regularFile(shareExtensionInfo) ||
        !_regularFile(notificationServiceExecutable) ||
        !_regularFile(notificationServiceInfo)) {
      throw const GroupMediaIosBackgroundRecoveryBlocked(
        'missingArtifact',
        'The prepared iOS bundle is missing its app or XCTest executable.',
      );
    }
    return _PreparedIosBundle(
      root: root,
      application: application,
      xctestrun: xctestrun,
      products: products,
      uiTestHost: uiTestHost,
      uiTestBundle: uiTestBundle,
      contractDigest: groupMediaPreparedDirectorySha256(root),
    );
  }
}

final class _PendingFixture {
  _PendingFixture(Future<_FixtureReceipt> source) : future = source {
    source.then<void>(
      (_) {
        completed = true;
      },
      onError: (Object value, StackTrace trace) {
        error = value;
        stackTrace = trace;
        completed = true;
      },
    );
  }

  final Future<_FixtureReceipt> future;
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;
}

final class _FixtureReceipt {
  const _FixtureReceipt({
    required this.runId,
    required this.phase,
    required this.senderDigest,
    required this.receiverDigest,
    required this.parentMessageDigest,
    required this.uiEffectDigest,
    required this.receiverPid,
    required this.relaunchPid,
    required this.barrier,
    required this.criticalTaskGranted,
    required this.terminalPath,
    required this.nativeEndCount,
    required this.durableStatus,
    required this.downloadAttempts,
    required this.resumeAttempts,
    required this.nativeObservationDigest,
    required this.databaseObservationDigest,
    required this.observationPair,
  });

  final String runId;
  final String phase;
  final String senderDigest;
  final String receiverDigest;
  final String parentMessageDigest;
  final String uiEffectDigest;
  final int receiverPid;
  final int? relaunchPid;
  final String barrier;
  final bool criticalTaskGranted;
  final String terminalPath;
  final int nativeEndCount;
  final String durableStatus;
  final int downloadAttempts;
  final int resumeAttempts;
  final String nativeObservationDigest;
  final String databaseObservationDigest;
  final Map<String, Object?> observationPair;

  _FixtureReceipt withObservationPair(Map<String, Object?> pair) =>
      _FixtureReceipt(
        runId: runId,
        phase: phase,
        senderDigest: senderDigest,
        receiverDigest: receiverDigest,
        parentMessageDigest: parentMessageDigest,
        uiEffectDigest: uiEffectDigest,
        receiverPid: receiverPid,
        relaunchPid: relaunchPid,
        barrier: barrier,
        criticalTaskGranted: criticalTaskGranted,
        terminalPath: terminalPath,
        nativeEndCount: nativeEndCount,
        durableStatus: durableStatus,
        downloadAttempts: downloadAttempts,
        resumeAttempts: resumeAttempts,
        nativeObservationDigest: nativeObservationDigest,
        databaseObservationDigest: databaseObservationDigest,
        observationPair: Map<String, Object?>.unmodifiable(pair),
      );

  factory _FixtureReceipt.parse(Map<String, Object?> value) {
    const keys = <String>{
      'schema',
      'run_id',
      'phase',
      'sender_device_sha256',
      'receiver_device_sha256',
      'parent_message_sha256',
      'ui_effect_sha256',
      'receiver_pid',
      'relaunch_pid',
      'barrier',
      'critical_task_granted',
      'terminal_path',
      'native_end_count',
      'durable_status',
      'download_attempts',
      'resume_after_drain_attempts',
      'native_observation_sha256',
      'database_observation_sha256',
    };
    final exactKeys =
        value.keys.toSet().length == keys.length &&
        value.keys.toSet().containsAll(keys);
    final runId = value['run_id'];
    final phase = value['phase'];
    final senderDigest = value['sender_device_sha256'];
    final receiverDigest = value['receiver_device_sha256'];
    final parentMessageDigest = value['parent_message_sha256'];
    final uiEffectDigest = value['ui_effect_sha256'];
    final receiverPid = value['receiver_pid'];
    final relaunchPid = value['relaunch_pid'];
    final barrier = value['barrier'];
    final granted = value['critical_task_granted'];
    final terminalPath = value['terminal_path'];
    final nativeEndCount = value['native_end_count'];
    final durableStatus = value['durable_status'];
    final attempts = value['download_attempts'];
    final resumeAttempts = value['resume_after_drain_attempts'];
    final nativeObservationDigest = value['native_observation_sha256'];
    final databaseObservationDigest = value['database_observation_sha256'];
    if (!exactKeys ||
        value['schema'] != groupMediaIosFixtureReceiptSchema ||
        runId is! String ||
        !_safeRunId.hasMatch(runId) ||
        phase is! String ||
        senderDigest is! String ||
        !_digestPattern.hasMatch(senderDigest) ||
        receiverDigest is! String ||
        !_digestPattern.hasMatch(receiverDigest) ||
        parentMessageDigest is! String ||
        !_digestPattern.hasMatch(parentMessageDigest) ||
        uiEffectDigest is! String ||
        !_digestPattern.hasMatch(uiEffectDigest) ||
        receiverPid is! int ||
        receiverPid <= 0 ||
        (relaunchPid != null && (relaunchPid is! int || relaunchPid <= 0)) ||
        barrier is! String ||
        granted is! bool ||
        terminalPath is! String ||
        nativeEndCount is! int ||
        nativeEndCount < 0 ||
        durableStatus is! String ||
        attempts is! int ||
        attempts < 0 ||
        resumeAttempts is! int ||
        resumeAttempts < 0 ||
        nativeObservationDigest is! String ||
        !_digestPattern.hasMatch(nativeObservationDigest) ||
        databaseObservationDigest is! String ||
        !_digestPattern.hasMatch(databaseObservationDigest)) {
      throw const GroupMediaIosBackgroundRecoveryFailure(
        'The iOS fixture receipt has an invalid or ambiguous schema.',
      );
    }
    return _FixtureReceipt(
      runId: runId,
      phase: phase,
      senderDigest: senderDigest,
      receiverDigest: receiverDigest,
      parentMessageDigest: parentMessageDigest,
      uiEffectDigest: uiEffectDigest,
      receiverPid: receiverPid,
      relaunchPid: relaunchPid as int?,
      barrier: barrier,
      criticalTaskGranted: granted,
      terminalPath: terminalPath,
      nativeEndCount: nativeEndCount,
      durableStatus: durableStatus,
      downloadAttempts: attempts,
      resumeAttempts: resumeAttempts,
      nativeObservationDigest: nativeObservationDigest,
      databaseObservationDigest: databaseObservationDigest,
      observationPair: const <String, Object?>{},
    );
  }
}

Map<String, Object?> _readObject(File file, String label) {
  if (!_regularFile(file)) {
    throw GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      '$label is missing.',
    );
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) throw const FormatException('root is not an object');
    return decoded.map<String, Object?>((key, item) => MapEntry('$key', item));
  } on FormatException {
    throw GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      '$label is invalid JSON.',
    );
  }
}

List<Object?> _decodeList(String source, String label) {
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) throw const FormatException('root is not an array');
    return decoded.cast<Object?>();
  } on FormatException {
    throw GroupMediaIosBackgroundRecoveryBlocked(
      'targetUnavailable',
      '$label is invalid JSON.',
    );
  }
}

Directory _safeDirectoryMember(
  Directory root,
  Object? relative, {
  String? suffix,
}) {
  final path = _safeRelative(relative, suffix: suffix);
  final candidate = Directory('${root.path}${Platform.pathSeparator}$path');
  if (!_directory(candidate)) {
    throw const GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      'The prepared iOS bundle is missing a required directory member.',
    );
  }
  final resolved = Directory(candidate.resolveSymbolicLinksSync());
  _requireContained(root, resolved.path);
  return resolved;
}

File _safeFileMember(
  Directory root,
  Object? relative, {
  required String suffix,
}) {
  final path = _safeRelative(relative, suffix: suffix);
  final candidate = File('${root.path}${Platform.pathSeparator}$path');
  if (!_regularFile(candidate)) {
    throw const GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      'The prepared iOS bundle is missing a required file member.',
    );
  }
  final resolved = File(candidate.resolveSymbolicLinksSync());
  _requireContained(root, resolved.path);
  return resolved;
}

String _safeRelative(Object? value, {String? suffix}) {
  if (value is! String ||
      value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '..' || part == '.') ||
      (suffix != null && !value.endsWith(suffix))) {
    throw const GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      'The prepared iOS bundle contains an unsafe member path.',
    );
  }
  return value;
}

void _requireContained(Directory root, String memberPath) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  if (!memberPath.startsWith(prefix)) {
    throw const GroupMediaIosBackgroundRecoveryBlocked(
      'missingArtifact',
      'The prepared iOS bundle member escapes artifact custody.',
    );
  }
}

bool _regularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
        FileSystemEntityType.file &&
    file.lengthSync() > 0;

bool _fileEntity(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: true) ==
    FileSystemEntityType.file;

bool _directory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: true) ==
    FileSystemEntityType.directory;

String? _uiMarker(String line) {
  final index = line.indexOf(_uiMarkerPrefix);
  if (index < 0) return null;
  final suffix = line.substring(index + _uiMarkerPrefix.length).trim();
  return suffix.split(RegExp(r'\s')).first;
}

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameSet(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
