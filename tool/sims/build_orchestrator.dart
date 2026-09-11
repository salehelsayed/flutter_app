import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'android_app_package.dart';
import 'build_cache.dart';
import 'manifest.dart';
import 'planner.dart';
import 'report.dart';

const String _iosDeviceProductionProfileId = 'ios.device.production';
const String _iosDeviceGroupMedia269ProfileId = 'ios.device.group_media_269';
const String _iosDeviceGroupMedia269BundleId = 'com.mknoon.sims.groupmedia269';
const String _androidProductionAudioCallProfileId =
    'android.e2e.production_call_local';
const String _androidProductionAudioCallApplicationId =
    'com.mknoon.sims.productionaudio';
const String _androidGroupMedia269ProfileId = 'android.e2e.group_media_269';
const String _androidGroupMedia269ApplicationId =
    'com.mknoon.sims.groupmedia269';
const String simsIosDeviceProductValidatorInputName =
    'ios-device-product-validator.schema';
const String simsIosDeviceProductValidatorSchema =
    'mknoon.sims.ios-device-product-validator.v1';

final class _IosDeviceBuildConfiguration {
  const _IosDeviceBuildConfiguration({
    required this.derivedDataEnvironment,
    required this.defaultDerivedDataPath,
    required this.bundlePathEnvironment,
    required this.defaultBundlePath,
    required this.bundleManifestSchema,
    required this.cachedBundleName,
    required this.swiftCompilationConditions,
    this.allowProvisioningUpdates = false,
    this.buildSettings = const <String>[],
  });

  final String derivedDataEnvironment;
  final String defaultDerivedDataPath;
  final String bundlePathEnvironment;
  final String defaultBundlePath;
  final String bundleManifestSchema;
  final String cachedBundleName;
  final String swiftCompilationConditions;
  final bool allowProvisioningUpdates;
  final List<String> buildSettings;
}

const _iosDeviceProductionBuild = _IosDeviceBuildConfiguration(
  derivedDataEnvironment: 'SIMS_IOS_DEVICE_PRODUCTION_DERIVED_DATA',
  defaultDerivedDataPath: 'build/sims/ios-device-production-derived',
  bundlePathEnvironment: 'SIMS_IOS_DEVICE_PRODUCTION_BUNDLE_PATH',
  defaultBundlePath: 'build/sims/prepared/ios.device.production.bundle',
  bundleManifestSchema: 'mknoon.sims.ios-device-production-bundle.v1',
  cachedBundleName: 'ios.device.production.bundle',
  swiftCompilationConditions:
      r'$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP',
);

const _iosDeviceGroupMedia269Build = _IosDeviceBuildConfiguration(
  derivedDataEnvironment: 'SIMS_IOS_DEVICE_GROUP_MEDIA_269_DERIVED_DATA',
  defaultDerivedDataPath: 'build/sims/ios-device-group-media-269-derived',
  bundlePathEnvironment: 'SIMS_IOS_DEVICE_GROUP_MEDIA_269_BUNDLE_PATH',
  defaultBundlePath: 'build/sims/prepared/ios.device.group_media_269.bundle',
  bundleManifestSchema: 'mknoon.sims.ios-device-group-media-269-bundle.v1',
  cachedBundleName: 'ios.device.group_media_269.bundle',
  swiftCompilationConditions: r'$(inherited) MKNOON_SIMS_GROUP_MEDIA_269',
  allowProvisioningUpdates: true,
  buildSettings: <String>[
    'CODE_SIGN_STYLE=Automatic',
    'PROVISIONING_PROFILE=',
    'PROVISIONING_PROFILE_SPECIFIER=',
    'MKNOON_RUNNER_CODE_SIGN_ENTITLEMENTS='
        'Runner/GroupMedia269.empty.entitlements',
    'MKNOON_RUNNER_UI_TESTS_CODE_SIGN_ENTITLEMENTS='
        'Runner/GroupMedia269.empty.entitlements',
    'MKNOON_SHARE_EXTENSION_CODE_SIGN_ENTITLEMENTS='
        'Runner/GroupMedia269.empty.entitlements',
    'MKNOON_NOTIFICATION_SERVICE_CODE_SIGN_ENTITLEMENTS='
        'Runner/GroupMedia269.empty.entitlements',
    'CUSTOM_GROUP_ID=group.com.mknoon.sims.groupmedia269.share',
    'MKNOON_RUNNER_BUNDLE_IDENTIFIER=com.mknoon.sims.groupmedia269',
    'MKNOON_RUNNER_TESTS_BUNDLE_IDENTIFIER='
        'com.mknoon.sims.groupmedia269.RunnerTests',
    'MKNOON_RUNNER_UI_TESTS_BUNDLE_IDENTIFIER='
        'com.mknoon.sims.groupmedia269.RunnerUITests',
    'MKNOON_SHARE_EXTENSION_BUNDLE_IDENTIFIER='
        'com.mknoon.sims.groupmedia269.ShareExtension',
    'MKNOON_NOTIFICATION_SERVICE_BUNDLE_IDENTIFIER='
        'com.mknoon.sims.groupmedia269.NotificationService',
  ],
);

_IosDeviceBuildConfiguration? _iosDeviceBuildConfiguration(String profileId) =>
    switch (profileId) {
      _iosDeviceProductionProfileId => _iosDeviceProductionBuild,
      _iosDeviceGroupMedia269ProfileId => _iosDeviceGroupMedia269Build,
      _ => null,
    };

/// Deterministically invalidates physical-iOS cache entries whenever the
/// central product graph/signature contract changes.
Map<String, List<int>> simsIosDeviceProductValidatorInputFiles(
  String profileId,
) => _iosDeviceBuildConfiguration(profileId) == null
    ? const <String, List<int>>{}
    : <String, List<int>>{
        simsIosDeviceProductValidatorInputName: utf8.encode(
          simsIosDeviceProductValidatorSchema,
        ),
      };

typedef SimsIosCodesignRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      Map<String, String> environment,
    );

/// Result of validating the exact physical-iOS app/XCTest product graph that
/// the prepared-bundle consumer resolves later.
final class SimsIosDeviceBuildProductsValidation {
  const SimsIosDeviceBuildProductsValidation._({
    required this.ok,
    required this.detail,
    required this.application,
    required this.xctestrun,
    required this.relativeApplication,
    required this.uiTestHost,
    required this.uiTestBundle,
    required this.verifiedCodePaths,
  });

  factory SimsIosDeviceBuildProductsValidation.failure(String detail) =>
      SimsIosDeviceBuildProductsValidation._(
        ok: false,
        detail: detail,
        application: null,
        xctestrun: null,
        relativeApplication: null,
        uiTestHost: null,
        uiTestBundle: null,
        verifiedCodePaths: const <String>[],
      );

  factory SimsIosDeviceBuildProductsValidation.success({
    required Directory application,
    required File xctestrun,
    required String relativeApplication,
    required Directory uiTestHost,
    required Directory uiTestBundle,
    required List<String> verifiedCodePaths,
  }) => SimsIosDeviceBuildProductsValidation._(
    ok: true,
    detail: '',
    application: application,
    xctestrun: xctestrun,
    relativeApplication: relativeApplication,
    uiTestHost: uiTestHost,
    uiTestBundle: uiTestBundle,
    verifiedCodePaths: List<String>.unmodifiable(verifiedCodePaths),
  );

  final bool ok;
  final String detail;
  final Directory? application;
  final File? xctestrun;
  final String? relativeApplication;
  final Directory? uiTestHost;
  final Directory? uiTestBundle;
  final List<String> verifiedCodePaths;
}

