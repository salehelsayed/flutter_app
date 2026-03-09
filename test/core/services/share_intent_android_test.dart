import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  group('Android share target configuration', () {
    test('manifest declares singleTask launch mode and share intent filters', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:launchMode="singleTask"'));
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>',
        ),
      );
      expect(manifest, contains('android.intent.action.SEND'));
      expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
      expect(manifest, contains('android:mimeType="text/plain"'));
      expect(manifest, contains('android:mimeType="image/*"'));
      expect(manifest, contains('android:mimeType="video/*"'));
    });
  });

  group('Android share intent conversion', () {
    test('3a: parses ACTION_SEND text/plain payload', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: 'Shared from Chrome',
            type: SharedMediaType.text,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.text);
      expect(intent.text, 'Shared from Chrome');
      expect(intent.filePaths, isEmpty);
    });

    test('3b: parses ACTION_SEND image payload', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: '/tmp/android-photo.jpg',
            type: SharedMediaType.image,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.files);
      expect(intent.filePaths, ['/tmp/android-photo.jpg']);
    });

    test('3c: parses ACTION_SEND video payload', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: '/tmp/android-video.mp4',
            type: SharedMediaType.video,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.files);
      expect(intent.filePaths, ['/tmp/android-video.mp4']);
    });

    test('3d: parses ACTION_SEND_MULTIPLE image payload', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: '/tmp/photo-1.jpg',
            type: SharedMediaType.image,
          ),
          SharedMediaFile(
            path: '/tmp/photo-2.jpg',
            type: SharedMediaType.image,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.files);
      expect(intent.filePaths, ['/tmp/photo-1.jpg', '/tmp/photo-2.jpg']);
    });

    test('3e: parses mixed text plus image payload', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => [
          SharedMediaFile(
            path: 'https://example.com/post',
            type: SharedMediaType.url,
          ),
          SharedMediaFile(
            path: '/tmp/preview.jpg',
            type: SharedMediaType.image,
          ),
        ],
        resetShareIntent: () {},
      );

      final intent = await service.getInitialIntent();

      expect(intent, isNotNull);
      expect(intent!.type, ShareIntentType.mixed);
      expect(intent.text, 'https://example.com/post');
      expect(intent.filePaths, ['/tmp/preview.jpg']);
    });

    test('3f: ignores unsupported or empty payloads', () async {
      final service = ShareIntentService(
        getInitialMedia: () async => const [],
        resetShareIntent: () {},
      );

      expect(await service.getInitialIntent(), isNull);
    });
  });
}
