import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'manifest.dart';

enum SimsLiveDevicePlatform { android, ios }

enum SimsLiveDeviceKind { physical, emulator, simulator }

enum SimsLiveDeviceAvailability { connected, launchable }

enum SimsLiveDeviceClass {
  androidPhysical,
  androidEmulator,
  iosPhysical,
  iosSimulator,
}

enum SimsDeviceDiscoverySource { flutterDevices, adb, simctl, flutterEmulators }

enum SimsDiscoveryStatus { success, failed, notApplicable }

enum SimsDeviceResolutionStatus {
  resolved,
  preparationRequired,
  targetUnavailable,
  discoveryFailed,
  invalidResource,
}

final class SimsDiscoveryCommandOutput {
  const SimsDiscoveryCommandOutput({
    required this.exitCode,
    required this.stdoutText,
    required this.stderrText,
  });

  final int exitCode;
  final String stdoutText;
  final String stderrText;
}

abstract interface class SimsDiscoveryCommandRunner {
  Future<SimsDiscoveryCommandOutput> run(
    String executable,
    List<String> arguments,
  );
}

final class ProcessSimsDiscoveryCommandRunner
    implements SimsDiscoveryCommandRunner {
  const ProcessSimsDiscoveryCommandRunner();

  @override
  Future<SimsDiscoveryCommandOutput> run(
    String executable,
    List<String> arguments,
  ) async {
    final result = await Process.run(executable, arguments);
    return SimsDiscoveryCommandOutput(
      exitCode: result.exitCode,
      stdoutText: '${result.stdout}',
      stderrText: '${result.stderr}',
    );
  }
}

final class SimsDiscoverySourceResult {
  const SimsDiscoverySourceResult({
    required this.source,
    required this.status,
    required this.detail,
  });

  final SimsDeviceDiscoverySource source;
  final SimsDiscoveryStatus status;
  final String detail;
}

final class SimsLiveDeviceTarget {
  SimsLiveDeviceTarget({
    required this.name,
    required this.platform,
    required this.kind,
    required this.availability,
    required this.runtimeId,
    required this.launchId,
    required Iterable<SimsDeviceDiscoverySource> sources,
  }) : sources = Set<SimsDeviceDiscoverySource>.unmodifiable(sources);

  final String name;
  final SimsLiveDevicePlatform platform;
  final SimsLiveDeviceKind kind;
  final SimsLiveDeviceAvailability availability;

  /// ID accepted by a device-pinned test command now. It is null for a target
  /// that is installed/available but has not been booted.
  final String? runtimeId;

  /// Stable ID accepted by the platform's launcher, when discovery exposes it.
  final String? launchId;
  final Set<SimsDeviceDiscoverySource> sources;

  bool get isPhysical => kind == SimsLiveDeviceKind.physical;
  bool get isAndroidEmulator =>
      platform == SimsLiveDevicePlatform.android &&
      kind == SimsLiveDeviceKind.emulator;
  bool get isIosSimulator =>
      platform == SimsLiveDevicePlatform.ios &&
      kind == SimsLiveDeviceKind.simulator;
  bool get requiresLaunch =>
      availability == SimsLiveDeviceAvailability.launchable &&
      runtimeId == null &&
      launchId != null;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'platform': platform.name,
    'kind': kind.name,
    'availability': availability.name,
    if (runtimeId != null) 'runtimeId': runtimeId,
    if (launchId != null) 'launchId': launchId,
    'sources': sources.map((source) => source.name).toList()..sort(),
  };
}

final class SimsLiveDeviceInventory {
  SimsLiveDeviceInventory({
    required Iterable<SimsLiveDeviceTarget> targets,
    required Iterable<SimsDiscoverySourceResult> sourceResults,
    Iterable<SimsLiveDeviceClass> notReadyTargetClasses =
        const <SimsLiveDeviceClass>[],
  }) : targets = List<SimsLiveDeviceTarget>.unmodifiable(targets),
       notReadyTargetClasses = Set<SimsLiveDeviceClass>.unmodifiable(
         notReadyTargetClasses,
       ),
       sourceResults =
           Map<
             SimsDeviceDiscoverySource,
             SimsDiscoverySourceResult
           >.unmodifiable(
             <SimsDeviceDiscoverySource, SimsDiscoverySourceResult>{
               for (final result in sourceResults) result.source: result,
             },
           );

  final List<SimsLiveDeviceTarget> targets;
  final Set<SimsLiveDeviceClass> notReadyTargetClasses;
  final Map<SimsDeviceDiscoverySource, SimsDiscoverySourceResult> sourceResults;

