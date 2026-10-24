import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_direct_actions_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionDirectActions);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError('this scenario requires the disposable emulator pair');
    }
    final destination = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (destination == null || destination.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      destination,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      directActionsRuntime,
      output,
    );
    final ui = <String, Object?>{};
    final phases = <String, Object?>{};
    final kills = <String, Object?>{};
    final nonces = <String, List<String>>{};
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': directActionsRuntime,
      'emulatorPair': journey.disposableAndroidJourneys,
      'ui': ui,
      'phases': phases,
      'ownedKills': kills,
      'nonces': nonces,
    };
    final texts = directActionsTexts(journey.runId);
    final patterns = directActionsPatterns(journey.runId);
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    ProductionJourneyPeer actor(String role) =>
        role == 'alice' ? journey.alice : journey.bob;
    Future<void> flow(
      String role,
      String name,
      String label,
      Map<String, String> values,
    ) async {
      attempted++;
      final receipt = await journey.flow(actor(role), name, label, values);
      ui[label] = {
        'flow': name,
        'values': values,
        'path': receipt,
        'receipt': jsonDecode(await File(receipt).readAsString()),
      };
      await persist();
    }

    Future<void> assertAction(
      String role,
      String label,
      String visible,
      String absent,
    ) => flow(role, 'production_direct_assert_action', label, {
      'VISIBLE_PATTERN': visible,
      'ABSENT_PATTERN': absent,
    });
    var firstFailureRecorded = false;
    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      final peers = {
        'alice': (await journey.alice.command('identity'))['peerId']! as String,
        'bob': (await journey.bob.command('identity'))['peerId']! as String,
      };
      proof['peers'] = peers;
      for (final role in ['alice', 'bob']) {
        nonces[role] = [actor(role).invocation.nonce];
        await flow(role, 'production_direct_open', 'open-$role', {
          'PEER_ID': peers[role == 'alice' ? 'bob' : 'alice']!,
        });
      }
      Map<String, String> sendValues(String key) => {
        'MESSAGE': texts[key]!,
        'MESSAGE_PATTERN': RegExp.escape(texts[key]!),
      };
      await flow(
        'alice',
        'production_direct_send',
        'send-parent',
        sendValues('parent'),
      );
      await flow('bob', 'production_catalog_quote_reply', 'reply-bob', {
        'PARENT_PATTERN': RegExp.escape(texts['parent']!),
        ...sendValues('reply'),
      });
      await flow(
        'alice',
        'production_direct_send',
        'send-deletion-target',
        sendValues('deleted'),
      );
      final ids = <String, String>{};
      Future<Map<String, Object?>> snapshot(
        String role, {
        bool deleted = false,
      }) async {
        final peer = actor(role);
        final value = await peer.command('routing_snapshot', {
          'peerIds': [peers[role == 'alice' ? 'bob' : 'alice']],
          'groupIds': <String>[],
          if (deleted) 'messageIds': [ids['deleted']],
        });
        return {
          ...value,
          'observedRole': role,
          'observedRunId': peer.invocation.runId,
          'observedNonce': peer.invocation.nonce,
        };
      }

      Future<void> settled(String phase) async {
        final deleted = phase == 'deleted' || phase == 'restarted';
        final expected = {
          'parent': texts['parent'],
          'reply': texts[phase == 'quoted' ? 'reply' : 'edited'],
          if (!deleted) 'deleted': texts['deleted'],
        };
        final pair = <String, Object?>{};
        for (final role in ['alice', 'bob']) {
          pair[role] = await waitForProductionObservation(
            '$phase/$role stable exact direct action rows',
            const Duration(minutes: 2),
            () async {
              final value = await snapshot(role, deleted: deleted);
              final rows = (value['messages'] as List)
                  .whereType<Map>()
                  .toList();
              if (rows.length != 3) return null;
              for (final entry in expected.entries) {
                final found = rows
                    .where(
                      (r) => r['text'] == entry.value && r['deletedAt'] == null,
                    )
                    .toList();
                if (found.length != 1 ||
                    (ids.containsKey(entry.key) &&
                        found.single['id'] != ids[entry.key])) {
                  return null;
                }
              }
              if (deleted) {
                final tombstones = (value['tombstones'] as List)
                    .whereType<Map>()
                    .toList();
                if (tombstones.length != 1 ||
                    tombstones.single['id'] != ids['deleted'] ||
                    tombstones.single['deletedAt'] == null) {
                  return null;
                }
              }
              return value;
            },
          );
        }
        phases[phase] = pair;
        await persist();
      }

      await settled('quoted');
      final initialRows =
          ((phases['quoted'] as Map)['alice'] as Map)['messages'] as List;
      for (final key in ['parent', 'reply', 'deleted']) {
        ids[key] =
            (initialRows.whereType<Map>().singleWhere(
                  (r) => r['text'] == texts[key],
                )['id'])
                as String;
      }
      for (final role in ['alice', 'bob']) {
        await assertAction(
          role,
          'quote-$role',
          patterns['quote']!,
          'NEVER_PRESENT_SENTINEL_${journey.runId}',
        );
      }
      await flow('alice', 'production_direct_reaction_toggle', 'reaction-add', {
        'MESSAGE_ID': ids['parent']!,
      });
      for (final role in ['alice', 'bob']) {
        await flow(
          role,
          'production_direct_assert_reaction_present',
          'reaction-added-$role',
          {'MESSAGE_ID': ids['parent']!},
        );
      }
      await flow(
        'alice',
        'production_direct_reaction_toggle',
        'reaction-remove',
        {'MESSAGE_ID': ids['parent']!},
      );
      for (final role in ['alice', 'bob']) {
        await flow(
          role,
          'production_direct_assert_reaction_absent',
          'reaction-removed-$role',
          {'MESSAGE_ID': ids['parent']!},
        );
      }
      await flow('bob', 'production_direct_edit', 'edit-bob', {
        'MESSAGE_ID': ids['reply']!,
        'EDITED_MESSAGE': texts['edited']!,
        'EDITED_PATTERN': RegExp.escape(texts['edited']!),
      });
      await settled('edited');
      for (final role in ['alice', 'bob']) {
        await assertAction(
          role,
          'edited-$role',
          patterns['editedQuote']!,
          RegExp.escape(texts['reply']!),
        );
      }
      await flow('alice', 'production_direct_delete', 'delete-alice', {
        'MESSAGE_PATTERN': RegExp.escape(texts['deleted']!),
      });
      Future<void> finalUi(String phase) async {
        for (final role in ['alice', 'bob']) {
          await assertAction(
            role,
            '$phase-$role',
            patterns['editedQuote']!,
            patterns['deleted']!,
          );
          await assertAction(
            role,
            '$phase-placeholder-$role',
            'This message was deleted',
            patterns['deleted']!,
          );
          await flow(
            role,
            'production_direct_assert_reaction_absent',
            '$phase-reaction-removed-$role',
            {'MESSAGE_ID': ids['parent']!},
          );
        }
      }

      await settled('deleted');
      await finalUi('deleted');
      for (final role in ['alice', 'bob']) {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await persist();
      }
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      for (final role in ['alice', 'bob']) {
        nonces[role]!.add(actor(role).invocation.nonce);
        await flow(role, 'production_direct_open', 'reopen-$role', {
          'PEER_ID': peers[role == 'alice' ? 'bob' : 'alice']!,
        });
      }
      await settled('restarted');
      await finalUi('restarted');
      final failures = validateProductionDirectActions(proof);
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } catch (error, stack) {
      firstFailureRecorded = true;
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      try {
        await journey.restore();
      } catch (error, stack) {
        await File(
          '${output.path}/cleanup-failure.txt',
        ).writeAsString('$error\n$stack');
        if (!firstFailureRecorded) rethrow;
      }
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionDirectActions,
      validatorIds: ['validateProductionDirectActions'],
      payload: {...journey.provenance(), ...proof, 'status': 'PASS'},
    );
  } catch (error, stack) {
    if (output != null) {
      final file = File('${output.path}/first-failure.txt');
      if (!file.existsSync()) await file.writeAsString('$error\n$stack');
    }
  }
  final passed = evidence != null;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'DC-006 UI actions and durable convergence passed' : 'DC-006 incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
