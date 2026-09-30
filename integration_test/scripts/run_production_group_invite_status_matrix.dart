import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_invite_matrix_criteria.dart';
import '../support/production_android_journey.dart';

const _scenario = 'production.group_invite_status_matrix';

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
    final flows = <String>[];
    final cases = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'flows': flows,
      'cases': cases,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));

    try {
      await journey.prepare();
      final peers = {
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      final seed = {'adminPeerId': peers['alice'], 'memberPeerId': peers['bob']};
      final seeded = await journey.alice.command('prepare_invite_matrix', seed);
      await journey.bob.command('prepare_invite_matrix', seed);
      final groupId = seeded['groupId'];
      if (groupId is! String || groupId.isEmpty) {
        throw StateError('matrix group was not seeded');
      }
      proof['groupId'] = groupId;
      proof['creatorSeeded'] = await journey.alice.command(
        'invite_matrix_snapshot',
      );
      proof['memberSeeded'] = await journey.bob.command(
        'invite_matrix_snapshot',
      );
      await persist();
      // Ordinary reopen so Orbit lists the seeded group.
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      final values = {
        'GROUP_ID': groupId,
        'GROUP_NAME': 'Invite Status Matrix ${journey.runId}',
      };
      attempts++;
      for (final (peer, flow, label) in [
        (journey.alice, 'production_group_open', 'alice-open-matrix'),
        (journey.alice, 'production_group_invite_matrix', 'alice-invite-matrix'),
      ]) {
        await journey.flow(peer, flow, label, values);
        flows.add(label);
      }
      proof['creatorObserved'] = await journey.alice.command(
        'invite_matrix_snapshot',
      );
      cases.add({'id': 'UP-005', 'status': 'PASS'});
      await persist();
      attempts++;
      for (final (peer, flow, label) in [
        (journey.bob, 'production_group_open', 'bob-open-matrix'),
        (journey.bob, 'production_group_info_self', 'bob-info-self'),
      ]) {
        await journey.flow(peer, flow, label, values);
        flows.add(label);
      }
      proof['memberObserved'] = await journey.bob.command(
        'invite_matrix_snapshot',
      );
      cases.add({'id': 'MEMBER-ROLE-ATTACH', 'status': 'PASS'});
      await persist();
      final failures = validateProductionGroupInviteMatrix(proof);
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
      validatorIds: ['validateProductionGroupInviteMatrix'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production invite status matrix passed' : 'production invite status matrix failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
