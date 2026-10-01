import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_catalog_send_sequence.dart';
import '../../tool/sims/production_group_removal_pair_criteria.dart';
import 'production_android_journey.dart';
import 'production_catalog_session.dart';

/// Runs one removal-then-remaining-pair catalog journey: UI creation and
/// acceptance, Alice removes Charlie through group info, then the case's
/// sender sends ten original texts through the composer; each is observed on
/// the remaining receiver, and Charlie's retained group is read at the end.
Future<void> runProductionRemovalPairJourney({
  required List<String> arguments,
  required ProductionRemovalPairCase removalCase,
  required String validatorId,
}) async {
  final capability = 'production.group_catalog.${removalCase.scenario}';
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(capability);
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
    final journey = ProductionAndroidJourney.fromEnvironment(
      capability,
      output,
    );
    final run = journey.runId;
    final steps = removalCase.steps(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      final peers = s.peers;
      s.watch = {
        for (final step in steps)
          step.key: {'text': step.text, 'senderPeerId': peers[step.role]},
      };
      final name = 'Catalog ${removalCase.scenario} $run';
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
      for (final role in productionCatalogRoles) {
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
      proof['bobExcluded'] = await s.waitWatch(
        'bob',
        'Bob excludes Charlie',
        (x) => !members(x).contains(peers['charlie']),
      );
      await s.waitWatch(
        'charlie',
        'Charlie self-removed',
        (x) => x['selfMember'] == false,
      );
      await s.flow('alice', 'production_back_to_chat', 'alice-back-to-chat');

      attempts++;
      for (final step in steps) {
        await s.verbatimSend(step.role, step.label, step.text);
        await s.waitWatch(
          removalCase.receiver,
          '${removalCase.receiver} receives ${step.key}',
          (x) => ProductionCatalogSession.rows(x, step.key) == 1,
        );
        proof['got:${step.key}:${removalCase.receiver}'] = await s.snap(
          removalCase.receiver,
        );
      }
      // The original's five-second window before counting Charlie's rows.
      await Future<void>.delayed(const Duration(seconds: 5));
      for (final role in productionCatalogRoles) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validateProductionRemovalPair(removalCase, proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: capability,
      validatorIds: [validatorId],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production ${removalCase.scenario} passed' : 'production ${removalCase.scenario} failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
