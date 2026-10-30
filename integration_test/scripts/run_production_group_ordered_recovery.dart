import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_ordered_recovery_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_catalog_membership_steps.dart';
import '../support/production_catalog_session.dart';
import '../support/production_sims_result.dart';
import '../support/production_verbatim_keyboard.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(productionGroupOrderedRecovery);
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
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(
      groupOrderedRecoveryRuntime,
      output,
    );
    final proof = <String, Object?>{
      'runId': journey.runId,
      'runtimeScenario': groupOrderedRecoveryRuntime,
      'emulatorTriple':
          journey.disposableAndroidJourneys && journey.actors.length == 3,
    };
    final session = ProductionCatalogSession(journey, output, proof);
    final kills = <String, Object?>{};
    proof['ownedKills'] = kills;
    try {
      await session.start();
      final texts = groupOrderedRecoveryTexts(journey.runId);
      session.watch = {
        for (final entry in texts.entries)
          entry.key: {
            'text': entry.value.text,
            'senderPeerId': session.peers[entry.value.role],
          },
      };
      proof['peers'] = session.peers;
      proof['initialNonces'] = {
        for (final entry in session.actors.entries)
          entry.key: entry.value.invocation.nonce,
      };
      attempted++;
      await session.createAndAcceptAll(session.catalogName('de002'));
      for (var i = 0; i < 100; i++) {
        await session.verbatimSend(
          'alice',
          'ordered-seq-$i',
          texts['seq$i']!.text,
        );
      }
      await session.verbatimSend('bob', 'ordered-bob', texts['bob']!.text);
      await session.verbatimSend(
        'charlie',
        'ordered-charlie',
        texts['charlie']!.text,
      );
      Future<Map<String, Object?>> complete(
        String role,
        Iterable<String> keys,
      ) => session.waitWatch(
        role,
        '$role complete canonical group rows',
        (snapshot) => keys.every(
          (key) => ProductionCatalogSession.rows(snapshot, key) == 1,
        ),
        timeout: const Duration(minutes: 5),
      );
      proof['beforeCrash'] = {
        for (final role in session.actors.keys)
          role: await complete(
            role,
            texts.keys.where((key) => key != 'accepted'),
          ),
      };
      await session.persist();
      Future<void> kill(String role) async {
        final peer = session.actors[role]!;
        await journey.killOwnedProcess(peer);
        kills[role] = jsonDecode(
          await File(
            '${output!.path}/${peer.invocation.nonce}-process-death.json',
          ).readAsString(),
        );
        await session.persist();
      }

      // Keep both recipients offline until the author has crossed the verified
      // accepted/durable text checkpoint and its owned process has died.
      for (final role in ['bob', 'charlie']) {
        await kill(role);
        final peer = session.actors[role]!;
        await peer.adb(['shell', 'am', 'force-stop', peer.packageName]);
      }
      await session.verbatimSend(
        'alice',
        'ordered-accepted',
        texts['accepted']!.text,
      );
      proof['acceptedSource'] = await session.waitWatch(
        'alice',
        'actual accepted text with committed recipient custody',
        (snapshot) {
          final watched = snapshot['watched'] as Map?;
          final rows = (watched?['accepted'] as List?) ?? const [];
          if (rows.length != 1 ||
              !['sent', 'delivered'].contains((rows.single as Map)['status'])) {
            return false;
          }
          final id = (rows.single as Map)['messageId'];
          return (snapshot['deliveries'] as List).whereType<Map>().any(
            (delivery) =>
                delivery['messageId'] == id &&
                delivery['ok'] == true &&
                delivery['inboxStored'] == true,
          );
        },
      );
      await session.persist();
      await kill('alice');
      final offline = <String, Object?>{};
      proof['offlineRecipients'] = offline;
      for (final role in ['bob', 'charlie']) {
        final peer = session.actors[role]!;
        final result = await peer.adb([
          'shell',
          'pidof',
          peer.packageName,
        ], allowFailure: true);
        offline[role] =
            result.exitCode == 1 &&
            '${result.stdout}'.trim().isEmpty &&
            '${result.stderr}'.trim().isEmpty;
      }
      await session.persist();
      if (offline.values.any((absent) => absent != true)) {
        throw StateError(
          'a recipient restarted before the accepted sender cut',
        );
      }
      for (final role in session.actors.keys.toList()) {
        session.replace(role, await journey.reopen(session.actors[role]!));
      }
      proof['finalNonces'] = {
        for (final entry in session.actors.entries)
          entry.key: entry.value.invocation.nonce,
      };
      proof['afterRestart'] = {
        for (final role in session.actors.keys)
          role: await complete(role, texts.keys),
      };
      await session.persist();
      // Retain the exact 103-row recovery oracle and its original flow list.
      // Additional UI receipts are kept separately so its exact sequence is
      // neither weakened nor rewritten to accommodate the new live leg.
      final originalFailures = validateProductionGroupOrderedRecovery(proof);
      if (originalFailures.isNotEmpty) {
        throw StateError(originalFailures.join('; '));
      }
      final ui = <String, Object?>{};
      final trace = <String>[];
      final afterLive = <String, Object?>{};
      final freshText = 'Fresh group after passive recovery ${journey.runId}';
      final post = <String, Object?>{
        'attemptDirectory': output.path,
        'ui': ui,
        'trace': trace,
        'freshText': freshText,
        'afterLive': afterLive,
        'observationOperation': 'catalog_watch_snapshot',
      };
      proof['postCatchup'] = post;
      Future<void> postFlow(
        String role,
        String name,
        String label, [
        Map<String, String> values = const {},
      ]) async {
        final path = await journey.flow(
          session.actors[role]!,
          name,
          label,
          values,
        );
        ui[label] = {'path': path, 'flow': name};
        trace.add(label);
        await session.persist();
      }

      for (final role in ['bob', 'charlie']) {
        await postFlow(role, 'production_group_open', '$role-recovered-open', {
          'GROUP_ID': (proof['acceptedSource'] as Map)['groupId'] as String,
        });
        await postFlow(
          role,
          'production_direct_assert_action',
          '$role-recovered-visible',
          {
            'VISIBLE_PATTERN': RegExp.escape(texts['accepted']!.text),
            'ABSENT_PATTERN': RegExp.escape(freshText),
          },
        );
      }
      await postFlow('alice', 'production_group_open', 'alice-live-open', {
        'GROUP_ID': (proof['acceptedSource'] as Map)['groupId'] as String,
      });
      session.watch = {
        ...session.watch,
        'freshAfterRecovery': {
          'text': freshText,
          'senderPeerId': session.peers['alice'],
        },
      };
      attempted++;
      await withProductionVerbatimKeyboard(
        session.actors['alice']!.adb,
        'fresh-after-recovery',
        session.imeSwitches,
        (verbatim) => postFlow(
          'alice',
          verbatim ? 'production_verbatim_send' : 'production_direct_send',
          'fresh-after-recovery',
          {'MESSAGE': freshText, 'MESSAGE_PATTERN': RegExp.escape(freshText)},
        ),
        extra: {'role': 'alice'},
      );
      for (final role in session.actors.keys) {
        afterLive[role] = await session.waitWatch(
          role,
          '$role exact fresh live message after passive recovery',
          (snapshot) {
            final rows =
                ((snapshot['watched'] as Map?)?['freshAfterRecovery']
                    as List?) ??
                const [];
            if (rows.length != 1) return false;
            final row = rows.single as Map;
            return role == 'alice'
                ? ['sent', 'delivered'].contains(row['status'])
                : ((snapshot['liveMessageIds'] as List?) ?? const []).contains(
                    row['messageId'],
                  );
          },
        );
      }
      for (final role in ['bob', 'charlie']) {
        await postFlow(
          role,
          'production_direct_assert_two',
          '$role-recovered-and-live-visible',
          {
            'FIRST_PATTERN': RegExp.escape(texts['accepted']!.text),
            'SECOND_PATTERN': RegExp.escape(freshText),
          },
        );
      }
      await session.persist();
      final failures = [
        ...validateProductionGroupOrderedRecovery(proof),
        ...validateProductionGroupPostRecoveryLive(proof),
      ];
      await File(
        '${output.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: productionGroupOrderedRecovery,
      validatorIds: ['validateProductionGroupOrderedRecovery'],
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
    'SIMS_RESULT_JSON=${jsonEncode(productionSimsResult(passed: passed, assertionsAttempted: attempted, detail: passed ? 'GC-002/GC-005 recovery and GC-003 post-catch-up live/UI leg passed' : 'group ordered recovery incomplete or failed', evidence: evidence))}',
  );
  exitCode = passed ? 0 : 1;
}

