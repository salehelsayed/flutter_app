/// End-to-end voice message smoke test.
///
/// Tests the full flow: record → stop → verify recording file exists.
/// The full send/receive/playback flow requires two real peers
/// and is best tested manually.
///
/// Run with: flutter test integration_test/voice_message_e2e_test.dart -d <device>
@Tags(['device'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Voice message E2E smoke', () {
    testWidgets('record voice → stop → file exists with valid duration',
        (tester) async {
      final recorder = RecordAudioRecorderService();

      try {
        final hasPermission = await recorder.hasPermission();
        if (!hasPermission) {
          // Skip on devices without mic permission granted
          return;
        }

        // Start recording
        await recorder.start(outputPath: '');
        expect(recorder.isRecording, true);

        // Record for 2 seconds
        await Future.delayed(const Duration(seconds: 2));

        // Stop and get recording
        final recording = await recorder.stop();
        expect(recording, isNotNull);
        expect(recording!.durationMs, greaterThan(1500));
        expect(recording.mime, 'audio/mp4');

        // Verify file
        final file = File(recording.filePath);
        expect(await file.exists(), true);
        expect(recording.sizeBytes, greaterThan(0));

        // Clean up
        await file.delete();
      } finally {
        await recorder.dispose();
      }
    });
  });
}
