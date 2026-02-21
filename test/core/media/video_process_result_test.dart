import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/video_process_result.dart';

void main() {
  group('VideoProcessResult', () {
    test('stores path correctly', () {
      final result = VideoProcessResult(path: '/tmp/video.mp4');
      expect(result.path, '/tmp/video.mp4');
    });

    test('stores width, height, durationMs when provided', () {
      final result = VideoProcessResult(
        path: '/tmp/video.mp4',
        width: 1920,
        height: 1080,
        durationMs: 30000,
      );

      expect(result.width, 1920);
      expect(result.height, 1080);
      expect(result.durationMs, 30000);
    });

    test('has null metadata when not provided', () {
      final result = VideoProcessResult(path: '/tmp/video.mp4');

      expect(result.width, isNull);
      expect(result.height, isNull);
      expect(result.durationMs, isNull);
    });
  });
}
