import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_direct_send_cut_criteria.dart';
import '../support/direct_text_checkpoint_client.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionDirectSendCut);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    final environment = Platform.environment;
    if (environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1' ||
        environment['MKNOON_DIRECT_TEXT_SEND_CHECKPOINT'] != '1') {
      throw StateError(
        'requires disposable emulator pair and owned text checkpoint fixture',
      );
    }
    final fixtureDigest =
        environment['MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256'];
    final probe = Uri.tryParse(
      environment['MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL'] ?? '',
    );
    final path = environment['SIMS_PROOF_DIRECTORY'];
    if (fixtureDigest == null ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fixtureDigest) ||
        probe == null ||
        probe.scheme != 'http' ||
        !probe.hasAuthority ||
        path == null ||
        path.isEmpty) {
      throw StateError('missing owned relay attestation or proof destination');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final checkpoint = DirectTextCheckpointClient(probe);
    final journey = ProductionAndroidJourney.fromEnvironment(
      directSendCutRuntime,
      output,
    );
    final phases = <String, Object?>{};
    final restartKills = <String, Object?>{};
    final nonces = <String, List<String>>{'alice': [], 'bob': []};
    final cut = <String, Object?>{};
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': directSendCutRuntime,
      'emulatorPair':
          journey.disposableAndroidJourneys && journey.actors.length == 2,
      'fixtureIdentitySha256': fixtureDigest,
      'cut': cut,
      'phases': phases,
      'nonces': nonces,
      'restartKills': restartKills,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    var assertionsComplete = false;
    Future<String>? pendingSubmission;
    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      final peers = <String, String>{
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      ProductionJourneyPeer actor(String role) =>
          role == 'alice' ? journey.alice : journey.bob;
      void rememberNonces() {
        for (final role in ['alice', 'bob']) {
          nonces[role]!.add(actor(role).invocation.nonce);
        }
      }

      rememberNonces();
      Future<Map<String, Object?>> snapshot(String role) async {
        final peer = actor(role);
        final value = await peer.command('routing_snapshot', {
          'peerIds': [peers[role == 'alice' ? 'bob' : 'alice']],
          'groupIds': <String>[],
        });
        return {
          ...value,
          'observedRunId': peer.invocation.runId,
          'observedRole': role,
          'observedNonce': peer.invocation.nonce,
        };
      }

      Future<Map<String, Object?>> kill(String role) async {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        return Map<String, Object?>.from(
          jsonDecode(
                await File(
                  '${output!.path}/${peer.invocation.nonce}-process-death.json',
                ).readAsString(),
              )
              as Map,
        );
      }

      Future<bool> absent(ProductionJourneyPeer peer) async {
        final result = await peer.adb([
          'shell',
          'pidof',
          peer.packageName,
        ], allowFailure: true);
        return result.exitCode == 1 &&
            '${result.stdout}'.trim().isEmpty &&
            '${result.stderr}'.trim().isEmpty;
      }

      await journey.flow(journey.alice, 'production_direct_open', 'cut-open', {
        'PEER_ID': peers['bob']!,
      });
      proof['recipientOfflineKill'] = await kill('bob');
      await journey.bob.adb([
        'shell',
        'am',
        'force-stop',
        journey.bob.packageName,
      ]);
      cut['recipientForceStopped'] = true;
      await checkpoint.arm(peers['bob']!);
      final text = 'In-flight sender cut ${journey.runId}';
      attempted++;
      Object? submissionError;
      final submission = journey
          .flow(
            journey.alice,
            'production_direct_send_checkpoint',
            'cut-send',
            {'MESSAGE': text, 'MESSAGE_PATTERN': RegExp.escape(text)},
          )
          .catchError((Object error, StackTrace stack) {
            submissionError = error;
            return '';
          });
      pendingSubmission = submission;
      final wait = Stopwatch()..start();
      var held = false;
      while (wait.elapsed < const Duration(minutes: 2)) {
        if (submissionError != null) {
          throw StateError(
            'in-flight UI submission failed; see its original flow receipt',
          );
        }
        if ((await checkpoint.status())['held'] == true) {
          held = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      if (!held) {
        throw StateError('causal committed-store checkpoint not reached');
      }
      final receiptPath = await submission;
      if (submissionError != null) {
        throw StateError(
          'in-flight status UI witness failed; see its original flow receipt',
        );
      }
      // Keep this interval free of disk writes. The independent post-death
      // device-clock bound rejects a late cut even if an earlier sample said
      // "sending". A missed window is a harness failure, not an app verdict.
      cut['source'] = await snapshot('alice');
      final sourceRows = ((cut['source'] as Map)['messages'] as List)
          .whereType<Map>()
          .toList();
      if (sourceRows.length != 1 || sourceRows.single['status'] != 'sending') {
        throw StateError('in-flight source checkpoint missed; no app verdict');
      }
      cut['gateBeforeKill'] = await checkpoint.status();
      cut['ownedKill'] = await kill('alice');
      final date = await journey.alice.adb(['shell', 'date', '+%s%3N']);
      final cutAt = int.tryParse('${date.stdout}'.trim());
      cut['deviceUnixMsAfterVerifiedDeath'] = cutAt;
      cut['gateAfterKill'] = await checkpoint.status();
      cut['recipientAbsentAfterCut'] = await absent(journey.bob);
      cut['uiReceiptPath'] = receiptPath;
      cut['uiReceipt'] = jsonDecode(await File(receiptPath).readAsString());
      await persist();
      final created = DateTime.tryParse('${sourceRows.single['timestamp']}');
      if (created == null ||
          cutAt == null ||
          cutAt < created.millisecondsSinceEpoch ||
          cutAt - created.millisecondsSinceEpoch >= directSendCutMaximumAgeMs ||
          (cut['gateAfterKill'] as Map)['held'] != true ||
          cut['recipientAbsentAfterCut'] != true) {
        throw StateError('causal in-flight cut window missed; no app verdict');
      }
      await checkpoint.release();
      journey.alice = await journey.reopen(journey.alice);
      await journey.flow(
        journey.alice,
        'production_direct_open',
        'cut-recovered-open',
        {'PEER_ID': peers['bob']!},
      );
      final recovery = await waitForProductionObservation(
        'sender recovers the original durable row',
        const Duration(minutes: 2),
        () async {
          final value = await snapshot('alice');
          final rows = (value['messages'] as List).whereType<Map>().toList();
          return rows.length == 1 ? value : null;
        },
      );
      proof['senderFirstRecovery'] = recovery;
      final recoveryRow = ((recovery['messages'] as List).single as Map);
      if (recoveryRow['id'] != sourceRows.single['id']) {
        throw StateError('sender recovery changed logical identity');
      }
      // Custody already committed before the cut. Reopen the receiver and
      // require automatic same-ID delivery/receipt convergence; do not infer a
      // visible Retry button from the stored status (custody-aware UI can
      // project a failed transport attempt into its pending recovery lane).
      journey.bob = await journey.reopen(journey.bob);
      rememberNonces();
      Future<void> settled(String phase) async {
        final actors = <String, Object?>{};
        for (final role in ['alice', 'bob']) {
          actors[role] = await waitForProductionObservation(
            '$phase/$role exact-once delivery',
            const Duration(minutes: 3),
            () async {
              final value = await snapshot(role);
              final rows = (value['messages'] as List)
                  .whereType<Map>()
                  .toList();
              return rows.length == 1 &&
                      (role == 'bob' || rows.single['status'] == 'delivered')
                  ? value
                  : null;
            },
          );
        }
        phases[phase] = actors;
        await persist();
      }

      await settled('firstReplay');
      for (final role in ['alice', 'bob']) {
        restartKills[role] = await kill(role);
      }
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      rememberNonces();
      await settled('bothRestarted');
      final failures = validateProductionDirectSendCut(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
      assertionsComplete = true;
    } finally {
      // The existing flow adapter owns and bounds its UI process. Do not
      // restore packages while that same owned flow can still act on them.
      if (pendingSubmission != null) await pendingSubmission;
      final cleanupErrors = <String>[];
      for (final operation in <Future<void> Function()>[
        () async {
          await checkpoint.release();
        },
        journey.restore,
      ]) {
        try {
          await operation();
        } catch (error, stack) {
          cleanupErrors.add('$error\n$stack');
        }
      }
      if (cleanupErrors.isNotEmpty) {
        await File(
          '${output.path}/cleanup-failures.json',
        ).writeAsString(jsonEncode(cleanupErrors));
        if (assertionsComplete) {
          throw StateError(
            'owned fixture cleanup failed; see cleanup-failures.json',
          );
        }
      }
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionDirectSendCut,
      validatorIds: ['validateProductionDirectSendCut'],
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'DC-004 bounded in-flight sender cut and exact-once replay passed' : 'DC-004 incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
