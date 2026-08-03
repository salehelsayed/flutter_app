import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/share/application/handle_share_intent_use_case.dart';
import 'package:flutter_app/features/share/presentation/navigation/share_target_picker_route.dart';
import 'package:flutter_app/features/introduction/data/repositories/introduction_repository_impl.dart';
import 'package:flutter_app/features/introduction/data/repositories/intro_review_seen_repository_impl.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/application/resolve_introduction_notification_target_use_case.dart';
import 'package:flutter_app/features/push/application/intro_accept_notification_open_flow.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contact_request/data/repositories/contact_request_repository_impl.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_notification_materializer.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_runtime_network_gate.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/migration_account_size_estimator.dart';
import 'package:flutter_app/features/conversation/data/repositories/message_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/media_attachment_repository_impl.dart';
import 'package:flutter_app/features/conversation/data/repositories/reaction_repository_impl.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/message_deletion_listener.dart';
import 'package:flutter_app/features/conversation/application/reaction_listener.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/verify_inbox_custody_use_case.dart';
import 'package:flutter_app/features/groups/application/recover_stuck_sending_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_pending_key_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_reaction_repository.dart';
import 'package:flutter_app/features/groups/data/repositories/group_history_gap_repair_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_reaction_replay_outbox_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_invite_delivery_attempt_repository_impl.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_key_repair_responder_listener.dart';
import 'package:flutter_app/features/groups/application/group_membership_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_repair_backoff_timer.dart';
import 'package:flutter_app/features/groups/application/group_pending_key_distribution_service.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/settings/application/profile_update_listener.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/pending_post_media_upload_retrier.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';
import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/application/start_node_use_case.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/debug/transport_metrics.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/group_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/dropped_push_recovery_coordinator.dart';
import 'package:flutter_app/core/notifications/ios_apns_notification_open_bridge.dart';
import 'package:flutter_app/core/notifications/notification_open_dedupe_gate.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/initial_local_notification_route_diagnostics.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/app_shell_theme_binding.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/startup_timing.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier, kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/contact_request/presentation/widgets/contact_request_dialog.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/push/application/background_push_notification_fallback.dart';
import 'package:flutter_app/features/push/application/background_group_notification_post_show_fence.dart';
import 'package:flutter_app/features/push/application/push_decrypt_preview.dart';
import 'package:flutter_app/features/push/application/firebase_readiness.dart';
import 'package:flutter_app/features/push/application/group_missing_notification_feedback.dart';
import 'package:flutter_app/features/push/application/group_notification_display_policy.dart';
import 'package:flutter_app/features/push/application/group_reaction_notification_copy.dart';
import 'package:flutter_app/features/push/application/push_listener_armer.dart';
import 'package:flutter_app/features/push/application/handle_foreground_remote_message_use_case.dart';
import 'package:flutter_app/features/push/application/push_registration_coordinator.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/resolve_group_notification_route_target_use_case.dart';
import 'package:flutter_app/features/push/application/set_presence_use_case.dart';
import 'package:flutter_app/core/services/active_peer_keepalive_use_case.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/post_presence_listener.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/application/post_notification_open_coordinator.dart';
import 'package:flutter_app/features/posts/application/post_pin_listener.dart';
import 'package:flutter_app/features/posts/application/post_pass_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/groups/application/sweep_expired_group_invites_use_case.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/data/repositories/contact_presence_snapshot_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/post_repository_impl.dart';
import 'package:flutter_app/features/posts/data/repositories/posts_privacy_settings_repository_impl.dart';
import 'package:flutter_app/features/feed/data/feed_cleared_repository.dart';

Future<void> openIntroNotificationOrbitRoute({
  required NavigatorState navigator,
  required AppShellController appShellController,
  required MessageRepository messageRepository,
  required Widget Function(ValueListenable<int> feedUnreadCountListenable)
  builder,
}) async {
  final returnTab = appShellController.activeTab;
  final unreadCount = await messageRepository
      .getTotalUnreadCountExcludingArchived();
  final feedUnreadCountNotifier = ValueNotifier<int>(unreadCount);

  if (appShellController.activeTab != AppShellTab.orbit) {
    appShellController.switchTo(AppShellTab.orbit);
  }

  try {
    await navigator.push(
      buildOrbitSlideUpRoute(builder: (_) => builder(feedUnreadCountNotifier)),
    );
  } finally {
    if (appShellController.activeTab == AppShellTab.orbit) {
      appShellController.switchTo(returnTab);
    }
    feedUnreadCountNotifier.dispose();
  }
}

/// Rebinds recipient-owned projection state before transferred notification
/// display custody is allowed to re-project an OS card.
Future<void> activateAccountMigrationReceiverNotificationState({
  required void Function() beginCanonicalNotificationRecovery,
  required void Function() invalidateIdentityCache,
  required Future<void> Function() rebuildRecipientProjection,
  required Future<void> Function({required bool canonicalStateComplete})
  endCanonicalNotificationRecovery,
}) async {
  beginCanonicalNotificationRecovery();
  var canonicalStateComplete = false;
  try {
    invalidateIdentityCache();
    await rebuildRecipientProjection();
    canonicalStateComplete = true;
  } finally {
    await endCanonicalNotificationRecovery(
      canonicalStateComplete: canonicalStateComplete,
    );
  }
}

class MyApp extends StatefulWidget {
  final IdentityRepositoryImpl repository;
  final ContactRepositoryImpl contactRepository;
  final ContactRequestRepositoryImpl contactRequestRepository;
  final ContactRequestListener contactRequestListener;
  final ContactRequestPresentationGate contactRequestPresentationGate;
  // FDC-09 §12 / CV-14 (217 §A1): once-per-cycle wake-token mint+register hook.
  final Future<bool> Function(List<String> contactPeerIds)?
  issueWakeTokensForContacts;
  final MessageRepositoryImpl messageRepository;
  final PostRepositoryImpl postRepository;
  final PostsPrivacySettingsRepositoryImpl postsPrivacySettingsRepository;
  final FeedClearedRepository feedClearedRepository;
  final ContactPresenceSnapshotRepositoryImpl contactPresenceSnapshotRepository;
  final NearbyLocationService nearbyLocationService;
  final MediaAttachmentRepositoryImpl mediaAttachmentRepository;

  /// 235: production Delete-for-me coordinator (journal prepare + cleanup).
  final GroupMediaDeleteForMeCoordinator groupMediaDeleteForMeCoordinator;

  /// 235: one bounded deletion-journal reconciliation pass; runs on resume
  /// BEFORE the account-migration network gate (local-only work).
  final Future<void> Function() groupMediaDeletionCleanup;

  /// 234 Session 03: the same bounded local direct private-media recovery is
  /// used at cold start and resume. Scheduler callbacks keep expiry strictly
  /// foreground-only without coupling it to network readiness.
  final Future<void> Function()? privateMediaLifecycleRecovery;
  final void Function()? stopPrivateMediaExpiryScheduler;
  final void Function()? disposePrivateMediaExpiryScheduler;
  final ChatMessageListener chatMessageListener;
  final PostListener postListener;
  final PostCommentListener postCommentListener;
  final PostReactionListener postReactionListener;
  final PostPresenceListener postPresenceListener;
  final PostPassListener postPassListener;
  final PostPinListener postPinListener;
  final ReactionListener reactionListener;
  final MessageDeletionListener messageDeletionListener;
  final ProfileUpdateListener profileUpdateListener;
  final IncomingMessageRouter messageRouter;
  final PendingMessageRetrier pendingMessageRetrier;
  final PendingPostMediaUploadRetrier pendingPostMediaUploadRetrier;
  final PendingPostDeliveryRetrier pendingPostDeliveryRetrier;
  final PendingPostFollowOnRetrier pendingPostFollowOnRetrier;
  final KeyExchangeRetrier keyExchangeRetrier;
  final Bridge bridge;
  final P2PServiceImpl p2pService;
  final TransportMetrics? transportMetrics;
  final MediaFileManager mediaFileManager;
  final SecureKeyStore secureKeyStore;
  final ImageProcessor imageProcessor;
  final AudioRecorderService audioRecorderService;
  final PrivateMediaOutboxE2EController? privateMediaOutboxE2EController;
  final Widget Function(Widget)? debugE2EOverlayBuilder;
  final Future<StartNodeResult> Function()? debugE2EStartP2PNodeOverride;
  final Future<void> Function()? debugE2EAfterRuntimeReady;
  final bool isDesktop;
  final ReactionRepositoryImpl reactionRepository;
  final NotificationService notificationService;
  final GroupNotificationPresentationCoordinator?
  groupNotificationPresentationCoordinator;
  final ForegroundGroupNotificationPendingReadAcknowledgementResolver?
  groupNotificationPendingReadAcknowledgementResolver;
  final DroppedPushRecoveryCoordinator? droppedPushRecoveryCoordinator;
  final AppShellController appShellController;
  final PendingPostTargetStore pendingPostTargetStore;
  final ActiveConversationTracker conversationTracker;
  final GroupRepositoryImpl groupRepository;
  final GroupMessageRepositoryImpl groupMessageRepository;
  final GroupExitDiagnosticRepository? groupExitDiagnosticRepository;
  final GroupInviteDeliveryAttemptRepositoryImpl
  groupInviteDeliveryAttemptRepository;
  final GroupPendingKeyRepairRepositoryImpl groupPendingKeyRepairRepository;
  final GroupPendingReactionRepository groupPendingReactionRepository;
  final GroupPendingKeyRepairRunner groupPendingKeyRepairRunner;
  final GroupPendingKeyRepairBackoffTimer groupPendingKeyRepairBackoffTimer;
  final GroupPendingKeyDistributionRunner groupPendingKeyDistributionRunner;
  final Future<void> Function()? groupExitIntentRecovery;
  final Future<bool> Function(String groupId)? canRejoinForExitIntent;
  final Future<void> Function(String groupId)? processGroupExitIntent;
  final GroupHistoryGapRepairRepositoryImpl groupHistoryGapRepairRepository;
  final GroupReactionReplayOutboxRepositoryImpl
  groupReactionReplayOutboxRepository;
  final GroupMessageListener groupMessageListener;
  final GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator;
  final GroupInviteListener groupInviteListener;
  final GroupKeyUpdateListener groupKeyUpdateListener;
  final GroupKeyRepairResponderListener groupKeyRepairResponderListener;
  final RequestGroupKeyRepair requestGroupKeyRepair;
  final GroupMembershipUpdateListener groupMembershipUpdateListener;
  final ActiveConversationTracker groupConversationTracker;
  final IntroductionRepositoryImpl introductionRepository;
  final IntroReviewSeenRepositoryImpl introReviewSeenRepository;
  final IntroductionListener introductionListener;
  final ShareIntentService shareIntentService;
  final PushRegistrationCoordinator? pushRegistrationCoordinator;
  final AccountMigrationTransferRunFn? accountMigrationRunTransfer;
  final AccountMigrationSizeGate? accountMigrationSizeGate;
  final AccountMigrationReceiverStartFn? accountMigrationStartReceiver;
  final AccountMigrationReceiverStopFn? accountMigrationStopReceiver;
  final AccountMigrationReceiverEvents? accountMigrationReceiverEvents;

  /// Restores active authority on app resume when a Move Account export
  /// pause is stale (no export run in flight). See handleAppResumed.
  final Future<bool> Function()? accountMigrationRecoverExportPause;
  final Future<bool> Function()? deferredRuntimeStartup;
  final Future<void> Function({required String source})?
  ingestStagedPushEnvelopes;

  /// 191 (Fix D2): the shared Firebase-readiness latch. _MyAppState registers
  /// its push-listener arm on this (the third arm point) so a retried/late
  /// Firebase init still arms the foreground-push listeners. Optional so the
  /// widget-test harnesses (no real Firebase) construct MyApp without it.
  final FirebaseReadiness? firebaseReadiness;

