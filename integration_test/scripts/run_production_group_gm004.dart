import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_gm004_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_session.dart';

const _scenario = 'production.group_catalog.gm004';

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
    final texts = productionGm004Texts(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      final peers = s.peers;
      s.watch = {
        'aliceAfterCharlieRemove': {
          'text': texts['aliceAfterCharlieRemove'],
          'senderPeerId': peers['alice'],
        },
        'bobAfterCharlieRemove': {
          'text': texts['bobAfterCharlieRemove'],
          'senderPeerId': peers['bob'],
        },
      };
      final name = 'Catalog gm004 $run';
      int rows(Map<String, Object?> x, String key) =>
          ProductionCatalogSession.rows(x, key);
      List members(Map<String, Object?> x) =>
          ProductionCatalogSession.members(x);

      attempts++;
      await s.flow('alice', 'production_catalog_group_create', 'create', {
        'GROUP_NAME': name,
      });
      await s.invitedAndAccept('bob', 'accept-bob', name);
      await s.invitedAndAccept('charlie', 'accept-charlie', name);
      for (final role in ['alice', 'bob', 'charlie']) {
        await s.settled(role, 3);
      }
      proof['charlieBefore'] = await s.waitWatch(
        'charlie',
        'Charlie current member before removal',
        (x) => x['selfMember'] == true,
      );

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
      await s.waitWatch(
        'charlie',
        'Charlie self removal',
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
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');

      attempts++;
      await s.verbatimSend(
        'alice',
        'alice-after-remove',
        texts['aliceAfterCharlieRemove']!,
      );
      proof['aliceSentAfter'] = await s.snap('alice');
      await s.waitWatch(
        'bob',
        'Bob receives Alice after removal',
        (x) => rows(x, 'aliceAfterCharlieRemove') == 1,
      );
      // Retain the original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      proof['bobGotAlice'] = await s.snap('bob');
      await s.verbatimSend(
        'bob',
        'bob-after-remove',
        texts['bobAfterCharlieRemove']!,
      );
      proof['bobSentAfter'] = await s.snap('bob');
      await s.waitWatch(
        'alice',
        'Alice receives Bob after removal',
        (x) => rows(x, 'bobAfterCharlieRemove') == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      proof['aliceGotBob'] = await s.snap('alice');

      attempts++;
      // The original's five-second absence window before counting leaks.
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['charlieLeak'] = await s.snap('charlie');
      proof['charlieRejected'] = await s.actors['charlie']!.command(
        'catalog_attempt_removed_send',
        {
          'key': 'charlieAfterCharlieRemove',
          'text': 'GM-004 Charlie after removal $run',
        },
      );
      for (final role in ['alice', 'bob', 'charlie']) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionGroupGm004(proof);
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
      validatorIds: ['validateProductionGroupGm004'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production gm004 passed' : 'production gm004 failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