  SimsLiveDeviceTarget? byRuntimeId(String id) {
    for (final target in targets) {
      if (target.runtimeId == id) return target;
    }
    return null;
  }

  SimsLiveDeviceTarget? byLaunchId(String id) {
    for (final target in targets) {
      if (target.launchId == id) return target;
    }
    return null;
  }

  SimsDiscoveryStatus sourceStatus(SimsDeviceDiscoverySource source) =>
      sourceResults[source]?.status ?? SimsDiscoveryStatus.failed;

  String sourceDetail(SimsDeviceDiscoverySource source) =>
      sourceResults[source]?.detail ?? '${source.name} was not discovered';

  Map<String, Object?> toJson() => <String, Object?>{
    'targets': targets.map((target) => target.toJson()).toList(),
    'notReadyTargetClasses':
        notReadyTargetClasses.map((targetClass) => targetClass.name).toList()
          ..sort(),
    'sources': <String, Object?>{
      for (final source in SimsDeviceDiscoverySource.values)
        source.name: <String, Object?>{
          'status': sourceStatus(source).name,
          'detail': sourceDetail(source),
        },
    },
  };
}

/// Read-only discovery for the availability-bounded project device matrix.
///
/// `listOnly` is deliberately the default. Discovery may report stopped AVDs
/// and iOS simulators as launchable, but it never launches, boots, installs, or
/// otherwise mutates a target.
final class SimsLiveDeviceDiscovery {
  SimsLiveDeviceDiscovery({
    SimsDiscoveryCommandRunner? commandRunner,
    bool? isMacOS,
  }) : commandRunner =
           commandRunner ?? const ProcessSimsDiscoveryCommandRunner(),
       isMacOS = isMacOS ?? Platform.isMacOS;

  final SimsDiscoveryCommandRunner commandRunner;
  final bool isMacOS;

