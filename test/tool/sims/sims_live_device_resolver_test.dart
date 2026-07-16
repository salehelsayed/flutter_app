import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/live_device_resolver.dart';
import '../../../tool/sims/manifest.dart';

const _flutterDevices = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'iPhone USB',
    'id': 'iphone-usb',
    'targetPlatform': 'ios',
    'emulator': false,
    'isSupported': true,
  },
  <String, Object?>{
    'name': 'Android USB',
    'id': 'android-usb',
    'targetPlatform': 'android-arm64',
    'emulator': false,
    'isSupported': true,
    'connectionInterface': 'usb',
  },
  <String, Object?>{
    'name': 'Android Emulator',
    'id': 'emulator-5554',
    'targetPlatform': 'android-x64',
    'emulator': true,
    'isSupported': true,
  },
  <String, Object?>{
    'name': 'Wireless Android',
    'id': '192.0.2.1:5555',
    'targetPlatform': 'android-arm64',
    'emulator': false,
    'isSupported': true,
    'connectionInterface': 'wireless',
  },
  <String, Object?>{
    'name': 'Booted iOS Simulator',
    'id': 'ios-sim-a',
    'targetPlatform': 'ios',
    'emulator': true,
    'isSupported': true,
  },
];

const _adbDevices = '''List of devices attached
android-usb device usb:1-1 product:oriole model:Android_USB transport_id:1
emulator-5554 device product:sdk_phone model:Android_Emulator transport_id:2
192.0.2.1:5555 device product:oriole model:Wireless_Android transport_id:3
offline-device offline transport_id:4
''';

Map<String, Object?> get _simctlDevices => <String, Object?>{
  'devices': <String, Object?>{
    'com.apple.CoreSimulator.SimRuntime.iOS-current': <Object?>[
      <String, Object?>{
        'name': 'Booted iOS Simulator',
        'udid': 'ios-sim-a',
        'state': 'Booted',
        'isAvailable': true,
      },
      <String, Object?>{
        'name': 'Available iOS Simulator',
        'udid': 'ios-sim-b',
        'state': 'Shutdown',
        'isAvailable': true,
      },
      <String, Object?>{
        'name': 'Unavailable iOS Simulator',
        'udid': 'ios-sim-unavailable',
        'state': 'Shutdown',
        'isAvailable': false,
      },
    ],
  },
};

const _flutterEmulators = <Map<String, Object?>>[
  <String, Object?>{
    'id': 'launchable-avd',
    'name': 'Launchable Android Emulator',
    'platformType': 'android',
  },
  <String, Object?>{
    'id': 'ios-launcher',
    'name': 'iOS Simulator Launcher',
    'platformType': 'ios',
  },
];

const _flutterEmulatorList = '''3 available emulators:

Id                  • Name                        • Manufacturer • Platform
apple_ios_simulator • iOS Simulator               • Apple        • ios
launchable-avd      • Launchable Android Emulator • Vendor       • android
''';

