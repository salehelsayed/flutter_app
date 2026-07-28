import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_group_media_reliability_controller.dart';
import '../../integration_test/scripts/group_media_reliability_criteria.dart';
import '../../integration_test/scripts/group_media_reliability_runner_contract.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/group_media_android_disposable_app.dart';

void main() {
  test(
    'P269 Android UI proof requires explicit awake and unlocked evidence',
    () {
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake\nmInteractive=true',
          windowPolicyDump: 'mShowingLockscreen=false\nmInputRestricted=false',
        ),
        isTrue,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Asleep\nmInteractive=false',
          windowPolicyDump: 'mShowingLockscreen=false',
        ),
        isFalse,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake',
          windowPolicyDump: 'showing=true\nmInputRestricted=true',
        ),
        isFalse,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake',
          windowPolicyDump: 'no keyguard facts',
        ),
        isFalse,
      );
    },
  );

  test(
    'P269 target preflight rejects a wireless sender before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(
        inventory: _androidInventory(
          senderRows: const <String>[
            'pixel-usb device product:pixel transport_id:1',
          ],
        ),
      );
    },
  );

  test(
    'P269 target preflight rejects a sender reporting qemu one before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(senderQemu: '1');
    },
  );

  test(
    'P269 target preflight rejects a noncanonical sender qemu value before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(senderQemu: 'false');
    },
  );

  test(
    'P269 target preflight rejects duplicate rows for either role before any mutation',
    () async {
      for (final inventory in <String>[
        _androidInventory(
          senderRows: const <String>[
            'pixel-usb device usb:1-1 product:pixel transport_id:1',
            'pixel-usb device usb:1-1 product:pixel transport_id:1',
          ],
        ),
        _androidInventory(
          receiverRows: const <String>[
            'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
            'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
          ],
        ),
      ]) {
        await _expectAndroidTargetPreflightBlocked(inventory: inventory);
      }
    },
  );

  test(
    'P269 dedicated APK rejects wrong manifest before any ADB mutation',
    () async {
      final fixture = _AndroidDisposableFixture(
        manifestApplicationId: 'com.mknoon.app',
      );
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.app.installPreparedArtifact(),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );

      expect(fixture.runner.adbCommands, isEmpty);
      expect(fixture.mutationCount, 0);
    },
  );

  test(
    'P269 dedicated APK install and reset leave app installed without destructive commands',
    () async {
      final fixture = _AndroidDisposableFixture();
      addTearDown(fixture.dispose);

      await fixture.app.installPreparedArtifact();
      final pre = await fixture.app.reset('pre');
      final preRawStdout = fixture.runner.receiptStdout['pre']!;
      final repeatedPre = await fixture.app.reset('pre');
      final post = await fixture.app.reset('post');

      expect(pre.phase, 'pre');
      expect(post.phase, 'post');
      expect(pre.sha256Digest, isNot(post.sha256Digest));
      expect(repeatedPre.sha256Digest, isNot(pre.sha256Digest));
      expect(
        pre.sha256Digest,
        sha256.convert(utf8.encode(preRawStdout)).toString(),
      );
      expect(
        post.sha256Digest,
        sha256
            .convert(utf8.encode(fixture.runner.receiptStdout['post']!))
            .toString(),
      );
      expect(fixture.mutationCount, 1);
      final journal = fixture.runner.adbCommands.join('\n');
      expect(journal, contains('install -r -d -t'));
      expect(
        journal,
        contains('shell pm path $groupMediaAndroidDisposablePackageId'),
      );
      expect(journal, isNot(contains('com.mknoon.app')));
      expect(journal, isNot(contains('uninstall')));
      expect(journal, isNot(contains('pm clear')));
      expect(journal, isNot(matches(RegExp(r'\brm\s+-(?:rf|fr|r|R)\b'))));
    },
  );

  test(
    'P269 dedicated APK rejects installed mismatch and stale receipt',
    () async {
      final mismatch = _AndroidDisposableFixture(installedDigestMatches: false);
      addTearDown(mismatch.dispose);
      await expectLater(
        mismatch.app.installPreparedArtifact(),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );

      final stale = _AndroidDisposableFixture(staleReceipt: true);
      addTearDown(stale.dispose);
      await stale.app.installPreparedArtifact();
      await expectLater(
        stale.app.reset('pre'),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );
    },
  );

  test(
    'P269 host proves old PID death and launcher-only fresh PID without sleeps or identity clearing',
    () async {
      final runner = _ProcessRunner();
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 4,
      );

      final evidence = await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
      );

      expect(evidence.oldPid, '111');
      expect(evidence.freshPid, '222');
      expect(evidence.oldPidGone, isTrue);
      expect(
        evidence.launcherComponent,
        '$groupMediaAndroidDisposablePackageId/.MainActivity',
      );
      expect(evidence.relaunchedWithoutGroupRoute, isTrue);
      expect(
        runner.commands,
        containsAllInOrder(<String>[
          'adb -s emulator-5554 shell cmd package resolve-activity --brief --user 0 $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am force-stop $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am start -W -n $groupMediaAndroidDisposablePackageId/.MainActivity',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
        ]),
      );
      final journal = runner.commands.join('\n');
      expect(journal, isNot(contains('flutter build')));
      expect(journal, isNot(contains('flutter drive')));
      expect(journal, isNot(contains('uninstall')));
      expect(journal, isNot(contains('pm clear')));
      expect(journal, isNot(contains('sleep')));
      expect(journal, isNot(contains('/group/')));
    },
  );

  test(
    'P269 launcher timeout still requires the exact component and a fresh PID',
    () async {
      final runner = _ProcessRunner(launchStatus: 'timeout');
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 4,
      );

      final evidence = await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
      );

      expect(evidence.oldPid, '111');
      expect(evidence.freshPid, '222');
      expect(evidence.oldPidGone, isTrue);
      expect(evidence.relaunchedWithoutGroupRoute, isTrue);
    },
  );

  test(
    'P269 stopped-window recovery staging remains after PID death and before launcher relaunch',
    () async {
      final runner = _ProcessRunner(withStoppedWindowStage: true);
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 5,
      );

      await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
        afterStoppedBeforeLaunch: () async {
          runner.commands.add('HOST stage receiver_recover');
        },
      );

      expect(
        runner.commands,
        containsAllInOrder(<String>[
          'adb -s emulator-5554 shell am force-stop $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'HOST stage receiver_recover',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am start -W -n $groupMediaAndroidDisposablePackageId/.MainActivity',
        ]),
      );

      final source = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<AndroidGroupMediaProcessTransitionEvidence> '
        'forceStopAndRelaunch',
      );
      final methodEnd = source.indexOf(
        'Future<String> launchValidatedLauncher',
        methodStart,
      );
      final method = source.substring(methodStart, methodEnd);
      final deathObserved = method.indexOf('final oldPidGone = await _pollPid');
      final stage = method.indexOf('await afterStoppedBeforeLaunch();');
      final stillStopped = method.indexOf(
        'final pidAfterStaging = await _readPid',
      );
      final launch = method.indexOf('await _launchResolvedComponent');
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));
      expect(deathObserved, greaterThanOrEqualTo(0));
      expect(stage, greaterThan(deathObserved));
      expect(stillStopped, greaterThan(stage));
      expect(launch, greaterThan(stillStopped));
    },
  );

  test(
    'P269 fixture publishes JPEG last and host settles sender before barrier observation',
    () {
      final fixtureSource = File(
        'lib/core/debug/group_media_reliability_e2e_main_actions.dart',
      ).readAsStringSync();
      final specsStart = fixtureSource.indexOf(
        'final specs = <({String kind, String mime, String? asset})>[',
      );
      final specsEnd = fixtureSource.indexOf(
        'final uploads = <String, int>{};',
        specsStart,
      );
      final specs = fixtureSource.substring(specsStart, specsEnd);
      final mp4 = specs.indexOf("kind: 'mp4'");
      final voice = specs.indexOf("kind: 'voice'");
      final jpeg = specs.indexOf("kind: 'jpeg'");
      expect(specsStart, greaterThanOrEqualTo(0));
      expect(specsEnd, greaterThan(specsStart));
      expect(mp4, greaterThanOrEqualTo(0));
      expect(voice, greaterThan(mp4));
      expect(jpeg, greaterThan(voice));
      expect(fixtureSource, contains('allowedPeers.length != 2'));
      final lease = fixtureSource.indexOf(
        'mediaUploadInFlightTracker.tryClaimAll(',
      );
      final parentSave = fixtureSource.indexOf(
        'await groupMessageRepository.saveMessage(expectedParent);',
      );
      final productionLeaf = fixtureSource.indexOf(
        'await runForegroundGroupUploadLeaf(',
      );
      final publication = fixtureSource.indexOf(
        'final result = await sendGroupMessage(',
        productionLeaf,
      );
      expect(lease, greaterThan(specsEnd));
      expect(parentSave, greaterThan(lease));
      expect(productionLeaf, greaterThan(parentSave));
      expect(publication, greaterThan(productionLeaf));
      final publicationEnd = fixtureSource.indexOf(
        'if (result.\$2?.id != messageId',
        publication,
      );
      expect(publicationEnd, greaterThan(publication));
      expect(
        fixtureSource.substring(publication, publicationEnd),
        contains('timestamp: now,'),
        reason:
            'the pre-saved optimistic parent and canonical send must share '
            'one timestamp so message-id reuse is authorized',
      );
      expect(fixtureSource, contains("downloadStatus: 'upload_pending'"));
      expect(fixtureSource, contains('messageIds.values.toSet().length != 3'));
      expect(
        fixtureSource,
        contains('attachmentIds.values.toSet().length != 3'),
      );
      expect(fixtureSource, contains('required String transportPeerId'));
      expect(
        fixtureSource,
        contains('groupMediaReliabilityDatabasePathFingerprint('),
      );
      expect(fixtureSource, contains('databasePath: database.path'));
      expect(
        fixtureSource,
        isNot(contains('sha256.convert(database.path.codeUnits)')),
      );

      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
      );
      expect(compositionSource, contains('transportPeerId: transportPeerId'));

      final productionLeafSource = File(
        'lib/features/groups/application/foreground_group_media_upload.dart',
      ).readAsStringSync();
      expect(productionLeafSource, contains('sameExactGroupRetryAttachment('));
      expect(
        productionLeafSource,
        contains('applyGroupUploadCompletionAuthority('),
      );
      expect(productionLeafSource, contains('completion.completeUploadRetry('));
      final conversationSource = File(
        'lib/features/groups/presentation/screens/group_conversation_wired.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'_runForegroundGroupUploadLeaf\s*\(',
        ).allMatches(conversationSource),
        hasLength(3),
        reason:
            'the shared wrapper plus ordinary and voice callers must remain',
      );
      expect(
        conversationSource,
        contains('}) => runForegroundGroupUploadLeaf('),
      );

      final hostSource = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final identityCalls = hostSource.indexOf(
        'final identities = await Future.wait',
      );
      final contactCall = hostSource.indexOf(
        'await _establishContacts(senderIdentity, receiverIdentity);',
      );
      final identityProbe = hostSource.indexOf("phase: 'identity_probe'");
      final bilateralContacts = hostSource.indexOf(
        'await Future.wait(<Future<Map<String, Object?>>>[',
      );
      final senderSetup = hostSource.indexOf("phase: 'sender_setup'");
      expect(identityCalls, greaterThanOrEqualTo(0));
      expect(contactCall, greaterThan(identityCalls));
      expect(senderSetup, greaterThan(contactCall));
      expect(identityProbe, greaterThanOrEqualTo(0));
      expect(bilateralContacts, greaterThanOrEqualTo(0));
      expect(
        hostSource,
        contains('receiverTransportPeerId: receiverIdentity.transportPeerId'),
      );
      expect(
        RegExp("'add_contacts': <Object\\?>\\[").allMatches(hostSource),
        hasLength(2),
      );
      expect(
        hostSource,
        isNot(contains('send_contact_requests_for_added_contacts')),
      );
      expect(hostSource, isNot(contains('contact_request_action')));
      final sendStart = hostSource.indexOf(
        'final senderSendFuture = _waitForGroupEndpoint(',
      );
      final recoveryStart = hostSource.indexOf(
        'final recoveryConfig = _groupPhaseConfig(',
        sendStart,
      );
      final sendAndBarrier = hostSource.substring(sendStart, recoveryStart);
      final senderSettled = sendAndBarrier.indexOf(
        'final senderSend = await senderSendFuture;',
      );
      final barrierObserved = sendAndBarrier.indexOf(
        'final barrier = await _waitForBarrierState(',
      );
      expect(sendStart, greaterThanOrEqualTo(0));
      expect(recoveryStart, greaterThan(sendStart));
      expect(senderSettled, greaterThanOrEqualTo(0));
      expect(barrierObserved, greaterThan(senderSettled));
    },
  );

  test(
    'P269 render parser accepts only the three safe renderer labels and host orders route after recovery',
    () {
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node content-desc="P269 receiver JPEG decoded"/>'
          '<node content-desc="P269 receiver voice player ready, 0:02"/>',
        ),
        <String>{'jpeg', 'voice'},
      );
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node text="P269 receiver MP4 thumbnail decoded"/>',
        ),
        <String>{'mp4'},
      );
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node text="Media unavailable"/><node text="0:02"/>',
        ),
        isEmpty,
      );
      expect(
        androidGroupMediaRenderFailureCode(<String>{'jpeg'}),
        'android_receiver_render_missing_mp4_voice',
      );
      expect(
        androidGroupMediaRenderFailureCode(<String>{'jpeg', 'mp4', 'voice'}),
        'android_receiver_render_incomplete',
      );
      expect(
        androidGroupMediaPackageOwnsForeground(
          windowsDump:
              'mCurrentFocus=Window{abc u0 '
              'com.mknoon.sims.groupmedia269/com.mknoon.app.MainActivity}',
          packageName: 'com.mknoon.sims.groupmedia269',
        ),
        isTrue,
      );
      expect(
        androidGroupMediaPackageOwnsForeground(
          windowsDump:
              'mFocusedApp=ActivityRecord{abc u0 '
              'com.android.launcher/.Launcher}',
          packageName: 'com.mknoon.sims.groupmedia269',
        ),
        isFalse,
      );

      final source = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final recovery = source.indexOf(
        'final receiverRecovery = await _waitForGroupEndpoint(',
      );
      final render = source.indexOf("phase: 'receiver_render_probe'", recovery);
      final uiProof = source.indexOf(
        'await _waitForReceiverRenderedKinds()',
        render,
      );
      final senderProbe = source.indexOf(
        'final senderProbeConfig = _groupPhaseConfig(',
        uiProof,
      );
      expect(recovery, greaterThanOrEqualTo(0));
      expect(render, greaterThan(recovery));
      expect(uiProof, greaterThan(render));
      expect(senderProbe, greaterThan(uiProof));
      expect(source, contains("'uiautomator',"));
      expect(
        source,
        contains("'dumpsys',\n        'window',\n        'displays'"),
      );
    },
  );

  test(
    'P269 Android aggregation rejects every process database retry and ACL false-green',
    () {
      final accepted = _aggregateFixture();
      expect(validateGroupMediaReliabilityArtifact(accepted).ok, isTrue);
      final acceptedPrepared = _map(accepted, 'prepared_artifact');
      final acceptedCleanup = _map(accepted, 'cleanup');
      expect(
        acceptedPrepared['application_id'],
        groupMediaAndroidDisposablePackageId,
      );
      expect(acceptedCleanup['artifact_sha256'], acceptedPrepared['sha256']);
      expect(acceptedCleanup['app_left_installed'], isTrue);
      expect(acceptedCleanup['production_package_commands'], 0);
      expect(acceptedCleanup['uninstall_commands'], 0);
      expect(acceptedCleanup['pm_clear_commands'], 0);
      expect(acceptedCleanup['broad_delete_commands'], 0);
      final acceptedDatabases = _map(accepted, 'role_databases');
      final acceptedSenderDb = _map(acceptedDatabases, 'sender');
      final acceptedReceiverDb = _map(acceptedDatabases, 'receiver');
      expect(
        acceptedSenderDb['database_path_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        acceptedReceiverDb['database_path_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        acceptedSenderDb['database_path_sha256'],
        isNot(acceptedReceiverDb['database_path_sha256']),
      );

      final mutations = <void Function(Map<String, Object?>)>[
        (bundle) => _map(bundle, 'receiverRecovery')['currentProcessId'] = 111,
        (bundle) => _map(bundle, 'receiverRecovery')['priorStatus'] = 'pending',
        (bundle) =>
            _map(_map(bundle, 'receiverRecovery'), 'downloadAttempts')['jpeg'] =
                1,
        (bundle) => _map(
          _map(bundle, 'senderProbe'),
          'roleDatabase',
        )['database_path_sha256'] = List<String>.filled(64, 'd').join(),
        (bundle) => _map(
          _map(bundle, 'senderProbe'),
          'roleDatabase',
        )['database_path_sha256'] = List<String>.filled(64, 'D').join(),
        (bundle) {
          final senderDigest = _map(
            _map(bundle, 'senderProbe'),
            'roleDatabase',
          )['database_path_sha256'];
          _map(
            _map(bundle, 'receiverArm'),
            'roleDatabaseIdentity',
          )['database_path_sha256'] = senderDigest;
          _map(
            _map(bundle, 'receiverRecovery'),
            'roleDatabase',
          )['database_path_sha256'] = senderDigest;
        },
        (bundle) => _map(bundle, 'receiverRecovery')['firstDownloadWork'] = 4,
        (bundle) => _map(bundle, 'receiverRecovery')['secondDownloadWork'] = 1,
        (bundle) =>
            (_map(bundle, 'senderSend')['allowedPeers']! as List).removeLast(),
        (bundle) => (_map(bundle, 'senderSend')['allowedPeers']! as List).add(
          'receiver-transport',
        ),
        (bundle) => _map(bundle, 'senderProbe')['processId'] = 333,
        (bundle) => _map(bundle, 'receiverRender')['renderProbeArmed'] = false,
        (bundle) => _map(bundle, 'receiverRenderedKinds')['voice'] = 0,
      ];
      for (final mutation in mutations) {
        expect(
          () => _aggregateFixture(mutate: mutation),
          throwsFormatException,
        );
      }
      expect(
        () => _aggregateFixture(
          mutateCleanup: (pre, post) => post['sender'] = pre['sender']!,
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(
          mutateCleanup: (pre, post) =>
              post['receiver'] = const GroupMediaAndroidDisposableResetReceipt(
                phase: 'post',
                processId: 0,
                sha256Digest:
                    '5555555555555555555555555555555555555555555555555555555555555555',
              ),
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(
          commandSafety: const AndroidGroupMediaCommandSafetyEvidence(
            productionPackageCommands: 0,
            uninstallCommands: 1,
            pmClearCommands: 0,
            broadDeleteCommands: 0,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(appsLeftInstalled: false),
        throwsFormatException,
      );
    },
  );
}

const String _androidSenderTarget = 'pixel-usb';
const String _androidReceiverTarget = 'emulator-5554';

String _androidInventory({
  List<String> senderRows = const <String>[
    'pixel-usb device usb:1-1 product:pixel transport_id:1',
  ],
  List<String> receiverRows = const <String>[
    'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
  ],
}) => <String>[
  'List of devices attached',
  ...senderRows,
  ...receiverRows,
  '',
].join('\n');

Future<void> _expectAndroidTargetPreflightBlocked({
  String? inventory,
  String senderQemu = '0',
  String receiverQemu = '1',
}) async {
  final fixture = _AndroidTargetPreflightFixture(
    inventory: inventory ?? _androidInventory(),
    senderQemu: senderQemu,
    receiverQemu: receiverQemu,
  );
  try {
    Object? failure;
    try {
      await executeAndroidGroupMediaReliabilityScenario(
        fixture.context,
        runner: fixture.runner,
      );
    } on Object catch (error) {
      failure = error;
    }

    expect(
      fixture.runner.mutationCommands,
      isEmpty,
      reason: 'target custody must fail before app or device mutation',
    );
    expect(
      failure,
      isA<GroupMediaReliabilityBlocked>().having(
        (error) => error.blocker,
        'blocker',
        'targetUnavailable',
      ),
    );
  } finally {
    fixture.dispose();
  }
}

final class _AndroidTargetPreflightFixture {
  _AndroidTargetPreflightFixture({
    required String inventory,
    required String senderQemu,
    required String receiverQemu,
  }) {
    directory = Directory.systemTemp.createTempSync('p269-target-preflight-');
    artifact = File(
      '${directory.path}${Platform.pathSeparator}group-media-269.apk',
    )..writeAsBytesSync(utf8.encode('dedicated-p269-preflight-apk'));
    final artifactDigest = sha256
        .convert(artifact.readAsBytesSync())
        .toString();
    runner = _AndroidTargetPreflightRunner(
      inventory: inventory,
      senderQemu: senderQemu,
      receiverQemu: receiverQemu,
    );
    context = GroupMediaReliabilityRunContext(
      scenario: groupMediaForegroundRetryAclRoundtripScenario,
      runId: 'p269-target-preflight',
      preparedArtifact: GroupMediaReliabilityPreparedArtifact(
        path: artifact.absolute.path,
        profile: groupMediaReliabilityAndroidBuildProfile,
        sha256Digest: artifactDigest,
      ),
      roles: const <String, GroupMediaReliabilityRoleBinding>{
        'sender': GroupMediaReliabilityRoleBinding(
          role: 'sender',
          deviceId: _androidSenderTarget,
          identityNamespace: 'sender-preflight',
        ),
        'receiver': GroupMediaReliabilityRoleBinding(
          role: 'receiver',
          deviceId: _androidReceiverTarget,
          identityNamespace: 'receiver-preflight',
        ),
      },
      proofDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}proof',
      ),
      buildGuardLog: null,
    );
  }

  late final Directory directory;
  late final File artifact;
  late final _AndroidTargetPreflightRunner runner;
  late final GroupMediaReliabilityRunContext context;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _AndroidTargetPreflightRunner implements AndroidHostProcessRunner {
  _AndroidTargetPreflightRunner({
    required this.inventory,
    required this.senderQemu,
    required this.receiverQemu,
  });

  final String inventory;
  final String senderQemu;
  final String receiverQemu;
  final List<String> mutationCommands = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final command = '$executable ${arguments.join(' ')}';
    if (executable != 'adb') {
      return ProcessResult(1, 0, '$groupMediaAndroidDisposablePackageId\n', '');
    }
    if (_sameArguments(arguments, const <String>['version'])) {
      return ProcessResult(1, 0, 'Android Debug Bridge version 1.0.41\n', '');
    }
    if (_sameArguments(arguments, const <String>['devices', '-l'])) {
      return ProcessResult(1, 0, inventory, '');
    }
    if (arguments.length >= 3 && arguments.first == '-s') {
      final deviceId = arguments[1];
      final tail = arguments.sublist(2);
      if (_sameArguments(tail, const <String>[
        'shell',
        'getprop',
        'ro.kernel.qemu',
      ])) {
        final value = deviceId == _androidSenderTarget
            ? senderQemu
            : receiverQemu;
        return ProcessResult(1, 0, '$value\n', '');
      }
      if (_sameArguments(tail, const <String>['shell', 'dumpsys', 'power'])) {
        return ProcessResult(
          1,
          0,
          'mWakefulness=Awake\nmInteractive=true\n',
          '',
        );
      }
      if (_sameArguments(tail, const <String>[
        'shell',
        'dumpsys',
        'window',
        'policy',
      ])) {
        return ProcessResult(
          1,
          0,
          'mShowingLockscreen=false\nmInputRestricted=false\n',
          '',
        );
      }
    }
    mutationCommands.add(command);
    return ProcessResult(1, 1, '', 'unexpected mutation');
  }

  bool _sameArguments(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}

final class _AndroidDisposableFixture {
  _AndroidDisposableFixture({
    String manifestApplicationId = groupMediaAndroidDisposablePackageId,
    bool installedDigestMatches = true,
    bool staleReceipt = false,
  }) {
    directory = Directory.systemTemp.createTempSync('p269-android-helper-');
    artifact = File(
      '${directory.path}${Platform.pathSeparator}group-media-269.apk',
    )..writeAsBytesSync(utf8.encode('dedicated-p269-apk'));
    artifactDigest = sha256.convert(artifact.readAsBytesSync()).toString();
    runner = _AndroidDisposableRunner(
      manifestApplicationId: manifestApplicationId,
      artifactDigest: artifactDigest,
      installedDigestMatches: installedDigestMatches,
      staleReceipt: staleReceipt,
    );
    app = GroupMediaAndroidDisposableApp(
      deviceId: 'emulator-5554',
      artifact: artifact,
      expectedArtifactSha256: artifactDigest,
      runId: 'p269-helper-causal',
      workDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}reset',
      ),
      runner: runner,
      pollInterval: Duration.zero,
      maximumPollsPerLaunch: 1,
      onMutationStarted: () => mutationCount += 1,
    );
  }

  late final Directory directory;
  late final File artifact;
  late final String artifactDigest;
  late final _AndroidDisposableRunner runner;
  late final GroupMediaAndroidDisposableApp app;
  var mutationCount = 0;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _AndroidDisposableRunner implements AndroidHostProcessRunner {
  _AndroidDisposableRunner({
    required this.manifestApplicationId,
    required this.artifactDigest,
    required this.installedDigestMatches,
    required this.staleReceipt,
  });

  final String manifestApplicationId;
  final String artifactDigest;
  final bool installedDigestMatches;
  final bool staleReceipt;
  final List<String> adbCommands = <String>[];
  final Map<String, String> receiptStdout = <String, String>{};
  Map<String, Object?>? _resetRequest;
  String? _stagedRequestDigest;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable != 'adb') {
      return ProcessResult(1, 0, '$manifestApplicationId\n', '');
    }
    adbCommands.add(arguments.join(' '));
    final command = arguments.skip(2).toList(growable: false);
    if (command.isNotEmpty && command.first == 'install') {
      return ProcessResult(1, 0, 'Success\n', '');
    }
    if (_startsWith(command, const <String>['shell', 'pm', 'path'])) {
      return ProcessResult(
        1,
        0,
        'package:/data/app/~~P269Token==/'
            'com.mknoon.sims.groupmedia269-P269Suffix==/base.apk\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'sha256sum'])) {
      final digest = installedDigestMatches
          ? artifactDigest
          : List<String>.filled(64, 'f').join();
      return ProcessResult(1, 0, '$digest  ${command.last}\n', '');
    }
    if (command.isNotEmpty && command.first == 'push') {
      final request = File(command[1]);
      final bytes = request.readAsBytesSync();
      _stagedRequestDigest = sha256.convert(bytes).toString();
      _resetRequest = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      return ProcessResult(1, 0, '1 file pushed\n', '');
    }
    if (_startsWith(command, const <String>['shell', 'run-as']) &&
        command.contains('sha256sum')) {
      return ProcessResult(
        1,
        0,
        '${_stagedRequestDigest ?? ''}  pending\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'run-as']) &&
        command.contains('cat')) {
      final request = _resetRequest!;
      final phase = request['phase']! as String;
      final receipt = <String, Object?>{
        'schema': groupMediaIosDisposableResetReceiptSchema,
        'run_id': request['run_id'],
        'nonce': staleReceipt ? 'stale-nonce' : request['nonce'],
        'phase': phase,
        'process_id': phase == 'pre' ? 7001 : 7002,
        'bundle_id': groupMediaAndroidDisposablePackageId,
        'profile': groupMediaAndroidDisposableBuildProfile,
        'keychain_empty': true,
        'database_absent': true,
        'allowlisted_files_absent': true,
        'contains_secrets': false,
      };
      final stdout = '${jsonEncode(receipt)}\n';
      receiptStdout[phase] = stdout;
      return ProcessResult(1, 0, stdout, '');
    }
    if (_startsWith(command, const <String>[
      'shell',
      'cmd',
      'package',
      'resolve-activity',
    ])) {
      return ProcessResult(
        1,
        0,
        '$groupMediaAndroidDisposablePackageId/.MainActivity\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'am', 'start'])) {
      return ProcessResult(
        1,
        0,
        'Starting: Intent { cmp=$groupMediaAndroidDisposablePackageId/'
            '.MainActivity }\nStatus: timeout\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'pidof'])) {
      return ProcessResult(1, 1, '', '');
    }
    return ProcessResult(1, 0, '', '');
  }

  bool _startsWith(List<String> values, List<String> prefix) {
    if (values.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (values[index] != prefix[index]) return false;
    }
    return true;
  }
}

final class _ProcessRunner implements AndroidHostProcessRunner {
  _ProcessRunner({
    this.withStoppedWindowStage = false,
    this.launchStatus = 'ok',
  });

  final bool withStoppedWindowStage;
  final String launchStatus;
  final List<String> commands = <String>[];
  var pidReads = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    commands.add('$executable ${arguments.join(' ')}');
    final tail = arguments.skip(3).join(' ');
    if (tail.startsWith('cmd package resolve-activity')) {
      return ProcessResult(
        1,
        0,
        '$groupMediaAndroidDisposablePackageId/.MainActivity\n',
        '',
      );
    }
    if (tail == 'pidof $groupMediaAndroidDisposablePackageId') {
      pidReads++;
      final stopped =
          pidReads == 2 || (withStoppedWindowStage && pidReads == 3);
      return ProcessResult(
        1,
        stopped ? 1 : 0,
        pidReads == 1
            ? '111\n'
            : stopped
            ? ''
            : '222\n',
        '',
      );
    }
    return ProcessResult(
      1,
      0,
      'Starting: Intent { cmp=$groupMediaAndroidDisposablePackageId/'
          '.MainActivity }\nStatus: $launchStatus\n',
      '',
    );
  }
}

Map<String, Object?> _aggregateFixture({
  void Function(Map<String, Object?> bundle)? mutate,
  void Function(
    Map<String, GroupMediaAndroidDisposableResetReceipt> pre,
    Map<String, GroupMediaAndroidDisposableResetReceipt> post,
  )?
  mutateCleanup,
  AndroidGroupMediaCommandSafetyEvidence commandSafety =
      const AndroidGroupMediaCommandSafetyEvidence(
        productionPackageCommands: 0,
        uninstallCommands: 0,
        pmClearCommands: 0,
        broadDeleteCommands: 0,
      ),
  bool appsLeftInstalled = true,
}) {
  const runId = 'p269-aggregate';
  const messageIds = <String, String>{
    'jpeg': 'message-jpeg',
    'mp4': 'message-mp4',
    'voice': 'message-voice',
  };
  const attachmentIds = <String, String>{
    'jpeg': 'blob-jpeg',
    'mp4': 'blob-mp4',
    'voice': 'blob-voice',
  };
  final context = GroupMediaReliabilityRunContext(
    scenario: groupMediaForegroundRetryAclRoundtripScenario,
    runId: runId,
    preparedArtifact: GroupMediaReliabilityPreparedArtifact(
      path: '/tmp/prepared.apk',
      profile: groupMediaReliabilityAndroidBuildProfile,
      sha256Digest: List<String>.filled(64, 'c').join(),
    ),
    roles: const <String, GroupMediaReliabilityRoleBinding>{
      'sender': GroupMediaReliabilityRoleBinding(
        role: 'sender',
        deviceId: 'pixel-usb',
        identityNamespace: 'sender-namespace',
      ),
      'receiver': GroupMediaReliabilityRoleBinding(
        role: 'receiver',
        deviceId: 'emulator-5554',
        identityNamespace: 'receiver-namespace',
      ),
    },
    proofDirectory: Directory('/tmp/p269-proof'),
    buildGuardLog: null,
  );
  final senderDb = _roleDatabase(
    role: 'sender',
    runId: runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    pathDigest: List<String>.filled(64, 'a').join(),
  );
  final receiverDb = _roleDatabase(
    role: 'receiver',
    runId: runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    pathDigest: List<String>.filled(64, 'b').join(),
  );
  final bundle = <String, Object?>{
    'senderSetup': <String, Object?>{
      'groupId': 'group-id',
      'accountPeerId': 'sender-account',
      'transportPeerId': 'sender-transport',
      'processId': 333,
      'roleDatabaseIdentity': _databaseIdentity(senderDb),
    },
    'receiverArm': <String, Object?>{
      'groupId': 'group-id',
      'accountPeerId': 'receiver-account',
      'transportPeerId': 'receiver-transport',
      'processId': 111,
      'roleDatabaseIdentity': _databaseIdentity(receiverDb),
    },
    'senderSend': <String, Object?>{
      'accountPeerId': 'sender-account',
      'transportPeerId': 'sender-transport',
      'receiverAccountPeerId': 'receiver-account',
      'receiverTransportPeerId': 'receiver-transport',
      'processId': 333,
      'allowedPeers': <Object?>['sender-transport', 'receiver-transport'],
      'uploadsPerBlob': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
      'publicationsPerMessage': <String, Object?>{
        'jpeg': 1,
        'mp4': 1,
        'voice': 1,
      },
      'roleDatabase': senderDb,
    },
    'barrierState': <String, Object?>{
      'barrier': <String, Object?>{
        'name': 'receiver_jpeg_post_claim_pre_commit',
        'reached': true,
        'priorStatus': 'downloading',
        'attempt': 1,
        'processId': 111,
      },
    },
    'receiverRecovery': <String, Object?>{
      'priorStatus': 'downloading',
      'previousProcessId': 111,
      'currentProcessId': 222,
      'processId': 222,
      'firstUploadWork': 0,
      'firstDownloadWork': 3,
      'secondUploadWork': 0,
      'secondDownloadWork': 0,
      'downloadAttempts': <String, Object?>{'jpeg': 2, 'mp4': 1, 'voice': 1},
      'roleDatabase': receiverDb,
    },
    'receiverRender': <String, Object?>{
      'processId': 222,
      'renderProbeArmed': true,
    },
    'receiverRenderedKinds': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    'senderProbe': <String, Object?>{
      'processId': 444,
      'firstUploadWork': 0,
      'firstDownloadWork': 0,
      'secondUploadWork': 0,
      'secondDownloadWork': 0,
      'roleDatabase': senderDb,
    },
  };
  final copied = (jsonDecode(jsonEncode(bundle))! as Map)
      .cast<String, Object?>();
  mutate?.call(copied);
  final preResetReceipts = <String, GroupMediaAndroidDisposableResetReceipt>{
    'sender': _resetReceipt('pre', 501, '1'),
    'receiver': _resetReceipt('pre', 502, '2'),
  };
  final postResetReceipts = <String, GroupMediaAndroidDisposableResetReceipt>{
    'sender': _resetReceipt('post', 601, '3'),
    'receiver': _resetReceipt('post', 602, '4'),
  };
  mutateCleanup?.call(preResetReceipts, postResetReceipts);
  return aggregateAndroidGroupMediaReliabilityEvidence(
    context: context,
    senderExportedAccountPeerId: 'sender-account',
    receiverExportedAccountPeerId: 'receiver-account',
    senderSetup: _map(copied, 'senderSetup'),
    receiverArm: _map(copied, 'receiverArm'),
    senderSend: _map(copied, 'senderSend'),
    barrierState: _map(copied, 'barrierState'),
    receiverTransition: const AndroidGroupMediaProcessTransitionEvidence(
      oldPid: '111',
      freshPid: '222',
      oldPidGone: true,
      launcherComponent: '$groupMediaAndroidDisposablePackageId/.MainActivity',
      relaunchedWithoutGroupRoute: true,
    ),
    receiverRecovery: _map(copied, 'receiverRecovery'),
    receiverRender: _map(copied, 'receiverRender'),
    receiverRenderedKinds: _map(
      copied,
      'receiverRenderedKinds',
    ).cast<String, int>(),
    senderTransition: const AndroidGroupMediaProcessTransitionEvidence(
      oldPid: '333',
      freshPid: '444',
      oldPidGone: true,
      launcherComponent: '$groupMediaAndroidDisposablePackageId/.MainActivity',
      relaunchedWithoutGroupRoute: true,
    ),
    senderProbe: _map(copied, 'senderProbe'),
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    preResetReceipts: preResetReceipts,
    postResetReceipts: postResetReceipts,
    commandSafety: commandSafety,
    appsLeftInstalled: appsLeftInstalled,
  );
}

GroupMediaAndroidDisposableResetReceipt _resetReceipt(
  String phase,
  int processId,
  String digestCharacter,
) => GroupMediaAndroidDisposableResetReceipt(
  phase: phase,
  processId: processId,
  sha256Digest: List<String>.filled(64, digestCharacter).join(),
);

Map<String, Object?> _roleDatabase({
  required String role,
  required String runId,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required String pathDigest,
}) => <String, Object?>{
  'role_db_path': '$role/group-media.sqlite',
  'database_path_sha256': pathDigest,
  'cipher_version': 'SQLCipher 4.6.1',
  'user_version': 104,
  'rows': <Object?>[
    for (final kind in const <String>['jpeg', 'mp4', 'voice'])
      <String, Object?>{
        'run_id': runId,
        'media_kind': kind,
        'message_id': messageIds[kind],
        'blob_id': attachmentIds[kind],
        'status': 'done',
        'upload_retry_count': 0,
        'download_retry_count': 0,
      },
  ],
};

Map<String, Object?> _databaseIdentity(Map<String, Object?> settled) =>
    <String, Object?>{
      'role_db_path': settled['role_db_path'],
      'database_path_sha256': settled['database_path_sha256'],
      'cipher_version': settled['cipher_version'],
      'user_version': settled['user_version'],
      'rows': <Object?>[],
    };

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    (value[key]! as Map).cast<String, Object?>();
