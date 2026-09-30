import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_private_media_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.private_media_local';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  SimsArtifactEvidence? evidence;
  Directory? output;
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
    final proof = <String, Object?>{
      'runId': journey.runId,
      'claims': {'remoteRevocation': false, 'accountWideConsumption': false},
    };
    Future<Map<String, Object?>> capture(
      String stage,
      ProductionJourneyPeer peer,
    ) async {
      final value = await peer.command('private_local_snapshot');
      proof[stage] = value;
      await File(
        '${output!.path}/observations.json',
      ).writeAsString(jsonEncode(proof));
      return value;
    }

    Future<void> window(String name, ProductionJourneyPeer peer) async {
      final result = await peer.adb(['shell', 'dumpsys', 'window', 'windows']);
      if (result.exitCode != 0) {
        throw StateError('native private window observation failed');
      }
      proof[name] = {
        ...observeProductionPrivateWindow('${result.stdout}'),
        'role': peer.invocation.role,
      };
      await File(
        '${output!.path}/observations.json',
      ).writeAsString(jsonEncode(proof));
    }

    try {
      await journey.prepare();
      final aliceId =
          (await journey.alice.command('identity'))['peerId']! as String;
      final bobId =
          (await journey.bob.command('identity'))['peerId']! as String;
      proof['peers'] = {'alice': aliceId, 'bob': bobId};
      await journey.alice.command('prepare_private_local_fixtures', {
        'peerId': bobId,
        'set': 'sender_pending',
      });
      await journey.bob.command('prepare_private_local_fixtures', {
        'peerId': aliceId,
        'set': 'projection',
      });
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      await journey.flow(
        journey.bob,
        'production_direct_open',
        'projection-open',
        {'PEER_ID': aliceId},
      );
      attempts++;
      await capture('projection', journey.bob);
      await window('protectedWindow', journey.bob);
      await journey.flow(
        journey.bob,
        'production_private_terminal_delete',
        'terminal-delete',
        {'MESSAGE_ID': 'private-${journey.runId}-terminal'},
      );
      await capture('deleted', journey.bob);
      attempts++;
      await journey.flow(
        journey.bob,
        'production_private_open',
        'incoming-open',
        {'MESSAGE_ID': 'private-${journey.runId}-incoming'},
      );
      await capture('incomingViewing', journey.bob);
      await journey.flow(
        journey.bob,
        'production_private_close',
        'incoming-close',
      );
      await waitForProductionObservation(
        'recipient committed consume and cleanup',
        const Duration(seconds: 5),
        () async {
          final value = await journey.bob.command('private_local_snapshot');
          final row = (value['rows'] as List).cast<Map>().singleWhere(
            (r) => r['name'] == 'incoming',
          );
          return (row['sql'] as List).single['private_media_state'] ==
                      'consumed' &&
                  row['fileExists'] == false &&
                  (row['attachments'] as List).isEmpty
              ? value
              : null;
        },
      );
      await capture('incomingConsumed', journey.bob);
      proof['recipientBeforeNonce'] = journey.bob.invocation.nonce;
      journey.bob = await journey.reopen(journey.bob);
      proof['recipientAfterNonce'] = journey.bob.invocation.nonce;
      await journey.flow(
        journey.bob,
        'production_direct_open',
        'cold-recipient-chat',
        {'PEER_ID': aliceId},
      );
      await capture('incomingColdConsumed', journey.bob);
      await journey.flow(
        journey.bob,
        'production_private_refuse_reopen',
        'incoming-refused',
        {'MESSAGE_ID': 'private-${journey.runId}-incoming'},
      );
      await capture('incomingRefused', journey.bob);
      await journey.flow(
        journey.alice,
        'production_direct_open',
        'pending-chat',
        {'PEER_ID': bobId},
      );
      await capture('available', journey.alice);
      await window('senderBeforeWindow', journey.alice);
      attempts++;
      await journey.flow(
        journey.alice,
        'production_private_open',
        'pending-open',
        {'MESSAGE_ID': 'private-${journey.runId}-sender_pending'},
      );
      await capture('viewing', journey.alice);
      await window('senderViewingWindow', journey.alice);
      await journey.flow(
        journey.alice,
        'production_private_close',
        'pending-close',
      );
      await waitForProductionObservation(
        'committed consume and cleanup',
        const Duration(seconds: 5),
        () async {
          final value = await journey.alice.command('private_local_snapshot');
          final row = (value['rows'] as List).single as Map;
          return (row['sql'] as List).single['private_media_state'] ==
                      'consumed' &&
                  row['fileExists'] == false &&
                  (row['attachments'] as List).isEmpty
              ? value
              : null;
        },
      );
      await capture('consumed', journey.alice);
      await window('senderAfterWindow', journey.alice);
      proof['beforeNonce'] = journey.alice.invocation.nonce;
      journey.alice = await journey.reopen(journey.alice);
      proof['afterNonce'] = journey.alice.invocation.nonce;
      await journey.flow(
        journey.alice,
        'production_direct_open',
        'cold-pending-chat',
        {'PEER_ID': bobId},
      );
      attempts++;
      await capture('coldConsumed', journey.alice);
      await journey.flow(
        journey.alice,
        'production_private_refuse_reopen',
        'consumed-refused',
        {'MESSAGE_ID': 'private-${journey.runId}-sender_pending'},
      );
      await capture('refused', journey.alice);
      final failures = validateProductionPrivateMedia(proof);
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
      validatorIds: ['validateProductionPrivateMedia'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private-media local lifecycle passed' : 'production private-media local journey failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