void main() {
  group('live discovery', () {
    test('combines Flutter, adb, and simctl without booting a target', () async {
      final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
        'flutter devices --machine --device-connection=attached': _ok(
          'Waiting for the Flutter startup lock...\n${jsonEncode(_flutterDevices)}',
        ),
        'adb devices -l': _ok(_adbDevices),
        'xcrun simctl list devices available -j': _ok(
          jsonEncode(_simctlDevices),
        ),
        'flutter emulators': _ok(_flutterEmulatorList),
        'adb -s emulator-5554 emu avd name': _ok('running-avd\nOK\n'),
      });

      final inventory = await SimsLiveDeviceDiscovery(
        commandRunner: runner,
        isMacOS: true,
      ).discover(listOnly: true);

      expect(runner.invocations, <String>[
        'flutter devices --machine --device-connection=attached',
        'adb devices -l',
        'xcrun simctl list devices available -j',
        'flutter emulators',
        'adb -s emulator-5554 emu avd name',
      ]);
      expect(
        runner.invocations.where(
          (command) => command.contains('boot') || command.contains('launch'),
        ),
        isEmpty,
      );
      expect(inventory.byRuntimeId('android-usb')?.isPhysical, isTrue);
      expect(inventory.byRuntimeId('emulator-5554')?.isAndroidEmulator, isTrue);
      expect(inventory.byRuntimeId('emulator-5554')?.launchId, 'running-avd');
      expect(inventory.byRuntimeId('iphone-usb')?.isPhysical, isTrue);
      expect(inventory.byRuntimeId('ios-sim-a')?.isIosSimulator, isTrue);
      expect(inventory.byLaunchId('ios-sim-b')?.requiresLaunch, isTrue);
      expect(inventory.byLaunchId('launchable-avd')?.requiresLaunch, isTrue);
      expect(inventory.byRuntimeId('192.0.2.1:5555'), isNull);
      expect(inventory.byRuntimeId('offline-device'), isNull);
      expect(inventory.byLaunchId('ios-launcher'), isNull);
    });

    test('running AVD is merged with its launchable catalog entry', () async {
      final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
        'flutter devices --machine --device-connection=attached': _ok(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'name': 'Running emulator',
              'id': 'emulator-5554',
              'targetPlatform': 'android-arm64',
              'emulator': true,
              'isSupported': true,
            },
          ]),
        ),
        'adb devices -l': _ok(
          'List of devices attached\n'
          'emulator-5554 device product:sdk model:emu transport_id:1\n',
        ),
        'xcrun simctl list devices available -j': _ok(
          jsonEncode(<String, Object?>{'devices': <String, Object?>{}}),
        ),
        'flutter emulators': _ok(
          _emulatorList(const <Map<String, Object?>>[
            <String, Object?>{
              'id': 'running-avd',
              'name': 'Running AVD',
              'platformType': 'android',
            },
            <String, Object?>{
              'id': 'spare-avd',
              'name': 'Spare AVD',
              'platformType': 'android',
            },
          ]),
        ),
        'adb -s emulator-5554 emu avd name': _ok('running-avd\nOK\n'),
      });

      final inventory = await SimsLiveDeviceDiscovery(
        commandRunner: runner,
        isMacOS: true,
      ).discover();
      final androidEmulators = inventory.targets
          .where((target) => target.isAndroidEmulator)
          .toList(growable: false);

      expect(androidEmulators, hasLength(2));
      expect(inventory.byLaunchId('running-avd')?.runtimeId, 'emulator-5554');
      expect(inventory.byLaunchId('spare-avd')?.requiresLaunch, isTrue);
      final resolution = SimsLiveDeviceResolver(inventory).resolveResourceNames(
        const <String>[
          'device:android-emulator',
          'device:android-emulator-second',
        ],
      );
      expect(resolution.status, SimsDeviceResolutionStatus.preparationRequired);
      expect(resolution.preparationTargets.single.launchId, 'spare-avd');
    });

    test('unmapped running AVD fails closed for a second emulator', () async {
      final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
        'flutter devices --machine --device-connection=attached': _ok(
          jsonEncode(<Map<String, Object?>>[
            <String, Object?>{
              'name': 'Running emulator',
              'id': 'emulator-5554',
              'targetPlatform': 'android-arm64',
              'emulator': true,
              'isSupported': true,
            },
          ]),
        ),
        'adb devices -l': _ok(
          'List of devices attached\n'
          'emulator-5554 device product:sdk model:emu transport_id:1\n',
        ),
        'xcrun simctl list devices available -j': _ok(
          jsonEncode(<String, Object?>{'devices': <String, Object?>{}}),
        ),
        'flutter emulators': _ok(
          _emulatorList(const <Map<String, Object?>>[
            <String, Object?>{
              'id': 'unknown-running-or-spare',
              'name': 'Ambiguous AVD',
              'platformType': 'android',
            },
          ]),
        ),
        'adb -s emulator-5554 emu avd name': const SimsDiscoveryCommandOutput(
          exitCode: 1,
          stdoutText: '',
          stderrText: 'unsupported',
        ),
        'adb -s emulator-5554 shell getprop ro.boot.qemu.avd_name': _ok(''),
      });

      final inventory = await SimsLiveDeviceDiscovery(
        commandRunner: runner,
        isMacOS: true,
      ).discover();
      final resolution = SimsLiveDeviceResolver(inventory).resolveResourceNames(
        const <String>[
          'device:android-emulator',
          'device:android-emulator-second',
        ],
      );

      expect(
        inventory.notReadyTargetClasses,
        contains(SimsLiveDeviceClass.androidEmulator),
      );
      expect(
        inventory.targets.where((target) => target.isAndroidEmulator),
        hasLength(1),
      );
      expect(resolution.status, SimsDeviceResolutionStatus.preparationRequired);
      expect(resolution.preparationTargets, isEmpty);
    });

    test('does not invoke simctl when iOS discovery is inapplicable', () async {
      final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
        'flutter devices --machine --device-connection=attached': _ok('[]'),
        'adb devices -l': _ok('List of devices attached\n'),
        'flutter emulators': _ok('0 available emulators:\n'),
      });

      final inventory = await SimsLiveDeviceDiscovery(
        commandRunner: runner,
        isMacOS: false,
      ).discover();

      expect(
        runner.invocations,
        isNot(contains('xcrun simctl list devices available -j')),
      );
      expect(
        inventory.sourceStatus(SimsDeviceDiscoverySource.simctl),
        SimsDiscoveryStatus.notApplicable,
      );
    });
  });

  group('symbolic resource resolution', () {
    test(
      'generic two-peer locks choose physical Android plus Android emulator',
      () async {
        final inventory = await _inventory();
        final resolution = SimsLiveDeviceResolver(inventory)
            .resolveLocks(const <ResourceLock>[
              ResourceLock(
                name: 'device:android-physical',
                access: ResourceAccess.exclusive,
              ),
              ResourceLock(
                name: 'device:android-emulator',
                access: ResourceAccess.exclusive,
              ),
              ResourceLock(
                name: 'device-control:android-emulator',
                access: ResourceAccess.exclusive,
              ),
            ]);

        expect(resolution.status, SimsDeviceResolutionStatus.resolved);
        expect(resolution.policyNaEligible, isFalse);
        expect(
          resolution.deviceIdFor('device:android-physical'),
          'android-usb',
        );
        expect(
          resolution.deviceIdFor('device:android-emulator'),
          'emulator-5554',
        );
        expect(
          resolution.deviceIdFor('device-control:android-emulator'),
          'emulator-5554',
        );
        expect(resolution.assignments.values, isNot(contains('iphone-usb')));
        expect(
          resolution.environment['RELIABILITY_MULTI_DEVICE_IDS'],
          'android-usb,emulator-5554',
        );
        expect(
          resolution.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID'],
          'android-usb',
        );
        expect(
          resolution.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'],
          'emulator-5554',
        );
        expect(
          jsonDecode(resolution.environment['SIMS_DEVICE_ASSIGNMENTS_JSON']!),
          resolution.assignments,
        );
      },
    );

    test(
      'three-party Android locks choose one physical and two emulators',
      () async {
        final inventory = await _inventory(
          flutterDevices: <Map<String, Object?>>[
            ..._flutterDevices,
            <String, Object?>{
              'name': 'Second Android Emulator',
              'id': 'emulator-5556',
              'targetPlatform': 'android-x64',
              'emulator': true,
              'isSupported': true,
            },
          ],
          adbDevices:
              '$_adbDevices'
              'emulator-5556 device product:sdk_phone '
              'model:Second_Android_Emulator transport_id:5\n',
        );
        final resolution = SimsLiveDeviceResolver(inventory)
            .resolveResourceNames(const <String>[
              'device:android-physical',
              'device:android-emulator',
              'device:android-emulator-second',
            ]);

        expect(resolution.status, SimsDeviceResolutionStatus.resolved);
        expect(
          resolution.deviceIdFor('device:android-physical'),
          'android-usb',
        );
        expect(
          resolution.deviceIdFor('device:android-emulator'),
          'emulator-5554',
        );
        expect(
          resolution.deviceIdFor('device:android-emulator-second'),
          'emulator-5556',
        );
        expect(
          resolution.environment['SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID'],
          'emulator-5556',
        );
        expect(
          resolution.environment['SIMS_ANDROID_EMULATOR_DEVICE_IDS'],
          'emulator-5554,emulator-5556',
        );
        expect(resolution.assignments.values.toSet(), hasLength(3));
      },
    );

    test(
      'four iOS simulator locks receive distinct deterministic assignments',
      () async {
        final inventory = await _inventory(
          simctlDevices: <String, Object?>{
            'devices': <String, Object?>{
              'runtime': <Object?>[
                <String, Object?>{
                  'name': 'Simulator D',
                  'udid': 'ios-sim-d',
                  'state': 'Booted',
                  'isAvailable': true,
                },
                <String, Object?>{
                  'name': 'Simulator B',
                  'udid': 'ios-sim-b',
                  'state': 'Booted',
                  'isAvailable': true,
                },
                <String, Object?>{
                  'name': 'Simulator A',
                  'udid': 'ios-sim-a',
                  'state': 'Booted',
                  'isAvailable': true,
                },
                <String, Object?>{
                  'name': 'Simulator C',
                  'udid': 'ios-sim-c',
                  'state': 'Booted',
                  'isAvailable': true,
                },
              ],
            },
          },
        );

        final resolution = SimsLiveDeviceResolver(inventory)
            .resolveResourceNames(const <String>[
              'device:ios-simulator-d',
              'device:ios-simulator-b',
              'device:ios-simulator-a',
              'device:ios-simulator-c',
            ]);

        expect(resolution.status, SimsDeviceResolutionStatus.resolved);
        expect(resolution.deviceIdFor('device:ios-simulator-a'), 'ios-sim-a');
        expect(resolution.deviceIdFor('device:ios-simulator-b'), 'ios-sim-b');
        expect(resolution.deviceIdFor('device:ios-simulator-c'), 'ios-sim-c');
        expect(resolution.deviceIdFor('device:ios-simulator-d'), 'ios-sim-d');
        expect(
          resolution.environment['IOS_SECONDARY_SIMULATOR_DEVICE'],
          'ios-sim-b',
        );
        expect(
          resolution.environment['SIMS_IOS_SIMULATOR_C_DEVICE_ID'],
          'ios-sim-c',
        );
        expect(
          resolution.environment['SIMS_IOS_SIMULATOR_D_DEVICE_ID'],
          'ios-sim-d',
        );
        expect(resolution.assignments.values.toSet().length, 4);
      },
    );

    test(
      'launchable but stopped target requires preparation, not N/A',
      () async {
        final inventory = await _inventory(
          flutterDevices: _flutterDevices
              .where((device) => device['id'] != 'emulator-5554')
              .toList(),
          adbDevices:
              'List of devices attached\n'
              'android-usb device usb:1-1 model:Android_USB transport_id:1\n',
        );

        final resolution = SimsLiveDeviceResolver(
          inventory,
        ).resolveResourceNames(const <String>['device:android-emulator']);

        expect(
          resolution.status,
          SimsDeviceResolutionStatus.preparationRequired,
        );
        expect(resolution.policyNaEligible, isFalse);
        expect(resolution.preparationTargets.single.launchId, 'launchable-avd');
        expect(resolution.assignments, isEmpty);
      },
    );

    test('confirmed absent target is the only policy N/A condition', () async {
      final inventory = await _inventory(
        flutterDevices: const <Map<String, Object?>>[],
        adbDevices: 'List of devices attached\n',
        flutterEmulators: const <Map<String, Object?>>[],
      );
      final resolver = SimsLiveDeviceResolver(inventory);

      final absent = resolver.resolveResourceNames(const <String>[
        'device:android-physical',
      ]);
      expect(absent.status, SimsDeviceResolutionStatus.targetUnavailable);
      expect(absent.policyNaEligible, isTrue);
      expect(absent.naReason, targetUnavailableNaReason);

      final nonDevice = resolver.resolveResourceNames(const <String>[
        'credentials.fcm',
        'driver:notification-campaign',
        'artifact:notification-a6',
      ]);
      expect(nonDevice.status, SimsDeviceResolutionStatus.resolved);
      expect(nonDevice.policyNaEligible, isFalse);
      expect(nonDevice.assignments, isEmpty);
    });

    test(
      'failed discovery is a blocker and cannot become policy N/A',
      () async {
        final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
          'flutter devices --machine --device-connection=attached': _ok('[]'),
          'adb devices -l': const SimsDiscoveryCommandOutput(
            exitCode: 1,
            stdoutText: '',
            stderrText: 'adb server unavailable',
          ),
          'xcrun simctl list devices available -j': _ok(
            jsonEncode(<String, Object?>{'devices': <String, Object?>{}}),
          ),
          'flutter emulators': _ok('0 available emulators:\n'),
        });
        final inventory = await SimsLiveDeviceDiscovery(
          commandRunner: runner,
          isMacOS: true,
        ).discover();

        final resolution = SimsLiveDeviceResolver(
          inventory,
        ).resolveResourceNames(const <String>['device:android-physical']);

        expect(resolution.status, SimsDeviceResolutionStatus.discoveryFailed);
        expect(resolution.policyNaEligible, isFalse);
        expect(resolution.detail, contains('adb'));
      },
    );

    test('attached but unauthorized Android is not policy N/A', () async {
      final runner = _FakeRunner(<String, SimsDiscoveryCommandOutput>{
        'flutter devices --machine --device-connection=attached': _ok('[]'),
        'adb devices -l': _ok(
          'List of devices attached\n'
          'android-usb unauthorized usb:1-1 transport_id:1\n',
        ),
        'xcrun simctl list devices available -j': _ok(
          jsonEncode(<String, Object?>{'devices': <String, Object?>{}}),
        ),
        'flutter emulators': _ok('0 available emulators:\n'),
      });
      final inventory = await SimsLiveDeviceDiscovery(
        commandRunner: runner,
        isMacOS: true,
      ).discover();

      final resolution = SimsLiveDeviceResolver(
        inventory,
      ).resolveResourceNames(const <String>['device:android-physical']);

      expect(
        inventory.notReadyTargetClasses,
        contains(SimsLiveDeviceClass.androidPhysical),
      );
      expect(resolution.status, SimsDeviceResolutionStatus.preparationRequired);
      expect(resolution.policyNaEligible, isFalse);
    });

    test(
      'unknown symbolic device roles fail closed as harness configuration',
      () async {
        final resolution = SimsLiveDeviceResolver(
          await _inventory(),
        ).resolveResourceNames(const <String>['device:android-tablet-lab']);

        expect(resolution.status, SimsDeviceResolutionStatus.invalidResource);
        expect(resolution.policyNaEligible, isFalse);
      },
    );
  });
}

