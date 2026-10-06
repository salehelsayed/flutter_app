import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_transport_census_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.transport_census';

/// The original census conditions: cold (connection dropped before each of
/// the default 50 sends) and warm (connection kept), paced as the original
/// (`CENSUS_SEND_INTERVAL_MS` default 2500 ms).
const _conditions = [
  (name: 'A_cold', n: 50, cold: true),
  (name: 'B_warm', n: 20, cold: false),
];
const _sendInterval = Duration(milliseconds: 2500);

/// Production main owns all services; this runner owns the condition order,
/// pacing and receipt collection. Alice (physical phone) sends, Bob
/// (emulator) receives.
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
    final conditions = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'interval': productionTransportCensusInterval,
      'conditions': conditions,
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));
    try {
      await journey.prepare();
      final alicePeer = (await journey.alice.command('identity'))['peerId'];
      final bobPeer = (await journey.bob.command('identity'))['peerId'];
      proof['peers'] = {'alice': alicePeer, 'bob': bobPeer};
      for (final c in _conditions) {
        attempts++;
        final texts = [
          for (var i = 1; i <= c.n; i++) 'census-${journey.runId}-${c.name}-$i',
        ];
        final sends = <Map<String, Object?>>[];
        final record = <String, Object?>{
          'name': c.name,
          'n': c.n,
          'cold': c.cold,
          'sendIntervalMs': _sendInterval.inMilliseconds,
          'texts': texts,
          'sends': sends,
        };
        conditions.add(record);
        record['begin'] = await journey.alice.command('census_begin', {
          'condition': c.name,
          'peerId': bobPeer,
        });
        await persist();
        for (var i = 1; i <= c.n; i++) {
          sends.add(
            await journey.alice.command('census_send', {
              'index': i,
              'cold': c.cold,
              'peerId': bobPeer,
            }),
          );
          await persist();
          if (i < c.n) await Future<void>.delayed(_sendInterval);
        }
        final delivered = [
          for (final s in sends)
            if (s['result'] == 'success') texts[(s['index']! as int) - 1],
        ];
        record['delivered'] = delivered.length;
        record['failed'] = sends.length - delivered.length;
        record['report'] = await journey.alice.command('census_report');
        List<Object?> received = const [];
        try {
          await waitForProductionObservation(
            '${c.name} receiver stored every delivered census text',
            const Duration(minutes: 2),
            () async {
              final result = await journey.bob.command('census_received', {
                'peerId': alicePeer,
              });
              received = result['texts']! as List;
              return delivered.every(received.contains) ? true : null;
            },
          );
        } on Object catch (error) {
          record['receiverWaitError'] = '$error';
        }
        record['receivedTexts'] = received;
        await persist();
      }
      final failures = validateProductionTransportCensus(proof);
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
      validatorIds: ['validateProductionTransportCensus'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production transport census passed' : 'production transport census failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
