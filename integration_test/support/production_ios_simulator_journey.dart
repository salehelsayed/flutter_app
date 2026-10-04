import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import '../../tool/sims/build_cache.dart';
import '../../tool/sims/build_orchestrator.dart';
import 'android_app_state_guard.dart';
import 'production_android_journey.dart';
import 'production_journey.dart';
import 'production_journey_peer.dart';

const productionJourneyIosSimulatorProfile = 'ios.simulator.app';
const productionJourneyIosBundle = 'com.mknoon.app';

/// Catalog scenarios whose unchanged original oracle requires every role to
/// run on the iOS simulator, with the roles in simulator order (a, b, c, d).
const productionIosSimulatorScenarioRoles = <String, List<String>>{
  'production.group_catalog.private_peer_disconnect_not_removal': [
    'alice',
    'bob',
    'charlie',
  ],
};

/// The prepared `ios.simulator.app` bundle, bound to the executor's digests
/// exactly as [ProductionAndroidArtifact] binds an APK.
final class ProductionIosSimulatorArtifact {
  ProductionIosSimulatorArtifact.fromEnvironment(
    Map<String, String> environment,
  ) {
    String required(String name) {
      final value = environment[name];
      if (value == null || value.isEmpty) throw StateError('missing $name');
      return value;
    }

    bundle = Directory(required('SIMS_ARTIFACT_IOS_SIMULATOR_APP')).absolute;
    inputDigest = required('SIMS_ARTIFACT_INPUT_DIGEST');
    artifactDigest = required('SIMS_ARTIFACT_SHA256');
    final cacheRoot = environment['SIMS_CACHE_DIR']?.trim();
    final expected = Directory(
      '${cacheRoot == null || cacheRoot.isEmpty ? 'build/sims/cache' : cacheRoot}'
      '/$productionJourneyIosSimulatorProfile/$inputDigest/Runner.app',
    ).absolute;
    final attestation = BuildAttestation.fromJson(
      Map<String, Object?>.from(
        jsonDecode(
              File('${bundle.parent.path}/attestation.json').readAsStringSync(),
            )
            as Map,
      ),
    );
    if (bundle.path != expected.path ||
        Directory(attestation.artifactPath).absolute.path != bundle.path ||
        attestation.schemaVersion != 1 ||
        attestation.profileId != productionJourneyIosSimulatorProfile ||
        attestation.inputDigest != inputDigest ||
        attestation.artifactDigest != artifactDigest ||
        sha256.convert(simsPreparedArtifactDigestBytes(bundle)).toString() !=
            artifactDigest) {
      throw StateError(
        'prepared simulator artifact identity rejected; no fallback build',
      );
    }
  }

  late final Directory bundle;
  late final String inputDigest, artifactDigest;

  Map<String, Object?> toJson() => {
    'profileId': productionJourneyIosSimulatorProfile,
    'inputDigest': inputDigest,
    'artifactDigest': artifactDigest,
  };
}

/// Host-owned installation, invocation and cleanup of the production app on
/// pinned iOS simulators, one per role. Production main constructs the whole
/// application; this helper never builds or supplies application services,
/// never drives the UI itself and never declares a scenario passed. Every
/// pinned simulator must be explicitly authorized as disposable
/// (`SIMS_IOS_DISPOSABLE_SIMULATOR_IDS`): the app is reinstalled on it.
final class ProductionIosSimulatorJourney implements ProductionJourney {
  ProductionIosSimulatorJourney.fromEnvironment(
    this.scenario,
    this.output, {
    Map<String, String>? environment,
    AndroidHostProcessRunner? runner,
  }) : runner = runner ?? const SystemAndroidHostProcessRunner() {
    final values = environment ?? Platform.environment;
    String required(String name) {
      final value = values[name];
      if (value == null || value.isEmpty) throw StateError('missing $name');
      return value;
    }

    final roles = productionIosSimulatorScenarioRoles[scenario];
    if (roles == null || roles.length < 2 || roles.length > 4) {
      throw StateError('scenario has no iOS simulator topology');
    }
    artifact = ProductionIosSimulatorArtifact.fromEnvironment(values);
    final disposable = {
      for (final id
          in (values['SIMS_IOS_DISPOSABLE_SIMULATOR_IDS'] ?? '').split(','))
        if (id.trim().isNotEmpty) id.trim().toUpperCase(),
    };
    final devices = <String>[];
    for (var i = 0; i < roles.length; i++) {
      final device = required(
        'SIMS_IOS_SIMULATOR_${'ABCD'[i]}_DEVICE_ID',
      ).toUpperCase();
      if (!disposable.contains(device) || devices.contains(device)) {
        throw StateError(
          'each role needs a distinct simulator authorized as disposable',
        );
      }
      devices.add(device);
    }
    alice = peer(devices[0], roles[0]);
    bob = peer(devices[1], roles[1]);
    for (var i = 2; i < roles.length; i++) {
      additionalPeers[roles[i]] = peer(devices[i], roles[i]);
    }
  }

  @override
  final String scenario;
  final Directory output;
  @override
  final String runId = 'journey-${DateTime.now().microsecondsSinceEpoch}';
  @override
  final AndroidHostProcessRunner runner;
  final _random = Random.secure();
  final invocations = <Map<String, Object?>>[];
  final flowReceipts = <String>[];
  late final flows = ProductionJourneyFlowRunner(output, runner);
  late final ProductionIosSimulatorArtifact artifact;
  @override
  late ProductionJourneyPeer alice, bob;
  @override
  final additionalPeers = <String, ProductionJourneyPeer>{};
  @override
  List<ProductionJourneyPeer> get actors => [
    alice,
    bob,
    ...additionalPeers.values,
  ];
  bool _installed = false;

