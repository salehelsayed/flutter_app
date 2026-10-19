import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/update_check/application/update_check_controller.dart';
import '../features/update_check/support/fake_update_check_service.dart';
import 'package:flutter_app/app/application_root.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/missed_call_action_payload.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_history_access.dart';
import 'package:flutter_app/features/call/application/call_redial_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/outgoing_call_capability.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/screens/active_call_screen.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_call_timeline_source.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_backoff_timer.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/data/repositories/intro_review_seen_repository_impl.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';

final _activeId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _missedId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _now = DateTime.utc(2026, 10, 19, 12);

void main() {
  testWidgets('production root exposes unavailable callback feedback above '
      'the active call without ending or replacing it', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final semantics = tester.ensureSemantics();
    try {
      final calls = _BusyCall();
      addTearDown(calls.dispose);
      final notifications = _Notifications();
      final contacts = _Contacts();
      final identity = _Identity();
      final completed = <OutgoingCallStartResult?>[];
      final updates = UpdateCheckController(service: FakeUpdateCheckService());
      addTearDown(updates.dispose);
      const callChannel = MethodChannel('mknoon/call_task');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(callChannel, (_) async => true);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(callChannel, null),
      );
      await tester.pumpWidget(
        MyApp(
          repository: identity,
          contactRepository: contacts,
          contactRequestRepository: _ContactRequestRepositoryImpl(),
          contactRequestListener: _ContactRequestListener(),
          contactRequestPresentationGate: ContactRequestPresentationGate(),
          messageRepository: _MessageRepositoryImpl(),
          postRepository: _PostRepositoryImpl(),
          postsPrivacySettingsRepository: _PostsPrivacySettingsRepositoryImpl(),
          feedClearedRepository: _FeedClearedRepository(),
          contactPresenceSnapshotRepository:
              _ContactPresenceSnapshotRepositoryImpl(),
          nearbyLocationService: _NearbyLocationService(),
          mediaAttachmentRepository: _MediaAttachmentRepositoryImpl(),
          groupMediaDeleteForMeCoordinator: _GroupMediaDeleteForMeCoordinator(),
          groupMediaDeletionCleanup: () async {},
          chatMessageListener: _ChatMessageListener(),
          postListener: _PostListener(),
          postCommentListener: _PostCommentListener(),
          postReactionListener: _PostReactionListener(),
          postPresenceListener: _PostPresenceListener(),
          postPassListener: _PostPassListener(),
          postPinListener: _PostPinListener(),
          reactionListener: _ReactionListener(),
          messageDeletionListener: _MessageDeletionListener(),
          profileUpdateListener: _ProfileUpdateListener(),
          messageRouter: _IncomingMessageRouter(),
          pendingMessageRetrier: _PendingMessageRetrier(),
          pendingPostMediaUploadRetrier: _PendingPostMediaUploadRetrier(),
          pendingPostDeliveryRetrier: _PendingPostDeliveryRetrier(),
          pendingPostFollowOnRetrier: _PendingPostFollowOnRetrier(),
          keyExchangeRetrier: _KeyExchangeRetrier(),
          bridge: _Bridge(),
          p2pService: _P2P(),
          mediaFileManager: _MediaFileManager(),
          secureKeyStore: _SecureKeyStore(),
          imageProcessor: _ImageProcessor(),
          audioRecorderService: _AudioRecorderService(),
          reactionRepository: _ReactionRepositoryImpl(),
          isDesktop: false,
          notificationService: notifications,
          appShellController: AppShellController(),
          pendingPostTargetStore: PendingPostTargetStore(),
          conversationTracker: ActiveConversationTracker(),
          groupRepository: _GroupRepositoryImpl(),
          groupMessageRepository: _GroupMessageRepositoryImpl(),
          groupInviteDeliveryAttemptRepository:
              _GroupInviteDeliveryAttemptRepositoryImpl(),
          groupPendingKeyRepairRepository:
              _GroupPendingKeyRepairRepositoryImpl(),
          groupPendingReactionRepository: _GroupPendingReactionRepository(),
          groupPendingKeyRepairRunner: _GroupPendingKeyRepairRunner(),
          groupPendingKeyRepairBackoffTimer:
              _GroupPendingKeyRepairBackoffTimer(),
          groupPendingKeyDistributionRunner:
              _GroupPendingKeyDistributionRunner(),
          groupHistoryGapRepairRepository:
              _GroupHistoryGapRepairRepositoryImpl(),
          groupReactionReplayOutboxRepository:
              _GroupReactionReplayOutboxRepositoryImpl(),
          groupMessageListener: _GroupMessageListener(),
          groupInviteListener: _GroupInviteListener(),
          groupKeyUpdateListener: _GroupKeyUpdateListener(),
          groupKeyRepairResponderListener: _GroupKeyRepairResponderListener(),
          requestGroupKeyRepair: (_) async {},
          groupMembershipUpdateListener: _GroupMembershipUpdateListener(),
          groupConversationTracker: ActiveConversationTracker(),
          introductionRepository: _IntroductionRepositoryImpl(),
          introReviewSeenRepository: _IntroReviewSeenRepositoryImpl(),
          introductionListener: _IntroductionListener(),
          shareIntentService: _Shares(),
          updateCheckController: updates,
          outgoingCallCapability: calls,
          foregroundCallCapability: calls,
          callTimelineSource: _History(),
          deferredRuntimeStartup: () async => true,
          callBackReadinessBarrier: () async => true,
          onCallBackObservation: (event, id, result) {
            if (event == CallBackActionObservation.completed) {
              completed.add(result);
            }
          },
        ),
      );
      // Keep unrelated startup behind the fake initial-share capture. The real
      // MaterialApp, root callback handler and call overlay are all mounted.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final navigator = MyApp.navigatorKey.currentState!;
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('retained conversation')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(navigator.canPop(), isTrue);
      expect(find.byType(ActiveCallScreen), findsOneWidget);
      final before = calls.current;
      expect(notifications.onNotificationTap, isNotNull);
      notifications.onNotificationTap!(
        '$callBackPayloadPrefix${_missedId.value}',
      );
      for (var frame = 0; frame < 6; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(completed, [OutgoingCallStartResult.unavailable]);
      expect(calls.current, same(before));
      expect(calls.current.session.callId, _activeId);
      expect(calls.current.session.state, CallState.connected);
      expect(calls.current.audio, same(before.audio));
      expect(calls.current.audio.active, isTrue);
      expect(calls.actions, isEmpty);
      expect(MyApp.navigatorKey.currentState, same(navigator));
      expect(navigator.canPop(), isTrue);
      expect(find.text('retained conversation').hitTestable(), findsNothing);
      expect(find.byType(ActiveCallScreen), findsOneWidget);
      expect(find.byKey(ValueKey<CallId?>(_activeId)), findsOneWidget);
      expect(find.text('Voice calling is unavailable.'), findsOneWidget);
      expect(
        find.text('Voice calling is unavailable.').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Voice calling is unavailable\.')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      semantics.dispose();
    }
  });
}

