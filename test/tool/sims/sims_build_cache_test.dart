import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/build_cache.dart';
import '../../../tool/sims/build_orchestrator.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/report.dart';

BuildProfileInput _input({
  String source = 'source-a',
  String toolchain = 'flutter-a',
  String runtimeScenario = 'scenario-a',
  String profile = 'android.e2e.standard',
  String architecture = 'universal',
  String entrypoint = 'integration_test/sims_dispatcher.dart',
  String appId = 'com.mknoon.app',
  Map<String, String> compileDefines = const <String, String>{
    'E2E_TEST_MODE': 'true',
  },
  List<String> buildOptions = const <String>['--debug'],
}) => BuildProfileInput(
  profileId: profile,
  platform: 'android',
  architecture: architecture,
  entrypoint: entrypoint,
  mode: 'debug',
  flavor: 'default',
  compileDefines: compileDefines,
  appId: appId,
  providerConfigDigests: const <String, String>{},
  signingDigests: const <String, String>{},
  inputFiles: <String, List<int>>{
    'lib/main.dart': utf8.encode(source),
    'pubspec.lock': utf8.encode('lock-a'),
  },
  toolchain: <String, String>{'flutter': toolchain},
  buildOptions: buildOptions,
  runtimeConfig: <String, Object?>{'scenario': runtimeScenario},
);

const _androidProfile = BuildProfileSpec(
  id: 'android.e2e.standard',
  platform: 'android',
  artifactKind: 'universal-debug-apk',
  buildRequired: true,
  compileDefines: <String, String>{},
  declaredException: false,
);

const _iosProfile = BuildProfileSpec(
  id: 'ios.simulator.e2e',
  platform: 'ios',
  artifactKind: 'simulator-runner-app',
  buildRequired: true,
  compileDefines: <String, String>{},
  declaredException: false,
);

