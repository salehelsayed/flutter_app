import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import 'android_app_state_guard.dart';
import 'production_android_artifact.dart';
import 'production_journey.dart';
import 'production_journey_peer.dart';

const productionJourneyAndroidProfile = 'android.e2e.production';
const productionPerformanceAndroidProfile = 'android.e2e.performance_relay';
const productionJourneyAndroidPackage = 'com.mknoon.sims.connectivity';
const productionNotificationAndroidProfile = 'android.production_fcm.journey';
const productionNotificationAndroidPackage = 'com.mknoon.app';

abstract interface class ProductionAndroidInstallGuard {
  Future<void> prepareFreshInstall({
    required String device,
    required File artifact,
  });
  Future<void> restoreAll();
}

final class _CapturedProductionAndroidInstallGuard
    implements ProductionAndroidInstallGuard {
  _CapturedProductionAndroidInstallGuard(this.guard);
  final AndroidAppStateGuard guard;

  @override
  Future<void> prepareFreshInstall({
    required String device,
    required File artifact,
  }) => guard.prepareFreshInstall(device: device, artifact: artifact);

  @override
  Future<void> restoreAll() => guard.restoreAll();
}

typedef ProductionAndroidGuardCapture =
    Future<ProductionAndroidInstallGuard> Function({
      required List<String> devices,
      required String packageName,
      required String backupLabel,
      required File preparedArtifact,
      required String expectedArtifactSha256,
    });

Future<ProductionAndroidInstallGuard> _captureProductionAndroidGuard({
  required List<String> devices,
  required String packageName,
  required String backupLabel,
  required File preparedArtifact,
  required String expectedArtifactSha256,
}) async => _CapturedProductionAndroidInstallGuard(
  await AndroidAppStateGuard.capture(
    devices: devices,
    packageName: packageName,
    backupLabel: backupLabel,
    preparedArtifact: preparedArtifact,
    expectedArtifactSha256: expectedArtifactSha256,
  ),
);

/// Each invocation gets a fresh evidence directory, including repeated reopen
/// labels. Failed adapter output is retained without reusing an earlier PASS.
final class ProductionJourneyFlowRunner {
  ProductionJourneyFlowRunner(this.output, this.runner);
  final Directory output;
  final AndroidHostProcessRunner runner;

  Future<String> run(
    String device,
    String name,
    String label,
    Map<String, String> values, {
    String packageName = productionJourneyAndroidPackage,
  }) async {
    if (!{
          productionJourneyAndroidPackage,
          productionNotificationAndroidPackage,
        }.contains(packageName) ||
        values.containsKey('APP_ID')) {
      throw ArgumentError('invalid flow package binding');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(label) ||
        !RegExp(r'^production_[a-z0-9_]+$').hasMatch(name)) {
      throw ArgumentError('invalid flow identity');
    }
    // A Maestro driver that never starts ran no UI step: clear a leftover
    // driver on this device and run the flow once more, in a fresh evidence
    // directory.
    for (var start = 1; ; start++) {
      try {
        return await _runOnce(device, name, label, values, packageName);
      } on _DriverNeverStarted {
        if (start >= 2) throw StateError('$label Maestro flow failed');
        if (_isSimulator(device)) {
          await runner.run('xcrun', [
            'simctl',
            'terminate',
            device,
            'dev.mobile.maestro-driver-iosUITests.xctrunner',
          ]);
          continue;
        }
        for (final package in [
          'dev.mobile.maestro',
          'dev.mobile.maestro.test',
        ]) {
          await runner.run('adb', [
            '-s',
            device,
            'shell',
            'am',
            'force-stop',
            package,
          ]);
        }
      }
    }
  }

