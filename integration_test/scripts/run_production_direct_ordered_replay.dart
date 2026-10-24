import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_direct_ordered_replay_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

/// Uses the existing routing runtime's read-only row observations and the
/// existing real composer flows. The outer SIMS capability names the new
/// assertions; it does not grant a new app control channel or bypass consent.
Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionDirectOrderedReplay);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError(
        'this scenario requires the disposable emulator-pair route',
      );
    }
    final destination = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (destination == null || destination.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      destination,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      directOrderedReplayRuntime,
      output,
    );
    final phases = <String, Object?>{};
    final kills = <String, Object?>{};
    final batches = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': directOrderedReplayRuntime,
      'emulatorPair': journey.disposableAndroidJourneys,
      'phases': phases,
      'ownedKills': kills,
      'uiBatches': batches,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      final peers = {
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      proof['initialNonces'] = {
        'alice': journey.alice.invocation.nonce,
        'bob': journey.bob.invocation.nonce,
      };
      final texts = directOrderedReplayTexts(journey.runId);
      ProductionJourneyPeer actor(String role) =>
          role == 'alice' ? journey.alice : journey.bob;
      Future<Map<String, Object?>> snapshot(String role) async {
        final peer = actor(role);
        // command() verifies the runtime tuple, sequence, operation and OK
        // before it exposes this real repository snapshot.
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

      int matchingRows(Map<String, Object?> value, int count) {
        final expected = texts.take(count).toSet();
        final rows = value['messages'];
        return rows is List
            ? rows
                  .whereType<Map>()
                  .where((row) => expected.contains(row['text']))
                  .length
            : 0;
      }

      Future<void> settled(String phase, int count) async {
        final values = <String, Object?>{};
        for (final role in ['alice', 'bob']) {
          values[role] = await waitForProductionObservation(
            '$phase $role exact row count',
            const Duration(minutes: 3),
            () async {
              final value = await snapshot(role);
              return matchingRows(value, count) == count ? value : null;
            },
          );
        }
        phases[phase] = values;
        await persist();
      }

      Future<void> kill(String role, String label) async {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        kills[label] = jsonDecode(
          await File(
            '${output!.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await persist();
      }

      Future<void> sendBatch(int first, String phase) async {
        final values = <String, String>{};
        for (var j = 0; j < 5; j++) {
          values['MESSAGE_${j + 1}'] = texts[first + j];
          values['MESSAGE_PATTERN_${j + 1}'] = RegExp.escape(texts[first + j]);
        }
        attempted++;
        final path = await journey.flow(
          journey.alice,
          'production_direct_send_batch5',
          'ordered-$phase-$first',
          values,
        );
        batches.add({
          'firstIndex': first,
          'phase': phase,
          'path': path,
          'receipt': jsonDecode(await File(path).readAsString()),
        });
        await persist();
      }

      await journey.flow(
        journey.alice,
        'production_direct_open',
        'ordered-open',
        {'PEER_ID': peers['bob']!},
      );
      for (var first = 0; first < directOrderedReplayCount; first += 5) {
        await sendBatch(first, 'online');
      }
      await settled('online', directOrderedReplayCount);
      await kill('bob', 'bobOffline');
      // The direct offline leg has no native-notification proof. Force-stop
      // only our freshly owned package so a scheduled headless wake cannot
      // silently turn the recipient back online before the explicit relaunch.
      await journey.bob.adb([
        'shell',
        'am',
        'force-stop',
        journey.bob.packageName,
      ]);
      final offlineGuard = <String, Object?>{'ownedPackageForceStopped': true};
      proof['offlineGuard'] = offlineGuard;
      final offline = Stopwatch()..start();
      for (
        var first = directOrderedReplayCount;
        first < directOrderedTotalCount;
        first += 5
      ) {
        await sendBatch(first, 'offline');
      }
      proof['senderBeforeReplay'] = await waitForProductionObservation(
        'all ten offline messages have persisted inbox custody',
        const Duration(minutes: 2),
        () async {
          final value = await snapshot('alice');
          final rows = (value['messages'] as List)
              .whereType<Map>()
              .where(
                (row) =>
                    texts.skip(directOrderedReplayCount).contains(row['text']),
              )
              .toList();
          return rows.length == directOrderedOfflineCount &&
                  rows.every(
                    (row) =>
                        row['status'] == 'inboxed' &&
                        row['transport'] == 'inbox',
                  )
              ? value
              : null;
        },
      );
      final remaining =
          directOrderedReplayMinimumDwellMs - offline.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: remaining));
      }
      proof['offlineDwellMs'] = offline.elapsedMilliseconds;
      final absent = await journey.bob.adb([
        'shell',
        'pidof',
        journey.bob.packageName,
      ], allowFailure: true);
      offlineGuard['absentBeforeRelaunch'] =
          absent.exitCode == 1 &&
          '${absent.stdout}'.trim().isEmpty &&
          '${absent.stderr}'.trim().isEmpty;
      await persist();
      if (offlineGuard['absentBeforeRelaunch'] != true) {
        throw StateError(
          'owned offline recipient restarted before the explicit relaunch',
        );
      }
      journey.bob = await journey.reopen(journey.bob);
      await settled('firstReplay', directOrderedTotalCount);
      await kill('alice', 'aliceRestart');
      await kill('bob', 'bobRestart');
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      proof['finalNonces'] = {
        'alice': journey.alice.invocation.nonce,
        'bob': journey.bob.invocation.nonce,
      };
      await settled('bothRestarted', directOrderedTotalCount);
      final failures = validateProductionDirectOrderedReplay(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionDirectOrderedReplay,
      validatorIds: ['validateProductionDirectOrderedReplay'],
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'DC-002/DC-003 exact ordered replay passed' : 'DC-002/DC-003 incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