  ProductionJourneyPeer peer(String device, String role) {
    final invocation = SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: productionJourneyIosSimulatorProfile,
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
      packageName: productionJourneyIosBundle,
    );
  }

  @override
  Future<void> prepare() async {
    for (final p in actors) {
      // Boots the simulator if needed and waits until it is usable.
      await p.simctl(['bootstatus', p.device, '-b']);
      // Keyboards autocorrect original proof texts; this simulator types
      // them verbatim.
      for (final key in const [
        'KeyboardAutocorrection',
        'KeyboardPrediction',
        'KeyboardAutocapitalization',
        'KeyboardCheckSpelling',
      ]) {
        await p.simctl([
          'spawn',
          p.device,
          'defaults',
          'write',
          'com.apple.Preferences',
          key,
          '-bool',
          'NO',
        ]);
      }
      await p.simctl([
        'terminate',
        p.device,
        p.packageName,
      ], allowFailure: true);
      await p.simctl([
        'uninstall',
        p.device,
        p.packageName,
      ], allowFailure: true);
      await p.simctl(['install', p.device, artifact.bundle.path]);
      _installed = true;
      p.forgetContainer();
      await p.writeAppFile('auto_setup.json', {
        'username': 'Journey${p.invocation.role}',
      });
      await p.writeAppFile(
        'production-journey/runtime-config.json',
        p.invocation.toJson(),
      );
    }
    for (final p in actors) {
      await p.simctl(['launch', p.device, p.packageName]);
      await flow(
        p,
        'production_ios_allow_notifications',
        '${p.invocation.role}-ios-permissions',
      );
    }
    for (final p in actors) {
      await p.awaitReady();
    }
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

  @override
  Future<ProductionJourneyPeer> reopen(ProductionJourneyPeer previous) async {
    final next = peer(previous.device, previous.invocation.role);
    final journeyDirectory = Directory(
      '${await next.dataContainer()}/Documents/production-journey',
    );
    for (final name in const [
      'runtime-ack.json',
      'command.json',
      'command-result.json',
    ]) {
      final file = File('${journeyDirectory.path}/$name');
      if (file.existsSync()) await file.delete();
    }
    await next.writeAppFile(
      'production-journey/runtime-config.json',
      next.invocation.toJson(),
    );
    // An ordinary relaunch of the same install, as from the Home screen.
    await next.simctl([
      'terminate',
      next.device,
      next.packageName,
    ], allowFailure: true);
    await next.simctl(['launch', next.device, next.packageName]);
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

  /// Verified death of only this app's process on its simulator.
  @override
  Future<void> killOwnedProcess(ProductionJourneyPeer p) async {
    final pid = await _appPid(p);
    if (pid == null) throw StateError('app process not running');
    await p.simctl(['spawn', p.device, 'kill', '-9', pid]);
    await waitForProductionObservation(
      'owned process death',
      const Duration(seconds: 10),
      () async => await _appPid(p) == null ? true : null,
    );
    await File(
      '${output.path}/${p.invocation.nonce}-process-death.json',
    ).writeAsString(
      jsonEncode({
        'bundle': p.packageName,
        'device': p.device,
        'verifiedKill': true,
        'pid': pid,
      }),
    );
  }

  /// The app's pid from the simulator's launchd, or null when not running.
  Future<String?> _appPid(ProductionJourneyPeer p) async {
    final list = await p.simctl(['spawn', p.device, 'launchctl', 'list']);
    for (final line in '${list.stdout}'.split('\n')) {
      final fields = line.trim().split(RegExp(r'\s+'));
      if (fields.length == 3 &&
          fields[2].startsWith('UIKitApplication:${p.packageName}[') &&
          RegExp(r'^[0-9]+$').hasMatch(fields[0])) {
        return fields[0];
      }
    }
    return null;
  }

  @override
  Future<void> restore() async {
    if (!_installed) return;
    final failures = <String>[];
    for (final p in actors) {
      await p.simctl([
        'terminate',
        p.device,
        p.packageName,
      ], allowFailure: true);
      final removed = await p.simctl([
        'uninstall',
        p.device,
        p.packageName,
      ], allowFailure: true);
      if (removed.exitCode != 0) failures.add(p.device);
    }
    await File('${output.path}/cleanup.json').writeAsString(
      jsonEncode({
        'status': failures.isEmpty ? 'PASS' : 'FAIL',
        'disposableSimulatorsCleared': failures.isEmpty,
        'devices': actors.map((p) => p.device).toList(),
        'bundle': productionJourneyIosBundle,
        if (failures.isNotEmpty) 'failedDevices': failures,
      }),
    );
    if (failures.isNotEmpty) {
      throw StateError('simulator cleanup failed: ${failures.join(', ')}');
    }
  }

  @override
  Map<String, Object?> provenance() => {
    'scenario': scenario,
    'runId': runId,
    'entrypoint': 'lib/main.dart',
    'profileId': productionJourneyIosSimulatorProfile,
    'inputDigest': artifact.inputDigest,
    'artifactDigest': artifact.artifactDigest,
    'artifacts': [artifact.toJson()],
    'packagesByRole': {
      for (final p in actors) p.invocation.role: p.packageName,
    },
    'invocations': invocations,
    'flowReceipts': flowReceipts,
    'childBuilds': 0,
  };
}
