import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_routing_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.routing_smoke';
Map<String, Object?> _object(Object? v) => Map<String, Object?>.from(v as Map);
List<Map<String, Object?>> _maps(Object? v) =>
    (v as List).map(_object).toList();

/// Production main owns all services. This runner owns scenario order, exact
/// receipt collection and Maestro UI actions, using the retained three-minute
/// protocol stage bounds and the two-minute delivered-convergence bound.
Future<void> main(List<String> args) async {
  if (args.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    final path = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (path == null || path.isEmpty) {
      throw StateError('missing proof directory');
    }
    output = await (await Directory(
      path,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final journey = ProductionAndroidJourney.fromEnvironment(_scenario, output);
    final cases = <Map<String, Object?>>[];
    final proof = <String, Object?>{'cases': cases, 'runId': journey.runId};
    try {
      await journey.prepare();
      final a = await journey.alice.command('identity'),
          b = await journey.bob.command('identity');
      final peers = {
        'alice': a['peerId']! as String,
        'bob': b['peerId']! as String,
      };
      proof['peers'] = peers;
      final fixture = await journey.alice.command('prepare_group', {
        'peerId': peers['bob'],
      });
      final group = _object(fixture['group'])['id']! as String;
      proof['groupId'] = group;
      await journey.bob.command('import_group', fixture);
      await journey.alice.command('mark_fixture_joined', {
        'groupId': group,
        'peerId': peers['bob'],
        'username': b['username'],
      });
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      for (final p in [journey.alice, journey.bob]) {
        await p.command('adopt_prepared_group', {'groupId': group});
      }
      final discovery = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 5));
      final discoveryMs = discovery.elapsedMilliseconds;
      final extraPeers = <String>[];
      var serial = 0;
      final openLane = <String, String?>{'alice': null, 'bob': null};
      ProductionJourneyPeer peer(String role) =>
          role == 'alice' ? journey.alice : journey.bob;
      String opposite(String role) => role == 'alice' ? 'bob' : 'alice';
      Future<Map<String, Object?>> snapshot(
        String role, {
        List<String> messageIds = const [],
      }) => peer(role).command('routing_snapshot', {
        'peerIds': [peers[opposite(role)], if (role == 'alice') ...extraPeers],
        'groupIds': [group],
        'messageIds': messageIds,
      });
      Future<void> flow(
        String role,
        String name,
        String label, [
        Map<String, String> values = const {},
      ]) => journey.flow(peer(role), name, '${serial++}-$label', values);
      Future<void> inLane(String role, String lane, {String? target}) async {
        final destination =
            target ?? (lane == 'group' ? group : peers[opposite(role)]!);
        if (openLane[role] == destination) return;
        if (openLane[role] != null) {
          await flow(role, 'production_conversation_back', '$role-back');
        }
        await flow(
          role,
          lane == 'group' ? 'production_group_open' : 'production_direct_open',
          '$role-open',
          {
            if (lane == 'group')
              'GROUP_ID': destination
            else
              'PEER_ID': destination,
          },
        );
        openLane[role] = destination;
      }

      Future<void> orbit(String role) async {
        if (openLane[role] != null) {
          await flow(role, 'production_conversation_back', '$role-orbit');
        }
        openLane[role] = null;
      }

      List<Map<String, Object?>> events(Map<String, Object?> s, String name) =>
          _maps(s['events']).where((e) => e['event'] == name).toList();
      Map<String, Object?> exactRow(
        Map<String, Object?> s,
        String message, {
        required bool incoming,
      }) {
        final rows = _maps(s['messages'])
            .where((m) => m['id'] == message && m['incoming'] == incoming)
            .toList();
        if (rows.length != 1) {
          throw StateError('exact persisted row unavailable');
        }
        return rows.single;
      }

      Future<void> receive(
        Map<String, Object?> exchange, {
        Duration timeout = const Duration(minutes: 3),
      }) async {
        final role = opposite(exchange['senderRole']! as String);
        final id = _object(exchange['sender'])['id'];
        final watch = Stopwatch()..start();
        final row = await waitForProductionObservation(
          'exact receiver row $id',
          timeout,
          () async {
            final s = await snapshot(role);
            final rows = _maps(
              s['messages'],
            ).where((m) => m['id'] == id && m['incoming'] == true).toList();
            if (rows.length > 1) throw StateError('duplicate received row');
            return rows.singleOrNull;
          },
        );
        exchange['receiver'] = row;
        if (watch.elapsed > timeout) {
          throw StateError(
            'receiver receipt exceeded the original stage bound',
          );
        }
        exchange['receiptMs'] = watch.elapsedMilliseconds;
        exchange['receiptInterval'] =
            'host polling after UI send completion; not cross-device latency';
      }

      Future<Map<String, Object?>> send(
        String id,
        String suffix, {
        String role = 'alice',
        String lane = 'direct',
        bool awaitReceive = true,
        String? target,
        int? n,
      }) async {
        await inLane(role, lane, target: target);
        final name = lane == 'group'
            ? 'GROUP_SEND_MSG_TIMING'
            : 'CHAT_MSG_SEND_TIMING';
        final before = await snapshot(role);
        final count = events(before, name).length;
        final text = '$id: $suffix ${journey.runId}';
        final sendWatch = Stopwatch()..start();
        await flow(role, 'production_direct_send', '$id-send-${n ?? serial}', {
          'MESSAGE': text,
          'MESSAGE_PATTERN': RegExp.escape(text),
        });
        final observed = await waitForProductionObservation(
          'actual send timing and row',
          const Duration(minutes: 3),
          () async {
            final value = await snapshot(role);
            final rows = _maps(value['messages'])
                .where((m) => m['text'] == text && m['incoming'] == false)
                .toList();
            final added = events(value, name).skip(count).toList();
            if (rows.length > 1 || added.length > 1) {
              throw StateError('ambiguous UI send');
            }
            return rows.length == 1 && added.length == 1
                ? {
                    'sender': rows.single,
                    'timing': _object(added.single['details']),
                  }
                : null;
          },
        );
        final x = <String, Object?>{'senderRole': role, ...observed, 'n': ?n};
        if (sendWatch.elapsed > const Duration(minutes: 3)) {
          throw StateError('UI send exceeded the original stage bound');
        }
        x['sendPhaseMs'] = sendWatch.elapsedMilliseconds;
        if (awaitReceive) await receive(x);
        return x;
      }

      Future<Map<String, Object?>> node(String role, String operation) =>
          peer(role).command('routing_node_control', {'operation': operation});
      Future<Map<String, Object?>> restartBob({
        bool groupRecovery = false,
      }) async {
        final receipt = await node('bob', 'start');
        await peer('bob').awaitReady();
        await node('bob', 'warm_background');
        if (groupRecovery) await peer('bob').command('rejoin_topics');
        return receipt;
      }

      Future<void> record(
        String id,
        List<Map<String, Object?>> exchanges, [
        Map<String, Object?> extra = const {},
      ]) async {
        attempted++;
        cases.add({'id': id, 'exchanges': exchanges, ...extra});
        await File(
          '${output!.path}/observations.json',
        ).writeAsString(jsonEncode(proof));
      }

      final s1 = await send('S1', 'cold hello');
      await record('S1', [s1]);
      final convergence = Stopwatch()..start();
      final converged = await waitForProductionObservation(
        'S1 exact delivered convergence',
        const Duration(minutes: 2),
        () async {
          final row = exactRow(
            await snapshot('alice'),
            _object(s1['sender'])['id']! as String,
            incoming: false,
          );
          return row['status'] == 'delivered' ? row : null;
        },
      );
      await record('S1-CONV', [], {
        'messageId': converged['id'],
        'status': converged['status'],
        'convergenceMs': convergence.elapsedMilliseconds,
      });
      final s2 = <Map<String, Object?>>[];
      final s2Watch = Stopwatch()..start();
      for (var n = 1; n <= 5; n++) {
        s2.add(await send('S2', 'warm msg $n', n: n));
      }
      await record('S2', s2, {'sendPhaseMs': s2Watch.elapsedMilliseconds});
      final s3Stop = await node('bob', 'stop');
      final s3 = await send('S3', 'offline inbox', awaitReceive: false);
      final s3Start = await restartBob();
      await receive(s3);
      await record('S3', [s3], {'stop': s3Stop, 'restart': s3Start});
      await Future<void>.delayed(const Duration(seconds: 3));
      await record('S4', [await send('S4', 'reconnect')]);
      final s5 = <Map<String, Object?>>[];
      for (var n = 1; n <= 5; n++) {
        s5.add(
          await send(
            'S5',
            'bidirectional $n',
            role: n.isEven ? 'bob' : 'alice',
            n: n,
          ),
        );
      }
      await record('S5', s5);
      final previous = journey.bob;
      journey.bob = await journey.stageFreshInvocation(previous);
      await journey.killOwnedProcess(previous);
      await flow('bob', 'production_resume', 'S6-new-process');
      await journey.bob.awaitReady();
      await journey.bob.command('adopt_prepared_group', {'groupId': group});
      openLane['bob'] = null;
      // Fresh process starts in Inner Circle; select the existing All Chats UI.
      await flow('bob', 'production_all_chats', 'S6-all-chats');
      final s6 = await send('S6', 'stale recovery');
      await record(
        'S6',
        [s6],
        {
          'processDeathVerified': true,
          'beforeNonce': previous.invocation.nonce,
          'afterNonce': journey.bob.invocation.nonce,
        },
      );
      final missing = await journey.alice.command(
        'routing_prepare_unreachable_contact',
      );
      final missingId = missing['peerId']! as String;
      extraPeers.add(missingId);
      // Reopen Alice normally so the ordinary contact list observes the fixture.
      journey.alice = await journey.reopen(journey.alice);
      openLane['alice'] = null;
      await journey.alice.command('adopt_prepared_group', {'groupId': group});
      await record(
        'S7',
        [
          await send(
            'S7',
            'unreachable',
            target: missingId,
            awaitReceive: false,
          ),
        ],
        {'unreachablePeerId': missingId},
      );
      final s8 = <Map<String, Object?>>[];
      for (var n = 1; n <= 4; n++) {
        s8.add(await send('S8', 'msg$n ${n == 1 ? 'cold' : 'warm'}', n: n));
      }
      final s8Stop = await node('bob', 'stop');
      final offline = await send(
        'S8',
        'msg5 offline',
        n: 5,
        awaitReceive: false,
      );
      s8.add(offline);
      final s8Start = await restartBob();
      await receive(offline);
      s8.add(await send('S8', 'msg6 reconnect', n: 6));
      s8.add(await send('S8', 'bob msg7', role: 'bob', n: 7));
      for (var n = 8; n <= 10; n++) {
        s8.add(await send('S8', 'msg$n warm', n: n));
      }
      await record('S8', s8, {'stop': s8Stop, 'restart': s8Start});
      final s9Stop = await node('bob', 'stop'), s9 = <Map<String, Object?>>[];
      final s9Watch = Stopwatch()..start();
      await inLane('alice', 'direct');
      final s9Before = await snapshot('alice');
      final s9PriorTimings = events(s9Before, 'CHAT_MSG_SEND_TIMING').length;
      final s9Texts = [
        for (var n = 1; n <= 5; n++) 'S9: batch inbox $n ${journey.runId}',
      ];
      await flow('alice', 'production_direct_send_batch5', 'S9-send-batch', {
        for (var n = 1; n <= 5; n++) ...{
          'MESSAGE_$n': s9Texts[n - 1],
          'MESSAGE_PATTERN_$n': RegExp.escape(s9Texts[n - 1]),
        },
      });
      final s9Observed = await waitForProductionObservation(
        'five exact S9 rows and production send timings',
        const Duration(minutes: 3),
        () async {
          final value = await snapshot('alice');
          final rows = _maps(value['messages']);
          final timings = events(
            value,
            'CHAT_MSG_SEND_TIMING',
          ).skip(s9PriorTimings).toList();
          if (timings.length > 5 ||
              s9Texts.any(
                (text) =>
                    rows
                        .where(
                          (row) =>
                              row['text'] == text && row['incoming'] == false,
                        )
                        .length >
                    1,
              )) {
            throw StateError('ambiguous S9 batch send');
          }
          final exactRows = [
            for (final text in s9Texts)
              rows
                  .where(
                    (row) => row['text'] == text && row['incoming'] == false,
                  )
                  .singleOrNull,
          ];
          return timings.length == 5 && exactRows.every((row) => row != null)
              ? {'rows': exactRows, 'timings': timings}
              : null;
        },
      );
      final s9SendMs = s9Watch.elapsedMilliseconds;
      if (s9Watch.elapsed > const Duration(minutes: 3)) {
        throw StateError(
          'S9 five-message batch exceeded the original stage bound',
        );
      }
      final s9Rows = (s9Observed['rows'] as List).cast<Map<String, Object?>>();
      final s9Timings = (s9Observed['timings'] as List)
          .cast<Map<String, Object?>>();
      for (var n = 1; n <= 5; n++) {
        s9.add({
          'senderRole': 'alice',
          'sender': s9Rows[n - 1],
          'timing': _object(s9Timings[n - 1]['details']),
          'n': n,
          'sendPhaseMs': s9SendMs,
        });
      }
      final s9Start = await restartBob();
      for (final x in s9) {
        await receive(x);
      }
      await record('S9', s9, {
        'stop': s9Stop,
        'restart': s9Start,
        'sendPhaseMs': s9SendMs,
      });
      final s10 = await send('S10', 'message to delete');
      final deleteCount = events(
        await snapshot('alice'),
        'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
      ).length;
      await flow('alice', 'production_direct_delete', 'S10-delete', {
        'MESSAGE_PATTERN': RegExp.escape(
          _object(s10['sender'])['text']! as String,
        ),
      });
      final message = _object(s10['sender'])['id']! as String;
      final deletion = await waitForProductionObservation(
        'production deletion timing',
        const Duration(minutes: 3),
        () async {
          final added = events(
            await snapshot('alice'),
            'CHAT_MSG_DELETE_FOR_EVERYONE_TIMING',
          ).skip(deleteCount).toList();
          if (added.length > 1) throw StateError('ambiguous deletion result');
          return added.length == 1 ? _object(added.single['details']) : null;
        },
      );
      final tombstone = await waitForProductionObservation(
        'committed receiver tombstone',
        const Duration(minutes: 3),
        () async {
          final rows = _maps(
            (await snapshot('bob', messageIds: [message]))['tombstones'],
          );
          return rows.singleOrNull?['deletedAt'] != null ? rows.single : null;
        },
      );
      await record(
        'S10',
        [s10],
        {'deletion': deletion, 'receiverTombstone': tombstone},
      );
      // Protocol-only load keeps the original ten rapid use-case invocations;
      // serial UI startup would change this load case's semantics.
      final rapid = await journey.alice.routingProtocolCase({
        'caseId': 'S13',
        'peerId': peers['bob'],
      });
      final rapidRows = await snapshot('alice');
      final rapidEvents = _maps(
        rapid['events'],
      ).where((e) => e['event'] == 'CHAT_MSG_SEND_TIMING').toList();
      final ids = (rapid['messageIds'] as List).cast<String>();
      if (ids.length != 10 || rapidEvents.length != 10) {
        throw StateError('rapid send receipts incomplete');
      }
      final s13 = [
        for (var i = 0; i < 10; i++)
          <String, Object?>{
            'senderRole': 'alice',
            'sender': exactRow(rapidRows, ids[i], incoming: false),
            'timing': _object(rapidEvents[i]['details']),
          },
      ];
      final rapidReceiveWatch = Stopwatch()..start();
      await waitForProductionObservation(
        'at least five rapid receipts',
        const Duration(minutes: 3),
        () async {
          final value = await snapshot('bob');
          var received = 0;
          for (final x in s13) {
            final row = _maps(value['messages'])
                .where(
                  (m) =>
                      m['incoming'] == true &&
                      m['id'] == _object(x['sender'])['id'],
                )
                .singleOrNull;
            if (row != null) {
              x['receiver'] = row;
              x['receiptMs'] = rapidReceiveWatch.elapsedMilliseconds;
              received++;
            }
          }
          return received >= 5 ? true : null;
        },
      );
      await record('S13', s13);
      final voice = await journey.alice.routingProtocolCase({
        'caseId': 'S11',
        'peerId': peers['bob'],
      });
      final voiceEvents = _maps(
        voice['events'],
      ).where((e) => e['event'] == 'VOICE_SEND_TIMING').toList();
      if (voiceEvents.length != 1) throw StateError('voice timing missing');
      await record('S11', [
        {
          'senderRole': 'alice',
          'sender': exactRow(
            await snapshot('alice'),
            (voice['messageIds'] as List).single as String,
            incoming: false,
          ),
          'timing': _object(voiceEvents.single['details']),
        },
      ]);
      final media = await journey.alice.routingProtocolCase({
        'caseId': 'S12',
        'peerId': peers['bob'],
      });
      await record('S12', [], {
        'scope': 'informational',
        'uploads': media['uploads'],
      });
      final local = _object(
        (await snapshot('alice'))['localPeers'],
      )[peers['bob']];
      final s14 = await send(
        'S14',
        local == true ? 'local wifi' : 'relay fallback',
        awaitReceive: false,
      );
      // Informational receive keeps the original bounded attempt without a new
      // LAN success threshold. Only an actual incoming row gets a receipt.
      try {
        await receive(s14, timeout: const Duration(seconds: 30));
      } on Exception catch (error) {
        s14['receiveError'] = '$error';
      }
      await record('S14', [s14], {'scope': 'informational', 'isLocal': local});
      await node('bob', 'stop');
      final core = await node('bob', 'start_core');
      final gap = await journey.alice.routingProtocolCase({
        'caseId': 'S15',
        'peerId': peers['bob'],
      });
      final gapEvents = _maps(
        gap['events'],
      ).where((e) => e['event'] == 'CHAT_MSG_SEND_TIMING').toList();
      if (gapEvents.length != 1) throw StateError('gap timing missing');
      final s15 = <String, Object?>{
        'senderRole': 'alice',
        'sender': exactRow(
          await snapshot('alice'),
          (gap['messageIds'] as List).single as String,
          incoming: false,
        ),
        'timing': _object(gapEvents.single['details']),
      };
      await node('bob', 'warm_background');
      await receive(s15);
      await record('S15', [s15], {'coreStart': core});
      final restarts = <Map<String, Object?>>[];
      final stops = {
        for (final role in peers.keys) role: await node(role, 'stop'),
      };
      for (final role in peers.keys) {
        final start = await node(role, 'start');
        await peer(role).awaitReady();
        restarts.add({'role': role, 'stop': stops[role], 'start': start});
      }
      await record(
        'X1',
        [await send('X1', 'post restart')],
        {'restarts': restarts},
      );
      final lifecycle = <Map<String, Object?>>[];
      for (final role in peers.keys) {
        await flow(role, 'production_background', 'X2-$role-home');
        final paused = await snapshot(role);
        lifecycle.add({'role': role, 'paused': paused['lifecycle']});
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      for (final row in lifecycle) {
        final role = row['role']! as String;
        await flow(role, 'production_resume', 'X2-$role-resume');
        row['resumed'] = (await snapshot(role))['lifecycle'];
      }
      await record(
        'X2',
        [await send('X2', 'post resume')],
        {'lifecycle': lifecycle},
      );
      final health = [
        for (final role in peers.keys) await node(role, 'health_check'),
      ];
      await record(
        'X3',
        [await send('X3', 'post healthcheck')],
        {'healthChecks': health},
      );
      await orbit('alice');
      await orbit('bob');
      for (final role in peers.keys) {
        await peer(role).command('rejoin_topics');
      }
      await record('G1', [await send('G1', 'cold group hello', lane: 'group')]);
      final g2 = <Map<String, Object?>>[];
      final g2Watch = Stopwatch()..start();
      for (var n = 1; n <= 5; n++) {
        g2.add(await send('G2', 'warm $n', lane: 'group', n: n));
      }
      await record('G2', g2, {'sendPhaseMs': g2Watch.elapsedMilliseconds});
      final g3 = <Map<String, Object?>>[];
      for (var n = 1; n <= 3; n++) {
        g3.add(
          await send(
            'G3',
            'bidirectional $n',
            lane: 'group',
            role: n == 2 ? 'bob' : 'alice',
            n: n,
          ),
        );
      }
      await record('G3', g3);
      final g4Stop = await node('bob', 'stop');
      final g4 = await send(
        'G4',
        'offline group inbox',
        lane: 'group',
        awaitReceive: false,
      );
      final g4Start = await restartBob(groupRecovery: true);
      await receive(g4);
      await record('G4', [g4], {'stop': g4Stop, 'restart': g4Start});
      final g5 = <Map<String, Object?>>[];
      for (var n = 1; n <= 4; n++) {
        g5.add(
          await send(
            'G5',
            'msg$n ${n == 1 ? 'cold' : 'warm'}',
            lane: 'group',
            n: n,
          ),
        );
      }
      final g5Stop = await node('bob', 'stop');
      final g5Offline = await send(
        'G5',
        'msg5 offline',
        lane: 'group',
        n: 5,
        awaitReceive: false,
      );
      g5.add(g5Offline);
      final g5Start = await restartBob(groupRecovery: true);
      await receive(g5Offline);
      g5.add(await send('G5', 'msg6 reconnect', lane: 'group', n: 6));
      g5.add(await send('G5', 'bob msg7', lane: 'group', role: 'bob', n: 7));
      for (var n = 8; n <= 9; n++) {
        g5.add(await send('G5', 'msg$n warm', lane: 'group', n: n));
      }
      await record('G5', g5, {'stop': g5Stop, 'restart': g5Start});
      await record('G6', [], {
        'scope': 'informational',
        'peerDiscoveryMs': discoveryMs,
        'interval':
            'host join-completion to five-second topic settle; informational',
      });
      final pre = await send('G7', 'pre rotation', lane: 'group');
      final rotation = await journey.alice.routingProtocolCase({
        'caseId': 'G7',
        'groupId': group,
      });
      final post = await send('G7', 'post rotation', lane: 'group');
      await record('G7', [pre, post], {'rotation': rotation});
      await record('G8', [
        await send('G8', 'multi-member publish', lane: 'group'),
      ]);
      final failures = validateProductionRouting(proof);
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
      validatorIds: ['validateProductionRouting'],
      payload: {...journey.provenance(), ...proof, 'status': 'PASS'},
    );
  } catch (error, stack) {
    if (output != null) {
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
    }
  }
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({'status': evidence == null ? 'FAIL' : 'PASS', 'assertionsAttempted': attempted, 'artifactPresent': evidence != null, 'printOnly': false, 'exitCode': evidence == null ? 1 : 0, 'detail': 'production routing 27-case receipt validation', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = evidence == null ? 1 : 0;
}
