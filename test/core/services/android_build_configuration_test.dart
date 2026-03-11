import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android build configuration', () {
    test('declares Firebase Google Services support in Gradle settings', () {
      final settings = File('android/settings.gradle.kts').readAsStringSync();

      expect(settings, contains('com.google.gms.google-services'));
      expect(settings, contains('4.3.15'));
    });

    test('uses a non-template app id and release signing config', () {
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final rootBuild = File('android/build.gradle.kts').readAsStringSync();

      expect(appBuild, contains('applicationId = androidApplicationId'));
      expect(appBuild, contains('"com.mknoon.app"'));
      expect(
        appBuild,
        isNot(contains('applicationId = "com.example.flutter_app"')),
      );
      expect(appBuild, contains('google-services.json'));
      expect(
        appBuild,
        contains(
          'Android release builds require android/app/google-services.json',
        ),
      );
      expect(appBuild, contains('android/key.properties'));
      expect(appBuild, contains('allowDebugSigningInRelease'));
      expect(
        appBuild,
        contains(
          'allowDebugSigningInRelease -> signingConfig = signingConfigs.getByName("debug")',
        ),
      );
      expect(
        appBuild,
        contains('if (!hasReleaseSigning && !allowDebugSigningInRelease)'),
      );
      expect(rootBuild, contains('LibraryExtension'));
      expect(rootBuild, contains('targetCompatibility'));
      expect(rootBuild, contains('tasks.withType<KotlinCompile>()'));
      expect(rootBuild, contains('if (name == "app")'));
    });

    test('root build.gradle forces JVM 11 for all library subprojects', () {
      final rootBuild = File('android/build.gradle.kts').readAsStringSync();

      // All library subprojects must compile Kotlin with JVM target 11
      // to match the app module — prevents JVM-target mismatch errors.
      expect(rootBuild, contains('JavaVersion.VERSION_11'));
      expect(rootBuild, contains('sourceCompatibility = JavaVersion.VERSION_11'));
      expect(rootBuild, contains('targetCompatibility = JavaVersion.VERSION_11'));
      // Should NOT fall back to 1.8 (old default that caused mismatches)
      expect(rootBuild, isNot(contains('VERSION_1_8')));
    });

    test('root build.gradle uses afterEvaluate to override plugin JVM targets',
        () {
      final rootBuild = File('android/build.gradle.kts').readAsStringSync();

      // afterEvaluate ensures our JVM-11 override wins over plugins that
      // hardcode JVM 1.8 in their own build.gradle (e.g. bonsoir_android).
      expect(rootBuild, contains('afterEvaluate'));
    });

    test('Android and iOS use the same application identifier', () {
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      // Extract Android applicationId default
      expect(appBuild, contains('"com.mknoon.app"'));

      // iOS bundle identifiers must match
      expect(pbxproj, contains('PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app'));
    });

    test('iOS app group and share extension follow naming convention', () {
      final runnerEntitlements =
          File('ios/Runner/Runner.entitlements').readAsStringSync();
      final shareEntitlements =
          File('ios/Share Extension/Share Extension.entitlements')
              .readAsStringSync();
      final pbxproj =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      expect(runnerEntitlements, contains('group.com.mknoon.app.share'));
      expect(shareEntitlements, contains('group.com.mknoon.app.share'));
      expect(
        pbxproj,
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = "com.mknoon.app.ShareExtension"',
        ),
      );
    });

    test('main activity and bridge use the mknoon Android package', () {
      final mainActivity = File(
        'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
      );
      final goBridge = File(
        'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt',
      );

      expect(mainActivity.existsSync(), isTrue);
      expect(goBridge.existsSync(), isTrue);
      expect(
        mainActivity.readAsStringSync(),
        contains('package com.mknoon.app'),
      );
      expect(goBridge.readAsStringSync(), contains('package com.mknoon.app'));
    });
  });
}
