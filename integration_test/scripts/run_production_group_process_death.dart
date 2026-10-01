import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_process_death_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_catalog.private_process_death_matrix';

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
    final texts = productionProcessDeathTexts(run);
    final flows = <String>[];
    final finals = <String, Object?>{};
    final kills = <String, Object?>{};
    final proof = <String, Object?>{
      'runId': run,
      'flows': flows,
      'final': finals,
      'kills': kills,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));

    try {
      await journey.prepare();
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      journey.additionalPeers['charlie'] = await journey.reopen(
        journey.additionalPeers['charlie']!,
      );
      final actors = {for (final p in journey.actors) p.invocation.role: p};
      void replace(String role, ProductionJourneyPeer peer) {
        actors[role] = peer;
        if (role == 'alice') journey.alice = peer;
        if (role == 'bob') journey.bob = peer;
        if (role == 'charlie') journey.additionalPeers['charlie'] = peer;
      }

      Future<void> flow(
        String role,
        String name,
        String label, [
        Map<String, String> values = const {},
      ]) async {
        await journey.flow(actors[role]!, name, label, values);
        flows.add(label);
        await persist();
      }

      Future<Map<String, Object?>> wait(
        String role,
        String operation,
        String label,
        bool Function(Map<String, Object?>) predicate, {
        Map<String, Object?> args = const {},
        Duration timeout = const Duration(seconds: 120),
      }) => waitForProductionObservation(label, timeout, () async {
        final s = await actors[role]!.command(operation, args);
        return predicate(s) ? s : null;
      });

      final name = 'Catalog private_process_death_matrix $run';
      final peers = <String, String>{};
      for (final role in actors.keys) {
        final ready = await wait(
          role,
          'catalog_group_snapshot',
          '$role production readiness',
          (s) =>
              s['relayReady'] == true &&
              s['sendReady'] == true &&
              s['inboxReady'] == true &&
              s['groupRecoveryActive'] == false &&
              s['lifecycle'] == 'resumed',
        );
        peers[role] = ready['peerId']! as String;
        if (ready['group'] != null) {
          throw StateError('catalog fixture is not initially empty');
        }
      }
      proof['relayAddresses'] =
          (await actors['alice']!.command('catalog_group_snapshot'))['relayAddresses'];
      final watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value,
            'senderPeerId': peers[entry.key.startsWith('alice') ? 'alice' : 'charlie'],
          },
      };
      Future<Map<String, Object?>> snap(String role) =>
          actors[role]!.command('catalog_watch_snapshot', {'texts': watch});
      Future<Map<String, Object?>> waitWatch(
        String role,
        String label,
        bool Function(Map<String, Object?>) predicate, {
        Duration timeout = const Duration(seconds: 120),
      }) => wait(
        role,
        'catalog_watch_snapshot',
        label,
        predicate,
        args: {'texts': watch},
        timeout: timeout,
      );
      int rows(Map<String, Object?> s, String key) =>
          (((s['watched'] as Map?)?[key] as List?) ?? const []).length;
      List members(Map<String, Object?> s) =>
          (s['memberPeerIds'] as List?) ?? const [];
      Future<Map<String, Object?>> settled(String role, int count) => wait(
        role,
        'catalog_group_snapshot',
        '$role settled $count-member group',
        (s) =>
            s['group'] is Map &&
            ((s['group'] as Map)['members'] as List).length == count &&
            s['groupRecoveryActive'] == false &&
            s['relayReady'] == true,
      );
      // Membership edits are refused while group recovery runs; recovery can
      // restart when a join is processed. Require every invite attempt to be
      // joined and recovery to stay inactive for three consecutive seconds.
      Future<void> quiet(String role) async {
        var since = DateTime.now();
        await waitForProductionObservation(
          '$role quiet group',
          const Duration(minutes: 3),
          () async {
            final s = await actors[role]!.command('catalog_group_snapshot');
            final group = s['group'];
            final attempts = group is Map
                ? (group['deliveryAttempts'] as List)
                : const [];
            final calm =
                group is Map &&
                s['groupRecoveryActive'] == false &&
                attempts.every((a) => (a as Map)['status'] == 'joined');
            if (!calm) {
              since = DateTime.now();
              return null;
            }
            return DateTime.now().difference(since) >=
                    const Duration(seconds: 3)
                ? true
                : null;
          },
        );
      }

      // A refused membership edit (the app's recovery gate) is retried the
      // way a user would: wait for a quiet group, tap again from the same
      // screen. At most three tries; every retry is recorded.
      final retries = <String, Object?>{};
      proof['membershipEditRetries'] = retries;
      Future<void> membershipEdit(
        String label,
        String name,
        String retryName,
        Map<String, String> values,
        Future<bool> Function() applied,
      ) async {
        for (var attempt = 1; ; attempt++) {
          try {
            await journey.flow(
              actors['alice']!,
              attempt == 1 ? name : retryName,
              attempt == 1 ? label : '$label-retry$attempt',
              values,
            );
            break;
          } catch (error) {
            if (attempt >= 3 || await applied()) rethrow;
            retries[label] = attempt;
            await persist();
            await quiet('alice');
          }
        }
        flows.add(label);
        await persist();
      }

      // Keyboards autocorrect the original proof texts ("readd" -> "read").
      // For each proof send only, switch that device to the installed Appium
      // keyboard (commits text verbatim, shows no keyboard) and restore the
      // device's own keyboard immediately after. Every switch is recorded.
      const verbatimIme = 'io.appium.settings/.AppiumIME';
      final imeSwitches = <Map<String, Object?>>[];
      proof['imeSwitches'] = imeSwitches;
      Future<void> verbatimSend(String role, String label, String text) async {
        final peer = actors[role]!;
        final installed = '${(await peer.adb(['shell', 'ime', 'list', '-a', '-s'])).stdout}'
            .contains(verbatimIme);
        if (!installed) {
          // No verbatim keyboard on this device: use its own keyboard; the
          // flow still requires the exact composer text before sending.
          imeSwitches.add({'role': role, 'label': label, 'restoreTo': null});
          await flow(role, 'production_direct_send', label, {
            'MESSAGE': text,
            'MESSAGE_PATTERN': RegExp.escape(text),
          });
          return;
        }
        final original =
            '${(await peer.adb(['shell', 'settings', 'get', 'secure', 'default_input_method'])).stdout}'
                .trim();
        await peer.adb(['shell', 'ime', 'enable', verbatimIme]);
        await peer.adb(['shell', 'ime', 'set', verbatimIme]);
        imeSwitches.add({'role': role, 'label': label, 'restoreTo': original});
        try {
          await flow(role, 'production_verbatim_send', label, {
            'MESSAGE': text,
            'MESSAGE_PATTERN': RegExp.escape(text),
          });
        } finally {
          if (original.isNotEmpty && original != verbatimIme) {
            await peer.adb(['shell', 'ime', 'set', original]);
          }
        }
      }

      Future<void> invitedAndAccept(String role, String label) async {
        await wait(
          role,
          'catalog_pending_snapshot',
          '$role pending invitation',
          (s) => (s['pending'] as List).length == 1,
          timeout: const Duration(minutes: 4),
        );
        await flow(role, 'production_catalog_invite_accept', label, {
          'GROUP_NAME': name,
        });
      }

      Future<void> killAndRecover(String role, String kill) async {
        await journey.killOwnedProcess(actors[role]!);
        kills[kill] = File(
          '${output!.path}/${actors[role]!.invocation.nonce}-process-death.json',
        ).existsSync();
        replace(role, await journey.reopen(actors[role]!));
        await persist();
      }

      attempts++;
      await flow('alice', 'production_group_create', 'create', {
        'CONTACT_NAME': 'Journeybob',
        'GROUP_NAME': name,
      });
      await invitedAndAccept('bob', 'accept-bob');
      await settled('alice', 2);
      await settled('bob', 2);

      // ST-007 add: Charlie dies right after the add is persisted.
      attempts++;
      await quiet('alice');
      await membershipEdit(
        'add-charlie',
        'production_group_info_add_member',
        'production_group_info_add_member_retry',
        {'CONTACT_NAME': 'Journeycharlie'},
        () async => false,
      );
      await invitedAndAccept('charlie', 'accept-charlie-add');
      proof['addPersisted'] = await waitWatch(
        'charlie',
        'Charlie add persisted',
        (s) => s['selfMember'] == true,
      );
      await killAndRecover('charlie', 'charlie:add');
      proof['addRecovered'] = await waitWatch(
        'charlie',
        'Charlie add recovered',
        (s) => s['selfMember'] == true && members(s).length == 3,
      );
      for (final role in ['alice', 'bob', 'charlie']) {
        await settled(role, 3);
      }
      await verbatimSend('alice', 'alice-after-add', texts['aliceAfterAddCrash']!);
      proof['bobGotAdd'] = await waitWatch(
        'bob',
        'Bob receives after add',
        (s) => rows(s, 'aliceAfterAddCrash') == 1,
      );
      proof['charlieGotAdd'] = await waitWatch(
        'charlie',
        'Charlie receives after add',
        (s) => rows(s, 'aliceAfterAddCrash') == 1,
      );

      // ST-007 remove: Bob dies right after the removal is persisted.
      attempts++;
      await quiet('alice');
      await membershipEdit(
        'remove-charlie',
        'production_catalog_remove_charlie',
        'production_catalog_remove_charlie_retry',
        {'CHARLIE_PEER_ID': peers['charlie']!},
        () async => !members(await snap('alice')).contains(peers['charlie']),
      );
      proof['removePersisted'] = await waitWatch(
        'bob',
        'Bob removal persisted',
        (s) => !members(s).contains(peers['charlie']),
      );
      await killAndRecover('bob', 'bob:remove');
      final aliceRotated = await waitWatch(
        'alice',
        'Alice rotated after removal',
        (s) => (s['keyEpoch'] as int) >= 2,
      );
      proof['removeRecovered'] = await waitWatch(
        'bob',
        'Bob removal recovered',
        (s) =>
            !members(s).contains(peers['charlie']) &&
            s['keyEpoch'] == aliceRotated['keyEpoch'],
      );
      await flow('alice', 'production_back_to_chat', 'alice-back-to-chat');
      await verbatimSend('alice', 'alice-after-remove', texts['aliceAfterRemoveCrash']!);
      proof['bobGotRemove'] = await waitWatch(
        'bob',
        'Bob receives after removal',
        (s) => rows(s, 'aliceAfterRemoveCrash') == 1,
      );
      // The original's five-second absence window on the removed member.
      await Future<void>.delayed(const Duration(seconds: 5));
      proof['charlieRemovedWindow'] = await snap('charlie');

      // ST-007 re-add: Charlie dies right after the re-add is persisted.
      attempts++;
      await settled('alice', 2);
      await quiet('alice');
      await membershipEdit(
        'readd-charlie',
        'production_group_info_add_member',
        'production_group_info_add_member_retry',
        {'CONTACT_NAME': 'Journeycharlie'},
        () async => false,
      );
      await invitedAndAccept('charlie', 'accept-charlie-readd');
      proof['readdPersisted'] = await waitWatch(
        'charlie',
        'Charlie re-add persisted',
        (s) => s['selfMember'] == true,
      );
      await killAndRecover('charlie', 'charlie:readd');
      final aliceFinalEpoch =
          (await snap('alice'))['keyEpoch'] as int;
      proof['readdRecovered'] = await waitWatch(
        'charlie',
        'Charlie re-add recovered',
        (s) =>
            s['selfMember'] == true &&
            members(s).length == 3 &&
            s['keyEpoch'] == aliceFinalEpoch,
      );
      for (final role in ['alice', 'bob', 'charlie']) {
        await settled(role, 3);
      }
      await verbatimSend('alice', 'alice-after-readd', texts['aliceAfterReaddCrash']!);
      proof['bobGotReadd'] = await waitWatch(
        'bob',
        'Bob receives after re-add',
        (s) => rows(s, 'aliceAfterReaddCrash') == 1,
      );
      proof['charlieGotReadd'] = await waitWatch(
        'charlie',
        'Charlie receives after re-add',
        (s) => rows(s, 'aliceAfterReaddCrash') == 1,
      );
      final groupId =
          ((await actors['charlie']!.command('catalog_group_snapshot'))['group']
                  as Map)['id']
              as String;
      await journey.flow(actors['charlie']!, 'production_group_open', 'charlie-open-group', {
        'GROUP_ID': groupId,
      });
      await verbatimSend(
        'charlie',
        'charlie-after-readd',
        texts['charlieAfterReaddCrash']!,
      );
      proof['aliceGotCharlie'] = await waitWatch(
        'alice',
        'Alice receives Charlie',
        (s) => rows(s, 'charlieAfterReaddCrash') == 1,
      );
      proof['bobGotCharlie'] = await waitWatch(
        'bob',
        'Bob receives Charlie',
        (s) => rows(s, 'charlieAfterReaddCrash') == 1,
      );
      // Retain the original receiver's two-second duplicate-settlement window.
      await Future<void>.delayed(const Duration(seconds: 2));
      for (final role in ['alice', 'bob', 'charlie']) {
        finals[role] = await snap(role);
      }
      await persist();
      final failures = validateProductionGroupProcessDeath(proof);
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
      validatorIds: ['validateProductionGroupProcessDeath'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production private_process_death_matrix passed' : 'production private_process_death_matrix failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
