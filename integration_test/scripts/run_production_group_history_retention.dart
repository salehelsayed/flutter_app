import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_history_retention_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_session.dart';

const _scenario = 'production.group_catalog.private_history_retention';

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
    final texts = productionMl017Texts(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      final peers = s.peers;
      s.watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value,
            'senderPeerId':
                peers[entry.key.startsWith('alice')
                    ? 'alice'
                    : entry.key.startsWith('bob')
                    ? 'bob'
                    : 'charlie'],
          },
      };
      final name = 'Catalog private_history_retention $run';
      List members(Map<String, Object?> x) =>
          ProductionCatalogSession.members(x);
      Future<void> got(String role, String key) async {
        await s.waitWatch(
          role,
          '$role receives $key',
          (x) => ProductionCatalogSession.rows(x, key) == 1,
        );
        // Retain the original receiver's two-second settlement window.
        await Future<void>.delayed(const Duration(seconds: 2));
        proof['got:$key:$role'] = await s.snap(role);
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
      // Pre-removal history reaches every member, Charlie included.
      await s.verbatimSend(
        'alice',
        'alice-before-removal',
        texts[productionMl017BeforeKey]!,
      );
      await got('bob', productionMl017BeforeKey);
      await got('charlie', productionMl017BeforeKey);
      await s.membershipEdit(
        'alice',
        'remove-charlie',
        'production_catalog_remove_charlie',
        'production_catalog_remove_charlie_retry',
        {'CHARLIE_PEER_ID': peers['charlie']!},
        () async => !members(await s.snap('alice')).contains(peers['charlie']),
      );
      proof['aliceRemoved'] = await s.snap('alice');
      await s.waitWatch(
        'bob',
        'Bob excludes Charlie',
        (x) => !members(x).contains(peers['charlie']),
      );
      await s.waitWatch(
        'charlie',
        'Charlie self-removed',
        (x) => x['selfMember'] == false,
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

      attempts++;
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      await s.verbatimSend(
        'alice',
        'alice-after-removal',
        texts[productionMl017AliceAfterKey]!,
      );
      await got('bob', productionMl017AliceAfterKey);
      await s.verbatimSend(
        'bob',
        'bob-after-removal',
        texts[productionMl017BobAfterKey]!,
      );
      await got('alice', productionMl017BobAfterKey);
      // The original's five-second window, then the removed Charlie's one
      // publish attempt through the production use case.
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['charlieRejected'] = await s.actors['charlie']!.command(
        'catalog_attempt_removed_send',
        {
          'key': productionMl017CharlieKey,
          'text': texts[productionMl017CharlieKey]!,
        },
      );
      for (final role in ['alice', 'bob', 'charlie']) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionGroupHistoryRetention(proof);
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
      validatorIds: ['validateProductionGroupHistoryRetention'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private_history_retention passed' : 'production private_history_retention failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
