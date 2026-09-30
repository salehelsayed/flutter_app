import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_online_remove_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_catalog.private_online_remove';
const _original = 'integration_test/group_multi_party_device_real_harness.dart';

/// The original PL-006 fixture: `_pngFixtureBytes([6, 0, 0, 6, 42, 43, 44, 45])`,
/// read from the unchanged original harness.
String _pl006PngBase64() {
  final source = File(_original).readAsStringSync();
  final match = RegExp(
    r"List<int> _pngFixtureBytes\(List<int> suffix\) \{\s*return <int>\[\s*\.\.\.base64Decode\(\s*'([^']+)'",
  ).firstMatch(source);
  if (match == null) throw StateError('original PL-006 fixture missing');
  return base64Encode([
    ...base64Decode(match.group(1)!),
    ...[6, 0, 0, 6, 42, 43, 44, 45],
  ]);
}

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
    final texts = productionOnlineRemoveTexts(run);
    final flows = <String>[];
    final clock = Stopwatch()..start();
    final order = <String, int>{};
    final proof = <String, Object?>{
      'runId': run,
      'flows': flows,
      'order': order,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<void> flow(
      ProductionJourneyPeer peer,
      String name,
      String label, [
      Map<String, String> values = const {},
    ]) async {
      await journey.flow(peer, name, label, values);
      flows.add(label);
      await persist();
    }

    Future<Map<String, Object?>> wait(
      ProductionJourneyPeer peer,
      String operation,
      String label,
      bool Function(Map<String, Object?>) predicate, {
      Map<String, Object?> args = const {},
      Duration timeout = const Duration(seconds: 120),
    }) => waitForProductionObservation(label, timeout, () async {
      final s = await peer.command(operation, args);
      return predicate(s) ? s : null;
    });

    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      journey.additionalPeers['charlie'] = await journey.reopen(
        journey.additionalPeers['charlie']!,
      );
      final actors = {for (final p in journey.actors) p.invocation.role: p};
      final name = 'Catalog private_online_remove $run';
      for (final p in actors.values) {
        final ready = await wait(
          p,
          'catalog_group_snapshot',
          '${p.invocation.role} production readiness',
          (s) =>
              s['relayReady'] == true &&
              s['sendReady'] == true &&
              s['inboxReady'] == true &&
              s['groupRecoveryActive'] == false &&
              s['lifecycle'] == 'resumed',
        );
        final invite = await p.command('catalog_pending_snapshot');
        if (ready['group'] != null || (invite['pending'] as List).isNotEmpty) {
          throw StateError('catalog fixture is not initially empty');
        }
      }
      attempts++;
      await flow(journey.alice, 'production_catalog_group_create', 'create', {
        'GROUP_NAME': name,
      });
      final created = await journey.alice.command('catalog_group_snapshot');
      proof['relayAddresses'] = created['relayAddresses'];
      for (final role in ['bob', 'charlie']) {
        await wait(
          actors[role]!,
          'catalog_pending_snapshot',
          '$role pending invitation',
          (s) => (s['pending'] as List).length == 1,
        );
      }
      for (final role in ['bob', 'charlie']) {
        await flow(
          actors[role]!,
          'production_catalog_invite_accept',
          'accept-$role',
          {'GROUP_NAME': name},
        );
      }
      final peers = <String, String>{};
      for (final entry in actors.entries) {
        // Removal is refused while group recovery/resync is in progress.
        final s = await wait(
          entry.value,
          'catalog_group_snapshot',
          '${entry.key} settled three-member group',
          (s) =>
              s['group'] is Map &&
              ((s['group'] as Map)['members'] as List).length == 3 &&
              s['groupRecoveryActive'] == false,
        );
        peers[entry.key] = s['peerId']! as String;
      }
      proof['peers'] = peers;
      final watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value,
            'senderPeerId': peers[entry.key.startsWith('alice') ? 'alice' : 'bob'],
          },
      };
      Future<Map<String, Object?>> snap(
        String role, [
        Map<String, Object?> extra = const {},
      ]) => actors[role]!.command('online_remove_snapshot', {
        'texts': watch,
        ...extra,
      });
      Future<Map<String, Object?>> waitSnap(
        String role,
        String label,
        bool Function(Map<String, Object?>) predicate, {
        Map<String, Object?> extra = const {},
        Duration timeout = const Duration(seconds: 120),
      }) => wait(
        actors[role]!,
        'online_remove_snapshot',
        label,
        predicate,
        args: {'texts': watch, ...extra},
        timeout: timeout,
      );
      int rows(Map<String, Object?> s, String key) =>
          (((s['watched'] as Map?)?[key] as List?) ?? const []).length;

      proof['charlieBefore'] = await snap('charlie');
      attempts++;
      // ST-006: hold Alice's rotated-key send to Bob so Bob publishes during
      // the rotation, exactly as the original's distribution callback does.
      await journey.alice.command('online_remove_arm_rotation_hold', {
        'bobPeerId': peers['bob'],
      });
      await flow(
        journey.alice,
        'production_catalog_remove_charlie_start',
        'remove-charlie-start',
        {'CHARLIE_PEER_ID': peers['charlie']!},
      );
      proof['rotationHeld'] = await wait(
        journey.alice,
        'online_remove_rotation_state',
        'rotation held at Bob',
        (s) => s['held'] == true,
      );
      proof['bobExcluded'] = await waitSnap(
        'bob',
        'Bob excludes Charlie',
        (s) => !(s['memberPeerIds'] as List).contains(peers['charlie']),
      );
      proof['charlieRemoved'] = await waitSnap(
        'charlie',
        'Charlie self removal',
        (s) => s['selfMember'] == false,
      );
      await flow(journey.bob, 'production_catalog_group_send', 'bob-send-during-rotation', {
        'MESSAGE': texts['st006BobDuringRotation']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['st006BobDuringRotation']!),
      });
      proof['st006Sent'] = await snap('bob');
      proof['st006Received'] = await waitSnap(
        'alice',
        'Alice receives Bob during rotation',
        (s) => rows(s, 'st006BobDuringRotation') == 1,
      );
      proof['rotationAtSt006Receive'] = await journey.alice.command(
        'online_remove_rotation_state',
      );
      await journey.alice.command('online_remove_release_rotation');
      final rotated = await wait(
        journey.alice,
        'online_remove_rotation_state',
        'Alice rotated epoch',
        (s) => (s['keyEpoch'] as int) >= 2,
      );
      proof['bobRotated'] = await waitSnap(
        'bob',
        'Bob holds rotated key',
        (s) => s['keyEpoch'] == rotated['keyEpoch'],
      );
      order['bobRotatedAtMs'] = clock.elapsedMilliseconds;
      await flow(
        journey.alice,
        'production_catalog_remove_charlie_verify',
        'remove-charlie-verify',
        {'CHARLIE_PEER_ID': peers['charlie']!},
      );
      attempts++;
      order['aliceSendStartMs'] = clock.elapsedMilliseconds;
      final aliceSent = await journey.alice.command(
        'online_remove_send_media_message',
        {
          'text': texts['aliceAfterCharlieRemove'],
          'pngBase64': _pl006PngBase64(),
          'bobPeerId': peers['bob'],
          'charliePeerId': peers['charlie'],
        },
      );
      proof['aliceSent'] = aliceSent;
      await persist();
      final bobReceived = await waitSnap(
        'bob',
        'Bob receives Alice after removal',
        (s) => rows(s, 'aliceAfterCharlieRemove') == 1,
      );
      final aliceMessageId =
          (((bobReceived['watched'] as Map)['aliceAfterCharlieRemove']
                      as List)
                  .single
              as Map)['messageId'];
      // Retain the original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      proof['bobReceivedAlice'] = await snap('bob');
      proof['bobMedia'] = await journey.bob.command(
        'online_remove_download_media',
        {'messageId': aliceMessageId},
      );
      await flow(journey.bob, 'production_catalog_group_send', 'bob-send-after-removal', {
        'MESSAGE': texts['bobAfterCharlieRemove']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['bobAfterCharlieRemove']!),
      });
      proof['bobSentAfter'] = await snap('bob');
      await waitSnap(
        'alice',
        'Alice receives Bob after removal',
        (s) => rows(s, 'bobAfterCharlieRemove') == 1,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      proof['aliceReceivedBob'] = await snap('alice');
      await persist();

      attempts++;
      final blobId = (aliceSent['upload'] as Map)['blobId'];
      proof['charlieDownload'] = await actors['charlie']!.command(
        'online_remove_direct_download',
        {'blobId': blobId},
      );
      // The original's five-second absence window before counting leaks.
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['charlieLeak'] = await snap('charlie', {
        'mediaMessageId': aliceMessageId,
      });
      proof['charlieRejected'] = await actors['charlie']!.command(
        'online_remove_attempt_send',
      );
      proof['charlieFinal'] = await snap('charlie');
      proof['aliceFinal'] = await snap('alice');
      proof['bobFinal'] = await snap('bob');
      await persist();
      final failures = validateProductionGroupOnlineRemove(proof);
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
      validatorIds: ['validateProductionGroupOnlineRemove'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private_online_remove passed' : 'production private_online_remove failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
