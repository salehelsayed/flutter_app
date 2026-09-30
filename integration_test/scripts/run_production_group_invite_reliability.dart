import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_invite_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_invite_reliability';

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
    final waits = <String, int>{};
    final cases = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'waits': waits,
      'cases': cases,
    };
    final name = 'Invite Reliability ${journey.runId}';
    final peers = <String, String>{};
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<Map<String, Object?>> snapshot(ProductionJourneyPeer peer) =>
        peer.command('invite_snapshot', {
          'peerId': peers[peer.invocation.role == 'alice' ? 'bob' : 'alice'],
        });
    Future<Map<String, Object?>> capture(
      String stage,
      ProductionJourneyPeer peer,
    ) async {
      final value = await snapshot(peer);
      proof[stage] = value;
      await persist();
      return value;
    }

    Future<Map<String, Object?>> wait(
      String stage,
      ProductionJourneyPeer peer,
      Duration timeout,
      bool Function(Map<String, Object?>) predicate, {
      bool drainOther = false,
    }) async {
      final elapsed = Stopwatch()..start();
      final value = await waitForProductionObservation(
        stage,
        timeout,
        () async {
          await peer.command('invite_drain_inbox');
          if (drainOther) await journey.alice.command('invite_drain_inbox');
          final current = await snapshot(peer);
          return predicate(current) ? current : null;
        },
      );
      waits[stage] = elapsed.elapsedMilliseconds;
      proof[stage] = value;
      await persist();
      return value;
    }

    try {
      await journey.prepare();
      peers['alice'] =
          (await journey.alice.command('identity'))['peerId']! as String;
      peers['bob'] =
          (await journey.bob.command('identity'))['peerId']! as String;
      proof['peers'] = peers;
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      await snapshot(journey.alice);
      await snapshot(journey.bob);
      attempts++;
      await journey.flow(
        journey.alice,
        'production_group_create',
        'create-invitation',
        {'CONTACT_NAME': 'Journeybob', 'GROUP_NAME': name},
      );
      final created = await capture('created', journey.alice);
      final groupId = created['groupId'];
      if (groupId is! String || groupId.isEmpty) {
        throw StateError('UI did not create exact group');
      }
      proof['groupId'] = groupId;
      final staleFixture = await journey.alice.command(
        'export_invite_stale_fixture',
      );
      final first = await wait(
        'receivedFirst',
        journey.bob,
        const Duration(minutes: 4),
        (v) => (v['pending'] as List).length == 1,
      );
      final firstId = (first['pending'] as List).single['inviteId'];
      await journey.flow(
        journey.bob,
        'production_group_invite_decline',
        'decline-first',
        {'GROUP_NAME': name},
      );
      await capture('declinedRecipient', journey.bob);
      await wait(
        'declinedSender',
        journey.alice,
        const Duration(seconds: 150),
        (v) =>
            v['attempt'] is Map &&
            (v['attempt'] as Map)['status'] == 'declined',
      );
      cases.add({'id': 'F', 'status': 'PASS'});
      attempts++;
      await journey.alice.command('resend_declined_invite');
      await capture('resent', journey.alice);
      await wait(
        'receivedSecond',
        journey.bob,
        const Duration(seconds: 150),
        (v) =>
            (v['pending'] as List).length == 1 &&
            (v['pending'] as List).single['inviteId'] != firstId,
      );
      await journey.flow(
        journey.alice,
        'production_group_invite_revoke',
        'revoke-second',
      );
      await capture('revokedSender', journey.alice);
      await wait(
        'revokedRecipient',
        journey.bob,
        const Duration(seconds: 150),
        (v) =>
            (v['pending'] as List).isEmpty && (v['revoked'] as List).isNotEmpty,
      );
      cases.add({'id': 'C', 'status': 'PASS'});
      attempts++;
      await journey.bob.command('import_group', staleFixture);
      await capture('staleRecipient', journey.bob);
      await journey.alice.command('prepare_invite_fresh_metadata');
      await capture('freshSender', journey.alice);
      proof['metadataRequest'] = await journey.bob.command(
        'request_invite_metadata',
      );
      await wait(
        'convergedRecipient',
        journey.bob,
        const Duration(minutes: 4),
        (v) =>
            v['group'] is Map && (v['group'] as Map)['name'] == '$name (fresh)',
        drainOther: true,
      );
      cases.add({'id': 'D', 'status': 'PASS'});
      await persist();
      final failures = validateProductionGroupInvite(proof);
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
      validatorIds: ['validateProductionGroupInvite'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production invitation F C D passed' : 'production invitation journey failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
