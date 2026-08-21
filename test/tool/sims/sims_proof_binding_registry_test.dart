import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';

const _captureOwnedBindings = <String>{
  'integration_test/inbox_replay_before_ack_custody_harness.dart',
  'integration_test/notif_push_payload_persist_harness.dart',
  'integration_test/notification_tap_message_visible_proof_test.dart',
  'integration_test/intro_accept_notification_android_proof_test.dart',
  'integration_test/group_notification_projection_android_proof_test.dart',
  'integration_test/group_strict_notification_proof_test.dart',
  'integration_test/group_muted_notification_proof_test.dart',
  'integration_test/android_notification_recovery_completion_proof_test.dart',
  'integration_test/scripts/validate_group_reaction_notification_artifacts.dart',
};

const _deletedProofFiles = <String>{
  'integration_test/connectivity_restore_inbox_drain_proof_test.dart',
  'integration_test/keepalive_drop_skip_direct_proof_test.dart',
  'integration_test/wake_token_distribution_proof_test.dart',
  'integration_test/dcutr_upgrade_proof_test.dart',
};

const _manualProofRegistry = 'Test-Flight-Improv/sims-manual-proof-registry.md';

const _manifestOwnedSupportFacades = <String>{
  'integration_test/scripts/run_1to1_device_real.dart',
  'integration_test/scripts/run_notification_tap_device_real.dart',
};

const _groupNotificationProjectionSupport = <String, String>{
  'integration_test/scripts/run_group_notification_projection_android.dart':
      'typed Sims adapter for Android group notification projection durability; manifest owns execution',
  'integration_test/scripts/group_notification_projection_android_criteria.dart':
      '330 strict Android group notification projection raw-evidence criteria',
};

const _groupStrictNotificationSupport = <String, String>{
  'integration_test/scripts/run_group_strict_notification_sims.dart':
      'typed Sims adapter for Android strict group notification closure; manifest owns execution',
  'integration_test/scripts/group_strict_notification_criteria.dart':
      '393 strict Android group notification raw-evidence criteria',
};

const _groupMutedNotificationSupport = <String, String>{
  'integration_test/scripts/run_group_muted_notification_android.dart':
      'typed Sims adapter for Android muted-group notification suppression; manifest owns execution',
  'integration_test/scripts/group_muted_notification_android_criteria.dart':
      '379 strict Android muted-group notification suppression raw-evidence criteria',
};

const _androidRecoveryCompletionSupport = <String, String>{
  'integration_test/scripts/run_android_notification_recovery_completion_sims.dart':
      '393 disposable encrypted Redis/FCM relay wrapper prepares the central fixed-wake artifact before manifest execution',
  'integration_test/scripts/run_android_notification_recovery_completion.dart':
      '393 manifest-owned physical-sender emulator-receiver fixed-wake recovery adapter',
  'integration_test/scripts/android_notification_recovery_completion_criteria.dart':
      '393 strict content-addressed fixed-wake recovery evidence criteria',
};

const _directMediaBlobCustodySupport = <String, String>{
  'integration_test/scripts/run_direct_media_blob_custody_sims.dart':
      '347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract',
  'integration_test/scripts/android_direct_media_blob_custody_campaign.dart':
      '347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract',
  'integration_test/scripts/android_direct_media_blob_custody_device_action.dart':
      '347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract',
  'integration_test/support/android_direct_media_blob_custody_campaign_contract.dart':
      '347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract',
  'integration_test/support/android_direct_media_blob_custody_evidence.dart':
      '347 manifest-owned disposable-relay adapter, concrete Android action campaign, or hash-only evidence contract',
  'lib/debug/android_direct_media_blob_custody_e2e.dart':
      '347 profile-gated direct-media custody endpoint and pure host protocol',
  'lib/core/debug/android_direct_media_blob_custody_e2e_protocol.dart':
      '347 profile-gated direct-media custody endpoint and pure host protocol',
};