/// Fails closed unless [products] contains the complete signed app/UI-test
/// graph consumed by `_PreparedIosBundle.resolve`.
///
/// The validation is intentionally public so the central-builder contract can
/// exercise real filesystem negatives without invoking a second Xcode build.
Future<SimsIosDeviceBuildProductsValidation>
validateSimsIosDeviceBuildProducts({
  required Directory products,
  Map<String, String>? environment,
  SimsIosCodesignRunner? codesignRunner,
}) async {
  final productRoot = products.absolute;
  if (!_realDirectory(productRoot)) {
    return SimsIosDeviceBuildProductsValidation.failure(
      'Central iOS UI-rig build did not materialize a real Build/Products '
      'directory.',
    );
  }
  final entries = productRoot.listSync(recursive: true, followLinks: false);
  final xctestruns =
      entries
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.xctestrun') && _nonEmptyRegularFile(file),
          )
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  if (xctestruns.length != 1) {
    return SimsIosDeviceBuildProductsValidation.failure(
      'Central iOS UI-rig build requires exactly one non-empty .xctestrun; '
      'found ${xctestruns.length}.',
    );
  }
  final applications =
      entries
          .whereType<Directory>()
          .where(
            (directory) =>
                _realDirectory(directory) &&
                _lastPathComponent(directory.path) == 'Runner.app',
          )
          .toList(growable: false)
        ..sort((left, right) => left.path.compareTo(right.path));
  if (applications.length != 1) {
    return SimsIosDeviceBuildProductsValidation.failure(
      'Central iOS build-for-testing requires exactly one real Runner.app; '
      'found ${applications.length}.',
    );
  }

  final application = applications.single;
  final uiTestHost = Directory(
    '${productRoot.path}${Platform.pathSeparator}Release-iphoneos'
    '${Platform.pathSeparator}RunnerUITests-Runner.app',
  );
  final uiTestBundle = Directory(
    '${uiTestHost.path}${Platform.pathSeparator}PlugIns'
    '${Platform.pathSeparator}RunnerUITests.xctest',
  );
  final shareExtension = Directory(
    '${application.path}${Platform.pathSeparator}PlugIns'
    '${Platform.pathSeparator}Share Extension.appex',
  );
  final notificationService = Directory(
    '${application.path}${Platform.pathSeparator}PlugIns'
    '${Platform.pathSeparator}NotificationService.appex',
  );
  for (final requiredDirectory in <(String, Directory)>[
    ('RunnerUITests host app', uiTestHost),
    ('RunnerUITests bundle', uiTestBundle),
    ('Share Extension', shareExtension),
    ('NotificationService', notificationService),
  ]) {
    if (!_realDirectory(requiredDirectory.$2)) {
      return SimsIosDeviceBuildProductsValidation.failure(
        'Central iOS build products are missing the required '
        '${requiredDirectory.$1} directory.',
      );
    }
  }

  for (final requiredFile in <(String, File, bool)>[
    (
      'Runner.app/Info.plist',
      File('${application.path}${Platform.pathSeparator}Info.plist'),
      false,
    ),
    (
      'Runner.app/Runner executable',
      File('${application.path}${Platform.pathSeparator}Runner'),
      true,
    ),
    (
      'RunnerUITests host Info.plist',
      File('${uiTestHost.path}${Platform.pathSeparator}Info.plist'),
      false,
    ),
    (
      'RunnerUITests host executable',
      File('${uiTestHost.path}${Platform.pathSeparator}RunnerUITests-Runner'),
      true,
    ),
    (
      'RunnerUITests bundle Info.plist',
      File('${uiTestBundle.path}${Platform.pathSeparator}Info.plist'),
      false,
    ),
    (
      'RunnerUITests bundle executable',
      File('${uiTestBundle.path}${Platform.pathSeparator}RunnerUITests'),
      true,
    ),
    (
      'Share Extension Info.plist',
      File('${shareExtension.path}${Platform.pathSeparator}Info.plist'),
      false,
    ),
    (
      'Share Extension executable',
      File('${shareExtension.path}${Platform.pathSeparator}Share Extension'),
      true,
    ),
    (
      'NotificationService Info.plist',
      File('${notificationService.path}${Platform.pathSeparator}Info.plist'),
      false,
    ),
    (
      'NotificationService executable',
      File(
        '${notificationService.path}${Platform.pathSeparator}'
        'NotificationService',
      ),
      true,
    ),
  ]) {
    final file = requiredFile.$2;
    if (!_nonEmptyRegularFile(file)) {
      return SimsIosDeviceBuildProductsValidation.failure(
        'Central iOS build products are missing non-empty '
        '${requiredFile.$1}.',
      );
    }
    if (requiredFile.$3 && !_executableFile(file)) {
      return SimsIosDeviceBuildProductsValidation.failure(
        'Central iOS build products contain a non-executable '
        '${requiredFile.$1}.',
      );
    }
  }

  final signedBundles = <String, Directory>{};
  void addSignedBundle(Directory directory) {
    signedBundles[directory.absolute.path] = directory.absolute;
  }

  for (final required in <Directory>[
    application,
    shareExtension,
    notificationService,
    uiTestHost,
    uiTestBundle,
  ]) {
    addSignedBundle(required);
  }
  for (final root in <Directory>[application, uiTestHost]) {
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! Directory || !_realDirectory(entity)) continue;
      if (const <String>{
        '.app',
        '.appex',
        '.framework',
        '.xctest',
      }.any(entity.path.endsWith)) {
        addSignedBundle(entity);
      }
    }
  }
  final orderedSignedBundles = signedBundles.values.toList(growable: false)
    ..sort((left, right) {
      final depth = right.path.length.compareTo(left.path.length);
      return depth != 0 ? depth : left.path.compareTo(right.path);
    });
  final effectiveEnvironment = environment ?? Platform.environment;
  final runner = codesignRunner ?? _runSimsIosCodesign;
  final verified = <String>[];
  for (final signedBundle in orderedSignedBundles) {
    late final ProcessResult result;
    try {
      result = await runner('codesign', <String>[
        '--verify',
        '--deep',
        '--strict',
        signedBundle.path,
      ], effectiveEnvironment);
    } on Object catch (error) {
      return SimsIosDeviceBuildProductsValidation.failure(
        'Unable to run codesign verification for '
        '${_lastPathComponent(signedBundle.path)}: ${error.runtimeType}.',
      );
    }
    if (result.exitCode != 0) {
      final output = '${result.stderr}'.trim().isNotEmpty
          ? '${result.stderr}'
          : '${result.stdout}';
      return SimsIosDeviceBuildProductsValidation.failure(
        'codesign verification failed for '
        '${_lastPathComponent(signedBundle.path)} '
        '(exit ${result.exitCode}): ${_bounded(output)}',
      );
    }
    verified.add(signedBundle.path);
  }

  final relativeApplication = application.path.substring(
    productRoot.path.length + 1,
  );
  return SimsIosDeviceBuildProductsValidation.success(
    application: application,
    xctestrun: xctestruns.single,
    relativeApplication: relativeApplication,
    uiTestHost: uiTestHost,
    uiTestBundle: uiTestBundle,
    verifiedCodePaths: verified,
  );
}

Future<ProcessResult> _runSimsIosCodesign(
  String executable,
  List<String> arguments,
  Map<String, String> environment,
) => Process.run(executable, arguments, environment: environment);

bool _realDirectory(Directory directory) =>
    FileSystemEntity.typeSync(directory.path, followLinks: false) ==
    FileSystemEntityType.directory;

bool _nonEmptyRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file &&
    file.lengthSync() > 0;

bool _executableFile(File file) =>
    Platform.isWindows || (file.statSync().mode & 0x49) != 0;

String _lastPathComponent(String path) =>
    Uri.file(path).pathSegments.where((part) => part.isNotEmpty).last;

final class SimsBuildPreparation {
  const SimsBuildPreparation({
    required this.report,
    required this.artifacts,
    required this.failures,
    required this.inputDigests,
  });

  final SimsBuildReport report;
  final Map<String, String> artifacts;
  final Map<String, String> failures;
  final Map<String, String> inputDigests;
}

final class SimsBuildOrchestrator {
  SimsBuildOrchestrator({
    Directory? cacheDirectory,
    Map<String, String>? environment,
  }) : cacheDirectory = cacheDirectory ?? _defaultCacheDirectory(),
       environment = Map<String, String>.unmodifiable(
         environment ?? Platform.environment,
       );

  final Directory cacheDirectory;
  final Map<String, String> environment;

  Future<SimsBuildPreparation> prepare(
    SimsManifest manifest,
    SimsPlan plan, {
    Set<String> skipProfileIds = const <String>{},
  }) async {
    final totalStopwatch = Stopwatch()..start();
    final requestedIds = BuildRequestSet.fromProfileIds(
      plan.rows
          .map((row) => row.buildProfileId)
          .where(
            (id) =>
                !skipProfileIds.contains(id) &&
                (manifest.buildProfileById(id)?.buildRequired ?? false),
          ),
    ).profileIds;
    final artifacts = <String, String>{};
    final failures = <String, String>{};
    final inputDigests = <String, String>{};
    final artifactDigests = <String, String>{};
    final invalidations = <String>[];
    final declaredExceptions = <String>[];
    final builtProfileIds = <String>[];
    final cacheHitProfileIds = <String>[];
    final failedProfileIds = <String>[];
    final profileElapsedMs = <String, int>{};
    var actualBuilds = 0;
    var hits = 0;
    var misses = 0;

    if (requestedIds.isEmpty) {
      return const SimsBuildPreparation(
        report: SimsBuildReport.empty,
        artifacts: <String, String>{},
        failures: <String, String>{},
        inputDigests: <String, String>{},
      );
    }

    final sourceDigests = <String, String>{};
    final toolchains = <String, Map<String, String>>{};
    cacheDirectory.createSync(recursive: true);
    for (final profileId in requestedIds) {
      final profile = manifest.buildProfileById(profileId)!;
      final profileStopwatch = Stopwatch()..start();
      try {
        if (profile.declaredException) declaredExceptions.add(profile.id);
        final entrypoint =
            environment['SIMS_BUILD_ENTRYPOINT'] ?? _entrypointFor(profile);
        final sourceKey = '${profile.platform}\u0000$entrypoint';
        final sourceDigest = sourceDigests.putIfAbsent(
          sourceKey,
          () => computeSimsBuildProfileSourceClosureDigest(
            profile: profile,
            entrypoint: entrypoint,
            environment: environment,
            allowTestOverride:
                environment['SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE'] == '1',
          ),
        );
        final toolchain = toolchains.putIfAbsent(
          profile.platform,
          () => _toolchainFingerprint(profile),
        );
        final input = _inputFor(profile, sourceDigest, toolchain);
        inputDigests[profile.id] = input.inputDigest;
        final profileRoot = Directory('${cacheDirectory.path}/${profile.id}');
        final entryRoot = Directory('${profileRoot.path}/${input.inputDigest}');
        final attestationFile = File('${entryRoot.path}/attestation.json');
        final cachedArtifact = _cachedArtifact(entryRoot, profile);

        BuildAttestation? attestation;
        if (attestationFile.existsSync()) {
          try {
            final decoded = jsonDecode(attestationFile.readAsStringSync());
            if (decoded is Map) {
              attestation = BuildAttestation.fromJson(
                decoded.map<String, Object?>(
                  (key, value) => MapEntry('$key', value),
                ),
              );
            }
          } on Object {
            invalidations.add('${profile.id}:invalid-attestation');
          }
        }
        final cachedBytes = _artifactDigestBytes(cachedArtifact);
        final verification = BuildCacheVerifier.verify(
          input,
          attestation,
          cachedBytes,
        );
        if (verification.isHit) {
          hits += 1;
          cacheHitProfileIds.add(profile.id);
          artifacts[profile.id] = cachedArtifact.path;
          artifactDigests[profile.id] = attestation!.artifactDigest;
          continue;
        }

        misses += 1;
        if (profileRoot.existsSync() &&
            profileRoot.listSync().whereType<Directory>().isNotEmpty) {
          invalidations.add('${profile.id}:${verification.reason.name}');
        }
        final build = await _build(profile);
        if (!build.ok) {
          failures[profile.id] = build.detail;
          failedProfileIds.add(profile.id);
          continue;
        }

        final sourceArtifact = _artifactEntity(build.artifactPath!);
        if (sourceArtifact == null) {
          failures[profile.id] =
              'Builder reported a missing artifact: ${build.artifactPath}';
          failedProfileIds.add(profile.id);
          continue;
        }
        final artifactBytes = _artifactDigestBytes(sourceArtifact);
        entryRoot.createSync(recursive: true);
        _replaceCachedArtifact(sourceArtifact, cachedArtifact);
        final created = BuildAttestation.create(
          input: input,
          artifactBytes: artifactBytes,
          artifactPath: cachedArtifact.path,
          redactedCommand: build.redactedCommand,
          createdAt: DateTime.now().toUtc(),
        );
        attestationFile.writeAsStringSync(
          '${jsonEncode(created.toJson())}\n',
          flush: true,
        );
        actualBuilds += 1;
        builtProfileIds.add(profile.id);
        artifacts[profile.id] = cachedArtifact.path;
        artifactDigests[profile.id] = created.artifactDigest;
      } finally {
        profileStopwatch.stop();
        profileElapsedMs[profile.id] = profileStopwatch.elapsedMilliseconds;
      }
    }
    totalStopwatch.stop();

    return SimsBuildPreparation(
      report: SimsBuildReport(
        requestedProfiles: requestedIds.length,
        actualBuilds: actualBuilds,
        hits: hits,
        misses: misses,
        invalidations: List<String>.unmodifiable(invalidations),
        artifactDigests: Map<String, String>.unmodifiable(artifactDigests),
        declaredExceptions: List<String>.unmodifiable(declaredExceptions),
        builtProfileIds: List<String>.unmodifiable(builtProfileIds),
        cacheHitProfileIds: List<String>.unmodifiable(cacheHitProfileIds),
        failedProfileIds: List<String>.unmodifiable(failedProfileIds),
        profileElapsedMs: Map<String, int>.unmodifiable(profileElapsedMs),
        totalElapsedMs: totalStopwatch.elapsedMilliseconds,
      ),
      artifacts: Map<String, String>.unmodifiable(artifacts),
      failures: Map<String, String>.unmodifiable(failures),
      inputDigests: Map<String, String>.unmodifiable(inputDigests),
    );
  }

