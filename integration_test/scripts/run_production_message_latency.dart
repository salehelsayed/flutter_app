import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_message_latency_criteria.dart';
import '../support/production_android_journey.dart';

const _scenario = 'production.message_latency';
Map<String, Object?> _object(Object? v) => Map<String, Object?>.from(v as Map);

/// Production main owns all services; this runner owns the original send
/// sequences, pacing and receipts. Alice (physical phone) sends; Bob
/// (emulator) receives and plays the originals' CLI-peer roles (leaving
/// rendezvous, stopping and restarting his node).
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
    final cases = <String, Object?>{};
    final proof = <String, Object?>{
      'runId': journey.runId,
      'interval': productionMessageLatencyInterval,
      'notReproduced': productionMessageLatencyNotReproduced,
      'cases': cases,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    try {
      await journey.prepare();
      final a = await journey.alice.command('identity'),
          b = await journey.bob.command('identity');
      final bob = b['peerId']! as String;
      proof['peers'] = {'alice': a['peerId'], 'bob': bob};
      // The routing journey's two-member group fixture (GP's original creates
      // a group with its single CLI member and waits until it joined).
      final fixture = await journey.alice.command('prepare_group', {
        'peerId': bob,
      });
      final group = _object(fixture['group'])['id']! as String;
      await journey.bob.command('import_group', fixture);
      await journey.alice.command('mark_fixture_joined', {
        'groupId': group,
        'peerId': bob,
        'username': b['username'],
      });
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      for (final p in [journey.alice, journey.bob]) {
        await p.command('adopt_prepared_group', {'groupId': group});
      }
      await Future<void>.delayed(const Duration(seconds: 5));

      Map<String, Object?> start(String name) {
        attempts++;
        final record = <String, Object?>{'sends': <Map<String, Object?>>[]};
        cases[name] = record;
        return record;
      }

      List<Map<String, Object?>> sends(Map<String, Object?> r) =>
          r['sends']! as List<Map<String, Object?>>;
      Future<void> direct(
        Map<String, Object?> record,
        String name,
        int index, {
        required String peerId,
        bool cold = false,
      }) async {
        sends(record).add(
          await journey.alice.command('latency_send', {
            'case': name,
            'index': index,
            'peerId': peerId,
            'cold': cold,
          }),
        );
        await persist();
      }

      const second = Duration(seconds: 1);

      // A-Sim-1: five sends, split cold/warm by connectionReused.
      var r = start('A-Sim-1');
      for (var i = 1; i <= 5; i++) {
        await direct(r, 'A-Sim-1', i, peerId: bob);
      }
      r['coldStats'] = productionLatencyStats(
        sends(r),
        where: (d) => d['connectionReused'] != true,
      );
      r['warmStats'] = productionLatencyStats(
        sends(r),
        where: (d) => d['connectionReused'] == true,
      );

      // A-Sim-2: one warmup, wait one second, ten sequential sends.
      r = start('A-Sim-2');
      await direct(r, 'A-Sim-2', 0, peerId: bob);
      await Future<void>.delayed(second);
      for (var i = 1; i <= 10; i++) {
        await direct(r, 'A-Sim-2', i, peerId: bob);
      }
      r['stats'] = productionLatencyStats(sends(r).skip(1).toList());

      // A-Sim-3 / R-Sim-4 / R-Sim-5: a real but never-online peer.
      final unreachable =
          (await journey.alice.command(
                'latency_unreachable_contact',
              ))['peerId']!
              as String;
      r = start('A-Sim-3');
      await direct(r, 'A-Sim-3', 1, peerId: unreachable);

      // R-Sim-1: one cold send, one second, five warm.
      r = start('R-Sim-1');
      await direct(r, 'R-Sim-1', 1, peerId: bob, cold: true);
      await Future<void>.delayed(second);
      for (var i = 2; i <= 6; i++) {
        await direct(r, 'R-Sim-1', i, peerId: bob);
      }
      r['warmStats'] = productionLatencyStats(sends(r).skip(1).toList());

      // R-Sim-2d: a cold send after a connection drop. The original R-Sim-2
      // uses a fresh identity per run; this is a different, named interval.
      r = start('R-Sim-2d');
      await direct(r, 'R-Sim-2d', 1, peerId: bob, cold: true);

      // R-Sim-3: the receiver stays online but leaves rendezvous.
      r = start('R-Sim-3');
      r['unregister'] = await journey.bob.command('latency_rendezvous', {
        'operation': 'unregister',
      });
      await direct(r, 'R-Sim-3', 1, peerId: bob, cold: true);
      r['register'] = await journey.bob.command('latency_rendezvous', {
        'operation': 'register',
      });
      await persist();

      r = start('R-Sim-4');
      await direct(r, 'R-Sim-4', 1, peerId: unreachable);
      r = start('R-Sim-5');
      final wall = Stopwatch()..start();
      await direct(r, 'R-Sim-5', 1, peerId: unreachable);
      r['wallMs'] = wall.elapsedMilliseconds;

      // GP: five group publishes to the two-member group.
      r = start('GP');
      for (var i = 1; i <= 5; i++) {
        sends(r).add(
          await journey.alice.command('latency_group_send', {
            'groupId': group,
            'index': i,
          }),
        );
        await persist();
      }
      r['stats'] = productionLatencyStats(sends(r));

      // R-Sim-7: cold, five warm, receiver offline, reconnect, three warm.
      r = start('R-Sim-7');
      await direct(r, 'R-Sim-7', 1, peerId: bob, cold: true);
      await Future<void>.delayed(second);
      for (var i = 2; i <= 6; i++) {
        await direct(r, 'R-Sim-7', i, peerId: bob);
      }
      r['stop'] = await journey.bob.command('latency_node', {
        'operation': 'stop',
      });
      await direct(r, 'R-Sim-7', 7, peerId: bob);
      r['start'] = await journey.bob.command('latency_node', {
        'operation': 'start',
      });
      await Future<void>.delayed(const Duration(seconds: 5));
      for (var i = 8; i <= 11; i++) {
        await direct(r, 'R-Sim-7', i, peerId: bob);
      }
      await persist();

      final failures = validateProductionMessageLatency(proof);
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
      validatorIds: ['validateProductionMessageLatency'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production message latency passed' : 'production message latency failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
