import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const handlerPath =
      'android/app/src/main/kotlin/com/mknoon/app/PictureInPictureHandler.kt';
  const activityPath =
      'android/app/src/main/kotlin/com/mknoon/app/'
      'ReceivedVideoPictureInPictureActivity.kt';
  const runnerPath = 'scripts/run_received_video_picture_in_picture_proof.sh';

  test(
    'SystemUI close uses a session fenced monotonic checkpoint when terminal position is zero',
    () {
      final handlerFile = File(handlerPath);
      final activityFile = File(activityPath);
      expect(handlerFile.existsSync(), isTrue);
      expect(activityFile.existsSync(), isTrue);

      final handler = handlerFile.readAsStringSync();
      final activity = activityFile.readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(handler, contains('mknoon/picture_in_picture'));
      expect(handler, contains('mknoon/picture_in_picture/events'));
      expect(handler, contains('FEATURE_PICTURE_IN_PICTURE'));
      expect(handler, contains('Build.VERSION_CODES.O'));
      expect(handler, contains('activity.applicationInfo.dataDir'));
      expect(handler, contains('File(canonicalDataRoot, "app_flutter")'));
      expect(handler, isNot(contains('activity.filesDir')));
      expect(
        handler,
        contains(
          'setOf("session", "attachment", "path", "positionMs", "durationMs")',
        ),
      );
      expect(
        handler,
        contains('setOf("session", "attachment")'),
        reason: 'activate/stop must carry only the exact session fence.',
      );

      expect(
        activity,
        contains('maxOf(lastKnownPositionMs, observedPositionMs)'),
      );
      expect(activity, contains('removeCallbacks(checkpointRunnable)'));
      expect(activity, contains('stopPlayback()'));
      expect(
        activity.indexOf('removeCallbacks(checkpointRunnable)'),
        lessThan(activity.indexOf('stopPlayback()')),
        reason: 'The sampler must stop before VideoView releases its player.',
      );
      expect(activity, contains('savedInstanceState != null'));
      expect(activity, contains('isInPictureInPictureMode'));
      expect(activity, isNot(contains('setAutoEnterEnabled(true)')));
      expect(activity, contains('class PictureInPictureExitClassifier'));
      expect(activity, contains('exitClassifier.onResume()'));
      expect(
        activity,
        contains('exitClassifier.onWindowFocusChanged(hasFocus)'),
      );
      expect(activity, contains('exitClassifier.onStop()'));
      expect(activity, contains('exitClassifier.onDestroy()'));
      expect(activity, contains('exitClassifier.onFallbackTimeout()'));
      expect(activity, contains('SYSTEM_EXIT_FALLBACK_MS = 2_000L'));
      expect(activity, isNot(contains('SYSTEM_EXIT_CLASSIFICATION_MS')));
      expect(activity, isNot(contains('settleSystemReturnRunnable')));
      expect(
        activity,
        contains('class ReceivedVideoPictureInPictureActivity : Activity()'),
      );
      expect(activity, contains('VideoView(this)'));
      expect(activity, isNot(contains('FlutterActivity')));
      expect(activity, isNot(contains('FlutterView')));

      final dedicatedDeclaration = RegExp(
        r'<activity\s+[^>]*android:name="\.ReceivedVideoPictureInPictureActivity"[^>]*/>',
        dotAll: true,
      ).firstMatch(manifest);
      expect(dedicatedDeclaration, isNotNull);
      final declaration = dedicatedDeclaration!.group(0)!;
      expect(declaration, contains('android:exported="false"'));
      expect(declaration, contains('android:supportsPictureInPicture="true"'));
      expect(declaration, contains('android:resizeableActivity="true"'));
      expect(declaration, isNot(contains('<intent-filter')));

      final mainDeclaration = RegExp(
        r'<activity\s+[^>]*android:name="\.MainActivity"[^>]*>',
        dotAll: true,
      ).firstMatch(manifest)!.group(0)!;
      expect(mainDeclaration, isNot(contains('supportsPictureInPicture')));
    },
  );

  test(
    'Flutter engine detach stops native once and process recreation is empty',
    () async {
      final handler = File(handlerPath).readAsStringSync();
      final activity = File(activityPath).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
      ).readAsStringSync();
      final coordinator = File(
        'android/app/src/main/kotlin/com/mknoon/app/'
        'PictureInPictureEngineCleanupCoordinator.kt',
      ).readAsStringSync();
      final proofReceiver = File(
        'android/app/src/pipProof/kotlin/com/mknoon/app/'
        'PictureInPictureEngineDetachProofReceiver.kt',
      ).readAsStringSync();
      final proofManifest = File(
        'android/app/src/pipProof/AndroidManifest.xml',
      ).readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();

      expect(handler, contains('flutter_engine_detached'));
      expect(
        handler,
        contains(r'"[MKNOON_PIP] TERMINAL state=$state reason=$reason"'),
      );
      expect(handler, isNot(contains('TERMINAL session=')));
      expect(handler, isNot(contains('TERMINAL attachment=')));
      expect(handler, isNot(contains('TERMINAL path=')));
      expect(handler, contains('host_destroyed'));
      expect(handler, contains('terminalEmitted'));
      expect(handler, contains('WeakReference'));
      expect(activity, contains('savedInstanceState != null'));
      expect(activity, contains('registry.current(sessionId)'));
      expect(activity, isNot(contains('getStringExtra("path")')));
      expect(activity, isNot(contains('getParcelableExtra')));
      expect(activity, isNot(contains('onSaveInstanceState')));

      expect(
        mainActivity,
        contains('PictureInPictureHandler('),
        reason: 'MainActivity must register the additive channel handler.',
      );
      expect(mainActivity, contains('pictureInPictureHandler?.dispose('));
      expect(
        RegExp(r'override\s+fun\s+onNewIntent').hasMatch(mainActivity),
        isTrue,
        reason: 'PiP wiring must preserve notification intent ownership.',
      );
      expect(mainActivity, contains('ReceivedMediaEgressHandler('));
      expect(mainActivity, contains('PrivateMediaProtectionHandler'));
      expect(mainActivity, contains('mknoon/disk_space'));
      expect(mainActivity, contains('mknoon/mdns_resolver'));

      final topologyOutput = File(
        '${Directory.systemTemp.path}/pip-topology-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      addTearDown(() {
        if (topologyOutput.existsSync()) topologyOutput.deleteSync();
      });
      final topologyResult = await Process.run('python3', [
        'scripts/parse_android_picture_in_picture_task_topology.py',
        '--input',
        'test/fixtures/android_picture_in_picture_two_task_activities.txt',
        '--package',
        'com.mknoon.app.pipproof',
        '--output',
        topologyOutput.path,
      ]);
      expect(
        topologyResult.exitCode,
        0,
        reason: '${topologyResult.stdout}\n${topologyResult.stderr}',
      );
      expect(
        topologyOutput.readAsStringSync(),
        'fullscreenMainTaskId=834\npinnedNativeTaskId=835\n',
      );

      final duplicateInput = File(
        '${Directory.systemTemp.path}/pip-topology-duplicate-${DateTime.now().microsecondsSinceEpoch}.txt',
      );
      final duplicateOutput = File('${duplicateInput.path}.out');
      addTearDown(() {
        if (duplicateInput.existsSync()) duplicateInput.deleteSync();
        if (duplicateOutput.existsSync()) duplicateOutput.deleteSync();
      });
      duplicateInput.writeAsStringSync(
        '${File('test/fixtures/android_picture_in_picture_two_task_activities.txt').readAsStringSync()}\n'
        '  * Task{duplicate #999 type=standard I=com.mknoon.app.pipproof/com.mknoon.app.MainActivity U=0 visible=true mode=fullscreen sz=1}\n'
        '    mActivityComponent=com.mknoon.app.pipproof/com.mknoon.app.MainActivity\n',
      );
      final duplicateResult = await Process.run('python3', [
        'scripts/parse_android_picture_in_picture_task_topology.py',
        '--input',
        duplicateInput.path,
        '--package',
        'com.mknoon.app.pipproof',
        '--output',
        duplicateOutput.path,
      ]);
      expect(duplicateResult.exitCode, isNot(0));
      expect(duplicateOutput.existsSync(), isFalse);

      final runner = File(runnerPath).readAsStringSync();
      expect(appBuild, contains('enablePictureInPictureEngineDetachProof'));
      expect(appBuild, contains('src/pipProof/kotlin'));
      expect(appBuild, contains('src/pipProof/AndroidManifest.xml'));
      expect(appBuild, contains('com.mknoon.app.pipproof'));
      expect(
        coordinator,
        contains('class PictureInPictureEngineCleanupBinding<T : Any>'),
      );
      expect(coordinator, contains('WeakReference'));
      expect(
        coordinator,
        contains('object PictureInPictureEngineCleanupCoordinator'),
      );
      const coordinatorCall =
          'PictureInPictureEngineCleanupCoordinator.cleanUpFlutterEngine()';
      expect(mainActivity, contains(coordinatorCall));
      expect(proofReceiver, contains(coordinatorCall));
      expect(
        proofReceiver,
        contains('[MKNOON_PIP] PROOF_ENGINE_CLEANUP_CONTROL invoked=true'),
      );
      expect(proofReceiver, contains('android.permission.DUMP'));
      expect(proofReceiver, contains('intent.extras != null'));
      expect(proofManifest, contains('android:exported="true"'));
      expect(
        proofManifest,
        contains('android:permission="android.permission.DUMP"'),
      );
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('PictureInPictureEngineDetachProofReceiver')),
      );
      expect(
        File('android/app/src/debug/AndroidManifest.xml').readAsStringSync(),
        isNot(contains('PictureInPictureEngineDetachProofReceiver')),
      );
      expect(
        runner,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=true',
        ),
      );
      expect(
        RegExp(
          'ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false',
        ).allMatches(runner),
        hasLength(7),
        reason:
            'Both non-engine dry-run and execution branches must override '
            'inherited proof-control state.',
      );
      expect(runner, contains('engine-detach-proof-broadcast.txt'));
      expect(runner, contains('Broadcast completed: result=-1'));
      expect(
        runner,
        contains('[MKNOON_PIP] PROOF_ENGINE_CLEANUP_CONTROL invoked=true'),
      );
      expect(runner, contains('system_close'));
      expect(
        runner,
        isNot(contains(r'am stack remove "$fullscreen_main_task_id"')),
      );
      expect(runner, isNot(contains('KEYCODE_BACK')));
      expect(runner, contains('proofControl=true'));
      expect(runner, contains('flutterHostExit=0'));
      expect(
        mainActivity,
        contains('"[MKNOON_PIP] MainActivity.cleanUpFlutterEngine " +'),
      );
      expect(mainActivity, contains('"reason=flutter_engine_detached"'));
    },
  );

  test(
    'runner preserves pre-existing app and seeds canonical documents path',
    () {
      final runner = File(runnerPath).readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final integrationProof = File(
        'integration_test/received_video_picture_in_picture_proof_test.dart',
      ).readAsStringSync();
      const preExistingCheck =
          r'shell pm path "$candidate_package" 2>/dev/null';
      const launch = r'ORG_GRADLE_PROJECT_androidApplicationId="$package_name"';

      expect(runner, contains('package_name="com.mknoon.app.pipproof"'));
      expect(
        runner,
        contains(r'if [[ "$package_name" == "$production_package"'),
      );
      expect(runner, contains(preExistingCheck));
      expect(
        runner.indexOf(preExistingCheck),
        lessThan(runner.indexOf(launch)),
      );
      expect(
        runner,
        contains(r'ORG_GRADLE_PROJECT_androidApplicationId="$package_name"'),
      );
      expect(
        runner,
        contains(
          'ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true',
        ),
      );
      expect(runner, isNot(contains('--android-project-arg')));
      expect(runner, contains('ro.build.version.sdk'));
      expect(runner, contains('android.software.picture_in_picture'));
      expect(runner, contains('sys.boot_completed'));
      expect(runner, contains('apksigner'));
      expect(runner, contains('signingCertificateSha256'));
      expect(runner, contains('wait_for_flutter_shutdown'));
      final shutdownWaiter = RegExp(
        r'wait_for_flutter_shutdown\(\) \{(.*?)\n\}',
        dotAll: true,
      ).firstMatch(runner)!.group(1)!;
      expect(
        shutdownWaiter,
        isNot(contains('set -e')),
        reason:
            'The helper must return the killed Flutter status without '
            're-enabling caller errexit before process-recreation can inspect it.',
      );
      expect(
        shutdownWaiter,
        isNot(contains('set +e')),
        reason: 'The helper must preserve rather than mutate caller errexit.',
      );
      expect(runner, isNot(contains('shell monkey')));
      expect(
        runner,
        contains(r'am start -W -n "$flutter_component"'),
        reason: 'Process recreation must pin the exact installed launcher.',
      );
      expect(runner, contains('process-relaunch-am-start.txt'));
      expect(runner, contains("grep -Fq 'Status: ok'"));
      expect(runner, contains('process-relaunched-logcat.txt'));
      expect(runner, contains('process-relaunched-process.txt'));
      expect(runner, contains(r'logcat -d --pid="$relaunch_pid"'));
      expect(
        runner,
        contains(r'--dart-define="PIP_PROOF_PACKAGE=$package_name"'),
      );
      expect(
        runner,
        contains(
          '[PIP_PROOF] PROCESS_RECREATION_EMPTY fixture=verified '
          'nativeReplay=false scenario=process-recreation',
        ),
        reason:
            'Process recreation must retain and assert the exact empty-state '
            'marker emitted by the independently relaunched process.',
      );
      expect(runner, contains(r'session=$process_recreation_session'));
      expect(runner, contains(r'package=$package_name'));
      expect(
        runner,
        contains(
          'Relaunched process replayed the received-video native PiP session.',
        ),
      );
      expect(runner, contains('shell uiautomator dump'));
      expect(
        runner,
        contains('select_android_picture_in_picture_system_ui_control.dart'),
      );
      expect(
        runner,
        contains(
          'Refusing an unverified Android SystemUI PiP control coordinate.',
        ),
      );
      expect(
        runner,
        contains(
          'select_android_picture_in_picture_pixel6_api36_geometry.dart',
        ),
      );
      expect(runner, contains(r'"$device_codename" == "oriole"'));
      expect(runner, contains(r'"$device_model" == "Pixel 6"'));
      expect(runner, contains(r'"$wm_size" == "Physical size: 1080x2400"'));
      expect(runner, contains(r'"$wm_density" == "Physical density: 420"'));
      expect(
        runner,
        contains(
          'Expected exactly one live pinned task before the SystemUI action.',
        ),
      );
      expect(runner, contains('pinned_task_ids='));
      expect(runner, contains('sort -u'));
      expect(runner, contains('native-pre-action-activities.txt'));
      expect(runner, contains('native-post-reveal-activities.txt'));
      expect(
        runner,
        contains(
          'The post-reveal task did not match the unique dedicated '
          'pre-action PiP owner.',
        ),
      );
      expect(runner, contains('preRevealBounds=%s postRevealBounds=%s'));
      expect(
        runner,
        contains(r'''sed -n 's/^selectorSource=//p' "$selection_normalized"'''),
      );
      expect(runner, contains(r'--output "$selection_json"'));
      expect(
        runner,
        contains('validate_android_picture_in_picture_system_ui_selection.py'),
      );
      expect(runner, contains('selection_link_count'));
      expect(runner, contains('Structured SystemUI PiP control selection'));
      expect(runner, isNot(contains("s/.*selectorSource=//p")));
      expect(runner, isNot(contains(r'action_x="$center_x"')));
      expect(appBuild, contains('disableGoogleServicesForDisposableProof'));
      expect(
        appBuild,
        contains(
          'hasGoogleServicesConfig && '
          '!disableGoogleServicesForDisposableProof',
        ),
      );
      expect(
        runner,
        contains(
          'app_fixture="app_flutter/media/plan243-proof/'
          'received_video_picture_in_picture_fixture.mp4"',
        ),
      );
      expect(runner, isNot(contains('files/media/plan243-proof')));
      expect(runner, contains(r'if [[ "$test_install_started" == true ]]'));
      expect(runner, contains('local cleanup_exit=0'));
      expect(
        runner,
        contains('primaryExit=%s cleanupExit=%s cleanupVerified=%s'),
      );
      expect(
        RegExp(
          r'adb -s "\$device" uninstall "\$package_name"',
        ).allMatches(runner).length,
        1,
        reason: 'Only unconditional cleanup may uninstall the test-owned app.',
      );
      expect(
        runner,
        contains(r'adb -s "$device" uninstall "$proof_test_package"'),
      );
      expect(
        runner,
        contains('flutterChatPinned=false nativeVideoSurface=true'),
      );
      expect(integrationProof, contains('FullScreenTypedMediaViewer('));
      expect(integrationProof, contains('MediaPictureInPictureController('));
      expect(integrationProof, contains('IoAppOwnedMediaPathAuthority()'));
      expect(
        integrationProof,
        contains("ValueKey('media_action_picture_in_picture')"),
      );
      expect(integrationProof, contains('await tester.tap(action)'));
      expect(
        integrationProof,
        contains(
          '[PIP_PROOF] PROTECTED_NEGATIVE control=absent gatewayStart=false',
        ),
      );
      expect(
        integrationProof,
        contains("attachmentId: 'plan243-protected-unowned-video'"),
      );
      expect(
        integrationProof,
        contains('MediaViewerProtection(isProtected: true)'),
      );
      expect(
        integrationProof,
        contains('expect(protectedGateway.startCalls, 0)'),
      );
      expect(
        integrationProof,
        contains(r'[PIP_PROOF] FLUTTER_OWNER_READY scenario=$_proofScenario'),
      );
      expect(
        integrationProof,
        contains(
          r'[PIP_PROOF] FLUTTER_OWNER_RESTORED scenario=$_proofScenario',
        ),
      );
      expect(
        integrationProof,
        contains("_waitForHostCaptureAck('flutter-owner-ready')"),
      );
      expect(
        integrationProof,
        contains("_waitForHostCaptureAck('flutter-owner-restored')"),
      );
      expect(
        integrationProof.indexOf('[PIP_PROOF] FLUTTER_OWNER_READY'),
        lessThan(integrationProof.indexOf('await tester.tap(action)')),
      );
      expect(
        integrationProof.indexOf('[PIP_PROOF] FLUTTER_OWNER_RESTORED'),
        lessThan(integrationProof.indexOf('[PIP_PROOF] TERMINAL scenario=')),
      );
      expect(runner, contains('flutter-pre-handoff-audio.txt'));
      expect(runner, contains('type:android.media.AudioTrack'));
      expect(runner, contains('type:android.media.MediaPlayer'));
      expect(runner, contains('.flutter-owner-ready-captured-v1'));
      expect(runner, contains('flutter-post-terminal-audio.txt'));
      expect(runner, contains('.flutter-owner-restored-captured-v1'));
      expect(runner, contains('postTerminalPlaying=%s'));
      expect(
        runner,
        contains('validate_android_picture_in_picture_restored_ownership.py'),
      );
      expect(runner, contains('post-terminal-restored-ownership.txt'));
      final restoredOwnershipStart = runner.indexOf('restored_owner_marker=');
      final restoredOwnershipEnd = runner.indexOf(
        r'wait_for_log "[PIP_PROOF] TERMINAL scenario=$scenario"',
        restoredOwnershipStart,
      );
      expect(restoredOwnershipStart, isNonNegative);
      expect(restoredOwnershipEnd, greaterThan(restoredOwnershipStart));
      final restoredOwnershipBlock = runner.substring(
        restoredOwnershipStart,
        restoredOwnershipEnd,
      );
      expect(
        restoredOwnershipBlock,
        isNot(contains(r'grep -Fq "$native_component"')),
      );
      expect(
        integrationProof,
        contains(r'session=$_proofSessionId package=$_proofPackage'),
      );
      expect(
        RegExp(
          r'gateway\.(?:start|activate|stop)\(',
        ).hasMatch(integrationProof),
        isFalse,
        reason: 'The proof must enter PiP only through the production viewer.',
      );
    },
  );

  test(
    'interruption proof is a gated separate test APK with causal focus evidence',
    () {
      const helperPath =
          'android/app/src/pipInterruptionProofAndroidTest/java/com/mknoon/app/'
          'pipproof/PictureInPictureAudioFocusInterruptionProofActivity.java';
      const helperManifestPath =
          'android/app/src/pipInterruptionProofAndroidTest/AndroidManifest.xml';
      const validatorPath =
          'scripts/validate_android_picture_in_picture_interruption.py';
      final helperFile = File(helperPath);
      final helperManifestFile = File(helperManifestPath);
      final validatorFile = File(validatorPath);
      final runner = File(runnerPath).readAsStringSync();
      final appBuild = File('android/app/build.gradle.kts').readAsStringSync();
      final mainManifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final debugManifest = File(
        'android/app/src/debug/AndroidManifest.xml',
      ).readAsStringSync();

      expect(helperFile.existsSync(), isTrue);
      expect(helperManifestFile.existsSync(), isTrue);
      expect(validatorFile.existsSync(), isTrue);
      final helper = helperFile.readAsStringSync();
      final helperManifest = helperManifestFile.readAsStringSync();
      const helperClass = 'PictureInPictureAudioFocusInterruptionProofActivity';
      const helperPackage = r'${package_name}.test';

      expect(helper, contains('AudioManager.AUDIOFOCUS_GAIN'));
      expect(helper, contains('AudioAttributes.USAGE_MEDIA'));
      expect(helper, contains('AudioAttributes.CONTENT_TYPE_MOVIE'));
      expect(helper, contains('AudioManager.AUDIOFOCUS_REQUEST_GRANTED'));
      expect(helper, contains('[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST'));
      expect(helper, contains('onWindowFocusChanged'));
      expect(helper, contains('NONCE_PATTERN'));
      expect(helperManifest, contains(helperClass));
      expect(helperManifest, contains('android:exported="true"'));
      expect(mainManifest, isNot(contains(helperClass)));
      expect(debugManifest, isNot(contains(helperClass)));

      expect(appBuild, contains('enablePictureInPictureInterruptionProof'));
      expect(appBuild, contains('src/pipInterruptionProofAndroidTest/java'));
      expect(
        appBuild,
        contains('src/pipInterruptionProofAndroidTest/AndroidManifest.xml'),
      );
      expect(
        appBuild,
        contains(
          'Picture-in-picture interruption proof sources require the exact',
        ),
      );
      expect(runner, contains(':app:assembleDebugAndroidTest'));
      expect(runner, contains('interruption-helper.apk'));
      expect(runner, contains(r'adb -s "$device" install -t'));
      expect(runner, contains(helperPackage));
      expect(runner, contains('distinctUid=true'));
      expect(runner, contains('interruption-focus-transferred'));
      expect(runner, contains(validatorPath));
      expect(
        runner,
        contains('validate_android_picture_in_picture_interruption_cleanup.py'),
      );
      expect(runner, contains('PYTHONPYCACHEPREFIX'));
      expect(runner, contains(r'python-cache-${$}'));
      expect(runner, contains('interruption-cleanup-audio.txt'));
      expect(runner, contains(r'cat "$cleanup_focus_result"'));
      final cleanupValidator = File(
        'scripts/validate_android_picture_in_picture_interruption_cleanup.py',
      ).readAsStringSync();
      expect(cleanupValidator, contains('cleanupFocusReleased=true'));
      expect(runner, contains(r'am force-stop "$proof_test_package"'));
      expect(runner, contains('[MKNOON_PIP_INTERRUPT] FOCUS_REQUEST'));
      expect(
        runner,
        contains('[MKNOON_PIP] TERMINAL state=stopped reason=interrupted'),
      );
      expect(
        runner,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=true',
        ),
      );
      expect(
        runner,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false',
        ),
      );
      expect(runner, isNot(contains('public_interruption_fixture')));
      expect(runner, isNot(contains('android.intent.action.VIEW')));
      expect(runner, contains('resolve-activity --components'));
      expect(runner, contains(r'-n "$interruption_helper_component"'));
      expect(runner, isNot(contains('resolve-activity --brief')));
      expect(runner, isNot(contains('query-activities')));
      expect(runner, contains("grep -Fq 'E: intent-filter'"));
      expect(runner, contains('ResolverActivity|ChooserActivity'));
    },
  );

  test(
    'engine-detach proof build checker proves default absence and disposable-only presence',
    () {
      final checker = File(
        'scripts/check_android_picture_in_picture_engine_detach_proof_build.sh',
      );
      expect(checker.existsSync(), isTrue);
      final source = checker.readAsStringSync();
      expect(source, contains('default APK unexpectedly contains'));
      expect(source, contains('proof APK did not contain'));
      expect(source, contains('PictureInPictureEngineDetachProofReceiver'));
      expect(source, contains('com.mknoon.app.pipproof'));
      expect(source, contains('com.mknoon.app'));
      expect(source, contains('enablePictureInPictureEngineDetachProof=true'));
      expect(source, contains('did not refuse the production application ID'));
    },
  );

  test(
    'interruption proof build checker fences helper to disposable test APK',
    () {
      final checker = File(
        'scripts/check_android_picture_in_picture_interruption_proof_build.sh',
      );
      expect(checker.existsSync(), isTrue);
      final source = checker.readAsStringSync();
      expect(source, contains(':app:assembleDebugAndroidTest'));
      expect(source, contains('defaultBaseHelper=false'));
      expect(source, contains('defaultTestHelper=false'));
      expect(source, contains('proofBaseHelper=false'));
      expect(source, contains('proofTestHelper=true'));
      expect(source, contains('proofTestPackage=%s'));
      expect(source, contains('productionRefused=true'));
      expect(source, contains('enablePictureInPictureInterruptionProof=true'));
      expect(
        source,
        contains(r'proof_test_application_id="${proof_application_id}.test"'),
      );
      expect(source, contains("grep -Fq 'E: intent-filter'"));
      expect(source, contains('ResolverActivity|ChooserActivity'));
    },
  );

  test(
    'API 36 installed helper identity does not require unfiltered Activity resolver rows',
    () {
      const helperClass =
          'com.mknoon.app.pipproof.PictureInPictureAudioFocusInterruptionProofActivity';
      final packageDump = File(
        'test/fixtures/android_picture_in_picture_interruption_helper_package_api36.txt',
      ).readAsStringSync();
      expect(packageDump, contains('Package [com.mknoon.app.pipproof.test]'));
      expect(packageDump, contains('appId=10473'));
      expect(packageDump, isNot(contains(helperClass)));
      int exactPackageRows(String value) => RegExp(
        r'^  Package \[com\.mknoon\.app\.pipproof\.test\]',
        multiLine: true,
      ).allMatches(value).length;
      expect(exactPackageRows(packageDump), 1);
      expect(
        exactPackageRows(
          packageDump.replaceFirst(
            'Package [com.mknoon.app.pipproof.test]',
            'Package [com.mknoon.app.pipproof.other]',
          ),
        ),
        0,
      );
      expect(
        exactPackageRows(
          '$packageDump\n  Package [com.mknoon.app.pipproof.test] (duplicate):\n',
        ),
        2,
      );

      final runner = File(runnerPath).readAsStringSync();
      expect(
        runner,
        contains(
          'grep -Fc "Package [\$proof_test_package]" '
          '"\$interruption_helper_package_dump"',
        ),
      );
      expect(
        runner,
        isNot(
          contains(
            'grep -Fc "\$interruption_helper_class" '
            '"\$interruption_helper_package_dump"',
          ),
        ),
      );
      expect(runner, contains('resolve-activity --components'));
      expect(runner, contains('--components --user 0'));
      expect(runner, contains(r'-n "$interruption_helper_component"'));
      expect(
        runner,
        contains('interruption-helper-resolved-component-stderr.txt'),
      );
      expect(runner, contains(r'"$interruption_helper_resolve_status" != "0"'));
      expect(
        runner,
        contains(r'-s "$interruption_helper_resolved_component_error"'),
      );
      expect(
        runner,
        contains(r'"$interruption_helper_resolved_component_lines" != "1"'),
      );
      expect(
        runner,
        contains(
          r'"$interruption_helper_resolved_component_value" != "$interruption_helper_component"',
        ),
      );
      expect(
        runner,
        contains(
          r'"$interruption_helper_installed_sha256" != "$interruption_helper_local_sha256"',
        ),
      );
      expect(
        runner,
        contains(
          r'"$interruption_helper_installed_signer_sha256" != "$installed_signer_sha256"',
        ),
      );
      expect(runner, contains(r'"$interruption_helper_uid" == "$uid"'));
    },
  );

  test(
    'SystemUI PiP action keeps validated geometry but reacquires a live menu under a strict budget',
    () {
      final runner = File(runnerPath).readAsStringSync();
      final actionStart = runner.indexOf(
        'select_and_tap_pip_system_ui_control() {',
      );
      final actionEnd = runner.indexOf(
        r'adb -s "$device" logcat -c',
        actionStart,
      );
      expect(actionStart, isNonNegative);
      expect(actionEnd, greaterThan(actionStart));
      final action = runner.substring(actionStart, actionEnd);

      expect(runner, contains('PIP_MENU_ACTION_LATENCY_BUDGET_MS=750'));
      expect(runner, contains('PIP_MENU_ANIMATION_SETTLE_SECONDS=0.125'));
      expect(runner, contains("PIP_MENU_INPUT_TARGET='Embedded{PipMenuView}'"));
      expect(action, contains('wait_for_pip_menu_visibility hidden'));
      expect(action, contains('native-action-ready-activities.txt'));
      expect(action, contains('native-action-ready-pinned-task.txt'));
      expect(
        action,
        contains(
          'The action-ready task/bounds changed after geometry validation.',
        ),
      );
      expect(action, contains('wait_for_pip_menu_visibility visible'));
      expect(
        action,
        contains(
          'Refusing a SystemUI PiP action outside the live-menu latency budget.',
        ),
      );
      expect(action, contains('wait_for_exact_pinned_task_absent'));
      expect(
        action,
        contains('SystemUI PiP action left the exact task pinned.'),
      );
      expect(
        action,
        contains(r'wait_for_log "$native_action_terminal_marker" 50 0.1'),
      );
      expect(
        action,
        contains(
          'pipMenuValidationStartMs=%s pipMenuValidatedMs=%s '
          'pipMenuValidationLatencyMs=%s',
        ),
      );
      expect(
        action,
        contains(
          'pipMenuHiddenMs=%s pipMenuFinalRevealMs=%s pipMenuVisibleMs=%s '
          'pipMenuActionTapMs=%s pipMenuRevealToTapMs=%s '
          'pipMenuActionBudgetMs=%s',
        ),
      );

      final hidden = action.indexOf('wait_for_pip_menu_visibility hidden');
      final freshTask = action.indexOf('native-action-ready-activities.txt');
      final finalReveal = action.indexOf(
        r'pip_menu_action_reveal_ms="$(monotonic_ms)"',
      );
      final visible = action.indexOf('wait_for_pip_menu_visibility visible');
      final animationSettle = action.indexOf(
        r'sleep "$PIP_MENU_ANIMATION_SETTLE_SECONDS"',
      );
      final finalTap = action.lastIndexOf(
        r'adb -s "$device" shell input tap "$center_x" "$center_y"',
      );
      final taskAbsent = action.indexOf('wait_for_exact_pinned_task_absent');
      expect(hidden, lessThan(freshTask));
      expect(freshTask, lessThan(finalReveal));
      expect(finalReveal, lessThan(visible));
      expect(visible, lessThan(animationSettle));
      expect(animationSettle, lessThan(finalTap));
      expect(finalTap, lessThan(taskAbsent));

      final liveMenuCriticalPath = action.substring(finalReveal, finalTap);
      expect(liveMenuCriticalPath, isNot(contains('dart run')));
      expect(liveMenuCriticalPath, isNot(contains('screencap')));
      expect(liveMenuCriticalPath, isNot(contains('sleep 0.8')));
      expect(
        liveMenuCriticalPath,
        isNot(contains('dumpsys activity activities >')),
      );
    },
  );

  test(
    'runner dry-run emits Flutter-supported Gradle environment syntax',
    () async {
      final result = await Process.run('bash', [
        runnerPath,
        '--platform',
        'android',
        '--scenario',
        'return',
        '--device',
        'emulator-5554',
        '--dry-run',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final output = result.stdout.toString();
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.app.pipproof',
        ),
      );
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_disableGoogleServicesForDisposableProof=true',
        ),
      );
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false',
        ),
      );
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureInterruptionProof=false',
        ),
      );
      expect(output, contains('flutter test -d emulator-5554'));
      expect(
        output,
        contains(
          'integration_test/received_video_picture_in_picture_proof_test.dart',
        ),
      );
      expect(output, isNot(contains('--android-project-arg')));
    },
  );

  test(
    'process recreation dry-run keeps the exact drive app installed for relaunch',
    () async {
      final driver = File('test_driver/integration_test.dart');
      expect(driver.existsSync(), isTrue);
      expect(driver.readAsStringSync(), contains('integrationDriver()'));

      final result = await Process.run('bash', [
        runnerPath,
        '--platform',
        'android',
        '--scenario',
        'process-recreation',
        '--device',
        '21071FDF600CSC',
        '--dry-run',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final output = result.stdout.toString();
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_androidApplicationId=com.mknoon.app.pipproof',
        ),
      );
      expect(
        output,
        contains(
          'ORG_GRADLE_PROJECT_enablePictureInPictureEngineDetachProof=false',
        ),
      );
      expect(output, contains('flutter drive -d 21071FDF600CSC'));
      expect(output, contains('--keep-app-running'));
      expect(output, contains('--driver test_driver/integration_test.dart'));
      expect(
        output,
        contains(
          '--target '
          'integration_test/received_video_picture_in_picture_proof_test.dart',
        ),
      );
      expect(output, isNot(contains('flutter test')));

      final runner = File(runnerPath).readAsStringSync();
      expect(
        runner,
        contains(
          'Process-recreation drive package disappeared before exact relaunch.',
        ),
      );
      expect(
        RegExp(
          r'adb -s "\$device" uninstall "\$package_name"',
        ).allMatches(runner).length,
        1,
        reason: 'Harness cleanup remains the only disposable-app uninstaller.',
      );
    },
  );

  test('PiP proof discovery paths have exact classifications', () async {
    const expected = <String, String>{
      'integration_test/received_video_picture_in_picture_proof_test.dart':
          'ignored\tignored',
      'integration_test/scripts/'
              'select_android_picture_in_picture_pixel6_api36_geometry.dart':
          'support\tsupport',
      'integration_test/scripts/'
              'select_android_picture_in_picture_system_ui_control.dart':
          'support\tsupport',
    };
    final result = await Process.run('bash', <String>[
      'scripts/check_reliability_simulation_discovery.sh',
      '--records-tsv',
    ]);

    expect(result.exitCode, 0, reason: result.stderr.toString());
    final records = const LineSplitter().convert(result.stdout.toString());
    for (final entry in expected.entries) {
      final matching = records
          .where((line) {
            final columns = line.split('\t');
            return columns.length >= 3 && columns[2] == entry.key;
          })
          .toList(growable: false);
      expect(matching, hasLength(1), reason: entry.key);
      expect(matching.single, startsWith('${entry.value}\t${entry.key}\t'));
    }
  });

  test('full regression PiP retries preserve prior proof artifacts', () {
    final fullRegressionRunner = File(
      'scripts/run_flutter_full_regression.sh',
    ).readAsStringSync();

    expect(fullRegressionRunner, contains('local attempt_id'));
    expect(
      fullRegressionRunner,
      contains(r'pip-$scenario-$attempt_id'),
    );
    expect(
      fullRegressionRunner,
      isNot(contains(r'--output "$run_dir/aux/pip-$scenario"')),
    );
  });
}
