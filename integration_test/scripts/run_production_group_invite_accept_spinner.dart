import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_accept_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_invite_accept_spinner';

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
    final name = 'Writers Room ${journey.runId}';
    final flows = <String>[];
    final waits = <String, int>{};
    final cases = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'flows': flows,
      'waits': waits,
      'cases': cases,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));

    try {
      await journey.prepare();
      proof['peers'] = {
        'alice': (await journey.alice.command('identity'))['peerId'],
        'bob': (await journey.bob.command('identity'))['peerId'],
      };
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      attempts++;
      await journey.flow(journey.alice, 'production_group_create', 'alice-create', {
        'CONTACT_NAME': 'Journeybob',
        'GROUP_NAME': name,
      });
      flows.add('alice-create');
      final elapsed = Stopwatch()..start();
      proof['invited'] = await waitForProductionObservation(
        'invited',
        const Duration(minutes: 4),
        () async {
          await journey.bob.command('accept_drain_inbox');
          final s = await journey.bob.command('accept_snapshot');
          return (s['pending'] as List).length == 1 ? s : null;
        },
      );
      waits['invited'] = elapsed.elapsedMilliseconds;
      await persist();
      await journey.flow(
        journey.bob,
        'production_group_invite_accept_spinner',
        'bob-accept',
        {'GROUP_NAME': name},
      );
      flows.add('bob-accept');
      proof['accepted'] = await journey.bob.command('accept_snapshot');
      proof['creator'] = await journey.alice.command('accept_snapshot');
      cases.add({'id': 'INVITE_ACCEPT_SPINNER', 'status': 'PASS'});
      await persist();
      final failures = validateProductionGroupAccept(proof);
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
      validatorIds: ['validateProductionGroupAccept'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production invite accept spinner passed' : 'production invite accept spinner failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