void main() {
  late SimsManifest manifest;
  late List<_DiscoveryRecord> discovery;

  setUpAll(() {
    manifest = SimsManifest.loadSync(File('tool/sims/critical_features.json'));
    discovery = _readDiscoveryRecords();
  });

  test(
    'proof bindings are support owned by captures and absent from default executable plan',
    () {
      for (final path in _captureOwnedBindings) {
        final records = discovery.where(
          (record) =>
              record.path == path &&
              record.category == 'support' &&
              record.kind == 'support' &&
              record.note.contains('capture-owned'),
        );
        expect(
          records,
          hasLength(1),
          reason: '$path must have one capture-owned support record',
        );

        final owners = manifest.capabilities.where(
          (capability) => capability.artifactValidators.contains(path),
        );
        expect(
          owners,
          hasLength(1),
          reason: '$path must be bound to exactly one owning capture',
        );
        final owner = owners.single;
        expect(
          owner.artifactRequired,
          isTrue,
          reason: '${owner.id} must fail closed when its artifact is absent',
        );
        expect(
          owner.participatesIn(SimsMode.major),
          isTrue,
          reason: '${owner.id} must retain its major capture ownership',
        );
        expect(
          _commandReferences(owner.command, path),
          isFalse,
          reason: '$path is a post-capture validator, not the capture command',
        );
      }

      final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
      for (final path in _captureOwnedBindings) {
        expect(
          major.rows.where((row) => _commandReferences(row.command, path)),
          isEmpty,
          reason: '$path must not become an executable major row',
        );
      }
    },
  );

  test(
    'deleted placeholder files and print-only catalog success are forbidden',
    () {
      expect(
        FileSystemEntity.typeSync(_manualProofRegistry, followLinks: false),
        FileSystemEntityType.file,
      );
      for (final path in _deletedProofFiles) {
        expect(
          FileSystemEntity.typeSync(path, followLinks: false),
          FileSystemEntityType.notFound,
          reason: '$path must not remain an executable-looking test file',
        );
        expect(
          _executableDiscoveryRecords(discovery, path),
          isEmpty,
          reason: '$path is requirement history, not an executable proof',
        );
        expect(
          manifest.capabilities.where(
            (capability) =>
                capability.active &&
                _commandReferences(capability.command, path),
          ),
          isEmpty,
          reason: '$path must not be selectable from an active manifest plan',
        );
      }

      for (final id in const <String>{
        'android.connectivity_restore_inbox_drain',
        'android.keepalive_drop_skip_direct',
        'android.wake_token_directionality',
      }) {
        expect(
          discovery.where(
            (record) =>
                record.path == _manualProofRegistry &&
                record.category == 'implemented' &&
                record.kind == 'capability' &&
                record.note.startsWith('id=$id '),
          ),
          hasLength(1),
          reason: '$id must remain archived in the non-executable registry',
        );
      }

      for (final path in _manifestOwnedSupportFacades) {
        final supportRecords = discovery.where(
          (record) =>
              record.path == path &&
              record.category == 'support' &&
              record.kind == 'support',
        );
        expect(
          supportRecords,
          hasLength(1),
          reason: '$path must remain support-only in compatibility discovery',
        );
        expect(_executableDiscoveryRecords(discovery, path), isEmpty);

        final listResult = Process.runSync('dart', <String>[
          path,
          '--list-scenarios',
        ]);
        expect(
          listResult.exitCode,
          0,
          reason:
              '$path must retain deterministic metadata discovery:\n'
              '${listResult.stderr}',
        );

        final runResult = Process.runSync('dart', <String>[path]);
        expect(
          runResult.exitCode,
          78,
          reason:
              '$path cannot print recipes and return a false PASS:\n'
              'stdout: ${runResult.stdout}\n'
              'stderr: ${runResult.stderr}',
        );
      }
    },
  );

  test(
    'VC-02 DCUtR capability remains activation-gated after placeholder removal',
    () {
      const ids = <String>{
        'vc02.dcutr_upgrade',
        'vc02.dcutr_symmetric_cgnat_negative',
      };

      final allSelectedIds = <String>{
        for (final mode in SimsMode.values)
          ...SimsPlanner(manifest).compile(mode: mode).selectedIds,
      };

      for (final id in ids) {
        final capability = manifest.capabilityById(id);
        expect(capability, isNotNull, reason: '$id must not be deleted');
        expect(
          capability!.active,
          isFalse,
          reason: '$id is not implemented yet',
        );
        expect(
          capability.required,
          isFalse,
          reason: '$id cannot block releases before VC-01/VC-02 activation',
        );
        expect(
          capability.families,
          contains('voice-video-1to1'),
          reason: '$id must remain owned by the future 1:1 call feature',
        );
        expect(allSelectedIds, isNot(contains(id)));
        expect(
          _commandReferences(
            capability.command,
            'integration_test/dcutr_upgrade_proof_test.dart',
          ),
          isFalse,
          reason: '$id cannot reactivate the inert placeholder',
        );

        final inactiveRecords = discovery.where(
          (record) =>
              record.category == 'inactive' &&
              record.kind == 'capability' &&
              record.note.startsWith('id=$id '),
        );
        expect(
          inactiveRecords,
          hasLength(1),
          reason: '$id must remain visible in compatibility discovery',
        );
      }

      final symmetric = manifest.capabilityById(
        'vc02.dcutr_symmetric_cgnat_negative',
      );
      expect(
        symmetric!.allowedNaReason,
        targetUnavailableNaReason,
        reason:
            'symmetric-CGNAT may become N/A only when that topology is absent',
      );
    },
  );

  test(
    'private-media outbox restore proof is manifest-owned and discoverable',
    () {
      const capabilityId = 'android.connectivity_restore_media_outbox';
      const runner =
          'integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart';
      final capability = manifest.capabilityById(capabilityId);

      expect(capability, isNotNull);
      expect(capability!.active, isTrue);
      expect(capability.required, isTrue);
      expect(capability.participatesIn(SimsMode.major), isTrue);
      expect(capability.command, <String>['dart', 'run', runner]);
      expect(capability.artifactValidators, <String>[
        'validatePrivateMediaOutboxRestoreArtifact',
      ]);
      expect(
        discovery.where(
          (record) =>
              record.path == runner &&
              record.category == 'support' &&
              record.kind == 'support' &&
              record.note.contains('production private-media outbox restore'),
        ),
        hasLength(1),
      );
      expect(
        discovery.where(
          (record) =>
              record.path == _manualProofRegistry &&
              record.category == 'implemented' &&
              record.kind == 'capability' &&
              record.note.startsWith('id=$capabilityId '),
        ),
        hasLength(1),
      );

      final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
      expect(major.selectedIds, contains(capabilityId));
      expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
    },
  );

  test(
    'group notification projection durability is manifest-owned and discoverable',
    () {
      const capabilityId = 'groups.notification_projection_durability';
      const runner =
          'integration_test/scripts/run_group_notification_projection_android.dart';
      final capability = manifest.capabilityById(capabilityId);

      expect(capability, isNotNull);
      expect(capability!.toJson(), <String, Object?>{
        'id': capabilityId,
        'owner': 'groups',
        'proofBoundary': 'android.group-notification-projection-durability',
        'assertions': <String>[
          'groups.two_group_read_zero_exact_cancel',
          'groups.killed_group_photo_message',
          'groups.group_reaction_photo_semantic_kind',
          'groups.group_reaction_video_semantic_kind',
          'groups.group_reaction_voice_message_semantic_kind',
          'groups.group_projection_stable_single_card',
        ],
        'lane': 'reliability',
        'modes': <String>['full', 'major'],
        'families': <String>['group', 'notifications'],
        'required': true,
        'command': <String>['dart', 'run', runner],
        'buildProfile': 'android.production_fcm',
        'dependencies': <String>['build.android.production_fcm'],
        'resources': <Map<String, String>>[
          <String, String>{
            'name': 'build:android.production_fcm',
            'access': 'read',
          },
          <String, String>{
            'name': 'device:android-physical',
            'access': 'exclusive',
          },
          <String, String>{
            'name': 'device:android-emulator',
            'access': 'exclusive',
          },
          <String, String>{
            'name': 'relay-mutation:staging',
            'access': 'exclusive',
          },
          <String, String>{
            'name': 'artifact:group-notification-projection',
            'access': 'write',
          },
        ],
        'targetCapabilities': <String>[
          'android.physical',
          'android.emulator',
          'credentials.fcm',
          'relay.staging',
        ],
        'allowedNaReason': targetUnavailableNaReason,
        'artifactRequired': true,
        'artifactValidator':
            'integration_test/group_notification_projection_android_proof_test.dart',
        'active': true,
        'declaredBuildException': false,
        'automationReady': true,
      });

      for (final entry in _groupNotificationProjectionSupport.entries) {
        expect(
          discovery.where(
            (record) =>
                record.path == entry.key &&
                record.category == 'support' &&
                record.kind == 'support' &&
                record.note == entry.value,
          ),
          hasLength(1),
          reason: '${entry.key} must remain one exact support-only record',
        );
        expect(_executableDiscoveryRecords(discovery, entry.key), isEmpty);
      }

      final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
      expect(major.selectedIds, contains(capabilityId));
      expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
    },
  );

  test('TC-393-08 strict group notification closure is manifest-owned', () {
    const capabilityId = 'groups.strict_notification_closure';
    const runner =
        'integration_test/scripts/run_group_strict_notification_sims.dart';
    final capability = manifest.capabilityById(capabilityId);

    expect(capability, isNotNull);
    expect(capability!.assertionIds, <String>[
      'groups.strict_exact_chat_suppressed',
      'groups.strict_message_killed_card',
      'groups.strict_reaction_author_card',
      'groups.strict_relay_provenance',
      'groups.strict_state_restored',
    ]);
    expect(capability.command, <String>['dart', 'run', runner]);
    expect(capability.buildProfileId, 'android.production_fcm');
    expect(capability.dependencies, <String>['build.android.production_fcm']);
    expect(
      capability.artifactValidator,
      'integration_test/group_strict_notification_proof_test.dart',
    );
    expect(capability.automationReady, isTrue);

    for (final entry in _groupStrictNotificationSupport.entries) {
      expect(
        discovery.where(
          (record) =>
              record.path == entry.key &&
              record.category == 'support' &&
              record.kind == 'support' &&
              record.note == entry.value,
        ),
        hasLength(1),
      );
      expect(_executableDiscoveryRecords(discovery, entry.key), isEmpty);
    }
    final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
    expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
  });

  test('muted-group notification campaign is manifest-owned and '
      'discoverable', () {
    const capabilityId = 'groups.muted_notification_campaign';
    const runner =
        'integration_test/scripts/run_group_muted_notification_android.dart';
    final capability = manifest.capabilityById(capabilityId);

    expect(capability, isNotNull);
    expect(capability!.toJson(), <String, Object?>{
      'id': capabilityId,
      'owner': 'groups',
      'proofBoundary': 'android.group-muted-notification-suppression',
      'assertions': <String>[
        'groups.muted_live_message_no_card',
        'groups.muted_background_reaction_no_card',
        'groups.muted_unread_preserved',
        'groups.muted_excluded_from_canonical_badge',
        'groups.muted_delivery_unharmed',
        'groups.killed_app_group_text_card',
      ],
      'lane': 'reliability',
      'modes': <String>['full', 'major'],
      'families': <String>['group', 'notifications'],
      'required': true,
      'command': <String>['dart', 'run', runner],
      'buildProfile': 'android.production_fcm',
      'dependencies': <String>['build.android.production_fcm'],
      'resources': <Map<String, String>>[
        <String, String>{
          'name': 'build:android.production_fcm',
          'access': 'read',
        },
        <String, String>{
          'name': 'device:android-physical',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'device:android-emulator',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'relay-mutation:staging',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'artifact:group-muted-notification',
          'access': 'write',
        },
      ],
      'targetCapabilities': <String>[
        'android.physical',
        'android.emulator',
        'credentials.fcm',
        'relay.staging',
      ],
      'allowedNaReason': targetUnavailableNaReason,
      'artifactRequired': true,
      'artifactValidator':
          'integration_test/group_muted_notification_proof_test.dart',
      'active': true,
      'declaredBuildException': false,
      'automationReady': true,
    });

    for (final entry in _groupMutedNotificationSupport.entries) {
      expect(
        discovery.where(
          (record) =>
              record.path == entry.key &&
              record.category == 'support' &&
              record.kind == 'support' &&
              record.note == entry.value,
        ),
        hasLength(1),
        reason: '${entry.key} must remain one exact support-only record',
      );
      expect(_executableDiscoveryRecords(discovery, entry.key), isEmpty);
    }

    final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
    expect(major.selectedIds, contains(capabilityId));
    expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
  });

  test('TC-393-12 Android fixed-wake recovery is manifest-owned and fail-closed', () {
    const capabilityId = 'notifications.android_recovery_completion';
    const runner =
        'integration_test/scripts/run_android_notification_recovery_completion.dart';
    final capability = manifest.capabilityById(capabilityId);

    expect(capability, isNotNull);
    expect(capability!.toJson(), <String, Object?>{
      'id': capabilityId,
      'owner': 'notifications',
      'proofBoundary':
          'android.fixed-wake.real-relay.ephemeral-redis-fcm.direct-reaction-recovery',
      'assertions': <String>[
        'notifications.fixed_wake_live_route_selected',
        'notifications.direct_reaction_canonical_recovery',
        'notifications.generic_recovery_card_retired',
        'notifications.no_duplicate_or_second_tone',
        'notifications.state_and_route_restored',
        'notifications.zero_taps_zero_child_builds',
      ],
      'lane': 'reliability',
      'modes': <String>['full', 'major'],
      'families': <String>['1to1', 'notifications'],
      'required': true,
      'command': <String>['dart', 'run', runner],
      'buildProfile': 'android.production_fcm.fixed_wake',
      'dependencies': <String>['build.android.production_fcm.fixed_wake'],
      'resources': <Map<String, String>>[
        <String, String>{
          'name': 'build:android.production_fcm.fixed_wake',
          'access': 'read',
        },
        <String, String>{
          'name': 'device:android-physical',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'device:android-emulator',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'relay-mutation:local-plan393-fixture',
          'access': 'exclusive',
        },
        <String, String>{
          'name': 'artifact:android-notification-recovery-completion',
          'access': 'write',
        },
      ],
      'targetCapabilities': <String>[
        'android.physical',
        'android.emulator',
        'credentials.fcm',
        'relay.staging',
      ],
      'allowedNaReason': targetUnavailableNaReason,
      'artifactRequired': true,
      'artifactValidator':
          'integration_test/android_notification_recovery_completion_proof_test.dart',
      'active': true,
      'declaredBuildException': false,
      'automationReady': true,
    });

    for (final entry in _androidRecoveryCompletionSupport.entries) {
      expect(
        discovery.where(
          (record) =>
              record.path == entry.key &&
              record.category == 'support' &&
              record.kind == 'support' &&
              record.note == entry.value,
        ),
        hasLength(1),
        reason: '${entry.key} must remain one exact support-only record',
      );
      expect(_executableDiscoveryRecords(discovery, entry.key), isEmpty);
    }

    final runnerSource = File(runner).readAsStringSync();
    expect(runnerSource, isNot(contains('force-stop')));
    expect(runnerSource, isNot(contains("'input', 'tap'")));
    expect(runnerSource, isNot(contains('flutter build')));
    expect(runnerSource, isNot(contains('gradlew')));
    expect(
      runnerSource,
      contains('androidNotificationRecoveryCompletionArtifactEnvironment'),
    );
    expect(runnerSource, contains("'--fixed-wake-recovery'"));
    expect(runnerSource, contains('AndroidAppStateGuard.capture'));
    expect(runnerSource, contains('stateGuard.restoreAll'));
    expect(
      runnerSource,
      contains('validateAndroidNotificationRecoveryRawArtifact'),
    );
    expect(
      runnerSource.indexOf('final credentialPath ='),
      lessThan(runnerSource.indexOf('final artifactPath =')),
      reason: 'relay/FCM credentials must fail before APK/device mutation',
    );
    expect(runnerSource, isNot(contains('21071FDF600CSC')));
    expect(runnerSource, isNot(contains('emulator-5554')));
    expect(
      runnerSource,
      isNot(contains('NotificationRecoveryCompletionReceiver')),
    );
    expect(capability.automationReady, isTrue);

    final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
    expect(major.selectedIds, contains(capabilityId));
    expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
  });

  test(
    'TC-347-09 direct-media custody is one manifest-owned Android-pair proof',
    () {
      const capabilityId = 'android.direct_media_blob_custody';
      const dispatcher = 'integration_test/scripts/run_1to1_device_real.dart';
      final capability = manifest.capabilityById(capabilityId);

      expect(capability, isNotNull);
      expect(capability!.active, isTrue);
      expect(capability.required, isTrue);
      expect(capability.participatesIn(SimsMode.major), isTrue);
      expect(capability.command, <String>[
        'dart',
        'run',
        dispatcher,
        '--scenario',
        capabilityId,
      ]);
      expect(capability.buildProfileId, 'android.e2e.direct_media_custody');
      expect(capability.dependencies, <String>[
        'build.android.e2e.direct_media_custody',
      ]);
      expect(capability.artifactValidators, <String>[
        'validateDirectMediaBlobCustodyArtifact',
      ]);

      for (final entry in _directMediaBlobCustodySupport.entries) {
        expect(
          discovery.where(
            (record) =>
                record.path == entry.key &&
                record.category == 'support' &&
                record.kind == 'support' &&
                record.note == entry.value,
          ),
          hasLength(1),
          reason: '${entry.key} must remain one support-only record',
        );
        expect(_executableDiscoveryRecords(discovery, entry.key), isEmpty);
      }
      expect(
        discovery.where(
          (record) =>
              record.path == _manualProofRegistry &&
              record.category == 'implemented' &&
              record.kind == 'capability' &&
              record.note.startsWith('id=$capabilityId '),
        ),
        hasLength(1),
      );

      final listed = Process.runSync('dart', const <String>[
        dispatcher,
        '--scenario',
        capabilityId,
        '--list-scenarios',
      ]);
      expect(listed.exitCode, 0, reason: '${listed.stderr}');
      expect('${listed.stdout}'.trim(), capabilityId);

      final major = SimsPlanner(manifest).compile(mode: SimsMode.major);
      expect(major.selectedIds, contains(capabilityId));
      expect(major.rows.where((row) => row.id == capabilityId), hasLength(1));
    },
  );
}

