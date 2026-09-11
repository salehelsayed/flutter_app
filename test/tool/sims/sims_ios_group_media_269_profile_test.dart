import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/group_media_ios_background_e2e.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_orchestrator.dart';
import '../../../tool/sims/build_cache.dart';
import '../../../tool/sims/manifest.dart';

int _occurrences(String source, String value) =>
    RegExp(RegExp.escape(value)).allMatches(source).length;

final class _IosBuildProductsFixture {
  _IosBuildProductsFixture._({
    required this.root,
    required this.products,
    required this.runnerInfo,
    required this.uiHostExecutable,
    required this.uiTestBundle,
  });

  final Directory root;
  final Directory products;
  final File runnerInfo;
  final File uiHostExecutable;
  final Directory uiTestBundle;

  static _IosBuildProductsFixture create(String label) {
    final root = Directory.systemTemp.createTempSync('sims-ios-$label-');
    final products = Directory('${root.path}/Build/Products')
      ..createSync(recursive: true);
    final application = Directory(
      '${products.path}/Release-iphoneos/Runner.app',
    )..createSync(recursive: true);
    final runnerInfo = _writeFixtureFile(
      '${application.path}/Info.plist',
      'runner-info',
    );
    _writeFixtureExecutable('${application.path}/Runner', 'runner');

    final share = Directory('${application.path}/PlugIns/Share Extension.appex')
      ..createSync(recursive: true);
    _writeFixtureFile('${share.path}/Info.plist', 'share-info');
    _writeFixtureExecutable('${share.path}/Share Extension', 'share');

    final notification = Directory(
      '${application.path}/PlugIns/NotificationService.appex',
    )..createSync(recursive: true);
    _writeFixtureFile('${notification.path}/Info.plist', 'notification-info');
    _writeFixtureExecutable(
      '${notification.path}/NotificationService',
      'notification',
    );

    final embeddedFramework = Directory(
      '${application.path}/Frameworks/Fixture.framework',
    )..createSync(recursive: true);
    _writeFixtureFile('${embeddedFramework.path}/Info.plist', 'framework-info');
    _writeFixtureExecutable('${embeddedFramework.path}/Fixture', 'framework');

    final uiHost = Directory(
      '${products.path}/Release-iphoneos/RunnerUITests-Runner.app',
    )..createSync(recursive: true);
    _writeFixtureFile('${uiHost.path}/Info.plist', 'ui-host-info');
    final uiHostExecutable = _writeFixtureExecutable(
      '${uiHost.path}/RunnerUITests-Runner',
      'ui-host',
    );
    final uiTestBundle = Directory(
      '${uiHost.path}/PlugIns/RunnerUITests.xctest',
    )..createSync(recursive: true);
    _writeFixtureFile('${uiTestBundle.path}/Info.plist', 'ui-test-info');
    _writeFixtureExecutable('${uiTestBundle.path}/RunnerUITests', 'ui-test');
    _writeFixtureFile(
      '${products.path}/Runner_iphoneos.xctestrun',
      'xctestrun',
    );
    return _IosBuildProductsFixture._(
      root: root,
      products: products,
      runnerInfo: runnerInfo,
      uiHostExecutable: uiHostExecutable,
      uiTestBundle: uiTestBundle,
    );
  }
}

File _writeFixtureFile(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$contents\n', flush: true);
  return file;
}

File _writeFixtureExecutable(String path, String contents) {
  final file = _writeFixtureFile(path, contents);
  if (!Platform.isWindows) {
    final chmod = Process.runSync('chmod', <String>['755', file.path]);
    if (chmod.exitCode != 0) {
      throw StateError('Unable to make fixture executable: ${file.path}');
    }
  }
  return file;
}

BuildProfileInput _iosCacheInput(
  String profileId,
  Map<String, List<int>> inputFiles,
) => BuildProfileInput(
  profileId: profileId,
  platform: 'ios',
  architecture: 'arm64',
  entrypoint: 'lib/main.dart',
  mode: 'release',
  flavor: 'default',
  compileDefines: const <String, String>{},
  appId: '$profileId.fixture',
  providerConfigDigests: const <String, String>{},
  signingDigests: const <String, String>{'identity': 'fixture'},
  inputFiles: inputFiles,
  toolchain: const <String, String>{'xcode': 'fixture'},
  buildOptions: const <String>['build-for-testing'],
  runtimeConfig: const <String, Object?>{},
);