  Future<SimsLiveDeviceInventory> discover({bool listOnly = true}) async {
    if (!listOnly) {
      throw UnsupportedError(
        'Live device discovery is read-only; prepare targets explicitly.',
      );
    }
    final flutter = await _capture(
      SimsDeviceDiscoverySource.flutterDevices,
      'flutter',
      const <String>['devices', '--machine', '--device-connection=attached'],
      _decodeJsonList,
    );
    final adb = await _capture(
      SimsDeviceDiscoverySource.adb,
      'adb',
      const <String>['devices', '-l'],
      _parseAdbRows,
    );
    final simctl = isMacOS
        ? await _capture(
            SimsDeviceDiscoverySource.simctl,
            'xcrun',
            const <String>['simctl', 'list', 'devices', 'available', '-j'],
            _decodeSimctlRows,
          )
        : _DiscoveryCapture.notApplicable(
            SimsDeviceDiscoverySource.simctl,
            'simctl is not applicable on this host',
          );
    final emulators = await _capture(
      SimsDeviceDiscoverySource.flutterEmulators,
      'flutter',
      const <String>['emulators'],
      _decodeFlutterEmulatorRows,
    );

    final targets = <SimsLiveDeviceTarget>[];
    final notReadyTargetClasses = <SimsLiveDeviceClass>{};
    final flutterRows = flutter.rows;
    final adbRows = adb.rows;
    final androidAvdNameByRuntimeId = <String, String>{};
    var hasUnmappedConnectedAndroidEmulator = false;
    if (adb.status == SimsDiscoveryStatus.success) {
      for (final row in adbRows) {
        final id = _nonEmptyString(row['id']);
        if (id == null ||
            !id.startsWith('emulator-') ||
            row['state'] != 'device') {
          continue;
        }
        final avdName = await _androidAvdName(id);
        if (avdName != null) {
          androidAvdNameByRuntimeId[id] = avdName;
        } else {
          hasUnmappedConnectedAndroidEmulator = true;
          notReadyTargetClasses.add(SimsLiveDeviceClass.androidEmulator);
        }
      }
    }

    if (flutter.status == SimsDiscoveryStatus.success &&
        adb.status == SimsDiscoveryStatus.success) {
      final flutterById = <String, Map<String, Object?>>{};
      for (final row in flutterRows) {
        final id = _nonEmptyString(row['id']);
        if (id != null) flutterById[id] = row;
      }
      for (final adbRow in adbRows) {
        final id = _nonEmptyString(adbRow['id']);
        if (id == null) continue;
        final flutterRow = flutterById[id];
        final emulator =
            flutterRow?['emulator'] == true || id.startsWith('emulator-');
        final explicitlyWireless =
            '${flutterRow?['connectionInterface'] ?? ''}'.toLowerCase() ==
            'wireless';
        final usb = adbRow['usbConnected'] == true;
        if (!emulator && (!usb || explicitlyWireless)) continue;
        final targetClass = emulator
            ? SimsLiveDeviceClass.androidEmulator
            : SimsLiveDeviceClass.androidPhysical;
        final targetPlatform = '${flutterRow?['targetPlatform'] ?? ''}';
        if (adbRow['state'] != 'device' ||
            flutterRow == null ||
            !_isSupported(flutterRow) ||
            !targetPlatform.startsWith('android')) {
          notReadyTargetClasses.add(targetClass);
          continue;
        }
        targets.add(
          SimsLiveDeviceTarget(
            name: _targetName(flutterRow, adbRow, id),
            platform: SimsLiveDevicePlatform.android,
            kind: emulator
                ? SimsLiveDeviceKind.emulator
                : SimsLiveDeviceKind.physical,
            availability: SimsLiveDeviceAvailability.connected,
            runtimeId: id,
            launchId: emulator ? androidAvdNameByRuntimeId[id] : null,
            sources: const <SimsDeviceDiscoverySource>{
              SimsDeviceDiscoverySource.flutterDevices,
              SimsDeviceDiscoverySource.adb,
            },
          ),
        );
      }
    }

    if (flutter.status == SimsDiscoveryStatus.success) {
      for (final row in flutterRows) {
        final id = _nonEmptyString(row['id']);
        final targetPlatform = '${row['targetPlatform'] ?? ''}';
        if (id == null || !targetPlatform.startsWith('ios')) continue;
        final emulator = row['emulator'] == true;
        final connectionInterface = '${row['connectionInterface'] ?? ''}'
            .toLowerCase();
        if (!emulator && connectionInterface == 'wireless') {
          continue;
        }
        if (!_isSupported(row)) {
          notReadyTargetClasses.add(
            emulator
                ? SimsLiveDeviceClass.iosSimulator
                : SimsLiveDeviceClass.iosPhysical,
          );
          continue;
        }
        targets.add(
          SimsLiveDeviceTarget(
            name: _targetName(row, const <String, Object?>{}, id),
            platform: SimsLiveDevicePlatform.ios,
            kind: emulator
                ? SimsLiveDeviceKind.simulator
                : SimsLiveDeviceKind.physical,
            availability: SimsLiveDeviceAvailability.connected,
            runtimeId: id,
            launchId: emulator ? id : null,
            sources: const <SimsDeviceDiscoverySource>{
              SimsDeviceDiscoverySource.flutterDevices,
            },
          ),
        );
      }
    }

    if (simctl.status == SimsDiscoveryStatus.success) {
      for (final row in simctl.rows) {
        if (row['isAvailable'] == false) continue;
        final id = _nonEmptyString(row['udid']);
        if (id == null) continue;
        final booted = row['state'] == 'Booted';
        targets.add(
          SimsLiveDeviceTarget(
            name: _nonEmptyString(row['name']) ?? id,
            platform: SimsLiveDevicePlatform.ios,
            kind: SimsLiveDeviceKind.simulator,
            availability: booted
                ? SimsLiveDeviceAvailability.connected
                : SimsLiveDeviceAvailability.launchable,
            runtimeId: booted ? id : null,
            launchId: id,
            sources: const <SimsDeviceDiscoverySource>{
              SimsDeviceDiscoverySource.simctl,
            },
          ),
        );
      }
    }

    if (emulators.status == SimsDiscoveryStatus.success &&
        !hasUnmappedConnectedAndroidEmulator) {
      for (final row in emulators.rows) {
        final platform = '${row['platformType'] ?? row['platform'] ?? ''}'
            .toLowerCase();
        if (platform != 'android') continue;
        final id = _nonEmptyString(row['id']);
        if (id == null) continue;
        targets.add(
          SimsLiveDeviceTarget(
            name: _nonEmptyString(row['name']) ?? id,
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.emulator,
            availability: SimsLiveDeviceAvailability.launchable,
            runtimeId: null,
            launchId: id,
            sources: const <SimsDeviceDiscoverySource>{
              SimsDeviceDiscoverySource.flutterEmulators,
            },
          ),
        );
      }
    }

    return SimsLiveDeviceInventory(
      targets: _mergeTargets(targets),
      notReadyTargetClasses: notReadyTargetClasses,
      sourceResults: <SimsDiscoverySourceResult>[
        flutter.result,
        adb.result,
        simctl.result,
        emulators.result,
      ],
    );
  }

