import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/_android_app_package.dart';
import '../../tool/sims/build_orchestrator.dart';
import '../../tool/sims/manifest.dart';

const _androidBuildProfile = BuildProfileSpec(
  id: 'android.e2e.main',
  platform: 'android',
  artifactKind: 'universal-debug-apk',
  buildRequired: true,
  compileDefines: <String, String>{},
  declaredException: false,
);

void main() {
  test('accepts only dotted Android Java identifier packages', () {
    for (final value in <String>[
      'com.mknoon.app',
      'de.example_2.client3',
      'A.b',
    ]) {
      expect(isValidAndroidAppPackage(value), isTrue, reason: value);
    }
  });

  test('malicious package overrides fail instead of reaching adb', () {
    for (final value in <String>[
      '-com.mknoon.app',
      'com.mknoon.app --user 0',
      'com.mknoon.app;rm',
      'com.mknoon.app|id',
      'com.mknoon/app',
      'com..app',
      '.com.mknoon',
      'com.mknoon.',
      'com',
      ' com.mknoon.app',
      'com.mknoon.app ',
      'com.mknoon.\napp',
      'com.mknoon.app\n',
      r'com.mknoon.$app',
      'com.mknoon.-app',
      'com.mknoon._app',
    ]) {
      expect(
        () => resolveAndroidAppPackageFromSources(
          environmentValue: value,
          localPropertyLines: const <String>[
            'android.applicationId=com.safe.fallback',
          ],
        ),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('parsed local applicationId is validated and empty is fail closed', () {
    expect(
      resolveAndroidAppPackageFromSources(
        environmentValue: null,
        localPropertyLines: const <String>[
          'sdk.dir=/tmp/android',
          ' android.applicationId=org.example.client ',
        ],
      ),
      'org.example.client',
    );
    for (final line in <String>[
      'android.applicationId=',
      'android.applicationId=org.example.app --user 0',
      'android.applicationId=org..example',
    ]) {
      expect(
        () => resolveAndroidAppPackageFromSources(
          environmentValue: null,
          localPropertyLines: <String>[line],
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'empty override falls through to validated local or default package',
    () {
      expect(
        resolveAndroidAppPackageFromSources(
          environmentValue: '',
          localPropertyLines: const <String>[
            'android.applicationId=org.example.client',
          ],
        ),
        'org.example.client',
      );
      expect(
        resolveAndroidAppPackageFromSources(
          environmentValue: null,
          localPropertyLines: null,
        ),
        'com.mknoon.app',
      );
    },
  );

  test(
    'runtime and central build share exact package precedence and parsing',
    () {
      final root = Directory.systemTemp.createTempSync('android-app-parity-');
      addTearDown(() => root.deleteSync(recursive: true));
      final localProperties = File('${root.path}/android/local.properties');
      localProperties.parent.createSync(recursive: true);

      final cases =
          <
            ({
              String name,
              Map<String, String> environment,
              String? localProperty,
              String expected,
            })
          >[
            (
              name: 'ANDROID_APP_PACKAGE',
              environment: const <String, String>{
                'ANDROID_APP_PACKAGE': 'org.explicit.app',
                'SIMS_APP_ID': 'org.sims.app',
                'ORG_GRADLE_PROJECT_androidApplicationId': 'org.gradle.app',
              },
              localProperty: 'android.applicationId=org.local.app',
              expected: 'org.explicit.app',
            ),
            (
              name: 'SIMS_APP_ID',
              environment: const <String, String>{
                'SIMS_APP_ID': 'org.sims.app',
                'ORG_GRADLE_PROJECT_androidApplicationId': 'org.gradle.app',
              },
              localProperty: 'android.applicationId=org.local.app',
              expected: 'org.sims.app',
            ),
            (
              name: 'Gradle project override',
              environment: const <String, String>{
                'ORG_GRADLE_PROJECT_androidApplicationId': 'org.gradle.app',
              },
              localProperty: 'android.applicationId=org.local.app',
              expected: 'org.gradle.app',
            ),
            (
              name: 'whitespace-separated local property',
              environment: const <String, String>{},
              localProperty: '  android.applicationId   org.local.space',
              expected: 'org.local.space',
            ),
            (
              name: 'colon-separated local property',
              environment: const <String, String>{},
              localProperty: 'android.applicationId : org.local.colon',
              expected: 'org.local.colon',
            ),
            (
              name: 'equals-separated local property',
              environment: const <String, String>{},
              localProperty: 'android.applicationId=org.local.equal',
              expected: 'org.local.equal',
            ),
            (
              name: 'default',
              environment: const <String, String>{},
              localProperty: null,
              expected: 'com.mknoon.app',
            ),
          ];

      for (final testCase in cases) {
        if (testCase.localProperty case final value?) {
          localProperties.writeAsStringSync('$value\n');
        } else if (localProperties.existsSync()) {
          localProperties.deleteSync();
        }
        final runtime = resolveAndroidAppPackageFromSources(
          environmentValue: testCase.environment['ANDROID_APP_PACKAGE'],
          simsApplicationId: testCase.environment['SIMS_APP_ID'],
          gradleApplicationId:
              testCase.environment['ORG_GRADLE_PROJECT_androidApplicationId'],
          localPropertyLines: testCase.localProperty == null
              ? null
              : <String>[testCase.localProperty!],
        );
        final central = effectiveSimsApplicationId(
          _androidBuildProfile,
          environment: testCase.environment,
          projectDirectory: root,
        );
        expect(runtime, testCase.expected, reason: testCase.name);
        expect(
          central,
          runtime,
          reason: '${testCase.name} must stay in parity',
        );
      }
    },
  );

  test('runtime and central build reject the same invalid source values', () {
    final root = Directory.systemTemp.createTempSync('android-app-invalid-');
    addTearDown(() => root.deleteSync(recursive: true));
    final localProperties = File('${root.path}/android/local.properties');
    localProperties.parent.createSync(recursive: true);

    final cases =
        <
          ({String name, Map<String, String> environment, String localProperty})
        >[
          (
            name: 'ANDROID_APP_PACKAGE',
            environment: const <String, String>{
              'ANDROID_APP_PACKAGE': 'org.explicit.app --user 0',
              'SIMS_APP_ID': 'org.safe.sims',
            },
            localProperty: 'android.applicationId=org.safe.local',
          ),
          (
            name: 'SIMS_APP_ID',
            environment: const <String, String>{
              'SIMS_APP_ID': 'org.sims.app;id',
              'ORG_GRADLE_PROJECT_androidApplicationId': 'org.safe.gradle',
            },
            localProperty: 'android.applicationId=org.safe.local',
          ),
          (
            name: 'Gradle project override',
            environment: const <String, String>{
              'ORG_GRADLE_PROJECT_androidApplicationId': 'org.gradle/app',
            },
            localProperty: 'android.applicationId=org.safe.local',
          ),
          (
            name: 'whitespace-separated local property',
            environment: const <String, String>{},
            localProperty: 'android.applicationId org..invalid',
          ),
          (
            name: 'colon-separated local property',
            environment: const <String, String>{},
            localProperty: 'android.applicationId:org.invalid;id',
          ),
          (
            name: 'equals-separated local property',
            environment: const <String, String>{},
            localProperty: 'android.applicationId=org.invalid --user 0',
          ),
        ];

    for (final testCase in cases) {
      localProperties.writeAsStringSync('${testCase.localProperty}\n');
      expect(
        () => resolveAndroidAppPackageFromSources(
          environmentValue: testCase.environment['ANDROID_APP_PACKAGE'],
          simsApplicationId: testCase.environment['SIMS_APP_ID'],
          gradleApplicationId:
              testCase.environment['ORG_GRADLE_PROJECT_androidApplicationId'],
          localPropertyLines: <String>[testCase.localProperty],
        ),
        throwsFormatException,
        reason: 'runtime ${testCase.name}',
      );
      expect(
        () => effectiveSimsApplicationId(
          _androidBuildProfile,
          environment: testCase.environment,
          projectDirectory: root,
        ),
        throwsFormatException,
        reason: 'central ${testCase.name}',
      );
    }
  });
}
