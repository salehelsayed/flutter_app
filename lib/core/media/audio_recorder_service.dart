import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

/// Abstract interface for audio recording.
///
/// Production implementation wraps the `record` package.
/// Test implementation uses [FakeAudioRecorderService].
abstract class AudioRecorderService {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> start({required String outputPath});
  Future<AudioRecording?> stop();
  Future<void> cancel();
  bool get isRecording;
  Stream<Duration> get durationStream;
  Future<void> dispose();
}
