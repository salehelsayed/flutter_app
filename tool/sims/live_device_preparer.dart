import 'dart:async';
import 'dart:io';

import 'live_device_resolver.dart';

enum SimsDevicePreparationStatus { success, failed }

final class SimsPreparationCommandOutput {
  const SimsPreparationCommandOutput({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

abstract interface class SimsDevicePreparationCommandRunner {
  Future<SimsPreparationCommandOutput> run(
    String executable,
    List<String> arguments,
  );

  Future<SimsPreparationCommandOutput> startDetached(
    String executable,
    List<String> arguments,
  );
}

final class ProcessSimsDevicePreparationCommandRunner
    implements SimsDevicePreparationCommandRunner {
  const ProcessSimsDevicePreparationCommandRunner();

  @override
  Future<SimsPreparationCommandOutput> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return SimsPreparationCommandOutput(
      exitCode: result.exitCode,
      stdoutText: '${result.stdout}',
      stderrText: '${result.stderr}',
    );
  }

  @override
  Future<SimsPreparationCommandOutput> startDetached(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.detached,
    );
    return SimsPreparationCommandOutput(
      exitCode: 0,
      stdoutText: 'pid=${process.pid}',
      stderrText: '',
    );
  }
}

final class SimsDevicePreparationResult {
  SimsDevicePreparationResult._({
    required this.status,
    required Iterable<String> preparedLaunchIds,
    required Iterable<String> skippedConnectedRuntimeIds,
    required this.failedLaunchId,
    required this.detail,
  }) : preparedLaunchIds = List<String>.unmodifiable(preparedLaunchIds),
       skippedConnectedRuntimeIds = List<String>.unmodifiable(
         skippedConnectedRuntimeIds,
       );

  final SimsDevicePreparationStatus status;
  final List<String> preparedLaunchIds;
  final List<String> skippedConnectedRuntimeIds;
  final String? failedLaunchId;
  final String detail;

  bool get succeeded => status == SimsDevicePreparationStatus.success;
}

/// Boots only the launchable targets selected by [SimsLiveDeviceResolver].
///
/// Preparation deliberately does not rediscover targets or resolve symbolic
/// locks. The caller must perform both steps again before executing a test.
final class SimsLiveDevicePreparer {
  SimsLiveDevicePreparer({
    SimsDevicePreparationCommandRunner? commandRunner,
    Map<String, String>? environment,
    this.androidEmulatorExecutable,
    this.androidAdbExecutable,
    this.commandTimeout = const Duration(minutes: 5),
    this.androidReadinessTimeout = const Duration(minutes: 5),
    this.androidReadinessProbeTimeout = const Duration(seconds: 10),
    this.androidReadinessPollInterval = const Duration(seconds: 2),
  }) : assert(commandTimeout > Duration.zero),
       assert(androidReadinessTimeout > Duration.zero),
       assert(androidReadinessProbeTimeout > Duration.zero),
       assert(androidReadinessPollInterval >= Duration.zero),
       commandRunner =
           commandRunner ?? const ProcessSimsDevicePreparationCommandRunner(),
       environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       );

  final SimsDevicePreparationCommandRunner commandRunner;
  final Map<String, String> environment;
  final String? androidEmulatorExecutable;
  final String? androidAdbExecutable;
  final Duration commandTimeout;
  final Duration androidReadinessTimeout;
  final Duration androidReadinessProbeTimeout;
  final Duration androidReadinessPollInterval;

