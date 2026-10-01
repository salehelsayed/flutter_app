import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_gm020_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_session.dart';

const _scenario = 'production.group_catalog.gm020';

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
    final run = journey.runId;
    final texts = productionGm020Texts(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      final peers = s.peers;
      s.watch = {
        for (final entry in texts.entries)
          entry.key: {'text': entry.value, 'senderPeerId': peers['alice']},
      };
      final name = 'Catalog gm020 $run';
      List members(Map<String, Object?> x) =>
          ProductionCatalogSession.members(x);
      Future<Map<String, Object?>> got(String key) async {
        await s.waitWatch(
          'bob',
          'bob receives $key',
          (x) => ProductionCatalogSession.rows(x, key) == 1,
        );
        // Retain the original receiver's two-second settlement window.
        await Future<void>.delayed(const Duration(seconds: 2));
        return s.snap('bob');
      }

      attempts++;
      await s.verbatimFlow(
        'alice',
        'production_catalog_group_create_verbatim',
        'production_catalog_group_create',
        'create',
        {'GROUP_NAME': name},
      );
      await s.invitedAndAccept('bob', 'accept-bob', name);
      await s.invitedAndAccept('charlie', 'accept-charlie', name);
      for (final role in ['alice', 'bob', 'charlie']) {
        await s.settled(role, 3);
      }
      // The original's five-second settle after every member joined.
      await Future<void>.delayed(const Duration(seconds: 5));

      attempts++;
      await s.membershipEdit(
        'alice',
        'remove-charlie',
        'production_catalog_remove_charlie',
        'production_catalog_remove_charlie_retry',
        {'CHARLIE_PEER_ID': peers['charlie']!},
        () async => !members(await s.snap('alice')).contains(peers['charlie']),
      );
      proof['removedAt'] = DateTime.now().toUtc().toIso8601String();
      proof['aliceRemoved'] = await s.snap('alice');
      // The immediate send does not wait for Bob or Charlie to apply it.
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      await s.verbatimSend(
        'alice',
        'alice-immediate',
        texts[productionGm020ImmediateKey]!,
      );
      proof['got:$productionGm020ImmediateKey:bob'] = await got(
        productionGm020ImmediateKey,
      );

      attempts++;
      // Charlie applies its removal, then becomes unavailable (verified
      // process death) before Alice's second send.
      await s.waitWatch(
        'charlie',
        'Charlie self-removed',
        (x) => x['selfMember'] == false,
      );
      await journey.killOwnedProcess(s.actors['charlie']!);
      proof['charlieOffline'] = File(
        '${output.path}/${s.actors['charlie']!.invocation.nonce}-process-death.json',
      ).existsSync();
      await s.persist();
      await s.verbatimSend(
        'alice',
        'alice-offline',
        texts[productionGm020OfflineKey]!,
      );
      proof['got:$productionGm020OfflineKey:bob'] = await got(
        productionGm020OfflineKey,
      );
      // Charlie relaunches; the app's own startup catch-up runs, then the
      // retained group is read after the original five-second window.
      s.replace('charlie', await journey.reopen(s.actors['charlie']!));
      await Future<void>.delayed(const Duration(seconds: 5));
      for (final role in ['alice', 'bob', 'charlie']) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionGroupGm020(proof);
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
      validatorIds: ['validateProductionGroupGm020'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production gm020 passed' : 'production gm020 failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
