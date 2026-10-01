import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_gm006_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_session.dart';

const _scenario = 'production.group_catalog.gm006';

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
    final texts = productionGm006Texts(run);
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
                peers[entry.key.startsWith('alice') ? 'alice' : 'charlie'],
          },
      };
      final name = 'Catalog gm006 $run';
      List members(Map<String, Object?> x) =>
          ProductionCatalogSession.members(x);
      Future<Map<String, Object?>> got(String role, String key) async {
        await s.waitWatch(
          role,
          '$role receives $key',
          (x) => ProductionCatalogSession.rows(x, key) == 1,
        );
        // Retain the original receiver's two-second settlement window.
        await Future<void>.delayed(const Duration(seconds: 2));
        return s.snap(role);
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

      attempts++;
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
      // The original waits for Charlie's own removal before rotating.
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
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      await s.verbatimSend(
        'alice',
        'alice-during-removal',
        texts['aliceDuringCharlieRemoval']!,
      );
      proof['bobGotDuring'] = await got('bob', 'aliceDuringCharlieRemoval');
      // The original's five-second absence window on the removed member.
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['charlieRemovedWindow'] = await s.snap('charlie');

      attempts++;
      await s.membershipEdit(
        'alice',
        'readd-charlie',
        'production_group_info_add_member',
        'production_group_info_add_member_retry',
        {'CONTACT_NAME': 'Journeycharlie'},
        () async => false,
      );
      // The removed Charlie returns to the home tabs to see the new invite.
      await s.flow('charlie', 'production_home_tabs', 'charlie-home');
      await s.invitedAndAccept('charlie', 'accept-charlie-readd', name);
      for (final role in ['alice', 'bob', 'charlie']) {
        await s.settled(role, 3);
      }
      await s.verbatimSend(
        'charlie',
        'charlie-after-readd',
        texts['charlieAfterImmediateReadd']!,
      );
      proof['aliceGotCharlie'] = await got('alice', 'charlieAfterImmediateReadd');
      proof['bobGotCharlie'] = await got('bob', 'charlieAfterImmediateReadd');
      await s.verbatimSend(
        'alice',
        'alice-after-readd',
        texts['aliceAfterImmediateReadd']!,
      );
      proof['bobGotAfter'] = await got('bob', 'aliceAfterImmediateReadd');
      proof['charlieGotAfter'] = await got('charlie', 'aliceAfterImmediateReadd');
      for (final role in ['alice', 'bob', 'charlie']) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionGroupGm006(proof);
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
      validatorIds: ['validateProductionGroupGm006'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production gm006 passed' : 'production gm006 failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