/// Extends the incumbent oracle; the caller still runs every original 103-row,
/// custody, kill and fresh-invocation assertion unchanged.
List<String> validateProductionGroupPostRecoveryLive(
  Map<String, Object?> proof,
) {
  Map<String, Object?> map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : {};
  List<Map<String, Object?>> rows(Map<String, Object?> snapshot, String key) =>
      ((map(snapshot['watched'])[key] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList();
  final failures = <String>[];
  final post = map(proof['postCatchup']);
  final ui = map(post['ui']);
  final trace = (post['trace'] as List?) ?? const [];
  final run = proof['runId'];
  if (run is! String || run.isEmpty) return ['GC-003 exact run required'];
  final freshText = 'Fresh group after passive recovery $run';
  final peers = map(proof['peers']);
  final accepted = rows(map(proof['acceptedSource']), 'accepted');
  final snapshots = map(post['afterLive']);
  final source = rows(map(snapshots['alice']), 'freshAfterRecovery');
  final sendReceipt = map(ui['fresh-after-recovery']);
  final sendFlow = sendReceipt['flow'];
  final oldSource = map(map(proof['afterRestart'])['alice']);
  final oldIds = {
    for (final key in groupOrderedRecoveryTexts(run).keys)
      for (final row in rows(oldSource, key)) row['messageId'],
  };
  if (post['freshText'] != freshText ||
      post['observationOperation'] != 'catalog_watch_snapshot' ||
      accepted.length != 1 ||
      source.length != 1 ||
      source.single['text'] != freshText ||
      source.single['senderPeerId'] != peers['alice'] ||
      source.single['isIncoming'] != false ||
      source.single['messageId'] is! String ||
      (source.single['messageId'] as String).isEmpty ||
      oldIds.contains(source.single['messageId']) ||
      source.single['groupId'] != accepted.single['groupId'] ||
      DateTime.tryParse('${source.single['timestamp']}') == null ||
      ![
        'production_verbatim_send',
        'production_direct_send',
      ].contains(sendFlow) ||
      !maestroFlowReceiptPassed(
        sendReceipt['path'],
        post['attemptDirectory'],
        '$sendFlow',
      )) {
    return [
      'GC-003 requires a distinct current author row after the original passive catch-up',
    ];
  }
  for (final role in ['bob', 'charlie']) {
    final recoveredLabel = '$role-recovered-visible';
    final liveLabel = '$role-recovered-and-live-visible';
    final recoveredReceipt = map(ui[recoveredLabel]);
    final liveReceipt = map(ui[liveLabel]);
    if (!maestroFlowReceiptPassed(
          recoveredReceipt['path'],
          post['attemptDirectory'],
          'production_direct_assert_action',
        ) ||
        !maestroFlowReceiptPassed(
          liveReceipt['path'],
          post['attemptDirectory'],
          'production_direct_assert_two',
        ) ||
        !trace.contains(recoveredLabel) ||
        !trace.contains('fresh-after-recovery') ||
        trace.indexOf(recoveredLabel) >=
            trace.indexOf('fresh-after-recovery') ||
        trace.indexOf(liveLabel) <= trace.indexOf('fresh-after-recovery')) {
      failures.add(
        '$role: actual recovered UI must precede the fresh send, then show both exact texts',
      );
    }
    final snapshot = map(snapshots[role]);
    final fresh = rows(snapshot, 'freshAfterRecovery');
    final recovered = rows(snapshot, 'accepted');
    if (snapshot['runId'] != run ||
        snapshot['peerId'] != peers[role] ||
        fresh.length != 1 ||
        recovered.length != 1 ||
        recovered.single['messageId'] != accepted.single['messageId'] ||
        fresh.single['messageId'] != source.single['messageId'] ||
        fresh.single['text'] != freshText ||
        fresh.single['isIncoming'] != true ||
        fresh.single['senderPeerId'] != peers['alice'] ||
        fresh.single['timestamp'] != source.single['timestamp'] ||
        fresh.single['keyEpoch'] != source.single['keyEpoch'] ||
        fresh.single['groupId'] != source.single['groupId'] ||
        !((snapshot['liveMessageIds'] as List?) ?? const []).contains(
          source.single['messageId'],
        )) {
      failures.add(
        '$role: exact fresh canonical row must arrive live after the recovered triggering row',
      );
    }
  }
  return failures;
}
