import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_gm005_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_session.dart';

const _scenario = 'production.group_catalog.gm005';

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
    final texts = productionGm005Texts(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      final peers = s.peers;
      s.watch = {
        for (final entry in texts.entries)
          entry.key: {'text': entry.value, 'senderPeerId': peers['alice']},
      };
      final name = 'Catalog gm005 $run';
      List members(Map<String, Object?> x) =>
          ProductionCatalogSession.members(x);

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
      // Charlie persists the old configuration and key, then goes offline.
      proof['charlieStale'] = await s.waitWatch(
        'charlie',
        'Charlie old state persisted',
        (x) => x['selfMember'] == true && x['keyEpoch'] == 1,
      );
      await journey.killOwnedProcess(s.actors['charlie']!);
      proof['charlieOffline'] = File(
        '${output.path}/${s.actors['charlie']!.invocation.nonce}-process-death.json',
      ).existsSync();
      await s.persist();
      // The original's five-second settle before the offline removal.
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
      await s.waitWatch(
        'bob',
        'Bob excludes Charlie',
        (x) => !members(x).contains(peers['charlie']),
      );
      final rotated = await s.waitWatch(
        'alice',
        'Alice rotated epoch',
        (x) => (x['keyEpoch'] as int) >= 2,
      );
      await s.waitWatch(
        'bob',
        'Bob holds rotated key',
        (x) => x['keyEpoch'] == rotated['keyEpoch'],
      );
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      for (var i = 1; i <= 3; i++) {
        final key = 'aliceAfterCharlieOfflineRemove$i';
        await s.verbatimSend('alice', 'alice-after-remove-$i', texts[key]!);
        proof['aliceSent$i'] = await s.snap('alice');
        await s.waitWatch(
          'bob',
          'Bob receives $key',
          (x) => ProductionCatalogSession.rows(x, key) == 1,
        );
        // Retain the original receiver's two-second settlement window.
        await Future<void>.delayed(const Duration(seconds: 2));
        proof['bobGot$i'] = await s.snap('bob');
      }

      attempts++;
      // Charlie reconnects with stale state and drains until self-removed.
      s.replace('charlie', await journey.reopen(s.actors['charlie']!));
      proof['charlieDrain'] = await s.actors['charlie']!.command(
        'catalog_drain_until_self_removed',
      );
      proof['charlieRejected'] = await s.actors['charlie']!.command(
        'catalog_attempt_removed_send',
        {
          'key': 'charlieAfterOfflineRemove',
          'text': 'GM-005 Charlie after offline removal $run',
        },
      );
      for (final role in ['alice', 'bob', 'charlie']) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionGroupGm005(proof);
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
      validatorIds: ['validateProductionGroupGm005'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production gm005 passed' : 'production gm005 failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