  Future<_DiscoveryCapture> _capture(
    SimsDeviceDiscoverySource source,
    String executable,
    List<String> arguments,
    List<Map<String, Object?>> Function(String output) parser,
  ) async {
    try {
      final output = await commandRunner.run(executable, arguments);
      if (output.exitCode != 0) {
        return _DiscoveryCapture.failed(
          source,
          _boundedDetail(
            output.stderrText.isNotEmpty
                ? output.stderrText
                : 'command exited ${output.exitCode}',
          ),
        );
      }
      final rows = parser(output.stdoutText);
      return _DiscoveryCapture.success(source, rows);
    } on Object catch (error) {
      return _DiscoveryCapture.failed(source, _boundedDetail('$error'));
    }
  }

  Future<String?> _androidAvdName(String runtimeId) async {
    for (final arguments in <List<String>>[
      <String>['-s', runtimeId, 'emu', 'avd', 'name'],
      <String>['-s', runtimeId, 'shell', 'getprop', 'ro.boot.qemu.avd_name'],
    ]) {
      try {
        final output = await commandRunner.run('adb', arguments);
        if (output.exitCode != 0) continue;
        for (final line in output.stdoutText.split(RegExp(r'[\r\n]+'))) {
          final value = line.trim();
          if (value.isNotEmpty && value != 'OK') return value;
        }
      } on Object {
        // Try the read-only property fallback before giving up.
      }
    }
    return null;
  }
}

final class SimsDeviceResolution {
  SimsDeviceResolution._({
    required this.status,
    required Map<String, String> assignments,
    required Map<String, String> environment,
    required Iterable<SimsLiveDeviceTarget> preparationTargets,
    required this.detail,
  }) : assignments = Map<String, String>.unmodifiable(assignments),
       environment = Map<String, String>.unmodifiable(environment),
       preparationTargets = List<SimsLiveDeviceTarget>.unmodifiable(
         preparationTargets,
       );

  final SimsDeviceResolutionStatus status;
  final Map<String, String> assignments;
  final Map<String, String> environment;
  final List<SimsLiveDeviceTarget> preparationTargets;
  final String detail;

  bool get policyNaEligible =>
      status == SimsDeviceResolutionStatus.targetUnavailable;
  String? get naReason => policyNaEligible ? targetUnavailableNaReason : null;

  String? deviceIdFor(String symbolicResource) => assignments[symbolicResource];
}

/// Resolves symbolic manifest locks to concrete, deterministic target IDs.
///
/// Non-device resources are intentionally ignored. Credential, driver,
/// artifact, relay, and build failures are executor blockers and can never be
/// upgraded to policy N/A by this resolver.
final class SimsLiveDeviceResolver {
  const SimsLiveDeviceResolver(this.inventory);

  final SimsLiveDeviceInventory inventory;

  SimsDeviceResolution resolveLocks(
    Iterable<ResourceLock> locks, {
    Map<String, String> requiredTargetIds = const <String, String>{},
  }) => resolveResourceNames(
    locks.map((lock) => lock.name),
    requiredTargetIds: requiredTargetIds,
  );