  /// Best-effort teardown invoked on [AppLifecycleState.detached] (app
  /// terminating): stops the libp2p node and closes the encrypted DB so the
  /// next cold start doesn't stall on the splash screen behind a stale
  /// socket/relay reservation or DB lock.
  final Future<void> Function()? onAppDetached;

  static final navigatorKey = GlobalKey<NavigatorState>();

  // 04-P0 / QW-2: app-level messenger so notification handlers (which run
  // outside any Scaffold subtree) can surface SnackBar feedback.
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  const MyApp({
    super.key,
    required this.repository,
    required this.contactRepository,
    required this.contactRequestRepository,
    required this.contactRequestListener,
    required this.contactRequestPresentationGate,
    this.issueWakeTokensForContacts,
    required this.messageRepository,
    required this.postRepository,
    required this.postsPrivacySettingsRepository,
    required this.feedClearedRepository,
    required this.contactPresenceSnapshotRepository,
    required this.nearbyLocationService,
    required this.mediaAttachmentRepository,
    required this.groupMediaDeleteForMeCoordinator,
    required this.groupMediaDeletionCleanup,
    this.privateMediaLifecycleRecovery,
    this.stopPrivateMediaExpiryScheduler,
    this.disposePrivateMediaExpiryScheduler,
    required this.chatMessageListener,
    required this.postListener,
    required this.postCommentListener,
    required this.postReactionListener,
    required this.postPresenceListener,
    required this.postPassListener,
    required this.postPinListener,
    required this.reactionListener,
    required this.messageDeletionListener,
    required this.profileUpdateListener,
    required this.messageRouter,
    required this.pendingMessageRetrier,
    required this.pendingPostMediaUploadRetrier,
    required this.pendingPostDeliveryRetrier,
    required this.pendingPostFollowOnRetrier,
    required this.keyExchangeRetrier,
    required this.bridge,
    required this.p2pService,
    this.transportMetrics,
    required this.mediaFileManager,
    required this.secureKeyStore,
    required this.imageProcessor,
    required this.audioRecorderService,
    this.privateMediaOutboxE2EController,
    this.debugE2EOverlayBuilder,
    this.debugE2EStartP2PNodeOverride,
    this.debugE2EAfterRuntimeReady,
    required this.reactionRepository,
    required this.isDesktop,
    required this.notificationService,
    this.groupNotificationPresentationCoordinator,
    this.groupNotificationPendingReadAcknowledgementResolver,
    this.droppedPushRecoveryCoordinator,
    required this.appShellController,
    required this.pendingPostTargetStore,
    required this.conversationTracker,
    required this.groupRepository,
    required this.groupMessageRepository,
    this.groupExitDiagnosticRepository,
    required this.groupInviteDeliveryAttemptRepository,
    required this.groupPendingKeyRepairRepository,
    required this.groupPendingReactionRepository,
    required this.groupPendingKeyRepairRunner,
    required this.groupPendingKeyRepairBackoffTimer,
    required this.groupPendingKeyDistributionRunner,
    this.groupExitIntentRecovery,
    this.canRejoinForExitIntent,
    this.processGroupExitIntent,
    required this.groupHistoryGapRepairRepository,
    required this.groupReactionReplayOutboxRepository,
    required this.groupMessageListener,
    this.groupMediaDownloadCoordinator,
    required this.groupInviteListener,
    required this.groupKeyUpdateListener,
    required this.groupKeyRepairResponderListener,
    required this.requestGroupKeyRepair,
    required this.groupMembershipUpdateListener,
    required this.groupConversationTracker,
    required this.introductionRepository,
    required this.introReviewSeenRepository,
    required this.introductionListener,
    required this.shareIntentService,
    this.pushRegistrationCoordinator,
    this.accountMigrationRunTransfer,
    this.accountMigrationSizeGate,
    this.accountMigrationStartReceiver,
    this.accountMigrationStopReceiver,
    this.accountMigrationReceiverEvents,
    this.accountMigrationRecoverExportPause,
    this.deferredRuntimeStartup,
    this.ingestStagedPushEnvelopes,
    this.firebaseReadiness,
    this.onAppDetached,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isResuming = false;
  final DroppedPushRecoveryRepollLatch _droppedPushRecoveryRepollLatch =
      DroppedPushRecoveryRepollLatch();
  // 164 (cold-start-1 regression #1): unconditional idempotence latch so the
  // initState _setupPushListeners() call and the post-runtime-ready re-arm cannot
  // double-register onMessage / onMessageOpenedApp.
  bool _pushListenersArmed = false;
  final NotificationOpenRouteCoordinator _notificationRouteCoordinator =
      NotificationOpenRouteCoordinator();
  DateTime? get _notificationTappedAt =>
      _notificationRouteCoordinator.activeTappedAt;
  // 133: a notification route must be pushed ON TOP of the startup home, not
  // before it — otherwise the StartupRouter's `pushReplacement(home)` clobbers
  // the just-pushed conversation and the user lands on Feed (Android cold-tap).
  // `_startupHomeReady` flips true when StartupRouter establishes the home; the
  // fallback timer guarantees a notification is never permanently stranded if
  // that signal never arrives (degrades to the legacy push-anyway behavior).
  bool _startupHomeReady = false;
  Timer? _homeReadyFallbackTimer;
  final NotificationOpenDeferredRetryScheduler
  _deferredNotificationRouteRetryScheduler =
      NotificationOpenDeferredRetryScheduler();
  static const Duration _homeReadyFallbackDelay = Duration(seconds: 8);
  static const Duration _deferredNotificationRouteRetryDelay = Duration(
    milliseconds: 250,
  );
  static const int _maxDeferredNotificationRouteAttempts = 2;
  late final PostNotificationOpenCoordinator _postNotificationOpenCoordinator;
  late final ContactRequestNotificationMaterializer
  _contactRequestNotificationMaterializer;
  late final IosApnsNotificationOpenBridge _iosApnsNotificationOpenBridge;
  final NotificationOpenDedupeGate _remoteNotificationOpenDedupeGate =
      NotificationOpenDedupeGate();
  late final Future<void> _initialShareIntentCapture;
  late final AccountMigrationRuntimeStartupLatch runtimeStartupLatch;
  // 181: FDC-09 §6.3 presence self-publish lifecycle driver. Announces
  // `foreground` on resume (+ arms a 60s heartbeat) and `background` on pause so
  // the relay can report this peer reachable/unreachable to senders — activating
  // the committed send-side `unreachable` short-circuit. Best-effort, never
  // load-bearing. Constructed from the concrete P2PServiceImpl (which implements
  // RelayPresenceSet — kept off the base P2PService interface to spare the ~31
  // fakes; no cast needed because widget.p2pService is the concrete type).
  late final SetPresenceUseCase _setPresenceUseCase;

  // 183: active-chat keepalive lifecycle driver. While foreground + in a 1:1
  // chat it pings the OPEN peer (~8s, under the ~30s QUIC idle) to keep the warm
  // connection alive and detect a drop in seconds, then REUSES warmPeer +
  // drainOfflineInbox (never a new re-dial/drain). Armed on resume, cancelled on
  // pause, disposed on teardown. The probe is the concrete P2PServiceImpl (which
  // implements PeerLivenessProbe — kept off the base P2PService interface to
  // spare the ~31 fakes; no cast needed); the active 1:1 peer comes from the
  // conversation tracker. Best-effort, never load-bearing.
  late final ActivePeerKeepAliveUseCase _keepAliveUseCase;

  // 191 (Fix D2): observable, retryable, idempotent push-listener arm. Owns the
  // onMessage/onMessageOpenedApp subscription + the PUSH_LISTENERS_ARMED
  // telemetry; _setupPushListeners delegates to it.
  late final PushListenerArmer _pushListenerArmer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    runtimeStartupLatch = AccountMigrationRuntimeStartupLatch(
      startRuntime: widget.deferredRuntimeStartup,
      onAttemptStarted: () {
        StartupTiming.instance.mark('deferred_runtime_start_begin');
      },
      onStarted: () {
        StartupTiming.instance.mark('deferred_runtime_start_complete');
        unawaited(_ingestStagedPushEnvelopes(source: 'runtime_ready'));
      },
    );
    _setPresenceUseCase = SetPresenceUseCase(presenceSetter: widget.p2pService);
    _keepAliveUseCase = ActivePeerKeepAliveUseCase(
      probe: widget.p2pService,
      activePeerId: () => widget.conversationTracker.activePeerId,
      onDropReWarm: widget.p2pService.warmPeer,
      onDropDrain: widget.p2pService.drainOfflineInbox,
      // 187: expose the keepalive drop latch to the send path (P2PServiceImpl
      // implements PeerDropSignal — no cast needed) so a send to a latched-
      // dropped active peer skips the doomed direct dial and leans on the
      // already-concurrent durable inbox.
      onLivenessChanged: widget.p2pService.setPeerDropSuspected,
    );
    widget.pendingMessageRetrier.setExternalRecoveryInProgressProvider(
      () => _isResuming || isGroupRecoveryInProgress(),
    );
    _postNotificationOpenCoordinator = PostNotificationOpenCoordinator(
      pendingTargetStore: widget.pendingPostTargetStore,
      postRepository: widget.postRepository,
      appShellController: widget.appShellController,
      revealPostsSurface: _revealPostsSurface,
    );
    _contactRequestNotificationMaterializer =
        ContactRequestNotificationMaterializer(
          requestRepository: widget.contactRequestRepository,
          contactRepository: widget.contactRepository,
          identityRepository: widget.repository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          onProfileDownloaded: widget.chatMessageListener.emitContactUpdate,
          presentPendingRequest:
              ({
                required navigator,
                required request,
                required onAccept,
                required onDecline,
              }) async {
                if (kE2ETestMode) {
                  return;
                }
                await showDialog<void>(
                  context: navigator.context,
                  barrierDismissible: false,
                  builder: (dialogContext) => ContactRequestDialog(
                    request: request,
                    onAccept: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(onAccept());
                    },
                    onDecline: () {
                      Navigator.of(dialogContext).pop();
                      unawaited(onDecline());
                    },
                  ),
                );
              },
          openConversation: ({required navigator, required contact}) =>
              _openConversationForContact(
                navigator: navigator,
                contact: contact,
              ),
        );
    // 191 (Fix D2): the foreground-push / open-app subscription + its
    // PUSH_LISTENERS_ARMED telemetry live in PushListenerArmer so the arm is
    // observable and unit-locked. _setupPushListeners delegates to arm().
    _pushListenerArmer = PushListenerArmer(
      firebaseReady: () => Firebase.apps.isNotEmpty,
      platform: kIsWeb ? 'web' : Platform.operatingSystem,
      subscribe: () {
        FirebaseMessaging.onMessage.listen((message) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_FOREGROUND_MESSAGE_RECEIVED',
            details: {
              'messageId': message.messageId,
              'dataKeys': message.data.keys.toList(),
            },
          );
          unawaited(_handleForegroundRemotePush(message));
        });

        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PUSH_MESSAGE_OPENED_APP',
            details: {
              'messageId': message.messageId,
              'dataKeys': message.data.keys.toList(),
            },
          );
          unawaited(_routeRemoteNotificationOpen(message.data));
        });
      },
    );
    _setupPushListeners();
    // 164 (cold-start-1 regression #1): Firebase is now initialized lazily inside
    // the deferred startLiveServices, so the _setupPushListeners() call above
    // no-ops on a normal launch (Firebase.apps is empty until runtime services
    // start). Re-arm the foreground-push + open-app listeners once runtime
    // services (hence Firebase) are ready. The unconditional _pushListenersArmed
    // latch inside _setupPushListeners keeps this idempotent against the (no-op)
    // initState call above.
    unawaited(_ensureRuntimeServicesReady().then((_) => _setupPushListeners()));
    final debugE2EAfterRuntimeReady = widget.debugE2EAfterRuntimeReady;
    if (debugE2EAfterRuntimeReady != null) {
      unawaited(
        _ensureRuntimeServicesReady().then((_) => debugE2EAfterRuntimeReady()),
      );
    }
    // 191 (Fix D2): a THIRD arm point rides Firebase first-success readiness —
    // the only event that flips Firebase.apps non-empty. If the
    // _ensureRuntimeServicesReady re-arm above fires while Firebase.apps is
    // still empty (a retried/late init), it no-ops WITHOUT consuming the
    // _pushListenersArmed latch; this readiness listener then arms the moment
    // Firebase actually becomes ready — so a transient init failure can never
    // leave push permanently disarmed.
    widget.firebaseReadiness?.addOnReadyListener(() {
      if (mounted) {
        _setupPushListeners();
      }
    });
    _setupNotificationTapHandler();
    widget.droppedPushRecoveryCoordinator?.registerNativeAcceleration(
      _handleNativeDroppedPushRecoverySignal,
    );
    _setupIosApnsNotificationOpenBridge();
    _setupShareIntentHandling();
    _initialShareIntentCapture = _captureInitialShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_flushDeferredNotificationRouteTarget());
    });
    // 183/181 (cold-start arm): Flutter delivers NO initial `resumed` lifecycle
    // transition on a fresh launch, so `_onResumed()` never runs and the
    // foreground-only heartbeats — the 183 active-chat keepalive and the 181
    // presence heartbeat — would stay DORMANT until the first
    // background→foreground cycle (device-proven 2026-07-01: no `peer:ping` until
    // the app was cycled). Arm them once at first frame IF the app launched
    // already foreground. Cheap timer-arms ONLY, never the full `_onResumed()`
    // cold-start work (that already runs via main()); idempotent — a later real
    // resume just re-arms the same timers (`onForegrounded()` cancels first).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _keepAliveUseCase.onForegrounded();
        unawaited(_setPresenceUseCase.onForegrounded());
      }
    });
    unawaited(_handleInitialLocalNotificationLaunchWhenReady());
  }

  Future<void> _ensureRuntimeServicesReady() {
    return runtimeStartupLatch.ensureStarted();
  }

  Future<bool> _hasPendingDroppedPushRecovery() async {
    final coordinator = widget.droppedPushRecoveryCoordinator;
    if (coordinator == null) return false;
    try {
      await _ensureRuntimeServicesReady();
      return await coordinator.hasPendingRecovery();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DROPPED_PUSH_RECOVERY_OWNERSHIP_POLL_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
      return true;
    }
  }

  Future<void> _recoverDroppedPushes() async {
    final coordinator = widget.droppedPushRecoveryCoordinator;
    if (coordinator == null) return;
    try {
      await _ensureRuntimeServicesReady();
      await coordinator.recoverIfPending();
    } catch (error) {
      // The coordinator is deliberately total, but retain an application-root
      // boundary so lifecycle delivery can never surface an uncaught error.
      emitFlowEvent(
        layer: 'FL',
        event: 'DROPPED_PUSH_RECOVERY_ROOT_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  Future<void> _handleNativeDroppedPushRecoverySignal() async {
    if (_isResuming) {
      // The durable marker remains authoritative. The active resume pass made
      // its ownership decision before ordinary drains, so a newer signal waits
      // for the next poll instead of racing that pass.
      _droppedPushRecoveryRepollLatch.request();
      emitFlowEvent(
        layer: 'FL',
        event: 'DROPPED_PUSH_RECOVERY_NATIVE_SIGNAL_DEFERRED',
        details: {'reason': 'resume_in_progress'},
      );
      return;
    }
    await _recoverDroppedPushes();
  }

  Future<void> _ingestStagedPushEnvelopes({required String source}) async {
    final ingest = widget.ingestStagedPushEnvelopes;
    if (ingest == null) {
      return;
    }
    try {
      await ingest(source: source);
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'STAGED_PUSH_ENVELOPE_INGEST_ERROR',
        details: {'source': source, 'error': e.toString()},
      );
    }
  }

  void _setupShareIntentHandling() {
    // Warm-start: share arrives while app is running
    widget.shareIntentService.intentStream.listen((intent) {
      unawaited(
        handleShareIntent(
          intent: intent,
          shareIntentService: widget.shareIntentService,
          navigator: MyApp.navigatorKey.currentState,
          buildRoute: _buildSharePickerRoute,
        ),
      );
    });
  }

  Future<void> _captureInitialShareIntent() async {
    if (widget.shareIntentService.hasPendingIntent) {
      _routeBufferedShareIfSettled();
      return;
    }

    final intent = await widget.shareIntentService.captureInitialIntent();
    if (intent == null || !mounted) {
      return;
    }

    _routeBufferedShareIfSettled();
  }

  void _routeBufferedShareIfSettled() {
    final navigator = MyApp.navigatorKey.currentState;
    if (!widget.shareIntentService.isSettled ||
        navigator == null ||
        !widget.shareIntentService.hasPendingIntent) {
      return;
    }

    final pendingIntent = widget.shareIntentService.consumePendingIntent();
    if (pendingIntent == null) {
      return;
    }

    widget.shareIntentService.reset();
    navigator.push(_buildSharePickerRoute(pendingIntent));
  }

  Route<void> _buildSharePickerRoute(ShareIntent intent) {
    return buildShareTargetPickerRoute(
      shareIntent: intent,
      identityRepo: widget.repository,
      contactRepository: widget.contactRepository,
      messageRepository: widget.messageRepository,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      chatMessageListener: widget.chatMessageListener,
      bridge: widget.bridge,
      p2pService: widget.p2pService,
      mediaFileManager: widget.mediaFileManager,
      imageProcessor: widget.imageProcessor,
      secureKeyStore: widget.secureKeyStore,
      conversationTracker: widget.conversationTracker,
      audioRecorderService: widget.audioRecorderService,
      reactionRepository: widget.reactionRepository,
      reactionListener: widget.reactionListener,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupInviteDeliveryAttemptRepository:
          widget.groupInviteDeliveryAttemptRepository,
      groupMessageListener: widget.groupMessageListener,
      groupConversationTracker: widget.groupConversationTracker,
      introductionRepository: widget.introductionRepository,
      appShellController: widget.appShellController,
      preSendReady: _ensureRuntimeServicesReady,
    );
  }

  void _setupNotificationTapHandler() {
    widget.notificationService.onNotificationTap = _onNotificationTap;
  }

  void _setupIosApnsNotificationOpenBridge() {
    _iosApnsNotificationOpenBridge = IosApnsNotificationOpenBridge();
    // 133: the `mknoon/ios_notification_open` MethodChannel only exists on iOS;
    // invoking it on Android throws MissingPluginException (log noise on every
    // cold start). Keep the field assigned (dispose references it) but only wire
    // the channel + readiness probe on iOS.
    if (!Platform.isIOS) return;
    _iosApnsNotificationOpenBridge.register(_routeRemoteNotificationOpen);
    unawaited(_prepareIosApnsNotificationOpenBridgeWhenReady());
  }

  Future<void> _prepareIosApnsNotificationOpenBridgeWhenReady({
    bool allowRetry = true,
  }) async {
    await _ensureRuntimeServicesReady();
    if (!mounted) {
      return;
    }
    final isReady = await _iosApnsNotificationOpenBridge
        .markNotificationOpenBridgeReady();
    if (!mounted) {
      return;
    }
    if (!isReady) {
      if (allowRetry) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future<void>.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              unawaited(
                _prepareIosApnsNotificationOpenBridgeWhenReady(
                  allowRetry: false,
                ),
              );
            }
          });
        });
      }
      return;
    }
    await _iosApnsNotificationOpenBridge.consumeInitialNotificationOpen(
      _routeRemoteNotificationOpen,
    );
  }

  Future<void> _routeRemoteNotificationOpen(Map<String, dynamic> data) async {
    if (!_remoteNotificationOpenDedupeGate.tryBegin(data)) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REMOTE_NOTIFICATION_OPEN_DEDUPED',
        details: {
          'dataKeys': data.keys.toList(growable: false),
          'dedupeKey': NotificationOpenDedupeGate.dedupeKeyFor(data) ?? '',
        },
      );
      return;
    }

    var routeSucceeded = false;
    NotificationOpenRouteContext? preparedContext;
    NotificationOpenRouteCompletion? routeCompletion;
    try {
      final routeTarget = NotificationRouteTarget.fromRemoteMessageData(data);
      // Mint the ordering ordinal immediately after synchronous validation.
      // Recent-announcement persistence, delivered-notification clearing, and
      // route preparation can all yield; none of them may let an older remote
      // tap borrow a newer ordinal when local and remote opens overlap.
      preparedContext = routeTarget == null
          ? null
          : _createNotificationOpenRouteContext(routeTarget);
      final markedRecentAnnouncement =
          await markRemoteNotificationOpenAsRecentAnnouncement(
            data: data,
            gate: recentRemoteNotificationGate,
          );
      if (markedRecentAnnouncement) {
        emitFlowEvent(
          layer: 'FL',
          event: 'REMOTE_NOTIFICATION_OPEN_MARKED_RECENT',
          details: {
            'kind': routeTarget?.kind.name ?? '',
            'hasMessageId':
                (remoteNotificationMessageIdFromData(data) ??
                        routeTarget?.messageId)
                    ?.isNotEmpty ==
                true,
          },
        );
      }
      final routeTargetResolved =
          await _withContactRequestPresentationSuppressed(
            routeTarget: routeTarget,
            action: () => routeAppRootRemoteNotificationOpenWithResult(
              data: data,
              prevalidatedRouteTarget: preparedContext?.routeTarget,
              onBeforeRouteTarget: (target) async {
                final context = preparedContext;
                if (context == null ||
                    !identical(context.routeTarget, target)) {
                  throw StateError(
                    'Remote notification route context was not validated.',
                  );
                }
                await _prepareNotificationRouteTarget(context.routeTarget);
              },
              onRouteTarget: (target) async {
                routeCompletion = await _dispatchPreparedNotificationRoute(
                  preparedContext,
                  target,
                );
                _throwIfNotificationRouteFailed(routeCompletion!);
              },
              onMissingGroupRouteId: _emitMissingGroupRouteId,
              onMissingRouteTarget: widget.p2pService.drainOfflineInbox,
            ),
          );
      routeSucceeded = didNotificationOpenRouteSucceed(
        routeTargetResolved: routeTargetResolved,
        completion: routeCompletion,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'REMOTE_NOTIFICATION_ROUTE_ERROR',
        details: {'error': e.toString()},
      );
    } finally {
      _remoteNotificationOpenDedupeGate.finish(data, success: routeSucceeded);
    }
  }

  Future<T> _withContactRequestPresentationSuppressed<T>({
    required NotificationRouteTarget? routeTarget,
    required Future<T> Function() action,
  }) async {
    final peerId =
        routeTarget?.kind == NotificationRouteTargetKind.contactRequest
        ? routeTarget?.peerId
        : null;
    if (peerId != null) {
      widget.contactRequestPresentationGate.suppress(peerId);
    }
    try {
      return await action();
    } finally {
      if (peerId != null) {
        widget.contactRequestPresentationGate.release(peerId);
      }
    }
  }

  Future<void> _emitMissingGroupRouteId(Map<String, dynamic> data) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'PUSH_GROUP_ROUTE_MISSING_GROUP_ID',
      details: NotificationRouteTarget.missingGroupIdTelemetryDetails(data),
    );
  }

  Future<void> _handleInitialLocalNotificationLaunchWhenReady() async {
    await _ensureRuntimeServicesReady();
    await _handleInitialLocalNotificationLaunch();
  }

  Future<void> _handleInitialLocalNotificationLaunch() async {
    NotificationOpenRouteContext? preparedContext;
    String? consumedPayload;
    try {
      await routeAppRootInitialLocalNotificationOpen(
        consumeInitialPayload: () async {
          consumedPayload = await widget.notificationService
              .consumeInitialPayload();
          return consumedPayload;
        },
        // A terminated local-notification open does not pass through the warm
        // callback. Create its immutable context only after payload parsing;
        // ordinary and malformed cold starts therefore create no route state.
        onBeforeRouteTarget: (target) async {
          emitFlowEvent(
            layer: 'FL',
            event: initialLocalNotificationRouteParsedEvent,
            details: initialLocalNotificationRouteParsedDetails(
              rawPayload: consumedPayload,
              target: target,
            ),
          );
          preparedContext = _createNotificationOpenRouteContext(target);
          await _prepareNotificationRouteTarget(target);
        },
        onRouteTarget: (target) async {
          final completion = await _dispatchPreparedNotificationRoute(
            preparedContext,
            target,
          );
          _throwIfNotificationRouteFailed(completion);
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<void> _onNotificationTap(String payload) async {
    NotificationOpenRouteContext? preparedContext;
    try {
      await routeAppRootLocalNotificationTap(
        payload: payload,
        onBeforeRouteTarget: (target) async {
          preparedContext = _createNotificationOpenRouteContext(target);
          await _prepareNotificationRouteTarget(target);
        },
        onRouteTarget: (target) async {
          final completion = await _dispatchPreparedNotificationRoute(
            preparedContext,
            target,
          );
          _throwIfNotificationRouteFailed(completion);
        },
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_TAP_NAV_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  NotificationOpenRouteContext _createNotificationOpenRouteContext(
    NotificationRouteTarget routeTarget,
  ) {
    return _notificationRouteCoordinator.createContext(
      routeTarget: routeTarget,
      tappedAt: DateTime.now(),
    );
  }

  Future<NotificationOpenRouteCompletion> _dispatchPreparedNotificationRoute(
    NotificationOpenRouteContext? preparedContext,
    NotificationRouteTarget routeTarget,
  ) async {
    if (preparedContext == null ||
        !identical(preparedContext.routeTarget, routeTarget)) {
      throw StateError('Notification route context was not prepared.');
    }
    final dispatch = await _dispatchNotificationRouteContext(preparedContext);
    return dispatch.completion;
  }

  Future<NotificationOpenRouteDispatch> _dispatchNotificationRouteContext(
    NotificationOpenRouteContext context,
  ) {
    return _notificationRouteCoordinator.dispatch(
      context: context,
      onRouteContext: _handleNotificationRouteTarget,
    );
  }

  Future<void> _beginStartupNotificationRouteContext(
    NotificationOpenRouteContext context,
  ) async {
    final dispatch = await _dispatchNotificationRouteContext(context);
    // StartupRouter must be allowed to establish the home before a deferred
    // open can complete. Observe the owned completion without awaiting it on
    // the startup critical path; the observer never throws.
    unawaited(
      _observeNotificationRouteCompletion(
        dispatch.completion,
        source: 'initial_remote',
      ),
    );
  }

  Future<void> _observeNotificationRouteCompletion(
    Future<NotificationOpenRouteCompletion> completionFuture, {
    required String source,
  }) async {
    final completion = await completionFuture;
    if (completion.status != NotificationOpenRouteCompletionStatus.failed) {
      return;
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'NOTIFICATION_DEFERRED_ROUTE_COMPLETION_ERROR',
      details: {'source': source, 'error': completion.error.toString()},
    );
  }

  void _dispatchNotificationRouteUnawaited(
    NotificationOpenRouteContext context, {
    required String source,
  }) {
    unawaited(() async {
      try {
        final dispatch = await _dispatchNotificationRouteContext(context);
        await _observeNotificationRouteCompletion(
          dispatch.completion,
          source: source,
        );
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'NOTIFICATION_ROUTE_ASYNC_ERROR',
          details: {'source': source, 'error': e.toString()},
        );
      }
    }());
  }

  void _throwIfNotificationRouteFailed(
    NotificationOpenRouteCompletion completion,
  ) {
    if (completion.status != NotificationOpenRouteCompletionStatus.failed) {
      return;
    }
    Error.throwWithStackTrace(
      completion.error!,
      completion.stackTrace ?? StackTrace.current,
    );
  }

  Future<NotificationOpenRouteDisposition> _handleNotificationRouteTarget(
    NotificationOpenRouteContext context,
  ) async {
    final routeTarget = context.routeTarget;
    assert(_notificationTappedAt == context.tappedAt);
    final navigator = MyApp.navigatorKey.currentState;
    // 133: defer until BOTH the navigator exists AND the startup home has been
    // established. Routing before the home is replaced lets StartupRouter's
    // `pushReplacement(home)` clobber the conversation we push (Android cold-tap
    // → Feed). The navigator-null case re-tries on the next frame; the
    // home-not-ready case waits for `_onStartupHomeReady` (or the fallback
    // timer), so we don't busy-loop for the ~1-2s until the home lands.
    if (navigator == null || !_startupHomeReady) {
      final accepted = _notificationRouteCoordinator.defer(context);
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_flushDeferredNotificationRouteTarget());
        });
      }
      _armHomeReadyFallback();
      return accepted
          ? NotificationOpenRouteDisposition.deferred
          : NotificationOpenRouteDisposition.superseded;
    }

    if (routeTarget.kind == NotificationRouteTargetKind.post ||
        routeTarget.kind == NotificationRouteTargetKind.postComment) {
      await _postNotificationOpenCoordinator.handleRouteTarget(
        routeTarget: routeTarget,
        drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      );
      return NotificationOpenRouteDisposition.routed;
    }

    switch (routeTarget.kind) {
      case NotificationRouteTargetKind.contactRequest:
        await _contactRequestNotificationMaterializer.handleRoute(
          navigator: navigator,
          peerId: routeTarget.peerId!,
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.intros:
        // 252: snapshot the tap timestamp (matching the conversation/group
        // branches) so an introducer-acceptance redirect can hand the
        // original tap context to the conversation screen; the shared
        // coordinator falls back to the Orbit/Intros route for everything
        // else.
        await openIntroAcceptNotificationRoute(
          routeTarget: routeTarget,
          notificationTappedAt: context.tappedAt,
          resolveTarget: (target) => resolveIntroductionNotificationTarget(
            routeTarget: target,
            introRepo: widget.introductionRepository,
            contactRepo: widget.contactRepository,
            loadOwnPeerId: () async =>
                (await widget.repository.loadIdentity())?.peerId,
            introStatusChanges:
                widget.introductionListener.introStatusChangedStream,
          ),
          isConversationAlreadyActive: (conversationTarget) =>
              isNotificationRouteTargetAlreadyActive(
                routeTarget: conversationTarget,
                groupConversationTracker: widget.groupConversationTracker,
                conversationTracker: widget.conversationTracker,
              ),
          openConversation: (contact, tappedAt) => _openConversationForContact(
            navigator: navigator,
            contact: contact,
            notificationTappedAt: tappedAt,
          ),
          openIntros: () => _openIntroOrbitRoute(navigator: navigator),
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.group:
        final identity = await widget.repository.loadIdentity();
        final resolution = await resolveGroupNotificationRouteTarget(
          groupId: routeTarget.groupId!,
          groupRepo: widget.groupRepository,
          pendingInviteRepo: widget.groupInviteListener.pendingInviteRepo,
          drainOfflineInbox: widget.p2pService.drainOfflineInbox,
          localPeerId: identity?.peerId,
        );
        if (!_notificationRouteCoordinator.isLatest(context)) {
          return NotificationOpenRouteDisposition.superseded;
        }
        if (resolution.group == null) {
          emitFlowEvent(
            layer: 'FL',
            event: resolution.hasPendingInvite
                ? 'GROUP_NOTIFICATION_ROUTE_PENDING_INVITE_REDIRECT'
                : 'GROUP_NOTIFICATION_ROUTE_GROUP_MISSING',
            details: {
              'groupId': routeTarget.groupId!.length > 8
                  ? routeTarget.groupId!.substring(0, 8)
                  : routeTarget.groupId!,
            },
          );
          if (resolution.hasPendingInvite) {
            await _openIntroOrbitRoute(navigator: navigator);
            return NotificationOpenRouteDisposition.routed;
          }
          if (!navigator.mounted) {
            // Neither the requested group nor the visible feedback/home
            // fallback was reached. Keep remote dedupe retryable instead of
            // falsely committing this dead tap as routed.
            throw StateError(
              'Group notification fallback navigator is not available.',
            );
          }
          // 04-P0 / QW-2: the group can't be resolved and there is no pending
          // invite — don't dead-tap silently. Show feedback (with a single
          // user-driven Retry that re-runs this handler) and route home. The
          // targeted drain already ran once inside
          // resolveGroupNotificationRouteTarget; Retry is not an auto-loop.
          final l10n = AppLocalizations.of(navigator.context);
          showGroupMissingNotificationFeedback(
            messenger: MyApp.scaffoldMessengerKey.currentState,
            navigator: navigator,
            message:
                l10n?.group_notification_catching_up ??
                'This group is still catching up — try again in a moment.',
            retryLabel: l10n?.btn_retry,
            onRetry: () => _dispatchNotificationRouteUnawaited(
              context,
              source: 'group_missing_retry',
            ),
          );
          return NotificationOpenRouteDisposition.routed;
        }
        final group = resolution.group!;
        if (isNotificationRouteTargetAlreadyActive(
          routeTarget: routeTarget,
          groupConversationTracker: widget.groupConversationTracker,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            details: {
              'groupId': routeTarget.groupId!.length > 8
                  ? routeTarget.groupId!.substring(0, 8)
                  : routeTarget.groupId!,
              'hasMessageId': routeTarget.messageId?.isNotEmpty == true,
            },
          );
          return NotificationOpenRouteDisposition.routed;
        }
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GroupConversationWired(
              group: group,
              groupRepo: widget.groupRepository,
              msgRepo: widget.groupMessageRepository,
              uploadRetryProjectionRepo: widget.groupMessageRepository,
              groupMessageListener: widget.groupMessageListener,
              groupMediaDownloadCoordinator:
                  widget.groupMediaDownloadCoordinator,
              openAnnouncementSenderConversation: (contact) =>
                  _openConversationForContact(
                    navigator: navigator,
                    contact: contact,
                  ),
              inviteDeliveryAttemptRepo:
                  widget.groupInviteDeliveryAttemptRepository,
              bridge: widget.bridge,
              identityRepo: widget.repository,
              contactRepo: widget.contactRepository,
              p2pService: widget.p2pService,
              groupConversationTracker: widget.groupConversationTracker,
              initialHighlightedMessageId: routeTarget.messageId,
              mediaAttachmentRepo: widget.mediaAttachmentRepository,
              mediaDeleteForMeCoordinator:
                  widget.groupMediaDeleteForMeCoordinator,
              mediaFileManager: widget.mediaFileManager,
              imageProcessor: widget.imageProcessor,
              audioRecorderService: widget.audioRecorderService,
              reactionRepo: widget.reactionRepository,
              groupReactionReplayOutboxRepository:
                  widget.groupReactionReplayOutboxRepository,
              historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
              notificationTappedAt: context.tappedAt,
              backgroundPreference:
                  widget.appShellController.backgroundPreference,
              forwardMessageRepository: widget.messageRepository,
              forwardChatMessageListener: widget.chatMessageListener,
            ),
          ),
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.conversation:
        // 139: mirror the group already-active guard. When the user taps a
        // fresh notification for a peer whose 1:1 conversation is already the
        // active (backgrounded) screen, do NOT push a second ConversationWired
        // — the mounted screen re-fetches the new message on resume
        // (conversation_wired.dart didChangeAppLifecycleState). Decided before
        // the contact lookup so suppression is a pure routing decision; when
        // `isViewing` is true the contact necessarily exists.
        if (isNotificationRouteTargetAlreadyActive(
          routeTarget: routeTarget,
          groupConversationTracker: widget.groupConversationTracker,
          conversationTracker: widget.conversationTracker,
        )) {
          emitFlowEvent(
            layer: 'FL',
            event: 'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
            details: {
              'peerId': routeTarget.peerId!.length > 8
                  ? routeTarget.peerId!.substring(0, 8)
                  : routeTarget.peerId!,
            },
          );
          return NotificationOpenRouteDisposition.routed;
        }
        final contact = await widget.contactRepository.getContact(
          routeTarget.peerId!,
        );
        if (!_notificationRouteCoordinator.isLatest(context)) {
          return NotificationOpenRouteDisposition.superseded;
        }
        if (contact == null) {
          // The inbox/contact materialization can lag the notification. A
          // silent no-op is not a successful route: surface failure to the
          // deferred retry/remote dedupe owner so another tap can succeed once
          // the contact is available.
          throw StateError(
            'Notification conversation contact is not available yet.',
          );
        }
        await _openConversationForContact(
          navigator: navigator,
          contact: contact,
          notificationTappedAt: context.tappedAt,
        );
        return NotificationOpenRouteDisposition.routed;
      case NotificationRouteTargetKind.post:
      case NotificationRouteTargetKind.postComment:
        return NotificationOpenRouteDisposition.routed;
    }
  }

  Future<void> _openIntroOrbitRoute({required NavigatorState navigator}) async {
    await openIntroNotificationOrbitRoute(
      navigator: navigator,
      appShellController: widget.appShellController,
      messageRepository: widget.messageRepository,
      builder: (feedUnreadCountListenable) => OrbitWired(
        groupMediaDeleteForMeCoordinator:
            widget.groupMediaDeleteForMeCoordinator,
        identityRepo: widget.repository,
        contactRepo: widget.contactRepository,
        contactRequestRepo: widget.contactRequestRepository,
        contactRequestListener: widget.contactRequestListener,
        messageRepo: widget.messageRepository,
        postRepository: widget.postRepository,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        chatMessageListener: widget.chatMessageListener,
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        mediaFileManager: widget.mediaFileManager,
        secureKeyStore: widget.secureKeyStore,
        imageProcessor: widget.imageProcessor,
        feedClearedRepository: widget.feedClearedRepository,
        conversationTracker: widget.conversationTracker,
        audioRecorderService: widget.audioRecorderService,
        reactionRepository: widget.reactionRepository,
        reactionListener: widget.reactionListener,
        groupRepository: widget.groupRepository,
        groupMessageRepository: widget.groupMessageRepository,
        groupExitDiagnosticRepository: widget.groupExitDiagnosticRepository,
        groupInviteDeliveryAttemptRepository:
            widget.groupInviteDeliveryAttemptRepository,
        groupPendingKeyRepairRepository: widget.groupPendingKeyRepairRepository,
        groupHistoryGapRepairRepository: widget.groupHistoryGapRepairRepository,
        groupReactionReplayOutboxRepository:
            widget.groupReactionReplayOutboxRepository,
        groupMessageListener: widget.groupMessageListener,
        groupMediaDownloadCoordinator: widget.groupMediaDownloadCoordinator,
        groupInviteListener: widget.groupInviteListener,
        waitForGroupMembershipUpdateIdle:
            widget.groupMembershipUpdateListener.waitForIdle,
        groupConversationTracker: widget.groupConversationTracker,
        introductionRepository: widget.introductionRepository,
        introReviewSeenRepository: widget.introReviewSeenRepository,
        introductionListener: widget.introductionListener,
        appShellController: widget.appShellController,
        feedUnreadCountListenable: feedUnreadCountListenable,
        pendingPostTargetStore: widget.pendingPostTargetStore,
        postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
        initialFilterTab: 'intros',
        transportMetrics: widget.transportMetrics,
        accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
        accountMigrationSizeGate: widget.accountMigrationSizeGate,
        // 206: the Orbit center avatar opens Settings; thread the nearby service
        // so its posts-nearby refresh is functional on this construction path.
        nearbyLocationService: widget.nearbyLocationService,
      ),
    );
  }

  Future<void> _openConversationForContact({
    required NavigatorState navigator,
    required ContactModel contact,
    DateTime? notificationTappedAt,
  }) async {
    await navigator.push(
      buildConversationRoute(
        builder: (_) => ConversationWired(
          contact: contact,
          identityRepo: widget.repository,
          messageRepo: widget.messageRepository,
          uploadRetryProjectionRepo: widget.messageRepository,
          chatMessageListener: widget.chatMessageListener,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          contactRepo: widget.contactRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
          imageProcessor: widget.imageProcessor,
          conversationTracker: widget.conversationTracker,
          audioRecorderService: widget.audioRecorderService,
          reactionRepo: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          introductionRepository: widget.introductionRepository,
          forwardGroupRepository: widget.groupRepository,
          forwardGroupMessageRepository: widget.groupMessageRepository,
          forwardGroupInviteDeliveryAttemptRepository:
              widget.groupInviteDeliveryAttemptRepository,
          forwardGroupMessageListener: widget.groupMessageListener,
          forwardGroupConversationTracker: widget.groupConversationTracker,
          appShellController: widget.appShellController,
          notificationTappedAt: notificationTappedAt,
          transportMetrics: widget.transportMetrics,
          privateMediaOutboxE2EController:
              widget.privateMediaOutboxE2EController,
        ),
      ),
    );
  }

  void _revealPostsSurface() {
    final navigator = MyApp.navigatorKey.currentState;
    if (navigator == null) {
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _flushDeferredNotificationRouteTarget() async {
    try {
      if (_notificationRouteCoordinator.deferred == null) {
        return;
      }
      final navigator = MyApp.navigatorKey.currentState;
      if (navigator == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_flushDeferredNotificationRouteTarget());
        });
        return;
      }
      // 133: hold the route until the startup home is up;
      // `_onStartupHomeReady` (or the fallback timer) re-invokes this flush
      // once it is, so the conversation lands ON TOP of the home rather than
      // being replaced by it. The coordinator keeps ownership during the
      // attempt and CAS-clears only after actual route success.
      if (!_startupHomeReady) {
        _armHomeReadyFallback();
        return;
      }
      final result = await _notificationRouteCoordinator.runDeferredAttempt(
        maxAttempts: _maxDeferredNotificationRouteAttempts,
        onRouteContext: _handleNotificationRouteTarget,
      );
      switch (result.status) {
        case NotificationOpenDeferredAttemptStatus.retry:
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_DEFERRED_ROUTE_ATTEMPT_ERROR',
            details: {
              'attempt': result.attempt,
              'maxAttempts': _maxDeferredNotificationRouteAttempts,
              'willRetry': true,
              'routeKind': result.context?.routeTarget.kind.name ?? '',
              'error': result.error.toString(),
            },
          );
          final retryContext = result.context!;
          _deferredNotificationRouteRetryScheduler.schedule(
            ownerOrdinal: retryContext.ordinal,
            delay: _deferredNotificationRouteRetryDelay,
            onRetry: () {
              if (!mounted ||
                  _notificationRouteCoordinator.deferred?.ordinal !=
                      retryContext.ordinal) {
                return;
              }
              unawaited(_flushDeferredNotificationRouteTarget());
            },
          );
          return;
        case NotificationOpenDeferredAttemptStatus.failed:
          emitFlowEvent(
            layer: 'FL',
            event: 'NOTIFICATION_DEFERRED_ROUTE_ATTEMPT_ERROR',
            details: {
              'attempt': result.attempt,
              'maxAttempts': _maxDeferredNotificationRouteAttempts,
              'willRetry': false,
              'routeKind': result.context?.routeTarget.kind.name ?? '',
              'error': result.error.toString(),
            },
          );
          final failedContext = result.context;
          if (failedContext != null) {
            _deferredNotificationRouteRetryScheduler.cancelIfOwnedBy(
              failedContext.ordinal,
            );
          }
          return;
        case NotificationOpenDeferredAttemptStatus.none:
          return;
        case NotificationOpenDeferredAttemptStatus.routed:
        case NotificationOpenDeferredAttemptStatus.retained:
        case NotificationOpenDeferredAttemptStatus.superseded:
          final completedContext = result.context;
          if (completedContext != null) {
            _deferredNotificationRouteRetryScheduler.cancelIfOwnedBy(
              completedContext.ordinal,
            );
          }
          return;
      }
    } catch (e) {
      // Every caller intentionally starts this flush unawaited. Keep this
      // boundary total so an unexpected implementation error is observable but
      // can never become an uncaught zone error.
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_DEFERRED_ROUTE_FLUSH_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  /// 133: StartupRouter has established the home surface — release any deferred
  /// notification route so it is pushed on top of it.
  void _onStartupHomeReady() {
    _homeReadyFallbackTimer?.cancel();
    _homeReadyFallbackTimer = null;
    if (_startupHomeReady) return;
    _startupHomeReady = true;
    unawaited(_flushDeferredNotificationRouteTarget());
  }

  /// 133 safety net: if the home-ready signal never arrives (an abnormal startup
  /// path that bypasses StartupRouter), flush anyway after a bounded delay so a
  /// tapped notification is never permanently stranded — degrading to the legacy
  /// push-immediately behavior rather than a worse regression.
  void _armHomeReadyFallback() {
    if (_startupHomeReady) return;
    _homeReadyFallbackTimer ??= Timer(_homeReadyFallbackDelay, () {
      _homeReadyFallbackTimer = null;
      if (_startupHomeReady) return;
      emitFlowEvent(
        layer: 'FL',
        event: 'NOTIFICATION_ROUTE_HOME_READY_FALLBACK',
        details: {},
      );
      _startupHomeReady = true;
      unawaited(_flushDeferredNotificationRouteTarget());
    });
  }

  Future<void> _prepareNotificationRouteTarget(
    NotificationRouteTarget routeTarget,
  ) async {
    final identity = await widget.repository.loadIdentity();
    await prepareNotificationRouteTarget(
      routeTarget: routeTarget,
      drainOfflineInbox: () => _runAccountRuntimeNetworkVoidAction(
        operation: 'push_notification_open_inbox_drain',
        action: widget.p2pService.drainOfflineInbox,
      ),
      bridge: widget.bridge,
      groupRepository: widget.groupRepository,
      groupMessageRepository: widget.groupMessageRepository,
      groupMessageListener: widget.groupMessageListener,
      mediaAttachmentRepository: widget.mediaAttachmentRepository,
      reactionRepository: widget.reactionRepository,
      groupPendingReactionRepository: widget.groupPendingReactionRepository,
      accountMigrationNetworkGate: AccountMigrationRuntimeNetworkGate(
        authorityRepository: SecureKeyStoreAccountMigrationAuthorityRepository(
          secureKeyStore: widget.secureKeyStore,
        ),
      ).allowsAccountNetworkSideEffects,
      selfPeerId: identity?.peerId,
      // FDC-04 (WIRE-1): the only seam holding a P2PService — supply the real
      // eager-warm fn so a warm notif-tap overlaps the dial with the screen.
      warmPeer: widget.p2pService.warmPeer,
      ingestStagedPushEnvelopes: () =>
          _ingestStagedPushEnvelopes(source: 'notification_tap_prepare'),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.disposePrivateMediaExpiryScheduler?.call();

    // Orderly teardown: retriers → listeners → router → service → bridge
    widget.keyExchangeRetrier.dispose();
    widget.pendingPostFollowOnRetrier.dispose();
    widget.pendingPostDeliveryRetrier.dispose();
    widget.pendingPostMediaUploadRetrier.dispose();
    widget.pendingMessageRetrier.dispose();
    widget.groupPendingKeyRepairBackoffTimer.dispose();
    widget.introductionListener.dispose();
    widget.groupMembershipUpdateListener.dispose();
    widget.groupKeyUpdateListener.dispose();
    widget.groupKeyRepairResponderListener.dispose();
    widget.groupInviteListener.dispose();
    widget.groupMessageListener.dispose();
    widget.profileUpdateListener.dispose();
    widget.reactionListener.dispose();
    widget.messageDeletionListener.dispose();
    widget.postListener.dispose();
    widget.postCommentListener.dispose();
    widget.postReactionListener.dispose();
    widget.postPresenceListener.dispose();
    widget.postPassListener.dispose();
    widget.postPinListener.dispose();
    widget.chatMessageListener.dispose();
    widget.contactRequestListener.dispose();
    _postNotificationOpenCoordinator.dispose();
    // 181: cancel the 60s presence heartbeat Timer.
    _setPresenceUseCase.dispose();
    // 183: cancel the ~8s keepalive Timer (no leak).
    _keepAliveUseCase.dispose();
    widget.pushRegistrationCoordinator?.dispose();
    widget.droppedPushRecoveryCoordinator?.dispose();
    widget.contactPresenceSnapshotRepository.dispose();
    widget.postRepository.dispose();
    widget.messageRouter.dispose();
    widget.p2pService.dispose();
    widget.bridge.dispose();
    widget.audioRecorderService.dispose();
    _homeReadyFallbackTimer?.cancel();
    _deferredNotificationRouteRetryScheduler.cancelAll();
    _notificationRouteCoordinator.cancelDeferred();
    _iosApnsNotificationOpenBridge.dispose();
    widget.notificationService.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] AppLifecycleState changed → ${state.name}');
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_STATE_CHANGED',
      details: {'state': state.name},
    );

    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }

    // Commit any in-flight 'sending' messages to 'failed' before
    // the OS may freeze or kill this process. Using 'paused' and 'hidden'
    // because 'inactive' is a transient state visited during foreground
    // app-switcher and does not reliably precede backgrounding.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _onPaused();
    }

    // App is terminating: release the node + DB so the next cold start doesn't
    // stall on the splash screen behind a stale lock/socket. Intentionally NOT
    // on 'paused'/'hidden' — those fire on transient backgrounding (app
    // switcher, biometric prompt) and tearing the node down there would kill
    // connectivity on every app switch.
    if (state == AppLifecycleState.detached) {
      _onDetached();
    }
  }

  void _onDetached() {
    if (kDebugMode) {
      debugPrint('[LIFECYCLE] detached — running best-effort teardown');
    }
    final onAppDetached = widget.onAppDetached;
    if (onAppDetached != null) {
      // Fire-and-forget: the teardown itself is internally time-bounded.
      unawaited(onAppDetached());
    }
  }

  void _onPaused() {
    widget.stopPrivateMediaExpiryScheduler?.call();
    // Fire-and-forget (PS-4): we have at most a few hundred milliseconds of
    // foreground execution. handleAppPaused() is local-DB-only EXCEPT for the
    // FDC-06 bounded pause-flush, which ships ENABLED (kFdcPauseFlushEnabled;
    // kill-switch --dart-define=FDC_PAUSE_FLUSH_DISABLE=1). The flush NARROWS
    // (does not delete) the "no network on pause" rule to a single *bounded,
    // bg-assertion-protected, inbox-store-only* deposit of the newest in-flight
    // sends — persisting each accepted row to durable custody
    // ('inboxed'/'inbox') and marking the rest failed — with no unbounded
    // network and no held connection.
    //
    // Stays `unawaited` (FDC-06 Step 7, resolved): the assertion is acquired
    // inside handleAppPaused (callBgBegin) before the first network await, and
    // once held it is the native OS background task — not this Dart future —
    // that keeps the process alive across the deposit (S4 device-verified, the
    // same window the interactive send path already relies on). If a device
    // flake ever appears, the fallback is a bounded `await` here that still
    // never throws.
    //
    // FDC-S4 grant-probe is MEASUREMENT-ONLY (kFdcPauseGrantProbeEnabled, armed
    // by --dart-define=FDC_PAUSE_FLUSH=1) and must NOT fire in a normal build —
    // it takes a ~1.5s bg assertion on every pause. Kept until T8 closes on a
    // 2nd iOS major (the device RESULTS parser greps PAUSE_GRANT_PROBE).
    // 181: announce `background` (best-effort, fire-and-forget) so the relay
    // reports this peer `unreachable` to senders. The publish is unawaited INSIDE
    // onBackgrounded() — it must NOT block or widen the bounded FDC-06 pause
    // window (no new bg assertion); it also cancels the foreground heartbeat so
    // no timer fires while suspended. A lost publish is acceptable (presence is
    // non-load-bearing; the entry lapses to `unknown` after the ~180s self-TTL).
    unawaited(_setPresenceUseCase.onBackgrounded());
    // 183: cancel the active-chat keepalive loop on pause (zero pings while
    // suspended; resume re-arms it).
    _keepAliveUseCase.onBackgrounded();
    if (kFdcPauseGrantProbeEnabled) {
      unawaited(probePauseBackgroundGrant(widget.bridge));
    }
    unawaited(
      handleAppPaused(
            messageRepo: widget.messageRepository,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            groupMsgRepo: widget.groupMessageRepository,
            enablePauseFlush: kFdcPauseFlushEnabled,
            p2pService: widget.p2pService,
            bridge: widget.bridge,
          )
          .then((result) {
            if (kDebugMode) {
              debugPrint(
                '[LIFECYCLE] _onPaused() complete: '
                'transitioned=${result.transitionedCount} '
                'groupTransitioned=${result.groupTransitionedCount}',
              );
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_PAUSED_COMPLETE',
              details: {
                'transitionedCount': result.transitionedCount,
                'groupTransitionedCount': result.groupTransitionedCount,
              },
            );
          })
          .catchError((Object e) {
            if (kDebugMode) {
              debugPrint('[LIFECYCLE] _onPaused() error: $e');
            }
            emitFlowEvent(
              layer: 'FL',
              event: 'APP_LIFECYCLE_PAUSED_ERROR',
              details: {'error': e.toString()},
            );
          }),
    );
  }

  Future<void> _onResumed() async {
    // Private lifecycle recovery has its own generation/queue. Start it before
    // the broad network-resume coalescing guard: resume A may still be pending
    // after a pause when resume B arrives, and B must be able to re-arm the
    // foreground expiry scheduler independently.
    Future<void>? privateMediaRecovery;
    try {
      privateMediaRecovery = widget.privateMediaLifecycleRecovery?.call();
    } catch (error, stackTrace) {
      privateMediaRecovery = Future<void>.error(error, stackTrace);
    }
    if (_isResuming) {
      _droppedPushRecoveryRepollLatch.request();
      debugPrint('[LIFECYCLE] _onResumed() skipped — already resuming');
      if (privateMediaRecovery != null) {
        try {
          await privateMediaRecovery;
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_COALESCED_PRIVATE_MEDIA_RECOVERY_DONE',
            details: {},
          );
        } catch (error) {
          emitFlowEvent(
            layer: 'FL',
            event: 'APP_LIFECYCLE_COALESCED_PRIVATE_MEDIA_RECOVERY_FAILED',
            details: {'error': error.runtimeType.toString()},
          );
        }
      }
      return;
    }
    _isResuming = true;
    debugPrint('[LIFECYCLE] _onResumed() starting handleAppResumed...');
    var droppedPushRecoveryOwnsInbox = false;

    try {
      widget.p2pService.markResumeStarted();
      // 181: announce `foreground` (+ arm the 60s presence heartbeat) on resume.
      // Unawaited — best-effort hint, must add no latency to the resume path.
      unawaited(_setPresenceUseCase.onForegrounded());
      // 183: arm the active-chat keepalive loop on resume (foreground-only — it
      // can never fire while suspended).
      _keepAliveUseCase.onForegrounded();
      unawaited(_ingestStagedPushEnvelopes(source: 'app_resumed'));
      droppedPushRecoveryOwnsInbox = await _hasPendingDroppedPushRecovery();
      await handleAppResumed(
        bridge: widget.bridge,
        p2pService: widget.p2pService,
        // FDC-04 (SRC-1): the 1:1 active-peer source for resume eager-warm
        // (PS-4 — only the open conversation, never the roster).
        activeConversationPeerId: () => widget.conversationTracker.activePeerId,
        recoverInterruptedExportPause:
            widget.accountMigrationRecoverExportPause,
        // 235: local deletion-journal cleanup — before the network gate.
        groupMediaDeletionCleanupFn: widget.groupMediaDeletionCleanup,
        privateMediaLifecycleRecoveryFn: privateMediaRecovery == null
            ? null
            : () => privateMediaRecovery!,
        retryPushRegistrationFn: widget.pushRegistrationCoordinator?.retryNow,
        skipDirectInboxDrain: droppedPushRecoveryOwnsInbox,
        skipGroupInboxDrain: droppedPushRecoveryOwnsInbox,
        contactRepo: widget.contactRepository,
        identityRepo: widget.repository,
        retryIncompleteKeyExchangesFn: () =>
            widget.keyExchangeRetrier.retryNow(trigger: 'app_resumed'),
        groupRepo: widget.groupRepository,
        groupMsgRepo: widget.groupMessageRepository,
        groupMessageListener: widget.groupMessageListener,
        canRejoinForExitIntent: widget.canRejoinForExitIntent,
        processExitIntent: widget.processGroupExitIntent,
        pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
        drainPendingKeyDistributionsFn:
            widget.groupPendingKeyDistributionRunner.drainAllPending,
        retryAllPendingGroupKeyRepairsFn:
            widget.groupPendingKeyRepairRunner.retryAllPending,
        historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
        requestGroupKeyRepair: widget.requestGroupKeyRepair,
        mediaAttachmentRepo: widget.mediaAttachmentRepository,
        reactionRepo: widget.reactionRepository,
        pendingReactionRepo: widget.groupPendingReactionRepository,
        nearbyLocationService: widget.nearbyLocationService,
        retryPendingPostMediaUploads:
            widget.pendingPostMediaUploadRetrier.retryNow,
        retryPendingPostDeliveries: widget.pendingPostDeliveryRetrier.retryNow,
        recoverStuckSendingMessagesFn: () =>
            recoverStuckSendingMessages(messageRepo: widget.messageRepository),
        recoverStuckSendingGroupMessagesFn: () =>
            recoverStuckSendingGroupMessages(
              groupMsgRepo: widget.groupMessageRepository,
            ),
        accountMigrationNetworkGate: AccountMigrationRuntimeNetworkGate(
          authorityRepository:
              SecureKeyStoreAccountMigrationAuthorityRepository(
                secureKeyStore: widget.secureKeyStore,
              ),
        ).allowsAccountNetworkSideEffects,
        retryIncompleteGroupUploadsFn: () => retryIncompleteGroupUploads(
          groupRepo: widget.groupRepository,
          groupMsgRepo: widget.groupMessageRepository,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.repository,
          mediaFileManager: widget.mediaFileManager,
          inviteDeliveryAttemptRepo:
              widget.groupInviteDeliveryAttemptRepository,
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.resume,
              ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
          requireOsConnectivity: true,
        ),
        retryIncompleteGroupDownloadsFn:
            widget.groupMediaDownloadCoordinator?.call,
        retryFailedGroupMessagesFn: () => retryFailedGroupMessages(
          groupMsgRepo: widget.groupMessageRepository,
          groupRepo: widget.groupRepository,
          identityRepo: widget.repository,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          inviteDeliveryAttemptRepo:
              widget.groupInviteDeliveryAttemptRepository,
        ),
        retryPendingIntroductionDeliveriesFn: () =>
            retryPendingIntroductionDeliveries(
              introRepo: widget.introductionRepository,
              p2pService: widget.p2pService,
            ),
        retryIncompleteUploadsFn: () => retryIncompleteUploads(
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          messageRepo: widget.messageRepository,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          mediaFileManager: widget.mediaFileManager,
          isUploadInFlight: mediaUploadInFlightTracker.isInFlight,
          tryClaimUploadLease: (attachmentIds) =>
              mediaUploadInFlightTracker.tryClaimAll(
                attachmentIds,
                source: MediaUploadTriggerSource.resume,
              ),
          releaseUploadLease: mediaUploadInFlightTracker.release,
          requireOsConnectivity: true,
        ),
        retryFailedMessagesFn: () => retryFailedMessages(
          messageRepo: widget.messageRepository,
          identityRepo: widget.repository,
          contactRepo: widget.contactRepository,
          p2pService: widget.p2pService,
          bridge: widget.bridge,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          mediaFileManager: widget.mediaFileManager,
        ),
        retryUnackedMessagesFn: () => retryUnackedMessages(
          messageRepo: widget.messageRepository,
          p2pService: widget.p2pService,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
        ),
        verifyInboxCustodyFn: () => verifyInboxCustody(
          loadInboxCustody:
              widget.messageRepository.getInboxCustodyOutgoingMessages,
          storeInInboxDetailed: widget.p2pService.storeInInboxDetailed,
          markCustodyChecked: widget.messageRepository.markInboxCustodyChecked,
          messageRepo: widget.messageRepository,
        ),
        retryFailedGroupInboxStoresFn: () => retryFailedGroupInboxStores(
          bridge: widget.bridge,
          msgRepo: widget.groupMessageRepository,
          reactionReplayOutboxRepo: widget.groupReactionReplayOutboxRepository,
          groupRepo: widget.groupRepository,
          identityRepo: widget.repository,
        ),
      );
      // PB264-18: only start the global role/exit pass after the awaited resume
      // pipeline has rejoined each eligible topic and run its exact per-group
      // drain/exit continuation. Starting this before handleAppResumed lets a
      // native-leave phase overtake watchdog rejoin after process recreation.
      // The wrapper is error-isolated and a still-offline retry stays durable.
      final recoverGroupExits = widget.groupExitIntentRecovery;
      if (recoverGroupExits != null) {
        unawaited(recoverGroupExits());
      } else {
        // Compatibility for lightweight MyApp widget harnesses.
        unawaited(triggerGroupPendingBroadcastDrainAll());
      }
      await sweepExpiredPosts(
        postRepo: widget.postRepository,
        mediaFileManager: widget.mediaFileManager,
      );
      // Placed last in the resume path: the 7d invite TTL never races the
      // seconds-scale accept-recovery / inbox-drain work above.
      await sweepExpiredGroupInvites(
        repo: widget.groupInviteListener.pendingInviteRepo,
      );
      widget.p2pService.checkResumeAlreadyOnline();
    } finally {
      if (droppedPushRecoveryOwnsInbox) {
        // The ownership preflight suppressed both ordinary inbox legs, so this
        // is the only canonical full direct+group drain for the pending wake.
        await _recoverDroppedPushes();
      }
      await _droppedPushRecoveryRepollLatch.drain(
        hasPendingRecovery: _hasPendingDroppedPushRecovery,
        recoverIfPending: _recoverDroppedPushes,
      );
      widget.p2pService.clearResumeStarted();
      _isResuming = false;
      debugPrint('[LIFECYCLE] _onResumed() finished');
    }
  }

  void _setupPushListeners() {
    if (widget.isDesktop || Firebase.apps.isEmpty) return;
    // 164: latch AFTER the empty-Firebase.apps guard so the no-op initState call
    // on a normal launch does NOT consume the latch — the post-ready re-arm is
    // then the first effective registration; a third call is a no-op.
    if (_pushListenersArmed) return;
    _pushListenersArmed = true;
    // 191 (Fix D2): the subscription + PUSH_LISTENERS_ARMED / PUSH_LISTENER_ERROR
    // telemetry live in the observable, unit-locked PushListenerArmer. The
    // widget-level guard + _pushListenersArmed latch above preserve the 164
    // idempotence contract; the armer carries its own latch too.
    _pushListenerArmer.arm();
  }

  Future<void> _handleForegroundRemotePush(RemoteMessage message) async {
    final result = await handleForegroundRemoteMessage(
      data: message.data,
      messageId: message.messageId,
      // Off-iOS the gate has no sidecar dir provider, so the discard is a
      // no-op; passing unconditionally keeps the wiring platform-free.
      recentRemoteGate: recentRemoteNotificationGate,
      drainOfflineInbox: () => _runAccountRuntimeNetworkVoidAction(
        operation: 'push_foreground_inbox_drain',
        action: widget.p2pService.drainOfflineInbox,
      ),
      drainGroupOfflineInboxForGroup: (groupId) async {
        if (!await _allowsAccountRuntimeNetworkSideEffects(
          'push_foreground_group_drain',
        )) {
          return;
        }
        final identity = await widget.repository.loadIdentity();
        return drainGroupOfflineInboxForGroup(
          bridge: widget.bridge,
          groupRepo: widget.groupRepository,
          msgRepo: widget.groupMessageRepository,
          groupId: groupId,
          mediaAttachmentRepo: widget.mediaAttachmentRepository,
          reactionRepo: widget.reactionRepository,
          pendingReactionRepo: widget.groupPendingReactionRepository,
          groupMessageListener: widget.groupMessageListener,
          pendingKeyRepairRepo: widget.groupPendingKeyRepairRepository,
          historyGapRepairRepo: widget.groupHistoryGapRepairRepository,
          requestGroupKeyRepair: widget.requestGroupKeyRepair,
          selfPeerId: identity?.peerId,
        );
      },
    );

    DurableNotificationToneLease? groupReactionCoordinator;
    DurableNotificationToneLease? groupMessageCoordinator;
    Future<DurableNotificationToneLease>
    resolveGroupReactionCoordinator() async {
      return groupReactionCoordinator ??=
          await DurableNotificationToneLease.openDefault();
    }

    Future<DurableNotificationToneLease>
    resolveGroupMessageCoordinator() async {
      return groupMessageCoordinator ??=
          await DurableNotificationToneLease.openMobileDefault();
    }

    try {
      if (result == ForegroundRemoteMessageResult.notificationNeeded &&
          !await _allowsAccountRuntimeNetworkSideEffects(
            'push_foreground_notification_display',
          )) {
        return;
      }
      await showForegroundPushFallbackNotificationIfNeeded(
        result: result,
        notificationService: widget.notificationService,
        message: message,
        groupMessageDisplayEligibilityResolver: (groupId) async {
          final identity = await widget.repository.loadIdentity();
          return resolveGroupMessageNotificationDisplayEligibility(
            groupId: groupId,
            groupRepo: widget.groupRepository,
            pendingInviteRepo: widget.groupInviteListener.pendingInviteRepo,
            localPeerId: identity?.peerId,
          );
        },
        groupReactionNotificationResolver:
            _resolveForegroundGroupReactionNotification,
        durableReactionNotificationCoordinatorResolver:
            resolveGroupReactionCoordinator,
        groupConversationTracker: widget.groupConversationTracker,
        getAppLifecycleState: () =>
            WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
        durableGroupMessageNotificationCoordinatorResolver:
            resolveGroupMessageCoordinator,
        groupNotificationPresentationCoordinator:
            widget.groupNotificationPresentationCoordinator,
        groupNotificationReadAcknowledgementResolver:
            _isForegroundGroupNotificationReadAcknowledged,
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_FOREGROUND_FALLBACK_NOTIFICATION_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  Future<bool> _isForegroundGroupNotificationReadAcknowledged({
    required String groupId,
    required ConversationNotificationContentKind contentKind,
    required String eventIdentity,
    required BackgroundManagedGroupNotificationComparand? comparand,
  }) async {
    try {
      return resolveForegroundGroupNotificationReadAcknowledgement(
        groupId: groupId,
        contentKind: contentKind,
        eventIdentity: eventIdentity,
        pendingReadAcknowledgementResolver:
            widget.groupNotificationPendingReadAcknowledgementResolver,
        canonicalReadAcknowledgementResolver: () async {
          switch (contentKind) {
            case ConversationNotificationContentKind.message:
              final canonical = await widget.groupMessageRepository.getMessage(
                eventIdentity,
              );
              return isExactForegroundGroupMessageReadAcknowledgement(
                groupId: groupId,
                eventIdentity: eventIdentity,
                canonicalGroupId: canonical?.groupId,
                canonicalMessageId: canonical?.id,
                canonicalIsIncoming: canonical?.isIncoming ?? false,
                canonicalReadAt: canonical?.readAt,
              );
            case ConversationNotificationContentKind.reaction:
              if (comparand is! BackgroundGroupReactionNotificationComparand ||
                  comparand.groupId != groupId) {
                return false;
              }
              final target = await widget.groupMessageRepository.getMessage(
                comparand.messageId,
              );
              if (target == null || target.groupId != groupId) return false;
              final canonical = await widget.reactionRepository
                  .getReactionForSenderIncludingRemoved(
                    messageId: comparand.messageId,
                    senderPeerId: comparand.senderPeerId,
                  );
              return isExactForegroundGroupReactionReadAcknowledgement(
                comparand: comparand,
                canonicalReactionId: canonical?.id,
                canonicalMessageId: canonical?.messageId,
                canonicalSenderPeerId: canonical?.senderPeerId,
                canonicalTimestamp: canonical?.timestamp,
                canonicalNotificationAcknowledgedAt:
                    canonical?.notificationAcknowledgedAt,
              );
          }
        },
      );
    } catch (error) {
      // A repository read failure is unknown, never proof that the user read
      // this exact event. Preserve the existing foreground fallback contract.
      emitFlowEvent(
        layer: 'FL',
        event: 'PUSH_FOREGROUND_READ_ACKNOWLEDGEMENT_CHECK_ERROR',
        details: {'errorType': error.runtimeType.toString()},
      );
      return false;
    }
  }

  Future<BackgroundPushNotificationFallback?>
  _resolveForegroundGroupReactionNotification(RemoteMessage message) async {
    final data = message.data;
    final action = data['action']?.toString().trim();
    final groupId = NotificationRouteTarget.groupIdFromRemoteMessageData(data);
    final actorPeerId =
        data['reactor_peer_id']?.toString().trim().isNotEmpty == true
        ? data['reactor_peer_id']!.toString().trim()
        : data['sender_id']?.toString().trim().isNotEmpty == true
        ? data['sender_id']!.toString().trim()
        : data['from']?.toString().trim();
    final targetMessageId =
        data['target_message_id']?.toString().trim().isNotEmpty == true
        ? data['target_message_id']!.toString().trim()
        : data['targetMessageId']?.toString().trim();
    final eventId = data['event_id']?.toString().trim().isNotEmpty == true
        ? data['event_id']!.toString().trim()
        : data['reaction_id']?.toString().trim();
    final keyEpoch = int.tryParse(data['keyEpoch']?.toString() ?? '');
    if (action != 'add' ||
        groupId == null ||
        actorPeerId == null ||
        actorPeerId.isEmpty ||
        targetMessageId == null ||
        targetMessageId.isEmpty ||
        eventId == null ||
        eventId.isEmpty ||
        keyEpoch == null) {
      return null;
    }

    final identity = await widget.repository.loadIdentity();
    final localPeerId = identity?.peerId.trim();
    final localTransportPeerId = widget.p2pService.currentState.peerId?.trim();
    if (localPeerId == null ||
        localPeerId.isEmpty ||
        localTransportPeerId == null ||
        localTransportPeerId.isEmpty ||
        localPeerId == actorPeerId) {
      return null;
    }
    final verifiedNomination = await verifyGroupReactionNotificationNomination(
      data: data,
      localTransportPeerId: localTransportPeerId,
      verifySignature:
          ({required publicKey, required signedPayload, required signature}) =>
              callVerifyPayload(
                bridge: widget.bridge,
                publicKey: publicKey,
                data: signedPayload,
                signature: signature,
              ),
    );
    if (verifiedNomination == null) return null;
    final group = await widget.groupRepository.getGroup(groupId);
    final target = await widget.groupMessageRepository.getMessage(
      targetMessageId,
    );
    final targetAttachments = await widget.mediaAttachmentRepository
        .getAttachmentsForMessage(targetMessageId, owner: MediaOwnerLane.group);
    final localMember = await widget.groupRepository.getMember(
      groupId,
      localPeerId,
    );
    final actor = await widget.groupRepository.getMember(groupId, actorPeerId);
    final key = await widget.groupRepository.getKeyByGeneration(
      groupId,
      keyEpoch,
    );
    final latestKey = await widget.groupRepository.getLatestKey(groupId);
    final currentReaction = await widget.reactionRepository
        .getReactionForSenderIncludingRemoved(
          messageId: targetMessageId,
          senderPeerId: actorPeerId,
        );
    final actorName = actor?.username?.trim();
    final localDevice = localMember?.findDeviceByTransportPeerId(
      localTransportPeerId,
      allowLegacyFallback: true,
    );
    final actorDevice = actor?.findDeviceByTransportPeerId(
      verifiedNomination.reactorTransportPeerId,
      allowLegacyFallback: true,
    );
    final displayEligibility = evaluateGroupReactionNotificationDisplayPolicy(
      GroupReactionNotificationDisplayPolicyInput(
        group: GroupNotificationDisplayPolicyInput(
          groupExists: group != null,
          hasCurrentLocalMembership: localMember != null,
          groupType: group?.type.toValue(),
          isMuted: group?.isMuted ?? false,
          isArchived: group?.isArchived ?? false,
          isDissolved: group?.isDissolved ?? false,
          hasDissolvedAt: group?.dissolvedAt != null,
          hasSelfRemovedAt: group?.selfRemovedAt != null,
        ),
        hasCurrentLocalAuthoredTarget:
            target != null &&
            target.groupId == groupId &&
            target.senderPeerId == localPeerId &&
            !target.isIncoming,
        targetRequiresRedaction:
            target?.privateMediaPolicy.requiresRedaction ?? true,
      ),
    );
    final routePayload = NotificationRouteTarget.group(
      groupId,
      messageId: targetMessageId,
    ).toPayload();
    if (group == null ||
        !displayEligibility.shouldDisplay ||
        localMember == null ||
        localDevice == null ||
        actor == null ||
        actorDevice == null ||
        actorDevice.deviceSigningPublicKey !=
            verifiedNomination.senderPublicKey ||
        actorName == null ||
        actorName.isEmpty ||
        target == null ||
        key == null ||
        latestKey == null ||
        !isCurrentGroupReactionKeyEpoch(
          requestedEpoch: keyEpoch,
          selectedEpoch: key.keyGeneration,
          latestEpoch: latestKey.keyGeneration,
        ) ||
        widget.groupConversationTracker.isViewing('group:$groupId') ||
        widget.groupConversationTracker.isViewing(routePayload)) {
      return null;
    }

    return resolveBackgroundPushNotification(
      message,
      groupReactionContext: GroupReactionNotificationContext(
        groupId: groupId,
        groupName: group.name,
        actorPeerId: actorPeerId,
        actorUsername: actorName,
        targetMessageId: targetMessageId,
        targetKind: groupReactionTargetKindForAttachments(targetAttachments),
        currentReactionId: currentReaction?.id,
        currentReactionTimestamp: currentReaction?.timestamp,
        currentReactionRemovedAt: currentReaction?.removedAt,
        currentReactionAcknowledged:
            currentReaction?.notificationAcknowledgedAt != null,
      ),
      locale: WidgetsBinding.instance.platformDispatcher.locale,
      decryptGroup:
          ({
            required groupId,
            required keyEpoch,
            required ciphertext,
            required nonce,
          }) => callGroupDecrypt(
            widget.bridge,
            key.encryptedKey,
            ciphertext,
            nonce,
          ),
    );
  }

  Future<bool> _allowsAccountRuntimeNetworkSideEffects(String operation) async {
    final identity = await widget.repository.loadIdentity();
    final allowed =
        await AccountMigrationRuntimeNetworkGate(
          authorityRepository:
              SecureKeyStoreAccountMigrationAuthorityRepository(
                secureKeyStore: widget.secureKeyStore,
              ),
        ).allowsAccountNetworkSideEffects(
          peerId: identity?.peerId,
          operation: operation,
        );
    if (!allowed) {
      emitFlowEvent(
        layer: 'FL',
        event: 'ACCOUNT_MIGRATION_RUNTIME_NETWORK_ACTION_BLOCKED',
        details: {'operation': operation},
      );
    }
    return allowed;
  }

  Future<void> _runAccountRuntimeNetworkVoidAction({
    required String operation,
    required Future<void> Function() action,
  }) async {
    if (!await _allowsAccountRuntimeNetworkSideEffects(operation)) {
      return;
    }
    await action();
  }

  Future<void> _handleAccountMigrationReceiverActivated() async {
    await activateAccountMigrationReceiverNotificationState(
      beginCanonicalNotificationRecovery:
          widget.groupMessageListener.beginCanonicalNotificationRecovery,
      invalidateIdentityCache: widget.repository.invalidateCache,
      rebuildRecipientProjection: () async {
        // The imported identity owns a different projection generation.
        // Establish it first (clearing prior-account rows), then rebuild every
        // recipient-owned group/reaction comparand before display resumes.
        await widget.repository.loadIdentity();
        await Future.wait([
          widget.contactRepository.mirrorAllDirectReactionContacts(),
          widget.messageRepository.mirrorAllDirectReactionAuthoredTargets(),
        ]);
        await widget.groupRepository.mirrorAllGroupReactionNotificationContexts(
          rethrowOnError: true,
        );
        await widget.groupMessageRepository
            .mirrorAllGroupReactionAuthoredTargets(rethrowOnError: true);
        await widget.reactionRepository
            .mirrorAllGroupReactionNotificationComparands(rethrowOnError: true);
      },
      endCanonicalNotificationRecovery:
          widget.groupMessageListener.endCanonicalNotificationRecovery,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 248 — bind the root ThemeMode to the live background preference so
    // selecting Signal switches the whole app (root ThemeData + every pushed
    // route/modal that falls back to it) to the warm light theme, while every
    // dark wallpaper keeps the dark root. The MaterialApp rebuilds only its
    // theme config on a background change; the navigatorKey + stable `home`
    // preserve Navigator/StartupRouter state across the flip (TC-248-03).
    return AppShellThemeBinding(
      controller: widget.appShellController,
      builder: (context, themeMode) => MaterialApp(
        title: 'mknoon',
        navigatorKey: MyApp.navigatorKey,
        scaffoldMessengerKey: MyApp.scaffoldMessengerKey,
        navigatorObservers: [directPrivateMediaRouteObserver],
        builder: (context, child) {
          final routedChild = DirectPrivateMediaRouteObserverScope(
            observer: directPrivateMediaRouteObserver,
            child: child ?? const SizedBox.shrink(),
          );
          return widget.debugE2EOverlayBuilder?.call(routedChild) ??
              routedChild;
        },
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        home: StartupRouter(
          repository: widget.repository,
          contactRepository: widget.contactRepository,
          contactRequestRepository: widget.contactRequestRepository,
          contactRequestListener: widget.contactRequestListener,
          issueWakeTokensForContacts: widget.issueWakeTokensForContacts,
          contactRequestPresentationGate: widget.contactRequestPresentationGate,
          messageRepository: widget.messageRepository,
          postRepository: widget.postRepository,
          mediaAttachmentRepository: widget.mediaAttachmentRepository,
          chatMessageListener: widget.chatMessageListener,
          bridge: widget.bridge,
          p2pService: widget.p2pService,
          transportMetrics: widget.transportMetrics,
          mediaFileManager: widget.mediaFileManager,
          secureKeyStore: widget.secureKeyStore,
          imageProcessor: widget.imageProcessor,
          audioRecorderService: widget.audioRecorderService,
          conversationTracker: widget.conversationTracker,
          reactionRepository: widget.reactionRepository,
          reactionListener: widget.reactionListener,
          groupPendingReactionRepository: widget.groupPendingReactionRepository,
          groupRepository: widget.groupRepository,
          groupMessageRepository: widget.groupMessageRepository,
          groupExitDiagnosticRepository: widget.groupExitDiagnosticRepository,
          groupPendingKeyRepairRepository:
              widget.groupPendingKeyRepairRepository,
          groupHistoryGapRepairRepository:
              widget.groupHistoryGapRepairRepository,
          groupReactionReplayOutboxRepository:
              widget.groupReactionReplayOutboxRepository,
          groupMessageListener: widget.groupMessageListener,
          groupMediaDownloadCoordinator: widget.groupMediaDownloadCoordinator,
          canRejoinForExitIntent: widget.canRejoinForExitIntent,
          processExitIntent: widget.processGroupExitIntent,
          groupExitIntentRecovery: widget.groupExitIntentRecovery,
          groupInviteListener: widget.groupInviteListener,
          waitForGroupMembershipUpdateIdle:
              widget.groupMembershipUpdateListener.waitForIdle,
          groupConversationTracker: widget.groupConversationTracker,
          introductionRepository: widget.introductionRepository,
          introReviewSeenRepository: widget.introReviewSeenRepository,
          introductionListener: widget.introductionListener,
          requestGroupKeyRepair: widget.requestGroupKeyRepair,
          shareIntentService: widget.shareIntentService,
          initialShareIntentCapture: _initialShareIntentCapture,
          ensureRuntimeServicesReady: _ensureRuntimeServicesReady,
          startP2PNodeOverride: widget.debugE2EStartP2PNodeOverride,
          // FDC-07: start LAN mDNS discovery early on the cold-start branch. Bound
          // to the concrete impl method (off the P2PService interface to avoid
          // churning the fakes); idempotent with startNode's own early seam.
          startEarlyLocalDiscovery: () =>
              widget.p2pService.startEarlyLocalDiscovery(),
          appShellController: widget.appShellController,
          pendingPostTargetStore: widget.pendingPostTargetStore,
          postsPrivacySettingsRepository: widget.postsPrivacySettingsRepository,
          feedClearedRepository: widget.feedClearedRepository,
          contactPresenceSnapshotRepository:
              widget.contactPresenceSnapshotRepository,
          nearbyLocationService: widget.nearbyLocationService,
          pushRegistrationCoordinator: widget.pushRegistrationCoordinator,
          accountMigrationRunTransfer: widget.accountMigrationRunTransfer,
          accountMigrationSizeGate: widget.accountMigrationSizeGate,
          accountMigrationStartReceiver: widget.accountMigrationStartReceiver,
          accountMigrationStopReceiver: widget.accountMigrationStopReceiver,
          accountMigrationReceiverEvents: widget.accountMigrationReceiverEvents,
          onAccountMigrationReceiverActivated:
              _handleAccountMigrationReceiverActivated,
          clearDeliveredNotifications:
              widget.notificationService.clearDeliveredNotifications,
          ingestStagedPushEnvelopes: () => _ingestStagedPushEnvelopes(
            source: 'startup_router_notification_tap',
          ),
          createNotificationRouteContext: _createNotificationOpenRouteContext,
          onNotificationRouteContext: _beginStartupNotificationRouteContext,
          onStartupHomeReady: _onStartupHomeReady,
          recoverDroppedPushes: _recoverDroppedPushes,
          hasPendingDroppedPushRecovery: _hasPendingDroppedPushRecovery,
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
