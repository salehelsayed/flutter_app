import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_introduction_mutual_criteria.dart';
import '../../tool/sims/production_introduction_offline_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_intro_probe.dart';
import '../support/production_intro_offline_probe.dart';
import '../support/production_journey_peer.dart';
import '../support/production_sims_result.dart';

Future<void> main(List<String> arguments) =>
    runProductionIntroductionJourney(arguments);

Future<void> runProductionIntroductionJourney(
  List<String> arguments, {
  bool offlineOutbox = false,
}) async {
  final scenario = offlineOutbox
      ? productionIntroductionOffline
      : productionIntroductionMutual;
  final validator = offlineOutbox
      ? 'validateProductionIntroductionOffline'
      : 'validateProductionIntroductionMutual';
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(scenario);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    if (Platform.environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] != '1') {
      throw StateError(
        'this scenario requires three disposable emulator roles',
      );
    }
    final destination = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (destination == null || destination.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      destination,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      introductionMutualRuntime,
      output,
      prepareContactMesh: false,
    );
    const roles = ['alice', 'bob', 'charlie'];
    ProductionJourneyPeer actor(String role) => role == 'alice'
        ? journey.alice
        : role == 'bob'
        ? journey.bob
        : journey.additionalPeers[role]!;
    void replace(String role, ProductionJourneyPeer peer) {
      if (role == 'alice') {
        journey.alice = peer;
      } else if (role == 'bob') {
        journey.bob = peer;
      } else {
        journey.additionalPeers[role] = peer;
      }
    }

    final ui = <String, Object?>{},
        phases = <String, Object?>{},
        kills = <String, Object?>{};
    final nonces = <String, List<String>>{},
        probeAttempts = <String, List<Object?>>{};
    final trace = <String>[];
    final manualEdges = <Map<String, String>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': introductionMutualRuntime,
      'offlineOutbox': offlineOutbox,
      'emulatorTopology': journey.disposableAndroidJourneys,
      'prepareContactMesh': false,
      'ui': ui,
      'phases': phases,
      'ownedKills': kills,
      'nonces': nonces,
      'trace': trace,
      'manualEdges': manualEdges,
      'probeAttempts': probeAttempts,
      'scope':
          'actual picker/decisions and natural participant UI before any post-action active intro probe; probes perform health/inbox work and do not prove unassisted receipt timing',
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    Future<void> flow(
      String role,
      String name,
      String label, [
      Map<String, String> values = const {},
    ]) async {
      attempted++;
      final path = await journey.flow(actor(role), name, label, values);
      ui[label] = {
        'path': path,
        'flow': name,
        'values': values,
        'receipt': jsonDecode(await File(path).readAsString()),
      };
      trace.add(label);
      await persist();
    }

    var firstFailureRecorded = false;
    try {
      await journey.prepare();
      for (final role in roles) {
        replace(role, await journey.reopen(actor(role)));
        nonces[role] = [actor(role).invocation.nonce];
      }
      final identities = <String, Map<String, Object?>>{
        for (final role in roles) role: await actor(role).command('identity'),
      };
      final peers = {
        for (final role in roles) role: identities[role]!['peerId']! as String,
      };
      final names = {
        for (final role in roles)
          role: identities[role]!['username']! as String,
      };
      proof['peers'] = peers;
      proof['names'] = names;
      for (final (role, contact) in [
        ('alice', 'bob'),
        ('bob', 'alice'),
        ('alice', 'charlie'),
        ('charlie', 'alice'),
      ]) {
        final result = await actor(
          role,
        ).command('prepare_contact', identities[contact]!);
        if (result['contactPrepared'] != true) {
          throw StateError('selective contact preparation failed');
        }
        manualEdges.add({'actor': role, 'peer': contact});
      }
      final text = introductionMutualText(journey.runId),
          pattern = RegExp.escape(text);
      Future<void> probePhase(String phase) async {
        final observed = <String, Object?>{};
        phases[phase] = observed;
        for (final role in roles) {
          final label = 'probe-$phase-$role';
          trace.add(label);
          final attempts = <Object?>[];
          probeAttempts[label] = attempts;
          observed[role] = await waitForProductionObservation(
            '$phase/$role exact current introduction state',
            const Duration(minutes: 3),
            () async {
              final result = await readProductionIntroductionSnapshot(
                actor(role),
                expectedPeerId: peers[role]!,
              );
              attempts.add(result['stepId']);
              final snapshot = result['snapshot'] as Map;
              final intros = (snapshot['introductions'] as List)
                  .whereType<Map>()
                  .toList();
              final messages = [
                for (final conversation
                    in (snapshot['chatMessages'] as List).whereType<Map>())
                  for (final row
                      in (conversation['messages'] as List).whereType<Map>())
                    if (row['text'] == text) row,
              ];
              if (intros.length > 1 ||
                  messages.length > 1 ||
                  (role == 'alice' && messages.isNotEmpty)) {
                throw StateError(
                  'duplicate introduction/chat or leaked participant chat; first observation retained',
                );
              }
              if (phase == 'mutual' || phase == 'restarted') {
                if (intros.length != 1 ||
                    intros.single['overallStatus'] != 'mutual_accepted') {
                  return null;
                }
                if (role != 'alice' &&
                    (messages.length != 1 ||
                        (role == 'bob' &&
                            messages.single['status'] != 'delivered'))) {
                  return null;
                }
              }
              return result;
            },
          );
          await persist();
        }
      }

      await probePhase('before');
      // No B-C contact is injected. The production application must create
      // that relationship only after both real user decisions.
      final before = phases['before'] as Map;
      for (final role in ['bob', 'charlie']) {
        final snapshot = (before[role] as Map)['snapshot'] as Map;
        final contacts = (snapshot['contacts'] as List)
            .whereType<Map>()
            .toList();
        if (contacts.length != 1 ||
            contacts.single['peerId'] != peers['alice'] ||
            (snapshot['introductions'] as List).isNotEmpty) {
          throw StateError('selective empty introduction fixture is invalid');
        }
      }
      await flow('alice', 'production_direct_open', 'open-alice-bob', {
        'PEER_ID': peers['bob']!,
      });
      Future<void> cutBeforeMutual(String role) async {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        kills['$role-offline'] = jsonDecode(
          await File(
            '${output!.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        trace.add('kill-offline-$role');
        await persist();
      }

      Future<void> restartBeforeMutual(String role) async {
        replace(role, await journey.reopen(actor(role)));
        nonces[role]!.add(actor(role).invocation.nonce);
        trace.add('restart-offline-$role');
        await persist();
      }

      Future<void> introduce() =>
          flow('alice', 'production_intro_send_one', 'introduce', {
            'RECIPIENT_PATTERN': RegExp.escape(names['bob']!),
            'FRIEND_PATTERN': RegExp.escape(names['charlie']!),
          });
      if (offlineOutbox) {
        proof['offlineOffers'] =
            await withProductionIntroductionStoppedNodeSnapshot(
              actor('alice'),
              expectedPeerId: peers['alice']!,
              action: introduce,
            );
        trace.add('offers-offline-snapshot');
        await persist();
        await cutBeforeMutual('alice');
        await restartBeforeMutual('alice');
      } else {
        await introduce();
      }
      for (final role in ['bob', 'charlie']) {
        await flow(
          role,
          'production_intro_review_pending',
          'natural-pending-$role',
          {
            'OTHER_PATTERN': RegExp.escape(
              names[role == 'bob' ? 'charlie' : 'bob']!,
            ),
            'INTRODUCER_PATTERN': RegExp.escape(names['alice']!),
          },
        );
      }
      await probePhase('pending');
      await flow('bob', 'production_intro_decide', 'accept-bob', {
        'OTHER_PATTERN': RegExp.escape(names['charlie']!),
        'DECISION_PATTERN': 'Accept',
        'EXPECTED_STATE_PATTERN': RegExp.escape(
          'Waiting for ${names['charlie']}',
        ),
      });
      Future<void> acceptCharlie() =>
          flow('charlie', 'production_intro_decide', 'accept-charlie', {
            'OTHER_PATTERN': RegExp.escape(names['bob']!),
            'DECISION_PATTERN': 'Accept',
            'EXPECTED_STATE_PATTERN': 'No introductions yet',
          });
      if (offlineOutbox) {
        // Establish the first response at the second participant before
        // stopping both nodes. This existing probe can drain inboxes; it
        // establishes a fixture precondition, not unassisted delivery timing.
        trace.add('probe-first-accept-charlie');
        final firstAttempts = <Object?>[];
        probeAttempts['first-accept-charlie'] = firstAttempts;
        final pendingCharlie =
            ((phases['pending'] as Map)['charlie'] as Map)['snapshot'] as Map;
        final originalId =
            ((pendingCharlie['introductions'] as List).single as Map)['id'];
        proof['responsePrecondition'] = await waitForProductionObservation(
          'Charlie holds Bob acceptance before the stopped response window',
          const Duration(minutes: 3),
          () async {
            final result = await readProductionIntroductionSnapshot(
              actor('charlie'),
              expectedPeerId: peers['charlie']!,
            );
            firstAttempts.add(result['stepId']);
            final rows = ((result['snapshot'] as Map)['introductions'] as List)
                .whereType<Map>()
                .toList();
            if (rows.length > 1) {
              throw StateError('ambiguous response precondition');
            }
            return rows.length == 1 &&
                    rows.single['id'] == originalId &&
                    rows.single['recipientStatus'] == 'accepted' &&
                    rows.single['introducedStatus'] == 'pending' &&
                    rows.single['overallStatus'] == 'pending'
                ? result
                : null;
          },
        );
        await persist();
        proof['offlineResponseReceiver'] =
            await withProductionIntroductionStoppedNodeSnapshot(
              actor('bob'),
              expectedPeerId: peers['bob']!,
              settleDelaySeconds: 240,
              action: () async {
                trace.add('response-offline-window');
                proof['offlineResponseCommitted'] =
                    await withProductionIntroductionStoppedNodeSnapshot(
                      actor('charlie'),
                      expectedPeerId: peers['charlie']!,
                      action: () async {
                        await acceptCharlie();
                        await flow(
                          'charlie',
                          'production_intro_ready_chat',
                          'response-ready-charlie',
                          {
                            'OTHER_PATTERN': RegExp.escape(names['bob']!),
                            'PEER_ID': peers['bob']!,
                          },
                        );
                      },
                    );
                trace.add('probe-response-committed-charlie');
                await persist();
                await cutBeforeMutual('charlie');
              },
            );
        trace.add('response-offline-snapshot');
        await persist();
        await cutBeforeMutual('bob');
        await restartBeforeMutual('charlie');
        await restartBeforeMutual('bob');
        // Each contact is created by actual mutual consent, never injected.
        // This naturally rendered contact/chat witness precedes all new probes.
        for (final role in ['bob', 'charlie']) {
          await flow(role, 'production_direct_open', '$role-ready', {
            'PEER_ID': peers[role == 'bob' ? 'charlie' : 'bob']!,
          });
        }
      } else {
        await acceptCharlie();
        for (final role in ['bob', 'charlie']) {
          await flow(role, 'production_intro_ready_chat', '$role-ready', {
            'PEER_ID': peers[role == 'bob' ? 'charlie' : 'bob']!,
            'OTHER_PATTERN': RegExp.escape(
              names[role == 'bob' ? 'charlie' : 'bob']!,
            ),
          });
        }
        for (final role in ['bob', 'charlie']) {
          await flow(role, 'production_intro_open_chat', 'open-chat-$role', {
            'PEER_ID': peers[role == 'bob' ? 'charlie' : 'bob']!,
            'OTHER_PATTERN': RegExp.escape(
              names[role == 'bob' ? 'charlie' : 'bob']!,
            ),
          });
        }
      }
      await flow('bob', 'production_direct_send', 'send-bob', {
        'MESSAGE': text,
        'MESSAGE_PATTERN': pattern,
      });
      await flow('charlie', 'production_intro_read_chat', 'received-charlie', {
        'MESSAGE_PATTERN': pattern,
      });
      await probePhase('mutual');
      for (final role in ['bob', 'charlie']) {
        final peer = actor(role);
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        trace.add('kill-$role');
        await persist();
      }
      for (final role in ['bob', 'charlie']) {
        replace(role, await journey.reopen(actor(role)));
        nonces[role]!.add(actor(role).invocation.nonce);
        await flow(role, 'production_direct_open', 'reopen-$role', {
          'PEER_ID': peers[role == 'bob' ? 'charlie' : 'bob']!,
        });
        await flow(role, 'production_intro_read_chat', 'replayed-$role', {
          'MESSAGE_PATTERN': pattern,
        });
      }
      await probePhase('restarted');
      final failures = offlineOutbox
          ? validateProductionIntroductionOffline(proof)
          : validateProductionIntroductionMutual(proof);
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
      capabilityId: scenario,
      validatorIds: [validator],
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? '$scenario real mutual consent and private direct chat passed' : '$scenario incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}
