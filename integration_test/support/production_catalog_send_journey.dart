import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_catalog_send_sequence.dart';
import 'production_android_journey.dart';
import 'production_catalog_session.dart';

/// Runs one create-accept-send-sequence catalog journey: Alice creates the
/// group through the UI, Bob and Charlie accept, then each step's role sends
/// its original proof text through the composer and every other role is
/// observed receiving it. [after] may add read-only observations before the
/// final snapshots; [validate] maps the proof to oracle failures.
Future<void> runProductionCatalogSendJourney({
  required List<String> arguments,
  required String capability,
  required String validatorId,
  required List<ProductionSendStep> Function(String run) steps,
  required List<String> Function(Map<String, Object?> proof) validate,
  Future<void> Function(ProductionCatalogSession session)? after,
}) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(capability);
    return;
  }
  final scenario = capability.split('.').last;
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
    final sequence = steps(run);
    final proof = <String, Object?>{'runId': run};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      s.watch = {
        for (final step in sequence)
          step.key: {'text': step.text, 'senderPeerId': s.peers[step.role]},
      };
      final name = 'Catalog $scenario $run';

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
      for (final step in sequence) {
        await s.verbatimSend(step.role, step.label, step.text);
        for (final role in productionCatalogRoles.where(
          (r) => r != step.role,
        )) {
          await s.waitWatch(
            role,
            '$role receives ${step.key}',
            (x) => ProductionCatalogSession.rows(x, step.key) == 1,
          );
          // The original receiver's two-second duplicate-settlement window.
          await Future<void>.delayed(const Duration(seconds: 2));
          proof['got:${step.key}:$role'] = await s.snap(role);
        }
      }
      if (after != null) await after(s);
      for (final role in productionCatalogRoles) {
        proof['${role}Final'] = await s.snap(role);
      }
      await s.persist();
      final failures = validate(proof);
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production $scenario passed' : 'production $scenario failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
