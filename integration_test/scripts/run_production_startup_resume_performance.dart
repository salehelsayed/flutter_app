import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_performance_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.startup_resume_performance';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempts = 0;
  try {
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(_scenario, output);
    final cold = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'cold': cold,
      'measurementTarget': journey.physical,
      'intervals': {
        'node': 'production readiness-window totalMs',
        'lifecycle': 'actual paused/resumed observations',
        'wholeApplicationLaunchClaim': false,
      },
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<Map<String, Object?>> snapshot() =>
        journey.alice.command('performance_snapshot');
    bool hasMetric(
      Map<String, Object?> s,
      String event, {
      List<String>? phases,
      int after = 0,
    }) => (s['events'] as List).any(
      (e) =>
          e['event'] == event &&
          e['sequence'] > after &&
          (phases == null || phases.contains(e['details']['phase'])),
    );
    Future<Map<String, Object?>> wait(
      String label,
      Duration timeout,
      bool Function(Map<String, Object?>) predicate,
      Map<String, Object?> times,
      String key,
    ) async {
      final timer = Stopwatch()..start();
      final result = await waitForProductionObservation(
        label,
        timeout,
        () async {
          final s = await snapshot();
          return predicate(s) ? s : null;
        },
      );
      times[key] = timer.elapsedMilliseconds;
      return result;
    }

    Future<Map<String, Object?>> ready(
      String name,
      Map<String, Object?> times, {
      Duration sendableTimeout = const Duration(seconds: 30),
      Duration relayTimeout = const Duration(seconds: 30),
      bool Function(Map<String, Object?>)? observed,
    }) async {
      await wait(
        '$name sendable',
        sendableTimeout,
        (s) => s['sendReady'] == true && s['inboxReady'] == true,
        times,
        'sendableWaitMs',
      );
      return wait(
        '$name relay-ready',
        relayTimeout,
        (s) => s['badge'] == 'onlineDotted' && (observed?.call(s) ?? true),
        times,
        'relayWaitMs',
      );
    }

    try {
      await journey.prepare();
      for (var i = 0; i < 6; i++) {
        if (i > 0) journey.alice = await journey.freshPerformanceSample();
        attempts++;
        final timings = <String, Object?>{};
        final s = await ready(
          'cold-$i',
          timings,
          relayTimeout: const Duration(seconds: 5),
          observed: (s) =>
              hasMetric(s, 'TIME_TO_SENDABLE_BADGE', phases: ['cold_start']),
        );
        cold.add({...s, 'waits': timings});
        await persist();
      }
      for (final name in [
        'hot-node',
        'healthy',
        'degraded',
        'extended',
        'recovery',
        // C-Sim-2: three consecutive foreground relay-loss recoveries.
        'repeated-recovery-1',
        'repeated-recovery-2',
        'repeated-recovery-3',
        // B's core-only return sample runs last: unlike M's full start,
        // it deliberately omits the warm tasks that establish usability.
        'hot-core',
      ]) {
        attempts++;
        final recovery =
            name == 'recovery' || name.startsWith('repeated-recovery-');
        final before = await journey.alice.command('performance_begin', {
          'window': name,
        });
        final window = <String, Object?>{'before': before};
        proof[name] = window;
        await persist();
        final start = (before['events'] as List).length;
        if (name.startsWith('hot-')) {
          final operation = await journey.alice.command(
            'performance_hot_start',
          );
          window['started'] = operation['started'];
          window['operation'] = operation;
          await persist();
          if (name == 'hot-core') {
            window['after'] = operation;
            await persist();
            continue;
          }
          window['after'] = await ready(
            name,
            window,
            sendableTimeout: const Duration(seconds: 10),
            relayTimeout: const Duration(seconds: 10),
            observed: (s) =>
                name == 'hot-core' ||
                hasMetric(
                  s,
                  'TIME_TO_SENDABLE_BADGE',
                  phases: ['hot_restart'],
                  after: start,
                ),
          );
          await persist();
          continue;
        }
        if (name == 'healthy') {
          // Keep Home and resume in one UI session. Starting a second driver
          // prolonged the paused interval enough to observe a real outage.
          await journey.flow(
            journey.alice,
            'production_healthy_resume',
            '$name-home-resume',
          );
          window['background'] = await journey.alice.command(
            'performance_paused_snapshot',
          );
          await persist();
        } else if (!recovery) {
          await journey.flow(
            journey.alice,
            'production_background',
            '$name-background',
          );
          window['background'] = await wait(
            '$name actual paused',
            const Duration(seconds: 5),
            (s) => s['lifecycle'] == 'paused',
            window,
            'backgroundWaitMs',
          );
          await persist();
        }
        if (name == 'degraded' || recovery) {
          final fault = await journey.alice.command(
            'performance_disconnect_relay',
          );
          window['disconnectCount'] = fault['disconnectedRelayCount'];
          window['degraded'] = await wait(
            '$name observed relay loss',
            const Duration(seconds: 15),
            (s) => s['badge'] != 'onlineDotted',
            window,
            'degradeWaitMs',
          );
          await persist();
        }
        if (name == 'extended') {
          await Future<void>.delayed(const Duration(seconds: 30));
        }
        if (recovery) {
          await journey.alice.command('performance_recover');
        } else if (name != 'healthy') {
          await journey.flow(
            journey.alice,
            'production_resume',
            '$name-resume',
          );
        }
        window['after'] = await ready(
          name,
          window,
          observed: (s) {
            if (s['lifecycle'] != 'resumed') return false;
            if (name == 'healthy') {
              return hasMetric(
                s,
                'TIME_TO_ONLINE_BADGE',
                phases: ['background_resume_already_online'],
                after: start,
              );
            }
            return hasMetric(
                  s,
                  'TIME_TO_SENDABLE_BADGE',
                  phases: recovery
                      ? ['recovery']
                      : ['background_resume', 'recovery'],
                  after: start,
                ) ||
                (name == 'extended' &&
                    hasMetric(
                      s,
                      'TIME_TO_ONLINE_BADGE',
                      phases: ['background_resume_already_online'],
                      after: start,
                    ));
          },
        );
        await persist();
      }
      final failures = validateProductionPerformance(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: _scenario,
      validatorIds: ['validateProductionPerformance'],
      payload: {...journey.provenance(), ...proof, 'status': 'PASS'},
    );
  } catch (error, stack) {
    if (output != null) {
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
    }
  }
  final passed = evidence != null;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production startup/resume performance passed' : 'production startup/resume performance failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