  BuildProfileInput _inputFor(
    BuildProfileSpec profile,
    String sourceDigest,
    Map<String, String> toolchain,
  ) {
    final inputFiles = <String, List<int>>{
      'source-closure.sha256': utf8.encode(sourceDigest),
      if (File('pubspec.lock').existsSync())
        'pubspec.lock': File('pubspec.lock').readAsBytesSync(),
      ..._profileAttestedInputFiles(profile),
      ...simsIosDeviceProductValidatorInputFiles(profile.id),
    };
    return BuildProfileInput(
      profileId: profile.id,
      platform: profile.platform,
      architecture: _architectureFor(profile),
      entrypoint:
          environment['SIMS_BUILD_ENTRYPOINT'] ?? _entrypointFor(profile),
      mode: _iosDeviceBuildConfiguration(profile.id) != null
          ? 'release'
          : 'debug',
      flavor: environment['SIMS_BUILD_FLAVOR'] ?? 'default',
      compileDefines: _effectiveCompileDefines(profile),
      appId: effectiveSimsApplicationId(profile, environment: environment),
      providerConfigDigests:
          profile.artifactKind == 'provider-configured-debug-apk'
          ? _digestEnvironmentValues('SIMS_PROVIDER_')
          : const <String, String>{},
      signingDigests: _signingFingerprint(profile, inputFiles),
      inputFiles: inputFiles,
      toolchain: <String, String>{
        ...toolchain,
        'os': Platform.operatingSystemVersion,
      },
      buildOptions: _buildArguments(profile),
      runtimeConfig: const <String, Object?>{},
    );
  }

  Map<String, String> _toolchainFingerprint(BuildProfileSpec profile) {
    final fingerprints = <String, String>{
      'dart': _versionDigestFromText(Platform.version),
      'flutter': _commandVersionDigest('flutter', const <String>[
        '--version',
        '--machine',
      ]),
    };
    if (profile.platform == 'android') {
      fingerprints['gradle'] = _commandVersionDigest(
        'android/gradlew',
        const <String>['--version'],
      );
    }
    if (profile.platform == 'android' || profile.platform == 'ios') {
      // The centrally built app embeds gomobile output. Pin the effective Go
      // toolchain, not the host's incidental default, to the same version used
      // by the ensure scripts and Makefile.
      fingerprints['go'] = _commandVersionDigest(
        'go',
        const <String>['version'],
        environmentOverrides: const <String, String>{'GOTOOLCHAIN': 'go1.25.0'},
        includeBinaryDigest: true,
      );
      fingerprints['gomobile'] = _gomobileToolchainDigest();
    }
    if (profile.platform == 'android') {
      fingerprints.addAll(
        computeSimsAndroidNdkIdentity(environment: environment),
      );
    }
    if (profile.platform == 'ios') {
      fingerprints['xcode'] = _commandVersionDigest(
        'xcodebuild',
        const <String>['-version'],
      );
      fingerprints['cocoapods'] = _commandVersionDigest('pod', const <String>[
        '--version',
      ]);
    }
    return Map<String, String>.unmodifiable(fingerprints);
  }

  Map<String, List<int>> _profileAttestedInputFiles(BuildProfileSpec profile) {
    if (profile.id != _iosDeviceProductionProfileId) {
      return const <String, List<int>>{};
    }
    final result = <String, List<int>>{};
    _addEnvironmentFile(
      result,
      logicalName: 'ios-staging-signing-attestation.json',
      environmentNames: const <String>[
        'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST',
        'SIMS_IOS_SIGNING_ATTESTATION_PATH',
        'SIMS_SIGNING_ATTESTATION_PATH',
      ],
    );
    _addEnvironmentFile(
      result,
      logicalName: 'ios-provisioning-profile.mobileprovision',
      environmentNames: const <String>[
        'SIMS_IOS_PROVISIONING_PROFILE_PATH',
        'SIMS_SIGNING_PROVISIONING_PROFILE_PATH',
        'SIMS_PROVISIONING_PROFILE_PATH',
      ],
    );
    return Map<String, List<int>>.unmodifiable(result);
  }

  void _addEnvironmentFile(
    Map<String, List<int>> destination, {
    required String logicalName,
    required List<String> environmentNames,
  }) {
    for (final name in environmentNames) {
      final path = environment[name]?.trim();
      if (path == null || path.isEmpty) continue;
      final file = File(path);
      if (FileSystemEntity.typeSync(file.path, followLinks: true) !=
          FileSystemEntityType.file) {
        continue;
      }
      destination[logicalName] = file.readAsBytesSync();
      return;
    }
  }

  Map<String, String> _signingFingerprint(
    BuildProfileSpec profile,
    Map<String, List<int>> inputFiles,
  ) {
    if (_iosDeviceBuildConfiguration(profile.id) == null) {
      return const <String, String>{};
    }
    final result = <String, String>{
      ..._digestEnvironmentValues('SIMS_SIGNING_'),
    };
    for (final name in const <String>[
      'CODE_SIGN_IDENTITY',
      'CODE_SIGN_STYLE',
      'DEVELOPMENT_TEAM',
      'EXPANDED_CODE_SIGN_IDENTITY',
      'EXPANDED_CODE_SIGN_IDENTITY_NAME',
      'PRODUCT_BUNDLE_IDENTIFIER',
      'PROVISIONING_PROFILE',
      'PROVISIONING_PROFILE_SPECIFIER',
      'SIMS_APP_ID',
      'SIMS_IOS_PHYSICAL_DEVICE_ID',
      'SIMS_SIGNING_EXPIRES_AT',
      'SIMS_PROVISIONING_PROFILE_EXPIRES_AT',
    ]) {
      final value = environment[name];
      if (value == null || value.isEmpty) continue;
      result[name] = sha256.convert(utf8.encode(value)).toString();
    }

    final attestation = inputFiles['ios-staging-signing-attestation.json'];
    if (attestation != null) {
      result['attestation.contents'] = sha256.convert(attestation).toString();
      _addAttestationCategoryDigests(result, attestation);
    }
    final provision = inputFiles['ios-provisioning-profile.mobileprovision'];
    if (provision != null) {
      result['provisioningProfile.contents'] = sha256
          .convert(provision)
          .toString();
    }
    return Map<String, String>.unmodifiable(result);
  }