// Unused process owners are inert. Only the explicit fake methods below may
// execute asynchronous work; no database, networking, devices or credentials.
class _Unused {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Identity extends _Unused implements IdentityRepositoryImpl {
  @override
  Future<IdentityModel?> loadIdentity() => Completer<IdentityModel?>().future;
}

class _Contacts extends _Unused implements ContactRepositoryImpl {
  @override
  Future<ContactModel?> getContact(String peerId) async => ContactModel(
    peerId: peerId,
    publicKey: '',
    rendezvous: '',
    username: 'Saved contact',
    signature: '',
    scannedAt: _now.toIso8601String(),
  );
}

class _Notifications extends _Unused implements NotificationService {
  @override
  void Function(String)? onNotificationTap;
  @override
  Future<String?> consumeInitialPayload() async => null;
}

class _P2P extends _Unused implements P2PServiceImpl {
  @override
  Future<PresenceSetResult> setPresence(String state, int ttlMs) async =>
      PresenceSetResult.unsupported;
}

class _Shares extends _Unused implements ShareIntentService {
  @override
  bool get hasPendingIntent => false;
  @override
  Stream<ShareIntent> get intentStream => const Stream.empty();
  @override
  Future<ShareIntent?> captureInitialIntent() =>
      Completer<ShareIntent?>().future;
}

class _History extends _Unused
    implements ConversationCallTimelineSource, CallHistoryAccess {
  final entry = CallHistoryEntry(
    callId: _missedId,
    contactAccountPeerId: 'saved-contact',
    direction: CallDirection.incoming,
    terminalReason: CallEndReason.noAnswer,
    status: CallHistoryStatus.missed,
    startedAt: _now,
    endedAt: _now,
    transportRoute: null,
    createdAt: _now,
    updatedAt: _now,
  );
  @override
  Future<CallHistoryEntry?> findCall(CallId id) async =>
      id == _missedId ? entry : null;
  @override
  Future<List<CallHistoryEntry>> recentCallsForContact(String peerId) async => [
    entry,
  ];
}

class _BusyCall extends _Unused
    implements ForegroundCallCapability, OutgoingCallCapability {
  final _changes = StreamController<ForegroundCallProjection?>.broadcast(
    sync: true,
  );
  Future<void> dispose() => _changes.close();
  final actions = <Symbol>[];
  @override
  final ForegroundCallProjection current = ForegroundCallProjection(
    session: CallSessionSnapshot.active(
      callId: _activeId,
      contactPeerId: 'active-contact',
      direction: CallDirection.outgoing,
      state: CallState.connected,
      callerAccountPeerId: 'local-peer',
      callerDeviceId: 'local-device',
      startedAt: _now.subtract(const Duration(minutes: 1)),
      connectedAt: _now.subtract(const Duration(seconds: 30)),
    ),
    audio: CallAudioControlState(
      muted: false,
      selectedRoute: CallAudioOutputRoute.systemDefault,
      supportedRoutes: const [
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.speaker,
      ],
      active: true,
      failure: CallAudioFailure.none,
    ),
  );
  @override
  Stream<ForegroundCallProjection?> get changes => _changes.stream;
  @override
  bool get isOutgoingCallAvailable => false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    actions.add(invocation.memberName);
    return Future<ForegroundCallActionResult>.value(
      ForegroundCallActionResult.unavailable,
    );
  }
}