  SimsDeviceResolution resolveResourceNames(
    Iterable<String> resourceNames, {
    Map<String, String> requiredTargetIds = const <String, String>{},
  }) {
    final requestedNames = resourceNames
        .where(_isSymbolicDeviceResource)
        .toList(growable: false);
    final roleByName = <String, _DeviceRole>{};
    for (final name in requestedNames) {
      final role = _roleForResource(name);
      if (role == null) {
        return SimsDeviceResolution._(
          status: SimsDeviceResolutionStatus.invalidResource,
          assignments: const <String, String>{},
          environment: const <String, String>{},
          preparationTargets: const <SimsLiveDeviceTarget>[],
          detail: 'Unknown symbolic device resource: $name',
        );
      }
      roleByName[name] = role;
    }
    if (roleByName.isEmpty) {
      return SimsDeviceResolution._(
        status: SimsDeviceResolutionStatus.resolved,
        assignments: const <String, String>{},
        environment: const <String, String>{},
        preparationTargets: const <SimsLiveDeviceTarget>[],
        detail: 'No symbolic device resources requested.',
      );
    }

    final requiredTargetIdByRole = <_DeviceRole, String>{};
    for (final entry in roleByName.entries) {
      final requiredId = requiredTargetIds[entry.key]?.trim();
      if (requiredId == null || requiredId.isEmpty) continue;
      final previous = requiredTargetIdByRole[entry.value];
      if (previous != null && previous != requiredId) {
        return SimsDeviceResolution._(
          status: SimsDeviceResolutionStatus.invalidResource,
          assignments: const <String, String>{},
          environment: const <String, String>{},
          preparationTargets: const <SimsLiveDeviceTarget>[],
          detail:
              'Conflicting explicitly required target IDs for '
              '${entry.value.name}.',
        );
      }
      requiredTargetIdByRole[entry.value] = requiredId;
    }

    final targetByRole = <_DeviceRole, SimsLiveDeviceTarget>{};
    final missingRoles = <_DeviceRole>[];
    final notReadyRoles = <_DeviceRole>[];
    final preparationTargets = <SimsLiveDeviceTarget>[];
    final requestedRoles = roleByName.values.toSet();

    for (final role in requestedRoles) {
      final candidate = _candidateForRole(
        role,
        requiredTargetId: requiredTargetIdByRole[role],
      );
      if (candidate == null) {
        if (inventory.notReadyTargetClasses.contains(_targetClass(role))) {
          notReadyRoles.add(role);
        } else {
          missingRoles.add(role);
        }
      } else if (candidate.runtimeId == null) {
        preparationTargets.add(candidate);
      } else {
        targetByRole[role] = candidate;
      }
    }

    if (missingRoles.isNotEmpty) {
      final failedSources = <SimsDeviceDiscoverySource>{};
      for (final role in missingRoles) {
        failedSources.addAll(_failedRequiredSources(role));
      }
      if (failedSources.isNotEmpty) {
        final names = failedSources.map((source) => source.name).toList()
          ..sort();
        return SimsDeviceResolution._(
          status: SimsDeviceResolutionStatus.discoveryFailed,
          assignments: const <String, String>{},
          environment: const <String, String>{},
          preparationTargets: const <SimsLiveDeviceTarget>[],
          detail: 'Device discovery failed for ${names.join(', ')}.',
        );
      }
      final names = missingRoles.map((role) => role.name).toList()..sort();
      return SimsDeviceResolution._(
        status: SimsDeviceResolutionStatus.targetUnavailable,
        assignments: const <String, String>{},
        environment: const <String, String>{},
        preparationTargets: const <SimsLiveDeviceTarget>[],
        detail:
            'Required live target is unavailable by project policy: '
            '${names.join(', ')}.',
      );
    }

    if (notReadyRoles.isNotEmpty) {
      final names = notReadyRoles.map((role) => role.name).toList()..sort();
      return SimsDeviceResolution._(
        status: SimsDeviceResolutionStatus.preparationRequired,
        assignments: const <String, String>{},
        environment: const <String, String>{},
        preparationTargets: const <SimsLiveDeviceTarget>[],
        detail:
            'A discovered target is attached but not executable: '
            '${names.join(', ')}.',
      );
    }

    if (preparationTargets.isNotEmpty) {
      return SimsDeviceResolution._(
        status: SimsDeviceResolutionStatus.preparationRequired,
        assignments: const <String, String>{},
        environment: const <String, String>{},
        preparationTargets: preparationTargets.toSet(),
        detail:
            'A discovered target must be booted before its runtime ID can be '
            'assigned.',
      );
    }

    final rolesByTargetId = <String, List<_DeviceRole>>{};
    for (final entry in targetByRole.entries) {
      rolesByTargetId
          .putIfAbsent(entry.value.runtimeId!, () => <_DeviceRole>[])
          .add(entry.key);
    }
    final duplicate = rolesByTargetId.entries
        .where((entry) => entry.value.length > 1)
        .firstOrNull;
    if (duplicate != null) {
      final names = duplicate.value.map((role) => role.name).toList()..sort();
      return SimsDeviceResolution._(
        status: SimsDeviceResolutionStatus.invalidResource,
        assignments: const <String, String>{},
        environment: const <String, String>{},
        preparationTargets: const <SimsLiveDeviceTarget>[],
        detail:
            'Distinct device roles resolved to the same target '
            '${duplicate.key}: ${names.join(', ')}.',
      );
    }

    final assignments = SplayTreeMap<String, String>();
    for (final entry in roleByName.entries) {
      assignments[entry.key] = targetByRole[entry.value]!.runtimeId!;
    }
    final environment = _environmentFor(assignments, targetByRole);
    return SimsDeviceResolution._(
      status: SimsDeviceResolutionStatus.resolved,
      assignments: assignments,
      environment: environment,
      preparationTargets: const <SimsLiveDeviceTarget>[],
      detail: 'All symbolic device resources resolved to explicit target IDs.',
    );
  }