  void _addAttestationCategoryDigests(
    Map<String, String> destination,
    List<int> bytes,
  ) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) return;
      final categories = <String, List<Object?>>{
        'identity': <Object?>[],
        'provisioning': <Object?>[],
        'device': <Object?>[],
        'expiry': <Object?>[],
      };
      _collectAttestationCategories(decoded, categories);
      for (final entry in categories.entries) {
        if (entry.value.isEmpty) continue;
        destination['attestation.${entry.key}'] = sha256
            .convert(utf8.encode(_canonicalJsonForDigest(entry.value)))
            .toString();
      }
      final expiries = categories['expiry']!
          .whereType<String>()
          .map(DateTime.tryParse)
          .whereType<DateTime>()
          .toList(growable: false);
      if (expiries.isNotEmpty) {
        final expired = expiries.any(
          (expiry) => !expiry.toUtc().isAfter(DateTime.now().toUtc()),
        );
        destination['attestation.expiryState'] = sha256
            .convert(utf8.encode(expired ? 'expired' : 'unexpired'))
            .toString();
      }
    } on Object {
      // The complete byte digest still invalidates malformed/opaque
      // attestations. Validation and typed blocking happen in device preflight.
    }
  }

  String _commandVersionDigest(
    String executable,
    List<String> arguments, {
    Map<String, String> environmentOverrides = const <String, String>{},
    bool includeBinaryDigest = false,
  }) {
    final resolved = _resolveExecutable(executable, environment);
    if (resolved == null) return 'missing';
    var binaryIdentity = '';
    if (includeBinaryDigest) {
      try {
        final binary = File(File(resolved).resolveSymbolicLinksSync());
        binaryIdentity = 'binary=${sha256.convert(binary.readAsBytesSync())}\n';
      } on Object catch (error) {
        binaryIdentity = 'binary-read-error:${error.runtimeType}\n';
      }
    }
    try {
      final result = Process.runSync(
        resolved,
        arguments,
        environment: <String, String>{...environment, ...environmentOverrides},
      );
      return _versionDigestFromText(
        '$binaryIdentity'
        'exit=${result.exitCode}\n${result.stdout}\n${result.stderr}',
      );
    } on ProcessException catch (error) {
      return _versionDigestFromText('process-error:${error.message}');
    }
  }

  String _gomobileToolchainDigest() {
    const pinned = <String, String>{'GOTOOLCHAIN': 'go1.25.0'};
    var resolved = _resolveExecutable('gomobile', environment);
    if (resolved == null) {
      final go = _resolveExecutable('go', environment);
      if (go != null) {
        try {
          final result = Process.runSync(
            go,
            const <String>['env', 'GOPATH'],
            environment: <String, String>{...environment, ...pinned},
          );
          if (result.exitCode == 0) {
            final goPath = '${result.stdout}'
                .trim()
                .split(Platform.isWindows ? ';' : ':')
                .first;
            if (goPath.isNotEmpty) {
              final candidate = File(
                '$goPath${Platform.pathSeparator}bin'
                '${Platform.pathSeparator}gomobile',
              );
              if (candidate.existsSync()) resolved = candidate.absolute.path;
            }
          }
        } on ProcessException {
          // The missing identity below remains fail-closed and deterministic.
        }
      }
    }
    if (resolved == null) return 'missing';
    late final File binary;
    late final String binaryDigest;
    try {
      binary = File(File(resolved).resolveSymbolicLinksSync());
      binaryDigest = sha256.convert(binary.readAsBytesSync()).toString();
    } on Object catch (error) {
      final stat = File(resolved).statSync();
      return _versionDigestFromText(
        'binary-read-error:${error.runtimeType}\n'
        'size=${stat.size}\nmodified=${stat.modified.toUtc().toIso8601String()}',
      );
    }
    try {
      final result = Process.runSync(
        binary.path,
        const <String>['version'],
        environment: <String, String>{...environment, ...pinned},
      );
      return _versionDigestFromText(
        'binary=$binaryDigest\nexit=${result.exitCode}\n'
        '${result.stdout}\n${result.stderr}',
      );
    } on Object catch (error) {
      return _versionDigestFromText(
        'binary=$binaryDigest\nprocess-error:${error.runtimeType}',
      );
    }
  }

  Future<_BuildInvocation> _build(BuildProfileSpec profile) async {
    final iosDeviceConfiguration = _iosDeviceBuildConfiguration(profile.id);
    if (iosDeviceConfiguration != null) {
      return _buildIosDevice(profile, iosDeviceConfiguration);
    }
    final arguments = _buildArguments(profile);
    final command = <String>['flutter', ...arguments];
    ProcessResult result;
    try {
      result = await Process.run(
        command.first,
        command.skip(1).toList(growable: false),
        environment: <String, String>{
          ...environment,
          'SIMS_BUILD_PROFILE': profile.id,
          if (profile.platform == 'android')
            'ORG_GRADLE_PROJECT_androidApplicationId':
                effectiveSimsApplicationId(profile, environment: environment),
        },
      );
    } on ProcessException catch (error) {
      return _BuildInvocation.failure(
        'Unable to start builder: ${error.message}',
      );
    }
    if (result.exitCode != 0) {
      return _BuildInvocation.failure(
        'Central build exited ${result.exitCode}: ${_bounded('${result.stderr}')}',
      );
    }

    String? artifactPath;
    for (final line in LineSplitter.split('${result.stdout}')) {
      if (line.startsWith('SIMS_BUILD_ARTIFACT=')) {
        artifactPath = line.substring('SIMS_BUILD_ARTIFACT='.length).trim();
      }
    }
    artifactPath ??= _defaultArtifactPath(profile);
    if (artifactPath == null || artifactPath.isEmpty) {
      return _BuildInvocation.failure(
        'Builder did not emit SIMS_BUILD_ARTIFACT for ${profile.id}.',
      );
    }
    return _BuildInvocation.success(
      artifactPath,
      redactSimsBuildCommandForAttestation(command),
    );
  }

  Future<_BuildInvocation> _buildIosDevice(
    BuildProfileSpec profile,
    _IosDeviceBuildConfiguration configuration,
  ) async {
    final encodedDefines = _effectiveCompileDefines(profile).entries
        .map(
          (entry) => base64.encode(utf8.encode('${entry.key}=${entry.value}')),
        )
        .join(',');
    final derivedData = Directory(
      environment[configuration.derivedDataEnvironment]?.trim().isNotEmpty ==
              true
          ? environment[configuration.derivedDataEnvironment]!.trim()
          : configuration.defaultDerivedDataPath,
    ).absolute;
    if (derivedData.existsSync()) derivedData.deleteSync(recursive: true);
    derivedData.createSync(recursive: true);
    final xcodeArguments = <String>[
      'build-for-testing',
      '-workspace',
      'ios/Runner.xcworkspace',
      '-scheme',
      'Runner',
      '-configuration',
      'Release',
      if (configuration.allowProvisioningUpdates) '-allowProvisioningUpdates',
      'ENABLE_TESTABILITY=YES',
      '-destination',
      'generic/platform=iOS',
      '-derivedDataPath',
      derivedData.path,
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS='
          '${configuration.swiftCompilationConditions}',
      ...configuration.buildSettings,
      'FLUTTER_TARGET=${environment['SIMS_BUILD_ENTRYPOINT'] ?? _entrypointFor(profile)}',
      if (encodedDefines.isNotEmpty) 'DART_DEFINES=$encodedDefines',
    ];
    late final ProcessResult xcodeResult;
    try {
      xcodeResult = await Process.run(
        'xcodebuild',
        xcodeArguments,
        environment: <String, String>{
          ...environment,
          'SIMS_BUILD_PROFILE': profile.id,
        },
      );
    } on ProcessException catch (error) {
      return _BuildInvocation.failure(
        'Unable to start the central iOS UI-rig builder: ${error.message}',
      );
    }
    if (xcodeResult.exitCode != 0) {
      return _BuildInvocation.failure(
        'Central iOS UI-rig build exited ${xcodeResult.exitCode}: '
        '${_xcodeFailureDetail(xcodeResult)}',
      );
    }
    final products = Directory(
      '${derivedData.path}${Platform.pathSeparator}Build'
      '${Platform.pathSeparator}Products',
    );
    final sourceValidation = await validateSimsIosDeviceBuildProducts(
      products: products,
      environment: environment,
    );
    if (!sourceValidation.ok) {
      return _BuildInvocation.failure(sourceValidation.detail);
    }
    final sourceXctestrun = sourceValidation.xctestrun!;
    final relativeApplication = sourceValidation.relativeApplication!;

    final bundle = Directory(
      environment[configuration.bundlePathEnvironment]?.trim().isNotEmpty ==
              true
          ? environment[configuration.bundlePathEnvironment]!.trim()
          : configuration.defaultBundlePath,
    ).absolute;
    if (bundle.existsSync()) bundle.deleteSync(recursive: true);
    bundle.createSync(recursive: true);
    final bundledXctestrun = File(
      '${bundle.path}${Platform.pathSeparator}RunnerUITests.xctestrun',
    );
    sourceXctestrun.copySync(bundledXctestrun.path);
    _preserveMode(sourceXctestrun, bundledXctestrun.path);
    final bundledProducts = Directory(
      '${bundle.path}${Platform.pathSeparator}TestProducts',
    )..createSync(recursive: true);
    _copyDirectory(products, bundledProducts);
    final bundleManifest =
        File(
          '${bundle.path}${Platform.pathSeparator}bundle_manifest.json',
        )..writeAsStringSync(
          '${jsonEncode(<String, Object?>{'schema': configuration.bundleManifestSchema, 'profileId': profile.id, 'applicationApp': 'TestProducts/$relativeApplication', 'xctestrun': 'RunnerUITests.xctestrun', 'testProducts': 'TestProducts', 'centralCompileCommands': 1, 'logicalBuildCount': 1, 'childBuildCount': 0})}\n',
          flush: true,
        );
    final packagedValidation = await validateSimsIosDeviceBuildProducts(
      products: bundledProducts,
      environment: environment,
    );
    if (!packagedValidation.ok ||
        packagedValidation.relativeApplication != relativeApplication ||
        !_nonEmptyRegularFile(bundledXctestrun) ||
        !_nonEmptyRegularFile(bundleManifest)) {
      final detail = !packagedValidation.ok
          ? packagedValidation.detail
          : packagedValidation.relativeApplication != relativeApplication
          ? 'Packaged iOS Runner.app moved from its validated product path.'
          : 'Packaged iOS bundle is missing its xctestrun or member manifest.';
      bundle.deleteSync(recursive: true);
      return _BuildInvocation.failure(
        'Packaged iOS UI-rig validation failed: $detail',
      );
    }
    return _BuildInvocation.success(
      bundle.path,
      redactSimsBuildCommandForAttestation(<String>[
        'xcodebuild',
        ...xcodeArguments,
      ]),
    );
  }

  List<String> _buildArguments(BuildProfileSpec profile) =>
      effectiveSimsBuildArguments(profile, environment: environment);

  String? _defaultArtifactPath(BuildProfileSpec profile) {
    if (profile.platform == 'android') {
      return 'build/app/outputs/flutter-apk/app-debug.apk';
    }
    if (profile.id == 'ios.simulator.e2e') {
      return 'build/ios/iphonesimulator/Runner.app';
    }
    if (profile.id == _iosDeviceProductionProfileId) {
      final ipaDirectory = Directory('build/ios/ipa');
      if (!ipaDirectory.existsSync()) return null;
      final candidates =
          ipaDirectory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.ipa'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      return candidates.isEmpty ? null : candidates.last.path;
    }
    return null;
  }

  String _entrypointFor(BuildProfileSpec profile) =>
      _defaultSimsBuildEntrypoint(profile);

  Map<String, String> _effectiveCompileDefines(BuildProfileSpec profile) =>
      effectiveSimsCompileDefines(profile, environment: environment);

  Map<String, String> _digestEnvironmentValues(String prefix) {
    final result = <String, String>{};
    for (final entry in environment.entries) {
      if (!entry.key.startsWith(prefix) || entry.value.isEmpty) continue;
      result[entry.key] = sha256.convert(utf8.encode(entry.value)).toString();
    }
    return result;
  }
}