void _write(Directory root, String path, String contents) {
  final file = File('${root.path}/$path');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

void main() {
  test('every built profile gets its exact compile-time profile handshake', () {
    final manifest = SimsManifest.loadSync(
      File('tool/sims/critical_features.json'),
    );

    for (final profile in manifest.buildProfiles) {
      final defines = effectiveSimsCompileDefines(
        profile,
        environment: const <String, String>{},
      );
      if (profile.buildRequired) {
        expect(
          defines['SIMS_BUILD_PROFILE_ID'],
          profile.id,
          reason: '${profile.id} must be able to reject a mismatched artifact',
        );
      } else {
        expect(
          defines,
          isNot(contains('SIMS_BUILD_PROFILE_ID')),
          reason: '${profile.id} does not compile an app artifact',
        );
      }
    }

    final wake = manifest.buildProfileById('android.e2e.wake_token')!;
    expect(
      effectiveSimsCompileDefines(
        BuildProfileSpec(
          id: wake.id,
          platform: wake.platform,
          artifactKind: wake.artifactKind,
          buildRequired: wake.buildRequired,
          compileDefines: const <String, String>{
            'SIMS_BUILD_PROFILE_ID': 'wrong-profile',
          },
          declaredException: wake.declaredException,
        ),
        environment: const <String, String>{},
      )['SIMS_BUILD_PROFILE_ID'],
      wake.id,
      reason: 'the reserved handshake cannot be overridden by the manifest',
    );
  });

  test(
    'production-call APK command and cache identity include every native option',
    () {
      final manifest = SimsManifest.loadSync(
        File('tool/sims/critical_features.json'),
      );
      final profile = manifest.buildProfileById(
        'android.e2e.production_call_local',
      )!;
      const relay = '/ip4/127.0.0.1/tcp/4005/p2p/12D3KooWProductionCallFixture';
      const environment = <String, String>{'MKNOON_RELAY_ADDRESSES': relay};
      final defines = effectiveSimsCompileDefines(
        profile,
        environment: environment,
      );
      final arguments = effectiveSimsBuildArguments(
        profile,
        environment: environment,
      );

      expect(arguments, contains('--target-platform=android-arm64'));
      expect(
        arguments,
        contains('--android-project-arg=simsAndroidAbi=arm64-v8a'),
      );
      expect(
        arguments,
        contains('--android-project-arg=enableAndroidNativeCalls=true'),
      );
      expect(
        arguments,
        contains(
          '--android-project-arg=disableGoogleServicesForDisposableProof=true',
        ),
      );
      expect(
        effectiveSimsApplicationId(
          profile,
          environment: const <String, String>{
            'ANDROID_APP_PACKAGE': 'com.mknoon.app',
            'SIMS_APP_ID': 'com.mknoon.app',
            'ORG_GRADLE_PROJECT_androidApplicationId': 'com.mknoon.app',
          },
        ),
        'com.mknoon.sims.productionaudio',
      );
      expect(arguments, contains('--target=lib/main.dart'));
      for (final define in defines.entries) {
        expect(
          arguments,
          contains('--dart-define=${define.key}=${define.value}'),
          reason: '${define.key} must affect the exact Flutter build command',
        );
      }

      BuildProfileInput productionInput({
        Map<String, String>? compileDefines,
        List<String>? buildOptions,
      }) => _input(
        profile: profile.id,
        architecture: 'android-arm64',
        entrypoint: 'lib/main.dart',
        compileDefines: compileDefines ?? defines,
        buildOptions: buildOptions ?? arguments,
      );

      expect(productionInput().inputDigest, productionInput().inputDigest);
      expect(
        productionInput().inputDigest,
        isNot(
          productionInput(
            compileDefines: <String, String>{
              ...defines,
              'VOICE_CALL_TURN_ENABLED': 'false',
            },
          ).inputDigest,
        ),
        reason: 'every effective dart-define belongs to cache identity',
      );
      expect(
        productionInput().inputDigest,
        isNot(
          productionInput(
            buildOptions: arguments
                .where(
                  (argument) =>
                      argument !=
                      '--android-project-arg=enableAndroidNativeCalls=true',
                )
                .toList(growable: false),
          ).inputDigest,
        ),
        reason: 'the native Android project argument belongs to cache identity',
      );
      expect(
        BuildRequestSet.fromProfileIds(<String>[
          profile.id,
          profile.id,
        ]).profileIds,
        <String>[profile.id],
        reason: 'both peers reuse one centrally built arm64 APK',
      );

      for (final offProfileId in const <String>[
        'android.e2e.standard',
        'android.e2e.main',
      ]) {
        final offArguments = effectiveSimsBuildArguments(
          manifest.buildProfileById(offProfileId)!,
          environment: const <String, String>{},
        );
        expect(
          offArguments,
          isNot(
            contains('--android-project-arg=enableAndroidNativeCalls=true'),
          ),
          reason: '$offProfileId must keep the native-call feature off',
        );
        expect(
          offArguments.any(
            (argument) => argument.contains('VOICE_CALL_CAPABILITY_V1'),
          ),
          isFalse,
          reason: '$offProfileId must keep the call capability off',
        );
      }
    },
  );

  test('iOS device cache identity retains native compilation conditions', () {
    final manifest = SimsManifest.loadSync(
      File('tool/sims/critical_features.json'),
    );
    for (final profileAndCondition in const <String, String>{
      'ios.device.production': 'MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP',
      'ios.device.group_media_269': 'MKNOON_SIMS_GROUP_MEDIA_269',
    }.entries) {
      final arguments = effectiveSimsBuildArguments(
        manifest.buildProfileById(profileAndCondition.key)!,
        environment: const <String, String>{},
      );
      expect(
        arguments.where(
          (argument) =>
              argument.startsWith('SWIFT_ACTIVE_COMPILATION_CONDITIONS='),
        ),
        <String>[
          r'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) '
              '${profileAndCondition.value}',
        ],
        reason: 'the native entry point must participate in cache identity',
      );
      expect(arguments, contains('-configuration=Release'));
      expect(arguments.any((argument) => argument.contains('DEBUG')), isFalse);
    }
  });

  test('device E2E artifacts attest only a configured relay boundary', () {
    final manifest = SimsManifest.loadSync(
      File('tool/sims/critical_features.json'),
    );
    const stagingRelays =
        '/dns/staging.example/udp/4002/quic-v1/p2p/12D3KooWFixture';

    for (final profileId in const <String>[
      'android.e2e.main',
      'ios.device.production',
      'ios.device.group_media_269',
    ]) {
      final profile = manifest.buildProfileById(profileId)!;
      final configured = effectiveSimsCompileDefines(
        profile,
        environment: const <String, String>{
          'MKNOON_RELAY_ADDRESSES': stagingRelays,
        },
      );
      expect(
        configured['MKNOON_RELAY_ADDRESSES'],
        stagingRelays,
        reason: '$profileId must be bound to the selected real relay',
      );
      expect(configured['SIMS_BUILD_PROFILE_ID'], profileId);

      final unconfigured = effectiveSimsCompileDefines(
        profile,
        environment: const <String, String>{},
      );
      expect(
        unconfigured,
        isNot(contains('MKNOON_RELAY_ADDRESSES')),
        reason: '$profileId must not embed an absent relay boundary',
      );
      expect(unconfigured['SIMS_BUILD_PROFILE_ID'], profileId);
      expect(
        effectiveSimsCompileDefines(
          profile,
          environment: const <String, String>{'MKNOON_RELAY_ADDRESSES': '   '},
        ),
        isNot(contains('MKNOON_RELAY_ADDRESSES')),
      );
    }

    final groupMediaIos = manifest.buildProfileById(
      'ios.device.group_media_269',
    )!;
    expect(
      effectiveSimsApplicationId(
        groupMediaIos,
        environment: const <String, String>{
          'SIMS_APP_ID': 'com.example.must-not-override',
        },
      ),
      'com.mknoon.sims.groupmedia269',
    );
  });

  test(
    'relay dart-defines stay private in deterministic cache attestations',
    () {
      const relayA =
          '/dns/staging-a.example/udp/4002/quic-v1/p2p/12D3KooWRelayA';
      const relayB =
          '/dns/staging-b.example/udp/4002/quic-v1/p2p/12D3KooWRelayB';
      const commandPrefix = <String>['flutter', 'build', 'apk', '--debug'];

      List<String> redacted(String relay) =>
          redactSimsBuildCommandForAttestation(<String>[
            ...commandPrefix,
            '--dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.main',
            '--dart-define=MKNOON_RELAY_ADDRESSES=$relay',
          ]);

      final redactedA = redacted(relayA);
      expect(redactedA, redacted(relayA));
      expect(redactedA, isNot(redacted(relayB)));
      expect(redactedA.join(' '), isNot(contains(relayA)));
      expect(
        redactedA.singleWhere(
          (value) => value.contains('MKNOON_RELAY_ADDRESSES'),
        ),
        matches(
          RegExp(
            r'^--dart-define=MKNOON_RELAY_ADDRESSES='
            r'<sha256:[a-f0-9]{64}>$',
          ),
        ),
      );
      expect(
        redactedA.singleWhere((value) => value.contains('SIMS_BUILD_PROFILE')),
        isNot(contains('android.e2e.main')),
        reason: 'all compile-time values are private by default',
      );
      final encodedDefines = base64.encode(
        utf8.encode('MKNOON_RELAY_ADDRESSES=$relayA'),
      );
      final redactedEncoded = redactSimsBuildCommandForAttestation(<String>[
        'xcodebuild',
        'DART_DEFINES=$encodedDefines',
      ]);
      expect(redactedEncoded.join(' '), isNot(contains(encodedDefines)));
      expect(
        redactedEncoded.last,
        matches(RegExp(r'^DART_DEFINES=<sha256:[a-f0-9]{64}>$')),
      );

      final inputA = _input(
        profile: 'android.e2e.main',
        compileDefines: const <String, String>{
          'SIMS_BUILD_PROFILE_ID': 'android.e2e.main',
          'MKNOON_RELAY_ADDRESSES': relayA,
        },
      );
      final repeatedInputA = _input(
        profile: 'android.e2e.main',
        compileDefines: const <String, String>{
          'SIMS_BUILD_PROFILE_ID': 'android.e2e.main',
          'MKNOON_RELAY_ADDRESSES': relayA,
        },
      );
      final inputB = _input(
        profile: 'android.e2e.main',
        compileDefines: const <String, String>{
          'SIMS_BUILD_PROFILE_ID': 'android.e2e.main',
          'MKNOON_RELAY_ADDRESSES': relayB,
        },
      );
      expect(inputA.inputDigest, repeatedInputA.inputDigest);
      expect(inputA.inputDigest, isNot(inputB.inputDigest));

      final artifactBytes = utf8.encode('relay-boundary-apk');
      final attestation = BuildAttestation.create(
        input: inputA,
        artifactBytes: artifactBytes,
        artifactPath: '/cache/android.e2e.main/app.apk',
        redactedCommand: redactedA,
        createdAt: DateTime.utc(2026, 7, 19),
      );
      final encoded = jsonEncode(attestation.toJson());
      expect(encoded, isNot(contains(relayA)));
      expect(encoded, contains('MKNOON_RELAY_ADDRESSES'));
      expect(
        BuildCacheVerifier.verify(inputA, attestation, artifactBytes).isHit,
        isTrue,
      );
      expect(
        BuildCacheVerifier.verify(inputB, attestation, artifactBytes).isHit,
        isFalse,
      );
    },
  );

  test('build and whole-suite source closures are intentionally separated', () {
    expect(
      simsBuildSourceRoots,
      containsAll(const <String>[
        'integration_test',
        'android',
        'ios',
        'packages/background_push_crypto',
        'third_party/bonsoir_darwin',
      ]),
    );
    expect(simsSuiteSourceRoots, containsAll(simsBuildSourceRoots));
    expect(
      simsSuiteSourceRoots,
      containsAll(const <String>[
        'test',
        'scripts',
        'tool/sims',
        'go-mknoon',
        'go-relay-server',
      ]),
    );
    expect(simsBuildSourceRoots, isNot(contains('test')));
    expect(simsBuildSourceRoots, isNot(contains('tool/sims')));
    expect(simsSharedFlutterBuildSourceRoots, contains('assets'));
    expect(simsAndroidBuildSourceRoots, contains('android'));
    expect(simsAndroidBuildSourceRoots, isNot(contains('ios')));
    expect(
      simsIosBuildSourceRoots,
      containsAll(<String>['ios', 'third_party/bonsoir_darwin']),
    );
    expect(simsIosBuildSourceRoots, isNot(contains('android')));
  });

  test(
    'profile source closure isolates native platforms and follows the actual entrypoint',
    () {
      final root = Directory.systemTemp.createTempSync('sims-profile-source-');
      addTearDown(() => root.deleteSync(recursive: true));
      _write(
        root,
        'pubspec.yaml',
        'name: flutter_app\n'
            'flutter:\n'
            '  assets:\n'
            '    - integration_test/fixtures/declared.jpg\n',
      );
      _write(root, 'pubspec.lock', 'packages: {}\n');
      _write(root, 'l10n.yaml', 'arb-dir: lib/l10n\n');
      _write(root, 'lib/l10n/app_en.arb', '{"hello":"Hello"}\n');
      _write(
        root,
        'lib/l10n/app_localizations.dart',
        'const generatedGreeting = "Hello";\n',
      );
      _write(root, 'lib/shared.dart', 'const shared = 1;\n');
      _write(
        root,
        '.dart_tool/package_config.json',
        jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{
              'name': 'flutter_app',
              'rootUri': '../',
              'packageUri': 'lib/',
            },
            <String, Object?>{
              'name': 'local_shared',
              'rootUri': '../packages/local_shared',
              'packageUri': 'lib/',
            },
          ],
        }),
      );
      _write(
        root,
        'packages/local_shared/lib/local_shared.dart',
        'const localShared = 1;\n',
      );
      _write(root, 'android/native.txt', 'android-a\n');
      _write(root, 'ios/native.txt', 'ios-a\n');
      _write(root, 'third_party/bonsoir_darwin/native.txt', 'darwin-a\n');
      _write(root, 'go-mknoon/bridge/bridge.go', 'package bridge\n');
      _write(root, 'go-mknoon/bridge/bridge_test.go', 'package bridge\n');
      _write(root, 'go-mknoon/testdata/vector.json', '{"test":1}\n');
      _write(root, 'go-mknoon/go.mod', 'module example.test/app\n');
      _write(root, 'go-mknoon/go.sum', 'sum-a\n');
      _write(root, 'go-mknoon/Makefile', 'android:\n\t@true\n');
      _write(
        root,
        'packages/background_push_crypto/pubspec.yaml',
        'name: background_push_crypto\n',
      );
      _write(root, 'scripts/ensure_go_android_bindings.sh', 'android-a\n');
      _write(root, 'scripts/ensure_go_ios_bindings.sh', 'ios-a\n');
      _write(root, 'scripts/gomobile_binding_inputs.sh', 'inputs-a\n');
      _write(root, 'scripts/verify_gomobile_bindings.sh', 'verify-a\n');
      _write(root, 'integration_test/fixtures/declared.jpg', 'declared-a\n');
      _write(
        root,
        'integration_test/fixtures/not-declared.jpg',
        'unrelated-a\n',
      );
      _write(root, 'android/app/libs/GoMknoon.aar', 'generated-a\n');
      _write(root, 'android/app/libs/GoMknoon.inputs.sha256', '${'a' * 64}\n');
      _write(
        root,
        'ios/Runner/GoMknoon.xcframework/Info.plist',
        'generated-a\n',
      );
      _write(root, 'ios/Runner/GoMknoon.inputs.sha256', '${'a' * 64}\n');
      _write(root, 'android/key.properties', 'password=secret-a\n');
      _write(
        root,
        'ios/Runner.xcodeproj/xcuserdata/user.xcuserdatad/state.xcuserstate',
        'generated-a\n',
      );
      _write(
        root,
        'integration_test/android_entry.dart',
        "import 'package:flutter_app/shared.dart';\n"
            "import 'package:flutter_app/l10n/app_localizations.dart';\n"
            "import 'package:local_shared/local_shared.dart';\n"
            "import 'support/android_support.dart';\n",
      );
      _write(
        root,
        'integration_test/support/android_support.dart',
        'const support = 1;\n',
      );
      _write(
        root,
        'integration_test/ios_entry.dart',
        "import 'package:flutter_app/shared.dart';\n"
            "import 'package:flutter_app/l10n/app_localizations.dart';\n"
            "import 'package:local_shared/local_shared.dart';\n",
      );
      _write(
        root,
        'integration_test/unrelated_ios_only.dart',
        'const unrelated = 1;\n',
      );

      String androidDigest() => computeSimsBuildProfileSourceClosureDigest(
        profile: _androidProfile,
        entrypoint: 'integration_test/android_entry.dart',
        projectDirectory: root,
      );
      String iosDigest() => computeSimsBuildProfileSourceClosureDigest(
        profile: _iosProfile,
        entrypoint: 'integration_test/ios_entry.dart',
        projectDirectory: root,
      );

      final initialAndroid = androidDigest();
      final initialIos = iosDigest();

      _write(root, 'ios/native.txt', 'ios-b\n');
      expect(androidDigest(), initialAndroid);
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'ios/native.txt', 'ios-a\n');

      _write(root, 'android/native.txt', 'android-b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), initialIos);
      _write(root, 'android/native.txt', 'android-a\n');

      _write(root, 'lib/shared.dart', 'const shared = 2;\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'lib/shared.dart', 'const shared = 1;\n');

      _write(
        root,
        'packages/local_shared/lib/local_shared.dart',
        'const localShared = 2;\n',
      );
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(
        root,
        'packages/local_shared/lib/local_shared.dart',
        'const localShared = 1;\n',
      );

      _write(
        root,
        'integration_test/support/android_support.dart',
        'const support = 2;\n',
      );
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), initialIos);
      _write(
        root,
        'integration_test/support/android_support.dart',
        'const support = 1;\n',
      );

      _write(
        root,
        'integration_test/unrelated_ios_only.dart',
        'const unrelated = 2;\n',
      );
      expect(androidDigest(), initialAndroid);
      expect(iosDigest(), initialIos);

      _write(root, 'go-mknoon/bridge/bridge.go', 'package bridge // b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'go-mknoon/bridge/bridge.go', 'package bridge\n');

      _write(root, 'scripts/ensure_go_android_bindings.sh', 'android-b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), initialIos);
      _write(root, 'scripts/ensure_go_android_bindings.sh', 'android-a\n');

      _write(root, 'scripts/ensure_go_ios_bindings.sh', 'ios-b\n');
      expect(androidDigest(), initialAndroid);
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'scripts/ensure_go_ios_bindings.sh', 'ios-a\n');

      _write(root, 'scripts/gomobile_binding_inputs.sh', 'inputs-b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'scripts/gomobile_binding_inputs.sh', 'inputs-a\n');

      _write(root, 'scripts/verify_gomobile_bindings.sh', 'verify-b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'scripts/verify_gomobile_bindings.sh', 'verify-a\n');

      _write(root, 'go-mknoon/Makefile', 'android:\n\t@echo changed\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'go-mknoon/Makefile', 'android:\n\t@true\n');

      _write(root, 'go-mknoon/go.mod', 'module example.test/changed\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'go-mknoon/go.mod', 'module example.test/app\n');

      _write(
        root,
        'packages/background_push_crypto/pubspec.yaml',
        'name: background_push_crypto_changed\n',
      );
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), initialIos);
      _write(
        root,
        'packages/background_push_crypto/pubspec.yaml',
        'name: background_push_crypto\n',
      );

      _write(root, 'lib/l10n/app_en.arb', '{"hello":"Hallo"}\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'lib/l10n/app_en.arb', '{"hello":"Hello"}\n');

      _write(root, 'integration_test/fixtures/declared.jpg', 'declared-b\n');
      expect(androidDigest(), isNot(initialAndroid));
      expect(iosDigest(), isNot(initialIos));
      _write(root, 'integration_test/fixtures/declared.jpg', 'declared-a\n');

      for (final ignoredMutation in <(String, String)>[
        ('go-mknoon/bridge/bridge_test.go', 'package bridge // b\n'),
        ('go-mknoon/testdata/vector.json', '{"test":2}\n'),
        ('go-mknoon/.gocache/cache.go', 'package cache\n'),
        ('integration_test/fixtures/not-declared.jpg', 'unrelated-b\n'),
        (
          'lib/l10n/app_localizations.dart',
          'const generatedGreeting = "Regenerated";\n',
        ),
        ('android/app/libs/GoMknoon.aar', 'generated-b\n'),
        ('android/app/libs/GoMknoon.inputs.sha256', '${'b' * 64}\n'),
        ('android/app/libs/GoMknoon.inputs.sha256.tmp', '${'c' * 64}\n'),
        ('ios/Runner/GoMknoon.xcframework/Info.plist', 'generated-b\n'),
        ('ios/Runner/GoMknoon.inputs.sha256', '${'b' * 64}\n'),
        ('ios/Runner/GoMknoon.inputs.sha256.tmp', '${'c' * 64}\n'),
        ('android/key.properties', 'password=secret-b\n'),
        (
          'ios/Runner.xcodeproj/xcuserdata/user.xcuserdatad/state.xcuserstate',
          'generated-b\n',
        ),
      ]) {
        _write(root, ignoredMutation.$1, ignoredMutation.$2);
        expect(
          androidDigest(),
          initialAndroid,
          reason: '${ignoredMutation.$1} must not churn the Android cache',
        );
        expect(
          iosDigest(),
          initialIos,
          reason: '${ignoredMutation.$1} must not churn the iOS cache',
        );
      }
    },
  );

  test(
    'effective Android app ID is canonical but local paths stay private',
    () {
      final root = Directory.systemTemp.createTempSync('sims-app-id-');
      addTearDown(() => root.deleteSync(recursive: true));
      _write(
        root,
        'android/local.properties',
        'sdk.dir=/private/android-sdk\n'
            'flutter.sdk=/private/flutter\n'
            'android.applicationId=org.example.local\n',
      );

      expect(
        effectiveSimsApplicationId(
          _androidProfile,
          environment: const <String, String>{},
          projectDirectory: root,
        ),
        'org.example.local',
      );
      expect(
        effectiveSimsApplicationId(
          _androidProfile,
          environment: const <String, String>{
            'ORG_GRADLE_PROJECT_androidApplicationId': 'org.example.gradle',
          },
          projectDirectory: root,
        ),
        'org.example.gradle',
      );
      expect(
        effectiveSimsApplicationId(
          _androidProfile,
          environment: const <String, String>{
            'SIMS_APP_ID': 'org.example.sims',
            'ORG_GRADLE_PROJECT_androidApplicationId': 'org.example.gradle',
          },
          projectDirectory: root,
        ),
        'org.example.sims',
      );
      expect(
        _input(appId: 'org.example.local').inputDigest,
        isNot(_input(appId: 'org.example.changed').inputDigest),
      );
    },
  );

  test('Android NDK identity tracks selected revisions without raw paths', () {
    final root = Directory.systemTemp.createTempSync('sims-ndk-');
    addTearDown(() => root.deleteSync(recursive: true));
    final sdk = Directory('${root.path}/private-sdk');
    _write(
      sdk,
      'ndk/28.2.13676358/source.properties',
      'Pkg.Revision = 28.2.13676358\n',
    );
    _write(sdk, 'ndk/29.0.1/source.properties', 'Pkg.Revision = 29.0.1\n');

    Map<String, String> identity() => computeSimsAndroidNdkIdentity(
      projectDirectory: root,
      environment: <String, String>{'ANDROID_HOME': sdk.path},
      flutterNdkVersionOverride: '28.2.13676358',
    );

    final initial = identity();
    expect(initial.keys, <String>{'ndk.flutter', 'ndk.gomobile'});
    expect(initial.values.join(), isNot(contains(root.path)));
    _write(
      sdk,
      'ndk/28.2.13676358/source.properties',
      'Pkg.Revision = 28.2.13676358-hotfix\n',
    );
    expect(identity()['ndk.flutter'], isNot(initial['ndk.flutter']));
    expect(identity()['ndk.gomobile'], initial['ndk.gomobile']);
    _write(sdk, 'ndk/29.0.1/source.properties', 'Pkg.Revision = 29.0.2\n');
    expect(identity()['ndk.gomobile'], isNot(initial['ndk.gomobile']));
  });

  test('compatible rows request and build one profile once', () {
    final requests = BuildRequestSet.fromProfileIds(const <String>[
      'android.e2e.standard',
      'android.e2e.standard',
      'android.production_fcm',
    ]);
    expect(requests.profileIds, <String>[
      'android.e2e.standard',
      'android.production_fcm',
    ]);
  });

  test(
    'runtime config changes hit while content toolchain and profile mutations miss',
    () {
      expect(
        _input(runtimeScenario: 'a').inputDigest,
        _input(runtimeScenario: 'b').inputDigest,
      );
      expect(
        _input(source: 'a').inputDigest,
        isNot(_input(source: 'b').inputDigest),
      );
      expect(
        _input(toolchain: 'a').inputDigest,
        isNot(_input(toolchain: 'b').inputDigest),
      );
      expect(
        _input(profile: 'android.e2e.standard').inputDigest,
        isNot(_input(profile: 'android.e2e.wake_token').inputDigest),
      );
    },
  );

  test('corrupt or unattested artifact fails closed', () {
    final input = _input();
    final artifact = utf8.encode('apk-v1');
    final attestation = BuildAttestation.create(
      input: input,
      artifactBytes: artifact,
      artifactPath: '/cache/app.apk',
      redactedCommand: const <String>['flutter', 'build', 'apk'],
      createdAt: DateTime.utc(2026, 7, 14),
    );

    expect(
      BuildCacheVerifier.verify(input, attestation, artifact).isHit,
      isTrue,
    );
    expect(
      BuildCacheVerifier.verify(
        input,
        attestation,
        utf8.encode('corrupt'),
      ).isHit,
      isFalse,
    );
    expect(BuildCacheVerifier.verify(input, null, artifact).isHit, isFalse);
  });

  test(
    'build report has hits misses hashes invalidations and no secret values',
    () {
      final report = SimsBuildReport(
        requestedProfiles: 3,
        actualBuilds: 1,
        hits: 2,
        misses: 1,
        invalidations: const <String>['wrong-source'],
        artifactDigests: const <String, String>{
          'android.e2e.standard':
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        },
        declaredExceptions: const <String>['android.e2e.wake_token'],
        builtProfileIds: const <String>['android.e2e.standard'],
        cacheHitProfileIds: const <String>[
          'android.production_fcm',
          'android.e2e.wake_token',
        ],
        profileElapsedMs: const <String, int>{
          'android.e2e.standard': 82000,
          'android.production_fcm': 15,
          'android.e2e.wake_token': 12,
        },
        totalElapsedMs: 82150,
      );
      final encoded = jsonEncode(report.toJson());
      expect(encoded, contains('wrong-source'));
      expect(encoded, contains('android.e2e.wake_token'));
      expect(encoded, contains('builtProfileIds'));
      expect(encoded, contains('profileElapsedMs'));
      expect(encoded, contains('82000'));
      expect(encoded, isNot(contains('super-secret-token')));
    },
  );
}