  Future<String> _runOnce(
    String device,
    String name,
    String label,
    Map<String, String> values,
    String packageName,
  ) async {
    final attempt = await output.createTemp('flow-$label-');
    final destination = Directory('${attempt.path}/maestro');
    final simulator = _isSimulator(device);
    final args = [
      'scripts/maestro_flow_runner.py',
      '--device',
      device,
      '--flow',
      'integration_test/maestro/$name.yaml',
      '--expected-name',
      name,
      '--output',
      destination.path,
      if (simulator) ...['--timeout', '300'],
      '--env',
      'APP_ID=$packageName',
      for (final entry in values.entries) ...[
        '--env',
        '${entry.key}=${entry.value}',
      ],
    ];
    // Simulator flows get Maestro's 300 s bound plus margin, so a driver that
    // never started is reported (and retried) instead of cut off by the
    // default host command limit.
    final runner = this.runner;
    final result = simulator && runner is AndroidHostProcessRunnerWithTimeout
        ? await runner.runWithTimeout(
            'python3',
            args,
            timeout: const Duration(seconds: 330),
          )
        : await runner.run('python3', args);
    await File('${attempt.path}/adapter.json').writeAsString(
      jsonEncode({
        'exitCode': result.exitCode,
        'stdout': '${result.stdout}',
        'stderr': '${result.stderr}',
      }),
    );
    if (result.exitCode != 0) {
      final log = File('${destination.path}/process.log');
      if (log.existsSync() &&
          _driverNeverStarted.any(log.readAsStringSync().contains)) {
        throw const _DriverNeverStarted();
      }
      throw StateError('$label Maestro flow failed');
    }
    final receipt = File('${destination.path}/result.json');
    final value = jsonDecode(await receipt.readAsString()) as Map;
    if (value['status'] != 'PASS' ||
        value['exit_status'] != 0 ||
        value['flows'] is! List ||
        (value['flows'] as List).length != 1 ||
        (value['flows'] as List).single != name) {
      throw StateError('$label lacks an exact successful flow receipt');
    }
    return receipt.path;
  }
}

// Messages Maestro logs when its device driver or device server never came
// up (the beta runner's iOS retry patterns), not when a flow step failed.
const _driverNeverStarted = [
  'Maestro Android driver did not start up in time',
  'driver not ready in time',
  'DeviceServerDiedException',
  'Unable to launch',
];

bool _isSimulator(String device) => RegExp(
  r'^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$',
  caseSensitive: false,
).hasMatch(device);

final class _DriverNeverStarted implements Exception {
  const _DriverNeverStarted();
}

/// Catalog scenarios with a fourth Android peer, Dana, on the pinned third
/// emulator (`SIMS_ANDROID_EMULATOR_THIRD_DEVICE_ID`).
const productionFourPeerScenarios = {
  'production.group_catalog.gm002',
  'production.group_catalog.private_online_add',
  'production.group_catalog.gm003',
  'production.group_catalog.private_offline_add',
};

