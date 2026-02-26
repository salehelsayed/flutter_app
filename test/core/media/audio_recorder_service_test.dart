import 'package:flutter_test/flutter_test.dart';
import '../../shared/fakes/fake_audio_recorder_service.dart';

void main() {
  group('AudioRecorderService contract (via Fake)', () {
    late FakeAudioRecorderService recorder;

    setUp(() {
      recorder = FakeAudioRecorderService();
    });

    tearDown(() async {
      await recorder.dispose();
    });

    test('start() sets isRecording to true', () async {
      await recorder.start(outputPath: '/tmp/test.m4a');
      expect(recorder.isRecording, true);
    });

    test('stop() returns AudioRecording with correct duration', () async {
      recorder.fakeDurationMs = 5000;
      recorder.fakeSizeBytes = 80000;

      await recorder.start(outputPath: '/tmp/test.m4a');
      final result = await recorder.stop();

      expect(result, isNotNull);
      expect(result!.durationMs, 5000);
      expect(result.sizeBytes, 80000);
      expect(result.filePath, '/tmp/test.m4a');
    });

    test('stop() sets isRecording to false', () async {
      await recorder.start(outputPath: '/tmp/test.m4a');
      expect(recorder.isRecording, true);

      await recorder.stop();
      expect(recorder.isRecording, false);
    });

    test('cancel() sets isRecording to false and returns no recording',
        () async {
      await recorder.start(outputPath: '/tmp/test.m4a');
      expect(recorder.isRecording, true);

      await recorder.cancel();
      expect(recorder.isRecording, false);
    });

    test('cancel() records the deleted path', () async {
      await recorder.start(outputPath: '/tmp/test.m4a');
      await recorder.cancel();
      expect(recorder.deletedPaths, contains('/tmp/test.m4a'));
    });

    test('durationStream emits elapsed durations while recording', () async {
      final durations = <Duration>[];
      final sub = recorder.durationStream.listen(durations.add);

      await recorder.start(outputPath: '/tmp/test.m4a');
      recorder.emitDuration(const Duration(milliseconds: 100));
      recorder.emitDuration(const Duration(milliseconds: 200));

      await Future<void>.delayed(Duration.zero);
      expect(durations.length, 2);
      expect(durations[0], const Duration(milliseconds: 100));
      expect(durations[1], const Duration(milliseconds: 200));

      await sub.cancel();
    });

    test('cannot start() while already recording', () async {
      await recorder.start(outputPath: '/tmp/test.m4a');
      expect(
        () => recorder.start(outputPath: '/tmp/test2.m4a'),
        throwsStateError,
      );
    });

    test('stop() returns null if duration < 500ms', () async {
      recorder.fakeDurationMs = 200;

      await recorder.start(outputPath: '/tmp/test.m4a');
      final result = await recorder.stop();

      expect(result, isNull);
    });

    test('amplitudeStream emits values when emitAmplitude() called', () async {
      final values = <double>[];
      final sub = recorder.amplitudeStream.listen(values.add);

      recorder.emitAmplitude(0.5);
      recorder.emitAmplitude(0.8);

      await Future<void>.delayed(Duration.zero);
      expect(values, [0.5, 0.8]);

      await sub.cancel();
    });

    test('amplitudeStream is a broadcast stream (multi-listener safe)',
        () async {
      final values1 = <double>[];
      final values2 = <double>[];
      final sub1 = recorder.amplitudeStream.listen(values1.add);
      final sub2 = recorder.amplitudeStream.listen(values2.add);

      recorder.emitAmplitude(0.3);

      await Future<void>.delayed(Duration.zero);
      expect(values1, [0.3]);
      expect(values2, [0.3]);

      await sub1.cancel();
      await sub2.cancel();
    });
  });
}