  SimsLiveDeviceTarget? _candidateForRole(
    _DeviceRole role, {
    String? requiredTargetId,
  }) {
    final candidates = inventory.targets.where((target) {
      if (requiredTargetId != null &&
          target.runtimeId != requiredTargetId &&
          target.launchId != requiredTargetId) {
        return false;
      }
      return switch (role) {
        _DeviceRole.androidPhysical =>
          target.platform == SimsLiveDevicePlatform.android &&
              target.kind == SimsLiveDeviceKind.physical,
        _DeviceRole.androidEmulator ||
        _DeviceRole.androidEmulatorSecond => target.isAndroidEmulator,
        _DeviceRole.iosPhysical =>
          target.platform == SimsLiveDevicePlatform.ios &&
              target.kind == SimsLiveDeviceKind.physical,
        _DeviceRole.iosSimulatorA ||
        _DeviceRole.iosSimulatorB ||
        _DeviceRole.iosSimulatorC ||
        _DeviceRole.iosSimulatorD => target.isIosSimulator,
      };
    }).toList();
    candidates.sort(_compareCandidates);
    final index = requiredTargetId != null
        ? 0
        : switch (role) {
            _DeviceRole.androidEmulatorSecond => 1,
            _DeviceRole.iosSimulatorB => 1,
            _DeviceRole.iosSimulatorC => 2,
            _DeviceRole.iosSimulatorD => 3,
            _ => 0,
          };
    return candidates.length > index ? candidates[index] : null;
  }

  Set<SimsDeviceDiscoverySource> _failedRequiredSources(_DeviceRole role) {
    final required = switch (role) {
      _DeviceRole.androidPhysical => const <SimsDeviceDiscoverySource>{
        SimsDeviceDiscoverySource.flutterDevices,
        SimsDeviceDiscoverySource.adb,
      },
      _DeviceRole.androidEmulator ||
      _DeviceRole.androidEmulatorSecond => const <SimsDeviceDiscoverySource>{
        SimsDeviceDiscoverySource.flutterDevices,
        SimsDeviceDiscoverySource.adb,
        SimsDeviceDiscoverySource.flutterEmulators,
      },
      _DeviceRole.iosPhysical => const <SimsDeviceDiscoverySource>{
        SimsDeviceDiscoverySource.flutterDevices,
      },
      _DeviceRole.iosSimulatorA ||
      _DeviceRole.iosSimulatorB ||
      _DeviceRole.iosSimulatorC ||
      _DeviceRole.iosSimulatorD => const <SimsDeviceDiscoverySource>{
        SimsDeviceDiscoverySource.simctl,
      },
    };
    return required
        .where(
          (source) =>
              inventory.sourceStatus(source) == SimsDiscoveryStatus.failed,
        )
        .toSet();
  }
}

enum _DeviceRole {
  androidPhysical,
  androidEmulator,
  androidEmulatorSecond,
  iosPhysical,
  iosSimulatorA,
  iosSimulatorB,
  iosSimulatorC,
  iosSimulatorD,
}

SimsLiveDeviceClass _targetClass(_DeviceRole role) => switch (role) {
  _DeviceRole.androidPhysical => SimsLiveDeviceClass.androidPhysical,
  _DeviceRole.androidEmulator ||
  _DeviceRole.androidEmulatorSecond => SimsLiveDeviceClass.androidEmulator,
  _DeviceRole.iosPhysical => SimsLiveDeviceClass.iosPhysical,
  _DeviceRole.iosSimulatorA ||
  _DeviceRole.iosSimulatorB ||
  _DeviceRole.iosSimulatorC ||
  _DeviceRole.iosSimulatorD => SimsLiveDeviceClass.iosSimulator,
};

bool _isSymbolicDeviceResource(String value) =>
    value.startsWith('device:') || value.startsWith('device-control:');

_DeviceRole? _roleForResource(String value) {
  final separator = value.indexOf(':');
  if (separator < 0) return null;
  return switch (value.substring(separator + 1)) {
    'android-physical' => _DeviceRole.androidPhysical,
    'android-emulator' => _DeviceRole.androidEmulator,
    'android-emulator-second' => _DeviceRole.androidEmulatorSecond,
    'ios-physical' => _DeviceRole.iosPhysical,
    'ios-simulator-a' => _DeviceRole.iosSimulatorA,
    'ios-simulator-b' => _DeviceRole.iosSimulatorB,
    'ios-simulator-c' => _DeviceRole.iosSimulatorC,
    'ios-simulator-d' => _DeviceRole.iosSimulatorD,
    _ => null,
  };
}

