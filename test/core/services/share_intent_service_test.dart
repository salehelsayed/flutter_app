import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';

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

    test('1i4: bufferIntent falls back to original path if copy fails',
        () async {
      const intent = ShareIntent(
        type: ShareIntentType.files,
        filePaths: ['/nonexistent/path/file.jpg'],
      );

      await service.bufferIntent(intent);

      final buffered = service.consumePendingIntent();
      expect(buffered, isNotNull);
      expect(buffered!.filePaths.first, '/nonexistent/path/file.jpg');
    });

    test('1j: consumePendingIntent returns and clears buffered intent',
        () async {
      const intent = ShareIntent(type: ShareIntentType.text, text: 'test');
      await service.bufferIntent(intent);

      final first = service.consumePendingIntent();
      expect(first, isNotNull);
      expect(first!.text, 'test');

      final second = service.consumePendingIntent();
      expect(second, isNull);
    });

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
  });
}
