import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';

void main() {
  group('AudioRecording', () {
    test('construction with all fields', () {
      final recording = AudioRecording(
        filePath: '/tmp/voice_123.m4a',
        durationMs: 3000,
        mime: 'audio/mp4',
        sizeBytes: 48000,
      );

      expect(recording.filePath, '/tmp/voice_123.m4a');
      expect(recording.durationMs, 3000);
      expect(recording.mime, 'audio/mp4');
      expect(recording.sizeBytes, 48000);
    });

    test('mime defaults to audio/mp4', () {
      final recording = AudioRecording(
        filePath: '/tmp/voice_123.m4a',
        durationMs: 3000,
        sizeBytes: 48000,
      );

      expect(recording.mime, 'audio/mp4');
    });

    test('toString includes duration', () {
      final recording = AudioRecording(
        filePath: '/tmp/voice_123.m4a',
        durationMs: 3000,
        sizeBytes: 48000,
      );

      final str = recording.toString();
      expect(str, contains('3000'));
    });

    test('equality by filePath', () {
      final a = AudioRecording(
        filePath: '/tmp/voice_123.m4a',
        durationMs: 3000,
        sizeBytes: 48000,
      );
      final b = AudioRecording(
        filePath: '/tmp/voice_123.m4a',
        durationMs: 5000,
        sizeBytes: 80000,
      );
      final c = AudioRecording(
        filePath: '/tmp/voice_456.m4a',
        durationMs: 3000,
        sizeBytes: 48000,
      );

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });
  });
}