Future<SimsLiveDeviceInventory> _inventory({
  List<Map<String, Object?>> flutterDevices = _flutterDevices,
  String adbDevices = _adbDevices,
  Map<String, Object?>? simctlDevices,
  List<Map<String, Object?>> flutterEmulators = _flutterEmulators,
}) => SimsLiveDeviceDiscovery(
  commandRunner: _FakeRunner(<String, SimsDiscoveryCommandOutput>{
    'flutter devices --machine --device-connection=attached': _ok(
      jsonEncode(flutterDevices),
    ),
    'adb devices -l': _ok(adbDevices),
    'xcrun simctl list devices available -j': _ok(
      jsonEncode(simctlDevices ?? _simctlDevices),
    ),
    'flutter emulators': _ok(_emulatorList(flutterEmulators)),
    'adb -s emulator-5554 emu avd name': _ok('running-avd\nOK\n'),
    'adb -s emulator-5556 emu avd name': _ok('second-running-avd\nOK\n'),
  }),
  isMacOS: true,
).discover();

String _emulatorList(List<Map<String, Object?>> emulators) => <String>[
  '${emulators.length} available emulators:',
  'Id • Name • Manufacturer • Platform',
  for (final emulator in emulators)
    '${emulator['id']} • ${emulator['name']} • Vendor • '
        '${emulator['platformType']}',
].join('\n');

SimsDiscoveryCommandOutput _ok(String stdoutText) => SimsDiscoveryCommandOutput(
  exitCode: 0,
  stdoutText: stdoutText,
  stderrText: '',
);

final class _FakeRunner implements SimsDiscoveryCommandRunner {
  _FakeRunner(this.outputs);

  final Map<String, SimsDiscoveryCommandOutput> outputs;
  final List<String> invocations = <String>[];

  @override
  Future<SimsDiscoveryCommandOutput> run(
    String executable,
    List<String> arguments,
  ) async {
    final command = <String>[executable, ...arguments].join(' ');
    invocations.add(command);
    final output = outputs[command];
    if (output == null) {
      throw StateError('Unexpected discovery command: $command');
    }
    return output;
  }
}
