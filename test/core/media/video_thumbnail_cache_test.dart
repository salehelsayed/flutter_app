import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/video_thumbnail_cache.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

void main() {
  late Directory tempDir;
  late List<Map<String, dynamic>> events;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_thumb_cache_');
    events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
  });

  tearDown(() async {
    debugSetFlowEventSink(null);
    debugSetVideoThumbnailGenerator(null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'generation failure emits a FLOW event and returns null (not silent)',
    () async {
      final videoPath = '${tempDir.path}/gen-fail.mp4';
      File(videoPath).writeAsBytesSync(const [0, 0, 0, 18, 102, 116, 121, 112]);

      debugSetVideoThumbnailGenerator(
        (_) async => throw StateError('boom'),
      );

      final result = await VideoThumbnailCache.resolve(videoPath);

      expect(result, isNull);
      final failure = events.where(
        (e) => e['event'] == 'VIDEO_THUMBNAIL_GENERATE_FAILED',
      );
      expect(
        failure,
        isNotEmpty,
        reason: 'thumbnail generation failure must be observable in FLOW logs',
      );
      expect(failure.first['layer'], 'FL');
      expect(failure.first['details'], isA<Map<String, dynamic>>());
      final details = failure.first['details'] as Map<String, dynamic>;
      expect(details['error'], contains('boom'));
    },
  );

  test('successful generation does not emit the failure event', () async {
    final videoPath = '${tempDir.path}/gen-ok.mp4';
    File(videoPath).writeAsBytesSync(const [0, 0, 0, 18, 102, 116, 121, 112]);
    final generated = File('${tempDir.path}/generated.thumb.jpg')
      ..writeAsBytesSync(const [0xFF, 0xD8, 0xFF, 0xE0]);

    debugSetVideoThumbnailGenerator((_) async => generated);

    final result = await VideoThumbnailCache.resolve(videoPath);

    expect(result, isNotNull);
    expect(
      events.where((e) => e['event'] == 'VIDEO_THUMBNAIL_GENERATE_FAILED'),
      isEmpty,
    );
  });

  test('non-video path returns null without invoking the generator', () async {
    var generatorCalled = false;
    debugSetVideoThumbnailGenerator((_) async {
      generatorCalled = true;
      return File('${tempDir.path}/never.jpg');
    });

    final result = await VideoThumbnailCache.resolve('${tempDir.path}/note.txt');

    expect(result, isNull);
    expect(generatorCalled, isFalse);
  });
}
