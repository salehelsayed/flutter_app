import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_direct_sender_offline_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionDirectSenderOffline);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError('this scenario requires a disposable emulator pair');
    }
    final destination = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (destination == null || destination.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      destination,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      directSenderOfflineRuntime,
      output,
    );
    final ui = <String, Object?>{};
    final phases = <String, Object?>{};
    final kills = <String, Object?>{};
    final nonces = <String, List<String>>{};
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': directSenderOfflineRuntime,
      'emulatorPair': journey.disposableAndroidJourneys,
      'ui': ui,
      'phases': phases,
      'ownedKills': kills,
      'nonces': nonces,
      'scope':
          'ordinary-text staged-custody automatic recovery after stopped production node; not OS airplane mode or an envelope-less terminal Retry row',
    };
    ProductionJourneyPeer actor(String role) =>
        role == 'alice' ? journey.alice : journey.bob;
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<void> flow(
      String role,
      String name,
      String label,
      Map<String, String> values,
    ) async {
      attempted++;
      final path = await journey.flow(actor(role), name, label, values);
      ui[label] = {
        'path': path,
        'flow': name,
        'values': values,
        'receipt': jsonDecode(await File(path).readAsString()),
      };
      await persist();
    }

    var firstFailureRecorded = false;
    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      final peers = {
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      for (final role in ['alice', 'bob']) {
        nonces[role] = [actor(role).invocation.nonce];
        await flow(role, 'production_direct_open', 'open-$role', {
          'PEER_ID': peers[role == 'alice' ? 'bob' : 'alice']!,
        });
      }
      Future<Map<String, Object?>> snapshot(String role) async {
        final peer = actor(role);
        final value = await peer.command('routing_snapshot', {
          'peerIds': [peers[role == 'alice' ? 'bob' : 'alice']],
          'groupIds': <String>[],
        });
        return {
          ...value,
          'observedRole': role,
          'observedRunId': peer.invocation.runId,
          'observedNonce': peer.invocation.nonce,
        };
      }

      proof['stop'] = await journey.alice.command('routing_node_control', {
        'operation': 'stop',
      });
      await persist();
      final stopped = await snapshot('alice');
      if ((stopped['node'] as Map)['isStarted'] != false ||
          (stopped['messages'] as List).isNotEmpty) {
        throw StateError(
          'offline/empty-fixture prerequisite absent; no offline product verdict',
        );
      }
      final text = directSenderOfflineText(journey.runId);
      final pattern = RegExp.escape(text);
      await flow('alice', 'production_direct_send_checkpoint', 'send-offline', {
        'MESSAGE': text,
        'MESSAGE_PATTERN': pattern,
      });
      await flow('alice', 'production_direct_assert_action', 'offline-ui', {
        'VISIBLE_PATTERN': '$pattern.*Message status: sending',
        'ABSENT_PATTERN': '$pattern.*(?:Message status: failed|Retry)',
      });
      final actualFailed = await waitForProductionObservation(
        'actual authoritative node-not-running ordinary text',
        const Duration(seconds: 30),
        () async {
          final value = await snapshot('alice');
          if ((value['node'] as Map)['isStarted'] != false) {
            throw StateError(
              'offline prerequisite ended before observation; no offline product verdict',
            );
          }
          final rows = (value['messages'] as List).whereType<Map>().toList();
          return rows.length == 1 &&
                  rows.single['text'] == text &&
                  rows.single['status'] == 'failed'
              ? value
              : null;
        },
      );
      phases['offline'] = {'alice': actualFailed, 'bob': await snapshot('bob')};
      await persist();
      // Uses the same production lifecycle prerequisites as routing S3, not
      // a command that inserts, rewrites, clears or directly retries a row.
      proof['start'] = await journey.alice.command('routing_node_control', {
        'operation': 'start',
      });
      await journey.alice.awaitReady();
      proof['warm'] = await journey.alice.command('routing_node_control', {
        'operation': 'warm_background',
      });
      await persist();
      final original = (actualFailed['messages'] as List).single as Map;
      Future<void> settled(String phase) async {
        final pair = <String, Object?>{};
        for (final role in ['alice', 'bob']) {
          pair[role] = await waitForProductionObservation(
            '$phase/$role same logical ID and supported recovery',
            const Duration(minutes: 3),
            () async {
              final value = await snapshot(role);
              final rows = (value['messages'] as List)
                  .whereType<Map>()
                  .toList();
              final node = value['node'] as Map;
              if (node['isStarted'] != true ||
                  node['sendCapabilityReady'] != true ||
                  node['inboxCapabilityReady'] != true) {
                return null;
              }
              return rows.length == 1 &&
                      rows.single['id'] == original['id'] &&
                      rows.single['text'] == text &&
                      (role != 'alice' || rows.single['status'] == 'delivered')
                  ? value
                  : null;
            },
          );
        }
        phases[phase] = pair;
        await persist();
        for (final role in ['alice', 'bob']) {
          final row = ((pair[role] as Map)['messages'] as List).single as Map;
          final label = directSenderOfflineTransportLabel(
            row['transport'],
            incoming: role == 'bob',
          );
          if (label == null) {
            throw StateError(
              'actual transport lacks an existing rendered semantic',
            );
          }
          await flow(
            role,
            'production_direct_assert_action',
            '$phase-ui-$role',
            {
              'VISIBLE_PATTERN': '$pattern.*${RegExp.escape(label)}',
              'ABSENT_PATTERN': '$pattern.*(?:Message status: failed|Retry)',
            },
          );
        }
      }

      await settled('reconnected');
      for (final role in ['alice', 'bob']) {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await persist();
      }
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      for (final role in ['alice', 'bob']) {
        nonces[role]!.add(actor(role).invocation.nonce);
        await flow(role, 'production_direct_open', 'reopen-$role', {
          'PEER_ID': peers[role == 'alice' ? 'bob' : 'alice']!,
        });
      }
      await settled('restarted');
      final failures = validateProductionDirectSenderOffline(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } catch (error, stack) {
      firstFailureRecorded = true;
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      try {
        await journey.restore();
      } catch (error, stack) {
        await File(
          '${output.path}/cleanup-failure.txt',
        ).writeAsString('$error\n$stack');
        if (!firstFailureRecorded) rethrow;
      }
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionDirectSenderOffline,
      validatorIds: ['validateProductionDirectSenderOffline'],
      payload: {...journey.provenance(), ...proof, 'status': 'PASS'},
    );
  } catch (error, stack) {
    if (output != null) {
      final first = File('${output.path}/first-failure.txt');
      if (!first.existsSync()) await first.writeAsString('$error\n$stack');
    }
  }
  final passed = evidence != null;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'DC-022 same-ID ordinary-text offline recovery passed' : 'DC-022 incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
