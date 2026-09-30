import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/build_cache.dart';
import '../../tool/sims/production_foreground_push_criteria.dart';
import '../support/android_app_state_guard.dart';

const _scenario = 'production.foreground_group_push';
const _profile = 'android.e2e.main';
const _package = 'com.mknoon.sims.connectivity';
const _validator = 'validateProductionForegroundPush';

Map<String, Object?> _object(Object? value) =>
    (value as Map).map((key, value) => MapEntry('$key', value));

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  final watch = Stopwatch()..start();
  var attempts = 0;
  SimsArtifactEvidence? evidence;
  String? failure;
  Directory? attemptDirectory;
  try {
    final proofPath = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (proofPath == null || proofPath.isEmpty) {
      throw StateError('missing SIMS_PROOF_DIRECTORY');
    }
    final proofRoot = Directory(proofPath).absolute;
    await proofRoot.create(recursive: true);
    attemptDirectory = await proofRoot.createTemp('attempt-');
    final campaign = _Campaign.fromEnvironment(attemptDirectory);
    evidence = await campaign.run(() => attempts++);
  } catch (error, stack) {
    failure = 'production foreground push campaign failed';
    if (attemptDirectory != null) {
      final file = File('${attemptDirectory.path}/first-failure.txt');
      await file.parent.create(recursive: true);
      await file.writeAsString('${error.runtimeType}\n$error\n$stack');
    }
  }
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({'status': failure == null ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': evidence != null, 'printOnly': false, 'exitCode': failure == null ? 0 : 1, 'detail': failure ?? 'S1/S2/S3 production bootstrap foreground push assertions passed', 'elapsedMs': watch.elapsedMilliseconds, if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = failure == null ? 0 : 1;
}

final class _Campaign {
  _Campaign(
    this.artifact,
    this.inputDigest,
    this.artifactDigest,
    this.physical,
    this.emulator,
    this.output,
  );

  factory _Campaign.fromEnvironment(Directory output) {
    String required(String name) {
      final value = Platform.environment[name];
      if (value == null || value.isEmpty) {
        throw StateError('missing $name; no fallback build');
      }
      return value;
    }

    final artifact = File(required('SIMS_ARTIFACT_ANDROID_E2E_MAIN')).absolute;
    final input = required('SIMS_ARTIFACT_INPUT_DIGEST');
    final digest = required('SIMS_ARTIFACT_SHA256');
    final attestation = BuildAttestation.fromJson(
      _object(
        jsonDecode(
          File('${artifact.parent.path}/attestation.json').readAsStringSync(),
        ),
      ),
    );
    if (attestation.schemaVersion != 1 ||
        attestation.profileId != _profile ||
        attestation.inputDigest != input ||
        attestation.artifactDigest != digest ||
        sha256.convert(artifact.readAsBytesSync()).toString() != digest) {
      throw StateError('prepared artifact or input digest mismatch');
    }
    final physical = required('SIMS_ANDROID_PHYSICAL_DEVICE_ID');
    final emulator = required('SIMS_ANDROID_EMULATOR_DEVICE_ID');
    if (!RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(physical) ||
        physical.startsWith('emulator-') ||
        !RegExp(r'^emulator-[0-9]+$').hasMatch(emulator)) {
      throw StateError('one physical Android and one emulator must be pinned');
    }
    return _Campaign(artifact, input, digest, physical, emulator, output);
  }

  final File artifact;
  final String inputDigest, artifactDigest, physical, emulator;
  final Directory output;
  final runner = const SystemAndroidHostProcessRunner();

  Future<Directory> runFlow({
    required _Peer peer,
    required String name,
    required String label,
    Map<String, String> values = const {},
  }) async {
    final destination = Directory('${output.path}/$label-maestro');
    final result = await runner.run('python3', [
      'scripts/maestro_flow_runner.py',
      '--device',
      peer.device,
      '--flow',
      'integration_test/maestro/$name.yaml',
      '--expected-name',
      name,
      '--output',
      destination.path,
      '--env',
      'APP_ID=$_package',
      for (final value in values.entries) ...[
        '--env',
        '${value.key}=${value.value}',
      ],
    ]);
    if (result.exitCode != 0) throw StateError('$label Maestro flow failed');
    return destination;
  }

  Future<SimsArtifactEvidence> run(void Function() attempt) async {
    await output.create(recursive: true);
    for (final target in [physical, emulator]) {
      final result = await runner.run('adb', ['-s', target, 'get-state']);
      if (result.exitCode != 0 || '${result.stdout}'.trim() != 'device') {
        throw StateError('pinned target unavailable');
      }
    }
    final runId = 'fgpush-${DateTime.now().microsecondsSinceEpoch}';
    final random = Random.secure();
    SimsRuntimeInvocation invocation(String role) => SimsRuntimeInvocation(
      schema: simsRuntimeConfigSchema,
      profileId: _profile,
      scenarioId: _scenario,
      role: role,
      runId: runId,
      nonce: List.generate(
        24,
        (_) => random.nextInt(16).toRadixString(16),
      ).join(),
      values: {'fixtureId': runId},
    );
    var alice = _Peer(physical, invocation('alice'), output, runner);
    var bob = _Peer(emulator, invocation('bob'), output, runner);
    final setupInvocations = [
      alice.invocation.toJson(),
      bob.invocation.toJson(),
    ];
    final setupFlowReceipts = <String>[];
    final setup = Stopwatch()..start();
    final guard = await AndroidAppStateGuard.capture(
      devices: [physical, emulator],
      packageName: _package,
      backupLabel: runId,
      preparedArtifact: artifact,
      expectedArtifactSha256: artifactDigest,
    );
    final cases = <Map<String, Object?>>[];
    late int scenarioMs;
    try {
      // Both use the same centrally verified artifact; preparation precedes all
      // timed peer/scenario waits. There is no Flutter/Gradle/Xcode invocation.
      for (final peer in [alice, bob]) {
        await guard.prepareFreshInstall(
          device: peer.device,
          artifact: artifact,
        );
        await peer.writeAppFile('auto_setup.json', {
          'username': 'FgPush${peer.invocation.role}',
        });
        await peer.writeAppFile(
          'production-journey/runtime-config.json',
          peer.invocation.toJson(),
        );
        await peer.adb([
          'shell',
          'pm',
          'grant',
          _package,
          'android.permission.POST_NOTIFICATIONS',
        ]);
      }
      for (final peer in [alice, bob]) {
        await peer.adb([
          'shell',
          'am',
          'start',
          '-W',
          '-n',
          '$_package/com.mknoon.app.MainActivity',
        ]);
      }
      for (final peer in [alice, bob]) {
        await peer.awaitReady();
      }
      final a = await alice.command('identity');
      final b = await bob.command('identity');
      await alice.command('prepare_contact', b);
      await bob.command('prepare_contact', a);
      final fixture = await alice.command('prepare_group', {
        'peerId': b['peerId'],
      });
      final group = _object(fixture['group']);
      final groupId = group['id']! as String;
      await bob.command('import_group', fixture);
      await alice.command('mark_fixture_joined', {
        'groupId': groupId,
        'peerId': b['peerId'],
        'username': b['username'],
      });
      // Fixture seeding happens after the first startup decision. Reopen through
      // the normal UI lifecycle so production routing reads the persisted
      // contacts. Every new process gets a fresh nonce on the SAME artifact.
      Future<_Peer> stageReopen(_Peer previous) async {
        final next = _Peer(
          previous.device,
          invocation(previous.invocation.role),
          output,
          runner,
        );
        await next.adb([
          'shell',
          'run-as',
          _package,
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

      final probePath =
          Platform.environment['PRODUCTION_JOURNEY_UI_PROBE_DIRECTORY'];
      if (probePath != null) {
        // Diagnostic handoff only: the existing guard owns fixture setup and
        // restoration while Appium MCP owns all UI actions. This branch cannot
        // produce a passing scenario and never changes acceptance deadlines.
        final probe = Directory(probePath);
        if (!probe.existsSync() || probe.listSync().isNotEmpty) {
          throw StateError('UI probe requires a fresh existing directory');
        }
        alice = await stageReopen(alice);
        bob = await stageReopen(bob);
        await File('${probe.path}/ready.json').writeAsString(
          jsonEncode({
            'runId': runId,
            'groupId': groupId,
            'package': _package,
            'devices': [physical, emulator],
            'artifactDigest': artifactDigest,
            'scenarioComplete': false,
          }),
        );
        await _wait<bool>(
          'explicit UI probe release',
          const Duration(minutes: 10),
          () async {
            final release = File('${probe.path}/release.json');
            if (!await release.exists()) return null;
            final value = _object(jsonDecode(await release.readAsString()));
            return value['runId'] == runId && value['release'] == true
                ? true
                : null;
          },
        );
        throw StateError('Diagnostic UI probe ended; no scenario was executed');
      }

      Future<_Peer> reopen(_Peer previous) async {
        final next = await stageReopen(previous);
        final receipt = await runFlow(
          peer: next,
          name: 'production_reopen_seeded',
          label: '${next.invocation.role}-reopen',
        );
        setupFlowReceipts.add('${receipt.path}/result.json');
        await next.awaitReady();
        await next.command('adopt_prepared_group', {'groupId': groupId});
        final rejoin = await next.command('rejoin_topics');
        if (rejoin['errorCount'] != 0 ||
            (rejoin['joinedGroupCount'] as int) < 1) {
          throw StateError('${next.invocation.role} fixture rejoin failed');
        }
        return next;
      }

      alice = await reopen(alice);
      bob = await reopen(bob);
      await Future<void>.delayed(const Duration(seconds: 5));
      setup.stop();
      final scenarios = Stopwatch()..start();

      Future<Map<String, Object?>> snapshot(_Peer peer) =>
          peer.command('snapshot', {'groupId': groupId});
      Future<Map<String, Object?>> send(String id) async {
        final text = '$id production foreground push $runId';
        final flowOutput = await runFlow(
          peer: alice,
          name: 'production_group_send',
          label: '$runId-$id',
          values: {
            'GROUP_ID': groupId,
            'MESSAGE': text,
            'MESSAGE_PATTERN': RegExp.escape(text),
          },
        );
        final sent = await _wait<Map<String, Object?>>(
          'sender exact message',
          const Duration(seconds: 30),
          () async {
            final rows = (await snapshot(alice))['messages'] as List;
            final matches = rows
                .cast<Map>()
                .where((row) => row['text'] == text && row['incoming'] == false)
                .toList();
            return matches.length == 1 ? _object(matches.single) : null;
          },
        );
        return {
          'messageId': sent['id'],
          'sentText': text,
          'maestroReceipt': '${flowOutput.path}/result.json',
        };
      }

      attempt();
      final s1Baseline = (await snapshot(bob))['notifications'] as List;
      final s1Gap = await bob.command('leave_topic', {'groupId': groupId});
      if (s1Gap['leftTopic'] != groupId ||
          s1Gap['competingRecoveryHeld'] != true) {
        throw StateError('S1 missed-live fixture was not established');
      }
      await Future<void>.delayed(const Duration(seconds: 8));
      final s1 = await send('S1');
      await Future<void>.delayed(const Duration(seconds: 4));
      final s1Before = await snapshot(bob);
      if ((s1Before['messages'] as List).cast<Map>().any(
        (row) => row['id'] == s1['messageId'],
      )) {
        throw StateError('S1 did not miss live delivery before push');
      }
      await bob.command('foreground_push', {
        'groupId': groupId,
        'messageId': s1['messageId'],
      });
      final s1After = await bob.awaitMessage(
        groupId,
        s1['messageId']! as String,
      );
      cases.add({
        'id': 'S1',
        ...s1,
        'groupId': groupId,
        'notificationBaseline': s1Baseline.length,
        'liveGapFixture': s1Gap,
        'before': s1Before,
        'after': s1After,
      });

      attempt();
      final rejoin = await bob.command('rejoin_topics');
      if (rejoin['errorCount'] != 0 ||
          (rejoin['joinedGroupCount'] as int) < 1) {
        throw StateError('S2 rejoin failed');
      }
      await Future<void>.delayed(const Duration(seconds: 8));
      final s2Baseline = (await snapshot(bob))['notifications'] as List;
      final s2 = await send('S2');
      final s2Before = await bob.awaitMessage(
        groupId,
        s2['messageId']! as String,
        notificationCount: s2Baseline.length + 1,
      );
      await bob.command('foreground_push', {
        'groupId': groupId,
        'messageId': s2['messageId'],
      });
      await Future<void>.delayed(const Duration(seconds: 4));
      cases.add({
        'id': 'S2',
        ...s2,
        'groupId': groupId,
        'notificationBaseline': s2Baseline.length,
        'before': s2Before,
        'after': await snapshot(bob),
      });

      attempt();
      final s3Before = (await snapshot(bob))['notifications'];
      final s3 = await bob.command('foreground_push', {
        'groupId': 'missing-$runId',
        'messageId': 'msg-s3-non-current',
        'failMissingGroupDrain': true,
      });
      cases.add({
        'id': 'S3',
        'outcome': s3,
        'notificationsBefore': s3Before,
        'notificationsAfter': (await snapshot(bob))['notifications'],
      });
      scenarioMs = scenarios.elapsedMilliseconds;
      final failures = validateProductionForegroundPush({'cases': cases});
      await File(
        '${output.path}/$runId-observations.json',
      ).writeAsString(jsonEncode({'cases': cases, 'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } catch (error, stack) {
      await File(
        '${output.path}/scenario-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      // Existing guard restores only this run's package/files and original APK.
      try {
        await guard.restoreAll();
        await File('${output.path}/cleanup.json').writeAsString(
          jsonEncode({
            'status': 'PASS',
            'exactRestorationVerified': true,
            'devices': [physical, emulator],
            'package': _package,
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
    return writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: _scenario,
      validatorIds: [_validator],
      payload: {
        'scenario': _scenario,
        'runId': runId,
        'entrypoint': 'lib/main.dart',
        'profileId': _profile,
        'inputDigest': inputDigest,
        'artifactDigest': artifactDigest,
        'invocations': [alice.invocation.toJson(), bob.invocation.toJson()],
        'setupInvocations': setupInvocations,
        'setupFlowReceipts': setupFlowReceipts,
        'cases': cases,
        'setupMs': setup.elapsedMilliseconds,
        'scenarioMs': scenarioMs,
        'childBuilds': 0,
        'status': 'PASS',
      },
    );
  }
}

final class _Peer {
  _Peer(this.device, this.invocation, this.output, this.runner);
  final String device;
  final SimsRuntimeInvocation invocation;
  final Directory output;
  final SystemAndroidHostProcessRunner runner;
  int sequence = 0;

  Future<ProcessResult> adb(
    List<String> args, {
    bool allowFailure = false,
  }) async {
    final result = await runner.run('adb', ['-s', device, ...args]);
    if (result.exitCode != 0 && !allowFailure) {
      throw StateError('ADB operation failed: ${args.take(2).join(' ')}');
    }
    return result;
  }

  Future<void> writeAppFile(String name, Map<String, Object?> value) async {
    final local = File(
      '${output.path}/${invocation.role}-${invocation.nonce}-${name.replaceAll('/', '-')}.staging',
    );
    await local.writeAsString(jsonEncode(value));
    final remote = '/data/local/tmp/${invocation.nonce}.json';
    await adb(['push', local.path, remote]);
    try {
      await adb([
        'shell',
        'run-as',
        _package,
        'mkdir',
        '-p',
        'app_flutter/production-journey',
      ]);
      await adb([
        'shell',
        'run-as',
        _package,
        'cp',
        remote,
        'app_flutter/$name.tmp',
      ]);
      await adb([
        'shell',
        'run-as',
        _package,
        'mv',
        'app_flutter/$name.tmp',
        'app_flutter/$name',
      ]);
    } finally {
      await adb(['shell', 'rm', '-f', remote], allowFailure: true);
    }
  }

  Future<Map<String, Object?>?> readAppFile(String name) async {
    final result = await adb([
      'exec-out',
      'run-as',
      _package,
      'cat',
      'app_flutter/production-journey/$name',
    ], allowFailure: true);
    if (result.exitCode != 0) return null;
    try {
      return _object(jsonDecode('${result.stdout}'));
    } on FormatException {
      return null;
    }
  }

  Future<void> awaitReady() async {
    final ack = await _wait(
      'runtime acknowledgement',
      const Duration(minutes: 5),
      () => readAppFile('runtime-ack.json'),
    );
    if (!validateSimsRuntimeAck(ack, invocation).accepted) {
      throw StateError('runtime acknowledgement rejected');
    }
    await _wait(
      'production runtime readiness',
      const Duration(seconds: 60),
      () async {
        final ready = await command('readiness');
        return ready['productionRuntimeReady'] == true &&
                ready['foregroundPushBound'] == true
            ? ready
            : null;
      },
    );
    await _wait(
      'production online readiness',
      const Duration(seconds: 60),
      () async {
        final identity = await command('identity');
        return identity['online'] == true ? identity : null;
      },
    );
  }

  Future<Map<String, Object?>> command(
    String operation, [
    Map<String, Object?> args = const {},
  ]) async {
    final number = ++sequence;
    await writeAppFile('production-journey/command.json', {
      'invocation': invocation.toJson(),
      'sequence': number,
      'operation': operation,
      'arguments': args,
    });
    final receipt = await _wait(
      'command $operation',
      const Duration(seconds: 60),
      () async {
        final value = await readAppFile('command-result.json');
        if (value == null || value['sequence'] != number) return null;
        final identity = SimsRuntimeInvocation.fromJson(
          _object(value['invocation']),
        );
        if (!validateSimsRuntimeAck(
              SimsRuntimeAck.accept(identity).toJson(),
              invocation,
            ).accepted ||
            value['operation'] != operation) {
          throw StateError('stale command receipt');
        }
        return value;
      },
    );
    await File(
      '${output.path}/${invocation.role}-${invocation.nonce}-$number-$operation.json',
    ).writeAsString(jsonEncode(receipt));
    if (receipt['ok'] != true) {
      throw StateError('production command failed: $operation');
    }
    return _object(receipt['result']);
  }

  Future<Map<String, Object?>> awaitMessage(
    String group,
    String message, {
    int? notificationCount,
  }) => _wait('exact incoming message', const Duration(seconds: 30), () async {
    final value = await command('snapshot', {'groupId': group});
    final rows = (value['messages'] as List).cast<Map>();
    final present = rows.any(
      (row) => row['id'] == message && row['incoming'] == true,
    );
    return present &&
            (notificationCount == null ||
                (value['notifications'] as List).length >= notificationCount)
        ? value
        : null;
  });
}

Future<T> _wait<T>(
  String label,
  Duration timeout,
  Future<T?> Function() read,
) async {
  final elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    final value = await read();
    if (elapsed.elapsed >= timeout) break;
    if (value != null) return value;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException(label, timeout);
}
