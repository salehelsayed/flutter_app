import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/live_device_preparer.dart';
import '../../../tool/sims/live_device_resolver.dart';

void main() {
  test('launches an Android AVD with its explicit launch ID', () async {
    final runner = _FakePreparationRunner(<String, Object>{
      'DETACHED /sdk/emulator -avd avd-a -no-window -no-audio '
              '-no-boot-anim -gpu swiftshader_indirect':
          _ok(),
      'adb devices': _ok(
        stdoutText: 'List of devices attached\nemulator-5554\tdevice\n',
      ),
      'adb -s emulator-5554 emu avd name': _ok(stdoutText: 'avd-a\nOK\n'),
      'adb -s emulator-5554 shell getprop sys.boot_completed': _ok(
        stdoutText: '1\n',
      ),
    });

    final result =
        await SimsLiveDevicePreparer(
          commandRunner: runner,
          androidEmulatorExecutable: '/sdk/emulator',
          androidAdbExecutable: 'adb',
          androidReadinessPollInterval: Duration.zero,
        ).prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            launchId: 'avd-a',
          ),
        ]);

    expect(result.succeeded, isTrue);
    expect(result.preparedLaunchIds, <String>['avd-a']);
    expect(runner.invocations, <String>[
      'DETACHED /sdk/emulator -avd avd-a -no-window -no-audio '
          '-no-boot-anim -gpu swiftshader_indirect',
      'adb devices',
      'adb -s emulator-5554 emu avd name',
      'adb -s emulator-5554 shell getprop sys.boot_completed',
    ]);
  });

  test('resolves emulator and adb from Android SDK without PATH', () async {
    final sdk = Directory.systemTemp.createTempSync('sims-android-sdk-');
    addTearDown(() => sdk.deleteSync(recursive: true));
    final emulator = File(
      '${sdk.path}${Platform.pathSeparator}emulator${Platform.pathSeparator}emulator',
    )..createSync(recursive: true);
    final adb = File(
      '${sdk.path}${Platform.pathSeparator}platform-tools${Platform.pathSeparator}adb',
    )..createSync(recursive: true);
    final runner = _FakePreparationRunner(<String, Object>{
      'DETACHED ${emulator.path} -avd avd-a -no-window -no-audio '
              '-no-boot-anim -gpu swiftshader_indirect':
          _ok(),
      '${adb.path} devices': _ok(
        stdoutText: 'List of devices attached\nemulator-5554\tdevice\n',
      ),
      '${adb.path} -s emulator-5554 emu avd name': _ok(
        stdoutText: 'avd-a\nOK\n',
      ),
      '${adb.path} -s emulator-5554 shell getprop sys.boot_completed': _ok(
        stdoutText: '1\n',
      ),
    });

    final result =
        await SimsLiveDevicePreparer(
          commandRunner: runner,
          environment: <String, String>{'ANDROID_HOME': sdk.path},
          androidReadinessPollInterval: Duration.zero,
        ).prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            launchId: 'avd-a',
          ),
        ]);

    expect(result.succeeded, isTrue);
    expect(runner.invocations, contains('${adb.path} devices'));
  });

  test('boots an iOS simulator and waits for bootstatus', () async {
    final runner = _FakePreparationRunner(<String, Object>{
      'xcrun simctl boot ios-sim-a': _ok(),
      'xcrun simctl bootstatus ios-sim-a -b': _ok(),
    });

    final result = await SimsLiveDevicePreparer(commandRunner: runner)
        .prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.ios,
            kind: SimsLiveDeviceKind.simulator,
            launchId: 'ios-sim-a',
          ),
        ]);

    expect(result.succeeded, isTrue);
    expect(result.preparedLaunchIds, <String>['ios-sim-a']);
    expect(runner.invocations, <String>[
      'xcrun simctl boot ios-sim-a',
      'xcrun simctl bootstatus ios-sim-a -b',
    ]);
  });

  test('never runs a command for connected targets', () async {
    final runner = _FakePreparationRunner(const <String, Object>{});

    final result = await SimsLiveDevicePreparer(commandRunner: runner)
        .prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            availability: SimsLiveDeviceAvailability.connected,
            runtimeId: 'emulator-5554',
            launchId: 'avd-a',
          ),
          _target(
            platform: SimsLiveDevicePlatform.ios,
            kind: SimsLiveDeviceKind.simulator,
            availability: SimsLiveDeviceAvailability.connected,
            runtimeId: 'ios-sim-a',
            launchId: 'ios-sim-a',
          ),
        ]);

    expect(result.succeeded, isTrue);
    expect(result.preparedLaunchIds, isEmpty);
    expect(result.skippedConnectedRuntimeIds, <String>[
      'emulator-5554',
      'ios-sim-a',
    ]);
    expect(runner.invocations, isEmpty);
  });

  test('deduplicates repeated preparation targets', () async {
    final runner = _FakePreparationRunner(<String, Object>{
      'xcrun simctl boot ios-sim-a': _ok(),
      'xcrun simctl bootstatus ios-sim-a -b': _ok(),
    });
    final target = _target(
      platform: SimsLiveDevicePlatform.ios,
      kind: SimsLiveDeviceKind.simulator,
      launchId: 'ios-sim-a',
    );

    final result = await SimsLiveDevicePreparer(
      commandRunner: runner,
    ).prepare(<SimsLiveDeviceTarget>[target, target]);

    expect(result.succeeded, isTrue);
    expect(result.preparedLaunchIds, <String>['ios-sim-a']);
    expect(runner.invocations, hasLength(2));
  });

  test('a launch failure stops immediately with bounded detail', () async {
    final runner = _FakePreparationRunner(<String, Object>{
      'xcrun simctl boot ios-sim-a': SimsPreparationCommandOutput(
        exitCode: 7,
        stdoutText: '',
        stderrText: '  ${'failure '.padRight(500, 'x')}  ',
      ),
    });

    final result = await SimsLiveDevicePreparer(commandRunner: runner)
        .prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.ios,
            kind: SimsLiveDeviceKind.simulator,
            launchId: 'ios-sim-a',
          ),
          _target(
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            launchId: 'avd-later',
          ),
        ]);

    expect(result.succeeded, isFalse);
    expect(result.failedLaunchId, 'ios-sim-a');
    expect(result.detail.length, lessThanOrEqualTo(300));
    expect(result.detail, contains('failure'));
    expect(runner.invocations, <String>['xcrun simctl boot ios-sim-a']);
  });

  test(
    'bootstatus failure is terminal and does not claim preparation',
    () async {
      final runner = _FakePreparationRunner(<String, Object>{
        'xcrun simctl boot ios-sim-a': _ok(),
        'xcrun simctl bootstatus ios-sim-a -b':
            const SimsPreparationCommandOutput(
              exitCode: 1,
              stdoutText: '',
              stderrText: 'boot did not become ready',
            ),
      });

      final result = await SimsLiveDevicePreparer(commandRunner: runner)
          .prepare(<SimsLiveDeviceTarget>[
            _target(
              platform: SimsLiveDevicePlatform.ios,
              kind: SimsLiveDeviceKind.simulator,
              launchId: 'ios-sim-a',
            ),
          ]);

      expect(result.succeeded, isFalse);
      expect(result.preparedLaunchIds, isEmpty);
      expect(result.failedLaunchId, 'ios-sim-a');
      expect(result.detail, contains('boot did not become ready'));
    },
  );

  test('runner exceptions fail closed with bounded detail', () async {
    final runner = _FakePreparationRunner(<String, Object>{
      'DETACHED /sdk/emulator -avd avd-a -no-window -no-audio '
          '-no-boot-anim -gpu swiftshader_indirect': StateError(
        'x'.padRight(500, 'x'),
      ),
    });

    final result =
        await SimsLiveDevicePreparer(
          commandRunner: runner,
          androidEmulatorExecutable: '/sdk/emulator',
          androidAdbExecutable: 'adb',
        ).prepare(<SimsLiveDeviceTarget>[
          _target(
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            launchId: 'avd-a',
          ),
        ]);

    expect(result.succeeded, isFalse);
    expect(result.detail.length, lessThanOrEqualTo(300));
    expect(result.failedLaunchId, 'avd-a');
  });

  test(
    'malformed or unsupported preparation targets fail without mutation',
    () async {
      final runner = _FakePreparationRunner(const <String, Object>{});

      final missingId = await SimsLiveDevicePreparer(commandRunner: runner)
          .prepare(<SimsLiveDeviceTarget>[
            _target(
              platform: SimsLiveDevicePlatform.android,
              kind: SimsLiveDeviceKind.emulator,
            ),
          ]);
      expect(missingId.succeeded, isFalse);

      final physical = await SimsLiveDevicePreparer(commandRunner: runner)
          .prepare(<SimsLiveDeviceTarget>[
            _target(
              platform: SimsLiveDevicePlatform.android,
              kind: SimsLiveDeviceKind.physical,
              launchId: 'physical-id',
            ),
          ]);
      expect(physical.succeeded, isFalse);
      expect(runner.invocations, isEmpty);
    },
  );
}

