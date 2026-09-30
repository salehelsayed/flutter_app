import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_relay_only_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_catalog.private_relay_only_delivery';

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
    final texts = productionRelayOnlyTexts(run);
    final flows = <String>[];
    final finals = <String, Object?>{};
    final proof = <String, Object?>{
      'runId': run,
      'flows': flows,
      'final': finals,
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
    }) => waitForProductionObservation(
      label,
      const Duration(seconds: 120),
      () async {
        final s = await peer.command(operation, args);
        return predicate(s) ? s : null;
      },
    );

    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      journey.additionalPeers['charlie'] = await journey.reopen(
        journey.additionalPeers['charlie']!,
      );
      final actors = {for (final p in journey.actors) p.invocation.role: p};
      final name = 'Catalog private_relay_only_delivery $run';
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
      proof['relayAddresses'] =
          (await journey.alice.command('catalog_group_snapshot'))['relayAddresses'];
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
      final watch = {
        'aliceToRelayOnlyBob': {
          'text': texts['aliceToRelayOnlyBob'],
          'senderPeerId': peers['alice'],
        },
        'bobRelayOnlyPublishBack': {
          'text': texts['bobRelayOnlyPublishBack'],
          'senderPeerId': peers['bob'],
        },
      };
      int rows(Map<String, Object?> s, String key) =>
          (((s['watched'] as Map?)?[key] as List?) ?? const []).length;
      Future<Map<String, Object?>> received(String role, String key) => wait(
        actors[role]!,
        'catalog_watch_snapshot',
        '$role receives $key',
        (s) => rows(s, key) == 1,
        args: {'texts': watch},
      );
      // Production precondition (not in the original): the contact exchange
      // already connected everyone over Bob's relay circuit, so group
      // discovery never dials Bob. An ordinary restart of Alice and Charlie
      // makes their group rejoin run discovery against the real members.
      final groupId =
          ((await journey.alice.command('catalog_group_snapshot'))['group']
                  as Map)['id']
              as String;
      journey.alice = await journey.reopen(journey.alice);
      actors['alice'] = journey.alice;
      journey.additionalPeers['charlie'] = await journey.reopen(
        journey.additionalPeers['charlie']!,
      );
      actors['charlie'] = journey.additionalPeers['charlie']!;
      for (final role in ['alice', 'charlie']) {
        await wait(
          actors[role]!,
          'catalog_group_snapshot',
          '$role settled after restart',
          (s) =>
              s['relayReady'] == true &&
              s['groupRecoveryActive'] == false &&
              s['group'] is Map,
        );
      }
      // The original's settle interval before the first NW-002 publish.
      await Future<void>.delayed(const Duration(seconds: 5));
      attempts++;
      await flow(journey.alice, 'production_group_send', 'alice-send', {
        'GROUP_ID': groupId,
        'MESSAGE': texts['aliceToRelayOnlyBob']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['aliceToRelayOnlyBob']!),
      });
      await received('bob', 'aliceToRelayOnlyBob');
      await received('charlie', 'aliceToRelayOnlyBob');
      attempts++;
      await flow(journey.bob, 'production_catalog_group_send', 'bob-publish-back', {
        'MESSAGE': texts['bobRelayOnlyPublishBack']!,
        'MESSAGE_PATTERN': RegExp.escape(texts['bobRelayOnlyPublishBack']!),
      });
      await received('alice', 'bobRelayOnlyPublishBack');
      await received('charlie', 'bobRelayOnlyPublishBack');
      // Retain the original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final entry in actors.entries) {
        finals[entry.key] = await entry.value.command('catalog_watch_snapshot', {
          'texts': watch,
        });
      }
      await persist();
      final failures = validateProductionGroupRelayOnly(proof);
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
      validatorIds: ['validateProductionGroupRelayOnly'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private_relay_only_delivery passed' : 'production private_relay_only_delivery failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
