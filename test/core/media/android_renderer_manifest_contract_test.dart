import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const enableImpellerKey = 'io.flutter.embedding.android.EnableImpeller';
  const impellerBackendKey = 'io.flutter.embedding.android.ImpellerBackend';

  test(
    'Android renderer fallback is application scoped and preserves media/PiP',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final application = RegExp(
        r'<application\b[\s\S]*</application>',
      ).firstMatch(manifest)?.group(0);

      expect(application, isNotNull);
      final impellerDeclarations = RegExp(
        '<meta-data\\s+[^>]*android:name="$enableImpellerKey"[^>]*/>',
        multiLine: true,
      ).allMatches(application!).toList();
      expect(
        impellerDeclarations,
        hasLength(1),
        reason: 'FlutterLoader reads this key from application metadata.',
      );
      expect(
        impellerDeclarations.single.group(0),
        contains('android:value="false"'),
      );
      expect(
        application,
        isNot(contains(impellerBackendKey)),
        reason:
            'Flutter 3.41 release builds ignore backend selection; leaving an '
            'OpenGLES backend hint would give false release confidence.',
      );

      final mainActivity = RegExp(
        r'<activity\s+[^>]*android:name="\.MainActivity"[^>]*>',
        dotAll: true,
      ).firstMatch(application)?.group(0);
      expect(mainActivity, contains('android:hardwareAccelerated="true"'));

      final pipActivity = RegExp(
        r'<activity\s+[^>]*android:name="\.ReceivedVideoPictureInPictureActivity"[^>]*/>',
        dotAll: true,
      ).firstMatch(application)?.group(0);
      expect(pipActivity, contains('android:hardwareAccelerated="true"'));
      expect(pipActivity, contains('android:supportsPictureInPicture="true"'));
      expect(pipActivity, contains('android:resizeableActivity="true"'));

      expect(application, contains('android:mimeType="image/*"'));
      expect(application, contains('android:mimeType="video/*"'));
      expect(application, contains('.ReceivedMediaEgressProvider'));
      expect(application, contains('android:grantUriPermissions="true"'));
    },
  );

  test('profile manifest does not override the production renderer policy', () {
    final profileManifest = File(
      'android/app/src/profile/AndroidManifest.xml',
    ).readAsStringSync();
    expect(profileManifest, isNot(contains(enableImpellerKey)));
    expect(profileManifest, isNot(contains(impellerBackendKey)));
  });
}
