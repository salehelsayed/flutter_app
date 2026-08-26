import 'dart:convert';

import 'package:flutter_app/core/debug/group_reaction_notification_ios_setup_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Plan 397 setup actions require both E2E mode and the exact profile',
    () {
      expect(
        allowsGroupReactionNotificationIosSetupActions(
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
        ),
        isTrue,
      );
      for (final tuple in const <(bool, String)>[
        (false, groupReactionNotificationIosSetupBuildProfile),
        (true, 'ios.device.production'),
        (true, 'ios.device.group_media_269'),
        (true, ''),
      ]) {
        expect(
          allowsGroupReactionNotificationIosSetupActions(
            e2eTestMode: tuple.$1,
            installedProfileId: tuple.$2,
          ),
          isFalse,
          reason: '$tuple',
        );
      }
    },
  );

  group('Plan 397 iOS launch-environment auto setup', () {
    test('accepts a trimmed username only for the exact signed profile', () {
      expect(
        resolveGroupReactionNotificationIosAutoSetupUsername(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: const <String, String>{
            groupReactionNotificationIosAutoSetupUsernameEnvironmentKey:
                '  recipient397  ',
          },
        ),
        'recipient397',
      );
      expect(
        resolveGroupReactionNotificationIosSetupReadinessAttempt(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: const <String, String>{
            groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
                '  setup-readiness-1234567890  ',
          },
        ),
        'setup-readiness-1234567890',
      );
    });

    test('rejects every platform, mode, profile, and value mismatch', () {
      const validEnvironment = <String, String>{
        groupReactionNotificationIosAutoSetupUsernameEnvironmentKey:
            'recipient397',
      };
      for (final input
          in const <
            ({
              bool isIos,
              bool e2eTestMode,
              String installedProfileId,
              Map<String, String> launchEnvironment,
            })
          >[
            (
              isIos: false,
              e2eTestMode: true,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
              launchEnvironment: validEnvironment,
            ),
            (
              isIos: true,
              e2eTestMode: false,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
              launchEnvironment: validEnvironment,
            ),
            (
              isIos: true,
              e2eTestMode: true,
              installedProfileId: 'ios.device.production',
              launchEnvironment: validEnvironment,
            ),
            (
              isIos: true,
              e2eTestMode: true,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
              launchEnvironment: <String, String>{},
            ),
            (
              isIos: true,
              e2eTestMode: true,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
              launchEnvironment: <String, String>{
                groupReactionNotificationIosAutoSetupUsernameEnvironmentKey:
                    '   ',
              },
            ),
          ]) {
        expect(
          resolveGroupReactionNotificationIosAutoSetupUsername(
            isIos: input.isIos,
            e2eTestMode: input.e2eTestMode,
            installedProfileId: input.installedProfileId,
            launchEnvironment: input.launchEnvironment,
          ),
          isNull,
          reason: '$input',
        );
        expect(
          resolveGroupReactionNotificationIosSetupReadinessAttempt(
            isIos: input.isIos,
            e2eTestMode: input.e2eTestMode,
            installedProfileId: input.installedProfileId,
            launchEnvironment: <String, String>{
              if (input.launchEnvironment.isNotEmpty)
                groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
                    'setup-readiness-1234567890',
            },
          ),
          input.isIos &&
                  input.e2eTestMode &&
                  input.installedProfileId ==
                      groupReactionNotificationIosSetupBuildProfile &&
                  input.launchEnvironment.isNotEmpty
              ? 'setup-readiness-1234567890'
              : null,
          reason: '$input',
        );
      }
      expect(
        resolveGroupReactionNotificationIosSetupReadinessAttempt(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: const <String, String>{
            groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
                'too short',
          },
        ),
        isNull,
      );
    });
  });

  test(
    'Plan 398 v3 entry gate fails closed before production bootstrap',
    () async {
      const attempt = 'plan398-v3-entry-attempt-0001';
      const attemptSha256 =
          '23f42dee7f4a9b1f9123621e31138ea81059ec307bd6fb4558c6c1ee1d96a104';
      final validEnvironment = <String, String>{
        groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
            attempt,
        groupReactionNotificationIosSetupEntryProfileEnvironmentKey:
            groupReactionNotificationIosSetupBuildProfile,
      };
      var nativeCalls = 0;
      Map<String, Object?>? lastArguments;

      Future<Object?> acknowledgeNative(Map<String, Object?> arguments) async {
        nativeCalls += 1;
        lastArguments = Map<String, Object?>.from(arguments);
        return buildGroupReactionNotificationIosSetupEntryReadinessReceipt(
          launchAttemptSha256: attemptSha256,
          stage: GroupReactionNotificationIosSetupEntryStage.dartMain,
        );
      }

      for (final ordinary
          in const <
            ({bool isIos, bool e2eTestMode, String installedProfileId})
          >[
            (
              isIos: false,
              e2eTestMode: true,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
            ),
            (
              isIos: true,
              e2eTestMode: false,
              installedProfileId: groupReactionNotificationIosSetupBuildProfile,
            ),
            (
              isIos: true,
              e2eTestMode: true,
              installedProfileId: 'ios.device.production',
            ),
          ]) {
        expect(
          await acknowledgeGroupReactionNotificationIosDartMainEntry(
            isIos: ordinary.isIos,
            e2eTestMode: ordinary.e2eTestMode,
            installedProfileId: ordinary.installedProfileId,
            launchEnvironment: validEnvironment,
            acknowledgeNative: acknowledgeNative,
          ),
          isFalse,
        );
      }
      expect(nativeCalls, 0);

      for (final invalidEnvironment in <Map<String, String>>[
        const <String, String>{},
        const <String, String>{
          groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
              attempt,
        },
        const <String, String>{
          groupReactionNotificationIosSetupEntryProfileEnvironmentKey:
              groupReactionNotificationIosSetupBuildProfile,
        },
        <String, String>{
          ...validEnvironment,
          groupReactionNotificationIosSetupReadinessAttemptEnvironmentKey:
              'too short',
        },
        <String, String>{
          ...validEnvironment,
          groupReactionNotificationIosSetupEntryProfileEnvironmentKey:
              'ios.device.production',
        },
      ]) {
        await expectLater(
          acknowledgeGroupReactionNotificationIosDartMainEntry(
            isIos: true,
            e2eTestMode: true,
            installedProfileId: groupReactionNotificationIosSetupBuildProfile,
            launchEnvironment: invalidEnvironment,
            acknowledgeNative: acknowledgeNative,
          ),
          throwsStateError,
        );
      }
      expect(nativeCalls, 0);

      expect(
        await acknowledgeGroupReactionNotificationIosDartMainEntry(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: validEnvironment,
          acknowledgeNative: acknowledgeNative,
        ),
        isTrue,
      );
      expect(nativeCalls, 1);
      expect(lastArguments, <String, Object?>{
        'schema': groupReactionNotificationIosSetupReadinessSchema,
        'profileId': groupReactionNotificationIosSetupBuildProfile,
        'launchAttemptSha256': attemptSha256,
      });
      expect(lastArguments.toString(), isNot(contains(attempt)));

      await expectLater(
        acknowledgeGroupReactionNotificationIosDartMainEntry(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: validEnvironment,
          acknowledgeNative: (_) async =>
              buildGroupReactionNotificationIosSetupEntryReadinessReceipt(
                launchAttemptSha256: attemptSha256,
                stage: GroupReactionNotificationIosSetupEntryStage
                    .nativeAppDelegate,
              ),
        ),
        throwsStateError,
      );
      await expectLater(
        acknowledgeGroupReactionNotificationIosDartMainEntry(
          isIos: true,
          e2eTestMode: true,
          installedProfileId: groupReactionNotificationIosSetupBuildProfile,
          launchEnvironment: validEnvironment,
          acknowledgeNative: (_) async =>
              throw StateError('native write failed'),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Plan 398 setup readiness receipt closes every stage and binds the exported identity',
    () async {
      const attemptSha256 =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const identitySha256 =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const rawUsername = 'raw-username-must-not-survive';
      const rawIdentity = 'raw-identity-must-not-survive';
      const rawQrPayload = 'raw-qr-must-not-survive';
      const rawException = 'raw-exception-must-not-survive';

      final nativeEntryReceipt =
          buildGroupReactionNotificationIosSetupEntryReadinessReceipt(
            launchAttemptSha256: attemptSha256,
            stage:
                GroupReactionNotificationIosSetupEntryStage.nativeAppDelegate,
          );
      final dartEntryReceipt =
          buildGroupReactionNotificationIosSetupEntryReadinessReceipt(
            launchAttemptSha256: attemptSha256,
            stage: GroupReactionNotificationIosSetupEntryStage.dartMain,
          );
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          nativeEntryReceipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition.dartEntryFailure,
      );
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          dartEntryReceipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .bootstrapDocumentsFailure,
      );

      final bootstrapReceipts = <Map<String, Object?>>[];
      for (final expectation
          in const <
            ({
              GroupReactionNotificationIosSetupBootstrapStage stage,
              String reason,
              GroupReactionNotificationIosSetupReadinessDisposition disposition,
            })
          >[
            (
              stage:
                  GroupReactionNotificationIosSetupBootstrapStage.shareLaunch,
              reason: 'bootstrap_share_launch_incomplete',
              disposition: GroupReactionNotificationIosSetupReadinessDisposition
                  .bootstrapShareLaunchFailure,
            ),
            (
              stage: GroupReactionNotificationIosSetupBootstrapStage.database,
              reason: 'bootstrap_database_incomplete',
              disposition: GroupReactionNotificationIosSetupReadinessDisposition
                  .bootstrapDatabaseFailure,
            ),
            (
              stage:
                  GroupReactionNotificationIosSetupBootstrapStage.identityStore,
              reason: 'bootstrap_identity_store_incomplete',
              disposition: GroupReactionNotificationIosSetupReadinessDisposition
                  .bootstrapIdentityStoreFailure,
            ),
            (
              stage: GroupReactionNotificationIosSetupBootstrapStage.autoSetup,
              reason: 'bootstrap_auto_setup_not_reached',
              disposition: GroupReactionNotificationIosSetupReadinessDisposition
                  .bootstrapAutoSetupFailure,
            ),
          ]) {
        final receipt =
            buildGroupReactionNotificationIosSetupBootstrapReadinessReceipt(
              launchAttemptSha256: attemptSha256,
              stage: expectation.stage,
            );
        bootstrapReceipts.add(receipt);
        expect(receipt['status'], 'FAIL');
        expect(receipt['reason'], expectation.reason);
        expect(
          classifyGroupReactionNotificationIosSetupReadinessReceipt(
            receipt,
            expectedLaunchAttemptSha256: attemptSha256,
          ),
          expectation.disposition,
        );
      }
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          <String, Object?>{
            ...bootstrapReceipts.first,
            'launchAttemptSha256': 'c' * 64,
          },
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition.invalid,
      );

      Future<
        ({Map<String, Object?> receipt, List<Map<String, Object?>> writes})
      >
      execute({
        String? username = rawUsername,
        bool initialIdentityPresent = false,
        bool generationSucceeds = true,
        bool reloadSucceeds = true,
        bool usernamePersistenceSucceeds = true,
        String? qrPayload = rawQrPayload,
        String? exportSha256 = identitySha256,
        bool throwDuringQr = false,
      }) async {
        var loadCount = 0;
        final writes = <Map<String, Object?>>[];
        final receipt =
            await runGroupReactionNotificationIosSetupReadiness<String>(
              launchAttemptSha256: attemptSha256,
              resolveUsername: () async => username,
              loadIdentity: () async {
                loadCount += 1;
                if (initialIdentityPresent) return rawIdentity;
                return loadCount == 1 || !reloadSucceeds ? null : rawIdentity;
              },
              generateIdentity: () async => generationSucceeds,
              persistUsername: (_, _) async => usernamePersistenceSucceeds,
              buildSignedQrPayload: (_) async {
                if (throwDuringQr) throw StateError(rawException);
                return qrPayload;
              },
              exportIdentity: (_, _) async => exportSha256,
              writeReceipt: (value) async {
                writes.add(Map<String, Object?>.from(value));
              },
            );
        return (receipt: receipt, writes: writes);
      }

      final profileFailure = await execute(username: null);
      expect(profileFailure.receipt['reason'], 'profile_launch_failed');
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          profileFailure.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .profileLaunchFailure,
      );

      final generationFailure = await execute(generationSucceeds: false);
      expect(generationFailure.receipt['reason'], 'identity_generation_failed');
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          generationFailure.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .identityGenerationFailure,
      );

      final reloadFailure = await execute(reloadSucceeds: false);
      expect(reloadFailure.receipt['reason'], 'identity_reload_failed');
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          reloadFailure.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .identityReloadFailure,
      );

      final qrFailure = await execute(
        initialIdentityPresent: true,
        throwDuringQr: true,
      );
      expect(qrFailure.receipt['reason'], 'qr_generation_failed');
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          qrFailure.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .qrGenerationFailure,
      );

      final exportFailure = await execute(
        initialIdentityPresent: true,
        exportSha256: null,
      );
      expect(exportFailure.receipt['reason'], 'identity_export_failed');
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          exportFailure.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .identityExportFailure,
      );

      final ready = await execute();
      expect(
        ready.writes.map((receipt) => receipt['stage']),
        <String>[
          'profile_launch',
          'identity_generation',
          'identity_reload',
          'qr_generation',
          'identity_export',
          'ready',
        ],
        reason: 'TC-398-08 setup readiness closed stage order',
      );
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          ready.receipt,
          expectedLaunchAttemptSha256: attemptSha256,
          expectedIdentityExportSha256: identitySha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition.ready,
      );
      final orderedReceipts = <Map<String, Object?>>[
        nativeEntryReceipt,
        dartEntryReceipt,
        ...bootstrapReceipts,
        ...ready.writes,
      ];
      for (var index = 1; index < orderedReceipts.length; index += 1) {
        expect(
          isAllowedGroupReactionNotificationIosSetupReadinessTransition(
            previous: orderedReceipts[index - 1],
            next: orderedReceipts[index],
          ),
          isTrue,
          reason:
              '${orderedReceipts[index - 1]['stage']} -> '
              '${orderedReceipts[index]['stage']}',
        );
      }
      expect(
        isAllowedGroupReactionNotificationIosSetupReadinessTransition(
          previous: nativeEntryReceipt,
          next: bootstrapReceipts.first,
        ),
        isFalse,
        reason: 'the Dart-main acknowledgement cannot be skipped',
      );
      expect(
        isAllowedGroupReactionNotificationIosSetupReadinessTransition(
          previous: dartEntryReceipt,
          next: nativeEntryReceipt,
        ),
        isFalse,
        reason: 'a retained v3 receipt cannot roll back an entry stage',
      );
      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          null,
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition
            .nativeEntryFailure,
      );

      expect(
        classifyGroupReactionNotificationIosSetupReadinessReceipt(
          <String, Object?>{
            ...dartEntryReceipt,
            'schema': 'mknoon.plan398.ios-setup-readiness.v2',
          },
          expectedLaunchAttemptSha256: attemptSha256,
        ),
        GroupReactionNotificationIosSetupReadinessDisposition.invalid,
      );

      final staleAttempt = <String, Object?>{
        ...ready.receipt,
        'launchAttemptSha256': 'c' * 64,
      };
      final contradictory = <String, Object?>{
        ...ready.receipt,
        'identityExported': false,
      };
      for (final invalid in <Map<String, Object?>>[
        staleAttempt,
        contradictory,
      ]) {
        expect(
          classifyGroupReactionNotificationIosSetupReadinessReceipt(
            invalid,
            expectedLaunchAttemptSha256: attemptSha256,
            expectedIdentityExportSha256: identitySha256,
          ),
          GroupReactionNotificationIosSetupReadinessDisposition.invalid,
        );
      }

      final serialized = jsonEncode(<Object?>[
        nativeEntryReceipt,
        dartEntryReceipt,
        ...bootstrapReceipts,
        ...profileFailure.writes,
        ...generationFailure.writes,
        ...reloadFailure.writes,
        ...qrFailure.writes,
        ...exportFailure.writes,
        ...ready.writes,
      ]);
      for (final secret in const <String>[
        rawUsername,
        rawIdentity,
        rawQrPayload,
        rawException,
      ]) {
        expect(serialized, isNot(contains(secret)));
      }
      for (final receipt in ready.writes) {
        expect(
          receipt['schema'],
          groupReactionNotificationIosSetupReadinessSchema,
        );
        expect(receipt['status'], anyOf('PASS', 'FAIL'));
        expect(receipt['containsSecrets'], isFalse);
        expect(receipt['nativeEntryAcknowledged'], isTrue);
        expect(receipt['dartEntryAcknowledged'], isTrue);
        expect(receipt.keys, isNot(contains('error')));
      }
      for (final receipt in orderedReceipts) {
        expect(receipt.keys.toSet(), <String>{
          'schema',
          'status',
          'stage',
          'reason',
          'profileId',
          'launchAttemptSha256',
          'nativeEntryAcknowledged',
          'dartEntryAcknowledged',
          'launchInputPresent',
          'identityInitiallyPresent',
          'generationAttempted',
          'generationSucceeded',
          'reloadSucceeded',
          'qrPayloadBuilt',
          'identityExported',
          'identityExportSha256',
          'containsSecrets',
        });
      }
    },
  );
}