class _AudioRecorderService extends _Unused implements AudioRecorderService {
  @override
  Future<void> dispose() async {}
}

class _Bridge extends _Unused implements Bridge {}

class _ChatMessageListener extends _Unused implements ChatMessageListener {}

class _ContactPresenceSnapshotRepositoryImpl extends _Unused
    implements ContactPresenceSnapshotRepositoryImpl {}

class _ContactRequestListener extends _Unused
    implements ContactRequestListener {}

class _ContactRequestRepositoryImpl extends _Unused
    implements ContactRequestRepositoryImpl {}

class _FeedClearedRepository extends _Unused implements FeedClearedRepository {}

class _GroupHistoryGapRepairRepositoryImpl extends _Unused
    implements GroupHistoryGapRepairRepositoryImpl {}

class _GroupInviteDeliveryAttemptRepositoryImpl extends _Unused
    implements GroupInviteDeliveryAttemptRepositoryImpl {}

class _GroupInviteListener extends _Unused implements GroupInviteListener {}

class _GroupKeyRepairResponderListener extends _Unused
    implements GroupKeyRepairResponderListener {}

class _GroupKeyUpdateListener extends _Unused
    implements GroupKeyUpdateListener {}

class _GroupMediaDeleteForMeCoordinator extends _Unused
    implements GroupMediaDeleteForMeCoordinator {}

class _GroupMembershipUpdateListener extends _Unused
    implements GroupMembershipUpdateListener {}

class _GroupMessageListener extends _Unused implements GroupMessageListener {}

class _GroupMessageRepositoryImpl extends _Unused
    implements GroupMessageRepositoryImpl {}

class _GroupPendingKeyDistributionRunner extends _Unused
    implements GroupPendingKeyDistributionRunner {}

class _GroupPendingKeyRepairBackoffTimer extends _Unused
    implements GroupPendingKeyRepairBackoffTimer {}

class _GroupPendingKeyRepairRepositoryImpl extends _Unused
    implements GroupPendingKeyRepairRepositoryImpl {}

class _GroupPendingKeyRepairRunner extends _Unused
    implements GroupPendingKeyRepairRunner {}

class _GroupPendingReactionRepository extends _Unused
    implements GroupPendingReactionRepository {}

class _GroupReactionReplayOutboxRepositoryImpl extends _Unused
    implements GroupReactionReplayOutboxRepositoryImpl {}

class _GroupRepositoryImpl extends _Unused implements GroupRepositoryImpl {}

class _ImageProcessor extends _Unused implements ImageProcessor {}

class _IncomingMessageRouter extends _Unused implements IncomingMessageRouter {}

class _IntroReviewSeenRepositoryImpl extends _Unused
    implements IntroReviewSeenRepositoryImpl {}

class _IntroductionListener extends _Unused implements IntroductionListener {}

class _IntroductionRepositoryImpl extends _Unused
    implements IntroductionRepositoryImpl {}

class _KeyExchangeRetrier extends _Unused implements KeyExchangeRetrier {}

class _MediaAttachmentRepositoryImpl extends _Unused
    implements MediaAttachmentRepositoryImpl {}

class _MediaFileManager extends _Unused implements MediaFileManager {}

class _MessageDeletionListener extends _Unused
    implements MessageDeletionListener {}

class _MessageRepositoryImpl extends _Unused implements MessageRepositoryImpl {}

class _NearbyLocationService extends _Unused implements NearbyLocationService {}

class _PendingMessageRetrier extends _Unused implements PendingMessageRetrier {}

class _PendingPostDeliveryRetrier extends _Unused
    implements PendingPostDeliveryRetrier {}

class _PendingPostFollowOnRetrier extends _Unused
    implements PendingPostFollowOnRetrier {}

class _PendingPostMediaUploadRetrier extends _Unused
    implements PendingPostMediaUploadRetrier {}

class _PostCommentListener extends _Unused implements PostCommentListener {}

class _PostListener extends _Unused implements PostListener {}

class _PostPassListener extends _Unused implements PostPassListener {}

class _PostPinListener extends _Unused implements PostPinListener {}

class _PostPresenceListener extends _Unused implements PostPresenceListener {}

class _PostReactionListener extends _Unused implements PostReactionListener {}

class _PostRepositoryImpl extends _Unused implements PostRepositoryImpl {
  @override
  Stream<String> get postChanges => const Stream.empty();
}

class _PostsPrivacySettingsRepositoryImpl extends _Unused
    implements PostsPrivacySettingsRepositoryImpl {}

class _ProfileUpdateListener extends _Unused implements ProfileUpdateListener {}

class _ReactionListener extends _Unused implements ReactionListener {}

class _ReactionRepositoryImpl extends _Unused
    implements ReactionRepositoryImpl {}

class _SecureKeyStore extends _Unused implements SecureKeyStore {}