  Future<SimsDevicePreparationResult> prepare(
    Iterable<SimsLiveDeviceTarget> preparationTargets,
  ) async {
    final prepared = <String>[];
    final skippedConnected = <String>[];
    final seenPreparationKeys = <String>{};
    final seenConnectedIds = <String>{};

    for (final target in preparationTargets) {
      if (target.availability == SimsLiveDeviceAvailability.connected ||
          target.runtimeId != null) {
        final runtimeId = target.runtimeId;
        if (runtimeId != null && seenConnectedIds.add(runtimeId)) {
          skippedConnected.add(runtimeId);
        }
        continue;
      }

      final launchId = target.launchId?.trim();
      if (launchId == null || launchId.isEmpty) {
        return _failure(
          prepared: prepared,
          skippedConnected: skippedConnected,
          failedLaunchId: null,
          detail: 'Launchable target has no explicit launch ID.',
        );
      }
      final preparationKey =
          '${target.platform.name}:${target.kind.name}:$launchId';
      if (!seenPreparationKeys.add(preparationKey)) continue;

      if (target.isAndroidEmulator) {
        final emulatorExecutable =
            androidEmulatorExecutable ?? _resolveAndroidEmulatorExecutable();
        final adbExecutable =
            androidAdbExecutable ?? _resolveAndroidAdbExecutable();
        if (emulatorExecutable == null || adbExecutable == null) {
          return _failure(
            prepared: prepared,
            skippedConnected: skippedConnected,
            failedLaunchId: launchId,
            detail:
                'Android emulator or adb executable is unavailable. '
                'Configure ANDROID_HOME or ANDROID_SDK_ROOT.',
          );
        }
        var failure = await _startDetached(
          launchId: launchId,
          executable: emulatorExecutable,
          arguments: <String>[
            '-avd',
            launchId,
            '-no-window',
            '-no-audio',
            '-no-boot-anim',
            '-gpu',
            'swiftshader_indirect',
          ],
        );
        failure ??= await _waitForAndroidEmulator(
          launchId,
          adbExecutable: adbExecutable,
        );
        if (failure != null) {
          return _failure(
            prepared: prepared,
            skippedConnected: skippedConnected,
            failedLaunchId: launchId,
            detail: failure,
          );
        }
        prepared.add(launchId);
        continue;
      }

      if (target.isIosSimulator) {
        var failure = await _run(
          launchId: launchId,
          executable: 'xcrun',
          arguments: <String>['simctl', 'boot', launchId],
        );
        failure ??= await _run(
          launchId: launchId,
          executable: 'xcrun',
          arguments: <String>['simctl', 'bootstatus', launchId, '-b'],
        );
        if (failure != null) {
          return _failure(
            prepared: prepared,
            skippedConnected: skippedConnected,
            failedLaunchId: launchId,
            detail: failure,
          );
        }
        prepared.add(launchId);
        continue;
      }

      return _failure(
        prepared: prepared,
        skippedConnected: skippedConnected,
        failedLaunchId: launchId,
        detail:
            'Unsupported preparation target: '
            '${target.platform.name}/${target.kind.name}.',
      );
    }

    return SimsDevicePreparationResult._(
      status: SimsDevicePreparationStatus.success,
      preparedLaunchIds: prepared,
      skippedConnectedRuntimeIds: skippedConnected,
      failedLaunchId: null,
      detail:
          'Preparation commands completed. Rediscovery and resolution are '
          'required before execution.',
    );
  }

  Future<String?> _run({
    required String launchId,
    required String executable,
    required List<String> arguments,
  }) async {
    final command = <String>[executable, ...arguments].join(' ');
    try {
      final output = await commandRunner
          .run(executable, arguments)
          .timeout(commandTimeout);
      if (output.exitCode == 0) return null;
      final outputDetail = output.stderrText.trim().isNotEmpty
          ? output.stderrText
          : output.stdoutText;
      return _boundedDetail(
        '$command failed for $launchId with exit ${output.exitCode}: '
        '$outputDetail',
      );
    } on TimeoutException {
      return _boundedDetail(
        '$command timed out for $launchId after '
        '${commandTimeout.inSeconds}s.',
      );
    } on Object catch (error) {
      return _boundedDetail('$command failed for $launchId: $error');
    }
  }

  Future<String?> _startDetached({
    required String launchId,
    required String executable,
    required List<String> arguments,
  }) async {
    final command = <String>[executable, ...arguments].join(' ');
    try {
      final output = await commandRunner
          .startDetached(executable, arguments)
          .timeout(commandTimeout);
      if (output.exitCode == 0) return null;
      final outputDetail = output.stderrText.trim().isNotEmpty
          ? output.stderrText
          : output.stdoutText;
      return _boundedDetail(
        '$command failed for $launchId with exit ${output.exitCode}: '
        '$outputDetail',
      );
    } on TimeoutException {
      return _boundedDetail(
        '$command timed out for $launchId after '
        '${commandTimeout.inSeconds}s.',
      );
    } on Object catch (error) {
      return _boundedDetail('$command failed for $launchId: $error');
    }
  }

