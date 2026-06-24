import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 164 (cold-start-1 / cold-start-3): source-substring wiring locks over
// lib/main.dart. These assert the pre-runApp deferral structure (no eager
// startLiveServices / ensureFirebaseReady awaits, unconditional
// deferredRuntimeStartup, preserved deferred-startup trigger) and that the
// shared-Keychain mirror moved off the critical path while staying retained.
//
// Pattern mirrors main_resume_group_upload_wiring_test.dart: touch
// app.MyApp.navigatorKey first to force the import, then read lib/main.dart as a
// string and assert index-delimited substrings.
void main() {
  test(
    'TC-164-01 main wires startLiveServices as unconditional '
    'deferredRuntimeStartup and drops both eager pre-runApp awaits',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();

      // (i) deferredRuntimeStartup is unconditional, not isShareLaunch-gated.
      expect(
        mainSource,
        contains('deferredRuntimeStartup: startLiveServices,'),
        reason:
            'normal launch must take the same deferred startup path share '
            'launch already used',
      );
      expect(
        mainSource,
        isNot(
          contains('deferredRuntimeStartup: isShareLaunch ? startLiveServices'),
        ),
        reason: 'the isShareLaunch ternary on deferredRuntimeStartup is removed',
      );

      // (ii) the eager normal-launch startLiveServices await is gone.
      expect(
        mainSource,
        isNot(contains('if (!isShareLaunch) {\n    await startLiveServices();')),
        reason:
            'startLiveServices must not be awaited on the pre-runApp critical '
            'path on a normal launch',
      );

      // (iii) the eager top-level ensureFirebaseReady await is gone (the in-
      // startLiveServices await ensureFirebaseReady() at :3043 has no
      // `if (!isShareLaunch) {` prefix, so it is NOT matched).
      expect(
        mainSource,
        isNot(
          contains('if (!isShareLaunch) {\n    await ensureFirebaseReady();'),
        ),
        reason: 'Firebase must leave the pre-runApp critical path',
      );

      // (iv) INV-8: the deferred-startup trigger survives — it is the sole
      // driver of the deferred startup on an idle no-notification launch.
      expect(
        mainSource,
        contains('unawaited(_handleInitialLocalNotificationLaunchWhenReady())'),
        reason:
            'removing this trigger would mean the node/listeners never start on '
            'a passive launch (INV-8)',
      );
    },
  );

  test(
    'TC-164-06 the keychain mirror runs OFF the critical path but is guaranteed '
    'to run (retained, not dropped)',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final mainSource = await File('lib/main.dart').readAsString();
      final runAppIndex = mainSource.indexOf('runApp(');
      expect(runAppIndex, isNonNegative);
      final preRunApp = mainSource.substring(0, runAppIndex);

      // (i) the bare top-level (2-space-indented) eager mirror await is gone
      // from the pre-runApp region. The retained-future closure re-uses the same
      // call but at a deeper indent, so the 2-space anchor only matched the old
      // eager form.
      expect(
        preRunApp,
        isNot(contains('\n  await groupRepository.mirrorAllKeysToSecureStore();')),
        reason:
            'the unbounded keychain backfill must not block the pre-runApp '
            'critical path',
      );

      // (ii) it is still kicked off via a retained future (not a bare,
      // droppable unawaited(...)), and that kickoff drives both mirrors.
      expect(
        preRunApp,
        contains('keychainMirrorBackfill = '),
        reason:
            'the backfill must be retained so the analyzer/GC cannot silently '
            'drop it',
      );
      final kickoffIndex = preRunApp.indexOf('keychainMirrorBackfill = ');
      final kickoffBlock = preRunApp.substring(kickoffIndex);
      expect(
        kickoffBlock,
        contains('mirrorAllKeysToSecureStore'),
        reason: 'the retained kickoff must run the key mirror',
      );
      expect(
        kickoffBlock,
        contains('mirrorAllMutedGroups'),
        reason: 'the retained kickoff must run the mute mirror',
      );
    },
  );
}