/// Returns the exact deterministic arguments used by the central builder.
///
/// Keeping this pure makes the command itself part of the testable cache
/// contract: [BuildProfileInput.buildOptions] fingerprints this complete list.
List<String> effectiveSimsBuildArguments(
  BuildProfileSpec profile, {
  Map<String, String>? environment,
}) {
  final effectiveEnvironment = environment ?? Platform.environment;
  final defines = effectiveSimsCompileDefines(
    profile,
    environment: effectiveEnvironment,
  ).entries.toList()..sort((left, right) => left.key.compareTo(right.key));
  final defineArgs = <String>[
    for (final entry in defines) '--dart-define=${entry.key}=${entry.value}',
  ];
  final entrypoint =
      effectiveEnvironment['SIMS_BUILD_ENTRYPOINT'] ??
      _defaultSimsBuildEntrypoint(profile);
  final iosDeviceConfiguration = _iosDeviceBuildConfiguration(profile.id);
  if (iosDeviceConfiguration != null) {
    final encodedDefines = defines
        .map(
          (entry) => base64.encode(utf8.encode('${entry.key}=${entry.value}')),
        )
        .join(',');
    return <String>[
      'build-for-testing',
      '-workspace=ios/Runner.xcworkspace',
      '-scheme=Runner',
      '-configuration=Release',
      if (iosDeviceConfiguration.allowProvisioningUpdates)
        '-allowProvisioningUpdates',
      'ENABLE_TESTABILITY=YES',
      '-destination=generic/platform=iOS',
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS='
          '${iosDeviceConfiguration.swiftCompilationConditions}',
      ...iosDeviceConfiguration.buildSettings,
      'FLUTTER_TARGET=$entrypoint',
      if (encodedDefines.isNotEmpty) 'DART_DEFINES=$encodedDefines',
    ];
  }
  if (profile.platform == 'android') {
    return <String>[
      'build',
      'apk',
      '--debug',
      '--target-platform=android-arm64',
      '--android-project-arg=simsAndroidAbi=arm64-v8a',
      if (profile.id == _androidProductionAudioCallProfileId) ...const <String>[
        '--android-project-arg=enableAndroidNativeCalls=true',
        '--android-project-arg=disableGoogleServicesForDisposableProof=true',
      ],
      if (profile.id == _androidGroupMedia269ProfileId) ...const <String>[
        '--android-project-arg=disableGoogleServicesForDisposableProof=true',
        '--android-project-arg=enableGroupMedia269DisposableProof=true',
      ],
      '--target=$entrypoint',
      ...defineArgs,
    ];
  }
  if (profile.id == 'ios.simulator.e2e') {
    return <String>[
      'build',
      'ios',
      '--simulator',
      '--debug',
      '--no-codesign',
      '--target=$entrypoint',
      ...defineArgs,
    ];
  }
  if (profile.platform == 'ios') {
    return <String>[
      'build',
      'ipa',
      '--release',
      '--target=$entrypoint',
      ...defineArgs,
    ];
  }
  return <String>['build', profile.artifactKind, ...defineArgs];
}

String _defaultSimsBuildEntrypoint(BuildProfileSpec profile) =>
    switch (profile.id) {
      'android.e2e.standard' => 'integration_test/sims_dispatcher.dart',
      'android.e2e.main' => 'lib/main.dart',
      'android.e2e.production_call_local' => 'lib/main.dart',
      'android.e2e.direct_media_custody' => 'lib/main.dart',
      _androidGroupMedia269ProfileId => 'lib/main.dart',
      'ios.simulator.e2e' =>
        'integration_test/group_multi_party_device_real_harness.dart',
      _ => 'lib/main.dart',
    };

/// Compile-time identity embedded in every centrally built app artifact.
///
/// The profile ID is reserved and deliberately written after manifest defines,
/// so a malformed manifest cannot make an artifact claim another profile.
Map<String, String> effectiveSimsCompileDefines(
  BuildProfileSpec profile, {
  Map<String, String>? environment,
}) {
  final effectiveEnvironment = environment ?? Platform.environment;
  final defines = <String, String>{...profile.compileDefines};
  if (profile.buildRequired) {
    defines['SIMS_BUILD_PROFILE_ID'] = profile.id;
  } else {
    defines.remove('SIMS_BUILD_PROFILE_ID');
  }
  if (profile.platform == 'android' ||
      profile.id == 'ios.simulator.e2e' ||
      _iosDeviceBuildConfiguration(profile.id) != null) {
    final relayAddresses = effectiveEnvironment['MKNOON_RELAY_ADDRESSES']
        ?.trim();
    if (relayAddresses != null && relayAddresses.isNotEmpty) {
      defines['MKNOON_RELAY_ADDRESSES'] = relayAddresses;
    }
  }
  if (profile.id == 'ios.simulator.e2e') {
    defines['MKNOON_KEY_ROTATION_GRACE_PERIOD_MS'] = '1500';
  }
  return Map<String, String>.unmodifiable(defines);
}

/// Returns the exact application ID used by the Android Gradle build without
/// fingerprinting the machine-local `local.properties` file itself.
String effectiveSimsApplicationId(
  BuildProfileSpec profile, {
  Map<String, String>? environment,
  Directory? projectDirectory,
}) {
  final effectiveEnvironment = environment ?? Platform.environment;
  if (profile.id == _iosDeviceGroupMedia269ProfileId) {
    return _iosDeviceGroupMedia269BundleId;
  }
  if (profile.id == _androidProductionAudioCallProfileId) {
    return _androidProductionAudioCallApplicationId;
  }
  if (profile.id == _androidGroupMedia269ProfileId) {
    return _androidGroupMedia269ApplicationId;
  }
  if (profile.platform != 'android') {
    final explicit = effectiveEnvironment['SIMS_APP_ID']?.trim();
    return explicit == null || explicit.isEmpty
        ? defaultAndroidAppPackage
        : explicit;
  }
  final projectRoot = (projectDirectory ?? Directory.current).absolute;
  final localProperties = File('${projectRoot.path}/android/local.properties');
  return resolveAndroidAppPackageFromSources(
    environmentValue: effectiveEnvironment['ANDROID_APP_PACKAGE'],
    simsApplicationId: effectiveEnvironment['SIMS_APP_ID'],
    gradleApplicationId:
        effectiveEnvironment['ORG_GRADLE_PROJECT_androidApplicationId'],
    localPropertyLines: localProperties.existsSync()
        ? const LineSplitter().convert(localProperties.readAsStringSync())
        : null,
  );
}

/// Canonical, content-safe identities for the two NDK selections that can
/// affect an Android artifact: Flutter/Gradle's pinned NDK and gomobile's NDK.
Map<String, String> computeSimsAndroidNdkIdentity({
  Directory? projectDirectory,
  Map<String, String>? environment,
  String? flutterNdkVersionOverride,
}) {
  final projectRoot = (projectDirectory ?? Directory.current).absolute;
  final effectiveEnvironment = environment ?? Platform.environment;
  final sdkRoot = _androidSdkRoot(projectRoot, effectiveEnvironment);
  final flutterNdkVersion =
      flutterNdkVersionOverride ??
      _flutterNdkVersion(effectiveEnvironment) ??
      '<unknown>';
  Directory? flutterNdk;
  if (sdkRoot != null) {
    flutterNdk = Directory('${sdkRoot.path}/ndk/$flutterNdkVersion');
  }

  Directory? gomobileNdk;
  final explicitNdk = effectiveEnvironment['ANDROID_NDK_HOME']?.trim();
  if (explicitNdk != null && explicitNdk.isNotEmpty) {
    gomobileNdk = Directory(explicitNdk);
  } else if (sdkRoot != null) {
    final ndkRoot = Directory('${sdkRoot.path}/ndk');
    if (ndkRoot.existsSync()) {
      final candidates =
          ndkRoot
              .listSync(followLinks: false)
              .whereType<Directory>()
              .toList(growable: false)
            ..sort(
              (left, right) => _compareVersionNames(
                left.uri.pathSegments.where((part) => part.isNotEmpty).last,
                right.uri.pathSegments.where((part) => part.isNotEmpty).last,
              ),
            );
      if (candidates.isNotEmpty) gomobileNdk = candidates.last;
    }
  }

  return Map<String, String>.unmodifiable(<String, String>{
    'ndk.flutter': _ndkIdentityDigest(
      flutterNdk,
      expectedVersion: flutterNdkVersion,
    ),
    'ndk.gomobile': _ndkIdentityDigest(gomobileNdk),
  });
}

FileSystemEntity _cachedArtifact(
  Directory entryRoot,
  BuildProfileSpec profile,
) {
  final iosDeviceConfiguration = _iosDeviceBuildConfiguration(profile.id);
  if (iosDeviceConfiguration != null) {
    return Directory(
      '${entryRoot.path}/${iosDeviceConfiguration.cachedBundleName}',
    );
  }
  if (profile.id == 'ios.simulator.e2e') {
    return Directory('${entryRoot.path}/Runner.app');
  }
  if (profile.platform == 'android') {
    return File('${entryRoot.path}/artifact.apk');
  }
  if (profile.platform == 'ios') {
    return File('${entryRoot.path}/artifact.ipa');
  }
  return File('${entryRoot.path}/artifact.bin');
}

FileSystemEntity? _artifactEntity(String path) {
  return switch (FileSystemEntity.typeSync(path, followLinks: false)) {
    FileSystemEntityType.file => File(path),
    FileSystemEntityType.directory => Directory(path),
    _ => null,
  };
}

