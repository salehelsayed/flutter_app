import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_removed_reaction_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_catalog.private_removed_reaction_rejected';

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
    final pending = <String, Object?>{};
    final accepted = <String, Object?>{};
    final beforeSend = <String, Object?>{};
    final finals = <String, Object?>{};
    final ui = <String, Object?>{};
    final proof = <String, Object?>{
      'runId': journey.runId,
      'pending': pending,
      'accepted': accepted,
      'beforeSend': beforeSend,
      'final': finals,
      'ui': ui,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<void> flow(
      ProductionJourneyPeer peer,
      String name,
      String label,
      Map<String, String> values,
    ) async {
      final receipt = await journey.flow(peer, name, label, values);
      ui[label] = {
        ...jsonDecode(await File(receipt).readAsString()) as Map,
        'path': receipt,
      };
      await persist();
    }

    Future<Map<String, Object?>> wait(
      ProductionJourneyPeer peer,
      String operation,
      String label,
      bool Function(Map<String, Object?>) predicate,
    ) => waitForProductionObservation(
      label,
      const Duration(seconds: 120),
      () async {
        final s = await peer.command(operation);
        return predicate(s) ? s : null;
      },
    );
    bool hasJoins(Map<String, Object?> snapshot, List<String> roles) {
      final group = snapshot['group'];
      return group is Map &&
          roles.every(
            (r) => (group['messages'] as List).any(
              (m) => m['text'] == 'Journey$r joined the group',
            ),
          );
    }

    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      journey.additionalPeers['charlie'] = await journey.reopen(
        journey.additionalPeers['charlie']!,
      );
      final actors = {for (final p in journey.actors) p.invocation.role: p};
      final name = 'Catalog private_removed_reaction_rejected ${journey.runId}';
      for (final p in actors.values) {
        final group = await wait(
          p,
          'catalog_group_snapshot',
          '${p.invocation.role} production transport and recovery readiness',
          (s) =>
              s['relayReady'] == true &&
              s['sendReady'] == true &&
              s['inboxReady'] == true &&
              s['groupRecoveryActive'] == false &&
              s['lifecycle'] == 'resumed',
        );
        final invite = await p.command('catalog_pending_snapshot');
        if (group['group'] != null || (invite['pending'] as List).isNotEmpty) {
          throw StateError('catalog fixture is not initially empty');
        }
      }
      attempts++;
      await flow(journey.alice, 'production_catalog_group_create', 'create', {
        'GROUP_NAME': name,
      });
      proof['created'] = await journey.alice.command('catalog_group_snapshot');
      await persist();
      // Observe both actual pending invitations before accepting either.
      for (final role in ['bob', 'charlie']) {
        pending[role] = await wait(
          actors[role]!,
          'catalog_pending_snapshot',
          '$role pending invitation',
          (s) => (s['pending'] as List).length == 1,
        );
        await persist();
      }
      for (final role in ['bob', 'charlie']) {
        attempts++;
        await flow(
          actors[role]!,
          'production_catalog_invite_accept',
          'accept-$role',
          {'GROUP_NAME': name},
        );
        accepted[role] = await wait(
          actors[role]!,
          'catalog_pending_snapshot',
          '$role consumed invitation',
          (s) => (s['pending'] as List).isEmpty && s['consumed'] is Map,
        );
        await persist();
      }
      for (final entry in actors.entries) {
        beforeSend[entry.key] = await wait(
          entry.value,
          'catalog_group_snapshot',
          '${entry.key} readable joins',
          (s) => hasJoins(
            s,
            entry.key == 'alice' ? ['bob', 'charlie'] : [entry.key],
          ),
        );
        await persist();
      }
      attempts++;
      final text = 'PL-010 Alice pre-removal reaction target ${journey.runId}';
      await flow(journey.alice, 'production_catalog_group_send', 'send', {
        'MESSAGE': text,
        'MESSAGE_PATTERN': RegExp.escape(text),
      });
      for (final entry in actors.entries) {
        await wait(
          entry.value,
          'catalog_group_snapshot',
          '${entry.key} initial message',
          (s) {
            final group = s['group'];
            return group is Map &&
                (group['messages'] as List).any((m) => m['text'] == text);
          },
        );
      }
      // Retain the original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final entry in actors.entries) {
        finals[entry.key] = await entry.value.command('catalog_group_snapshot');
      }
      await persist();
      final arms = <String, Object?>{};
      final reactions = <String, Object?>{};
      proof['reactionArmed'] = arms;
      proof['removedFinal'] = reactions;
      final alice = finals['alice'] as Map;
      final target =
          ((alice['group'] as Map)['messages'] as List)
                  .where((m) => m['text'] == text)
                  .single['messageId']
              as String;
      final reactor = (finals['charlie'] as Map)['peerId'] as String;
      for (final entry in actors.entries) {
        arms[entry.key] = await entry.value.command(
          'catalog_arm_removed_reaction',
          {'messageId': target, 'reactorPeerId': reactor},
        );
        await persist();
      }
      attempts++;
      await flow(
        actors['alice']!,
        'production_catalog_remove_charlie',
        'remove-charlie',
        {'CHARLIE_PEER_ID': reactor},
      );
      final removed = <String, Object?>{};
      proof['removedBeforeAttempt'] = removed;
      for (final entry in actors.entries) {
        removed[entry.key] = await wait(
          entry.value,
          'catalog_removed_reaction_snapshot',
          '${entry.key} actual membership exclusion',
          (s) =>
              !(s['memberPeerIds'] as List).contains(reactor) &&
              (entry.key == 'charlie' ||
                  (s['memberPeerIds'] as List).length == 2),
        );
        await persist();
      }
      proof['removedAttempt'] = await actors['charlie']!.command(
        'catalog_attempt_removed_reaction',
      );
      await persist();
      // Preserve the original five-second absence observation on both receivers.
      final absence = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['absenceWindowMs'] = absence.elapsedMilliseconds;
      for (final entry in actors.entries) {
        reactions[entry.key] = await entry.value.command(
          'catalog_removed_reaction_snapshot',
        );
      }
      await persist();
      final failures = validateProductionGroupRemovedReaction(proof);
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
      validatorIds: ['validateProductionGroupRemovedReaction'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private_removed_reaction_rejected passed' : 'production private_removed_reaction_rejected failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
