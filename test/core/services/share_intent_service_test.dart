import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  group('ShareIntent model', () {
    test('1a: ShareIntent.text creates text intent', () {
      const intent = ShareIntent(type: ShareIntentType.text, text: 'hello');
      expect(intent.hasText, isTrue);
      expect(intent.hasFiles, isFalse);
      expect(intent.text, 'hello');
    });

    test('1b: ShareIntent.files creates file intent', () {
      const intent = ShareIntent(
        type: ShareIntentType.files,
        filePaths: ['/tmp/a.jpg', '/tmp/b.png'],
      );
      expect(intent.hasText, isFalse);
      expect(intent.hasFiles, isTrue);
      expect(intent.filePaths, hasLength(2));
    });

    test('1c: ShareIntent.mixed creates intent with text and files', () {
      const intent = ShareIntent(
        type: ShareIntentType.mixed,
        text: 'Check this out',
        filePaths: ['/tmp/photo.jpg'],
      );
      expect(intent.hasText, isTrue);
      expect(intent.hasFiles, isTrue);
    });
  });

  group('ShareIntentService buffering', () {
    late Directory tempDir;
    late ShareIntentService service;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('share_test_');
      service = ShareIntentService(
        getCacheDirectory: () async => tempDir,
        resetShareIntent: () {},
      );
    });

    tearDown(() {
      service.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('1i: bufferIntent copies shared files to app cache dir', () async {
      // Create a real temp file to copy
      final srcFile = File('${tempDir.path}/original/IMG_1234.jpg');
      srcFile.parent.createSync(recursive: true);
      srcFile.writeAsStringSync('fake image data');

      final intent = ShareIntent(
        type: ShareIntentType.files,
        filePaths: [srcFile.path],
      );

      await service.bufferIntent(intent);

      final buffered = service.consumePendingIntent();
      expect(buffered, isNotNull);
      expect(buffered!.filePaths, hasLength(1));
      // Should be in share_cache, not original location
      expect(buffered.filePaths.first, contains('share_cache'));
      expect(File(buffered.filePaths.first).existsSync(), isTrue);
    });

    test('1i2: bufferIntent with text-only stores without file I/O', () async {
      const intent = ShareIntent(type: ShareIntentType.text, text: 'hello');

      await service.bufferIntent(intent);

      final buffered = service.consumePendingIntent();
      expect(buffered, isNotNull);
      expect(buffered!.text, 'hello');
      expect(buffered.hasFiles, isFalse);
      // No share_cache dir should be created
      final cacheDir = Directory('${tempDir.path}/share_cache');
      expect(cacheDir.existsSync(), isFalse);
    });

    test('1i3: bufferIntent preserves original file names', () async {
      final srcFile = File('${tempDir.path}/original/photo_2026.png');
      srcFile.parent.createSync(recursive: true);
      srcFile.writeAsStringSync('fake png');

      final intent = ShareIntent(
        type: ShareIntentType.files,
        filePaths: [srcFile.path],
      );

      await service.bufferIntent(intent);

      final buffered = service.consumePendingIntent();
      expect(buffered!.filePaths.first, endsWith('photo_2026.png'));
    });

    test(
      '1i4: bufferIntent falls back to original path if copy fails',
      () async {
        const intent = ShareIntent(
          type: ShareIntentType.files,
          filePaths: ['/nonexistent/path/file.jpg'],
        );

        await service.bufferIntent(intent);

        final buffered = service.consumePendingIntent();
        expect(buffered, isNotNull);
        expect(buffered!.filePaths.first, '/nonexistent/path/file.jpg');
      },
    );

    test(
      '1j: consumePendingIntent returns and clears buffered intent',
      () async {
        const intent = ShareIntent(type: ShareIntentType.text, text: 'test');
        await service.bufferIntent(intent);

        final first = service.consumePendingIntent();
        expect(first, isNotNull);
        expect(first!.text, 'test');

        final second = service.consumePendingIntent();
        expect(second, isNull);
      },
    );

    test('1k: consumePendingIntent returns null when no intent buffered', () {
      expect(service.consumePendingIntent(), isNull);
    });

    test('1l: isSettled defaults to false', () {
      expect(service.isSettled, isFalse);
    });

    test('1m: isSettled can be set to true', () {
      service.isSettled = true;
      expect(service.isSettled, isTrue);
    });

    test(
      '1d: intentStream emits converted intents from the plugin stream',
      () async {
        final controller = StreamController<List<SharedMediaFile>>();
        addTearDown(controller.close);
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          getMediaStream: () => controller.stream,
          resetShareIntent: () {},
        );

        final nextIntent = service.intentStream.first;
        controller.add([
          SharedMediaFile(
            path: 'Hello from stream',
            type: SharedMediaType.text,
          ),
        ]);

        final intent = await nextIntent;
        expect(intent.type, ShareIntentType.text);
        expect(intent.text, 'Hello from stream');
        expect(intent.filePaths, isEmpty);
      },
    );

    test('1e: getInitialIntent handles cold-start text shares', () async {
      final service = ShareIntentService(
        getCacheDirectory: () async => tempDir,
        getInitialMedia: () async => [
          SharedMediaFile(
            path: 'https://mknoon.app',
            type: SharedMediaType.url,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.text);
      expect(intent.text, 'https://mknoon.app');
    });

    test(
      '1f: getInitialIntent handles warm-start style mixed shares',
      () async {
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          getInitialMedia: () async => [
            SharedMediaFile(path: 'Caption line', type: SharedMediaType.text),
            SharedMediaFile(
              path: '/tmp/stream-photo.jpg',
              type: SharedMediaType.image,
            ),
          ],
          resetShareIntent: () {},
        );

        final intent = await service.getInitialIntent();

        expect(intent, isNotNull);
        expect(intent!.type, ShareIntentType.mixed);
        expect(intent.text, 'Caption line');
        expect(intent.filePaths, ['/tmp/stream-photo.jpg']);
      },
    );

    test('1g: ignores empty/null-like payloads from the plugin', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      addTearDown(controller.close);
      final service = ShareIntentService(
        getCacheDirectory: () async => tempDir,
        getMediaStream: () => controller.stream,
        getInitialMedia: () async => [
          SharedMediaFile(path: '', type: SharedMediaType.text),
        ],
        resetShareIntent: () {},
      );

      expect(await service.getInitialIntent(), isNull);

      var emitted = false;
      final sub = service.intentStream.listen((_) => emitted = true);
      addTearDown(sub.cancel);

      controller.add([SharedMediaFile(path: '', type: SharedMediaType.text)]);
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isFalse);
    });

    test(
      '1h: reset delegates to plugin reset to prevent duplicate handling',
      () {
        var resetCalls = 0;
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          resetShareIntent: () => resetCalls++,
        );

        service.reset();
        service.reset();

        expect(resetCalls, 2);
      },
    );

    test(
      '1n: getInitialIntent keeps iOS media message as share text',
      () async {
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          getInitialMedia: () async => [
            SharedMediaFile(
              path: '/tmp/photo.jpg',
              type: SharedMediaType.image,
              message: 'Shared caption',
            ),
          ],
          getMediaStream: Stream<List<SharedMediaFile>>.empty,
          resetShareIntent: () {},
        );

        final intent = await service.getInitialIntent();

        expect(intent, isNotNull);
        expect(intent!.type, ShareIntentType.mixed);
        expect(intent.text, 'Shared caption');
        expect(intent.filePaths, ['/tmp/photo.jpg']);
      },
    );

    test(
      '1o: captureInitialIntent buffers cold-start share before routing',
      () async {
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          getInitialMedia: () async => [
            SharedMediaFile(
              path: 'https://example.com',
              type: SharedMediaType.url,
            ),
          ],
          getMediaStream: Stream<List<SharedMediaFile>>.empty,
          resetShareIntent: () {},
        );

        final intent = await service.captureInitialIntent();

        expect(intent, isNotNull);
        expect(service.hasPendingIntent, isTrue);
        expect(service.consumePendingIntent()?.text, 'https://example.com');
      },
    );

    test(
      '1p: captureInitialIntent keeps pending empty when no share exists',
      () async {
        final service = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          getInitialMedia: () async => const [],
          getMediaStream: Stream<List<SharedMediaFile>>.empty,
          resetShareIntent: () {},
        );

        final intent = await service.captureInitialIntent();

        expect(intent, isNull);
        expect(service.hasPendingIntent, isFalse);
      },
    );
  });
}
