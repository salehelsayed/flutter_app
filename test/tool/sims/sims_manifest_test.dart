import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/sims.dart';

void main() {
  late SimsManifest manifest;

  setUpAll(() {
    manifest = SimsManifest.loadSync(File('tool/sims/critical_features.json'));
  });

  test(
    'no-argument mode is major and smoke/full cannot claim release green',
    () {
      expect(SimsCliOptions.parse(const <String>[]).mode, SimsMode.major);

      final planner = SimsPlanner(manifest);
      expect(
        planner.compile(mode: SimsMode.major).releaseEligibleCandidate,
        isTrue,
      );
      expect(
        planner.compile(mode: SimsMode.full).releaseEligibleCandidate,
        isFalse,
      );
      expect(
        planner.compile(mode: SimsMode.smoke).releaseEligibleCandidate,
        isFalse,
      );
      expect(
        planner
            .compile(mode: SimsMode.major, family: '1to1')
            .releaseEligibleCandidate,
        isFalse,
      );
    },
  );

  test('every critical feature and core boundary has one complete owner', () {
    final featurePaths = Directory('lib/features')
        .listSync()
        .whereType<Directory>()
        .map((directory) => directory.path.replaceAll('\\', '/'))
        .toSet();

    expect(
      () => manifest.validateOrThrow(
        requiredFeaturePaths: featurePaths,
        requiredCorePaths: requiredCriticalCorePaths,
      ),
      returnsNormally,
    );

    for (final owner in manifest.ownership) {
      expect(manifest.capabilityById(owner.capabilityId), isNotNull);
      if (!owner.critical) {
        expect(owner.rationale, isNotEmpty);
      }
    }
  });

  test('critical ownership cannot point outside the required major gate', () {
    final owner = manifest.ownership.firstWhere((entry) => entry.critical);
    final capability = manifest.capabilityById(owner.capabilityId)!;

    for (final invalid in <CapabilitySpec>[
      capability.copyWith(active: false),
      capability.copyWith(required: false),
      capability.copyWith(modes: const <SimsMode>{SimsMode.full}),
    ]) {
      final errors = manifest
          .copyWith(
            capabilities: manifest.capabilities
                .map((entry) => entry.id == invalid.id ? invalid : entry)
                .toList(growable: false),
          )
          .validate();
      expect(
        errors.any(
          (error) =>
              error.contains('must use an active, required, major capability'),
        ),
        isTrue,
      );
    }
  });

  test('capability IDs commands and proof boundaries are unique', () {
    expect(manifest.validate(), isEmpty);
    final first = manifest.capabilities.first;

    final duplicateBoundary = first.copyWith(id: '${first.id}.duplicate');
    final errors = manifest
        .copyWith(
          capabilities: <CapabilitySpec>[
            ...manifest.capabilities,
            duplicateBoundary,
          ],
        )
        .validate();

    expect(errors.any((error) => error.contains('proof boundary')), isTrue);
    expect(errors.any((error) => error.contains('command')), isTrue);
  });

  test('resource classes and device-target locks fail closed', () {
    final first = manifest.capabilities.first;
    final typoResource = first.copyWith(
      id: '${first.id}.typo-resource',
      proofBoundaryId: '${first.proofBoundaryId}.typo-resource',
      command: <String>[...first.command, '--typo-resource'],
      resources: const <ResourceLock>[
        ResourceLock(
          name: 'devcie:android-physical',
          access: ResourceAccess.exclusive,
        ),
      ],
    );
    expect(
      manifest
          .copyWith(capabilities: <CapabilitySpec>[typoResource])
          .validate()
          .any((error) => error.contains('Unknown resource class')),
      isTrue,
    );

    final android = manifest.capabilityById(
      'android.voice_recorder_native_smoke',
    )!;
    final missingDeviceLock = android.copyWith(
      resources: const <ResourceLock>[
        ResourceLock(
          name: 'artifact:voice-recorder',
          access: ResourceAccess.write,
        ),
      ],
    );
    expect(
      manifest
          .copyWith(capabilities: <CapabilitySpec>[missingDeviceLock])
          .validate()
          .any((error) => error.contains('without a matching device resource')),
      isTrue,
    );

    final missingSecondEmulator = android.copyWith(
      targetCapabilities: const <String>[
        'android.physical',
        'android.emulator.count2',
      ],
      resources: const <ResourceLock>[
        ResourceLock(
          name: 'device:android-physical',
          access: ResourceAccess.exclusive,
        ),
        ResourceLock(
          name: 'device:android-emulator',
          access: ResourceAccess.exclusive,
        ),
      ],
    );
    expect(
      manifest
          .copyWith(capabilities: <CapabilitySpec>[missingSecondEmulator])
          .validate()
          .any(
            (error) =>
                error.contains('android.emulator.count2') &&
                error.contains('device:android-emulator-second'),
          ),
      isTrue,
    );
  });

  test('major plan has every required lane once and complete typed rows', () {
    final plan = SimsPlanner(manifest).compile(mode: SimsMode.major);
    const requiredLanes = <String>{
      'analyzer',
      'host-dart',
      'go-node',
      'go-relay',
      'native-android',
      'native-ios',
      'nested-package',
      'reliability',
      'performance',
    };

    expect(
      plan.rows.map((row) => row.lane).toSet(),
      containsAll(requiredLanes),
    );
    expect(plan.selectedIds.length, plan.rows.length);
    for (final row in plan.rows) {
      expect(row.id, isNotEmpty);
      expect(row.lane, isNotEmpty);
      expect(row.buildProfileId, isNotEmpty);
      expect(row.command, isNotEmpty);
      expect(row.resources, isNotEmpty);
      expect(row.proofBoundaryId, isNotEmpty);
    }
  });

  test('full Go node sweep keeps bounded timeout headroom', () {
    final row = manifest.capabilityById('go.node.all')!;
    expect(row.command, hasLength(3));
    expect(row.command.last, contains('go test ./... -count=1 -timeout=20m'));
  });

  test('native iOS runner tests keep Simulator A lifecycle serial', () {
    final row = manifest.capabilityById('native.ios.runner_tests')!;
    expect(row.command, <String>[
      'xcodebuild',
      'test',
      '-workspace',
      'ios/Runner.xcworkspace',
      '-scheme',
      'Runner',
      '-destination',
      r'platform=iOS Simulator,id=${SIMS_IOS_SIMULATOR_ID}',
      'CODE_SIGNING_ALLOWED=NO',
      '-parallel-testing-enabled',
      'NO',
      '-only-testing:RunnerTests',
    ]);
  });

  test('production FCM profile enables registration and wake emission', () {
    final profile = manifest.buildProfileById('android.production_fcm')!;
    expect(profile.compileDefines, <String, String>{
      'E2E_TEST_MODE': 'true',
      'PRODUCTION_FCM': 'true',
      'MKNOON_EMIT_WAKE_TOKEN': 'true',
    });
  });

  test('Android notification campaign reuses the central production APK', () {
    final capability = manifest.capabilityById(
      'notifications.android_payload_campaign',
    )!;

    expect(capability.automationReady, isTrue);
    expect(capability.buildProfileId, 'android.production_fcm');
    expect(capability.dependencies, <String>['build.android.production_fcm']);
    expect(capability.declaredBuildException, isFalse);
  });
}
