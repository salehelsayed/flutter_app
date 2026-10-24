import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_ordered_recovery_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_session.dart';
import '../support/production_sims_result.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionGroupOrderedRecovery);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError(
        'this scenario requires three disposable emulator roles',
      );
    }
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      groupOrderedRecoveryRuntime,
      output,
    );
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': groupOrderedRecoveryRuntime,
      'emulatorTriple':
          journey.disposableAndroidJourneys && journey.actors.length == 3,
    };
    final session = ProductionCatalogSession(journey, output, proof);
    final kills = <String, Object?>{};
    proof['ownedKills'] = kills;
    try {
      await session.start();
      final texts = groupOrderedRecoveryTexts(journey.runId);
      session.watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value.text,
            'senderPeerId': session.peers[entry.value.role],
          },
      };
      proof['peers'] = session.peers;
      proof['initialNonces'] = {
        for (final entry in session.actors.entries)
          entry.key: entry.value.invocation.nonce,
      };
      attempted++;
      await session.createAndAcceptAll(session.catalogName('de002'));
      for (var i = 0; i < 100; i++) {
        await session.verbatimSend(
          'alice',
          'ordered-seq-$i',
          texts['seq$i']!.text,
        );
      }
      await session.verbatimSend('bob', 'ordered-bob', texts['bob']!.text);
      await session.verbatimSend(
        'charlie',
        'ordered-charlie',
        texts['charlie']!.text,
      );
      Future<Map<String, Object?>> complete(
        String role,
        Iterable<String> keys,
      ) => session.waitWatch(
        role,
        '$role complete canonical group rows',
        (snapshot) => keys.every(
          (key) => ProductionCatalogSession.rows(snapshot, key) == 1,
        ),
        timeout: const Duration(minutes: 5),
      );
      proof['beforeCrash'] = {
        for (final role in session.actors.keys)
          role: await complete(
            role,
            texts.keys.where((key) => key != 'accepted'),
          ),
      };
      await session.persist();
      Future<void> kill(String role) async {
        final peer = session.actors[role]!;
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output!.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await session.persist();
      }

      // Keep both recipients offline until the author has crossed the verified
      // accepted/durable text checkpoint and its owned process has died.
      for (final role in ['bob', 'charlie']) {
        await kill(role);
        final peer = session.actors[role]!;
        await peer.adb(['shell', 'am', 'force-stop', peer.packageName]);
      }
      await session.verbatimSend(
        'alice',
        'ordered-accepted',
        texts['accepted']!.text,
      );
      proof['acceptedSource'] = await session.waitWatch(
        'alice',
        'actual accepted text with committed recipient custody',
        (snapshot) {
          final watched = snapshot['watched'] as Map?;
          final rows = (watched?['accepted'] as List?) ?? const [];
          if (rows.length != 1 ||
              !['sent', 'delivered'].contains((rows.single as Map)['status'])) {
            return false;
          }
          final id = (rows.single as Map)['messageId'];
          return (snapshot['deliveries'] as List).whereType<Map>().any(
            (delivery) =>
                delivery['messageId'] == id &&
                delivery['ok'] == true &&
                delivery['inboxStored'] == true,
          );
        },
      );
      await session.persist();
      await kill('alice');
      final offline = <String, Object?>{};
      proof['offlineRecipients'] = offline;
      for (final role in ['bob', 'charlie']) {
        final peer = session.actors[role]!;
        final result = await peer.adb([
          'shell',
          'pidof',
          peer.packageName,
        ], allowFailure: true);
        offline[role] =
            result.exitCode == 1 &&
            '${result.stdout}'.trim().isEmpty &&
            '${result.stderr}'.trim().isEmpty;
      }
      await session.persist();
      if (offline.values.any((absent) => absent != true)) {
        throw StateError(
          'a recipient restarted before the accepted sender cut',
        );
      }
      for (final role in session.actors.keys.toList()) {
        session.replace(role, await journey.reopen(session.actors[role]!));
      }
      proof['finalNonces'] = {
        for (final entry in session.actors.entries)
          entry.key: entry.value.invocation.nonce,
      };
      proof['afterRestart'] = {
        for (final role in session.actors.keys)
          role: await complete(role, texts.keys),
      };
      await session.persist();
      final failures = validateProductionGroupOrderedRecovery(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionGroupOrderedRecovery,
      validatorIds: ['validateProductionGroupOrderedRecovery'],
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'GC-002 and GC-005 accepted-text leg passed' : 'group ordered recovery incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
