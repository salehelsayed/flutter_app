import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_delete_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_delete_preserves_friends';

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
    final texts = productionDeleteTexts(journey.runId);
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
      var charlie = journey.additionalPeers['charlie']!;
      final peers = {
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
        'charlie': (await charlie.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      // Group fixture is a prerequisite; the operation under test is Bob's
      // ordinary Orbit delete.
      final fixture = await journey.alice.command('prepare_group', {
        'peerId': peers['bob'],
      });
      final groupId = (fixture['group']! as Map)['id']! as String;
      proof['groupId'] = groupId;
      await journey.bob.command('import_group', fixture);
      await journey.alice.command('mark_fixture_joined', {
        'groupId': groupId,
        'peerId': peers['bob'],
        'username': 'Journeybob',
      });
      await persist();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      charlie = await journey.reopen(charlie);

      Future<Map<String, Object?>> snapshot(ProductionJourneyPeer peer) =>
          peer.command('delete_snapshot', {
            'groupId': groupId,
            'friendPeerIds': [
              for (final role in ['alice', 'bob', 'charlie'])
                if (role != peer.invocation.role) peers[role],
            ],
          });
      Future<Map<String, Object?>> wait(
        String stage,
        ProductionJourneyPeer peer,
        Duration timeout,
        bool Function(Map<String, Object?>) predicate,
      ) async {
        final elapsed = Stopwatch()..start();
        final value = await waitForProductionObservation(stage, timeout, () async {
          final current = await snapshot(peer);
          return predicate(current) ? current : null;
        });
        waits[stage] = elapsed.elapsedMilliseconds;
        proof[stage] = value;
        await persist();
        return value;
      }

      Future<void> flow(
        ProductionJourneyPeer peer,
        String name,
        String label, [
        Map<String, String> values = const {},
      ]) async {
        await journey.flow(peer, name, label, values);
        flows.add(label);
      }

      Future<void> direct(
        ProductionJourneyPeer from,
        String to,
        String text,
        String label,
      ) async {
        await journey.flow(from, 'production_direct_open', '$label-open', {
          'PEER_ID': peers[to]!,
        });
        await flow(from, 'production_direct_send', label, {
          'MESSAGE': text,
          'MESSAGE_PATTERN': RegExp.escape(text),
        });
        await journey.flow(from, 'production_conversation_back', '$label-back');
      }

      bool hasDirect(Map<String, Object?> s, String peer, String text) =>
          ((s['direct'] as Map?)?[peers[peer]] as List? ?? const []).any(
            (m) => (m as Map)['text'] == text,
          );

      attempts++;
      await direct(journey.alice, 'bob', texts['aliceHello']!, 'alice-send-bob');
      await direct(journey.bob, 'alice', texts['aliceReply']!, 'bob-send-alice');
      await direct(charlie, 'bob', texts['charlieHello']!, 'charlie-send-bob');
      await direct(
        journey.bob,
        'charlie',
        texts['charlieReply']!,
        'bob-send-charlie',
      );
      for (final (key, label) in [
        ('groupOne', 'alice-group-one'),
        ('groupTwo', 'alice-group-two'),
      ]) {
        await flow(journey.alice, 'production_group_send', label, {
          'GROUP_ID': groupId,
          'MESSAGE': texts[key]!,
          'MESSAGE_PATTERN': RegExp.escape(texts[key]!),
        });
      }
      await wait(
        'beforeDelete',
        journey.bob,
        const Duration(minutes: 3),
        (s) =>
            hasDirect(s, 'alice', texts['aliceHello']!) &&
            hasDirect(s, 'charlie', texts['charlieHello']!) &&
            [texts['groupOne'], texts['groupTwo']].every(
              (text) => (s['groupMessages'] as List).any(
                (m) => (m as Map)['text'] == text,
              ),
            ),
      );
      proof['adminBefore'] = await snapshot(journey.alice);
      await persist();

      await flow(journey.bob, 'production_orbit_group_leave_delete', 'bob-leave-delete', {
        'GROUP_ID': groupId,
        'ALICE_PEER_ID': peers['alice']!,
        'CHARLIE_PEER_ID': peers['charlie']!,
      });
      await wait(
        'afterDelete',
        journey.bob,
        const Duration(seconds: 60),
        (s) => s['group'] == null && (s['groupMessages'] as List).isEmpty,
      );
      await wait(
        'adminAfter',
        journey.alice,
        const Duration(minutes: 3),
        (s) =>
            s['group'] is Map &&
            !((s['group'] as Map)['members'] as List).contains(peers['bob']),
      );

      for (final (friend, first, second) in [
        ('alice', 'aliceHello', 'aliceReply'),
        ('charlie', 'charlieHello', 'charlieReply'),
      ]) {
        await flow(journey.bob, 'production_direct_open', 'bob-open-$friend', {
          'PEER_ID': peers[friend]!,
        });
        await flow(journey.bob, 'production_direct_assert_two', 'bob-render-$friend', {
          'FIRST_PATTERN': RegExp.escape(texts[first]!),
          'SECOND_PATTERN': RegExp.escape(texts[second]!),
        });
        await flow(journey.bob, 'production_conversation_back', 'bob-back-$friend');
      }
      proof['afterUi'] = await snapshot(journey.bob);
      cases.add({'id': 'DELETE_PRESERVES_FRIENDS', 'status': 'PASS'});
      await persist();
      final failures = validateProductionGroupDelete(proof);
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
      validatorIds: ['validateProductionGroupDelete'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production group delete preserves friends passed' : 'production group delete preserves friends failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
