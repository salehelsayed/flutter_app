/// Simulator Benchmark: Media Transfer Timing (Test E)
///
/// Measures media upload latency, throughput, and stall detection.
/// Two-node upload tests require CLI test peer via orchestrator.
/// Run: flutter test integration_test/benchmark_media_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

import 'benchmark_helpers.dart';

const _configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);

Map<String, dynamic>? _loadFixture() {
  final path = _configuredCliPeerFixture.isNotEmpty
      ? _configuredCliPeerFixture
      : '${Directory.systemTemp.path}/cli_peer_fixture.json';
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('E-Sim-1: Upload files (1MB, 5MB) to test peer', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: MEDIA TRANSFER (E-Sim-1)');
    print('${'═' * 60}\n');

    final fixture = _loadFixture();
    if (fixture == null) {
      print(
        '[SKIP] No CLI peer fixture — run via orchestrator for'
        ' two-node media transfer',
      );

      // Still measure stream open timing with offline peer
      final node = await createBenchmarkNode();
      await node.startAndWaitOnline();

      final tmpDir = Directory.systemTemp.createTempSync('media_bench_');
      try {
        // Create 1MB test file
        final file1mb = File('${tmpDir.path}/test_1mb.bin');
        file1mb.writeAsBytesSync(List.filled(1024 * 1024, 0x42));

        final events = await captureFlowEventsUntil(() async {
          try {
            await callP2PMediaUpload(
              node.bridge,
              id: 'bench-offline-${DateTime.now().millisecondsSinceEpoch}',
              toPeerId: '12D3KooWOfflinePeerForMediaBenchmark00000',
              mime: 'application/octet-stream',
              filePath: file1mb.path,
            );
          } catch (_) {
            // Expected — peer offline
          }
        }, postActionTimeout: const Duration(seconds: 2));

        // §21: media:stream_open_timing
        final streamOpen = filterEvents(events, 'media:stream_open_timing');
        for (final e in streamOpen) {
          final d = e['details'] as Map<String, dynamic>;
          if (d.containsKey('totalMs')) {
            printBenchmarkSingle(
              'sim_media_stream_open_ms',
              (d['totalMs'] as num).toInt(),
            );
          }
          print('[BENCHMARK] sim_media_stream_open = $d');
        }
      } finally {
        tmpDir.deleteSync(recursive: true);
      }

      await node.dispose();
      return;
    }

    // Two-node path: upload to test peer
    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final tmpDir = Directory.systemTemp.createTempSync('media_bench_');
    try {
      final sizes = {'1mb': 1024 * 1024, '5mb': 5 * 1024 * 1024};

      for (final entry in sizes.entries) {
        final label = entry.key;
        final size = entry.value;

        final testFile = File('${tmpDir.path}/test_$label.bin');
        testFile.writeAsBytesSync(List.filled(size, 0x42));
        final mediaId = 'bench-$label-${DateTime.now().millisecondsSinceEpoch}';

        print('\n--- Uploading $label (${size} bytes) ---');
        Map<String, dynamic>? uploadResult;
        Object? uploadError;
        final events = await captureFlowEventsUntil(
          () async {
            try {
              uploadResult = await callP2PMediaUpload(
                node.bridge,
                id: mediaId,
                toPeerId: targetPeerId,
                mime: 'application/octet-stream',
                filePath: testFile.path,
              );
            } catch (e) {
              uploadError = e;
              print('[MEDIA] Upload error: $e');
            }
          },
          postActionTimeout: const Duration(seconds: 3),
          until: (events) {
            return filterEvents(events, 'media:upload_complete').isNotEmpty;
          },
        );

        if (uploadError != null) {
          fail('E-Sim-1 upload for $label threw: $uploadError');
        }
        if (uploadResult == null) {
          fail('E-Sim-1 upload for $label returned no response');
        }
        if (uploadResult!['ok'] != true) {
          fail(
            'E-Sim-1 upload for $label failed: '
            '${uploadResult!['errorCode'] ?? 'unknown'} '
            '${uploadResult!['errorMessage'] ?? uploadResult}',
          );
        }

        // §21: media:stream_open_timing
        final streamOpen = filterEvents(events, 'media:stream_open_timing');
        expect(
          streamOpen,
          isNotEmpty,
          reason:
              'E-Sim-1 should emit media:stream_open_timing for $label upload',
        );
        for (final e in streamOpen) {
          final d = e['details'] as Map<String, dynamic>;
          if (d.containsKey('totalMs')) {
            printBenchmarkSingle(
              'sim_media_${label}_stream_open_ms',
              (d['totalMs'] as num).toInt(),
            );
          }
          print('[BENCHMARK] sim_media_${label}_stream_open = $d');
        }

        // §21: media:upload_complete
        final complete = filterEvents(events, 'media:upload_complete');
        expect(
          complete,
          isNotEmpty,
          reason: 'E-Sim-1 should emit media:upload_complete for $label upload',
        );
        for (final e in complete) {
          final d = e['details'] as Map<String, dynamic>;
          if (d.containsKey('totalMs')) {
            printBenchmarkSingle(
              'sim_media_${label}_upload_ms',
              (d['totalMs'] as num).toInt(),
            );
          }
          if (d.containsKey('throughputBytesPerSec')) {
            print(
              '[BENCHMARK] sim_media_${label}_throughput = '
              '${d['throughputBytesPerSec']} bytes/sec',
            );
          }
          print(
            '[BENCHMARK] sim_media_${label}_measurement_source = '
            'go_upload_complete',
          );
        }

        // Count progress events (§3 profile upload progress)
        final progress = filterEvents(events, 'media:upload_progress');
        print(
          '[BENCHMARK] sim_media_${label}_progress_events = '
          '${progress.length}',
        );
      }
    } finally {
      tmpDir.deleteSync(recursive: true);
    }

    await node.dispose();
  });

  testWidgets('E-Sim-2: Profile upload with progress events', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: PROFILE UPLOAD (E-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final tmpDir = Directory.systemTemp.createTempSync('profile_bench_');
    try {
      final profileFile = File('${tmpDir.path}/test_profile.jpg');
      // Profile uploads are capped at 512KB on the relay.
      profileFile.writeAsBytesSync(List.filled(256 * 1024, 0x42)); // 256KB

      Map<String, dynamic>? profileUploadResult;
      Object? profileUploadError;
      final events = await captureFlowEventsUntil(
        () async {
          final stopwatch = Stopwatch()..start();
          try {
            profileUploadResult = await callP2PProfileUpload(
              node.bridge,
              mime: 'image/jpeg',
              filePath: profileFile.path,
            );
          } catch (e) {
            profileUploadError = e;
            print('[PROFILE] Upload error: $e');
          } finally {
            stopwatch.stop();
            printBenchmarkSingle(
              'sim_profile_upload_total_ms',
              stopwatch.elapsedMilliseconds,
            );
          }
        },
        postActionTimeout: const Duration(seconds: 2),
        until: (events) {
          return filterEvents(events, 'profile:upload_progress').length >= 2;
        },
      );

      if (profileUploadError != null) {
        fail('E-Sim-2 profile upload threw: $profileUploadError');
      }
      if (profileUploadResult == null) {
        fail('E-Sim-2 profile upload returned no response');
      }
      if (profileUploadResult!['ok'] != true) {
        fail(
          'E-Sim-2 profile upload failed: '
          '${profileUploadResult!['errorCode'] ?? 'unknown'} '
          '${profileUploadResult!['errorMessage'] ?? profileUploadResult}',
        );
      }

      final streamOpen = filterEvents(events, 'media:stream_open_timing');
      expect(
        streamOpen,
        isNotEmpty,
        reason: 'E-Sim-2 should emit media:stream_open_timing',
      );
      for (final e in streamOpen) {
        final d = e['details'] as Map<String, dynamic>;
        if (d.containsKey('totalMs')) {
          printBenchmarkSingle(
            'sim_profile_stream_open_ms',
            (d['totalMs'] as num).toInt(),
          );
        }
        print('[BENCHMARK] sim_profile_stream_open = $d');
      }

      // §3: profile:upload_progress events
      final profileProgress = filterEvents(events, 'profile:upload_progress');
      expect(
        profileProgress.length,
        greaterThanOrEqualTo(2),
        reason: 'E-Sim-2 should emit profile:upload_progress start/end events',
      );
      print(
        '[BENCHMARK] sim_profile_progress_event_count = '
        '${profileProgress.length}',
      );
      if (profileProgress.isNotEmpty) {
        final first = profileProgress.first['details'] as Map<String, dynamic>;
        final last = profileProgress.last['details'] as Map<String, dynamic>;
        print('[BENCHMARK] sim_profile_first_progress = $first');
        print('[BENCHMARK] sim_profile_last_progress = $last');
      }

      // media:upload_progress (general)
      final uploadProgress = filterEvents(events, 'media:upload_progress');
      print(
        '[BENCHMARK] sim_media_progress_event_count = '
        '${uploadProgress.length}',
      );
    } finally {
      tmpDir.deleteSync(recursive: true);
    }

    await node.dispose();
  });
}
