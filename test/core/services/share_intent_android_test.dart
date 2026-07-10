import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  test(
    'manifest preserves inbound filters and pins capped legacy storage plus restricted provider',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:launchMode="singleTask"'));
      expect(
        RegExp(r'android.intent.action.SEND"').allMatches(manifest).length,
        greaterThanOrEqualTo(4),
      );
      expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
      expect(
        manifest,
        contains(
          'android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="28"',
        ),
      );
      expect(
        manifest,
        contains(
          'android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"',
        ),
      );
      expect(manifest, contains('android:name=".ReceivedMediaEgressProvider"'));
      expect(manifest, contains('android:exported="false"'));
      expect(manifest, contains('android:grantUriPermissions="true"'));
      expect(manifest, isNot(contains('android.support.FILE_PROVIDER_PATHS')));
      final provider = File(
        'android/app/src/main/kotlin/com/mknoon/app/ReceivedMediaEgressProvider.kt',
      ).readAsStringSync();
      expect(
        provider,
        contains('class ReceivedMediaEgressProvider : ContentProvider()'),
      );
      expect(
        provider,
        contains(
          'context.getDir("flutter", Context.MODE_PRIVATE).absoluteFile',
        ),
      );
      expect(provider, contains('"media", "local_media", "post_media"'));
      expect(
        provider,
        contains(
          'canonical.path == canonicalLiteral.path && canonical.isDirectory',
        ),
      );
      expect(
        provider,
        contains(r'authority("${context.packageName}.received-media")'),
      );
      expect(provider, contains('if (mode != "r")'));
      expect(provider, contains('ParcelFileDescriptor.MODE_READ_ONLY'));
      expect(provider, isNot(contains('PathUtils.getDataDirectory')));
      expect(provider, isNot(contains('root-path')));
      expect(manifest, isNot(contains('FLAG_GRANT_WRITE_URI_PERMISSION')));
    },
  );

  group('Android share target configuration', () {
    test('manifest declares singleTask launch mode and share intent filters', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:launchMode="singleTask"'));
      expect(
        manifest,
        contains(
          '<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>',
        ),
      );
      expect(manifest, contains('android.intent.action.SEND'));
      expect(manifest, contains('android.intent.action.SEND_MULTIPLE'));
      expect(manifest, contains('android:mimeType="text/plain"'));
      expect(manifest, contains('android:mimeType="image/*"'));
      expect(manifest, contains('android:mimeType="video/*"'));
      expect(manifest, contains('android:mimeType="*/*"'));
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
