import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

String _startupStepInvocation(
  String source, {
  required String wrapper,
  required String stepId,
}) {
  final stepToken = "'$stepId'";
  final stepIndex = source.indexOf(stepToken);
  if (stepIndex < 0) {
    throw StateError('Missing startup step $stepId');
  }
  final invocationStart = source.lastIndexOf(wrapper, stepIndex);
  if (invocationStart < 0) {
    throw StateError('$stepId is not owned by $wrapper');
  }
  final openingParenthesis = source.indexOf('(', invocationStart);
  var depth = 0;
  for (var index = openingParenthesis; index < source.length; index++) {
    switch (source[index]) {
      case '(':
        depth += 1;
      case ')':
        depth -= 1;
        if (depth == 0) {
          return source.substring(invocationStart, index + 1);
        }
    }
  }
  throw StateError('Unterminated startup step $stepId');
}

// 164 (cold-start-1 / cold-start-3): source-substring wiring locks over the
// production bootstrap and application root. These assert the pre-launch
// deferral structure (no eager
// startLiveServices / ensureFirebaseReady awaits, unconditional
// deferredRuntimeStartup, preserved deferred-startup trigger) and that the
// shared-Keychain mirror moved off the critical path while staying retained.
//
// Pattern mirrors main_resume_group_upload_wiring_test.dart: touch
// app.MyApp.navigatorKey first to force the public entrypoint export, then read
// each exact implementation owner and assert index-delimited substrings.
void main() {
  test(
    'migration-gated deferred startup uses retryable outcome latch',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final applicationRootSource = await File(
        'lib/app/application_root.dart',
      ).readAsString();

      expect(
        applicationRootSource,
        contains('AccountMigrationRuntimeStartupLatch('),
        reason: 'MyApp must use the shared retryable runtime-startup latch',
      );
      expect(
        applicationRootSource,
        contains('startRuntime: widget.deferredRuntimeStartup'),
        reason: 'the latch must own the injected boolean startup outcome',
      );
      expect(
        productionSource,
        contains('Future<bool> startLiveServicesIfAllowed() async'),
        reason:
            'the existing void starter needs an outcome wrapper so a gated '
            'no-start can be retried',
      );
      expect(
        productionSource,
        contains('deferredRuntimeStartup: startLiveServicesIfAllowed,'),
        reason: 'MyApp must receive the outcome-returning startup wrapper',
      );
      expect(
        applicationRootSource,
        contains('return runtimeStartupLatch.ensureStarted();'),
        reason:
            '_ensureRuntimeServicesReady must delegate to the retryable latch',
      );
    },
  );

  test(
    'TC-16a every fallible live-service startup step is resumable and run once',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      final start = productionSource.indexOf(
        'Future<void> startLiveServices() async {',
      );
      final end = productionSource.indexOf(
        'Future<bool> startLiveServicesIfAllowed() async',
        start,
      );
      expect(start, isNonNegative);
      expect(end, greaterThan(start));
      final startupBody = productionSource.substring(start, end);

      const asyncSteps = <String, String>{
        'private_media_cold_recovery':
            'await ensurePrivateMediaColdRecovery();',
        'direct_media_blob_local_cleanup':
            'cleanupDirectMediaBlobCustodyLocally',
        'group_context_backfill': 'await groupContextBackfill;',
        'group_reaction_comparand_backfill':
            'await groupReactionComparandBackfill;',
        'firebase_ready': 'await ensureFirebaseReady();',
        'bridge_initialize': 'await bridge.initialize();',
        'notification_service_initialize':
            'await notificationService.initialize();',
      };
      const syncSteps = <String, String>{
        'message_router_start': 'messageRouter.start',
        'contact_request_listener_start': 'contactRequestListener.start',
        'chat_message_listener_start': 'chatMessageListener.start',
        'post_listener_start': 'postListener.start',
        'post_comment_listener_start': 'postCommentListener.start',
        'post_reaction_listener_start': 'postReactionListener.start',
        'post_presence_listener_start': 'postPresenceListener.start',
        'post_pass_listener_start': 'postPassListener.start',
        'post_pin_listener_start': 'postPinListener.start',
        'reaction_listener_start': 'reactionListener.start',
        'message_deletion_listener_start': 'messageDeletionListener.start',
        'delivery_receipt_listener_start': 'deliveryReceiptListener.start',
        'profile_update_listener_start': 'profileUpdateListener.start',
        'group_message_listener_start': 'groupMessageListener.start',
        'group_invite_listener_start': 'groupInviteListener.start',
        'group_key_update_listener_start': 'groupKeyUpdateListener.start',
        'group_key_repair_responder_listener_start':
            'groupKeyRepairResponderListener.start',
        'group_membership_update_listener_start':
            'groupMembershipUpdateListener.start',
        'introduction_listener_start': 'introductionListener.start',
        'pending_message_retrier_start': 'pendingMessageRetrier.start',
        'group_pending_key_repair_backoff_timer_start':
            'groupPendingKeyRepairBackoffTimer.start',
        'pending_post_media_upload_retrier_start':
            'pendingPostMediaUploadRetrier.start',
        'pending_post_delivery_retrier_start':
            'pendingPostDeliveryRetrier.start',
        'pending_post_follow_on_retrier_start':
            'pendingPostFollowOnRetrier.start',
        'key_exchange_retrier_start': 'keyExchangeRetrier.start',
        'profile_update_forwarder_install':
            'profileUpdateListener.contactUpdatedStream.listen',
        'contact_key_update_forwarder_install':
            'contactRequestListener.contactKeyUpdatedStream.listen',
        'auto_added_forwarder_install':
            'contactRequestListener.autoAddedStream.listen',
      };

      expect(
        'liveServiceStartupSteps.runAsync('.allMatches(startupBody),
        hasLength(asyncSteps.length),
      );
      expect(
        'liveServiceStartupSteps.runSync('.allMatches(startupBody),
        hasLength(syncSteps.length),
      );

      for (final entry in asyncSteps.entries) {
        expect(
          "'${entry.key}'".allMatches(startupBody),
          hasLength(1),
          reason: '${entry.key} must have one stable checkpoint ID',
        );
        expect(
          entry.value.allMatches(startupBody),
          hasLength(1),
          reason: '${entry.key} must have one production call site',
        );
        final invocation = _startupStepInvocation(
          startupBody,
          wrapper: 'liveServiceStartupSteps.runAsync',
          stepId: entry.key,
        );
        expect(
          invocation,
          contains(entry.value),
          reason: '${entry.key} must execute inside runAsync',
        );
      }

      for (final entry in syncSteps.entries) {
        expect(
          "'${entry.key}'".allMatches(startupBody),
          hasLength(1),
          reason: '${entry.key} must have one stable checkpoint ID',
        );
        expect(
          entry.value.allMatches(startupBody),
          hasLength(1),
          reason: '${entry.key} must have one production call site',
        );
        final invocation = _startupStepInvocation(
          startupBody,
          wrapper: 'liveServiceStartupSteps.runSync',
          stepId: entry.key,
        );
        expect(
          invocation,
          contains(entry.value),
          reason: '${entry.key} must execute inside runSync',
        );
        if (entry.key.endsWith('_forwarder_install')) {
          expect(
            invocation,
            contains('liveServiceForwardingSubscriptions.add('),
            reason: '${entry.key} must retain its subscription',
          );
        }
      }

      expect(
        'liveServiceForwardingSubscriptions.add('.allMatches(startupBody),
        hasLength(3),
      );
      expect(RegExp(r'\.listen\(').allMatches(startupBody), hasLength(3));
      expect(
        startupBody.indexOf('liveServicesStarted = true;'),
        greaterThan(startupBody.lastIndexOf('liveServiceStartupSteps.runSync')),
        reason: 'the runtime may be marked started only after every checkpoint',
      );
    },
  );

  test('TC-164-01 main wires the live-services outcome wrapper as '
      'unconditional deferredRuntimeStartup and drops both eager pre-runApp '
      'awaits', () async {
    expect(app.MyApp.navigatorKey, isNotNull);

    final productionSource = await File(
      'lib/app/bootstrap/production_application_bootstrap.dart',
    ).readAsString();
    final applicationRootSource = await File(
      'lib/app/application_root.dart',
    ).readAsString();

    // (i) deferredRuntimeStartup is unconditional, not isShareLaunch-gated.
    expect(
      productionSource,
      contains('deferredRuntimeStartup: startLiveServicesIfAllowed,'),
      reason:
          'normal launch must take the same deferred startup path share '
          'launch already used',
    );
    expect(
      productionSource,
      isNot(
        contains(
          'deferredRuntimeStartup: isShareLaunch '
          '? startLiveServicesIfAllowed',
        ),
      ),
      reason: 'the isShareLaunch ternary on deferredRuntimeStartup is removed',
    );

    // (ii) the eager normal-launch startLiveServices await is gone.
    expect(
      productionSource,
      isNot(contains('if (!isShareLaunch) {\n    await startLiveServices();')),
      reason:
          'startLiveServices must not be awaited on the pre-runApp critical '
          'path on a normal launch',
    );

    // (iii) the eager top-level ensureFirebaseReady await is gone (the in-
    // startLiveServices await ensureFirebaseReady() at :3043 has no
    // `if (!isShareLaunch) {` prefix, so it is NOT matched).
    expect(
      productionSource,
      isNot(
        contains('if (!isShareLaunch) {\n    await ensureFirebaseReady();'),
      ),
      reason: 'Firebase must leave the pre-runApp critical path',
    );

    // (iv) INV-8: the deferred-startup trigger survives — it is the sole
    // driver of the deferred startup on an idle no-notification launch.
    expect(
      applicationRootSource,
      contains('unawaited(_handleInitialLocalNotificationLaunchWhenReady())'),
      reason:
          'removing this trigger would mean the node/listeners never start on '
          'a passive launch (INV-8)',
    );
  });

  test(
    'TC-164-06 the keychain mirror runs OFF the critical path but is guaranteed '
    'to run (retained, not dropped)',
    () async {
      expect(app.MyApp.navigatorKey, isNotNull);

      final productionSource = await File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsString();
      // A compile-gated disposable reset profile may render an inert app and
      // return before normal startup. Anchor this preservation sentinel to the
      // production root-build phase that precedes host launch.
      final rootBuildIndex = productionSource.indexOf(
        'Future<Widget> _buildRootWidget() async {',
      );
      expect(rootBuildIndex, isNonNegative);
      final preRootBuild = productionSource.substring(0, rootBuildIndex);

      // (i) the bare top-level (2-space-indented) eager mirror await is gone
      // from the pre-runApp region. The retained-future closure re-uses the same
      // call but at a deeper indent, so the 2-space anchor only matched the old
      // eager form.
      expect(
        preRootBuild,
        isNot(
          contains('\n  await groupRepository.mirrorAllKeysToSecureStore();'),
        ),
        reason:
            'the unbounded keychain backfill must not block the pre-launch '
            'critical path',
      );

      // (ii) it is still kicked off via a retained future (not a bare,
      // droppable unawaited(...)), and that kickoff drives both mirrors.
      expect(
        preRootBuild,
        contains('keychainMirrorBackfill = '),
        reason:
            'the backfill must be retained so the analyzer/GC cannot silently '
            'drop it',
      );
      final kickoffIndex = preRootBuild.indexOf('keychainMirrorBackfill = ');
      final kickoffBlock = preRootBuild.substring(kickoffIndex);
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
