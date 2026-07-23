import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/ios_xctestrun_relocator.dart';

void main() {
  test('relocates macros and stale DerivedData paths into cached products', () {
    final root = Directory.systemTemp.createTempSync('xctestrun-cache-');
    addTearDown(() => root.deleteSync(recursive: true));
    final originalDerived = Directory('${root.path}/original-derived')
      ..createSync(recursive: true);
    final cachedProducts = Directory('${root.path}/cache/TestProducts')
      ..createSync(recursive: true);
    final app = Directory('${cachedProducts.path}/Release-iphoneos/Runner.app')
      ..createSync(recursive: true);
    File('${app.path}/Runner').writeAsStringSync('signed-runner');
    final testBundle = File(
      '${cachedProducts.path}/Release-iphoneos/'
      'RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest/RunnerUITests',
    )..createSync(recursive: true);
    testBundle.writeAsStringSync('test-binary');
    final framework = File(
      '${cachedProducts.path}/Release-iphoneos/Runner.app/'
      'Frameworks/XCTest.framework/XCTest',
    )..createSync(recursive: true);
    framework.writeAsStringSync('framework');

    final oldProducts = '${originalDerived.path}/Build/Products';
    final relocation = relocateIosXctestrun(
      plist: <String, Object?>{
        'RunnerUITests': <String, Object?>{
          'TestBundlePath':
              '__TESTROOT__/Release-iphoneos/'
              'RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest',
          'UITargetAppPath': '$oldProducts/Release-iphoneos/Runner.app',
          'DependentProductPaths': <String>[
            '$oldProducts/Release-iphoneos/Runner.app/'
                'Frameworks/XCTest.framework/XCTest',
          ],
          'EnvironmentVariables': <String, Object?>{'EXISTING': 'kept'},
        },
      },
      cachedProducts: cachedProducts,
      cachedApplication: app,
      uiEnvironment: const <String, String>{'FIXTURE': 'redacted'},
    );
    originalDerived.deleteSync(recursive: true);

    expect(relocation.uiTargetsPatched, 1);
    expect(relocation.productPathsPatched, 3);
    final encoded = jsonEncode(relocation.plist);
    expect(encoded, isNot(contains('__TESTROOT__')));
    expect(encoded, isNot(contains(originalDerived.path)));
    final target = relocation.plist['RunnerUITests']! as Map;
    expect(target['UITargetAppPath'], app.path);
    expect(target['UITargetAppBundleIdentifier'], 'com.mknoon.app');
    expect((target['EnvironmentVariables']! as Map)['EXISTING'], 'kept');
    expect((target['EnvironmentVariables']! as Map)['FIXTURE'], 'redacted');
    expect(
      File(
        (target['DependentProductPaths']! as List).single as String,
      ).existsSync(),
      isTrue,
    );
    expect(Directory(target['TestBundlePath']! as String).existsSync(), isTrue);
  });

  test('plans only test-without-building against explicit cached target', () {
    final arguments = iosTestWithoutBuildingArguments(
      xctestrun: File('/cache/RunnerUITests.patched.xctestrun'),
      receiverDeviceId: '00008150-001C3C6A3684401C',
      selector: 'testPayloadFastPathNotificationTap',
      resultBundle: Directory('/capture/payload.xcresult'),
    );
    expect(arguments.first, 'test-without-building');
    expect(arguments, contains('platform=iOS,id=00008150-001C3C6A3684401C'));
    expect(
      arguments,
      contains(
        '-only-testing:RunnerUITests/NotificationTapUITests/'
        'testPayloadFastPathNotificationTap',
      ),
    );
    expect(arguments, isNot(contains('build-for-testing')));
    expect(arguments, isNot(contains('build')));
  });

  test(
    'P269 test without building accepts validated group media selector and preserves notification default',
    () {
      final dedicatedRelocation = relocateIosXctestrun(
        plist: <String, Object?>{
          'RunnerUITests': <String, Object?>{
            'TestBundlePath':
                '__TESTROOT__/Release-iphoneos/'
                'RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest',
          },
        },
        cachedProducts: Directory('/cache/TestProducts'),
        cachedApplication: Directory(
          '/cache/TestProducts/Release-iphoneos/Runner.app',
        ),
        uiTargetBundleIdentifier: 'com.mknoon.sims.groupmedia269',
        uiEnvironment: const <String, String>{},
      );
      expect(
        (dedicatedRelocation.plist['RunnerUITests']!
            as Map)['UITargetAppBundleIdentifier'],
        'com.mknoon.sims.groupmedia269',
      );

      final groupMediaArguments = iosTestWithoutBuildingArguments(
        xctestrun: File('/cache/RunnerUITests.patched.xctestrun'),
        receiverDeviceId: '00008030-001A6D2801BB802E',
        selector:
            'RunnerUITests/GroupMediaBackgroundRecoveryUITests/'
            'testReceiverBackgroundRecovery',
        resultBundle: Directory('/capture/group-media.xcresult'),
      );
      expect(
        groupMediaArguments,
        contains(
          '-only-testing:RunnerUITests/'
          'GroupMediaBackgroundRecoveryUITests/'
          'testReceiverBackgroundRecovery',
        ),
      );
      expect(groupMediaArguments.first, 'test-without-building');
      expect(groupMediaArguments, isNot(contains('build-for-testing')));

      final notificationArguments = iosTestWithoutBuildingArguments(
        xctestrun: File('/cache/RunnerUITests.patched.xctestrun'),
        receiverDeviceId: '00008030-001A6D2801BB802E',
        selector: 'testPayloadFastPathNotificationTap',
        resultBundle: Directory('/capture/notification.xcresult'),
      );
      expect(
        notificationArguments,
        contains(
          '-only-testing:RunnerUITests/NotificationTapUITests/'
          'testPayloadFastPathNotificationTap',
        ),
      );

      for (final unsafe in const <String>[
        'RunnerUITests/../testEscape',
        'RunnerUITests/GroupMediaBackgroundRecoveryUITests',
        'OtherTests/GroupMediaBackgroundRecoveryUITests/testRecovery',
        'RunnerUITests/Group Media Tests/testRecovery',
        '-only-testing:RunnerUITests/GroupMediaTests/testRecovery',
      ]) {
        expect(
          () => validatedIosUiTestSelector(unsafe),
          throwsFormatException,
          reason: unsafe,
        );
      }
      expect(
        () => relocateIosXctestrun(
          plist: const <String, Object?>{},
          cachedProducts: Directory('/cache/TestProducts'),
          cachedApplication: Directory('/cache/Runner.app'),
          uiTargetBundleIdentifier: '../production',
          uiEnvironment: const <String, String>{},
        ),
        throwsFormatException,
      );
    },
  );
}