  Future<String?> _waitForAndroidEmulator(
    String launchId, {
    required String adbExecutable,
  }) async {
    final stopwatch = Stopwatch()..start();
    var lastDetail = 'ADB has not reported the requested AVD.';
    while (stopwatch.elapsed < androidReadinessTimeout) {
      final devices = await _readinessCommand(adbExecutable, const <String>[
        'devices',
      ], remaining: androidReadinessTimeout - stopwatch.elapsed);
      if (devices.output == null) {
        lastDetail = devices.detail;
      } else if (devices.output!.exitCode != 0) {
        lastDetail = _commandOutputDetail('adb devices', devices.output!);
      } else {
        final serials = _connectedAndroidEmulatorSerials(
          devices.output!.stdoutText,
        );
        for (final serial in serials) {
          final name = await _readinessCommand(adbExecutable, <String>[
            '-s',
            serial,
            'emu',
            'avd',
            'name',
          ], remaining: androidReadinessTimeout - stopwatch.elapsed);
          if (name.output == null || name.output!.exitCode != 0) {
            lastDetail = name.output == null
                ? name.detail
                : _commandOutputDetail('adb emu avd name', name.output!);
            continue;
          }
          if (_avdName(name.output!.stdoutText) != launchId) continue;

          final boot = await _readinessCommand(adbExecutable, <String>[
            '-s',
            serial,
            'shell',
            'getprop',
            'sys.boot_completed',
          ], remaining: androidReadinessTimeout - stopwatch.elapsed);
          if (boot.output != null &&
              boot.output!.exitCode == 0 &&
              boot.output!.stdoutText.trim() == '1') {
            return null;
          }
          lastDetail = boot.output == null
              ? boot.detail
              : 'AVD $launchId is attached as $serial but Android has not '
                    'finished booting.';
        }
      }

      final remaining = androidReadinessTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) break;
      final delay = androidReadinessPollInterval < remaining
          ? androidReadinessPollInterval
          : remaining;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
    }
    return _boundedDetail(
      'Android emulator $launchId did not become ready within '
      '${androidReadinessTimeout.inSeconds}s. $lastDetail',
    );
  }

  Future<({SimsPreparationCommandOutput? output, String detail})>
  _readinessCommand(
    String executable,
    List<String> arguments, {
    required Duration remaining,
  }) async {
    var timeout = remaining < commandTimeout ? remaining : commandTimeout;
    if (androidReadinessProbeTimeout < timeout) {
      timeout = androidReadinessProbeTimeout;
    }
    final command = <String>[executable, ...arguments].join(' ');
    if (timeout <= Duration.zero) {
      return (output: null, detail: '$command exceeded readiness timeout.');
    }
    try {
      final output = await commandRunner
          .run(executable, arguments)
          .timeout(timeout);
      return (output: output, detail: '');
    } on TimeoutException {
      return (output: null, detail: '$command timed out.');
    } on Object catch (error) {
      return (output: null, detail: '$command failed: $error');
    }
  }

  String? _resolveAndroidEmulatorExecutable() {
    final executableName = Platform.isWindows ? 'emulator.exe' : 'emulator';
    for (final root in _androidSdkRoots()) {
      final candidate = File(
        '$root${Platform.pathSeparator}emulator${Platform.pathSeparator}'
        '$executableName',
      );
      if (candidate.existsSync()) return candidate.path;
    }
    return _resolveExecutable(executableName, environment);
  }

  String? _resolveAndroidAdbExecutable() {
    final executableName = Platform.isWindows ? 'adb.exe' : 'adb';
    for (final root in _androidSdkRoots()) {
      final candidate = File(
        '$root${Platform.pathSeparator}platform-tools${Platform.pathSeparator}'
        '$executableName',
      );
      if (candidate.existsSync()) return candidate.path;
    }
    return _resolveExecutable(executableName, environment);
  }

  Set<String> _androidSdkRoots() {
    final roots = <String>{
      for (final name in const <String>['ANDROID_SDK_ROOT', 'ANDROID_HOME'])
        if ((environment[name]?.trim().isNotEmpty ?? false))
          environment[name]!.trim(),
    };
    final adb = _resolveExecutable('adb', environment);
    if (adb != null) {
      roots.add(File(adb).parent.parent.path);
    }
    return roots;
  }
}

List<String> _connectedAndroidEmulatorSerials(String adbDevicesOutput) =>
    adbDevicesOutput
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where(
          (fields) =>
              fields.length >= 2 &&
              fields.first.startsWith('emulator-') &&
              fields[1] == 'device',
        )
        .map((fields) => fields.first)
        .toList(growable: false);

String? _avdName(String output) {
  for (final line in output.split(RegExp(r'[\r\n]+'))) {
    final value = line.trim();
    if (value.isNotEmpty && value != 'OK') return value;
  }
  return null;
}

String _commandOutputDetail(
  String command,
  SimsPreparationCommandOutput output,
) {
  final detail = output.stderrText.trim().isNotEmpty
      ? output.stderrText
      : output.stdoutText;
  return _boundedDetail('$command exited ${output.exitCode}: $detail');
}

String? _resolveExecutable(String executable, Map<String, String> environment) {
  final path = environment['PATH'];
  if (path == null || path.isEmpty) return null;
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File('$directory${Platform.pathSeparator}$executable');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

SimsDevicePreparationResult _failure({
  required Iterable<String> prepared,
  required Iterable<String> skippedConnected,
  required String? failedLaunchId,
  required String detail,
}) => SimsDevicePreparationResult._(
  status: SimsDevicePreparationStatus.failed,
  preparedLaunchIds: prepared,
  skippedConnectedRuntimeIds: skippedConnected,
  failedLaunchId: failedLaunchId,
  detail: _boundedDetail(detail),
);

String _boundedDetail(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.length <= 300 ? normalized : normalized.substring(0, 300);
}
