import 'dart:convert';
import 'dart:io';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_group_media_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';

const _scenario = 'production.group_new_member_media';
const _original = 'integration_test/group_new_member_media_simulator_proof_test.dart';

/// The original fixture bytes, read from the unchanged original harness so the
/// replacement renders exactly the same media.
Map<String, String> _originalFixtures() {
  final source = File(_original).readAsStringSync();
  String constant(String name) {
    final match = RegExp(
      '$name =\\s*(?:\'\'\'([^\']*)\'\'\'|\'([^\']*)\')',
    ).firstMatch(source);
    if (match == null) throw StateError('original fixture $name missing');
    return (match.group(1) ?? match.group(2)!).replaceAll(RegExp(r'\s+'), '');
  }

  return {
    'mp4Base64': constant('_tinyMp4Base64'),
    'mp3Base64': constant('_tinyMp3Base64'),
    'pngBase64': constant('_tinyPngBase64'),
    'encryptionKeyBase64': constant('_fixtureEncryptionKeyBase64'),
    'encryptionNonce': constant('_fixtureEncryptionNonce'),
  };
}

final _bounds = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');

/// Nodes from a uiautomator dump: (content-desc, text, left, top, right, bottom).
List<(String, String, int, int, int, int)> _nodes(String xml) => [
  for (final m in RegExp(r'<node [^>]*>').allMatches(xml))
    () {
      final node = m.group(0)!;
      String attr(String name) =>
          RegExp('$name="([^"]*)"').firstMatch(node)?.group(1) ?? '';
      final b = _bounds.firstMatch(attr('bounds'));
      return (
        attr('content-desc'),
        attr('text'),
        int.parse(b?.group(1) ?? '0'),
        int.parse(b?.group(2) ?? '0'),
        int.parse(b?.group(3) ?? '0'),
        int.parse(b?.group(4) ?? '0'),
      );
    }(),
];

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
    final flows = <String>[];
    final passes = <Map<String, Object?>>[];
    final proof = <String, Object?>{
      'runId': journey.runId,
      'flows': flows,
      'passes': passes,
      'cases': <Map<String, Object?>>[],
    };
    Future<void> persist() => File(
      '${output!.path}/observations.json',
    ).writeAsString(jsonEncode(proof));

    Future<List<(String, String, int, int, int, int)>> dump(
      ProductionJourneyPeer peer,
      String label,
    ) async {
      await peer.adb(['shell', 'uiautomator', 'dump', '/sdcard/mknoon-media.xml']);
      final xml = '${(await peer.adb(['shell', 'cat', '/sdcard/mknoon-media.xml'])).stdout}';
      await File('${output!.path}/hierarchy-$label.xml').writeAsString(xml);
      await peer.adb(['shell', 'rm', '-f', '/sdcard/mknoon-media.xml']);
      return _nodes(xml);
    }

    Future<void> tap(ProductionJourneyPeer peer, int x, int y, String label) async {
      await journey.flow(peer, 'production_media_tap_point', label, {
        'X': '$x',
        'Y': '$y',
      });
      flows.add(label);
    }

    try {
      await journey.prepare();
      final alice = (await journey.alice.command('identity'))['peerId']! as String;
      proof['peers'] = {
        'alice': alice,
        'bob': (await journey.bob.command('identity'))['peerId'],
      };
      final seeded = await journey.bob.command('prepare_new_member_media', {
        'alicePeerId': alice,
        ..._originalFixtures(),
      });
      final groupId = seeded['groupId']! as String;
      proof['groupId'] = groupId;
      proof['seeded'] = seeded;
      await persist();
      attempts++;
      for (final pass in ['initial', 'reopened']) {
        // Reopen lets Orbit list the seeded group; the second reopen is the
        // original's dispose-and-pump-again.
        journey.bob = await journey.reopen(journey.bob);
        await journey.flow(journey.bob, 'production_group_open', '$pass-open', {
          'GROUP_ID': groupId,
        });
        flows.add('$pass-open');
        final record = <String, Object?>{'pass': pass};
        passes.add(record);
        record['rows'] = await waitForProductionObservation(
          '$pass-rows',
          const Duration(seconds: 8),
          () async {
            final s = await journey.bob.command('media_snapshot');
            final tree = s['tree']! as Map;
            return tree['audioPlayerWidgets'] == 2 &&
                    (tree['durationLabels'] as int) >= 2
                ? s
                : null;
          },
        );
        final nodes = await dump(journey.bob, pass);
        // The incoming bubble is one merged node; its clickable children are
        // the video cell (largest) and the voice play button (the square one).
        final bubble = nodes.where(
          (n) =>
              n.$1.contains('Voice message') &&
              n.$1.contains('post-join text plus video and voice'),
        );
        if (bubble.isEmpty) throw StateError('$pass incoming bubble not found');
        final b = bubble.first;
        final inside = nodes
            .where(
              (n) =>
                  n.$3 >= b.$3 &&
                  n.$4 >= b.$4 &&
                  n.$5 <= b.$5 &&
                  n.$6 <= b.$6 &&
                  n != b &&
                  n.$5 > n.$3 &&
                  n.$6 > n.$4,
            )
            .toList();
        final play = inside.where(
          (n) =>
              n.$1.isEmpty &&
              ((n.$5 - n.$3) - (n.$6 - n.$4)).abs() <= 4 &&
              (n.$5 - n.$3) < 200,
        );
        if (play.isEmpty) throw StateError('$pass voice play control not found');
        final v = play.first;
        await journey.bob.command('media_watch_playing');
        await tap(journey.bob, (v.$3 + v.$5) ~/ 2, (v.$4 + v.$6) ~/ 2, '$pass-play-voice');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        record['voice'] = await journey.bob.command('media_playing_result');
        await persist();
        final video = inside.toList()
          ..sort(
            (x, y) => ((y.$5 - y.$3) * (y.$6 - y.$4)).compareTo(
              (x.$5 - x.$3) * (x.$6 - x.$4),
            ),
          );
        if (video.isEmpty) throw StateError('$pass video cell not found');
        final c = video.first;
        await tap(journey.bob, (c.$3 + c.$5) ~/ 2, (c.$4 + c.$6) ~/ 2, '$pass-open-video');
        record['viewer'] = await waitForProductionObservation(
          '$pass-viewer',
          const Duration(seconds: 8),
          () async {
            final s = await journey.bob.command('media_snapshot');
            final tree = s['tree']! as Map;
            return (tree['videoPlayers'] as int) > 0 ||
                    (tree['videoLoadErrors'] as int) > 0
                ? s
                : null;
          },
        );
        await journey.flow(journey.bob, 'production_media_viewer_back', '$pass-viewer-back');
        flows.add('$pass-viewer-back');
        await persist();
      }
      (proof['cases']! as List).add({'id': 'NEW_MEMBER_MEDIA', 'status': 'PASS'});
      await persist();
      final failures = validateProductionGroupMedia(proof);
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
      validatorIds: ['validateProductionGroupMedia'],
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
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempts, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production new member media passed' : 'production new member media failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
