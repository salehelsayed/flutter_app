import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/_android_app_package.dart';

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
}
