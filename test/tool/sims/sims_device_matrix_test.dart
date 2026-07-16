import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/device_matrix.dart';

const devices = <SimsDevice>[
  SimsDevice(
    id: 'pixel-usb',
    name: 'Pixel',
    platform: SimsDevicePlatform.android,
    kind: SimsDeviceKind.physical,
  ),
  SimsDevice(
    id: 'emulator-5554',
    name: 'Android Emulator',
    platform: SimsDevicePlatform.android,
    kind: SimsDeviceKind.emulator,
  ),
  SimsDevice(
    id: 'ios-sim-1',
    name: 'iPhone Simulator',
    platform: SimsDevicePlatform.ios,
    kind: SimsDeviceKind.simulator,
  ),
  SimsDevice(
    id: 'iphone-usb',
    name: 'iPhone',
    platform: SimsDevicePlatform.ios,
    kind: SimsDeviceKind.physical,
  ),
];

void main() {
  test(
    'non-iOS two-peer work prefers physical Android plus emulator and pins IDs',
    () {
      final selected = SimsDeviceMatrix(
        devices,
      ).select(const SimsTargetRequirement(peerCount: 2));
      expect(selected.isAvailable, isTrue);
      expect(selected.deviceIds, <String>['pixel-usb', 'emulator-5554']);
    },
  );

  test('iOS is selected only for an iOS boundary or explicit parity claim', () {
    final matrix = SimsDeviceMatrix(devices);
    final generic = matrix.select(const SimsTargetRequirement(peerCount: 1));
    expect(generic.devices.single.platform, SimsDevicePlatform.android);

    final ios = matrix.select(
      const SimsTargetRequirement(peerCount: 1, iosSpecific: true),
    );
    expect(ios.devices.single.platform, SimsDevicePlatform.ios);

    final parity = matrix.select(
      const SimsTargetRequirement(peerCount: 1, parityClaim: true),
    );
    expect(parity.devices.map((device) => device.platform).toSet(), {
      SimsDevicePlatform.android,
      SimsDevicePlatform.ios,
    });
  });

  test('only initial target unavailability is N/A', () {
    final unavailable = SimsDeviceMatrix(
      const <SimsDevice>[],
    ).select(const SimsTargetRequirement(peerCount: 2));
    expect(unavailable.isAvailable, isFalse);
    expect(unavailable.failureKind, DeviceSelectionFailure.targetUnavailable);
    expect(
      classifyDeviceFailure(selectedPreviously: true),
      DeviceSelectionFailure.deviceLost,
    );
    expect(
      classifyDeviceFailure(selectedPreviously: false),
      DeviceSelectionFailure.targetUnavailable,
    );
  });
}
