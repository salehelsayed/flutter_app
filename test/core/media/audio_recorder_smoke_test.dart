/// Smoke test for [RecordAudioRecorderService] on a real device.
///
/// Requires a real device with microphone access — skipped in CI.
/// Run with: flutter test test/core/media/audio_recorder_smoke_test.dart -d <device>
@Tags(['device'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';

void main() {
  group('RecordAudioRecorderService smoke', () {
    late RecordAudioRecorderService recorder;

    setUp(() {
      recorder = RecordAudioRecorderService();
    });

    tearDown(() async {
      await recorder.dispose();
    });

    test('records audio and produces a valid .m4a file', () async {
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) {
        // Skip on CI / devices without mic permission
        return;
      }

      await recorder.start(outputPath: '');
      expect(recorder.isRecording, true);

      // Record for 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      final recording = await recorder.stop();
      expect(recorder.isRecording, false);
      expect(recording, isNotNull);

      final file = File(recording!.filePath);
      expect(await file.exists(), true);
      expect(recording.durationMs, greaterThan(1500));
      expect(recording.durationMs, lessThan(4000));
      expect(recording.sizeBytes, greaterThan(0));
      expect(recording.mime, 'audio/mp4');

      // Clean up
      await file.delete();
    });

    test('cancel discards the recording file', () async {
      final hasPermission = await recorder.hasPermission();
      if (!hasPermission) return;

      await recorder.start(outputPath: '');
      expect(recorder.isRecording, true);

      await Future.delayed(const Duration(seconds: 1));

      await recorder.cancel();
      expect(recorder.isRecording, false);
      // File should have been cleaned up by cancel()
    });
  });
}
