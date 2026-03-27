/// End-to-end voice message smoke test.
///
/// Tests the full flow: record → stop → verify recording file exists.
/// The full send/receive/playback flow requires two real peers
/// and is best tested manually.
///
/// Run with: flutter test integration_test/voice_message_e2e_test.dart -d deviceId
@Tags(['device'])
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_app/core/media/record_audio_recorder_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Voice message E2E smoke', () {
    testWidgets(
      'record voice → stop → file exists with valid duration',
      (tester) async {
        final recorder = RecordAudioRecorderService();

        try {
          final hasPermission = await _safeHasPermission(recorder);
          if (!hasPermission) {
            // Skip on devices without mic permission granted
            print('[TEST] SKIP: microphone permission not available.');
            return;
          }

          // Start recording
          await recorder
              .start(outputPath: '')
              .timeout(const Duration(seconds: 10));
          expect(recorder.isRecording, true);

          // Record for 2 seconds
          await Future.delayed(const Duration(seconds: 2));

          // Stop and get recording
          final recording = await recorder.stop().timeout(
            const Duration(seconds: 15),
          );
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
      },
      skip: _shouldSkipVoiceMessageE2E(),
    );
  });
}

bool _shouldSkipVoiceMessageE2E() {
  if (!Platform.isIOS) return false;
  if (Directory.systemTemp.path.contains('CoreSimulator')) {
    return true;
  }
  final env = Platform.environment;
  return env.containsKey('SIMULATOR_DEVICE_NAME') ||
      env.containsKey('SIMULATOR_UDID') ||
      env.containsKey('SIMULATOR_HOST_HOME') ||
      env.containsKey('IPHONE_SIMULATOR_ROOT');
}

Future<bool> _safeHasPermission(RecordAudioRecorderService recorder) async {
  try {
    return await recorder.hasPermission();
  } on MissingPluginException {
    return false;
  }
}
