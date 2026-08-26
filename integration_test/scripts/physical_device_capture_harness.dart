import 'dart:async';
import 'dart:io';

/// How a plan adapter exposes the shared capture child's output.
enum PhysicalDeviceCaptureOutputMode {
  /// Used by direct developer-facing runners whose child output is the run.
  inheritStdio,

  /// Used by Sims adapters that must reserve stdout for one result marker.
  redirectToStderr,
}

/// Declarative, plan-owned inputs to the shared physical-device capture child.
///
/// The adapter pins routing arguments before accepting plan-specific options,
/// so a caller cannot accidentally replace the selected scenario or devices.
final class PhysicalDeviceCaptureAdapter {
  factory PhysicalDeviceCaptureAdapter({
    required File captureDriver,
    required String scenarioId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required Directory artifactDirectory,
    List<String> additionalArguments = const <String>[],
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) {
    _requireSafeIdentifier(
      value: scenarioId,
      name: 'scenarioId',
      pattern: _safeScenarioId,
    );
    _requireSafeIdentifier(
      value: senderDeviceId,
      name: 'senderDeviceId',
      pattern: _safeDeviceId,
    );
    _requireSafeIdentifier(
      value: recipientDeviceId,
      name: 'recipientDeviceId',
      pattern: _safeDeviceId,
    );
    for (final argument in additionalArguments) {
      if (argument.isEmpty || argument.contains(RegExp(r'[\r\n\x00]'))) {
        throw ArgumentError.value(
          argument,
          'additionalArguments',
          'arguments must be non-empty single-line values',
        );
      }
      final option = argument.split('=').first;
      if (_pinnedRoutingOptions.contains(option)) {
        throw ArgumentError.value(
          argument,
          'additionalArguments',
          '$option is owned by the physical-device harness',
        );
      }
    }
    return PhysicalDeviceCaptureAdapter._(
      captureDriver: captureDriver.absolute,
      scenarioId: scenarioId,
      senderDeviceId: senderDeviceId,
      recipientDeviceId: recipientDeviceId,
      artifactDirectory: artifactDirectory,
      additionalArguments: List<String>.unmodifiable(additionalArguments),
      environment: environment == null
          ? null
          : Map<String, String>.unmodifiable(environment),
      includeParentEnvironment: includeParentEnvironment,
    );
  }

  const PhysicalDeviceCaptureAdapter._({
    required this.captureDriver,
    required this.scenarioId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.artifactDirectory,
    required this.additionalArguments,
    required this.environment,
    required this.includeParentEnvironment,
  });

  static final RegExp _safeScenarioId = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _safeDeviceId = RegExp(r'^[A-Za-z0-9._:-]{4,128}$');
  static const Set<String> _pinnedRoutingOptions = <String>{
    '--scenario',
    '--sender',
    '--recipient',
    '--artifact-dir',
  };

  final File captureDriver;
  final String scenarioId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final Directory artifactDirectory;
  final List<String> additionalArguments;
  final Map<String, String>? environment;
  final bool includeParentEnvironment;

  List<String> get processArguments => <String>[
    'run',
    captureDriver.path,
    '--scenario',
    scenarioId,
    '--sender',
    senderDeviceId,
    '--recipient',
    recipientDeviceId,
    '--artifact-dir',
    artifactDirectory.path,
    ...additionalArguments,
  ];
}

/// Outcome of launching the shared capture child.
///
/// A launch failure is data rather than an exception so each plan adapter can
/// retain its own blocker vocabulary and verdict schema.
final class PhysicalDeviceCaptureRun {
  const PhysicalDeviceCaptureRun._({this.exitCode, this.launchError});

  factory PhysicalDeviceCaptureRun.exited(int exitCode) =>
      PhysicalDeviceCaptureRun._(exitCode: exitCode);

  factory PhysicalDeviceCaptureRun.launchFailed(ProcessException error) =>
      PhysicalDeviceCaptureRun._(launchError: error);

  final int? exitCode;
  final ProcessException? launchError;

  bool get launched => launchError == null;
}

/// Runs one plan adapter through the shared capture process boundary.
Future<PhysicalDeviceCaptureRun> runPhysicalDeviceCapture(
  PhysicalDeviceCaptureAdapter adapter, {
  PhysicalDeviceCaptureOutputMode outputMode =
      PhysicalDeviceCaptureOutputMode.redirectToStderr,
  IOSink? redirectedOutput,
  String? executable,
}) async {
  try {
    if (outputMode == PhysicalDeviceCaptureOutputMode.inheritStdio) {
      final child = await Process.start(
        executable ?? Platform.resolvedExecutable,
        adapter.processArguments,
        mode: ProcessStartMode.inheritStdio,
        environment: adapter.environment,
        includeParentEnvironment: adapter.includeParentEnvironment,
      );
      return PhysicalDeviceCaptureRun.exited(await child.exitCode);
    }

    final child = await Process.start(
      executable ?? Platform.resolvedExecutable,
      adapter.processArguments,
      environment: adapter.environment,
      includeParentEnvironment: adapter.includeParentEnvironment,
    );
    final output = redirectedOutput ?? stderr;
    final stdoutDone = child.stdout.listen(output.add).asFuture<void>();
    final stderrDone = child.stderr.listen(output.add).asFuture<void>();
    final exitCode = await child.exitCode;
    await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
    return PhysicalDeviceCaptureRun.exited(exitCode);
  } on ProcessException catch (error) {
    return PhysicalDeviceCaptureRun.launchFailed(error);
  }
}

/// Removes every authoritative/failure layout a prior scenario run can leave.
void purgePhysicalDeviceCaptureArtifacts(
  Directory artifactDirectory,
  String scenarioId,
) {
  _requireSafeIdentifier(
    value: scenarioId,
    name: 'scenarioId',
    pattern: PhysicalDeviceCaptureAdapter._safeScenarioId,
  );
  final nested =
      '${artifactDirectory.path}${Platform.pathSeparator}$scenarioId';
  for (final path in <String>[
    '${artifactDirectory.path}${Platform.pathSeparator}$scenarioId.json',
    '${artifactDirectory.path}${Platform.pathSeparator}'
        '${scenarioId}_capture_failure.json',
    '$nested${Platform.pathSeparator}$scenarioId.json',
    '$nested${Platform.pathSeparator}${scenarioId}_capture_failure.json',
  ]) {
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.file) {
      File(path).deleteSync();
    }
  }
}

/// Resolves the two supported authoritative artifact layouts.
File physicalDeviceCaptureArtifact(
  Directory artifactDirectory,
  String scenarioId,
) {
  _requireSafeIdentifier(
    value: scenarioId,
    name: 'scenarioId',
    pattern: PhysicalDeviceCaptureAdapter._safeScenarioId,
  );
  final direct = File(
    '${artifactDirectory.path}${Platform.pathSeparator}$scenarioId.json',
  );
  if (direct.existsSync()) return direct;
  return File(
    '${artifactDirectory.path}${Platform.pathSeparator}$scenarioId'
    '${Platform.pathSeparator}$scenarioId.json',
  );
}

void _requireSafeIdentifier({
  required String value,
  required String name,
  required RegExp pattern,
}) {
  if (!pattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'unsafe physical harness value');
  }
}
