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

    final controlledPhysical = manifest.capabilityById(
      'android.connectivity_restore_media_outbox',
    )!;
    expect(
      controlledPhysical.resources.any(
        (resource) =>
            resource.name == 'device-control:android-physical' &&
            resource.access == ResourceAccess.exclusive,
      ),
      isTrue,
    );
    expect(
      manifest.validate(),
      isEmpty,
      reason: 'an exclusive physical network-control lock owns that target',
    );
    final withoutPhysicalControl = controlledPhysical.copyWith(
      resources: controlledPhysical.resources
          .where(
            (resource) => resource.name != 'device-control:android-physical',
          )
          .toList(growable: false),
    );
    expect(
      manifest
          .copyWith(
            capabilities: manifest.capabilities
                .map(
                  (entry) => entry.id == withoutPhysicalControl.id
                      ? withoutPhysicalControl
                      : entry,
                )
                .toList(growable: false),
          )
          .validate()
          .any(
            (error) =>
                error.contains('android.physical') &&
                error.contains('without a matching device resource'),
          ),
      isTrue,
    );
  });

  test('private media outbox capability is production-driving and exact', () {
    final capability = manifest.capabilityById(
      'android.connectivity_restore_media_outbox',
    );
    expect(capability, isNotNull);
    expect(capability!.owner, 'conversation');
    expect(capability.lane, 'reliability');
    expect(capability.required, isTrue);
    expect(
      capability.proofBoundaryId,
      'android.os-network.private-media-outbox.relay-delivery',
    );
    expect(capability.buildProfileId, 'android.e2e.main');
    expect(capability.dependencies, <String>['build.android.e2e.main']);
    expect(capability.artifactRequired, isTrue);
    expect(capability.artifactValidators, <String>[
      'validatePrivateMediaOutboxRestoreArtifact',
    ]);
    expect(capability.automationReady, isTrue);
    expect(capability.active, isTrue);
    expect(capability.allowedNaReason, 'target_unavailable_by_project_policy');
    expect(capability.command, <String>[
      'dart',
      'run',
      'integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart',
    ]);
    expect(
      capability.assertionIds,
      containsAll(<String>{
        'network_restored_claim_is_causal',
        'restore_retry_latency_recorded',
        'pause_resume_remained_queued',
        'zero_offline_resume_attempts',
        'one_post_restore_retry',
        'expected_attempt_counts',
        'zero_post_restore_ui_actions',
        'receiver_exact_media_delivered',
      }),
    );
  });

  test('runtime-root guard has exact required host execution contract', () {
    final capability = manifest.capabilityById('runtime.roots.advisory');

    expect(capability, isNotNull);
    expect(capability!.owner, 'flutter-app');
    expect(capability.proofBoundaryId, 'host.runtime-roots.advisory');
    expect(capability.assertionIds, <String>[
      'runtime_roots.inventory_accounted',
    ]);
    expect(capability.lane, 'host-dart');
    expect(capability.modes, <SimsMode>{SimsMode.major});
    expect(capability.families, <String>{'infra'});
    expect(capability.required, isTrue);
    expect(capability.command, <String>[
      './scripts/run_test_gates.sh',
      'runtime-roots',
    ]);
    expect(capability.buildProfileId, 'host.flutter_tester');
    expect(capability.dependencies, isEmpty);
    expect(capability.resources, hasLength(1));
    expect(capability.resources.single.name, 'host.cpu');
    expect(capability.resources.single.access, ResourceAccess.read);
    expect(capability.targetCapabilities, <String>[
      'host.flutter-tester',
      'host.bash',
      'host.git',
    ]);
    expect(capability.artifactRequired, isFalse);
    expect(capability.artifactValidators, isEmpty);
    expect(capability.allowedNaReason, isNull);
    expect(capability.active, isTrue);
    expect(capability.automationReady, isTrue);
    expect(capability.declaredBuildException, isFalse);
  });

  test('critical manifest pins architecture boundary release capability', () {
    final capability = manifest.capabilityById('architecture.boundaries');

    expect(capability, isNotNull);
    expect(capability!.owner, 'flutter-app');
    expect(capability.proofBoundaryId, 'host.architecture-boundaries.enforced');
    expect(capability.assertionIds, <String>[
      'architecture_boundaries.current_exceptions_exact',
    ]);
    expect(capability.lane, 'host-dart');
    expect(capability.modes, <SimsMode>{SimsMode.major});
    expect(capability.families, <String>{'infra'});
    expect(capability.required, isTrue);
    expect(capability.command, <String>[
      './scripts/run_test_gates.sh',
      'architecture-boundaries',
    ]);
    expect(capability.buildProfileId, 'host.flutter_tester');
    expect(capability.dependencies, isEmpty);
    expect(capability.resources, hasLength(1));
    expect(capability.resources.single.name, 'host.cpu');
    expect(capability.resources.single.access, ResourceAccess.read);
    expect(capability.targetCapabilities, <String>[
      'host.flutter-tester',
      'host.bash',
      'host.git',
    ]);
    expect(capability.artifactRequired, isFalse);
    expect(capability.artifactValidators, isEmpty);
    expect(capability.allowedNaReason, isNull);
    expect(capability.active, isTrue);
    expect(capability.automationReady, isTrue);
    expect(capability.declaredBuildException, isFalse);
  });

  test(
    'analyzer capability runs strict analysis and production unused suppression ratchet',
    () {
      final capability = manifest.capabilityById('analyzer.flutter');

      expect(capability, isNotNull);
      expect(capability!.owner, 'platform');
      expect(capability.proofBoundaryId, 'host.analyzer.repo');
      expect(capability.assertionIds, <String>[
        'analyzer.no_errors',
        'analyzer.no_warnings_or_infos',
        'analyzer.production_unused_suppressions_ratcheted',
      ]);
      expect(capability.lane, 'analyzer');
      expect(capability.modes, <SimsMode>{SimsMode.major});
      expect(capability.families, <String>{'infra'});
      expect(capability.required, isTrue);
      expect(capability.command, <String>[
        './scripts/check_flutter_analyze_strict.sh',
      ]);
      expect(capability.buildProfileId, 'host.process');
      expect(capability.dependencies, isEmpty);
      expect(capability.resources, hasLength(1));
      expect(capability.resources.single.name, 'host.cpu');
      expect(capability.resources.single.access, ResourceAccess.read);
      expect(capability.targetCapabilities, <String>[
        'host.flutter-sdk',
        'host.bash',
        'host.git',
      ]);
      expect(capability.artifactRequired, isFalse);
      expect(capability.artifactValidators, isEmpty);
      expect(capability.allowedNaReason, isNull);
      expect(capability.active, isTrue);
      expect(capability.automationReady, isTrue);
      expect(capability.declaredBuildException, isFalse);
    },
  );

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

  test('TC-393-11 fixed wake cohort is additive and exact', () {
    final base = manifest.buildProfileById('android.production_fcm')!;
    final fixed = manifest.buildProfileById(
      'android.production_fcm.fixed_wake',
    )!;
    expect(base.compileDefines, <String, String>{
      'E2E_TEST_MODE': 'true',
      'PRODUCTION_FCM': 'true',
      'MKNOON_EMIT_WAKE_TOKEN': 'true',
    });
    expect(fixed.artifactKind, 'provider-configured-debug-apk');
    expect(fixed.compileDefines, <String, String>{
      ...base.compileDefines,
      'MKNOON_ENABLE_WAKE_OUTCOME_COORDINATOR': 'true',
    });

    final build = manifest.capabilityById(
      'build.android.production_fcm.fixed_wake',
    )!;
    expect(build.command, <String>[
      '@prepare-build',
      'android.production_fcm.fixed_wake',
    ]);
    expect(build.buildProfileId, fixed.id);
    expect(build.dependencies, isEmpty);
    expect(
      build.resources.map(
        (resource) => '${resource.name}:${resource.access.name}',
      ),
      <String>['build:android.production_fcm.fixed_wake:write'],
    );
  });

  test('physical iOS production profile keeps its APNs-only compile seam', () {
    final profile = manifest.buildProfileById('ios.device.production')!;
    expect(profile.compileDefines, <String, String>{'PRODUCTION_APNS': 'true'});
  });

  test(
    'TC-347-09 owns one selector-only Android build and local fixture row',
    () {
      final profile = manifest.buildProfileById(
        'android.e2e.direct_media_custody',
      )!;
      expect(profile.platform, 'android');
      expect(profile.artifactKind, 'universal-debug-apk');
      expect(profile.buildRequired, isTrue);
      expect(profile.compileDefines, <String, String>{
        'E2E_TEST_MODE': 'true',
        'MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED': 'true',
      });

      final build = manifest.capabilityById(
        'build.android.e2e.direct_media_custody',
      )!;
      expect(build.command, <String>[
        '@prepare-build',
        'android.e2e.direct_media_custody',
      ]);
      expect(build.buildProfileId, profile.id);
      expect(build.dependencies, isEmpty);
      expect(
        build.resources.any(
          (resource) =>
              resource.name == 'build:android.e2e.direct_media_custody' &&
              resource.access == ResourceAccess.write,
        ),
        isTrue,
      );

      final scenario = manifest.capabilityById(
        'android.direct_media_blob_custody',
      )!;
      expect(scenario.owner, 'conversation');
      expect(scenario.required, isTrue);
      expect(scenario.active, isTrue);
      expect(scenario.automationReady, isTrue);
      expect(scenario.modes, <SimsMode>{SimsMode.major, SimsMode.full});
      expect(scenario.families, <String>{'1to1', 'media', 'transport'});
      expect(scenario.buildProfileId, profile.id);
      expect(scenario.dependencies, <String>[
        'build.android.e2e.direct_media_custody',
      ]);
      expect(scenario.command, <String>[
        'dart',
        'run',
        'integration_test/scripts/run_1to1_device_real.dart',
        '--scenario',
        'android.direct_media_blob_custody',
      ]);
      expect(scenario.targetCapabilities, <String>[
        'android.physical',
        'android.emulator',
      ]);
      expect(scenario.allowedNaReason, targetUnavailableNaReason);
      expect(scenario.artifactValidators, <String>[
        'validateDirectMediaBlobCustodyArtifact',
      ]);
      expect(
        scenario.resources
            .map((resource) => '${resource.access.name}:${resource.name}')
            .toSet(),
        containsAll(<String>{
          'read:build:android.e2e.direct_media_custody',
          'exclusive:device:android-physical',
          'exclusive:device:android-emulator',
          'exclusive:relay-mutation:local-direct-media-fixture',
          'write:artifact:direct-media-custody',
        }),
      );
    },
  );

  test('TC-269 Android proof owns only its disposable build profile', () {
    final profile = manifest.buildProfileById('android.e2e.group_media_269')!;
    expect(profile.platform, 'android');
    expect(profile.artifactKind, 'universal-debug-apk');
    expect(profile.buildRequired, isTrue);
    expect(profile.compileDefines, <String, String>{
      'E2E_TEST_MODE': 'true',
      'SIMS_ANDROID_DISPOSABLE_PACKAGE_ID': 'com.mknoon.sims.groupmedia269',
    });

    final build = manifest.capabilityById('build.android.e2e.group_media_269')!;
    expect(build.buildProfileId, profile.id);
    expect(build.command, <String>[
      '@prepare-build',
      'android.e2e.group_media_269',
    ]);
    expect(build.families, <String>['group', 'media', 'transport']);
    expect(build.assertionIds, <String>[
      'build.input_and_artifact_hash_attested',
      'build.disposable_application_id_attested',
    ]);
    expect(build.dependencies, isEmpty);
    expect(
      build.resources.any(
        (resource) =>
            resource.name == 'build:android.e2e.group_media_269' &&
            resource.access == ResourceAccess.write,
      ),
      isTrue,
    );

    final scenario = manifest.capabilityById('groups.media_send_reliability')!;
    expect(scenario.buildProfileId, profile.id);
    expect(scenario.dependencies, <String>[
      'build.android.e2e.group_media_269',
    ]);
    expect(
      scenario.resources.any(
        (resource) =>
            resource.name == 'build:android.e2e.group_media_269' &&
            resource.access == ResourceAccess.read,
      ),
      isTrue,
    );
    expect(
      manifest.capabilityById('build.android.e2e.main')!.families,
      isNot(contains('group')),
      reason: 'the production package must not be selected for Plan 269',
    );
  });

  test(
    'TC-269 physical iOS profile owns a distinct capability without APNs credentials',
    () {
      final profile = manifest.buildProfileById('ios.device.group_media_269')!;
      expect(profile.platform, 'ios');
      expect(profile.artifactKind, 'signed-physical-app-xctest-bundle');
      expect(profile.buildRequired, isTrue);
      expect(profile.compileDefines, <String, String>{
        'E2E_TEST_MODE': 'true',
        'PRODUCTION_APNS': 'true',
        'SIMS_IOS_DISPOSABLE_BUNDLE_ID': 'com.mknoon.sims.groupmedia269',
      });

      final capability = manifest.capabilityById(
        'build.ios.device.group_media_269',
      )!;
      expect(capability.buildProfileId, profile.id);
      expect(capability.command, <String>[
        '@prepare-build',
        'ios.device.group_media_269',
      ]);
      expect(capability.families, <String>['group', 'media', 'transport']);
      expect(capability.targetCapabilities, <String>['host.xcode']);
      expect(
        capability.targetCapabilities,
        isNot(contains('credentials.apns-signing')),
      );
      expect(capability.dependencies, isEmpty);
      expect(capability.declaredBuildException, isFalse);
    },
  );

  test('Android notification campaign reuses the central production APK', () {
    final capability = manifest.capabilityById(
      'notifications.android_payload_campaign',
    )!;

    expect(capability.automationReady, isTrue);
    expect(capability.buildProfileId, 'android.production_fcm');
    expect(capability.dependencies, <String>['build.android.production_fcm']);
    expect(capability.declaredBuildException, isFalse);
  });

  test('typed reaction reuses the central production APK', () {
    final matches = manifest.capabilities
        .where(
          (capability) =>
              capability.id == 'notifications.android_typed_reaction_smoke',
        )
        .toList(growable: false);
    expect(matches, hasLength(1));

    final capability = matches.single;
    expect(capability.required, isTrue);
    expect(capability.active, isTrue);
    expect(capability.automationReady, isTrue);
    expect(capability.modes, <SimsMode>{SimsMode.major, SimsMode.full});
    expect(capability.families, containsAll(<String>['notifications', '1to1']));
    expect(capability.buildProfileId, 'android.production_fcm');
    expect(capability.dependencies, <String>['build.android.production_fcm']);
    expect(capability.command, <String>[
      'dart',
      'run',
      'integration_test/scripts/run_1to1_reaction_notification_sims.dart',
    ]);
    expect(capability.declaredBuildException, isFalse);
  });

  test('TC-393-12 fixed-wake recovery capability is exact and runnable', () {
    final matches = manifest.capabilities
        .where(
          (capability) =>
              capability.id == 'notifications.android_recovery_completion',
        )
        .toList(growable: false);
    expect(matches, hasLength(1));

    final capability = matches.single;
    expect(capability.required, isTrue);
    expect(capability.active, isTrue);
    expect(capability.automationReady, isTrue);
    expect(capability.modes, <SimsMode>{SimsMode.major, SimsMode.full});
    expect(capability.families, containsAll(<String>['notifications', '1to1']));
    expect(capability.buildProfileId, 'android.production_fcm.fixed_wake');
    expect(capability.dependencies, <String>[
      'build.android.production_fcm.fixed_wake',
    ]);
    expect(capability.command, <String>[
      'dart',
      'run',
      'integration_test/scripts/run_android_notification_recovery_completion.dart',
    ]);
    expect(capability.assertionIds, <String>[
      'notifications.fixed_wake_live_route_selected',
      'notifications.direct_reaction_canonical_recovery',
      'notifications.generic_recovery_card_retired',
      'notifications.no_duplicate_or_second_tone',
      'notifications.state_and_route_restored',
      'notifications.zero_taps_zero_child_builds',
    ]);
    expect(
      capability.resources.map(
        (resource) => '${resource.name}:${resource.access.name}',
      ),
      <String>[
        'build:android.production_fcm.fixed_wake:read',
        'device:android-physical:exclusive',
        'device:android-emulator:exclusive',
        'relay-mutation:local-plan393-fixture:exclusive',
        'artifact:android-notification-recovery-completion:write',
      ],
    );
    expect(
      capability.artifactValidator,
      'integration_test/android_notification_recovery_completion_proof_test.dart',
    );
    expect(capability.declaredBuildException, isFalse);
  });

  test('TC-393-08 strict notification closure is exact and additive', () {
    final matches = manifest.capabilities
        .where(
          (capability) => capability.id == 'groups.strict_notification_closure',
        )
        .toList(growable: false);
    expect(matches, hasLength(1));
    final capability = matches.single;
    expect(capability.required, isTrue);
    expect(capability.active, isTrue);
    expect(capability.automationReady, isTrue);
    expect(capability.buildProfileId, 'android.production_fcm');
    expect(capability.dependencies, <String>['build.android.production_fcm']);
    expect(capability.command, <String>[
      'dart',
      'run',
      'integration_test/scripts/run_group_strict_notification_sims.dart',
    ]);
    expect(capability.assertionIds, <String>[
      'groups.strict_exact_chat_suppressed',
      'groups.strict_message_killed_card',
      'groups.strict_reaction_author_card',
      'groups.strict_relay_provenance',
      'groups.strict_state_restored',
    ]);
    expect(
      capability.artifactValidator,
      'integration_test/group_strict_notification_proof_test.dart',
    );
    expect(capability.declaredBuildException, isFalse);
  });
}
