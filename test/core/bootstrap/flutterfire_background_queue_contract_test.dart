import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pinned FlutterFire background callbacks use one unbounded serial queue',
    () {
      final packageConfigFile = File('.dart_tool/package_config.json');
      expect(packageConfigFile.existsSync(), isTrue);
      final packageConfig =
          jsonDecode(packageConfigFile.readAsStringSync())
              as Map<String, dynamic>;
      final packages = packageConfig['packages'] as List<dynamic>;
      final messagingPackage = packages
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['name'] == 'firebase_messaging');
      final packageRootUri = packageConfigFile.uri.resolve(
        messagingPackage['rootUri'] as String,
      );
      final packageRoot = Directory.fromUri(packageRootUri);

      expect(
        packageRoot.path.replaceAll('\\', '/'),
        endsWith('/firebase_messaging-15.2.10'),
      );
      final lock = File('pubspec.lock').readAsStringSync();
      expect(
        lock,
        matches(
          RegExp(
            r'firebase_messaging:\s*\n'
            r'\s+dependency: "direct main"[\s\S]*?'
            r'\s+version: "15\.2\.10"',
          ),
        ),
      );

      final androidSource = Directory(
        '${packageRoot.path}/android/src/main/java/'
        'io/flutter/plugins/firebase/messaging',
      );
      final service = File(
        '${androidSource.path}/FlutterFirebaseMessagingBackgroundService.java',
      ).readAsStringSync();
      final jobIntentService = File(
        '${androidSource.path}/JobIntentService.java',
      ).readAsStringSync();

      expect(
        service,
        contains('final CountDownLatch latch = new CountDownLatch(1);'),
      );
      expect(
        service,
        contains('executeDartCallbackInBackgroundIsolate(intent, latch)'),
      );
      expect(service, contains('latch.await();'));
      expect(
        service,
        isNot(matches(RegExp(r'latch\.await\s*\([^)]'))),
        reason: 'the pinned callback wait has no timeout argument',
      );
      expect(
        jobIntentService,
        contains(
          'private final Executor executor = '
          'Executors.newSingleThreadExecutor();',
        ),
      );
      expect(jobIntentService, contains('executor.execute('));
      expect(jobIntentService, contains('onHandleWork(work.getIntent());'));
    },
  );
}