List<int> _artifactDigestBytes(FileSystemEntity entity) {
  if (!entity.existsSync()) return const <int>[];
  if (entity is File) return entity.readAsBytesSync();
  if (entity is! Directory) return const <int>[];
  final records = <String>[];
  final entries = entity.listSync(recursive: true, followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  for (final entry in entries) {
    final relative = entry.path.substring(entity.path.length + 1);
    final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        final mode = entry.statSync().mode & 0x1ff;
        records.add(
          'file\t$relative\t${mode.toRadixString(8)}\t'
          '${sha256.convert(File(entry.path).readAsBytesSync())}',
        );
      case FileSystemEntityType.directory:
        final mode = entry.statSync().mode & 0x1ff;
        records.add('directory\t$relative\t${mode.toRadixString(8)}');
      case FileSystemEntityType.link:
        records.add('link\t$relative\t${Link(entry.path).targetSync()}');
      case FileSystemEntityType.notFound:
        records.add('missing\t$relative');
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        records.add('unsupported\t$relative\t$type');
    }
  }
  return utf8.encode(records.join('\n'));
}

void _replaceCachedArtifact(
  FileSystemEntity source,
  FileSystemEntity destination,
) {
  if (destination.existsSync()) destination.deleteSync(recursive: true);
  if (source is File && destination is File) {
    source.copySync(destination.path);
    return;
  }
  if (source is Directory && destination is Directory) {
    destination.createSync(recursive: true);
    _preserveMode(source, destination.path);
    _copyDirectory(source, destination);
    return;
  }
  throw StateError(
    'Artifact kind changed between builder and cache: '
    '${source.runtimeType} -> ${destination.runtimeType}',
  );
}

void _copyDirectory(Directory source, Directory destination) {
  for (final entity in source.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
    final targetPath = '${destination.path}/$name';
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        File(entity.path).copySync(targetPath);
        _preserveMode(entity, targetPath);
      case FileSystemEntityType.directory:
        final child = Directory(targetPath)..createSync();
        _preserveMode(entity, targetPath);
        _copyDirectory(Directory(entity.path), child);
      case FileSystemEntityType.link:
        Link(targetPath).createSync(Link(entity.path).targetSync());
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw StateError('Unsupported artifact entry: ${entity.path}');
    }
  }
}

void _preserveMode(FileSystemEntity source, String destinationPath) {
  if (Platform.isWindows) return;
  final permissionBits = source.statSync().mode & 0x1ff;
  final result = Process.runSync('chmod', <String>[
    permissionBits.toRadixString(8).padLeft(3, '0'),
    destinationPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Unable to preserve artifact mode for $destinationPath');
  }
}

final class _BuildInvocation {
  const _BuildInvocation._({
    required this.ok,
    required this.artifactPath,
    required this.redactedCommand,
    required this.detail,
  });

  factory _BuildInvocation.success(
    String artifactPath,
    List<String> redactedCommand,
  ) => _BuildInvocation._(
    ok: true,
    artifactPath: artifactPath,
    redactedCommand: redactedCommand,
    detail: '',
  );

  factory _BuildInvocation.failure(String detail) => _BuildInvocation._(
    ok: false,
    artifactPath: null,
    redactedCommand: const <String>[],
    detail: detail,
  );

  final bool ok;
  final String? artifactPath;
  final List<String> redactedCommand;
  final String detail;
}

void _collectAttestationCategories(
  Object? value,
  Map<String, List<Object?>> categories, {
  String key = '',
}) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((left, right) => '$left'.compareTo('$right'));
    for (final entry in entries) {
      _collectAttestationCategories(
        entry.value,
        categories,
        key: entry.key.toString(),
      );
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _collectAttestationCategories(item, categories, key: key);
    }
    return;
  }
  final normalized = key.toLowerCase();
  if (normalized.contains('identity') || normalized.contains('certificate')) {
    categories['identity']!.add(value);
  }
  if (normalized.contains('provision') || normalized.contains('team')) {
    categories['provisioning']!.add(value);
  }
  if (normalized.contains('device') || normalized.contains('receiver')) {
    categories['device']!.add(value);
  }
  if (normalized.contains('expir') ||
      normalized.contains('notafter') ||
      normalized.contains('validuntil')) {
    categories['expiry']!.add(value);
  }
}

String _canonicalJsonForDigest(Object? value) =>
    jsonEncode(_canonicalizeForDigest(value));

Object? _canonicalizeForDigest(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalizeForDigest(value[key]),
    };
  }
  if (value is Iterable) {
    return value.map(_canonicalizeForDigest).toList(growable: false);
  }
  return value;
}

Directory _defaultCacheDirectory() {
  final configured = Platform.environment['SIMS_CACHE_DIR']?.trim();
  return Directory(
    configured == null || configured.isEmpty ? 'build/sims/cache' : configured,
  );
}

const simsSharedFlutterBuildSourceRoots = <String>['assets'];

const simsAndroidBuildSourceRoots = <String>[
  'android',
  'packages/background_push_crypto/android',
];

const simsIosBuildSourceRoots = <String>[
  'ios',
  'third_party/bonsoir_darwin',
  'packages/background_push_crypto/ios',
];

const simsSharedMobileBindingBuildInputFiles = <String>[
  'scripts/gomobile_binding_inputs.sh',
  'scripts/verify_gomobile_bindings.sh',
];

const simsAndroidBuildInputFiles = <String>[
  'scripts/ensure_go_android_bindings.sh',
  'packages/background_push_crypto/pubspec.yaml',
];

const simsIosBuildInputFiles = <String>['scripts/ensure_go_ios_bindings.sh'];

/// Compatibility union used by the whole-suite source closure and inventory
/// assertions. Reusable artifacts use the narrower profile closure below.
const simsBuildSourceRoots = <String>[
  'lib',
  'integration_test',
  'android',
  'ios',
  'assets',
  'packages/background_push_crypto',
  'third_party/bonsoir_darwin',
];

const simsSuiteSourceRoots = <String>[
  ...simsBuildSourceRoots,
  'test',
  'tool/sims',
  'scripts',
  'go-mknoon',
  'go-relay-server',
];

String computeSimsSourceClosureDigest({
  Map<String, String>? environment,
  bool allowTestOverride = false,
}) => _computeSourceClosureDigest(
  roots: simsSuiteSourceRoots,
  files: const <String>[
    'pubspec.yaml',
    'pubspec.lock',
    'analysis_options.yaml',
    'l10n.yaml',
  ],
  environment: environment,
  allowTestOverride: allowTestOverride,
);

/// Build-cache input closure. This is intentionally narrower than the whole
/// sims-suite digest: changing a shell verifier must invalidate old reports
/// and checkpoints, but must not rebuild an otherwise identical app binary.
String computeSimsBuildSourceClosureDigest({
  Map<String, String>? environment,
  bool allowTestOverride = false,
}) => _computeSourceClosureDigest(
  roots: simsBuildSourceRoots,
  files: const <String>['pubspec.yaml', 'pubspec.lock', 'l10n.yaml'],
  environment: environment,
  allowTestOverride: allowTestOverride,
);

/// Build-cache source closure for one concrete artifact profile.
///
/// Shared Flutter/application sources are common inputs. Native sources are
/// selected by platform, and only the actual Dart entrypoint plus its local
/// import/export/part closure is included outside those shared roots. This
/// prevents an iOS-only native or harness edit from rebuilding Android (and
/// vice versa) without dropping any source that the selected build consumes.
String computeSimsBuildProfileSourceClosureDigest({
  required BuildProfileSpec profile,
  required String entrypoint,
  Directory? projectDirectory,
  Map<String, String>? environment,
  bool allowTestOverride = false,
}) {
  final effectiveEnvironment = environment ?? Platform.environment;
  final override = effectiveEnvironment['SIMS_SOURCE_DIGEST']?.trim();
  if (allowTestOverride && override != null && override.isNotEmpty) {
    return override;
  }
  final projectRoot = (projectDirectory ?? Directory.current).absolute;
  final roots = <String>[
    ...simsSharedFlutterBuildSourceRoots,
    if (profile.platform == 'android') ...simsAndroidBuildSourceRoots,
    if (profile.platform == 'ios') ...simsIosBuildSourceRoots,
  ];
  final declaredAssets = _declaredFlutterAssetInputs(projectRoot);
  roots.addAll(declaredAssets.roots);
  final entrypointClosure = _localDartEntrypointClosure(
    projectRoot,
    entrypoint,
  ).where((path) => !_ignoredSourcePath(path));
  return _computeSourceClosureDigest(
    roots: roots,
    files: <String>[
      'pubspec.yaml',
      'pubspec.lock',
      'l10n.yaml',
      ...declaredAssets.files,
      ..._l10nArbInputFiles(projectRoot),
      ..._goMobileProductionInputFiles(projectRoot),
      ...simsSharedMobileBindingBuildInputFiles,
      if (profile.platform == 'android') ...simsAndroidBuildInputFiles,
      if (profile.platform == 'ios') ...simsIosBuildInputFiles,
      ...entrypointClosure,
    ],
    environment: effectiveEnvironment,
    allowTestOverride: false,
    projectDirectory: projectRoot,
  );
}