Map<String, String> _environmentFor(
  Map<String, String> assignments,
  Map<_DeviceRole, SimsLiveDeviceTarget> targetByRole,
) {
  final result = SplayTreeMap<String, String>();
  String? id(_DeviceRole role) => targetByRole[role]?.runtimeId;
  final androidPhysical = id(_DeviceRole.androidPhysical);
  final androidEmulator = id(_DeviceRole.androidEmulator);
  final androidEmulatorSecond = id(_DeviceRole.androidEmulatorSecond);
  final iosPhysical = id(_DeviceRole.iosPhysical);
  final iosSimulatorA = id(_DeviceRole.iosSimulatorA);
  final iosSimulatorB = id(_DeviceRole.iosSimulatorB);
  final iosSimulatorC = id(_DeviceRole.iosSimulatorC);
  final iosSimulatorD = id(_DeviceRole.iosSimulatorD);

  if (androidPhysical != null) {
    result['ANDROID_SERIAL'] = androidPhysical;
    result['RELIABILITY_SINGLE_DEVICE_ID'] = androidPhysical;
    result['SIMS_ANDROID_PHYSICAL_DEVICE_ID'] = androidPhysical;
  }
  if (androidEmulator != null) {
    result['SIMS_ANDROID_EMULATOR_DEVICE_ID'] = androidEmulator;
  }
  if (androidEmulatorSecond != null) {
    result['SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID'] = androidEmulatorSecond;
  }
  if (androidEmulator != null && androidEmulatorSecond != null) {
    result['SIMS_ANDROID_EMULATOR_DEVICE_IDS'] =
        '$androidEmulator,$androidEmulatorSecond';
  }
  if (androidPhysical != null && androidEmulator != null) {
    result['RELIABILITY_MULTI_DEVICE_IDS'] =
        '$androidPhysical,$androidEmulator';
  }
  if (iosPhysical != null) {
    result['IOS_NOTIFICATION_TAP_DEVICES'] = iosPhysical;
    result['SIMS_IOS_PHYSICAL_DEVICE_ID'] = iosPhysical;
  }
  if (iosSimulatorA != null) {
    result['SIMULATOR_DEVICE'] = iosSimulatorA;
    result['SIMS_IOS_SIMULATOR_A_DEVICE_ID'] = iosSimulatorA;
  }
  if (iosSimulatorB != null) {
    result['IOS_SECONDARY_SIMULATOR_DEVICE'] = iosSimulatorB;
    result['SIMS_IOS_SIMULATOR_B_DEVICE_ID'] = iosSimulatorB;
  }
  if (iosSimulatorC != null) {
    result['SIMS_IOS_SIMULATOR_C_DEVICE_ID'] = iosSimulatorC;
  }
  if (iosSimulatorD != null) {
    result['SIMS_IOS_SIMULATOR_D_DEVICE_ID'] = iosSimulatorD;
  }
  result['SIMS_DEVICE_ASSIGNMENTS_JSON'] = jsonEncode(
    SplayTreeMap<String, String>.of(assignments),
  );
  return result;
}

int _compareCandidates(SimsLiveDeviceTarget left, SimsLiveDeviceTarget right) {
  final availability = left.availability.index.compareTo(
    right.availability.index,
  );
  if (availability != 0) return availability;
  final leftId = left.runtimeId ?? left.launchId ?? '';
  final rightId = right.runtimeId ?? right.launchId ?? '';
  return leftId.compareTo(rightId);
}

List<SimsLiveDeviceTarget> _mergeTargets(
  Iterable<SimsLiveDeviceTarget> targets,
) {
  final byKey = <String, SimsLiveDeviceTarget>{};
  for (final target in targets) {
    final key =
        '${target.platform.name}:${target.kind.name}:'
        '${target.launchId ?? target.runtimeId}';
    final previous = byKey[key];
    if (previous == null) {
      byKey[key] = target;
      continue;
    }
    final connected = previous.runtimeId != null ? previous : target;
    byKey[key] = SimsLiveDeviceTarget(
      name: connected.name,
      platform: connected.platform,
      kind: connected.kind,
      availability: connected.runtimeId != null
          ? SimsLiveDeviceAvailability.connected
          : SimsLiveDeviceAvailability.launchable,
      runtimeId: previous.runtimeId ?? target.runtimeId,
      launchId: previous.launchId ?? target.launchId,
      sources: <SimsDeviceDiscoverySource>{
        ...previous.sources,
        ...target.sources,
      },
    );
  }
  final result = byKey.values.toList()..sort(_compareCandidates);
  return List<SimsLiveDeviceTarget>.unmodifiable(result);
}

