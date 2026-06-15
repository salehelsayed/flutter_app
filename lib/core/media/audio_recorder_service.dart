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
  Stream<double> get amplitudeStream;
  Future<void> dispose();

  /// Invoked after the recorder stops itself at the max recording duration,
  /// with the result of that internal stop. Auto-stop happens without any user
  /// gesture, so the active UI surface sets this to resync its composer state
  /// and clears it again on its own stop/cancel paths.
  void Function(AudioRecording? recording)? onAutoStopped;
}