List<_DiscoveryRecord> _readDiscoveryRecords() {
  final result = Process.runSync('bash', const <String>[
    'scripts/check_reliability_simulation_discovery.sh',
    '--records-tsv',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Reliability discovery failed (${result.exitCode}):\n${result.stderr}',
    );
  }

  return (result.stdout as String)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map((line) {
        final columns = line.split('\t');
        if (columns.length != 4) {
          throw FormatException('Invalid discovery TSV record: $line');
        }
        return _DiscoveryRecord(
          category: columns[0],
          kind: columns[1],
          path: columns[2],
          note: columns[3],
        );
      })
      .toList(growable: false);
}

Iterable<_DiscoveryRecord> _executableDiscoveryRecords(
  List<_DiscoveryRecord> records,
  String path,
) => records.where(
  (record) =>
      record.path == path &&
      const <String>{
        '1to1',
        'group',
        'intro',
        'move-feature',
      }.contains(record.category) &&
      const <String>{'runner', 'test'}.contains(record.kind),
);

bool _commandReferences(List<String> command, String path) =>
    command.any((argument) => argument == path || argument.contains(path));

class _DiscoveryRecord {
  const _DiscoveryRecord({
    required this.category,
    required this.kind,
    required this.path,
    required this.note,
  });

  final String category;
  final String kind;
  final String path;
  final String note;
}
