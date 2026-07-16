import 'dart:convert';

import 'package:crypto/crypto.dart';

enum SimsDevicePlatform { android, ios }

enum SimsDeviceKind { physical, emulator, simulator }

final class SimsDevice {
  const SimsDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.kind,
  });

  final String id;
  final String name;
  final SimsDevicePlatform platform;
  final SimsDeviceKind kind;

  bool get isPhysical => kind == SimsDeviceKind.physical;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform.name,
    'kind': kind.name,
  };
}

final class SimsTargetRequirement {
  const SimsTargetRequirement({
    required this.peerCount,
    this.iosSpecific = false,
    this.parityClaim = false,
  }) : assert(peerCount > 0);

  final int peerCount;
  final bool iosSpecific;
  final bool parityClaim;
}

enum DeviceSelectionFailure { targetUnavailable, deviceLost }

final class SimsDeviceSelection {
  const SimsDeviceSelection._({
    required this.devices,
    required this.failureKind,
  });

  const SimsDeviceSelection.available(List<SimsDevice> devices)
    : this._(devices: devices, failureKind: null);

  const SimsDeviceSelection.unavailable()
    : this._(
        devices: const <SimsDevice>[],
        failureKind: DeviceSelectionFailure.targetUnavailable,
      );

  final List<SimsDevice> devices;
  final DeviceSelectionFailure? failureKind;

  bool get isAvailable => failureKind == null;
  List<String> get deviceIds => devices.map((device) => device.id).toList();
}

final class SimsDeviceMatrix {
  SimsDeviceMatrix(Iterable<SimsDevice> devices)
    : devices = List<SimsDevice>.unmodifiable(devices);

  final List<SimsDevice> devices;

  String get digest {
    final rows = devices.map((device) => device.toJson()).toList()
      ..sort(
        (left, right) =>
            (left['id']! as String).compareTo(right['id']! as String),
      );
    return sha256.convert(utf8.encode(jsonEncode(rows))).toString();
  }

  SimsDeviceSelection select(SimsTargetRequirement requirement) {
    final android = _preferred(
      devices.where((device) => device.platform == SimsDevicePlatform.android),
      preferEmulatorSecond: true,
    );
    final ios = _preferred(
      devices.where((device) => device.platform == SimsDevicePlatform.ios),
    );

    if (requirement.parityClaim) {
      if (android.isEmpty || ios.isEmpty) {
        return const SimsDeviceSelection.unavailable();
      }
      return SimsDeviceSelection.available(<SimsDevice>[
        android.first,
        ios.first,
      ]);
    }

    final candidates = requirement.iosSpecific ? ios : android;
    if (candidates.length < requirement.peerCount) {
      return const SimsDeviceSelection.unavailable();
    }
    return SimsDeviceSelection.available(
      List<SimsDevice>.unmodifiable(candidates.take(requirement.peerCount)),
    );
  }
}

List<SimsDevice> _preferred(
  Iterable<SimsDevice> input, {
  bool preferEmulatorSecond = false,
}) {
  final devices = input.toList();
  int rank(SimsDevice device) {
    if (device.isPhysical) return 0;
    if (preferEmulatorSecond && device.kind == SimsDeviceKind.emulator) {
      return 1;
    }
    if (device.kind == SimsDeviceKind.simulator) return 1;
    return 2;
  }

  devices.sort((left, right) {
    final byRank = rank(left).compareTo(rank(right));
    return byRank != 0 ? byRank : left.id.compareTo(right.id);
  });
  return devices;
}

DeviceSelectionFailure classifyDeviceFailure({
  required bool selectedPreviously,
}) => selectedPreviously
    ? DeviceSelectionFailure.deviceLost
    : DeviceSelectionFailure.targetUnavailable;