({List<String> roots, List<String> files}) _declaredFlutterAssetInputs(
  Directory projectRoot,
) {
  final pubspec = File('${projectRoot.path}/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return (roots: const <String>[], files: const <String>[]);
  }
  final roots = <String>{};
  final files = <String>{};
  var inFlutter = false;
  int? assetsIndent;
  for (final raw in const LineSplitter().convert(pubspec.readAsStringSync())) {
    final withoutComment = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
    if (withoutComment.trim().isEmpty) continue;
    final indent = withoutComment.length - withoutComment.trimLeft().length;
    final trimmed = withoutComment.trim();
    if (indent == 0) {
      inFlutter = trimmed == 'flutter:';
      assetsIndent = null;
      continue;
    }
    if (!inFlutter) continue;
    if (assetsIndent == null) {
      if (trimmed == 'assets:') assetsIndent = indent;
      continue;
    }
    if (indent <= assetsIndent) {
      assetsIndent = null;
      continue;
    }
    final match = RegExp(r'^-\s+(.+)$').firstMatch(trimmed);
    if (match == null) continue;
    final path = _yamlScalar(match.group(1)!);
    if (!_safeProjectRelativePath(path)) continue;
    final normalized = _normalizedProjectPath(path);
    final entityPath = _projectEntityPath(projectRoot, normalized);
    if (path.endsWith('/') || Directory(entityPath).existsSync()) {
      roots.add(normalized.replaceFirst(RegExp(r'/$'), ''));
    } else {
      files.add(normalized);
      files.addAll(_resolutionVariantAssetFiles(projectRoot, normalized));
    }
  }
  final sortedRoots = roots.toList()..sort();
  final sortedFiles = files.toList()..sort();
  return (
    roots: List<String>.unmodifiable(sortedRoots),
    files: List<String>.unmodifiable(sortedFiles),
  );
}

List<String> _resolutionVariantAssetFiles(
  Directory projectRoot,
  String declaredFile,
) {
  final slash = declaredFile.lastIndexOf('/');
  final parent = slash < 0 ? '.' : declaredFile.substring(0, slash);
  final name = slash < 0 ? declaredFile : declaredFile.substring(slash + 1);
  final parentDirectory = Directory(_projectEntityPath(projectRoot, parent));
  if (!parentDirectory.existsSync()) return const <String>[];
  final result = <String>[];
  for (final child in parentDirectory.listSync(followLinks: false)) {
    if (child is! Directory) continue;
    final variant = child.uri.pathSegments
        .where((part) => part.isNotEmpty)
        .last;
    if (!RegExp(r'^\d+(?:\.\d+)?x$').hasMatch(variant)) continue;
    final candidate = File('${child.path}/$name');
    if (candidate.existsSync()) {
      result.add(_relativeProjectPath(projectRoot, candidate.path));
    }
  }
  result.sort();
  return result;
}

List<String> _l10nArbInputFiles(Directory projectRoot) {
  final config = File('${projectRoot.path}/l10n.yaml');
  var arbDirectory = 'lib/l10n';
  if (config.existsSync()) {
    final match = RegExp(
      r'^\s*arb-dir\s*:\s*(.+?)\s*$',
      multiLine: true,
    ).firstMatch(config.readAsStringSync());
    if (match != null) arbDirectory = _yamlScalar(match.group(1)!);
  }
  if (!_safeProjectRelativePath(arbDirectory)) return const <String>[];
  final directory = Directory(_projectEntityPath(projectRoot, arbDirectory));
  if (!directory.existsSync()) return const <String>[];
  final result =
      directory
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .map((file) => _relativeProjectPath(projectRoot, file.path))
          .toList(growable: false)
        ..sort();
  return result;
}

List<String> _goMobileProductionInputFiles(Directory projectRoot) {
  final root = Directory('${projectRoot.path}/go-mknoon');
  if (!root.existsSync()) return const <String>[];
  const sourceExtensions = <String>{'.go', '.s', '.S', '.c', '.h', '.m', '.mm'};
  final result = <String>[];
  for (final file
      in root.listSync(recursive: true, followLinks: false).whereType<File>()) {
    final relative = _relativeProjectPath(projectRoot, file.path);
    final normalized = _normalizedProjectPath(relative);
    if (normalized.contains('/.gocache/') ||
        normalized.contains('/testdata/') ||
        normalized.endsWith('_test.go')) {
      continue;
    }
    final name = file.uri.pathSegments.last;
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '' : name.substring(dot);
    if (normalized == 'go-mknoon/Makefile' ||
        name == 'go.mod' ||
        name == 'go.sum' ||
        sourceExtensions.contains(extension)) {
      result.add(normalized);
    }
  }
  result.sort();
  return result;
}