void main() {
  test(
    'TC-269 physical iOS fixture driver is directly host executable',
    () async {
      if (Platform.isWindows) return;
      final result = await Process.run(
        'integration_test/scripts/group_media_ios_fixture_driver.dart',
        const <String>['--host-probe'],
        runInShell: false,
      );

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stderr}', isEmpty);
      final value = (jsonDecode('${result.stdout}'.trim()) as Map)
          .cast<String, Object?>();
      expect(value.keys.toSet(), <String>{
        'schema',
        'status',
        'containsSecrets',
      });
      expect(value, <String, Object?>{
        'schema': 'mknoon.group-media-ios-fixture-host-probe.v1',
        'status': 'PASS',
        'containsSecrets': false,
      });

      final source = File(
        'integration_test/scripts/group_media_ios_fixture_driver.dart',
      ).readAsStringSync();
      expect(
        source,
        contains(r"final destination = File('${directory.path}/$name');"),
      );
      expect(source, contains("'--destination',\n        destination.path,"));
      expect(
        source,
        isNot(contains("'--destination',\n        directory.path,")),
      );
    },
  );

  test(
    'TC-269 Android profile hard-pins package build flags and artifact environment',
    () {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final profile = manifest.buildProfileById(
        groupMediaAndroidDisposableBuildProfile,
      )!;
      final project = Directory.systemTemp.createTempSync(
        'p269-android-profile-',
      );
      addTearDown(() => project.deleteSync(recursive: true));
      final localProperties = File('${project.path}/android/local.properties');
      localProperties.parent.createSync(recursive: true);
      localProperties.writeAsStringSync(
        'android.applicationId=com.example.local-override\n',
      );

      expect(
        effectiveSimsApplicationId(
          profile,
          environment: const <String, String>{
            'ANDROID_APP_PACKAGE': 'com.example.android-override',
            'SIMS_APP_ID': 'com.example.sims-override',
            'ORG_GRADLE_PROJECT_androidApplicationId':
                'com.example.gradle-override',
          },
          projectDirectory: project,
        ),
        groupMediaAndroidDisposablePackageId,
      );

      final mechanicallyDerivedEnvironment =
          'SIMS_ARTIFACT_${profile.id.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '_')}';
      expect(
        mechanicallyDerivedEnvironment,
        groupMediaAndroidDisposableArtifactEnvironment,
      );
      expect(
        groupMediaIosAndroidSenderBuildProfile,
        groupMediaAndroidDisposableBuildProfile,
      );

      final arguments = effectiveSimsBuildArguments(
        profile,
        environment: const <String, String>{},
      );
      for (final flag in <String>[
        '--android-project-arg=disableGoogleServicesForDisposableProof=true',
        '--android-project-arg=enableGroupMedia269DisposableProof=true',
      ]) {
        expect(arguments.where((argument) => argument == flag), hasLength(1));
      }
      final fcmArguments = effectiveSimsBuildArguments(
        manifest.buildProfileById('android.production_fcm')!,
        environment: const <String, String>{},
      );
      expect(
        fcmArguments,
        isNot(
          contains(
            '--android-project-arg=disableGoogleServicesForDisposableProof=true',
          ),
        ),
        reason: 'Disposable audio/group flags must not disable provider proof',
      );

      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        gradle,
        contains('androidApplicationId != "com.mknoon.sims.groupmedia269"'),
      );
      expect(gradle, contains('!disableGoogleServicesForDisposableProof'));
      expect(
        gradle,
        contains(
          'enableGroupMedia269DisposableProof must be exactly true or false.',
        ),
      );
    },
  );

  test(
    'central iOS builder validates the complete app XCTest extension and nested-signature graph',
    () async {
      final fixture = _IosBuildProductsFixture.create('complete-products');
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final calls = <(String, List<String>)>[];

      final validation = await validateSimsIosDeviceBuildProducts(
        products: fixture.products,
        environment: const <String, String>{'PATH': '/fixture/bin'},
        codesignRunner: (executable, arguments, environment) async {
          calls.add((executable, List<String>.of(arguments)));
          expect(environment['PATH'], '/fixture/bin');
          return ProcessResult(269, 0, '', '');
        },
      );

      expect(validation.ok, isTrue, reason: validation.detail);
      expect(validation.relativeApplication, 'Release-iphoneos/Runner.app');
      expect(validation.xctestrun!.path, endsWith('Runner_iphoneos.xctestrun'));
      expect(
        validation.verifiedCodePaths.map(
          (path) => path.split(Platform.pathSeparator).last,
        ),
        containsAll(<String>[
          'Runner.app',
          'Share Extension.appex',
          'NotificationService.appex',
          'RunnerUITests-Runner.app',
          'RunnerUITests.xctest',
          'Fixture.framework',
        ]),
      );
      expect(calls, hasLength(6));
      for (final call in calls) {
        expect(call.$1, 'codesign');
        expect(call.$2.take(3), const <String>[
          '--verify',
          '--deep',
          '--strict',
        ]);
        expect(Directory(call.$2.last).existsSync(), isTrue);
      }
    },
  );

  test(
    'central iOS builder rejects missing plist executable and non-unique xctestrun before codesign',
    () async {
      for (final fault in <String>[
        'missing-plist',
        'missing-executable',
        if (!Platform.isWindows) 'non-executable',
        'second-xctestrun',
      ]) {
        final fixture = _IosBuildProductsFixture.create(fault);
        addTearDown(() => fixture.root.deleteSync(recursive: true));
        switch (fault) {
          case 'missing-plist':
            fixture.runnerInfo.deleteSync();
          case 'missing-executable':
            fixture.uiHostExecutable.deleteSync();
          case 'non-executable':
            final chmod = Process.runSync('chmod', <String>[
              '644',
              fixture.uiHostExecutable.path,
            ]);
            expect(chmod.exitCode, 0, reason: '$fault fixture chmod');
          case 'second-xctestrun':
            _writeFixtureFile(
              '${fixture.products.path}/Second.xctestrun',
              'second',
            );
        }
        var codesignCalls = 0;

        final validation = await validateSimsIosDeviceBuildProducts(
          products: fixture.products,
          codesignRunner: (executable, arguments, environment) async {
            codesignCalls++;
            return ProcessResult(269, 0, '', '');
          },
        );

        expect(validation.ok, isFalse, reason: fault);
        expect(validation.detail, isNotEmpty, reason: fault);
        expect(codesignCalls, 0, reason: fault);
      }
    },
  );

  test(
    'physical-iOS validator schema makes legacy partial attestations miss both cache profiles',
    () {
      final orchestrator = File(
        'tool/sims/build_orchestrator.dart',
      ).readAsStringSync();
      expect(
        orchestrator,
        contains('...simsIosDeviceProductValidatorInputFiles(profile.id),'),
      );
      final legacyArtifact = utf8.encode('attested legacy partial iOS bundle');

      for (final profileId in const <String>[
        'ios.device.production',
        'ios.device.group_media_269',
      ]) {
        final legacyInput = _iosCacheInput(
          profileId,
          const <String, List<int>>{},
        );
        final currentFiles = simsIosDeviceProductValidatorInputFiles(profileId);
        expect(currentFiles.keys, <String>[
          simsIosDeviceProductValidatorInputName,
        ]);
        expect(
          utf8.decode(currentFiles[simsIosDeviceProductValidatorInputName]!),
          simsIosDeviceProductValidatorSchema,
        );
        final currentInput = _iosCacheInput(profileId, currentFiles);
        final legacyAttestation = BuildAttestation.create(
          input: legacyInput,
          artifactBytes: legacyArtifact,
          artifactPath: '/fixture/legacy-partial.bundle',
          redactedCommand: const <String>['xcodebuild', 'build-for-testing'],
          createdAt: DateTime.utc(2026, 7, 22),
        );

        expect(currentInput.inputDigest, isNot(legacyInput.inputDigest));
        final verification = BuildCacheVerifier.verify(
          currentInput,
          legacyAttestation,
          legacyArtifact,
        );
        expect(verification.isHit, isFalse, reason: profileId);
        expect(
          verification.reason,
          BuildCacheMissReason.wrongInput,
          reason: profileId,
        );
      }
      expect(
        simsIosDeviceProductValidatorInputFiles('android.production'),
        isEmpty,
      );
    },
  );

  test(
    'central iOS builder rejects an invalid nested XCTest signature',
    () async {
      final fixture = _IosBuildProductsFixture.create('invalid-signature');
      addTearDown(() => fixture.root.deleteSync(recursive: true));
      final checked = <String>[];

      final validation = await validateSimsIosDeviceBuildProducts(
        products: fixture.products,
        codesignRunner: (executable, arguments, environment) async {
          checked.add(arguments.last);
          final invalid = arguments.last == fixture.uiTestBundle.absolute.path;
          return ProcessResult(
            269,
            invalid ? 1 : 0,
            '',
            invalid ? 'fixture signature rejected' : '',
          );
        },
      );

      expect(validation.ok, isFalse);
      expect(validation.detail, contains('codesign verification failed'));
      expect(validation.detail, contains('RunnerUITests.xctest'));
      expect(checked, contains(fixture.uiTestBundle.absolute.path));
    },
  );

  test('TC-269 dedicated iOS compilation omits receiver bootstrap', () {
    final orchestrator = File(
      'tool/sims/build_orchestrator.dart',
    ).readAsStringSync();
    final dedicatedStart = orchestrator.indexOf(
      'const _iosDeviceGroupMedia269Build',
    );
    final dedicatedEnd = orchestrator.indexOf(
      '_IosDeviceBuildConfiguration? _iosDeviceBuildConfiguration',
    );
    expect(dedicatedStart, greaterThanOrEqualTo(0));
    expect(dedicatedEnd, greaterThan(dedicatedStart));
    final dedicated = orchestrator.substring(dedicatedStart, dedicatedEnd);
    expect(dedicated, contains('MKNOON_SIMS_GROUP_MEDIA_269'));
    expect(dedicated, isNot(contains('MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP')));

    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(
      _occurrences(
        appDelegate,
        '#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP || '
        'MKNOON_SIMS_GROUP_MEDIA_269',
      ),
      2,
      reason: 'only process-launch and Home markers widen to the P269 build',
    );
    final launch = appDelegate.substring(
      appDelegate.indexOf('override func application('),
      appDelegate.indexOf('installNotificationCenterDelegate('),
    );
    expect(
      launch,
      contains(
        '#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP\n'
        '    iosReceiverBootstrapHandoff.prepareContainer()\n'
        '#endif\n'
        '#if MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP || '
        'MKNOON_SIMS_GROUP_MEDIA_269',
      ),
    );
  });

  test(
    'TC-269 dedicated profile contract is registered in group and typed sims lanes',
    () {
      const path = 'test/tool/sims/sims_ios_group_media_269_profile_test.dart';
      final gate = File('scripts/run_test_gates.sh').readAsStringSync();
      final gateContract = File(
        'scripts/test/sims_test_gate_contract_test.sh',
      ).readAsStringSync();
      expect(_occurrences(gate, path), 2);
      expect(_occurrences(gateContract, path), 1);
    },
  );

  test('TC-269 Xcode target bundle IDs keep production defaults indirect', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    const settings = <String, String>{
      'MKNOON_RUNNER_BUNDLE_IDENTIFIER': 'com.mknoon.app',
      'MKNOON_RUNNER_TESTS_BUNDLE_IDENTIFIER': 'com.mknoon.app.RunnerTests',
      'MKNOON_RUNNER_UI_TESTS_BUNDLE_IDENTIFIER':
          'com.mknoon.app.RunnerUITests',
      'MKNOON_SHARE_EXTENSION_BUNDLE_IDENTIFIER':
          'com.mknoon.app.ShareExtension',
      'MKNOON_NOTIFICATION_SERVICE_BUNDLE_IDENTIFIER':
          'com.mknoon.app.NotificationService',
    };

    for (final entry in settings.entries) {
      expect(
        _occurrences(project, '${entry.key} = ${entry.value};'),
        3,
        reason: '${entry.key} needs one production default per Xcode config',
      );
      expect(
        _occurrences(
          project,
          'PRODUCT_BUNDLE_IDENTIFIER = "\$(${entry.key})";',
        ),
        3,
        reason: 'every ${entry.key} target config must use its indirection',
      );
    }

    expect(
      project,
      isNot(contains('PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app;')),
    );
    expect(
      project,
      isNot(
        contains(
          'PRODUCT_BUNDLE_IDENTIFIER = com.mknoon.app.NotificationService;',
        ),
      ),
    );
  });

  test(
    'TC-269 Xcode targets select dedicated empty entitlements without changing production defaults',
    () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      const productionEntitlements = <String, String>{
        'MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS': 'Runner/Runner.entitlements',
        'MKNOON_SHARE_EXTENSION_CODE_SIGN_ENTITLEMENTS':
            '"Share Extension/Share Extension.entitlements"',
        'MKNOON_NOTIFICATION_SERVICE_CODE_SIGN_ENTITLEMENTS':
            'NotificationService/NotificationService.entitlements',
      };

      for (final entry in productionEntitlements.entries) {
        expect(
          _occurrences(project, 'CODE_SIGN_ENTITLEMENTS = "\$(${entry.key})";'),
          3,
          reason: '${entry.key} must select entitlements in every Xcode config',
        );
        expect(
          _occurrences(project, '${entry.key} = ${entry.value};'),
          3,
          reason: '${entry.key} must retain its production default',
        );
      }
      expect(
        _occurrences(
          project,
          r'CODE_SIGN_ENTITLEMENTS = "$(MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS)";',
        ),
        3,
      );
      expect(
        _occurrences(
          project,
          'MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS = "";',
        ),
        3,
        reason: 'production UI tests must retain their no-entitlements default',
      );

      final orchestrator = File(
        'tool/sims/build_orchestrator.dart',
      ).readAsStringSync();
      final dedicatedStart = orchestrator.indexOf(
        'const _iosDeviceGroupMedia269Build',
      );
      final dedicatedEnd = orchestrator.indexOf(
        '_IosDeviceBuildConfiguration? _iosDeviceBuildConfiguration',
      );
      final dedicated = orchestrator.substring(dedicatedStart, dedicatedEnd);
      for (final setting in <String>[
        ...productionEntitlements.keys,
        'MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS',
      ]) {
        expect(_occurrences(dedicated, setting), 1);
      }
      expect(
        _occurrences(dedicated, 'Runner/GroupMedia269.empty.entitlements'),
        4,
      );
      expect(
        dedicated,
        isNot(contains("'CODE_SIGN_ENTITLEMENTS='")),
        reason: 'the profile must not rely on a global Xcode override',
      );

      final emptyEntitlements = File(
        'ios/Runner/GroupMedia269.empty.entitlements',
      ).readAsStringSync();
      expect(emptyEntitlements, contains('<dict/>'));
      for (final forbidden in <String>[
        'aps-environment',
        'com.apple.security.application-groups',
        'keychain-access-groups',
        'group.com.mknoon.app.share',
      ]) {
        expect(emptyEntitlements, isNot(contains(forbidden)));
      }
    },
  );

  test('TC-269 native compilation cannot use production shared containers', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final appGroupHandler = appDelegate.substring(
      appDelegate.indexOf('private func setupAppGroupPathBridge'),
      appDelegate.indexOf('private func handleDiskSpaceMethodCall'),
    );
    expect(appGroupHandler, contains('#if MKNOON_SIMS_GROUP_MEDIA_269'));
    expect(
      appGroupHandler.indexOf('#if MKNOON_SIMS_GROUP_MEDIA_269'),
      lessThan(appGroupHandler.indexOf('group.com.mknoon.app.share')),
    );
    expect(
      appGroupHandler,
      contains('shared app-group access is disabled for this build'),
    );

    final resolver = File(
      'ios/NotificationService/NotificationPreviewResolver.swift',
    ).readAsStringSync();
    expect(resolver, contains('#if MKNOON_SIMS_GROUP_MEDIA_269'));
    expect(resolver, contains('group.com.mknoon.sims.groupmedia269.share'));
    expect(
      resolver,
      contains('397R9Q4WMX.group.com.mknoon.sims.groupmedia269.share'),
    );

    final shareInfo = File('ios/Share Extension/Info.plist').readAsStringSync();
    expect(shareInfo, contains(r'<string>$(CUSTOM_GROUP_ID)</string>'));
  });
}
