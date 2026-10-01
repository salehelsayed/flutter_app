import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_catalog_case.dart';
import 'production_android_journey.dart';
import 'production_catalog_session.dart';

/// Runs one catalog journey: proof directory, journey and session setup,
/// the watched original texts, the case's [steps], final snapshots of all
/// three roles, the [validate] adapter (unchanged original oracle), cleanup
/// and the SIMS result line.
Future<void> runProductionCatalogJourney({
  required List<String> arguments,
  required String capability,
  required String validatorId,
  required Map<String, ProductionCatalogText> Function(String run) texts,
  required Future<void> Function(ProductionCatalogSession session) steps,
  required List<String> Function(Map<String, Object?> proof) validate,
}) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(capability);
    return;
  }
  final scenario = capability.split('.').last;
  Directory? output;
  SimsArtifactEvidence? evidence;
  // Setup alone attempts no assertion; the case's steps do.
  var attempted = 0;
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
    final proof = <String, Object?>{'runId': journey.runId};
    final s = ProductionCatalogSession(journey, output, proof);
    try {
      await s.start();
      attempted = 1;
      s.watch = {
        for (final MapEntry(:key, :value) in texts(journey.runId).entries)
          key: {'text': value.text, 'senderPeerId': s.peers[value.role]},
      };
      await steps(s);
      for (final role in ['alice', 'bob', 'charlie']) {
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempted, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production $scenario passed' : 'production $scenario failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