List<Map<String, Object?>> _decodeJsonList(String output) {
  final decoded = _decodeMachineJson(output, opening: '[', closing: ']');
  if (decoded is! List) {
    throw const FormatException('expected a JSON array');
  }
  return decoded.map(_objectMap).toList(growable: false);
}

List<Map<String, Object?>> _decodeFlutterEmulatorRows(String output) {
  final trimmed = output.trimLeft();
  if (trimmed.startsWith('[')) return _decodeJsonList(output);
  final rows = <Map<String, Object?>>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final columns = rawLine.split('•').map((value) => value.trim()).toList();
    if (columns.length < 4 || columns.last.toLowerCase() == 'platform') {
      continue;
    }
    final id = columns.first;
    final platform = columns.last.toLowerCase();
    if (id.isEmpty || (platform != 'android' && platform != 'ios')) continue;
    rows.add(<String, Object?>{
      'id': id,
      'name': columns[1],
      'platformType': platform,
    });
  }
  return rows;
}

List<Map<String, Object?>> _decodeSimctlRows(String output) {
  final root = _objectMap(
    _decodeMachineJson(output, opening: '{', closing: '}'),
  );
  final devices = root['devices'];
  if (devices is! Map) {
    throw const FormatException('simctl JSON has no devices object');
  }
  return <Map<String, Object?>>[
    for (final runtimeDevices in devices.values)
      if (runtimeDevices is List)
        for (final device in runtimeDevices) _objectMap(device),
  ];
}

Object? _decodeMachineJson(
  String output, {
  required String opening,
  required String closing,
}) {
  try {
    return jsonDecode(output);
  } on FormatException {
    final start = output.indexOf(opening);
    final end = output.lastIndexOf(closing);
    if (start < 0 || end < start) rethrow;
    return jsonDecode(output.substring(start, end + 1));
  }
}

List<Map<String, Object?>> _parseAdbRows(String output) {
  final rows = <Map<String, Object?>>[];
  for (final rawLine in const LineSplitter().convert(output)) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('List of devices attached')) continue;
    final columns = line.split(RegExp(r'\s+'));
    if (columns.length < 2) continue;
    final fields = <String, Object?>{
      'id': columns[0],
      'state': columns[1],
      'usbConnected': columns.skip(2).any((field) => field.startsWith('usb:')),
    };
    for (final field in columns.skip(2)) {
      final separator = field.indexOf(':');
      if (separator <= 0) continue;
      fields[field.substring(0, separator)] = field.substring(separator + 1);
    }
    rows.add(fields);
  }
  return rows;
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) throw const FormatException('expected a JSON object');
  return value.map<String, Object?>((key, item) => MapEntry('$key', item));
}

bool _isSupported(Map<String, Object?> row) => row['isSupported'] != false;

String _targetName(
  Map<String, Object?> flutterRow,
  Map<String, Object?> adbRow,
  String fallback,
) =>
    _nonEmptyString(flutterRow['name']) ??
    _nonEmptyString(adbRow['model'])?.replaceAll('_', ' ') ??
    fallback;

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _boundedDetail(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return normalized.length <= 300 ? normalized : normalized.substring(0, 300);
}

final class _DiscoveryCapture {
  const _DiscoveryCapture({required this.result, required this.rows});

  factory _DiscoveryCapture.success(
    SimsDeviceDiscoverySource source,
    List<Map<String, Object?>> rows,
  ) => _DiscoveryCapture(
    result: SimsDiscoverySourceResult(
      source: source,
      status: SimsDiscoveryStatus.success,
      detail: '${rows.length} row(s) discovered',
    ),
    rows: rows,
  );

  factory _DiscoveryCapture.failed(
    SimsDeviceDiscoverySource source,
    String detail,
  ) => _DiscoveryCapture(
    result: SimsDiscoverySourceResult(
      source: source,
      status: SimsDiscoveryStatus.failed,
      detail: detail,
    ),
    rows: const <Map<String, Object?>>[],
  );

  factory _DiscoveryCapture.notApplicable(
    SimsDeviceDiscoverySource source,
    String detail,
  ) => _DiscoveryCapture(
    result: SimsDiscoverySourceResult(
      source: source,
      status: SimsDiscoveryStatus.notApplicable,
      detail: detail,
    ),
    rows: const <Map<String, Object?>>[],
  );

  final SimsDiscoverySourceResult result;
  final List<Map<String, Object?>> rows;

  SimsDiscoveryStatus get status => result.status;
}
