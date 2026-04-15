/// Simulator Benchmark: Voice Send Sub-Steps (Test K)
///
/// Measures voice message upload + transport sub-step timing.
/// Run: flutter test integration_test/benchmark_voice_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';

import 'benchmark_helpers.dart';

const _configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('K-Sim-1: Voice note send', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: VOICE SEND (K-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // Create a test audio file
    final tmpDir = Directory.systemTemp.createTempSync('voice_bench_');
    final testFile = File('${tmpDir.path}/test_voice.m4a');
    testFile.writeAsBytesSync(List.filled(48000, 0)); // ~48KB

    final recording = AudioRecording(
      filePath: testFile.path,
      durationMs: 3000,
      sizeBytes: 48000,
    );

    final messageRepo = InMemoryMessageRepository();
    final targetPeerId = '12D3KooWOfflinePeerForVoiceBenchmark00000';

    final events = await captureFlowEvents(() async {
      await sendVoiceMessage(
        p2pService: node.service,
        messageRepo: messageRepo,
        targetPeerId: targetPeerId,
        senderPeerId: node.peerId,
        senderUsername: 'BenchmarkUser',
        recording: recording,
        bridge: node.bridge,
      );
    });

    final voiceTiming = filterEvents(events, 'VOICE_SEND_TIMING');
    if (voiceTiming.isNotEmpty) {
      final d = voiceTiming.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle('sim_voice_total_ms', d['elapsedMs'] as int);
      if (d.containsKey('uploadMs')) {
        printBenchmarkSingle('sim_voice_upload_ms', d['uploadMs'] as int);
      }
      if (d.containsKey('sendMs')) {
        printBenchmarkSingle('sim_voice_send_ms', d['sendMs'] as int);
      }
      // §8: upload share percentage
      if (d.containsKey('uploadMs') && d.containsKey('elapsedMs')) {
        final uploadMs = d['uploadMs'] as int;
        final totalMs = d['elapsedMs'] as int;
        final uploadSharePct =
            totalMs > 0 ? (uploadMs / totalMs * 100).round() : 0;
        print('[BENCHMARK] sim_voice_upload_share_pct = $uploadSharePct%');
      }
      print('[BENCHMARK] sim_voice_outcome = ${d['outcome']}');
    }

    // Cleanup
    tmpDir.deleteSync(recursive: true);
    await node.dispose();
  });
}
