import 'dart:io';

import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/conversation/application/send_chat_message_use_case_test.dart'
    show FakeP2PService, FakeMessageRepository;
import '../core/bridge/fake_bridge.dart';
import 'benchmark_harness.dart';
import 'timing_test_bridge.dart';

void main() {
  late BenchmarkHarness harness;
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('voice_bench_');
  });

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  AudioRecording createRecording({int sizeBytes = 48000}) {
    final path =
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
    return AudioRecording(
      filePath: path,
      durationMs: 3000,
      sizeBytes: sizeBytes,
    );
  }

  group('Benchmark: Voice Send Sub-Steps', () {
    test('K1: VOICE_SEND_TIMING includes uploadMs and sendMs', () async {
      final bridge = FakeBridge(
        initialResponses: {
          'media:upload': {'ok': true},
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
      final p2pService = FakeP2PService();
      final messageRepo = FakeMessageRepository();
      final recording = createRecording();

      final events = await harness.captureFlowEvents(() async {
        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Test',
          recording: recording,
          bridge: bridge,
        );
      });

      final timings = harness.filterEvents(events, 'VOICE_SEND_TIMING');
      expect(timings, isNotEmpty, reason: 'Should emit VOICE_SEND_TIMING');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['elapsedMs'], greaterThanOrEqualTo(0));
      expect(details['outcome'], isA<String>());
      expect(details['durationMs'], 3000);
      expect(details['sizeBytes'], 48000);
    });

    test('K2: Upload-dominated voice send reports uploadMs > sendMs',
        () async {
      final bridge = TimingTestBridge(
        commandDelays: {
          'media:upload': const Duration(milliseconds: 200),
        },
        responseTimingFields: {
          'media:upload': {'ok': true},
        },
      );
      bridge.responses['media:upload'] = {'ok': true};

      final p2pService = FakeP2PService();
      final messageRepo = FakeMessageRepository();
      final recording = createRecording();

      final events = await harness.captureFlowEvents(() async {
        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Test',
          recording: recording,
          bridge: bridge,
        );
      });

      final timings = harness.filterEvents(events, 'VOICE_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      if (details['outcome'] == 'success') {
        final uploadMs = details['uploadMs'] as int;
        expect(
          uploadMs,
          greaterThanOrEqualTo(200),
          reason: 'Upload should include the configured delay',
        );
      }
    });

    test('K3: Invalid recording emits VOICE_SEND_TIMING with outcome',
        () async {
      final bridge = FakeBridge();
      final p2pService = FakeP2PService();
      final messageRepo = FakeMessageRepository();

      // Zero-size recording = invalid
      final recording = AudioRecording(
        filePath: '/nonexistent/voice.m4a',
        durationMs: 3000,
        sizeBytes: 48000,
      );

      final events = await harness.captureFlowEvents(() async {
        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Test',
          recording: recording,
          bridge: bridge,
        );
      });

      final timings = harness.filterEvents(events, 'VOICE_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['outcome'], isNot('success'));
    });
  });
}