/// Host-owned installation, invocation and cleanup. Production main constructs
/// the entire application. This helper never builds or supplies application
/// services, never drives the UI itself, and never declares a scenario passed.
final class ProductionAndroidJourney implements ProductionJourney {
  ProductionAndroidJourney.fromEnvironment(
    this.scenario,
    this.output, {
    Map<String, String>? environment,
    AndroidHostProcessRunner? runner,
    ProductionAndroidGuardCapture? captureGuard,
  }) : runner = runner ?? const SystemAndroidHostProcessRunner(),
       captureGuard = captureGuard ?? _captureProductionAndroidGuard {
    final values = environment ?? Platform.environment;
    String required(String name) {
      final value = values[name];
      if (value == null || value.isEmpty) throw StateError('missing $name');
      return value;
    }

    profileId = scenario == 'production.startup_resume_performance'
        ? productionPerformanceAndroidProfile
        : productionJourneyAndroidProfile;
    final primary = ProductionAndroidArtifact.fromEnvironment(
      profileId,
      values,
      primary: true,
    );
    artifacts[profileId] = primary;
    artifact = primary.file;
    inputDigest = primary.inputDigest;
    artifactDigest = primary.artifactDigest;
    if (usesProviderReceiver) {
      artifacts[productionNotificationAndroidProfile] =
          ProductionAndroidArtifact.fromEnvironment(
            productionNotificationAndroidProfile,
            values,
            primary: false,
          );
    }
    physical = required('SIMS_ANDROID_PHYSICAL_DEVICE_ID');
    emulator = scenario == 'production.startup_resume_performance'
        ? null
        : required('SIMS_ANDROID_EMULATOR_DEVICE_ID');
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(physical) ||
        physical.startsWith('emulator-') ||
        (emulator != null &&
            !RegExp(r'^emulator-[0-9]+$').hasMatch(emulator!))) {
      throw StateError('physical Android and emulator must be pinned');
    }
    alice = peer(physical, 'alice');
    if (scenario != 'production.startup_resume_performance') {
      bob = peer(emulator!, 'bob');
    }
    if ({
      'production.group_catalog.private_abc_create',
      'production.group_catalog.private_reaction_roundtrip',
      'production.group_catalog.private_reaction_toggle_convergence',
      'production.group_catalog.private_removed_reaction_rejected',
      'production.group_delete_preserves_friends',
      'production.group_catalog.private_online_remove',
      'production.group_catalog.private_relay_only_delivery',
      'production.group_catalog.private_process_death_matrix',
      'production.group_catalog.gm004',
      'production.group_catalog.gm005',
      'production.group_catalog.private_offline_remove',
      'production.group_catalog.gm006',
      'production.group_catalog.private_offline_readd',
      'production.group_catalog.gm001',
      'production.group_catalog.ge001',
      'production.group_catalog.de003',
      'production.group_catalog.ge002',
      'production.group_catalog.ge003',
      'production.group_catalog.gm020',
      'production.group_catalog.gm034',
      'production.group_catalog.gm016',
      'production.group_catalog.ge004',
      'production.group_catalog.gm007',
      'production.group_catalog.gm019',
      'production.group_catalog.ge009',
      'production.group_catalog.private_rapid_readd',
      'production.group_catalog.ir001',
      'production.group_catalog.gm008',
      'production.group_catalog.ge007',
      'production.group_catalog.ge008',
      'production.group_catalog.ge005',
      'production.group_catalog.private_readd_cycles',
      'production.group_catalog.ge010',
      'production.group_catalog.go001',
      'production.group_catalog.ge011',
      'production.group_catalog.private_full_mesh_online',
      'production.group_catalog.de002',
      'production.group_catalog.ge006',
      'production.group_catalog.de007',
      'production.group_catalog.private_voluntary_leave_convergence',
      'production.group_catalog.gm015',
      'production.group_catalog.ge024',
      'production.group_catalog.private_media_reaction_roundtrip',
      'production.group_catalog.private_removed_notification_privacy',
      ...productionFourPeerScenarios,
    }.contains(scenario)) {
      final third = required('SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID');
      if (!RegExp(r'^emulator-[0-9]+$').hasMatch(third) || third == emulator) {
        throw StateError(
          'catalog requires a distinct pinned third Android target',
        );
      }
      additionalPeers['charlie'] = peer(third, 'charlie');
      if (productionFourPeerScenarios.contains(scenario)) {
        final fourth = required('SIMS_ANDROID_EMULATOR_THIRD_DEVICE_ID');
        if (!RegExp(r'^emulator-[0-9]+$').hasMatch(fourth) ||
            fourth == emulator ||
            fourth == third) {
          throw StateError(
            'catalog requires a distinct pinned fourth Android target',
          );
        }
        additionalPeers['dana'] = peer(fourth, 'dana');
      }
    }
  }

  @override
  final String scenario;
  final Directory output;
  @override
  final String runId = 'journey-${DateTime.now().microsecondsSinceEpoch}';
  @override
  final AndroidHostProcessRunner runner;
  final ProductionAndroidGuardCapture captureGuard;
  final _random = Random.secure();
  final invocations = <Map<String, Object?>>[];
  final flowReceipts = <String>[];
  late final flows = ProductionJourneyFlowRunner(output, runner);
  late final File artifact;
  late final String profileId, inputDigest, artifactDigest, physical;
  late final String? emulator;
  @override
  late ProductionJourneyPeer alice, bob;
  @override
  final additionalPeers = <String, ProductionJourneyPeer>{};
  @override
  List<ProductionJourneyPeer> get actors =>
      scenario == 'production.startup_resume_performance'
      ? [alice]
      : [alice, bob, ...additionalPeers.values];
  ProductionAndroidInstallGuard? _guard;
  final artifacts = <String, ProductionAndroidArtifact>{};
  final _guards = <String, ProductionAndroidInstallGuard>{};
  bool get usesProviderReceiver => const {
    'production.notification_open',
    'production.notification_tap_latency',
    'production.notification_sound',
  }.contains(scenario);

  String profileFor(String role) => usesProviderReceiver && role == 'bob'
      ? productionNotificationAndroidProfile
      : profileId;
  String packageFor(String role) => usesProviderReceiver && role == 'bob'
      ? productionNotificationAndroidPackage
      : productionJourneyAndroidPackage;

  ProductionJourneyPeer peer(String device, String role) {
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: profileFor(role),
      scenarioId: scenario,
      role: role,
      runId: runId,
      nonce: List.generate(
        24,
        (_) => _random.nextInt(16).toRadixString(16),
      ).join(),
      values: {'fixtureId': runId},
    );
    invocations.add(invocation.toJson());
    return ProductionJourneyPeer(
      device,
      invocation,
      output,
      runner,
      packageName: packageFor(role),
    );
  }

  @override
  Future<void> prepare() async {
    // B/M/BR measure one independent production node. Other journeys prepare
    // only the peers required by their topology before ordinary UI actions.
    for (final target in actors.map((p) => p.device)) {
      final state = await runner.run('adb', ['-s', target, 'get-state']);
      if (state.exitCode != 0 || '${state.stdout}'.trim() != 'device') {
        throw StateError('pinned target unavailable');
      }
    }
    // Capture every package before mutating either fixture. The provider client
    // uses the repository's production Firebase package only on Bob's emulator.
    for (final prepared in artifacts.values) {
      final peers = actors
          .where((p) => p.invocation.profileId == prepared.profileId)
          .toList();
      final guard = await captureGuard(
        devices: peers.map((p) => p.device).toList(),
        packageName: peers.first.packageName,
        backupLabel: '$runId-${prepared.profileId}',
        preparedArtifact: prepared.file,
        expectedArtifactSha256: prepared.artifactDigest,
      );
      _guards[prepared.profileId] = guard;
      if (prepared.profileId == profileId) _guard = guard;
    }
    for (final p in actors) {
      await _guards[p.invocation.profileId]!.prepareFreshInstall(
        device: p.device,
        artifact: artifacts[p.invocation.profileId]!.file,
      );
      await p.writeAppFile('auto_setup.json', {
        'username': 'Journey${p.invocation.role}',
      });
      await p.writeAppFile(
        'production-journey/runtime-config.json',
        p.invocation.toJson(),
      );
      await p.adb([
        'shell',
        'pm',
        'grant',
        p.packageName,
        'android.permission.POST_NOTIFICATIONS',
      ]);
    }
    for (final p in actors) {
      await p.adb([
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        '${p.packageName}/com.mknoon.app.MainActivity',
      ]);
    }
    for (final p in actors) {
      await p.awaitReady();
    }
    if (actors.length == 1) return;
    final identities = <String, Map<String, Object?>>{};
    for (final actor in actors) {
      identities[actor.invocation.role] = await actor.command('identity');
    }
    for (final actor in actors) {
      for (final entry in identities.entries) {
        if (entry.key != actor.invocation.role) {
          await actor.command('prepare_contact', entry.value);
        }
      }
    }
  }

  Future<ProductionJourneyPeer> stageFreshInvocation(
    ProductionJourneyPeer previous,
  ) async {
    final next = peer(previous.device, previous.invocation.role);
    await next.adb([
      'shell',
      'run-as',
      next.packageName,
      'rm',
      '-f',
      'app_flutter/production-journey/runtime-ack.json',
      'app_flutter/production-journey/command.json',
      'app_flutter/production-journey/command-result.json',
    ]);
    await next.writeAppFile(
      'production-journey/runtime-config.json',
      next.invocation.toJson(),
    );
    return next;
  }

  @override
  Future<ProductionJourneyPeer> reopen(ProductionJourneyPeer previous) async {
    final next = await stageFreshInvocation(previous);
    await flow(
      next,
      'production_reopen_seeded',
      '${next.invocation.role}-reopen',
    );
    await next.awaitReady();
    return next;
  }

  /// Preserve the original benchmark's independently generated cold identities.
  /// The existing guard retains the pre-campaign package snapshot throughout;
  /// only the run-owned disposable fixture is cleared between these samples.
  Future<ProductionJourneyPeer> freshPerformanceSample() async {
    if (scenario != 'production.startup_resume_performance' || _guard == null) {
      throw StateError('fresh performance fixture is not owned');
    }
    final next = peer(physical, 'alice');
    await _guard!.prepareFreshInstall(device: physical, artifact: artifact);
    await next.writeAppFile('auto_setup.json', {'username': 'Journeyalice'});
    await next.writeAppFile(
      'production-journey/runtime-config.json',
      next.invocation.toJson(),
    );
    await next.adb([
      'shell',
      'pm',
      'grant',
      productionJourneyAndroidPackage,
      'android.permission.POST_NOTIFICATIONS',
    ]);
    await flow(next, 'production_resume', 'alice-fresh-performance');
    await next.awaitReady();
    return next;
  }

  @override
  Future<String> flow(
    ProductionJourneyPeer p,
    String name,
    String label, [
    Map<String, String> values = const {},
  ]) async {
    final receipt = await flows.run(
      p.device,
      name,
      label,
      values,
      packageName: p.packageName,
    );
    flowReceipts.add(receipt);
    return receipt;
  }

  /// Abrupt death of only this owned UID preserves a posted native card for the
  /// cold-tap boundary. Force-stop changes that precondition and is unsuitable.
  @override
  Future<void> killOwnedProcess(ProductionJourneyPeer p) async {
    final found = await p.adb(['shell', 'pidof', p.packageName]);
    final pid = '${found.stdout}'.trim();
    if (!RegExp(r'^[0-9]+$').hasMatch(pid)) {
      throw StateError('ambiguous app process');
    }
    final identity = await p.adb([
      'exec-out',
      'run-as',
      p.packageName,
      'cat',
      '/proc/$pid/cmdline',
    ]);
    if ('${identity.stdout}'.split('\u0000').first != p.packageName) {
      throw StateError('process identity changed');
    }
    await p.adb(['shell', 'run-as', p.packageName, 'kill', '-9', pid]);
    await waitForProductionObservation(
      'owned process death',
      const Duration(seconds: 10),
      () async {
        final state = await p.adb([
          'shell',
          'pidof',
          p.packageName,
        ], allowFailure: true);
        return '${state.stdout}'.trim().isEmpty ? true : null;
      },
    );
    await File(
      '${output.path}/${p.invocation.nonce}-process-death.json',
    ).writeAsString(
      jsonEncode({
        'package': p.packageName,
        'verifiedUidKill': true,
        'pid': pid,
      }),
    );
  }

  @override
  Future<void> restore() async {
    if (_guards.isEmpty) return;
    try {
      final failures = <String>[];
      for (final entry in _guards.entries.toList().reversed) {
        try {
          await entry.value.restoreAll();
        } catch (error) {
          failures.add('${entry.key}: $error');
        }
      }
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
      await File('${output.path}/cleanup.json').writeAsString(
        jsonEncode({
          'status': 'PASS',
          'exactRestorationVerified': true,
          'devices': actors.map((p) => p.device).toList(),
          if (!usesProviderReceiver) 'package': productionJourneyAndroidPackage,
          'packagesByDevice': {for (final p in actors) p.device: p.packageName},
        }),
      );
    } catch (error) {
      await File('${output.path}/cleanup.json').writeAsString(
        jsonEncode({
          'status': 'FAIL',
          'exactRestorationVerified': false,
          'detail': '$error',
        }),
      );
      rethrow;
    }
  }

  @override
  Map<String, Object?> provenance() => {
    'scenario': scenario,
    'runId': runId,
    'entrypoint': 'lib/main.dart',
    'profileId': profileId,
    'inputDigest': inputDigest,
    'artifactDigest': artifactDigest,
    'artifacts': artifacts.values.map((a) => a.toJson()).toList(),
    'packagesByRole': {
      for (final p in actors) p.invocation.role: p.packageName,
    },
    'invocations': invocations,
    'flowReceipts': flowReceipts,
    'childBuilds': 0,
  };
}