String _yamlScalar(String raw) {
  final value = raw.trim();
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

bool _safeProjectRelativePath(String path) {
  if (path.trim().isEmpty || File(path).isAbsolute) return false;
  final parts = _normalizedProjectPath(path).split('/');
  return !parts.contains('..');
}

String _computeSourceClosureDigest({
  required List<String> roots,
  required List<String> files,
  required Map<String, String>? environment,
  required bool allowTestOverride,
  Directory? projectDirectory,
}) {
  final effectiveEnvironment = environment ?? Platform.environment;
  final override = effectiveEnvironment['SIMS_SOURCE_DIGEST']?.trim();
  if (allowTestOverride && override != null && override.isNotEmpty) {
    return override;
  }
  final projectRoot = (projectDirectory ?? Directory.current).absolute;
  final records = <String>[];
  for (final root in roots) {
    final absoluteRoot = _projectEntityPath(projectRoot, root);
    final entity = FileSystemEntity.typeSync(absoluteRoot);
    if (entity == FileSystemEntityType.notFound) continue;
    if (entity == FileSystemEntityType.file) {
      records.add(
        '${_normalizedProjectPath(root)}\t'
        '${sha256.convert(File(absoluteRoot).readAsBytesSync())}',
      );
      continue;
    }
    final files =
        Directory(absoluteRoot)
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where(
              (file) => !_ignoredSourcePath(
                _relativeProjectPath(projectRoot, file.path),
              ),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    for (final file in files) {
      final relative = _relativeProjectPath(projectRoot, file.path);
      records.add(
        '$relative\t'
        '${sha256.convert(file.readAsBytesSync())}',
      );
    }
  }
  final recordedFiles = <String>{};
  for (final path in files) {
    final normalized = _normalizedProjectPath(path);
    if (_ignoredSourcePath(normalized)) continue;
    if (!recordedFiles.add(normalized)) continue;
    final file = File(_projectEntityPath(projectRoot, normalized));
    if (file.existsSync()) {
      records.add('$normalized\t${sha256.convert(file.readAsBytesSync())}');
    }
  }
  records.sort();
  return sha256.convert(utf8.encode(records.join('\n'))).toString();
}

List<String> _localDartEntrypointClosure(
  Directory projectRoot,
  String entrypoint,
) {
  final packageRoots = _localPackageRoots(projectRoot);
  final pending = <String>[_normalizedProjectPath(entrypoint)];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final relative = pending.removeLast();
    if (!visited.add(relative)) continue;
    final file = File(_projectEntityPath(projectRoot, relative));
    if (!file.existsSync() || !relative.endsWith('.dart')) continue;
    final contents = file.readAsStringSync();
    for (final uri in _dartDirectiveUris(contents)) {
      final dependency = _localDartDependency(
        projectRoot: projectRoot,
        importingFile: file,
        uri: uri,
        packageRoots: packageRoots,
      );
      if (dependency != null && !visited.contains(dependency)) {
        pending.add(dependency);
      }
    }
  }
  final result = visited.toList()..sort();
  return result;
}

Iterable<String> _dartDirectiveUris(String contents) sync* {
  final directive = RegExp(
    r'''(?:^|\n)\s*(?:import|export|part)\s+([\s\S]*?);''',
  );
  final quotedUri = RegExp(r'''['"]([^'"]+)['"]''');
  for (final match in directive.allMatches(contents)) {
    final body = match.group(1)!;
    for (final uriMatch in quotedUri.allMatches(body)) {
      yield uriMatch.group(1)!;
    }
  }
}

String? _localDartDependency({
  required Directory projectRoot,
  required File importingFile,
  required String uri,
  required Map<String, Directory> packageRoots,
}) {
  String path;
  if (uri.startsWith('package:')) {
    final slash = uri.indexOf('/');
    if (slash <= 'package:'.length) return null;
    final packageName = uri.substring('package:'.length, slash);
    final packageRoot = packageRoots[packageName];
    if (packageRoot == null) return null;
    path = '${packageRoot.path}/${uri.substring(slash + 1)}';
  } else if (uri.startsWith('dart:')) {
    return null;
  } else {
    final resolved = importingFile.absolute.uri.resolve(uri);
    if (resolved.scheme != 'file') return null;
    path = resolved.toFilePath();
  }
  final absolute = File(_projectEntityPath(projectRoot, path)).absolute.path;
  final rootPrefix = '${projectRoot.path}${Platform.pathSeparator}';
  if (absolute != projectRoot.path && !absolute.startsWith(rootPrefix)) {
    return null;
  }
  return _relativeProjectPath(projectRoot, absolute);
}

Map<String, Directory> _localPackageRoots(Directory projectRoot) {
  final result = <String, Directory>{};
  final rootPackageName = _projectPackageName(projectRoot);
  result[rootPackageName] = Directory('${projectRoot.path}/lib').absolute;
  final packageConfig = File(
    '${projectRoot.path}/.dart_tool/package_config.json',
  );
  if (!packageConfig.existsSync()) return result;
  try {
    final decoded = jsonDecode(packageConfig.readAsStringSync());
    if (decoded is! Map || decoded['packages'] is! List) return result;
    for (final value in decoded['packages'] as List) {
      if (value is! Map) continue;
      final name = value['name'];
      final rootUriValue = value['rootUri'];
      final packageUriValue = value['packageUri'];
      if (name is! String || rootUriValue is! String) continue;
      final rootUri = packageConfig.absolute.uri.resolve(rootUriValue);
      if (rootUri.scheme != 'file') continue;
      final rootDirectoryUri = rootUri.path.endsWith('/')
          ? rootUri
          : rootUri.replace(path: '${rootUri.path}/');
      final packageUri = rootDirectoryUri.resolve(
        packageUriValue is String ? packageUriValue : 'lib/',
      );
      if (packageUri.scheme != 'file') continue;
      final directory = Directory(packageUri.toFilePath()).absolute;
      final rootPrefix = '${projectRoot.path}${Platform.pathSeparator}';
      if (directory.path != projectRoot.path &&
          !directory.path.startsWith(rootPrefix)) {
        continue;
      }
      result[name] = directory;
    }
  } on Object {
    // Root package resolution still catches app-owned imports. A malformed
    // generated config will also make Flutter fail before producing an artifact.
  }
  return result;
}

String _projectPackageName(Directory projectRoot) {
  final pubspec = File('${projectRoot.path}/pubspec.yaml');
  if (!pubspec.existsSync()) return 'flutter_app';
  final match = RegExp(
    r'^name:\s*([A-Za-z0-9_]+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());
  return match?.group(1) ?? 'flutter_app';
}

String? _javaProperty(File file, String key) {
  if (!file.existsSync()) return null;
  for (final raw in const LineSplitter().convert(file.readAsStringSync())) {
    final line = raw.trimLeft();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
    final match = RegExp(
      '^${RegExp.escape(key)}\\s*[:=]\\s*(.*)\$',
    ).firstMatch(line);
    if (match != null) return match.group(1)?.trim();
  }
  return null;
}

Directory? _androidSdkRoot(
  Directory projectRoot,
  Map<String, String> environment,
) {
  for (final value in <String?>[
    environment['ANDROID_HOME'],
    environment['ANDROID_SDK_ROOT'],
    _javaProperty(
      File('${projectRoot.path}/android/local.properties'),
      'sdk.dir',
    ),
  ]) {
    final path = value?.trim();
    if (path != null && path.isNotEmpty) return Directory(path).absolute;
  }
  return null;
}

String? _flutterNdkVersion(Map<String, String> environment) {
  final flutter = _resolveExecutable('flutter', environment);
  if (flutter == null) return null;
  try {
    final resolved = File(flutter).resolveSymbolicLinksSync();
    final flutterRoot = File(resolved).parent.parent;
    final extension = File(
      '${flutterRoot.path}/packages/flutter_tools/gradle/src/main/kotlin/'
      'FlutterExtension.kt',
    );
    if (!extension.existsSync()) return null;
    return RegExp(
      r'val\s+ndkVersion\s*:\s*String\s*=\s*"([^"]+)"',
    ).firstMatch(extension.readAsStringSync())?.group(1);
  } on FileSystemException {
    return null;
  }
}

String _ndkIdentityDigest(Directory? directory, {String? expectedVersion}) {
  final sourceProperties = directory == null
      ? null
      : File('${directory.path}/source.properties');
  final revision = sourceProperties?.existsSync() == true
      ? _javaProperty(sourceProperties!, 'Pkg.Revision')
      : null;
  final directoryVersion = directory == null
      ? '<missing>'
      : directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
  final canonical = <String, String>{
    'expected': expectedVersion ?? '<auto>',
    'directoryVersion': directoryVersion,
    'revision': revision ?? '<missing>',
    if (sourceProperties?.existsSync() == true)
      'sourcePropertiesSha256': sha256
          .convert(sourceProperties!.readAsBytesSync())
          .toString(),
  };
  return 'sha256:${sha256.convert(utf8.encode(_canonicalJsonForDigest(canonical)))}';
}

int _compareVersionNames(String left, String right) {
  final leftParts = left.split(RegExp(r'[^0-9]+'));
  final rightParts = right.split(RegExp(r'[^0-9]+'));
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index += 1) {
    final leftValue = index < leftParts.length
        ? int.tryParse(leftParts[index]) ?? 0
        : 0;
    final rightValue = index < rightParts.length
        ? int.tryParse(rightParts[index]) ?? 0
        : 0;
    final comparison = leftValue.compareTo(rightValue);
    if (comparison != 0) return comparison;
  }
  return left.compareTo(right);
}

String _projectEntityPath(Directory projectRoot, String path) {
  final normalized = _normalizedProjectPath(path);
  if (File(normalized).isAbsolute) return normalized;
  return '${projectRoot.path}${Platform.pathSeparator}'
      '${normalized.replaceAll('/', Platform.pathSeparator)}';
}

String _relativeProjectPath(Directory projectRoot, String absolutePath) {
  final normalizedRoot = projectRoot.absolute.path.replaceAll('\\', '/');
  final normalized = File(absolutePath).absolute.path.replaceAll('\\', '/');
  if (normalized == normalizedRoot) return '.';
  final prefix = '$normalizedRoot/';
  return normalized.startsWith(prefix)
      ? normalized.substring(prefix.length)
      : normalized;
}

String _normalizedProjectPath(String path) => path
    .replaceAll('\\', '/')
    .replaceAll(RegExp(r'/+'), '/')
    .replaceFirst(RegExp(r'^\./'), '');

String? _resolveExecutable(String executable, Map<String, String> environment) {
  if (executable.contains(Platform.pathSeparator)) {
    final file = File(executable);
    return file.existsSync() ? file.absolute.path : null;
  }
  final path = environment['PATH'];
  if (path == null || path.isEmpty) return null;
  for (final directory in path.split(Platform.isWindows ? ';' : ':')) {
    if (directory.isEmpty) continue;
    final candidate = File('$directory${Platform.pathSeparator}$executable');
    if (candidate.existsSync()) return candidate.absolute.path;
  }
  return null;
}

String _versionDigestFromText(String value) =>
    'sha256:${sha256.convert(utf8.encode(value.trim()))}';

bool _ignoredSourcePath(String path) {
  final normalized = _normalizedProjectPath(path);
  return normalized.contains('/build/') ||
      normalized.contains('/.gradle/') ||
      normalized.contains('/.dart_tool/') ||
      normalized.contains('/.kotlin/') ||
      normalized.contains('/.cxx/') ||
      normalized.contains('/Pods/') ||
      normalized.contains('/.symlinks/') ||
      normalized.contains('/DerivedData/') ||
      normalized.contains('/ephemeral/') ||
      normalized.contains('/xcuserdata/') ||
      normalized.contains('/GoMknoon.xcframework/') ||
      normalized.endsWith('/GoMknoon.aar') ||
      normalized.endsWith('/GoMknoon-sources.jar') ||
      normalized.endsWith('/GoMknoon.inputs.sha256') ||
      normalized.endsWith('/GoMknoon.inputs.sha256.tmp') ||
      normalized.endsWith('/.DS_Store') ||
      normalized == '.DS_Store' ||
      normalized == 'android/local.properties' ||
      normalized == 'android/key.properties' ||
      normalized == 'android/app/upload-keystore.jks' ||
      (normalized.startsWith('android/app/') &&
          (normalized.endsWith('.jks') || normalized.endsWith('.keystore'))) ||
      normalized == 'ios/Flutter/Generated.xcconfig' ||
      normalized == 'ios/Flutter/flutter_export_environment.sh' ||
      RegExp(r'^ios/Runner/Runner \d{4}-\d{2}-\d{2} ').hasMatch(normalized) ||
      normalized ==
          'android/app/src/main/java/io/flutter/plugins/'
              'GeneratedPluginRegistrant.java' ||
      normalized == 'ios/Runner/GeneratedPluginRegistrant.h' ||
      normalized == 'ios/Runner/GeneratedPluginRegistrant.m' ||
      RegExp(
        r'^lib/l10n/app_localizations(?:_[a-zA-Z_]+)?\.dart$',
      ).hasMatch(normalized);
}

String _architectureFor(BuildProfileSpec profile) {
  if (profile.platform == 'android') return 'android-arm64';
  if (profile.artifactKind.contains('universal') ||
      profile.artifactKind == 'apk') {
    return 'universal';
  }
  if (profile.id.contains('simulator')) return 'simulator';
  return 'device';
}

/// Removes inline compile-time values before a central build command is
/// persisted in an artifact attestation.
///
/// Every dart-define is treated as private by default. Keeping its key and a
/// deterministic value digest preserves useful build provenance without
/// allowing a newly introduced endpoint, credential, or other define to leak
/// merely because its name was not added to a sensitive-key allowlist.
List<String> redactSimsBuildCommandForAttestation(Iterable<String> command) =>
    List<String>.unmodifiable(command.map(_redactArgument));

String _redactArgument(String argument) {
  final lower = argument.toLowerCase();
  const dartDefinePrefix = '--dart-define=';
  if (lower.startsWith(dartDefinePrefix)) {
    final definition = argument.substring(dartDefinePrefix.length);
    final separator = definition.indexOf('=');
    if (separator < 0) {
      return '$dartDefinePrefix${_hashedRedaction(definition)}';
    }
    final key = definition.substring(0, separator);
    final value = definition.substring(separator + 1);
    return '$dartDefinePrefix$key=${_hashedRedaction(value)}';
  }
  const encodedDartDefinesPrefix = 'dart_defines=';
  if (lower.startsWith(encodedDartDefinesPrefix)) {
    final prefix = argument.substring(0, encodedDartDefinesPrefix.length);
    final value = argument.substring(encodedDartDefinesPrefix.length);
    return '$prefix${_hashedRedaction(value)}';
  }
  if (lower.contains('token=') ||
      lower.contains('secret=') ||
      lower.contains('password=')) {
    final key = argument.substring(0, argument.indexOf('=') + 1);
    final value = argument.substring(argument.indexOf('=') + 1);
    return '$key${_hashedRedaction(value)}';
  }
  return argument;
}

String _hashedRedaction(String value) =>
    '<sha256:${sha256.convert(utf8.encode(value))}>';

String _bounded(String value) {
  final normalized = value.trim();
  return normalized.length <= 1000
      ? normalized
      : '${normalized.substring(0, 1000)}…';
}

String _xcodeFailureDetail(ProcessResult result) {
  final combined = '${result.stdout}\n${result.stderr}';
  final diagnostics = LineSplitter.split(combined)
      .where(
        (line) =>
            line.contains('error:') ||
            line.contains('fatal error:') ||
            line.contains('BUILD FAILED') ||
            line.contains('requires a development team'),
      )
      .take(12)
      .join('\n');
  if (diagnostics.isNotEmpty) return _bounded(diagnostics);
  final stderrText = '${result.stderr}'.trim();
  return _bounded(stderrText.isNotEmpty ? stderrText : '${result.stdout}');
}