SimsLiveDeviceTarget _target({
  required SimsLiveDevicePlatform platform,
  required SimsLiveDeviceKind kind,
  SimsLiveDeviceAvailability availability =
      SimsLiveDeviceAvailability.launchable,
  String? runtimeId,
  String? launchId,
}) => SimsLiveDeviceTarget(
  name: launchId ?? runtimeId ?? 'target',
  platform: platform,
  kind: kind,
  availability: availability,
  runtimeId: runtimeId,
  launchId: launchId,
  sources: const <SimsDeviceDiscoverySource>{},
);

SimsPreparationCommandOutput _ok({
  String stdoutText = '',
  String stderrText = '',
}) => SimsPreparationCommandOutput(
  exitCode: 0,
  stdoutText: stdoutText,
  stderrText: stderrText,
);

final class _FakePreparationRunner
    implements SimsDevicePreparationCommandRunner {
  _FakePreparationRunner(this.outcomes);

  final Map<String, Object> outcomes;
  final List<String> invocations = <String>[];

  @override
  Future<SimsPreparationCommandOutput> run(
    String executable,
    List<String> arguments,
  ) async {
    final command = <String>[executable, ...arguments].join(' ');
    invocations.add(command);
    final outcome = outcomes[command];
    if (outcome is SimsPreparationCommandOutput) return outcome;
    if (outcome is Object) throw outcome;
    throw StateError('Unexpected preparation command: $command');
  }

  @override
  Future<SimsPreparationCommandOutput> startDetached(
    String executable,
    List<String> arguments,
  ) => _outcome('DETACHED $executable ${arguments.join(' ')}');

  Future<SimsPreparationCommandOutput> _outcome(String command) async {
    invocations.add(command);
    final outcome = outcomes[command];
    if (outcome is SimsPreparationCommandOutput) return outcome;
    if (outcome is Object) throw outcome;
    throw StateError('Unexpected preparation command: $command');
  }
}
